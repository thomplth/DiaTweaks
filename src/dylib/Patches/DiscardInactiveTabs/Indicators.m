#import "DiscardInactiveTabs.h"

typedef NS_ENUM(NSInteger, DPTabLook) { DPTabLookNormal, DPTabLookDimmed, DPTabLookDiscarded };

static const CGFloat DPDimmedAlpha = 0.55;
static const CGFloat DPRingOutset = 3;
static const void *DPRingKey = &DPRingKey;

static void DPSetRing(NSView *icon, BOOL shown) {
    CAShapeLayer *ring = DPGet(icon, DPRingKey);
    if (!shown) {
        [ring removeFromSuperlayer];
        DPSet(icon, DPRingKey, nil);
        return;
    }
    icon.wantsLayer = YES;
    if (!ring) {
        ring = [CAShapeLayer layer];
        ring.fillColor = nil;
        ring.lineWidth = 1.25;
        ring.lineCap = kCALineCapRound;
        ring.lineDashPattern = @[ @0.01, @3.2 ];
        ring.zPosition = 10;
        ring.actions = @{ @"strokeColor": NSNull.null, @"path": NSNull.null, @"bounds": NSNull.null, @"position": NSNull.null };
        icon.layer.masksToBounds = NO;
        [icon.layer addSublayer:ring];
        DPSet(icon, DPRingKey, ring);
    }
    CGRect frame = CGRectInset(icon.bounds, -DPRingOutset, -DPRingOutset);
    ring.frame = frame;
    CGPathRef path = CGPathCreateWithEllipseInRect(CGRectMake(0, 0, frame.size.width, frame.size.height), NULL);
    ring.path = path;
    CGPathRelease(path);
    [icon.effectiveAppearance performAsCurrentDrawingAppearance:^{
        ring.strokeColor = NSColor.secondaryLabelColor.CGColor;
    }];
}

static void DPSetDimmed(NSView *view, BOOL dimmed) {
    CGFloat alpha = dimmed ? DPDimmedAlpha : 1;
    if (view.alphaValue != alpha) view.alphaValue = alpha;
}

static void DPDress(NSView *dimmed, NSView *icon, DPTabLook look) {
    DPSetDimmed(dimmed, look != DPTabLookNormal);
    DPSetRing(icon, look == DPTabLookDiscarded);
}

static NSView *DPRowContent(NSView *row) {
    return DPFindView(row, ^BOOL(NSView *view) { return DPIsKind(view, "_TtC5TabUI14TabContentView"); });
}

static NSView *DPIconIn(NSView *root) {
    return DPFindView(root, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSImageView.class] && !view.hidden && NSEqualSizes(view.frame.size, NSMakeSize(16, 16));
    });
}

typedef NS_ENUM(NSInteger, DPPaneLoad) { DPPaneLoadRunning, DPPaneLoadDiscarded, DPPaneLoadNone };

static DPPaneLoad DPLoadOfPanes(NSArray<NSString *> *panes, NSDictionary *states) {
    DPPaneLoad load = DPPaneLoadNone;
    for (NSString *pane in panes) {
        NSString *state = states[pane];
        if (!state) continue;
        if (![state isEqual:@"Discarded"] && ![state isEqual:@"Closed"]) return DPPaneLoadRunning;
        load = DPPaneLoadDiscarded;
    }
    return load;
}

static DPTabLook DPLookOfRow(NSView *row, NSDictionary *states) {
    switch (DPLoadOfPanes(DPPanesOfRow(row), states)) {
        case DPPaneLoadRunning: return DPTabLookNormal;
        case DPPaneLoadDiscarded: return DPTabLookDiscarded;
        case DPPaneLoadNone: return DPRowHasNoCloseButton(row) ? DPTabLookDimmed : DPTabLookDiscarded;
    }
}

static DPTabLook DPLookOfDockItem(NSView *item, NSDictionary *states) {
    switch (DPLoadOfPanes(DPPanesOfDockItem(item), states)) {
        case DPPaneLoadRunning: return DPTabLookNormal;
        case DPPaneLoadDiscarded: return DPTabLookDiscarded;
        case DPPaneLoadNone: return DPTabLookDimmed;
    }
}

static void DPDressTabs(DPTabLook (^lookOfRow)(NSView *), DPTabLook (^lookOfItem)(NSView *)) {
    for (NSView *row in DPFindViews(DPDiaTabView)) {
        NSView *content = DPRowContent(row);
        NSView *icon = DPIconIn(content);
        if (content && icon) DPDress(content, icon, lookOfRow(row));
    }
    for (NSView *item in DPFindViews(DPDiaPinnedTab)) {
        NSView *icon = DPIconIn(item);
        if (icon) DPDress(icon, icon, lookOfItem(item));
    }
}

void DPRefreshTabIndicators(void) {
    NSDictionary *states = DPLoadedPaneStates();
    DPDressTabs(^(NSView *row) { return DPLookOfRow(row, states); }, ^(NSView *item) { return DPLookOfDockItem(item, states); });
}

void DPClearTabIndicators(void) {
    DPDressTabs(^(NSView *_) { return DPTabLookNormal; }, ^(NSView *_) { return DPTabLookNormal; });
}

NSString *DPVerifyTabIndicators(void) {
    BOOL on = DPDiscardInactiveTabs.on;
    if (on) DPRefreshTabIndicators();
    NSDictionary *states = on ? DPLoadedPaneStates() : nil;
    for (NSView *row in DPFindViews(DPDiaTabView)) {
        NSView *content = DPRowContent(row), *icon = DPIconIn(content);
        if (!content || !icon) return @"a tab has no favicon to mark";
        DPTabLook look = on ? DPLookOfRow(row, states) : DPTabLookNormal;
        if ((DPGet(icon, DPRingKey) != nil) != (look == DPTabLookDiscarded)) return @"a tab's dotted ring is wrong";
        if ((content.alphaValue < 1) != (look != DPTabLookNormal)) return @"a tab's dimming is wrong";
    }
    return nil;
}
