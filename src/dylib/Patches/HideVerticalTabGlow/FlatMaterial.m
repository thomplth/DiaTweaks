#import "HideVerticalTabGlow.h"

static BOOL DPIsGlass(NSView *view) {
    Class glass = NSClassFromString(@"NSGlassEffectView");
    return glass && [view isKindOfClass:glass];
}

void DPFlattenTabMaterial(NSView *view, NSView *shape) {
    if (DPIsGlass(view)) DPHideTabDecoration(view, shape);
    for (NSView *sub in view.subviews) DPFlattenTabMaterial(sub, shape);
}

NSString *DPVerifyFlatTabMaterial(NSView *shape, BOOL on) {
    if (DPIsGlass(shape)) {
        if (on && !shape.hidden) return @"a vertical tab still has its glass highlight";
        if (!on && DPHasTabOverride(shape)) return @"tab glass wasn't restored";
    }
    for (NSView *sub in shape.subviews) {
        NSString *problem = DPVerifyFlatTabMaterial(sub, on);
        if (problem) return problem;
    }
    return nil;
}

static void DPGlass_viewDidMoveToSuperview(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGlass_viewDidMoveToSuperview, self);
    for (NSView *up = self.superview; up; up = up.superview)
        if (DPIsKind(up, DPDiaTabShape)) return DPHideTabDecoration(self, up);
    DPRestoreTabDecoration(self);
}

void DPInstallFlatTabMaterial(void) {
    Class glass = NSClassFromString(@"NSGlassEffectView");
    if (glass) DPHookClass(glass, @selector(viewDidMoveToSuperview), (IMP)DPGlass_viewDidMoveToSuperview);
}
