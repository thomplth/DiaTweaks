#import "StdPatch/StdPatch.h"

extern DPPatch DPHideSleepingTabs;

static id DPState(id viewModel) { return DPSwiftValue(DPSwiftValue(viewModel, @"stateSubject"), @"currentValue"); }

static NSArray<NSString *> *DPSwitcherItems(id viewModel) {
    return DPUUIDsIn([DPSwiftValue(DPState(viewModel), @"items") description]);
}

static NSSet<NSString *> *DPSleepingTabs(id viewModel) {
    NSDictionary *tabs = DPSwiftValue(DPSwiftValue(viewModel, @"delegate"), @"recentTabControllers");
    NSMutableSet *sleeping = [NSMutableSet new];
    for (id tab in tabs) {
        NSString *state = [DPState(DPSwiftValue(tabs[tab], @"viewModel")) description];
        if (state && ![state containsString:@"snapshot: Optional("]) [sleeping addObject:[tab description]];
    }
    return sleeping;
}

static NSArray<NSNumber *> *DPShownItems(id list) {
    id viewModel = DPSwiftValue(list, @"viewModel");
    NSSet *sleeping = DPHideSleepingTabs.on ? DPSleepingTabs(viewModel) : nil;
    NSMutableArray *shown = [NSMutableArray new];
    [DPSwitcherItems(viewModel) enumerateObjectsUsingBlock:^(NSString *tab, NSUInteger i, BOOL *stop) {
        if (![sleeping containsObject:tab]) [shown addObject:@(i)];
    }];
    return shown.count ? shown : nil;
}

static NSIndexPath *DPDiaIndexPath(id list, NSIndexPath *path) {
    NSArray<NSNumber *> *shown = DPShownItems(list);
    return shown && path.item < (NSInteger)shown.count ? [NSIndexPath indexPathForItem:shown[path.item].integerValue inSection:path.section] : path;
}

static void DPWatchSwitcherSize(id list);

static NSInteger DPList_count(id self, SEL _cmd, NSCollectionView *view, NSInteger section) {
    DPWatchSwitcherSize(self);
    NSArray *shown = DPShownItems(self);
    return shown ? (NSInteger)shown.count : DPCallOriginal(DPList_count, self, view, section);
}

// Dia makes the cell at its own index, which can be past the end of the shorter grid.
static NSIndexPath *DPShownPath;

static NSCollectionViewItem *DPList_item(id self, SEL _cmd, NSCollectionView *view, NSIndexPath *path) {
    DPShownPath = path;
    NSCollectionViewItem *item = DPCallOriginal(DPList_item, self, view, DPDiaIndexPath(self, path));
    DPShownPath = nil;
    return item;
}

static NSCollectionViewItem *DPGrid_makeItem(NSCollectionView *self, SEL _cmd, NSUserInterfaceItemIdentifier identifier, NSIndexPath *path) {
    return DPCallOriginal(DPGrid_makeItem, self, identifier, DPShownPath ?: path);
}

static NSSize DPList_size(id self, SEL _cmd, NSCollectionView *view, NSCollectionViewLayout *layout, NSIndexPath *path) {
    return DPCallOriginal(DPList_size, self, view, layout, DPDiaIndexPath(self, path));
}

static void DPList_select(id self, SEL _cmd, NSCollectionView *view, NSSet<NSIndexPath *> *paths) {
    NSMutableSet *dia = [NSMutableSet new];
    for (NSIndexPath *path in paths) [dia addObject:DPDiaIndexPath(self, path)];
    DPCallOriginal(DPList_select, self, view, dia);
}

static const CGFloat DPSwitcherChrome = 152;  // Shadow margin and grid inset, both sides.
static char DPWatchedKey;
static BOOL DPFitting;

