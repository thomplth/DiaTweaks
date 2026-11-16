#import "StdPatch/Hide.h"

extern DPPatch DPHideTrafficLights;
static const CGFloat DPPinnedTabsInset = 6;
static char DPLightsKey, DPStackFrameKey;

static BOOL DPIsTrafficLights(NSView *view) { return DPIsKind(view, DPDiaTrafficLights); }

static NSRect DPLaidOutStack(NSView *stack) { return [DPDiaValue(stack, &DPStackFrameKey, @(stack.frame)) rectValue]; }

// Out of the stack the lights aren't subviews, so the header holds them.
static void DPSidebarHeader_layout(NSView *self, SEL _cmd) {
    NSView *lights = DPFindView(self, ^BOOL(NSView *view) { return DPIsTrafficLights(view); });
    if (lights) DPSet(self, &DPLightsKey, @[ lights, lights.superview ]);
    NSArray *held = DPGet(self, &DPLightsKey);
    NSStackView *stack = held.lastObject;
    if (![stack isKindOfClass:NSStackView.class]) return DPCallOriginal(DPSidebarHeader_layout, self);
    [stack setVisibilityPriority:DPHideTrafficLights.on ? NSStackViewVisibilityPriorityNotVisible : NSStackViewVisibilityPriorityMustHold forView:held.firstObject];
    DPCallOriginal(DPSidebarHeader_layout, self);
    if (!DPMayAdjust(stack)) return;
    NSRect laidOut = DPLaidOutStack(stack), frame = laidOut;
    if (DPHideTrafficLights.on && NSMinX(laidOut) > DPPinnedTabsInset) {
        frame.origin.x = DPPinnedTabsInset;
        frame.size.width = NSMaxX(laidOut) - DPPinnedTabsInset;
    }
    DPOverride(stack, &DPStackFrameKey, @(laidOut), @(frame));
    stack.frame = frame;
}

static void DPInstallHideTrafficLights(void) { DPHook(DPDiaSidebarHeader, @selector(layout), (IMP)DPSidebarHeader_layout); }

static NSString *DPVerifyHideTrafficLights(DPPatch *patch) {
    NSString *problem = DPVerifyHides(patch);
    if (problem) return problem;
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        NSStackView *stack = [DPGet(header, &DPLightsKey) lastObject];
        if (![stack isKindOfClass:NSStackView.class] || header.hiddenOrHasHiddenAncestor) continue;
        NSRect laidOut = DPLaidOutStack(stack);
        CGFloat left = patch->on ? MIN(NSMinX(laidOut), DPPinnedTabsInset) : NSMinX(laidOut);
        if (fabs(NSMinX(stack.frame) - left) > 0.5) return patch->on ? @"profile button isn't in line with the pinned tabs" : @"profile button moved";
        if (fabs(NSMaxX(stack.frame) - NSMaxX(laidOut)) > 0.5) return @"header buttons moved";
    }
    return nil;
}

DP_PATCH(DPHideTrafficLights) {
    .key = @"hideTrafficLights",
    .order = 98,
    .title = @"Hide Window Controls",
    .detail = @"Hide the close, minimize and zoom buttons. ⌘W, ⌘M and the Window menu still work.",
    .symbol = @"ellipsis",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaTrafficLights, DPDiaSidebarHeader),
    .hides = DPIsTrafficLights,
    .install = DPInstallHideTrafficLights,
    .verify = DPVerifyHideTrafficLights,
};
