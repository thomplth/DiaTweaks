#import "Patches/CompactTabRows/CompactTabRows.h"

extern DPPatch DPCompactTabRows;

static const CGFloat DPOldRowHeight = 37;

// The attributes Dia keeps, not the moved copies Collapse Pinned Tabs hands out.
static NSArray<NSCollectionViewLayoutAttributes *> *DPKeptAttributes(NSCollectionViewLayout *layout) {
    NSArray *(*elements)(id, SEL, NSRect) = (void *)DPDiaIMP(objc_getClass(DPDiaTabListLayout), @selector(layoutAttributesForElementsInRect:));
    return elements(layout, @selector(layoutAttributesForElementsInRect:), NSMakeRect(-1e5, -1e5, 2e5, 1e7));
}

static CGFloat DPRowHeight(NSArray<NSCollectionViewLayoutAttributes *> *all) {
    NSCountedSet<NSNumber *> *heights = [NSCountedSet set];
    for (NSCollectionViewLayoutAttributes *a in all)
        if (a.representedElementCategory == NSCollectionElementCategoryItem) [heights addObject:@(round(NSHeight(a.frame) * 2) / 2)];
    NSNumber *row = nil;
    for (NSNumber *each in heights) if (!row || [heights countForObject:each] > [heights countForObject:row]) row = each;
    return row.doubleValue;
}

static char DPMovesKey;

static void DPLayout_prepareLayout(NSCollectionViewLayout *self, SEL _cmd) {
    DPCallOriginal(DPLayout_prepareLayout, self);
    if (!DPCompactTabRows.on) return DPSet(self, &DPMovesKey, nil);
    double *contentHeight = DPIvar(self, "contentHeight");  // Dia's layout hands out the attributes it keeps, so changing them changes it.
    NSArray<NSCollectionViewLayoutAttributes *> *all = DPKeptAttributes(self);
    CGFloat height = DPRowHeight(all), cut = height - DPOldRowHeight;
    if (!contentHeight || cut < 0.5) return;
    NSMutableArray<NSValue *> *rows = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all)
        if (a.representedElementCategory == NSCollectionElementCategoryItem && NSHeight(a.frame) >= height - 0.5)
            [rows addObject:[NSValue valueWithRect:NSMakeRect(NSMinX(a.frame), NSMinY(a.frame), NSWidth(a.frame), height)]];
    NSMutableArray<NSArray<NSValue *> *> *moves = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all) {
        NSRect frame = a.frame;
        for (NSValue *value in rows) {
            NSRect row = value.rectValue;
            // A folder's first row starts 3 pt up into its header.
            if (NSMaxY(row) <= NSMinY(a.frame) + 3.5) frame.origin.y -= cut;
            else if (NSMinY(row) >= NSMinY(a.frame) - 0.5 && NSMaxY(row) <= NSMaxY(a.frame) + 0.5) frame.size.height -= cut;
        }
        if (a.representedElementCategory == NSCollectionElementCategoryItem)
            [moves addObject:@[ [NSValue valueWithRect:frame], [NSValue valueWithRect:a.frame] ]];
        a.frame = frame;
    }
    *contentHeight -= cut * rows.count;
    DPSet(self, &DPMovesKey, moves);
}

// Collapse Pinned's hooks install after these, so run first and have already taken its header out of the point.
CGFloat DPTabListDiaY(NSArray<NSArray<NSValue *> *> *moves, CGFloat y) {
    NSArray<NSValue *> *inside = nil, *above = nil;
    for (NSArray<NSValue *> *move in moves) {
        NSRect now = move[0].rectValue;
        if (y >= NSMinY(now) && y < NSMaxY(now) && (!inside || NSHeight(now) < NSHeight(inside[0].rectValue))) inside = move;
        if (NSMaxY(now) <= y && (!above || NSMaxY(now) > NSMaxY(above[0].rectValue))) above = move;
    }
    if (inside) {
        NSRect now = inside[0].rectValue, then = inside[1].rectValue;
        return NSMinY(then) + (y - NSMinY(now)) * NSHeight(then) / NSHeight(now);
    }
    return above ? y - NSMaxY(above[0].rectValue) + NSMaxY(above[1].rectValue) : y;
}

@interface DPCompactDrag : NSProxy
@property (nonatomic, strong) id<NSDraggingInfo> info;
@property (nonatomic) NSPoint location;
@end

