#import "GroupTabs.h"

NSArray<NSString *> *DPSelectionIDKeys(id selection);
NSString *DPIDKey(id value);
void DPEachValue(id collection, void (^visit)(id value));

static NSArray<NSString *> *DPWalkKeys(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[ @"contentViewController", @"tabSidebarViewController", @"tabStripContainerViewController", @"delegate", @"viewModel",
                  @"presenter", @"sidebarStorage", @"storage", @"sidebarControllerStorage", @"controllerStorage", @"tabListController",
                  @"tabStripController" ];
    });
    return keys;
}

static BOOL DPIsTabList(id obj) {
    const char *name = object_getClassName(obj);
    return name && (strstr(name, "TabListController") || strstr(name, "TabStripController"));
}

// Keys such as delegate can lead to the rest of the app.
static BOOL DPMayHoldTabs(id obj) {
    const char *name = object_getClassName(obj);
    return name && (strstr(name, "Tab") || strstr(name, "Window") || strstr(name, "Sidebar") || strstr(name, "Strip"));
}

static void DPWalk(id obj, NSMutableArray *found, NSMutableSet *seen, NSInteger depth) {
    if (!obj || depth > 8 || [seen containsObject:obj]) return;
    if ([obj isKindOfClass:NSArray.class]) {
        for (id each in obj) DPWalk(each, found, seen, depth + 1);
        return;
    }
    if ([obj isKindOfClass:NSDictionary.class]) {
        for (id each in [obj allValues]) DPWalk(each, found, seen, depth + 1);
        return;
    }
    [seen addObject:obj];
    if (DPIsTabList(obj)) [found addObject:obj];
    if ([obj isKindOfClass:NSWindow.class]) DPWalk([(NSWindow *)obj contentViewController], found, seen, depth + 1);
    if ([obj isKindOfClass:NSViewController.class] && [obj respondsToSelector:@selector(childViewControllers)])
        DPWalk([(NSViewController *)obj childViewControllers], found, seen, depth + 1);
    if (!DPMayHoldTabs(obj)) return;
    for (NSString *key in DPWalkKeys()) DPWalk(DPSwiftValue(obj, key), found, seen, depth + 1);
}

static void DPAddUnique(NSMutableDictionary *lists, NSString *key, id value) {
    NSMutableArray *list = lists[key] ?: [NSMutableArray array];
    if (![list containsObject:value]) [list addObject:value];
    lists[key] = list;
}

static void DPReadObject(id obj, NSString *key, NSSet<NSNumber *> *tracked,
                         NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *sessions,
                         NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *urls) {
    if (!obj || obj == NSNull.null || !key.length) return;
    long long sid = DPLongID(DPSwiftValue(obj, @"tabSessionID"));
    if (sid <= 0) sid = DPLongID(DPSwiftValue(obj, @"sessionId"));
    if (sid > 0 && [tracked containsObject:@(sid)]) DPAddUnique(sessions, key, @(sid));
    NSString *url = DPText(DPSwiftValue(obj, @"webContentURL")) ?: DPText(DPSwiftValue(obj, @"url"));
    if (url.length) DPAddUnique(urls, key, url);
}

static void DPReadContent(id content, NSString *key, NSSet<NSNumber *> *tracked,
                          NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *sessions,
                          NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *urls) {
    id model = DPSwiftValue(content, @"viewModel");
    for (id obj in @[ content ?: NSNull.null, DPSwiftValue(content, @"delegate") ?: NSNull.null, DPSwiftValue(content, @"webContent") ?: NSNull.null,
                      model ?: NSNull.null, DPSwiftValue(model, @"delegate") ?: NSNull.null ])
        DPReadObject(obj, key, tracked, sessions, urls);
}

static void DPReadTab(id tab, NSSet<NSNumber *> *tracked, NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *sessions,
                      NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *urls) {
    NSString *key = DPIDKey(DPSwiftValue(tab, @"tabID") ?: DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"tabID"));
    if (!key.length) return;
    DPReadContent(tab, key, tracked, sessions, urls);
    DPEachValue(DPSwiftValue(tab, @"contentControllers") ?: DPSwiftValue(tab, @"contentViews"), ^(id content) {
        DPReadContent(content, key, tracked, sessions, urls);
    });
}

static id DPSelection(NSWindow *window, NSArray *controllers) {
    id state = DPSwiftValue(DPSwiftValue(DPSwiftValue(window, @"viewModel"), @"stateSubject"), @"currentValue");
    id selection = DPSwiftValue(state, @"tabSelectionState");
    if (selection) return selection;
    for (id controller in controllers) {
        selection = DPSwiftValue(controller, @"selectionState") ?: DPSwiftValue(controller, @"tabSelectionState") ?: DPSwiftValue(controller, @"sidebarSelectionState");
        if (selection) return selection;
    }
    return nil;
}

static NSArray *DPTabControllers(NSWindow *window) {
    NSMutableArray *controllers = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    DPWalk(window, controllers, seen, 0);
    for (NSView *view in [DPFindViews(DPDiaTabList) arrayByAddingObjectsFromArray:DPFindViews(DPDiaTabStrip)])
        if (view.window == window) DPWalk(DPSwiftValue(DPSwiftValue(view, @"viewModel"), @"presenter"), controllers, seen, 0);
    return controllers;
}

BOOL DPCanReadSelection(id browser) {
    NSWindow *window = DPBrowserWindow(browser);
    return !window || DPSelection(window, DPTabControllers(window));
}

NSSet<NSNumber *> *DPSelectedSessions(id browser) {
    NSWindow *window = DPBrowserWindow(browser);
    if (!window) return nil;
    NSArray *controllers = DPTabControllers(window);
    NSArray<NSString *> *keys = DPSelectionIDKeys(DPSelection(window, controllers));
    if (keys.count < 2) return nil;

    NSMutableSet<NSNumber *> *tracked = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *byURL = [NSMutableDictionary dictionary];
    for (id contents in DPTrackedContents(browser)) {
        long long sid = DPSessionOf(contents);
        NSString *url = DPText(DPMsg(contents, @selector(url)));
        if (sid <= 0) continue;
        [tracked addObject:@(sid)];
        if (!url.length) continue;
        NSMutableArray *list = byURL[url] ?: [NSMutableArray array];
        [list addObject:@(sid)];
        byURL[url] = list;
    }
    NSMutableDictionary *sessions = [NSMutableDictionary dictionary], *urls = [NSMutableDictionary dictionary];
    for (id controller in controllers) DPEachValue(DPSwiftValue(controller, @"tabControllers"), ^(id tab) { DPReadTab(tab, tracked, sessions, urls); });
    for (NSView *tab in [DPFindViews(DPDiaTabView) arrayByAddingObjectsFromArray:DPFindViews(DPDiaPinnedTab)])
        if (tab.window == window) DPReadTab(tab, tracked, sessions, urls);

    NSMutableSet<NSNumber *> *chosen = [NSMutableSet set];
    for (NSString *key in keys) {
        if ([sessions[key] count]) {
            [chosen addObjectsFromArray:sessions[key]];
            continue;
        }
        for (NSString *url in urls[key]) {
            NSMutableArray<NSNumber *> *list = byURL[url];
            if (!list.count) continue;
            [chosen addObject:list.firstObject];
            [list removeObjectAtIndex:0];
        }
    }
    return chosen.count >= 2 ? [chosen copy] : nil;
}
