#import "DiscardInactiveTabs.h"

static const CFTimeInterval DPDressBudget = 0.004;
static const NSTimeInterval DPStatesQuietTime = 0.15, DPStatesMaxWait = 1, DPRowConfigureTime = 0.1;

static NSHashTable<NSView *> *DPTabViews, *DPDressQueue, *DPDressAgain;
static NSMapTable<NSView *, NSSet<NSString *> *> *DPPanesByView;
static NSDictionary *DPPaneStates;
static BOOL DPDrainScheduled, DPAgainScheduled;
static CFTimeInterval DPFirstStatesRequest;
static NSUInteger DPLatestStatesRequest;

static void DPDrainDressQueue(void) {
    DPDrainScheduled = NO;
    if (!DPDiscardInactiveTabs.on) return [DPDressQueue removeAllObjects];
    CFTimeInterval deadline = CACurrentMediaTime() + DPDressBudget;
    NSArray<NSView *> *views = DPDressQueue.allObjects;
    for (NSView *view in views) {
        if (CACurrentMediaTime() > deadline) break;
        [DPDressQueue removeObject:view];
        if (view.window) [DPPanesByView setObject:[NSSet setWithArray:DPDressTabView(view, DPPaneStates)] forKey:view];
    }
    if (!DPDressQueue.count || DPDrainScheduled) return;
    DPDrainScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ DPDrainDressQueue(); });
}

static void DPEnqueueDress(NSView *view) {
    if (!DPPaneStates) DPPaneStates = DPLoadedPaneStates();
    [DPDressQueue addObject:view];
    if (DPDrainScheduled) return;
    DPDrainScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ DPDrainDressQueue(); });
}

// Dia can configure a recycled row after the run loop turn that reused it, so each one is dressed a second time.
static void DPDressAgainSoon(NSView *view) {
    [DPDressAgain addObject:view];
    if (DPAgainScheduled) return;
    DPAgainScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DPRowConfigureTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DPAgainScheduled = NO;
        if (DPDiscardInactiveTabs.on) for (NSView *again in DPDressAgain.allObjects) DPEnqueueDress(again);
        [DPDressAgain removeAllObjects];
    });
}

void DPTrackTabView(NSView *view) {
    [DPTabViews addObject:view];
    if (!DPDiscardInactiveTabs.on) return;
    DPEnqueueDress(view);
    DPDressAgainSoon(view);
}

BOOL DPIsTabViewTracked(NSView *view) {
    return [DPTabViews containsObject:view];
}

static void DPApplyLatestStates(void) {
    NSDictionary *previous = DPPaneStates, *latest = DPLoadedPaneStates();
    DPPaneStates = latest;
    if ([latest isEqualToDictionary:previous]) return;
    NSMutableSet<NSString *> *changed = [NSMutableSet set];
    for (NSString *pane in [previous.allKeys arrayByAddingObjectsFromArray:latest.allKeys])
        if (![previous[pane] isEqual:latest[pane]]) [changed addObject:pane];
    for (NSView *view in DPTabViews.allObjects)
        if ([[DPPanesByView objectForKey:view] intersectsSet:changed]) DPEnqueueDress(view);
}

// Waiting for the last event, up to a limit, is what keeps a burst of page changes from rebuilding the states repeatedly.
void DPRequestTabStates(void) {
    if (!DPDiscardInactiveTabs.on) return;
    NSUInteger request = ++DPLatestStatesRequest;
    CFTimeInterval now = CACurrentMediaTime();
    if (!DPFirstStatesRequest) DPFirstStatesRequest = now;
    NSTimeInterval delay = MAX(0, MIN(DPStatesQuietTime, DPFirstStatesRequest + DPStatesMaxWait - now));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL waitedTooLong = DPFirstStatesRequest && CACurrentMediaTime() - DPFirstStatesRequest >= DPStatesMaxWait;
        if (!DPDiscardInactiveTabs.on || !DPFirstStatesRequest || (request != DPLatestStatesRequest && !waitedTooLong)) return;
        DPFirstStatesRequest = 0;
        DPApplyLatestStates();
    });
}

void DPSweepTabViews(void) {
    if (!DPDiscardInactiveTabs.on) return;
    for (NSView *view in DPTabViews.allObjects) DPEnqueueDress(view);
}

void DPRefreshTabIndicators(void) {
    DPPaneStates = DPLoadedPaneStates();
    [DPDressQueue removeAllObjects];
    for (NSView *view in DPTabViews.allObjects)
        if (view.window) [DPPanesByView setObject:[NSSet setWithArray:DPDressTabView(view, DPPaneStates)] forKey:view];
}

void DPClearTabIndicators(void) {
    DPPaneStates = nil;
    [DPDressQueue removeAllObjects];
    [DPDressAgain removeAllObjects];
    for (NSView *view in DPTabViews.allObjects) DPClearTabView(view);
}

void DPInstallTabTracking(void) {
    DPTabViews = [NSHashTable weakObjectsHashTable];
    DPDressQueue = [NSHashTable weakObjectsHashTable];
    DPDressAgain = [NSHashTable weakObjectsHashTable];
    DPPanesByView = [NSMapTable weakToStrongObjectsMapTable];
}
