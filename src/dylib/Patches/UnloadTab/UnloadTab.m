#import "Patches/UnloadTab/Recent.h"
#import "Patches/PinnedTabCloseButton/PinnedTabs.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import <objc/message.h>

enum { DPPageVisible = 2 };

static NSHashTable *DPPages;
static NSHashTable *DPDiscarded;
static NSHashTable *DPUnloadOnHide;

static id DPTabContent(NSView *tab) {
    NSDictionary *views = DPSwiftValue(tab, @"contentViews");
    if (views.count != 1) return nil;
    return DPSwiftValue(DPSwiftValue(views.allValues.firstObject, @"viewModel"), @"delegate");
}

static id DPPageAt(NSURL *url) {
    id found = nil;
    for (id page in DPPages) {
        if (![[page valueForKey:@"url"] isEqual:url]) continue;
        if (found) return nil;
        found = page;
    }
    return found;
}

// A tab with no page of its own would be taken for another tab's page at the same address.
static id DPPageOf(id content) {
    NSURL *url = DPSwiftValue(content, @"webContentURL");
    NSString *tabID = DPUUIDsIn([DPSwiftValue(content, @"tabID") description]).firstObject;
    NSMutableArray<NSString *> *sharing = [NSMutableArray array];
    for (id window in [(id)NSApp.delegate valueForKey:@"appleScriptWindows"])
        for (id tab in [window valueForKey:@"appleScriptTabs"]) {
            NSString *text = [tab respondsToSelector:@selector(URL)] ? DPText(DPMsg(tab, @selector(URL))) : nil;
            if (text && [[NSURL URLWithString:text] isEqual:url]) [sharing addObject:DPTabID(tab)];
        }
    return sharing.count == 1 && [sharing.firstObject isEqual:tabID] ? DPPageAt(url) : nil;
}

static BOOL DPTabOpen(NSView *tab) {
    NSString *state = [DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue") description];
    NSString *style = [state componentsSeparatedByString:@"selectionStyle: "].lastObject;
    return ![style hasPrefix:@"nil"] && ![style hasPrefix:@"none"] && ![style hasPrefix:@"above"] && ![style hasPrefix:@"below"];
}

static void DPPage_setVisibility(id self, SEL _cmd, NSInteger visibility) {
    if ([self respondsToSelector:@selector(visibility)] && [self respondsToSelector:@selector(discard)]) [DPPages addObject:self];
    DPCallOriginal(DPPage_setVisibility, self, visibility);
    if (visibility == DPPageVisible) {
        [DPDiscarded removeObject:self];
    } else if ([DPUnloadOnHide containsObject:self]) {
        [DPUnloadOnHide removeObject:self];
        dispatch_async(dispatch_get_main_queue(), ^{ [self performSelector:@selector(discard)]; });
    }
}

// Chromium may decline (a page playing audio), so only its finalize callback marks a page unloaded.
static void DPWebContent_finalizeDiscard(id self, SEL _cmd, id page, BOOL discarded) {
    DPCallOriginal(DPWebContent_finalizeDiscard, self, page, discarded);
    if (discarded && page) [DPDiscarded addObject:page];
}

static NSMenu *DPTab_menuForEvent(NSView *self, SEL _cmd, NSEvent *event) {
    NSMenu *menu = DPCallOriginal(DPTab_menuForEvent, self, event);
    id content = menu && DPUnloadTab.on ? DPTabContent(self) : nil;
    NSView *pane = content ? DPFindView(self, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabContentView); }) : nil;
    BOOL pinned = pane && DPIsOpenPinned(pane) && [pane respondsToSelector:NSSelectorFromString(@"closeButtonClicked")];
    id page = content && !pinned ? DPPageOf(content) : nil;
    if (!pinned && (!page || [DPDiscarded containsObject:page])) return menu;
    BOOL open = DPTabOpen(self);
    BOOL visible = page ? ((NSInteger (*)(id, SEL))objc_msgSend)(page, @selector(visibility)) == DPPageVisible : open;
    NSWindow *window = self.window;
    id before = visible && open ? DPTabBefore(window) : nil;
    NSMenuItem *item = DPMenuItem(@"Unload Tab", ^{
        if (before) DPForgetFrontTab(window);
        if (pinned) {
            if (before) DPFocusTab(before);
            DPMarkOwnClose();
            return (void)DPCloseKeepingTab(pane);
        }
        if (!before) return (void)[page performSelector:@selector(discard)];
        [DPUnloadOnHide addObject:page];
        DPFocusTab(before);
        // If switching doesn't take it off screen, it isn't unloaded later out of the blue.
        __weak id weakPage = page;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            id shown = weakPage;
            if (shown) [DPUnloadOnHide removeObject:shown];
        });
    });
    item.image = [NSImage imageWithSystemSymbolName:@"moon.zzz" accessibilityDescription:nil];
    // By name: CI's SDK predates macOS 27. 1 is NSMenuItemImageVisibilityVisible.
    if (@available(macOS 27, *)) [item setValue:@1 forKey:@"preferredImageVisibility"];
    item.enabled = pinned || !visible || before;
    NSInteger close = [menu indexOfItemWithTitle:@"Close"];
    [menu insertItem:item atIndex:close < 0 ? menu.numberOfItems : close];
    return menu;
}