@implementation DPCompactDrag
- (NSPoint)draggingLocation { return self.location; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [(NSObject *)self.info methodSignatureForSelector:sel]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.info]; }
- (BOOL)respondsToSelector:(SEL)sel { return [(NSObject *)self.info respondsToSelector:sel]; }
- (BOOL)conformsToProtocol:(Protocol *)protocol { return [(NSObject *)self.info conformsToProtocol:protocol]; }
- (BOOL)isKindOfClass:(Class)cls { return [(NSObject *)self.info isKindOfClass:cls]; }
@end

id<NSDraggingInfo> DPDraggingInfoAt(id<NSDraggingInfo> info, NSPoint location) {
    DPCompactDrag *drag = [DPCompactDrag alloc];
    drag.info = info;
    drag.location = location;
    return (id<NSDraggingInfo>)drag;
}

static id<NSDraggingInfo> DPDiaDrag(NSView *tabList, id<NSDraggingInfo> info) {
    NSCollectionView *list = (NSCollectionView *)DPFindView(tabList, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabListCollection); });
    NSArray *moves = DPGet(list.collectionViewLayout, &DPMovesKey);
    if (!moves) return info;
    NSPoint point = [list convertPoint:info.draggingLocation fromView:nil];
    point.y = DPTabListDiaY(moves, point.y);
    return DPDraggingInfoAt(info, [list convertPoint:point toView:nil]);
}

static NSDragOperation DPTabList_entered(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPCallOriginal(DPTabList_entered, self, DPDiaDrag(self, info)); }
static NSDragOperation DPTabList_updated(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPCallOriginal(DPTabList_updated, self, DPDiaDrag(self, info)); }
static BOOL DPTabList_prepare(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPCallOriginal(DPTabList_prepare, self, DPDiaDrag(self, info)); }
static BOOL DPTabList_perform(NSView *self, SEL _cmd, id<NSDraggingInfo> info) { return DPCallOriginal(DPTabList_perform, self, DPDiaDrag(self, info)); }

static void DPGroupCell_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGroupCell_layout, self);
    if (!DPCompactTabRows.on || NSHeight(self.bounds) <= DPOldRowHeight + 0.5) return;
    for (NSView *header in self.subviews) {
        CGFloat extra = NSHeight(header.frame) - (DPOldRowHeight - 3);
        if (!DPIsKind(header, DPDiaTabGroupBackground) && extra > 0.5 && extra < 4.5 && NSMinY(header.frame) > 1)
            [header setFrameOrigin:NSMakePoint(NSMinX(header.frame), NSMinY(header.frame) - extra / 2)];
    }
}

static void DPInstallCompactTabRows(void) {
    DPHook(DPDiaTabListLayout, @selector(prepareLayout), (IMP)DPLayout_prepareLayout);
    DPHook(DPDiaTabGroupCell, @selector(layout), (IMP)DPGroupCell_layout);
    DPHook(DPDiaTabList, @selector(draggingEntered:), (IMP)DPTabList_entered);
    DPHook(DPDiaTabList, @selector(draggingUpdated:), (IMP)DPTabList_updated);
    DPHook(DPDiaTabList, @selector(prepareForDragOperation:), (IMP)DPTabList_prepare);
    DPHook(DPDiaTabList, @selector(performDragOperation:), (IMP)DPTabList_perform);
}

static void DPApplyCompactTabRows(DPPatch *patch) {
    for (NSView *view in DPFindViews(DPDiaTabListCollection)) [((NSCollectionView *)view).collectionViewLayout invalidateLayout];
}

static NSString *DPVerifyCompactTabRows(DPPatch *patch) {
    for (NSView *view in DPFindViews(DPDiaTabListCollection)) {
        NSArray *all = DPKeptAttributes(((NSCollectionView *)view).collectionViewLayout);
        if (patch->on && DPRowHeight(all) > DPOldRowHeight + 0.5) return @"tab rows are taller than 37 pt";
    }
    return nil;
}

DP_PATCH(DPCompactTabRows) {
    .key = @"compactTabRows",
    .order = 77,
    .section = @"Sidebar & Tab Bar",
    .title = @"Compact Tab Rows",
    .detail = @"Make the sidebar's tabs and folders as short as before Dia 1.57, so more fit.",
    .symbol = @"rectangle.compress.vertical",
    .tint = @"systemTealColor",
    .classes = DPClasses(DPDiaTabListLayout, DPDiaTabListCollection, DPDiaTabList, DPDiaTabGroupCell, DPDiaTabGroupBackground),
    .install = DPInstallCompactTabRows,
    .apply = DPApplyCompactTabRows,
    .verify = DPVerifyCompactTabRows,
};
