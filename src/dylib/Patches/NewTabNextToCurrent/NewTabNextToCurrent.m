#import "StdPatch/StdPatch.h"
#import "Patches/CommandBar/Tabs.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import <objc/message.h>

extern DPPatch DPNewTabNextToCurrent;
static char DPStateKey, DPRelayKey;

@interface DPNextTabs : NSObject
@property(strong) NSSet<NSString *> *knownIDs;
@property(copy) NSString *lastFrontID;
@property BOOL moving;  // The front tab changes while a new tab moves; DPNote must ignore that.
@property(strong) NSMutableDictionary<NSString *, NSString *> *originOf;
@end

@implementation DPNextTabs
@end

static NSArray<NSString *> *DPTabIDs(NSWindow *window) {
    return [[DPScriptWindow(window) valueForKey:@"appleScriptTabs"] valueForKey:@"tabId"] ?: @[];
}

static BOOL DPIsBlank(NSWindow *window, NSString *tabID) {
    NSString *url = [[DPScriptTab(window, tabID) valueForKey:@"URL"] description];
    return !url.length || !([url hasPrefix:@"http:"] || [url hasPrefix:@"https:"] || [url hasPrefix:@"file:"]);
}

static DPNextTabs *DPStateFor(NSWindow *window) {
    DPNextTabs *state = DPGet(window, &DPStateKey);
    NSString *active = DPActiveTabID(window);
    if (state || !active) return state;
    state = [DPNextTabs new];
    state.originOf = [NSMutableDictionary dictionary];
    state.knownIDs = [NSSet setWithArray:DPTabIDs(window)];
    state.lastFrontID = active;
    DPSet(window, &DPStateKey, state);
    return state;
}

static void DPAskGroups(id delegate, id browser, void (^done)(NSArray *groups)) {
    void (*ask)(id, SEL, id, void (^)(NSArray *)) = (void *)objc_msgSend;
    if (![delegate respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)]) return done(@[]);
    ask(delegate, @selector(browser:getAllTabGroupsWithCompletion:), browser, ^(NSArray *groups) {
        dispatch_async(dispatch_get_main_queue(), ^{ done([groups isKindOfClass:NSArray.class] ? groups : @[]); });
    });
}

static NSInteger DPTabsLeftInFolder(NSArray *groups, long long session) {
    for (id info in groups) {
        NSArray *raw = [info respondsToSelector:@selector(tabSessionIds)] ? DPMsg(info, @selector(tabSessionIds)) : nil;
        if (![raw isKindOfClass:NSArray.class]) continue;
        for (NSUInteger i = 0; i < raw.count; i++)
            if (DPLongID(raw[i]) == session) return (NSInteger)(raw.count - 1 - i);
    }
    return 0;
}

static NSSet<NSNumber *> *DPSessions(id browser) {
    NSMutableSet *sessions = [NSMutableSet set];
    for (id contents in DPTrackedContents(browser)) {
        long long sid = DPSessionOf(contents);
        if (sid > 0) [sessions addObject:@(sid)];
    }
    return sessions;
}

static void DPDoneMoving(NSWindow *window, DPNextTabs *state) {
    state.moving = NO;
    state.knownIDs = [NSSet setWithArray:DPTabIDs(window)];
    state.lastFrontID = DPActiveTabID(window);
}

