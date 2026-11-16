#import "StdPatch/StdPatch.h"

extern DPPatch DPCloseFromTabSwitcher;

static NSArray<NSString *> *DPSwitcherTabs(NSWindowController *switcher, NSString **focused) {
    id state = DPSwiftValue(DPSwiftValue(DPSwiftValue(switcher, @"viewModel"), @"stateSubject"), @"currentValue");
    if (focused) *focused = [DPSwiftValue(state, @"focusedItemID") description];
    return DPUUIDsIn([DPSwiftValue(state, @"items") description]);
}

static id DPScriptTab(NSString *tabID) {
    for (id window in [(id)NSApp.delegate valueForKey:@"appleScriptWindows"])
        for (id tab in [window valueForKey:@"appleScriptTabs"])
            if ([[tab valueForKey:@"tabId"] isEqual:tabID]) return tab;
    return nil;
}

static NSMenuItem *DPCycleItem(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.keyEquivalent isEqualToString:@"\t"] && item.keyEquivalentModifierMask == NSEventModifierFlagControl) return item;
        NSMenuItem *found = DPCycleItem(item.submenu);
        if (found) return found;
    }
    return nil;
}

static void DPStep(void) {
    [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagControl timestamp:NSProcessInfo.processInfo.systemUptime
                                  windowNumber:NSApp.keyWindow.windowNumber context:nil characters:@"\t" charactersIgnoringModifiers:@"\t" isARepeat:NO keyCode:48]
             atStart:NO];
}

static void DPFocus(NSString *tabID, NSString *lastSeen, int tries) {
    NSString *focused = nil;
    NSWindowController *switcher = DPOpenTabSwitcher();
    if (switcher) DPSwitcherTabs(switcher, &focused);
    if (!tries || [focused isEqual:tabID]) return;
    if (focused && ![focused isEqual:lastSeen]) DPStep();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        DPFocus(tabID, focused ?: lastSeen, tries - 1);
    });
}

static void DPReopenOnceClosed(NSString *closed, NSString *focus, int tries) {
    if (!tries || !(NSEvent.modifierFlags & NSEventModifierFlagControl)) return;
    if (DPScriptTab(closed)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPReopenOnceClosed(closed, focus, tries - 1); });
        return;
    }
    NSMenuItem *cycle = DPCycleItem(NSApp.mainMenu);
    if (cycle) [NSApp sendAction:cycle.action to:cycle.target from:cycle];
    DPFocus(focus, nil, 100);
}

static BOOL DPCloseFocusedTab(NSWindowController *switcher) {
    NSString *focused = nil;
    NSMutableArray<NSString *> *tabs = [DPSwitcherTabs(switcher, &focused) mutableCopy];
    NSUInteger index = [tabs indexOfObject:focused];
    id tab = DPScriptTab(focused);
    if (index == NSNotFound || !tab) return NO;
    [tab performSelector:@selector(close:) withObject:nil];
    [tabs removeObjectAtIndex:index];
    [switcher close];
    if (tabs.count > 1) DPReopenOnceClosed(focused, tabs[MIN(index, tabs.count - 1)], 50);
    return YES;
}

// The switcher picks the highlighted tab as soon as another modifier goes down, so it never sees ⌘.
static BOOL DPTakeEvent(NSEvent *event) {
    if (!DPCloseFromTabSwitcher.on || !(event.type == NSEventTypeKeyDown || event.type == NSEventTypeFlagsChanged)) return NO;
    if (!(event.modifierFlags & NSEventModifierFlagControl)) return NO;
    NSWindowController *switcher = DPOpenTabSwitcher();
    if (!switcher) return NO;
    if (event.type == NSEventTypeFlagsChanged) return event.keyCode == 54 || event.keyCode == 55;
    // ⇧ may still be down from cycling backward, and ⌘⇧W would close the window.
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption);
    // A layout with no Latin letters matches by the W key's position, others by the letter, so Dvorak's W works.
    NSString *typed = event.charactersIgnoringModifiers.lowercaseString;
    BOOL isW = (typed.length && [typed characterAtIndex:0] > 0x7f) ? event.keyCode == 13 : [typed isEqualToString:@"w"];
    return (mods == NSEventModifierFlagCommand || !mods) && isW && DPCloseFocusedTab(switcher);
}

static NSEvent *DPApplication_nextEvent(NSApplication *self, SEL _cmd, NSEventMask mask, NSDate *until, NSRunLoopMode mode, BOOL dequeue) {
    NSEvent *event;
    do event = DPCallOriginal(DPApplication_nextEvent, self, mask, until, mode, dequeue);
    while (dequeue && event && DPTakeEvent(event));
    return event;
}

static void DPInstallCloseFromTabSwitcher(void) {
    DPHookClass(NSApplication.class, @selector(nextEventMatchingMask:untilDate:inMode:dequeue:), (IMP)DPApplication_nextEvent);
}

DP_PATCH(DPCloseFromTabSwitcher) {
    .key = @"closeFromTabSwitcher",
    .defaultOn = YES,
    .order = 86,
    .title = @"Close Tabs from Tab Switcher",
    .detail = @"Press W or ⌘W while the tab switcher (⌃⇥) is open to close the highlighted tab and keep switching.",
    .symbol = @"xmark.square.fill",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaTabSwitcher),
    .install = DPInstallCloseFromTabSwitcher,
};
