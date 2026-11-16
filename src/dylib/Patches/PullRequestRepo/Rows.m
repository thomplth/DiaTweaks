#import "PullRequestRepo.h"
#import "Patches/CompactTabRows/CompactTabRows.h"
#import <objc/message.h>

static const CGFloat DPExtra = 14, DPTabHeight = 37;
static NSMutableSet<NSString *> *DPTallTabs;
static char DPStatusKey, DPLineKey, DPAdjustedKey, DPEditsKey;

@implementation DPPRStatusLine
@end

static void DPInvalidateRows(void) {
    static BOOL scheduled;
    if (scheduled) return;
    scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        scheduled = NO;
        for (NSView *view in DPFindViews(DPDiaTabListCollection)) [((NSCollectionView *)view).collectionViewLayout invalidateLayout];
    });
}

void DPSetPRStatus(NSView *subtitle, NSString *tab, NSString *status) {
    NSView *content = DPEnclosingView(subtitle.superview, DPDiaTabContentView);
    DPSet(content, &DPStatusKey, status);
    content.needsLayout = YES;
    if (!tab.length || [DPTallTabs containsObject:tab] == (status != nil)) return;
    if (status) [DPTallTabs addObject:tab];
    else [DPTallTabs removeObject:tab];
    DPInvalidateRows();
}

void DPResetPRRows(void) {
    [DPTallTabs removeAllObjects];
    DPInvalidateRows();
}

static NSString *DPTabAt(id source, NSIndexPath *path) {
    NSString *item = [((id (*)(id, SEL, id))objc_msgSend)(source, @selector(itemIdentifierForIndexPath:), path) description];
    NSRange open = [item rangeOfString:@".tab("];
    return open.location == NSNotFound || item.length < NSMaxRange(open) + 36 ? nil : [item substringWithRange:NSMakeRange(NSMaxRange(open), 36)];
}

static id DPObjectIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    return ivar ? object_getIvar(object, ivar) : nil;
}

static void DPLayout_prepareLayout(NSCollectionViewLayout *self, SEL _cmd) {
    DPCallOriginal(DPLayout_prepareLayout, self);
    if (!DPPullRequestRepo.on || !DPTallTabs.count) return DPSet(self, &DPEditsKey, nil);
    id diffable = self.collectionView.dataSource;
    id source = DPObjectIvar(diffable, "_impl");
    void *height = DPIvar(self, "contentHeight");
    if (![source respondsToSelector:@selector(itemIdentifierForIndexPath:)] || !height) return;
    // Dia's own IMP: Collapse Pinned Tabs hands out copies, and changing a copy changes nothing.
    NSArray *(*elements)(id, SEL, NSRect) = (void *)DPDiaIMP(objc_getClass(DPDiaTabListLayout), @selector(layoutAttributesForElementsInRect:));
    NSArray<NSCollectionViewLayoutAttributes *> *all = elements(self, @selector(layoutAttributesForElementsInRect:), NSMakeRect(-1e5, -1e5, 2e5, 1e7));
    NSMutableArray<NSCollectionViewLayoutAttributes *> *tall = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all)
        if (a.representedElementCategory == NSCollectionElementCategoryItem && [DPTallTabs containsObject:DPTabAt(source, a.indexPath)]) [tall addObject:a];
    // A prepare that kept the last geometry still has our heights in it.
    if (!tall.count) return DPSet(self, &DPEditsKey, nil);
    NSArray *last = DPGet(self, &DPAdjustedKey);
    if (last[0] == tall[0] && NSEqualRects([last[1] rectValue], tall[0].frame)) return;
    NSMutableArray<NSValue *> *rows = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in tall) [rows addObject:[NSValue valueWithRect:a.frame]];
    NSMutableArray *edits = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all) {
        NSRect frame = a.frame;
        for (NSValue *value in rows) {
            NSRect row = value.rectValue;
            if (NSMinY(a.frame) >= NSMaxY(row) - 0.5) frame.origin.y += DPExtra;
            else if (NSMinY(a.frame) <= NSMinY(row) + 0.5 && NSMaxY(a.frame) >= NSMaxY(row) - 0.5) frame.size.height += DPExtra;
        }
        if (a.representedElementCategory == NSCollectionElementCategoryItem)
            [edits addObject:@[a, @(frame.origin.y - a.frame.origin.y), @(frame.size.height - a.frame.size.height)]];
        a.frame = frame;
    }
    DPSet(self, &DPEditsKey, edits);
    *(double *)height += DPExtra * rows.count;
    DPSet(self, &DPAdjustedKey, @[tall[0], [NSValue valueWithRect:tall[0].frame]]);
}

