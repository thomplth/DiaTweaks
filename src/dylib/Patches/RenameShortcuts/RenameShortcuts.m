#import "StdPatch/StdPatch.h"

extern DPPatch DPRenameShortcuts;

static NSString *const DPRenameTitle = @"Rename…";
static const NSInteger DPRenameGroupTag = 0xD1A7002;
static const NSEventModifierFlags DPShortcutModifiers =
    NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl;

static NSMenu *DPTabsMenu(void) {
    return [NSApp.mainMenu itemWithTitle:@"Tabs"].submenu;
}

static NSInteger DPRenameIndex(NSMenu *menu) {
    for (NSInteger i = 0; i < menu.numberOfItems; i++)
        if ([[menu itemAtIndex:i].title isEqualToString:DPRenameTitle]) return i;
    return -1;
}

static BOOL DPPerformRename(NSMenu *menu) {
    NSInteger index = DPRenameIndex(menu);
    if (index < 0 || ![menu itemAtIndex:index].enabled) return NO;
    [menu performActionForItemAtIndex:index];
    return YES;
}

static NSView *DPSelectedTab(void) {
    return DPFindView(NSApp.keyWindow.contentView.superview, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaTabView) && !view.hiddenOrHasHiddenAncestor && [view.accessibilityValue boolValue];
    });
}

static BOOL DPIsGroup(NSView *view) {
    return DPIsKind(view, DPDiaTabGroupCell) || DPIsKind(view, DPDiaTabGroupView);
}

// Tabs aren't subviews of their group's view; it's drawn around them, so the group is the one the tab sits in.
static NSView *DPCurrentGroup(void) {
    NSView *tab = DPSelectedTab();
    if (!tab) return nil;
    NSPoint center = [tab convertPoint:NSMakePoint(NSMidX(tab.bounds), NSMidY(tab.bounds)) toView:nil];
    return DPFindView(tab.window.contentView.superview, ^BOOL(NSView *view) {
        return DPIsGroup(view) && NSPointInRect(center, [view convertRect:view.bounds toView:nil]);
    });
}

// The Tabs menu only lists the current tab's commands, Rename… among them, once Dia has filled it in for opening.
static BOOL DPRenameTab(void) {
    NSMenu *tabs = DPTabsMenu();
    if ([tabs.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [tabs.delegate menuNeedsUpdate:tabs];
    return DPPerformRename(tabs);
}

// A group's view builds its menu inside rightMouseDown: and pops it up there, so a synthesized right click with the
// pop-up swapped for Rename… is the only way to reach the command.
static BOOL DPRenamingGroup, DPRenamedGroup;

static BOOL DPMenu_popUp(NSMenu *self, SEL _cmd, NSMenuItem *item, NSPoint location, NSView *view) {
    if (!DPRenamingGroup) return DPCallOriginal(DPMenu_popUp, self, item, location, view);
    DPRenamedGroup = DPPerformRename(self);
    return DPRenamedGroup;
}

static BOOL DPRenameGroup(NSView *group) {
    if (!group) return NO;
    NSRect bounds = group.bounds;
    NSPoint header = NSMakePoint(NSMinX(bounds) + 12, group.isFlipped ? NSMinY(bounds) + 12 : NSMaxY(bounds) - 12);
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:[group convertPoint:header toView:nil]
                                   modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:group.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    DPRenamingGroup = YES;
    DPRenamedGroup = NO;
    [group rightMouseDown:click];
    DPRenamingGroup = NO;
    return DPRenamedGroup;
}

static void DPMenuBar_menuNeedsUpdate(id self, SEL _cmd, NSMenu *menu) {
    DPCallOriginal(DPMenuBar_menuNeedsUpdate, self, menu);
    if (menu != DPTabsMenu()) return;
    NSMenuItem *stale = [menu itemWithTag:DPRenameGroupTag];
    if (stale) [menu removeItem:stale];
    NSInteger index = DPRenameIndex(menu);
    if (index < 0) return;
    NSMenuItem *rename = [menu itemAtIndex:index];
    if (!DPRenameShortcuts.on) {
        if ([rename.keyEquivalent isEqualToString:@"/"]) rename.keyEquivalent = @"";
        return;
    }
    rename.keyEquivalent = @"/";
    rename.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    __weak NSView *group = DPCurrentGroup();
    if (!group) return;
    NSMenuItem *renameGroup = DPMenuItem(@"Rename Group…", ^{ DPRenameGroup(group); });
    renameGroup.tag = DPRenameGroupTag;
    renameGroup.keyEquivalent = @"/";
    renameGroup.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [menu insertItem:renameGroup atIndex:index + 1];
}

static BOOL DPIsRenameShortcut(NSEvent *event, NSEventModifierFlags modifiers) {
    return (event.modifierFlags & DPShortcutModifiers) == modifiers && [[event charactersByApplyingModifiers:0] isEqualToString:@"/"];
}

static NSEvent *DPHandleKeyDown(NSEvent *event) {
    if (!DPRenameShortcuts.on) return event;
    if (DPIsRenameShortcut(event, NSEventModifierFlagCommand)) return DPRenameTab() ? nil : event;
    if (DPIsRenameShortcut(event, NSEventModifierFlagCommand | NSEventModifierFlagShift)) return DPRenameGroup(DPCurrentGroup()) ? nil : event;
    return event;
}

static void DPInstallRenameShortcuts(void) {
    DPHook(DPDiaMenuBarManager, @selector(menuNeedsUpdate:), (IMP)DPMenuBar_menuNeedsUpdate);
    DPHookClass(NSMenu.class, @selector(popUpMenuPositioningItem:atLocation:inView:), (IMP)DPMenu_popUp);
    DPOnLaunch(^{ [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPHandleKeyDown(event); }]; });
}

DP_PATCH(DPRenameShortcuts) {
    .key = @"renameShortcuts",
    .order = 75,
    .title = @"Rename shortcuts",
    .detail = @"⌘/ renames the current tab and ⇧⌘/ renames the group it's in. The shortcuts are also listed in the Tabs menu.",
    .symbol = @"character.cursor.ibeam",
    .tint = @"systemBlueColor",
    .section = @"Sidebar and tab bar",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Rename-shortcuts.md",
    .classes = DPClasses(DPDiaTabView, DPDiaTabGroupCell, DPDiaTabGroupView, DPDiaMenuBarManager),
    .install = DPInstallRenameShortcuts,
};
