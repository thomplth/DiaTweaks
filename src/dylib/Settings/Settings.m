#import "Settings.h"

static char DPSettingsKey, DPSearchItemKey;

// Dia's cell lookup traps past its own rows, so it never sees our indexes.
typedef NS_ENUM(NSInteger, DPSidebarRow) { DPDiaRow = -1, DPDividerRow, DPHomeRow, DPPatchesRow, DPOurRowCount };

static DPSidebarRow DPOurRow(NSTableView *table, NSInteger row) {
    NSInteger ours = row - (table.numberOfRows - DPOurRowCount);
    return row >= 0 && ours >= 0 ? ours : DPDiaRow;
}

static void DPRemoveDiaPaneItems(NSToolbar *toolbar) {
    void **slot = DPIvar(toolbar.delegate, "paneToolbarItems");
    // A Swift array of objects is its storage, an NSArray; one bridged from Objective-C is tagged and left alone.
    if (!slot || !*slot || ((uintptr_t)*slot & 0xC000000000000001)) return;
    NSArray<NSToolbarItem *> *paneItems = (__bridge NSArray *)*slot;
    NSSet *identifiers = [NSSet setWithArray:[paneItems valueForKey:@"itemIdentifier"]];
    for (NSInteger i = toolbar.items.count - 1; i >= 0; i--)
        if ([identifiers containsObject:toolbar.items[i].itemIdentifier]) [toolbar removeItemAtIndex:i];
}

@interface DPSettings : NSObject
@property (nonatomic, weak) NSTableView *table;
@property (nonatomic, weak) NSTextField *title;
@property (nonatomic, copy) NSString *originalTitle, *shownTitle;
@property (nonatomic, strong) DPPaneView *home, *patches;
@property (nonatomic, weak) DPPaneView *shown;
@property (nonatomic) NSWindowStyleMask mask;
@property (nonatomic) NSWindowCollectionBehavior behavior;
@property (nonatomic) NSSize minSize, maxSize;
@property (nonatomic) CGFloat fixedHeight, dividerHeight;
@property (nonatomic) BOOL backWasEnabled, watchingHeight;
@end

static CGFloat const DPDividerMinHeight = 17;

static __weak DPPaneView *DPShownPane;

@implementation DPSettings

+ (DPSettings *)forTable:(NSTableView *)table {
    DPSettings *settings = DPGet(table, &DPSettingsKey);
    if (settings) return settings;
    settings = [DPSettings new];
    settings.table = table;
    settings.dividerHeight = DPDividerMinHeight;
    DPSet(table, &DPSettingsKey, settings);
    return settings;
}

- (CGFloat)fittedDividerHeight {
    NSTableView *table = self.table;
    NSClipView *clip = table.enclosingScrollView.contentView;
    if (!clip || table.numberOfRows < DPOurRowCount) return DPDividerMinHeight;
    if (!self.watchingHeight) {
        self.watchingHeight = YES;
        clip.postsFrameChangedNotifications = clip.postsBoundsChangedNotifications = YES;
        for (NSNotificationName name in @[NSViewFrameDidChangeNotification, NSViewBoundsDidChangeNotification])
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fitDivider) name:name object:clip];
    }
    CGFloat others = (table.numberOfRows - 1) * (table.rowHeight + table.intercellSpacing.height);
    CGFloat spare = NSHeight(clip.bounds) - clip.contentInsets.top - clip.contentInsets.bottom - others - 12;
    return self.dividerHeight = MAX(DPDividerMinHeight, floor(spare));
}

- (void)fitDivider {
    CGFloat before = self.dividerHeight;
    if ([self fittedDividerHeight] == before) return;
    NSInteger divider = self.table.numberOfRows - DPOurRowCount + DPDividerRow;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0;
        [self.table noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndex:divider]];
    }];
}

- (DPPaneView *)paneFor:(DPSidebarRow)row {
    if (row == DPHomeRow) return self.home ?: (self.home = [[DPPaneView alloc] initWithTitle:@"Home" content:[DPHomeView new]]);
    if (row == DPPatchesRow) return self.patches ?: (self.patches = [[DPPaneView alloc] initWithTitle:@"Patches" content:[DPOverviewView new]]);
    return nil;
}

- (void)preparePane:(DPPaneView *)pane {
    NSView *detail = ((NSSplitViewController *)self.table.window.contentViewController).splitViewItems.lastObject.viewController.view;
    if (!detail || pane.superview == detail) return;
    pane.hidden = YES;
    pane.frame = detail.bounds;
    pane.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [detail addSubview:pane positioned:NSWindowAbove relativeTo:nil];
    [pane layoutSubtreeIfNeeded];
}

