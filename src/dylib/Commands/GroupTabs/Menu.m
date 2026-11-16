#import "GroupTabs.h"

static const NSInteger DPGroupMenuTag = 0xD1A7001, DPExpandMenuTag = 0xD1A7004, DPCollapseMenuTag = 0xD1A7005, DPUngroupMenuTag = 0xD1A7002,
                       DPUngroupAllMenuTag = 0xD1A7003, DPGroupSelectedMenuTag = 0xD1A7006;
static const NSInteger DPFollowerTags[] = {DPGroupSelectedMenuTag, DPExpandMenuTag, DPCollapseMenuTag, DPUngroupMenuTag, DPUngroupAllMenuTag};
static const NSInteger DPFollowerCount = sizeof(DPFollowerTags) / sizeof(DPFollowerTags[0]);
static BOOL DPInserting;

static BOOL DPIsFollowerTag(NSInteger tag) {
    for (NSInteger i = 0; i < DPFollowerCount; i++)
        if (DPFollowerTags[i] == tag) return YES;
    return NO;
}

static BOOL DPHasFollower(NSMenu *menu) {
    for (NSInteger i = 0; i < DPFollowerCount; i++)
        if ([menu itemWithTag:DPFollowerTags[i]]) return YES;
    return NO;
}

static BOOL DPIsNewGroupTitle(NSString *title) {
    if ([title isEqualToString:@"New Group with Tab"] || [title isEqualToString:@"New Group with Tabs"]) return YES;
    return [title hasPrefix:@"New Group with "] && ([title hasSuffix:@" Tab"] || [title hasSuffix:@" Tabs"]);
}

static NSMenuItem *DPCommandItem(NSString *title, NSInteger tag, NSString *symbol, void (^action)(void)) {
    NSMenuItem *item = DPMenuItem(title, action);
    item.tag = tag;
    item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    item.hidden = !DPGroupTabs.on;
    return item;
}

static NSMenuItem *DPGroupMenuItem(void) {
    return DPCommandItem(@"Group Tabs by Domain", DPGroupMenuTag, @"rectangle.3.group", ^{ DPGroupTabsOnce(); });
}

static NSMenuItem *DPFollowerItem(NSInteger tag) {
    if (tag == DPGroupSelectedMenuTag)
        return DPCommandItem(@"Group Selected Tabs by Domain", tag, @"rectangle.3.group", ^{ DPGroupSelectedTabsOnce(); });
    if (tag == DPExpandMenuTag)
        return DPCommandItem(@"Expand All Tab Groups", tag, @"rectangle.expand.vertical", ^{ DPSetAllGroupsCollapsed(NO); });
    if (tag == DPCollapseMenuTag)
        return DPCommandItem(@"Collapse All Tab Groups", tag, @"rectangle.compress.vertical", ^{ DPSetAllGroupsCollapsed(YES); });
    if (tag == DPUngroupMenuTag) return DPCommandItem(@"Ungroup This Domain", tag, @"rectangle.stack.badge.minus", ^{ DPUngroupDomain(); });
    return DPCommandItem(@"Ungroup All Domains", tag, @"square.stack.3d.down.right", ^{ DPUngroupAllDomains(); });
}

static NSInteger DPFollowersInPlace(NSMenu *menu, NSInteger index) {
    NSInteger n = 0;
    while (n < DPFollowerCount && index + 1 + n < menu.numberOfItems && [menu itemAtIndex:index + 1 + n].tag == DPFollowerTags[n]) n++;
    return n;
}

// Dia removes the tagged copies it added, so keep the last item with a tag: dropping Dia's copy crashes Dia.
static void DPPlaceFollowerItems(NSMenu *menu) {
    if (DPInserting || !menu) return;
    NSInteger group = NSNotFound, count = 0;
    NSMutableDictionary<NSNumber *, NSMenuItem *> *kept = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < menu.numberOfItems; i++) {
        NSMenuItem *item = [menu itemAtIndex:i];
        if (item.tag == DPGroupMenuTag && group == NSNotFound) group = i;
        if (!DPIsFollowerTag(item.tag)) continue;
        kept[@(item.tag)] = item;
        count++;
    }
    if (group == NSNotFound || (count == DPFollowerCount && DPFollowersInPlace(menu, group) == DPFollowerCount)) return;
    DPInserting = YES;
    for (NSInteger i = menu.numberOfItems - 1; i >= 0; i--) {
        if (!DPIsFollowerTag([menu itemAtIndex:i].tag)) continue;
        [menu removeItemAtIndex:i];
        if (i < group) group--;
    }
    for (NSInteger n = 0; n < DPFollowerCount; n++)
        [menu insertItem:kept[@(DPFollowerTags[n])] ?: DPFollowerItem(DPFollowerTags[n]) atIndex:group + 1 + n];
    DPInserting = NO;
}

