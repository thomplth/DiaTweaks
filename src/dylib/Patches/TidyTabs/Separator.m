#import "TidyTabs.h"

// With pinned tabs in the list, Dia divides them from the rest with a line and a Close All button that shows while the
// pointer is on the divider. The broom goes just left of Close All and shows and hides with it, and Dia's line shortens
// to make room instead of a new row opening.
static char DPLineFrameKey;
static const CGFloat DPCloseAllGap = 4, DPLineGap = 6;

static CALayer *DPSeparatorLine(NSView *separator) {
    for (CALayer *layer in separator.layer.sublayers)
        if (NSHeight(layer.frame) <= 1.5 && NSWidth(layer.frame) > 20) return layer;
    return nil;
}

static NSView *DPCloseAll(NSView *separator) {
    for (NSView *sub in separator.subviews)
        if ([sub isKindOfClass:NSButton.class] && ![sub isKindOfClass:DPTidyBrush.class]) return sub;
    return nil;
}

static DPTidyBrush *DPBrushIn(NSView *separator, BOOL create) {
    for (NSView *sub in separator.subviews) if ([sub isKindOfClass:DPTidyBrush.class]) return (DPTidyBrush *)sub;
    if (!create) return nil;
    DPTidyBrush *brush = [DPTidyBrush new];
    brush.plain = YES;
    [separator addSubview:brush];
    return brush;
}

NSView *DPTidySeparatorIn(NSView *list) {
    NSScrollView *scroll = DPTidyListScroll(list);
    return scroll ? DPFindView(scroll.documentView, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaTabListSeparator) && !view.hiddenOrHasHiddenAncestor;
    }) : nil;
}

static void DPCloseAll_setHidden(NSView *self, SEL _cmd, BOOL hidden) {
    DPCallOriginal(DPCloseAll_setHidden, self, hidden);
    if (DPIsKind(self.superview, DPDiaTabListSeparator)) DPPlaceSeparatorBrush(self.superview);
}

// Tabs below the divider, or in the whole list without one, grouped ones included: rows of a tab's height, less the
// New Tab row at the end. A group's own row is taller than a tab's, so it isn't counted.
NSInteger DPTidyTabsBelowLine(NSView *list) {
    NSCollectionView *collection = (NSCollectionView *)DPTidyListScroll(list).documentView;
    if (![collection isKindOfClass:NSCollectionView.class]) return 0;
    NSView *separator = DPTidySeparatorIn(list);
    CGFloat line = separator ? NSMaxY([collection convertRect:separator.bounds fromView:separator]) - 0.5 : -CGFLOAT_MAX;
    NSInteger rows = 0;
    for (NSInteger section = 0; section < collection.numberOfSections; section++)
        for (NSInteger item = 0; item < [collection numberOfItemsInSection:section]; item++) {
            NSRect frame = [collection.collectionViewLayout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:section]].frame;
            if (NSMinY(frame) >= line && NSHeight(frame) > 0 && NSHeight(frame) <= DPTidyTabRowHeight) rows++;
        }
    return MAX(0, rows - 1);
}

static NSView *DPListOf(NSView *view) {
    for (; view; view = view.superview) if (DPIsKind(view, DPDiaTabList)) return view;
    return nil;
}

void DPPlaceSeparatorBrush(NSView *separator) {
    NSView *closeAll = DPCloseAll(separator);
    // Close All's class is private to Dia's TabList module, so it's hooked once one turns up.
    static BOOL hooked;
    if (closeAll && !hooked) {
        hooked = YES;
        DPHookClass(object_getClass(closeAll), @selector(setHidden:), (IMP)DPCloseAll_setHidden);
    }
    // With Close All, while the pointer is on the divider, and only with enough tabs to tidy. While the model works
    // the broom still comes and goes like this, and the wave fills the whole line whenever it's away.
    BOOL shown = DPTidyTabs.on && closeAll && !closeAll.hidden && (DPTidyIsBusy() || DPTidyTabsBelowLine(DPListOf(separator)) >= DPTidyMinimumTabs);
    DPTidyBrush *brush = DPBrushIn(separator, shown);
    CALayer *line = DPSeparatorLine(separator);
    if (!brush && !line) return;
    CGFloat right = closeAll ? NSMinX(closeAll.frame) - DPCloseAllGap : NSMaxX(separator.bounds) - 7;
    brush.frame = NSMakeRect(right - DPTidyBrushSize, round(NSMidY(separator.bounds) - DPTidyBrushSize / 2), DPTidyBrushSize, DPTidyBrushSize);
    brush.hidden = !shown;
    if (!line) return;
    NSRect dia = [DPDiaValue(line, &DPLineFrameKey, [NSValue valueWithRect:line.frame]) rectValue], frame = dia;
    CGFloat trimmed = MIN(NSWidth(dia), MAX(0, right - DPTidyBrushSize - DPLineGap - NSMinX(dia)));
    if (shown) frame.size.width = trimmed;
    DPOverride(line, &DPLineFrameKey, [NSValue valueWithRect:dia], [NSValue valueWithRect:frame]);
    if (!NSEqualRects(line.frame, frame)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        line.frame = frame;
        [CATransaction commit];
    }
    DPTidyWave(separator.layer, line, line.backgroundColor, DPTidyTabs.on && DPTidyIsBusy());
}

static void DPSeparator_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSeparator_layout, self);
    DPPlaceSeparatorBrush(self);
}

static void DPSeparator_updateLayer(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSeparator_updateLayer, self);
    DPPlaceSeparatorBrush(self);
}

// The tab list's collection view takes every click inside it, to drag tabs; a click on the broom goes to the broom.
static NSView *DPCollection_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    for (DPTidyBrush *brush in DPTidyBrushes()) {
        if (brush.hiddenOrHasHiddenAncestor || ![brush isDescendantOf:self]) continue;
        if (NSPointInRect([brush convertPoint:point fromView:self.superview], brush.bounds)) return brush;
    }
    return DPCallOriginal(DPCollection_hitTest, self, point);
}

void DPInstallTidySeparator(void) {
    DPHook(DPDiaTabListCollection, @selector(hitTest:), (IMP)DPCollection_hitTest);
    DPHook(DPDiaTabListSeparator, @selector(layout), (IMP)DPSeparator_layout);
    DPHook(DPDiaTabListSeparator, @selector(updateLayer), (IMP)DPSeparator_updateLayer);
}
