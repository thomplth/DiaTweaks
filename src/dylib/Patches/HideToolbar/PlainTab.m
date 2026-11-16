#import "HideToolbar.h"

static char DPFillKey, DPAppearanceKey;
static NSHashTable<NSView *> *DPTabFills;

static BOOL DPIsTabFill(NSView *view) {
    if (!DPIsKind(view.superview.superview, DPDiaTabShape)) return NO;
    for (NSView *up = view.superview; up; up = up.superview)
        if (DPIsKind(up, DPDiaTabStrip)) return YES;
    return NO;
}

static CGFloat DPToolbarShowing(NSWindow *window) {
    CGFloat showing = 0;
    for (NSView *pane in DPPanes) {
        NSView *bar = pane.window == window ? DPSubview(pane, DPDiaToolbar) : nil;
        if (bar && !bar.hiddenOrHasHiddenAncestor) showing = MAX(showing, bar.alphaValue);
    }
    return showing;
}

static BOOL DPPlain(NSView *fill) { return DPPlainSelectedTab.on && DPHideToolbar.on && DPToolbarShowing(fill.window) < 0.01; }

static void DPPlainAppearance(NSView *fill, BOOL plain) {
    NSView *tab = fill.superview.superview.superview.superview;
    if (!DPIsKind(tab, DPDiaTabView)) return;
    for (NSView *part in tab.subviews) {
        NSAppearance *dia = DPGet(part, &DPAppearanceKey);
        if (plain && part.appearance) {
            DPSet(part, &DPAppearanceKey, part.appearance);
            part.appearance = nil;
        } else if (!plain && dia) {
            if (!part.appearance && !fill.hiddenOrHasHiddenAncestor) part.appearance = dia;
            DPSet(part, &DPAppearanceKey, nil);
        }
    }
}

static void DPFill_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFill_updateLayer, self);
    if (!self.layer.backgroundColor || !DPIsTabFill(self)) return;
    [DPTabFills addObject:self];
    NSColor *dia = [NSColor colorWithCGColor:self.layer.backgroundColor];
    DPSet(self, &DPFillKey, dia);
    CGFloat plain = DPPlainSelectedTab.on && DPHideToolbar.on ? 1 - DPToolbarShowing(self.window) : 0;
    DPPlainAppearance(self, plain > 0.5);
    if (plain <= 0) return;
    NSView *strip = self;
    while (strip && !DPIsKind(strip, DPDiaTabStrip)) strip = strip.superview;
    __block NSColor *page;
    [(strip ?: self).effectiveAppearance performAsCurrentDrawingAppearance:^{ page = [NSColor.textBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; }];
    NSColor *fill = page ? [[dia colorUsingColorSpace:NSColorSpace.sRGBColorSpace] blendedColorWithFraction:plain ofColor:page] : nil;
    if (fill) self.layer.backgroundColor = fill.CGColor;
}

void DPRepaintTabs(NSWindow *window) {
    for (NSView *fill in DPTabFills)
        if (fill.window == window) fill.needsDisplay = YES;
}

static void DPInstallPlainSelectedTab(void) {
    DPTabFills = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaColorView, @selector(updateLayer), (IMP)DPFill_updateLayer);
}

static void DPApplyPlainSelectedTab(DPPatch *patch) {
    for (NSView *fill in DPFindViews(DPDiaColorView))
        if (DPIsTabFill(fill)) fill.needsDisplay = YES;
}

static NSString *DPVerifyPlainSelectedTab(DPPatch *patch) {
    for (NSView *fill in DPFindViews(DPDiaColorView)) {
        if (!DPIsTabFill(fill) || fill.hiddenOrHasHiddenAncestor || !fill.layer.backgroundColor) continue;
        NSColor *dia = DPGet(fill, &DPFillKey);
        if (!dia) return @"selected tab's fill isn't watched";
        if (!DPPlain(fill) && !CGColorEqualToColor(dia.CGColor, fill.layer.backgroundColor)) return @"selected tab lost the site's color";
    }
    return nil;
}

DP_PATCH(DPPlainSelectedTab) {
    .key = @"plainSelectedTab",
    .order = 46,
    .title = @"Hide Site Color in Tab Bar",
    .detail = @"While the toolbar is hidden, show the selected tab in the page color instead of the site's.",
    .symbol = @"paintbrush.fill",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .section = @"While It's Hidden",
    .classes = DPClasses(DPDiaColorView, DPDiaTabShape, DPDiaTabStrip),
    .install = DPInstallPlainSelectedTab,
    .apply = DPApplyPlainSelectedTab,
    .verify = DPVerifyPlainSelectedTab,
};
