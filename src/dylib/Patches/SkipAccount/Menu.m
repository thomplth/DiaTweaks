#import "Startup.h"

static BOOL DPIsSignIn(NSMenuItem *item) {
    return item.menu && item.menu == NSApp.mainMenu.itemArray.firstObject.submenu
        && [@[ @"Sign In…", @"Sign In..." ] containsObject:item.title];
}

static BOOL DPIsLocalAction(NSMenuItem *item) {
    if (!item.menu) return NO;
    NSMenu *bar = NSApp.mainMenu;
    if (item.menu == bar.itemArray.firstObject.submenu)
        return [@[ @"Settings…", @"Settings...", @"Set as Default Browser", @"Import from Another Browser…" ] containsObject:item.title];
    return item.menu && item.menu == [bar itemWithTitle:@"File"].submenu
        && [@[ @"New Window", @"New Incognito Window" ] containsObject:item.title];
}

static void DPItem_setEnabled(NSMenuItem *self, SEL _cmd, BOOL enabled) {
    DPCallOriginal(DPItem_setEnabled, self, enabled || DPIsLocalAction(self));
}

static void DPUpdateMenu(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        if (DPIsSignIn(item)) item.hidden = YES;
        if (DPIsLocalAction(item)) item.enabled = YES;
    }
}

static void DPItem_setHidden(NSMenuItem *self, SEL _cmd, BOOL hidden) {
    DPCallOriginal(DPItem_setHidden, self, hidden || DPIsSignIn(self));
}

static void DPMenu_addItem(NSMenu *self, SEL _cmd, NSMenuItem *item) {
    DPCallOriginal(DPMenu_addItem, self, item);
    if (DPIsSignIn(item)) item.hidden = YES;
    if (DPIsLocalAction(item)) item.enabled = YES;
}

static void DPMenu_insertItem(NSMenu *self, SEL _cmd, NSMenuItem *item, NSInteger index) {
    DPCallOriginal(DPMenu_insertItem, self, item, index);
    if (DPIsSignIn(item)) item.hidden = YES;
    if (DPIsLocalAction(item)) item.enabled = YES;
}

static void DPMenu_update(NSMenu *self, SEL _cmd) {
    DPCallOriginal(DPMenu_update, self);
    DPUpdateMenu(self);
}

void DPSkipAccountMenus(void) {
    DPHookClass(NSMenuItem.class, @selector(setHidden:), (IMP)DPItem_setHidden);
    DPHookClass(NSMenuItem.class, @selector(setEnabled:), (IMP)DPItem_setEnabled);
    DPHookClass(NSMenu.class, @selector(addItem:), (IMP)DPMenu_addItem);
    DPHookClass(NSMenu.class, @selector(insertItem:atIndex:), (IMP)DPMenu_insertItem);
    DPHookClass(NSMenu.class, @selector(update), (IMP)DPMenu_update);
    DPOnLaunch(^{ DPUpdateMenu(NSApp.mainMenu.itemArray.firstObject.submenu); });
}
