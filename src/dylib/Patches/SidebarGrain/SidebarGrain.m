#import "SidebarGrain.h"

static void DPGrainSidebarDidLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPGrainSidebarDidLayout, self);
    DPTrackGrainHost(self.view);
}

static void DPGrainStripDidLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPGrainStripDidLayout, self);
    DPTrackGrainHost(self.view);
}

static void DPGrainSwitcherItemDidUpdate(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGrainSwitcherItemDidUpdate, self);
    if ([DPSwiftValue(self, @"isSelected") boolValue]) DPRefreshSidebarGrain();
}

static void DPGrainDotDidLayout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGrainDotDidLayout, self);
    DPRefreshSidebarGrain();
}

static void DPGrainDotDidUpdate(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGrainDotDidUpdate, self);
    if ([DPSwiftValue(self, @"isSelected") boolValue]) DPRefreshSidebarGrain();
}

static void DPInstallSidebarGrain(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskRightMouseDown handler:^NSEvent *(NSEvent *event) {
        return DPGrainRightClick(event);
    }];
    DPHook(DPDiaSidebarController, @selector(viewDidLayout), (IMP)DPGrainSidebarDidLayout);
    DPHook(DPDiaTabStripController, @selector(viewDidLayout), (IMP)DPGrainStripDidLayout);
    DPHook(DPDiaSpaceSwitcherItem, @selector(updateLayer), (IMP)DPGrainSwitcherItemDidUpdate);
    DPHook(DPDiaPageIndicatorDot, @selector(layout), (IMP)DPGrainDotDidLayout);
    DPHook(DPDiaPageIndicatorDot, @selector(updateLayer), (IMP)DPGrainDotDidUpdate);
}

static void DPApplySidebarGrain(DPPatch *patch) { DPRefreshSidebarGrain(); }

DP_PATCH(DPSidebarGrain) {
    .key = @"sidebarGrain",
    .order = 74,
    .title = @"Sidebar Grain",
    .detail = @"Add texture behind sidebar or horizontal tabs. Adjust the grain, softness and scale, for all profiles or for one.",
    .choice = @"sidebarGrainMaterial",
    .defaultChoice = @"sand",
    .choices = DPGrainTextureMenu,
    .symbol = @"circle.dotted",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaSidebarController, DPDiaSidebarFooter, DPDiaTabStripController, DPDiaTabStrip, DPDiaSpaceSwitcher, DPDiaSpaceSwitcherItem, DPDiaPageIndicatorDot),
    .install = DPInstallSidebarGrain,
    .apply = DPApplySidebarGrain,
    .verify = DPVerifyGrainHosts,
    .rows = DPGrainRows,
};
