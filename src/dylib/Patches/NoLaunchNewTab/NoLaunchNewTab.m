#import "StdPatch/StdPatch.h"

extern DPPatch DPNoLaunchNewTab;

static const NSTimeInterval DPSweepInterval = 0.5;
static const NSTimeInterval DPLaunchSettleTime = 8;
static const NSTimeInterval DPLaunchSweepLimit = 120;

static NSMapTable<NSWindow *, NSDate *> *DPFirstSeen;
static NSDate *DPLaunched;
static BOOL DPUserActed;
static id DPInputMonitor;

static BOOL DPShown(NSView *view) {
    return !view.hiddenOrHasHiddenAncestor;
}

static NSView *DPSelectedTabIn(NSView *root) {
    return DPFindView(root, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaTabView) && DPShown(view) && [view.accessibilityValue boolValue];
    });
}

static BOOL DPShowsNewTabPage(NSView *root) {
    return DPFindView(root, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaNewTabPage) && DPShown(view); }) != nil;
}

static BOOL DPHasOtherTabs(NSView *root, NSView *selected) {
    NSView *list = DPFindView(root, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabList); }) ?: root;
    return DPFindView(list, ^BOOL(NSView *view) {
        return view != selected && DPShown(view) && (DPIsKind(view, DPDiaTabView) || DPIsKind(view, DPDiaTabGroupCell));
    }) != nil;
}

static NSButton *DPCloseButtonOf(NSView *tab) {
    return (NSButton *)DPFindView(tab, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaHoverableButton); });
}

static void DPCloseLaunchNewTab(NSWindow *window) {
    NSView *root = window.contentView.superview;
    NSView *selected = DPSelectedTabIn(root);
    if (!selected || !DPShowsNewTabPage(root) || !DPHasOtherTabs(root, selected)) return;
    NSButton *close = DPCloseButtonOf(selected);
    // The button is disabled while it's hidden, until the pointer is over the tab, so performClick: does nothing.
    if (close.action) [NSApp sendAction:close.action to:close.target from:close];
}

static BOOL DPIsBrowserWindow(NSWindow *window) {
    return window.visible && (window.styleMask & NSWindowStyleMaskTitled) && ![window isKindOfClass:NSPanel.class];
}

static void DPStopSweeping(void) {
    if (DPInputMonitor) [NSEvent removeMonitor:DPInputMonitor];
    DPInputMonitor = nil;
    DPUserActed = YES;
}

// Dia adds the New Tab while it restores each window, sometimes a few seconds after the window shows, and windows can
// wait behind the keychain prompt after an install. So each window is watched for a few seconds from when it first
// shows, until the first click or key press: after that a New Tab is one the user opened.
static void DPSweep(void) {
    if (DPUserActed || -DPLaunched.timeIntervalSinceNow > DPLaunchSweepLimit) return DPStopSweeping();
    if (DPNoLaunchNewTab.on)
        for (NSWindow *window in NSApp.windows) {
            if (!DPIsBrowserWindow(window)) continue;
            NSDate *firstSeen = [DPFirstSeen objectForKey:window];
            if (!firstSeen) [DPFirstSeen setObject:(firstSeen = NSDate.date) forKey:window];
            if (-firstSeen.timeIntervalSinceNow <= DPLaunchSettleTime) DPCloseLaunchNewTab(window);
        }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DPSweepInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DPSweep(); });
}

static void DPInstallNoLaunchNewTab(void) {
    DPFirstSeen = [NSMapTable weakToStrongObjectsMapTable];
    DPOnLaunch(^{
        DPLaunched = NSDate.date;
        NSEventMask input = NSEventMaskKeyDown | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown;
        DPInputMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:input handler:^NSEvent *(NSEvent *event) {
            if (DPIsBrowserWindow(event.window)) DPUserActed = YES;
            return event;
        }];
        DPSweep();
    });
}

DP_PATCH(DPNoLaunchNewTab) {
    .key = @"noLaunchNewTab",
    .order = 77,
    .title = @"Don't open a new tab at launch",
    .detail = @"Closes the New Tab Dia opens in a window when it starts, if the window already has other tabs.",
    .symbol = @"plus.square.on.square",
    .tint = @"systemBlueColor",
    .section = @"Sidebar and tab bar",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Dont-open-a-new-tab-at-launch.md",
    .classes = DPClasses(DPDiaTabView, DPDiaTabGroupCell, DPDiaNewTabPage, DPDiaTabList, DPDiaHoverableButton),
    .install = DPInstallNoLaunchNewTab,
};