static void DPFitSwitcherSize(NSLayoutConstraint *size, id list) {
    NSCollectionView *grid = DPSwiftValue(list, @"collectionView");
    NSArray *shown = DPHideSleepingTabs.on ? DPShownItems(list) : nil;
    if (DPFitting || !grid || !shown) return;
    NSSize cell = [list collectionView:grid layout:grid.collectionViewLayout sizeForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    BOOL width = size.firstAttribute == NSLayoutAttributeWidth;
    CGFloat step = width ? cell.width : cell.height;
    if (step <= 0) return;
    NSInteger dia = MAX(1, lround((size.constant - DPSwitcherChrome) / step));
    NSInteger columns = MIN((NSInteger)shown.count, dia);
    NSInteger fit = width ? columns : MIN(dia, ((NSInteger)shown.count + columns - 1) / columns);
    DPFitting = YES;
    size.constant = DPSwitcherChrome + fit * step;
    DPFitting = NO;
}

@interface DPSwitcherSizeWatch : NSObject
@property (nonatomic, weak) id list;
@end

@implementation DPSwitcherSizeWatch
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(NSLayoutConstraint *)size change:(NSDictionary *)change context:(void *)context {
    DPFitSwitcherSize(size, self.list);
}
@end

static void DPWatchSwitcherSize(id list) {
    NSView *content = [list view];
    for (NSLayoutConstraint *size in content.constraints) {
        BOOL dimension = size.firstAttribute == NSLayoutAttributeWidth || size.firstAttribute == NSLayoutAttributeHeight;
        if (size.firstItem != content || size.secondItem || !dimension || DPGet(size, &DPWatchedKey)) continue;
        DPSwitcherSizeWatch *watch = [DPSwitcherSizeWatch new];
        watch.list = list;
        [size addObserver:watch forKeyPath:@"constant" options:0 context:NULL];
        DPSet(size, &DPWatchedKey, watch);
        dispatch_async(dispatch_get_main_queue(), ^{ DPFitSwitcherSize(size, list); });  // Not mid-layout.
    }
}

static int DPStepsLeft;
static const int64_t DPOwnKey = 0x44505353;

static void DPStepPastSleeping(void);

static void DPStepSoon(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPStepPastSleeping(); });
}

static void DPStepPastSleeping(void) {
    if (!DPHideSleepingTabs.on) {
        DPStepsLeft = 0;
        return;
    }
    NSWindowController *switcher = DPOpenTabSwitcher();
    id viewModel = DPSwiftValue(switcher, @"viewModel");
    NSString *focused = [DPSwiftValue(DPState(viewModel), @"focusedItemID") description];
    BOOL sleeping = focused && [DPSleepingTabs(viewModel) containsObject:focused];
    if (sleeping) {
        NSEventModifierFlags mods = NSEventModifierFlagControl | (NSEvent.modifierFlags & NSEventModifierFlagShift);
        NSEvent *key = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:NSProcessInfo.processInfo.systemUptime
                                    windowNumber:switcher.window.windowNumber context:nil characters:@"\t" charactersIgnoringModifiers:@"\t" isARepeat:NO keyCode:48];
        CGEventRef tagged = key.CGEvent ? CGEventCreateCopy(key.CGEvent) : NULL;
        if (tagged) CGEventSetIntegerValueField(tagged, kCGEventSourceUserData, DPOwnKey);
        [NSApp postEvent:tagged ? [NSEvent eventWithCGEvent:tagged] : key atStart:NO];
        if (tagged) CFRelease(tagged);
    }
    DPStepsLeft = focused && !sleeping ? 0 : DPStepsLeft - 1;
    if (DPStepsLeft) DPStepSoon();
}

static void DPInstallHideSleepingTabs(void) {
    DPHook(DPDiaTabSwitcherList, @selector(collectionView:numberOfItemsInSection:), (IMP)DPList_count);
    DPHook(DPDiaTabSwitcherList, @selector(collectionView:itemForRepresentedObjectAtIndexPath:), (IMP)DPList_item);
    DPHook(DPDiaTabSwitcherList, @selector(collectionView:layout:sizeForItemAtIndexPath:), (IMP)DPList_size);
    DPHook(DPDiaTabSwitcherList, @selector(collectionView:didSelectItemsAtIndexPaths:), (IMP)DPList_select);
    DPHookClass(NSCollectionView.class, @selector(makeItemWithIdentifier:forIndexPath:), (IMP)DPGrid_makeItem);
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        BOOL own = event.CGEvent && CGEventGetIntegerValueField(event.CGEvent, kCGEventSourceUserData) == DPOwnKey;
        if (!own && DPHideSleepingTabs.on && event.keyCode == 48 && (event.modifierFlags & NSEventModifierFlagControl)) {
            BOOL running = DPStepsLeft > 0;
            DPStepsLeft = 20;
            if (!running) DPStepSoon();
        }
        return event;
    }];
}

DP_PATCH(DPHideSleepingTabs) {
    .key = @"hideSleepingTabs",
    .order = 86,
    .title = @"Hide Sleeping Tabs",
    .detail = @"Leave tabs with nothing loaded, like a pinned tab you closed, out of the tab switcher (⌃⇥) instead of showing them as empty pictures.",
    .symbol = @"moon.zzz.fill",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaTabSwitcher, DPDiaTabSwitcherList),
    .install = DPInstallHideSleepingTabs,
};
