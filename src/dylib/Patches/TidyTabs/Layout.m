#import "TidyTabs.h"

static const CGFloat DPTidyRowHeight = 24;
static NSHashTable<NSView *> *DPTidyLists;
static char DPScrollFrameKey;

NSScrollView *DPTidyListScroll(NSView *list) {
    for (NSView *sub in list.subviews) if ([sub isKindOfClass:NSScrollView.class]) return (NSScrollView *)sub;
    return nil;
}

static void DPTabList_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTabList_layout, self);
    [DPTidyLists addObject:self];
    DPTidyHover *hover = DPTidyTabs.on ? [DPTidyHover attachToList:self] : [DPTidyHover forList:self];
    CGFloat progress = DPTidyTabs.on ? hover.progress : 0;
    NSView *separator = DPTidySeparatorIn(self);
    if (separator) DPPlaceSeparatorBrush(separator);
    CGFloat inset = separator ? 0 : round(DPTidyRowHeight * progress);
    NSScrollView *scroll = DPTidyListScroll(self);
    if (!scroll) return;
    NSRect laidOut = [DPDiaValue(scroll, &DPScrollFrameKey, @(scroll.frame)) rectValue], frame = laidOut;
    inset = MIN(inset, NSHeight(laidOut));
    frame.size.height -= inset;
    if (self.isFlipped) frame.origin.y += inset;
    DPOverride(scroll, &DPScrollFrameKey, @(laidOut), @(frame));
    if (!NSEqualRects(scroll.frame, frame)) scroll.frame = frame;

    DPTidyRowView *row = DPTidyRowIn(self, inset > 0);
    if (!row) return;
    CGFloat y = self.isFlipped ? NSMinY(laidOut) : NSMaxY(laidOut) - inset;
    row.frame = NSMakeRect(NSMinX(laidOut), y, NSWidth(laidOut), inset);
    row.alphaValue = progress;
    row.hidden = inset < 1;
}

NSRect DPTidyHoverZone(NSView *list) {
    NSScrollView *scroll = DPTidyListScroll(list);
    if (!scroll || DPTidySeparatorIn(list)) return NSZeroRect;
    NSRect laidOut = [DPDiaValue(scroll, &DPScrollFrameKey, @(scroll.frame)) rectValue];
    DPTidyRowView *row = DPTidyRowIn(list, NO);
    CGFloat open = row && !row.hidden ? NSHeight(row.frame) : 0;
    NSRect zone = NSMakeRect(NSMinX(laidOut), NSMinY(laidOut) - 6, NSWidth(laidOut), 10 + open);
    if (!list.isFlipped) zone.origin.y = NSMaxY(laidOut) - 4 - open;
    return [list convertRect:zone toView:nil];
}

void DPRelayoutTidyLists(void) { DPRelayoutViews(DPTidyLists); }

void DPInstallTidyLayout(void) {
    DPTidyLists = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaTabList, @selector(layout), (IMP)DPTabList_layout);
    DPInstallTidySeparator();
}
