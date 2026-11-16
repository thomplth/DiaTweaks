#import "StdPatch/StdPatch.h"

extern DPPatch DPPinTabShortcut;

static NSDictionary *DPDefaultPinShortcut(void) { return @{ @"keyCode" : @2, @"modifiers" : @(NSEventModifierFlagCommand), @"key" : @"D" }; }

static id DPTabState(NSView *tab) { return DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue"); }

// selectionStyle is nil on an unselected pinned tab, "none" on other unselected tabs, above/below beside the selection.
static BOOL DPTabSelected(NSView *tab) {
    NSString *style = [[DPSwiftValue(DPTabState(tab), @"selectionStyle") description] lowercaseString];
    return style && ![style containsString:@"none"] && ![style containsString:@"above"] && ![style containsString:@"below"];
}

// The list keeps hidden cells it isn't showing, but a collapsed sidebar or an auto-hidden tab strip still counts.
static BOOL DPTabShown(NSView *tab) {
    for (NSView *view = tab; view && ![view isKindOfClass:NSCollectionView.class] && !DPIsKind(view, DPDiaTabStrip); view = view.superview)
        if (view.hidden) return NO;
    return YES;
}

static NSMenu *DPTabMenu(NSView *tab) {
    NSPoint point = [tab convertPoint:NSMakePoint(NSMidX(tab.bounds), NSMidY(tab.bounds)) toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:tab.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    return [tab menuForEvent:click];
}

static NSMenuItem *DPShownItem(NSMenuItem *item) { return item && !item.hidden && item.enabled ? item : nil; }

// Pin as Tab and Unpin are at the top of the menu, so an item of the same name in a submenu isn't taken for them.
static NSMenuItem *DPPinItem(NSMenu *menu) {
    return DPShownItem([menu itemWithTitle:@"Pin as Tab"]) ?: DPShownItem([menu itemWithTitle:@"Unpin"]);
}

static NSMenuItem *DPFindShownItem(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.hidden) continue;
        NSMenuItem *found = [item.title isEqualToString:title] ? DPShownItem(item) : DPFindShownItem(item.submenu, title);
        if (found) return found;
    }
    return nil;
}

// An item only points to its menu weakly, so whoever finds it holds the menu with DPHeld until it has run.
#define DPHeld __attribute__((objc_precise_lifetime))
static void DPRunItem(NSMenuItem *item) { [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]]; }

// The page a tab shows, or nil when it shows more than one.
static NSURL *DPTabURL(NSView *tab) {
    NSDictionary *views = DPSwiftValue(tab, @"contentViews");
    if (views.count != 1) return nil;
    return DPSwiftValue(DPSwiftValue(DPSwiftValue(views.allValues.firstObject, @"viewModel"), @"delegate"), @"webContentURL");
}

static NSArray<NSView *> *DPShownTabs(NSWindow *window) {
    NSMutableArray<NSView *> *tabs = [NSMutableArray array];
    for (NSView *tab in DPFindViews(DPDiaTabView))
        if ((!window || tab.window == window) && DPTabShown(tab)) [tabs addObject:tab];
    return tabs;
}

static NSView *DPSelectedTab(NSWindow *window) {
    for (NSView *tab in DPShownTabs(window))
        if (DPTabSelected(tab)) return tab;
    return nil;
}

// Dia keeps the URL a tab was first pinned at through Unpin, and Pin as Tab doesn't replace it, so a tab pinned again
// went back to that page when closed. Once the tab is among the pinned ones, the page it's on becomes its pinned URL.
// Only while it's still on the page it was pinned at, so a tab selected meanwhile keeps its own.
static void DPPinCurrentURL(NSWindow *window, NSURL *url, int tries) {
    NSView *tab = DPSelectedTab(window);
    DPHeld NSMenu *menu = tab && [DPTabURL(tab) isEqual:url] ? DPTabMenu(tab) : nil;
    if (DPShownItem([menu itemWithTitle:@"Unpin"])) {
        NSMenuItem *replace = DPFindShownItem(menu, @"Replace Pinned URL with Current");
        if (replace) DPRunItem(replace);
    } else if (tries > 0) {
        __weak NSWindow *weakWindow = window;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), ^{
            if (weakWindow) DPPinCurrentURL(weakWindow, url, tries - 1);
        });
    }
}

static void DPInstallPinTabShortcut(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (!DPPinTabShortcut.on || !event.window || !DPShortcutMatches(event, &DPPinTabShortcut)) return event;
        NSView *tab = DPSelectedTab(event.window);
        DPHeld NSMenu *menu = tab ? DPTabMenu(tab) : nil;
        NSMenuItem *item = DPPinItem(menu);
        if (!item) return event;
        if (event.isARepeat) return nil;
        BOOL pinning = [item.title isEqualToString:@"Pin as Tab"];
        NSURL *url = DPTabURL(tab);
        DPRunItem(item);
        if (pinning && url) DPPinCurrentURL(event.window, url, 20);
        return nil;
    }];
}

static NSString *DPVerifyPinTabShortcut(DPPatch *patch) {
    NSArray<NSView *> *tabs = DPShownTabs(nil);
    if (!patch->on || !tabs.count) return nil;
    for (NSView *tab in tabs)
        if (DPPinItem(DPTabMenu(tab))) return nil;
    return @"no tab's menu has Pin as Tab or Unpin";
}

DP_PATCH(DPPinTabShortcut) {
    .key = @"pinTabShortcut",
    .order = 86,
    .title = @"Pin Tab Shortcut",
    .detail = @"Press a shortcut, ⌘D unless you set another, to move the tab you’re on to the bottom of your pinned tabs, as in Arc. Press it on a pinned tab to unpin it.",
    .symbol = @"pin.fill",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaTabView),
    .shortcut = @"pinTabShortcutKey",
    .defaultShortcut = DPDefaultPinShortcut,
    .install = DPInstallPinTabShortcut,
    .verify = DPVerifyPinTabShortcut,
};