static void DPPlace(NSWindow *window, NSString *newID, NSString *fromID, long long fromSession, NSSet<NSNumber *> *before, DPNextTabs *state, int tries) {
    id browser = DPBrowserOfWindow(window), delegate = DPGroupingDelegate(browser);
    if (!DPNewTabNextToCurrent.on || !DPScriptTab(window, newID) || !delegate) return DPDoneMoving(window, state);
    NSMutableSet<NSNumber *> *gained = [DPSessions(browser) mutableCopy];
    [gained minusSet:before];
    if (gained.count != 1) {
        if (tries <= 0) return DPDoneMoving(window, state);
        return (void)dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            DPPlace(window, newID, fromID, fromSession, before, state, tries - 1);
        });
    }
    NSNumber *sid = gained.anyObject;
    NSMutableArray<NSString *> *others = [DPTabIDs(window) mutableCopy];
    NSUInteger newIndex = [others indexOfObject:newID];
    [others removeObject:newID];
    NSUInteger fromIndex = [others indexOfObject:fromID];
    if (newIndex == NSNotFound || fromIndex == NSNotFound || newIndex == fromIndex + 1) return DPDoneMoving(window, state);

    // DPMoveTab fails when the tab closes mid-move; that must clear `moving` too.
    void (^finish)(void) = ^{ DPDoneMoving(window, state); };
    // Nothing reports where the unpinned tabs start, but a tab moved to 0 lands there.
    DPMoveTab(delegate, browser, sid, 0, ^{
        NSUInteger start = [DPTabIDs(window) indexOfObject:newID];
        if (start == NSNotFound || fromIndex < start) return finish();
        DPAskGroups(delegate, browser, ^(NSArray *groups) {
            NSInteger to = (NSInteger)(fromIndex - start) + 1 + (fromSession > 0 ? DPTabsLeftInFolder(groups, fromSession) : 0);
            DPMoveTab(delegate, browser, sid, to, finish, finish);
        });
    }, finish);
}

static BOOL DPOpenNextToCurrent(NSWindow *window) {
    id scripted = DPScriptWindow(window), browser = DPBrowserOfWindow(window);
    NSString *from = DPActiveTabID(window);
    Class tabClass = NSClassFromString(@"DiaAppleScriptTab");
    SEL make = NSSelectorFromString(@"newScriptingObjectOfClass:forValueForKey:withContentsValue:properties:");
    if (!DPNewTabNextToCurrent.on || !from || !browser || !DPGroupingDelegate(browser) || !tabClass || ![scripted respondsToSelector:make]) return NO;
    if (DPIsBlank(window, from)) return NO;
    DPNextTabs *state = DPStateFor(window);
    if (state.moving) return NO;
    NSSet<NSNumber *> *before = DPSessions(browser);
    long long fromSession = DPActiveSession(browser);
    NSArray<NSString *> *tabsBefore = DPTabIDs(window);
    id tab = ((id (*)(id, SEL, Class, NSString *, id, id))objc_msgSend)(scripted, make, tabClass, @"appleScriptTabs", nil, @{});
    // The command bar sends you straight back to the tab you were on, so the new tab is found by what's new.
    NSMutableArray<NSString *> *added = [DPTabIDs(window) mutableCopy];
    [added removeObjectsInArray:tabsBefore];
    NSString *created = tab && added.count == 1 ? added.firstObject : nil;
    if (!created) return tab != nil;
    state.originOf[created] = from;
    state.moving = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ DPPlace(window, created, from, fromSession, before, state, 20); });
    return YES;
}

// Menu items hold their target weakly, so the relay is kept on the item.
@interface DPNewTabRelay : NSObject
@property(weak) id target;
@property SEL action;
@end

@implementation DPNewTabRelay
- (void)open:(NSMenuItem *)sender {
    NSWindow *window = NSApp.keyWindow;
    if (window && DPOpenNextToCurrent(window)) return;
    if (self.action) [NSApp sendAction:self.action to:self.target from:sender];
}
@end

static NSMenuItem *DPNewTabItem(void) {
    for (NSMenuItem *top in NSApp.mainMenu.itemArray)
        for (NSMenuItem *item in top.submenu.itemArray)
            if ([item.title isEqualToString:@"New Tab"] && item.keyEquivalent.length) return item;
    return nil;
}

static void DPRelayMenuItem(BOOL on) {
    NSMenuItem *item = DPNewTabItem();
    DPNewTabRelay *relay = DPGet(item, &DPRelayKey);
    if (!item || on == (relay != nil)) return;
    if (on) {
        relay = [DPNewTabRelay new];
        relay.target = item.target;
        relay.action = item.action;
        DPSet(item, &DPRelayKey, relay);
        item.target = relay;
        item.action = @selector(open:);
    } else {
        item.target = relay.target;
        item.action = relay.action;
        DPSet(item, &DPRelayKey, nil);
    }
}

static void DPNewTabButton_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    if (!(self.window && DPOpenNextToCurrent(self.window))) DPCallOriginal(DPNewTabButton_mouseDown, self, event);
}

