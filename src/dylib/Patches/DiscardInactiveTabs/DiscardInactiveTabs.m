#import "DiscardInactiveTabs.h"

static const NSTimeInterval DPDiscardCheckInterval = 60;
static NSTimer *DPCheckTimer;
static BOOL DPRefreshScheduled;

static NSMenu *DPDiscardChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Discard After"];
    NSDictionary<NSString *, NSString *> *titles = @{
        @"15": @"15 Minutes", @"30": @"30 Minutes", @"60": @"1 Hour", @"120": @"2 Hours",
        @"240": @"4 Hours", @"480": @"8 Hours", @"1440": @"1 Day",
    };
    for (NSString *minutes in @[ @"15", @"30", @"60", @"120", @"240", @"480", @"1440" ])
        [menu addItemWithTitle:titles[minutes] action:nil keyEquivalent:@""].representedObject = minutes;
    return menu;
}

static void DPRefreshIfActive(void) {
    DPRefreshScheduled = NO;
    if (DPDiscardInactiveTabs.on && NSApp.active) DPRefreshTabIndicators();
}

void DPScheduleTabRefresh(void) {
    if (!DPDiscardInactiveTabs.on || DPRefreshScheduled) return;
    DPRefreshScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{ DPRefreshIfActive(); });
}

static void DPCheckIdleTabs(void) {
    DPDiscardIdleTabs(DPChoice(&DPDiscardInactiveTabs).integerValue * 60);
    DPRefreshIfActive();
}

static void DPApplyDiscardInactiveTabs(DPPatch *patch) {
    [DPCheckTimer invalidate];
    DPCheckTimer = nil;
    if (!patch->on) {
        DPClearTabIndicators();
        return;
    }
    DPCheckTimer = [NSTimer scheduledTimerWithTimeInterval:DPDiscardCheckInterval repeats:YES block:^(NSTimer *_) { DPCheckIdleTabs(); }];
    DPCheckTimer.tolerance = 10;
    DPRefreshTabIndicators();
}

static void DPTabRow_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTabRow_viewDidMoveToWindow, self);
    DPScheduleTabRefresh();
}

static void DPTabRow_prepareForReuse(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTabRow_prepareForReuse, self);
    DPScheduleTabRefresh();
}

static void DPDockItem_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPDockItem_viewDidMoveToWindow, self);
    DPScheduleTabRefresh();
}

static void DPContentPane_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContentPane_viewDidMoveToWindow, self);
    DPScheduleTabRefresh();
}

static void DPInstallDiscardInactiveTabs(void) {
    DPInstallDiscarder();
    DPOnLaunch(^{ DPApplyDiscardInactiveTabs(&DPDiscardInactiveTabs); });
    DPHook(DPDiaTabView, @selector(viewDidMoveToWindow), (IMP)DPTabRow_viewDidMoveToWindow);
    DPHook(DPDiaTabView, sel_registerName("prepareForReuse"), (IMP)DPTabRow_prepareForReuse);
    DPHook(DPDiaPinnedTab, @selector(viewDidMoveToWindow), (IMP)DPDockItem_viewDidMoveToWindow);
    DPHook(DPDiaContentPane, @selector(viewDidMoveToWindow), (IMP)DPContentPane_viewDidMoveToWindow);
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *_) { DPScheduleTabRefresh(); }];
}

static NSString *DPVerifyDiscardInactiveTabs(DPPatch *patch) { return DPVerifyTabIndicators(); }

DP_PATCH(DPDiscardInactiveTabs) {
    .key = @"discardInactiveTabs",
    .order = 82,
    .title = @"Discard Inactive Tabs",
    .detail = @"Free the memory of tabs you haven't used for a while, and mark tabs that aren't loaded: a dotted ring around the favicon and a dimmed row. Closed pinned tabs dim too.",
    .symbol = @"memorychip",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Discard-inactive-tabs.md",
    .classes = DPClasses(DPDiaWebContents, DPDiaWebContentDelegate, DPDiaTabView, DPDiaPinnedTab, DPDiaContentPane),
    .choice = @"discardInactiveTabsAfter",
    .defaultChoice = @"120",
    .choices = DPDiscardChoices,
    .install = DPInstallDiscardInactiveTabs,
    .apply = DPApplyDiscardInactiveTabs,
    .verify = DPVerifyDiscardInactiveTabs,
};
