#import "DiscardInactiveTabs.h"

static const CGFloat DPDimmedAlpha = 0.55;

static void DPSetDimmed(NSView *view, BOOL dimmed) {
    CGFloat alpha = dimmed ? DPDimmedAlpha : 1;
    if (view.alphaValue != alpha) view.alphaValue = alpha;
}

static NSView *DPRowContent(NSView *row) {
    return DPFindView(row, ^BOOL(NSView *view) { return DPIsKind(view, "_TtC5TabUI14TabContentView"); });
}

static NSView *DPIconIn(NSView *root) {
    return DPFindView(root, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSImageView.class] && !view.hidden && NSEqualSizes(view.frame.size, NSMakeSize(16, 16));
    });
}

static BOOL DPAnyPaneRunning(NSArray<NSString *> *panes, NSDictionary *states) {
    for (NSString *pane in panes) {
        NSString *state = states[pane];
        if (state && ![state isEqual:@"Discarded"] && ![state isEqual:@"Closed"]) return YES;
    }
    return NO;
}

NSArray<NSString *> *DPPanesOfTabView(NSView *view) {
    return DPIsKind(view, DPDiaTabView) ? DPPanesOfRow(view) : DPPanesOfDockItem(view);
}

static void DPDressTabViewAs(NSView *view, BOOL dimmed) {
    BOOL isRow = DPIsKind(view, DPDiaTabView);
    NSView *content = isRow ? DPRowContent(view) : view;
    NSView *icon = DPIconIn(content);
    if (content && icon) DPSetDimmed(isRow ? content : icon, dimmed);
}

NSArray<NSString *> *DPDressTabView(NSView *view, NSDictionary *states) {
    NSArray<NSString *> *panes = DPPanesOfTabView(view);
    DPDressTabViewAs(view, !DPAnyPaneRunning(panes, states));
    return panes;
}

void DPClearTabView(NSView *view) {
    DPDressTabViewAs(view, NO);
}

NSString *DPVerifyTabIndicators(void) {
    BOOL on = DPDiscardInactiveTabs.on;
    if (on) DPRefreshTabIndicators();
    NSDictionary *states = on ? DPLoadedPaneStates() : nil;
    for (NSView *row in DPFindViews(DPDiaTabView)) {
        if (!DPIsTabViewTracked(row)) return @"a tab row isn't tracked";
        NSView *content = DPRowContent(row);
        if (!content || !DPIconIn(content)) return @"a tab has no favicon to mark";
        BOOL dimmed = on && !DPAnyPaneRunning(DPPanesOfRow(row), states);
        if ((content.alphaValue < 1) != dimmed) return @"a tab's dimming is wrong";
    }
    return nil;
}