static void DPPlaceGroupItem(NSMenu *menu) {
    if (DPInserting || !menu) return;
    NSInteger anchor = NSNotFound, visible = NSNotFound, existing = NSNotFound;
    for (NSInteger i = 0; i < menu.numberOfItems; i++) {
        NSMenuItem *item = [menu itemAtIndex:i];
        if (item.tag == DPGroupMenuTag) existing = i;
        else if (DPIsNewGroupTitle(item.title)) {
            if (!item.hidden && visible == NSNotFound) visible = i;
            if (anchor == NSNotFound) anchor = i;
        }
    }
    if (visible != NSNotFound) anchor = visible;
    if (anchor == NSNotFound) return;
    DPInserting = YES;
    for (NSInteger i = menu.numberOfItems - 1; i >= 0; i--)
        if ([menu itemAtIndex:i].tag == DPGroupMenuTag && i != existing) {
            [menu removeItemAtIndex:i];
            if (i < existing) existing--;
            if (i < anchor) anchor--;
        }
    DPInserting = NO;
    NSInteger end = menu.numberOfItems;
    for (NSInteger i = anchor + 1; i < menu.numberOfItems; i++)
        if ([menu itemAtIndex:i].isSeparatorItem) { end = i; break; }
    if (existing != NSNotFound && existing == end - 1 - DPFollowersInPlace(menu, existing)) return DPPlaceFollowerItems(menu);
    DPInserting = YES;
    NSMenuItem *item = existing != NSNotFound ? [menu itemAtIndex:existing] : DPGroupMenuItem();
    if (existing != NSNotFound) {
        [menu removeItemAtIndex:existing];
        if (existing < end) end--;
    }
    [menu insertItem:item atIndex:end];
    DPInserting = NO;
    DPPlaceFollowerItems(menu);
}

static void DPInstallMenuBarItem(void) {
    NSMenu *tabMenu = nil, *commandMenu = nil, *windowMenu = nil, *fileMenu = nil;
    for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
        NSString *title = top.title ?: @"";
        if ([title isEqualToString:@"Tab"] || [title isEqualToString:@"Tabs"]) tabMenu = top.submenu;
        if ([title isEqualToString:@"Window"]) windowMenu = top.submenu;
        if ([title isEqualToString:@"File"]) fileMenu = top.submenu;
        for (NSMenuItem *item in top.submenu.itemArray)
            if (DPIsNewGroupTitle(item.title) || [item.title isEqualToString:@"New Tab"] || [item.title isEqualToString:@"Close Tab"]
                || [item.title isEqualToString:@"Select Next Tab"] || [item.title isEqualToString:@"Reopen Closed Tab"])
                commandMenu = top.submenu;
    }
    NSMenu *menu = tabMenu ?: commandMenu ?: windowMenu ?: fileMenu;
    if (!menu) return;
    if ([menu itemWithTag:DPGroupMenuTag]) return DPPlaceFollowerItems(menu);
    for (NSMenuItem *item in menu.itemArray)
        if (DPIsNewGroupTitle(item.title)) return DPPlaceGroupItem(menu);
    NSInteger index = menu.numberOfItems;
    for (NSInteger i = 0; i < menu.numberOfItems; i++) {
        NSString *title = [menu itemAtIndex:i].title;
        if (DPIsNewGroupTitle(title) || [title isEqualToString:@"New Tab"]) index = i + 1;
    }
    DPInserting = YES;
    [menu insertItem:DPGroupMenuItem() atIndex:MIN(index, menu.numberOfItems)];
    DPInserting = NO;
    DPPlaceFollowerItems(menu);
}

static void DPMenuAdded(NSMenu *menu, NSMenuItem *item) {
    if (!DPInserting && (DPIsNewGroupTitle(item.title) || [menu itemWithTag:DPGroupMenuTag] || DPHasFollower(menu))) DPPlaceGroupItem(menu);
}

static void DPMenu_addItem(NSMenu *self, SEL _cmd, NSMenuItem *item) {
    DPCallOriginal(DPMenu_addItem, self, item);
    DPMenuAdded(self, item);
}

static void DPMenu_insertItem(NSMenu *self, SEL _cmd, NSMenuItem *item, NSInteger index) {
    DPCallOriginal(DPMenu_insertItem, self, item, index);
    DPMenuAdded(self, item);
}

void DPInstallGroupMenus(void) {
    DPHookClass(NSMenu.class, @selector(addItem:), (IMP)DPMenu_addItem);
    DPHookClass(NSMenu.class, @selector(insertItem:atIndex:), (IMP)DPMenu_insertItem);
    DPOnLaunch(^{ DPInstallMenuBarItem(); });
}

static void DPApplyGroupTabs(DPPatch *patch) {
    for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
        [top.submenu itemWithTag:DPGroupMenuTag].hidden = !patch->on;
        for (NSInteger i = 0; i < DPFollowerCount; i++) [top.submenu itemWithTag:DPFollowerTags[i]].hidden = !patch->on;
    }
}

static NSString *DPVerifyGroupTabs(DPPatch *patch) {
    NSMenuItem *item = nil;
    for (NSMenuItem *top in NSApp.mainMenu.itemArray) item = item ?: [top.submenu itemWithTag:DPGroupMenuTag];
    if (!item) return @"Group Tabs by Domain isn't in the menu bar";
    if (item.hidden == patch->on) return patch->on ? @"Group Tabs by Domain is hidden" : @"Group Tabs by Domain still shows";
    for (NSInteger i = 0; i < DPFollowerCount; i++)
        if (![item.menu itemWithTag:DPFollowerTags[i]]) return @"a group command is missing from the menu bar";
    if (patch->on && !DPCanReadSelection(DPCommandBrowser())) return @"can't read which tabs are selected";
    return nil;
}

DP_PATCH(DPGroupTabs) {
    .key = @"groupTabsByDomain",
    .order = 86,
    .defaultOn = YES,
    .title = @"Group Tabs by Domain",
    .detail = @"Groups a window’s tabs by site, from the Tabs menu, a tab’s right-click menu or a shortcut.",
    .symbol = @"rectangle.3.group.fill",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .install = DPInstallGroupTabs,
    .apply = DPApplyGroupTabs,
    .verify = DPVerifyGroupTabs,
    .shortcut = @"groupTabsByDomainShortcut",
    .defaultShortcut = DPDefaultGroupTabsShortcut,
};