- (void)showPane:(DPPaneView *)pane {
    NSWindow *window = self.table.window;
    [self preparePane:pane];
    if (!pane.superview || pane == self.shown) return;
    [self closeShownPane];
    pane.hidden = NO;
    if ([pane.content respondsToSelector:@selector(refresh)]) [pane.content refresh];
    self.shown = DPShownPane = pane;
    __weak DPSettings *weakSelf = self;
    pane.titleChanged = ^(NSString *title, BOOL canGoBack) {
        weakSelf.title.stringValue = weakSelf.shownTitle = title;
        [weakSelf borrowBack:canGoBack];
    };
    [self allowResizing:YES];

    NSToolbar *toolbar = window.toolbar;
    DPRemoveDiaPaneItems(toolbar);
    if (pane.searchItem) {
        DPSet(toolbar, &DPSearchItemKey, pane.searchItem);
        [toolbar insertItemWithItemIdentifier:NSToolbarFlexibleSpaceItemIdentifier atIndex:toolbar.items.count];
        [toolbar insertItemWithItemIdentifier:DPSearchItemIdentifier atIndex:toolbar.items.count];
    }

    for (NSToolbarItem *item in toolbar.items)
        if ([item.itemIdentifier isEqualToString:@"PreferencesPaneTitle"])
            self.title = (NSTextField *)DPFindView(item.view, ^BOOL(NSView *v) { return [v isKindOfClass:NSTextField.class]; });
    self.originalTitle = self.title.stringValue;
    self.title.stringValue = self.shownTitle = pane.title;
}

- (void)hidePane {
    [self closeShownPane];
    [self allowResizing:NO];
}