// Collapse Pinned Tabs' hooks install before these and so run after: rows are read as the list shows them.
static NSArray<NSArray<NSValue *> *> *DPMoves(NSCollectionViewLayout *layout) {
    NSMutableArray *moves = [NSMutableArray new];
    for (NSArray *edit in DPGet(layout, &DPEditsKey)) {
        NSCollectionViewLayoutAttributes *shown = [layout layoutAttributesForItemAtIndexPath:[edit[0] indexPath]];
        if (!shown || shown.hidden || shown.alpha < 1) continue;  // A folded pinned row sits under the rows that follow.
        NSRect now = shown.frame, then = now;
        then.origin.y -= [edit[1] doubleValue];
        then.size.height -= [edit[2] doubleValue];
        [moves addObject:@[ [NSValue valueWithRect:now], [NSValue valueWithRect:then] ]];
    }
    return moves;
}

static id<NSDraggingInfo> DPDiaDrag(NSView *tabList, id<NSDraggingInfo> info) {
    NSCollectionView *list = (NSCollectionView *)DPFindView(tabList, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabListCollection); });
    NSArray *moves = DPPullRequestRepo.on ? DPMoves(list.collectionViewLayout) : nil;
    if (!moves.count) return info;
    NSPoint point = [list convertPoint:info.draggingLocation fromView:nil];
    point.y = DPTabListDiaY(moves, point.y);
    return DPDraggingInfoAt(info, [list convertPoint:point toView:nil]);
}

static NSDragOperation DPTabList_entered(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPCallOriginal(DPTabList_entered, self, DPDiaDrag(self, info)); }
static NSDragOperation DPTabList_updated(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPCallOriginal(DPTabList_updated, self, DPDiaDrag(self, info)); }
static BOOL DPTabList_prepare(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPCallOriginal(DPTabList_prepare, self, DPDiaDrag(self, info)); }
static BOOL DPTabList_perform(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPCallOriginal(DPTabList_perform, self, DPDiaDrag(self, info)); }

static NSView *DPPart(NSView *content, const char *name) {
    id part = DPObjectIvar(content, name);
    return [part isKindOfClass:NSView.class] ? part : nil;
}

static void DPContent_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContent_layout, self);
    NSString *status = DPPullRequestRepo.on ? DPGet(self, &DPStatusKey) : nil;
    NSView *title = DPPart(self, "$__lazy_storage_$_titleView"), *subtitle = DPPart(self, "subtitleView"), *icon = DPPart(self, "subtitleIconView");
    NSTextField *line = DPGet(self, &DPLineKey), *source = (NSTextField *)DPSubview(subtitle, DPDiaFeatheredLabel);
    BOOL tall = status && title && source && NSHeight(self.bounds) >= DPTabHeight + DPExtra - 1;
    line.hidden = !tall;
    if (!tall) return;
    if (!line) DPSet(self, &DPLineKey, line = [DPPRStatusLine labelWithString:@""]);
    if (line.superview != self) [self addSubview:line];
    line.font = source.font;
    line.textColor = source.textColor;
    line.lineBreakMode = NSLineBreakByTruncatingTail;
    line.stringValue = status;
    CGFloat lineHeight = NSHeight(subtitle.frame), bottom = round((NSHeight(self.bounds) - NSHeight(title.frame) - 2 * lineHeight) / 2);
    CGFloat x = NSMinX(subtitle.frame), width = NSWidth(self.bounds) - x - 8;
    CGFloat text = ceil([status sizeWithAttributes:@{NSFontAttributeName: line.font ?: [NSFont systemFontOfSize:11]}].width);
    line.frame = NSMakeRect(x, bottom, width, lineHeight);
    [subtitle setFrameOrigin:NSMakePoint(x, bottom + lineHeight)];
    [title setFrameOrigin:NSMakePoint(NSMinX(title.frame), bottom + 2 * lineHeight)];
    if (icon && !icon.hidden) [icon setFrameOrigin:NSMakePoint(x + MIN(text, width) + 5, bottom + (lineHeight - NSHeight(icon.frame)) / 2)];
}

void DPInstallPRRows(void) {
    DPTallTabs = [NSMutableSet new];
    DPHook(DPDiaTabListLayout, @selector(prepareLayout), (IMP)DPLayout_prepareLayout);
    DPHook(DPDiaTabContentView, @selector(layout), (IMP)DPContent_layout);
    DPHook(DPDiaTabList, @selector(draggingEntered:), (IMP)DPTabList_entered);
    DPHook(DPDiaTabList, @selector(draggingUpdated:), (IMP)DPTabList_updated);
    DPHook(DPDiaTabList, @selector(prepareForDragOperation:), (IMP)DPTabList_prepare);
    DPHook(DPDiaTabList, @selector(performDragOperation:), (IMP)DPTabList_perform);
}
