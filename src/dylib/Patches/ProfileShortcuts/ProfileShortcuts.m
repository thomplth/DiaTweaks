#import "StdPatch/StdPatch.h"

extern DPPatch DPProfileShortcuts;
static char DPSwappedKey;

static BOOL DPIsDigit(NSString *text) {
    return text.length == 1 && [text characterAtIndex:0] >= '1' && [text characterAtIndex:0] <= '9';
}

static BOOL DPIsDigitShortcut(NSMenuItem *item, NSEventModifierFlags mods) {
    return DPIsDigit(item.keyEquivalent) && item.keyEquivalentModifierMask == mods;
}

static NSMenuItem *DPFindItem(NSMenu *menu, BOOL (^match)(NSMenuItem *item)) {
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *found = match(item) ? item : item.submenu ? DPFindItem(item.submenu, match) : nil;
        if (found) return found;
    }
    return nil;
}

static void DPSwapItem(NSMenuItem *item) {
    NSArray<NSNumber *> *swapped = DPGet(item, &DPSwappedKey);
    BOOL ours = swapped && item.keyEquivalentModifierMask == swapped[1].unsignedIntegerValue;
    if (!DPProfileShortcuts.on) {
        if (ours) item.keyEquivalentModifierMask = swapped[0].unsignedIntegerValue;
        if (swapped) DPSet(item, &DPSwappedKey, nil);
        return;
    }
    if (ours) return;
    NSEventModifierFlags to;
    if (DPIsDigitShortcut(item, NSEventModifierFlagCommand)) to = NSEventModifierFlagControl;
    else if (DPIsDigitShortcut(item, NSEventModifierFlagControl)) to = NSEventModifierFlagCommand;
    else return;
    DPSet(item, &DPSwappedKey, @[ @(item.keyEquivalentModifierMask), @(to) ]);
    item.keyEquivalentModifierMask = to;
}

static BOOL DPInMainMenu(NSMenu *menu) {
    while (menu.supermenu) menu = menu.supermenu;
    return menu == NSApp.mainMenu;
}

static void DPApplyProfileShortcuts(DPPatch *patch) {
    DPFindItem(NSApp.mainMenu, ^BOOL(NSMenuItem *item) {
        DPSwapItem(item);
        return NO;
    });
}

// AZERTY types digits only with ⇧, so ⌘⇧& is the menu's ⌘1; Arabic and Thai keys with no digit use the ⌘ layer's.
static NSString *DPCommandDigit(NSEvent *event) {
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
    BOOL shifted = mods == (NSEventModifierFlagCommand | NSEventModifierFlagShift) && !(event.modifierFlags & NSEventModifierFlagNumericPad);
    if (mods != NSEventModifierFlagCommand && !shifted) return nil;
    NSString *typed = event.charactersIgnoringModifiers;
    if (!shifted && !DPIsDigit(typed)) typed = event.characters;
    return DPIsDigit(typed) ? typed : nil;
}

static NSMenuItem *DPProfileItem(NSString *digit) {
    return DPFindItem(NSApp.mainMenu, ^BOOL(NSMenuItem *candidate) {
        return DPGet(candidate, &DPSwappedKey) && DPIsDigitShortcut(candidate, NSEventModifierFlagCommand) && [candidate.keyEquivalent isEqualToString:digit];
    });
}

static void DPApplication_sendEvent(NSApplication *self, SEL _cmd, NSEvent *event) {
    // A recording field must see the key first.
    NSString *digit = DPProfileShortcuts.on && event.type == NSEventTypeKeyDown && !DPShortcutRecording() ? DPCommandDigit(event) : nil;
    NSMenuItem *item = digit ? DPProfileItem(digit) : nil;
    // Performing an item doesn't validate it, so update first; update can rebuild the items, so look it up again.
    [item.menu update];
    if (item) item = DPProfileItem(digit);
    if (!item.enabled || item.hiddenOrHasHiddenAncestor || !item.action) return DPCallOriginal(DPApplication_sendEvent, self, event);
    [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]];
}

static void DPInstallProfileShortcuts(void) {
    DPHookClass(NSApplication.class, @selector(sendEvent:), (IMP)DPApplication_sendEvent);
    DPOnLaunch(^{
        DPApplyProfileShortcuts(&DPProfileShortcuts);
        __block BOOL pending = NO;
        void (^changed)(NSNotification *) = ^(NSNotification *note) {
            if (!DPProfileShortcuts.on) return;
            // Swap a rebuilt ⌃ item now: AppKit can match the next key before the re-apply below. A ⌘ item must wait for it.
            NSMenu *menu = note.object;
            NSNumber *index = note.userInfo[@"NSMenuItemIndex"];
            NSMenuItem *item = [menu isKindOfClass:NSMenu.class] && index && index.integerValue >= 0 && index.integerValue < menu.numberOfItems ? [menu itemAtIndex:index.integerValue] : nil;
            if (item && DPIsDigitShortcut(item, NSEventModifierFlagControl) && DPInMainMenu(menu)) DPSwapItem(item);
            if (pending) return;
            pending = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                pending = NO;
                DPApplyProfileShortcuts(&DPProfileShortcuts);
            });
        };
        for (NSNotificationName name in @[ NSMenuDidAddItemNotification, NSMenuDidChangeItemNotification ])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:changed];
    });
}

static NSString *DPVerifyProfileShortcuts(DPPatch *patch) {
    NSMenuItem *item = DPFindItem(NSApp.mainMenu, ^BOOL(NSMenuItem *candidate) { return [candidate.title isEqualToString:@"Go to Sidebar Item 1"]; });
    if (item && !DPIsDigitShortcut(item, patch->on ? NSEventModifierFlagControl : NSEventModifierFlagCommand))
        return patch->on ? @"the sidebar items keep ⌘ and a number" : @"the sidebar items didn't get ⌘ back";
    if (patch->on && !DPFindItem(NSApp.mainMenu, ^BOOL(NSMenuItem *candidate) { return DPIsDigitShortcut(candidate, NSEventModifierFlagCommand) && ![candidate.title hasPrefix:@"Go to Sidebar Item"]; }))
        return @"no profile has ⌘ and a number";
    return nil;
}

DP_PATCH(DPProfileShortcuts) {
    .key = @"profileShortcuts",
    .order = 79,
    .title = @"Switch Profiles with ⌘1–9",
    .detail = @"Press ⌘ and a number to switch to that profile, like Arc's spaces. The sidebar's items move to ⌃ and a number.",
    .symbol = @"command",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .install = DPInstallProfileShortcuts,
    .apply = DPApplyProfileShortcuts,
    .verify = DPVerifyProfileShortcuts,
};