static void DPReturnTo(NSWindow *window, NSString *originID, NSString *expectedFront) {
    id origin = DPScriptTab(window, originID);
    if (origin && [DPActiveTabID(window) isEqual:expectedFront]) DPFocusTab(origin);
}

static void DPNote(NSWindow *window) {
    NSString *active = DPActiveTabID(window);
    NSArray<NSString *> *ids = DPTabIDs(window);
    DPNextTabs *state = DPGet(window, &DPStateKey);
    if (!active || !ids.count) return;
    if (!state) return (void)DPStateFor(window);
    if (state.moving) return;
    NSSet<NSString *> *now = [NSSet setWithArray:ids];
    BOOL switched = ![active isEqual:state.lastFrontID];

    if (state.lastFrontID && switched && ![state.knownIDs containsObject:active] && [now containsObject:state.lastFrontID] && DPIsBlank(window, active))
        state.originOf[active] = state.lastFrontID;

    for (NSString *tab in state.originOf.allKeys) {
        NSString *origin = state.originOf[tab];
        if (![now containsObject:origin]) {
            [state.originOf removeObjectForKey:tab];
        } else if (![now containsObject:tab]) {
            [state.originOf removeObjectForKey:tab];
            if ([state.lastFrontID isEqual:tab] && ![active isEqual:origin])
                dispatch_async(dispatch_get_main_queue(), ^{ DPReturnTo(window, origin, active); });
        } else if (![active isEqual:tab] && ![active isEqual:origin]) {
            [state.originOf removeObjectForKey:tab];
            // Dia may bring the next tab to the front before it lets the closing one go.
            if ([state.lastFrontID isEqual:tab])
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    if (!DPScriptTab(window, tab)) DPReturnTo(window, origin, active);
                });
        }
    }
    state.knownIDs = now;
    state.lastFrontID = active;
}

static void DPContentPane_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContentPane_viewDidMoveToWindow, self);
    NSWindow *window = self.window;
    if (window && DPNewTabNextToCurrent.on) DPNote(window);
}

static void DPNewTabPage_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPNewTabPage_viewDidMoveToWindow, self);
    NSWindow *window = self.window;
    if (window && DPNewTabNextToCurrent.on) DPNote(window);
}

static void DPInstallNewTabNextToCurrent(void) {
    DPHook(DPDiaContentPane, @selector(viewDidMoveToWindow), (IMP)DPContentPane_viewDidMoveToWindow);
    DPHook(DPDiaNewTabPage, @selector(viewDidMoveToWindow), (IMP)DPNewTabPage_viewDidMoveToWindow);
    DPHook(DPDiaNewTabButton, @selector(mouseDown:), (IMP)DPNewTabButton_mouseDown);
    DPOnLaunch(^{ if (DPNewTabNextToCurrent.on) DPRelayMenuItem(YES); });
}

static void DPApplyNewTabNextToCurrent(DPPatch *patch) {
    DPRelayMenuItem(patch->on);
    for (NSWindow *window in NSApp.windows) {
        DPSet(window, &DPStateKey, nil);
        if (patch->on) DPNote(window);
    }
}

static NSString *DPVerifyNewTabNextToCurrent(DPPatch *patch) {
    NSMenuItem *item = DPNewTabItem();
    if (!item) return patch->on ? @"Dia has no New Tab menu item" : nil;
    if (patch->on && !DPGet(item, &DPRelayKey)) return @"New Tab doesn't open next to the current tab";
    if (!patch->on && DPGet(item, &DPRelayKey)) return @"New Tab is still changed";
    return nil;
}

DP_PATCH(DPNewTabNextToCurrent) {
    .key = @"newTabNextToCurrent",
    .order = 86,
    .title = @"Open New Tabs Next to Current",
    .detail = @"A new tab opens right after the tab you’re on, not at the end, as in Arc and Chrome. Close it and you’re back on the tab you came from. On a pinned tab, it opens at the top of the unpinned tabs.",
    .symbol = @"rectangle.badge.plus",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaContentPane, DPDiaNewTabPage, DPDiaNewTabButton),
    .install = DPInstallNewTabNextToCurrent,
    .apply = DPApplyNewTabNextToCurrent,
    .verify = DPVerifyNewTabNextToCurrent,
};

