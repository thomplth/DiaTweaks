#import "StdPatch/StdPatch.h"

extern DPPatch DPHideTabGroupBackground;
static char DPHiddenKey;

static BOOL DPIsGrey(CGColorRef color) {
    NSColor *rgb = [[NSColor colorWithCGColor:color] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) return NO;
    CGFloat r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent;
    return fabs(r - g) < 0.02 && fabs(g - b) < 0.02;
}

static void DPStyleBackground(NSView *cell) {
    CALayer *layer = DPSubview(cell, DPDiaTabGroupBackground).layer;
    NSArray *hidden = DPGet(layer, &DPHiddenKey);
    if (DPHideTabGroupBackground.on && layer.backgroundColor && DPIsGrey(layer.backgroundColor)) {
        if (!hidden) DPSet(layer, &DPHiddenKey, hidden = @[ @(layer.borderWidth), [NSMutableArray new] ]);
        for (CALayer *shadow in layer.sublayers) {
            if (shadow.hidden) continue;
            shadow.hidden = YES;
            [hidden[1] addObject:shadow];
        }
        layer.backgroundColor = nil;
        layer.borderWidth = 0;
    } else if (hidden && (!DPHideTabGroupBackground.on || layer.backgroundColor)) {
        layer.borderWidth = [hidden[0] doubleValue];
        for (CALayer *shadow in hidden[1]) shadow.hidden = NO;
        DPSet(layer, &DPHiddenKey, nil);
    }
}

static void DPGroupCell_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGroupCell_updateLayer, self);
    DPStyleBackground(self);
}

static void DPApplyHideTabGroupBackground(DPPatch *patch) {
    for (NSView *cell in DPFindViews(DPDiaTabGroupCell)) cell.needsDisplay = YES;
}

static NSString *DPVerifyHideTabGroupBackground(DPPatch *patch) {
    if (!patch->on) return nil;
    for (NSView *background in DPFindViews(DPDiaTabGroupBackground))
        if (background.layer.backgroundColor && DPIsGrey(background.layer.backgroundColor)) return @"a tab group is still grey";
    return nil;
}

static void DPInstallHideTabGroupBackground(void) {
    DPHook(DPDiaTabGroupCell, @selector(updateLayer), (IMP)DPGroupCell_updateLayer);
}

DP_PATCH(DPHideTabGroupBackground) {
    .key = @"hideTabGroupBackground",
    .order = 81,
    .title = @"Hide Group Background",
    .detail = @"Leave an open tab group without the grey behind it, unless you've picked a colour for the group.",
    .symbol = @"square.stack.fill square.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaTabGroupCell, DPDiaTabGroupBackground),
    .install = DPInstallHideTabGroupBackground,
    .apply = DPApplyHideTabGroupBackground,
    .verify = DPVerifyHideTabGroupBackground,
};