static NSMenuItem *DPUnloadItem(NSView *tab) {
    NSPoint point = [tab convertPoint:NSMakePoint(NSMidX(tab.bounds), NSMidY(tab.bounds)) toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:tab.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    return [[tab menuForEvent:click] itemWithTitle:@"Unload Tab"];
}

static NSString *DPVerifyUnloadTab(DPPatch *patch) {
    NSArray<NSView *> *tabs = DPFindViews(DPDiaTabView);
    NSCountedSet<NSURL *> *urls = [NSCountedSet set];
    for (NSView *tab in tabs) {
        NSURL *url = DPSwiftValue(DPTabContent(tab), @"webContentURL");
        if (url) [urls addObject:url];
    }
    for (NSView *tab in tabs) {
        if (!tab.window || tab.isHiddenOrHasHiddenAncestor) continue;
        NSMenuItem *item = DPUnloadItem(tab);
        if (!patch->on) {
            if (item) return @"tab still offers Unload Tab";
            continue;
        }
        NSURL *url = DPSwiftValue(DPTabContent(tab), @"webContentURL");
        if (![url.scheme hasPrefix:@"http"] || [urls countForObject:url] > 1) continue;
        BOOL front = DPTabOpen(tab);
        id page = DPPageAt(url);
        if (!front && (!page || [DPDiscarded containsObject:page])) continue;
        if (!item) return front ? @"tab in front has no Unload Tab" : @"loaded tab has no Unload Tab";
        if (front && !item.enabled && [[DPScriptWindow(tab.window) valueForKey:@"appleScriptTabs"] count] > 1)
            return @"Unload Tab can't leave the tab in front";
    }
    return nil;
}

static void DPInstallUnloadTab(void) {
    DPPages = [NSHashTable weakObjectsHashTable];
    DPDiscarded = [NSHashTable weakObjectsHashTable];
    DPUnloadOnHide = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaWebContents, @selector(setVisibility:), (IMP)DPPage_setVisibility);
    DPHook(DPDiaTabView, @selector(menuForEvent:), (IMP)DPTab_menuForEvent);
    DPWatchFrontTabs();
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:finalizeDiscardRequest:), (IMP)DPWebContent_finalizeDiscard);
    });
}

DP_PATCH(DPUnloadTab) {
    .key = @"unloadTab",
    .order = 86,
    .section = @"Tabs",
    .title = @"Unload Tabs",
    .detail = @"Right-click a tab and choose Unload Tab to free its memory. It stays in the sidebar and loads again when you open it. Unloading the tab you’re on takes you back to the one you were on before. A pinned tab goes back to its pinned page.",
    .symbol = @"moon.zzz.fill",
    .tint = @"systemPinkColor",
    .classes = DPClasses(DPDiaWebContents, DPDiaTabView, DPDiaContentPane),
    .install = DPInstallUnloadTab,
    .verify = DPVerifyUnloadTab,
};
