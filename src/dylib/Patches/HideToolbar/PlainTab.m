#import "HideToolbar.h"

// Dia fills the selected tab with the site's color so it runs into the toolbar under it. With the toolbar hidden it runs
// into nothing, so the tab takes the page color instead, and the site's color again as the toolbar fades in.
static char DPFillKey, DPAppearanceKey;
static NSHashTable<NSView *> *DPTabFills;  // Every tab fill Dia has painted.

static BOOL DPIsTabFill(NSView *view) {
    if (!DPIsKind(view.superview.superview, DPDiaTabShape)) return NO;
    for (NSView *up = view.superview; up; up = up.superview)
        if (DPIsKind(up, DPDiaTabStrip)) return YES;
    return NO;
}

// How much shows of the window's most visible toolbar.
static CGFloat DPToolbarShowing(NSWindow *window) {
    CGFloat showing = 0;
    for (NSView *pane in DPPanes) {
        NSView *bar = pane.window == window ? DPSubview(pane, DPDiaToolbar) : nil;
        if (bar && !bar.hiddenOrHasHiddenAncestor) showing = MAX(showing, bar.alphaValue);
    }
    return showing;
}

static BOOL DPPlain(NSView *fill) { return DPPlainSelectedTab.on && DPHideToolbar.on && DPToolbarShowing(fill.window) < 0.01; }

// The selected tab also gets an appearance that suits the site's color, so its title stays readable on it. A plain tab
// goes back to the tab strip's; Dia's comes back with the color. A tab that isn't selected has none.
static void DPPlainAppearance(NSView *fill, BOOL plain) {
    NSView *tab = fill.superview.superview.superview.superview;  // tab, background, shape, flipped, fill
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

// Dia sets the site's color here each time, so whatever's on the layer after it is Dia's.
static void DPFill_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFill_updateLayer, self);
    if (!self.layer.backgroundColor || !DPIsTabFill(self)) return;
    [DPTabFills addObject:self];
    NSColor *dia = [NSColor colorWithCGColor:self.layer.backgroundColor];
    DPSet(self, &DPFillKey, dia);
    CGFloat plain = DPPlainSelectedTab.on && DPHideToolbar.on ? 1 - DPToolbarShowing(self.window) : 0;
    DPPlainAppearance(self, plain > 0.5);
    if (plain <= 0) return;
    // The tab strip's appearance: Dia gives a tab on a dark color a dark appearance of its own.
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
    DPHook(DPDiaColorFill, @selector(updateLayer), (IMP)DPFill_updateLayer);
}

static void DPApplyPlainSelectedTab(DPPatch *patch) {
    for (NSView *fill in DPFindViews(DPDiaColorFill))
        if (DPIsTabFill(fill)) fill.needsDisplay = YES;
}

// Found from Dia's views, so a hook that never ran shows up: no tab fill has Dia's color recorded.
static NSString *DPVerifyPlainSelectedTab(DPPatch *patch) {
    for (NSView *fill in DPFindViews(DPDiaColorFill)) {
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
    .classes = DPClasses(DPDiaColorFill, DPDiaTabShape, DPDiaTabStrip),
    .install = DPInstallPlainSelectedTab,
    .apply = DPApplyPlainSelectedTab,
    .verify = DPVerifyPlainSelectedTab,
};