- (void)closeShownPane {
    DPPaneView *pane = self.shown;
    if (!pane) return;
    pane.hidden = YES;
    NSToolbar *toolbar = self.table.window.toolbar;
    NSUInteger index = pane.searchItem ? [toolbar.items indexOfObject:pane.searchItem] : NSNotFound;
    if (index != NSNotFound) {
        [toolbar removeItemAtIndex:index];
        if (index > 0 && [toolbar.items[index - 1].itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) [toolbar removeItemAtIndex:index - 1];
    }
    NSString *shown = self.title.stringValue;
    if (pane.showsPage) [self borrowBack:NO];
    [pane reset];
    self.shown = DPShownPane = nil;
    if ([shown isEqualToString:self.shownTitle]) self.title.stringValue = self.originalTitle;
}

- (void)borrowBack:(BOOL)borrow {
    NSToolbarItem *back = [self backItem];
    if (borrow) self.backWasEnabled = back.enabled;
    back.enabled = borrow || self.backWasEnabled;
}

- (NSToolbarItem *)backItem {
    for (NSToolbarItem *item in self.table.window.toolbar.items)
        if ([item.itemIdentifier isEqualToString:@"PreferencesNavigateBack"]) return item;
    return nil;
}

- (void)allowResizing:(BOOL)allow {
    NSWindow *window = self.table.window;
    if (allow == (self.fixedHeight > 0)) return;
    if (allow) {
        self.mask = window.styleMask;
        self.behavior = window.collectionBehavior;
        self.minSize = window.contentMinSize;
        self.maxSize = window.contentMaxSize;
        self.fixedHeight = window.frame.size.height;
        CGFloat width = window.contentLayoutRect.size.width;
        window.styleMask |= NSWindowStyleMaskResizable;
        window.collectionBehavior = (window.collectionBehavior & ~NSWindowCollectionBehaviorFullScreenPrimary) | NSWindowCollectionBehaviorFullScreenNone;
        [window standardWindowButton:NSWindowZoomButton].enabled = NO;
        window.contentMinSize = NSMakeSize(width, 400);
        window.contentMaxSize = NSMakeSize(width, CGFLOAT_MAX);
        return;
    }
    NSRect frame = window.frame;
    window.styleMask = self.mask;
    window.collectionBehavior = self.behavior;
    window.contentMinSize = self.minSize;
    window.contentMaxSize = self.maxSize;
    [window setFrame:NSMakeRect(frame.origin.x, NSMaxY(frame) - self.fixedHeight, frame.size.width, self.fixedHeight) display:YES];
    self.fixedHeight = 0;
}
@end

static NSView *DPDividerCell(NSTableView *table) {
    NSTableCellView *cell = [table makeViewWithIdentifier:@"DiaPatchesDivider" owner:nil];
    if (cell) return cell;
    cell = [NSTableCellView new];
    cell.identifier = @"DiaPatchesDivider";
    NSBox *line = [NSBox new];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [line.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
        [line.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
        [line.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-floor(DPDividerMinHeight / 2)],
    ]];
    return cell;
}

static NSView *DPLinkCell(NSTableView *table, NSString *title, NSString *symbol) {
    NSString *identifier = [@"DiaPatchesCell." stringByAppendingString:title];
    NSTableCellView *cell = [table makeViewWithIdentifier:identifier owner:nil];
    if (cell) return cell;
    cell = [objc_getClass(DPDiaSettingsSidebarCell) new];
    cell.identifier = identifier;
    cell.textField.stringValue = title;
    cell.imageView.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    return cell;
}

static NSInteger DPSidebar_numberOfRows(id self, SEL _cmd, NSTableView *table) {
    return DPCallOriginal(DPSidebar_numberOfRows, self, table) + DPOurRowCount;
}

static NSView *DPSidebar_viewForRow(id self, SEL _cmd, NSTableView *table, NSTableColumn *column, NSInteger row) {
    DPSidebarRow ours = DPOurRow(table, row);
    if (ours == DPDiaRow) return DPCallOriginal(DPSidebar_viewForRow, self, table, column, row);
    DPSettings *settings = [DPSettings forTable:table];
    if (ours == DPDividerRow) return DPDividerCell(table);
    dispatch_async(dispatch_get_main_queue(), ^{ [settings preparePane:[settings paneFor:ours]]; });
    return ours == DPHomeRow ? DPLinkCell(table, @"Home", @"house") : DPLinkCell(table, @"Patches", @"wand.and.stars");
}

static void DPSidebar_selectionDidChange(id self, SEL _cmd, NSNotification *notification) {
    NSTableView *table = notification.object;
    DPSettings *settings = [DPSettings forTable:table];
    DPPaneView *pane = [settings paneFor:DPOurRow(table, table.selectedRow)];
    if (pane) return [settings showPane:pane];
    [settings hidePane];
    DPCallOriginal(DPSidebar_selectionDidChange, self, notification);
}

static BOOL DPSidebar_shouldSelectRow(id self, SEL _cmd, NSTableView *table, NSInteger row) {
    return DPOurRow(table, row) != DPDividerRow;
}

static CGFloat DPSidebar_heightOfRow(id self, SEL _cmd, NSTableView *table, NSInteger row) {
    return DPOurRow(table, row) == DPDividerRow ? [[DPSettings forTable:table] fittedDividerHeight] : table.rowHeight;
}

static NSToolbarItem *DPSettings_toolbarItem(id self, SEL _cmd, NSToolbar *toolbar, NSToolbarItemIdentifier identifier, BOOL willInsert) {
    if ([identifier isEqualToString:DPSearchItemIdentifier]) return DPGet(toolbar, &DPSearchItemKey);
    return DPCallOriginal(DPSettings_toolbarItem, self, toolbar, identifier, willInsert);
}

static void DPSettings_handleBack(id self, SEL _cmd) {
    if (DPShownPane.showsPage) return [DPShownPane goBack];
    DPCallOriginal(DPSettings_handleBack, self);
}

static NSEvent *DPSettings_findKey(NSEvent *event) {
    DPPaneView *pane = DPShownPane;
    NSSearchToolbarItem *item = pane.searchItem;
    if (!item || pane.hidden || event.window != pane.window || !event.window.isKeyWindow || DPShortcutRecording()) return event;
    NSEventModifierFlags mods = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask & ~(NSEventModifierFlagCapsLock | NSEventModifierFlagNumericPad);
    if (mods != NSEventModifierFlagCommand || !DPEventIsKey(event, @"f")) return event;
    [item beginSearchInteraction];
    [item.searchField selectText:nil];
    return nil;
}

static void DPAddSidebarMethod(SEL sel, IMP imp) {
    const char *types = protocol_getMethodDescription(@protocol(NSTableViewDelegate), sel, NO, YES).types;
    if (!class_addMethod(objc_getClass(DPDiaSettingsSidebar), sel, imp, types))
        NSLog(@"DiaPatches: can't add -[%s %@]; Dia may implement it now", DPDiaSettingsSidebar, NSStringFromSelector(sel));
}

void DPInstallSettings(void) {
    DPInstallPreviews();
    DPHook(DPDiaSettingsController, @selector(handleBack), (IMP)DPSettings_handleBack);
    DPHook(DPDiaSettingsSidebar, @selector(numberOfRowsInTableView:), (IMP)DPSidebar_numberOfRows);
    DPHook(DPDiaSettingsSidebar, @selector(tableView:viewForTableColumn:row:), (IMP)DPSidebar_viewForRow);
    DPHook(DPDiaSettingsSidebar, @selector(tableViewSelectionDidChange:), (IMP)DPSidebar_selectionDidChange);
    DPAddSidebarMethod(@selector(tableView:shouldSelectRow:), (IMP)DPSidebar_shouldSelectRow);
    DPAddSidebarMethod(@selector(tableView:heightOfRow:), (IMP)DPSidebar_heightOfRow);
    DPHook(DPDiaSettingsController, @selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:), (IMP)DPSettings_toolbarItem);
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPSettings_findKey(event); }];
}
