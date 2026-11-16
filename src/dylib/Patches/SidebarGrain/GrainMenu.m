#import "GrainSettings.h"

@interface DPGrainMenu : NSObject
@property (weak) NSView *sidebar;
@property NSPoint anchor;
@property NSString *profile, *space;
@property NSPopUpButton *picker;
@property NSButton *shown;
@property NSArray<NSView *> *rows;
- (void)editGrain:(NSMenuItem *)item;
- (void)chooseScope:(NSPopUpButton *)picker;
- (void)chooseTexture:(NSPopUpButton *)picker;
- (void)toggleShown:(NSButton *)button;
@end

static NSStackView *DPGrainLabeledRow(NSString *title, NSView *control) {
    NSTextField *label = [NSTextField labelWithString:title];
    [label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *row = [NSStackView stackViewWithViews:@[ label, control ]];
    row.distribution = NSStackViewDistributionFill;
    return row;
}

@implementation DPGrainMenu
- (void)chooseTexture:(NSPopUpButton *)picker {
    NSString *material = picker.selectedItem.representedObject;
    if (self.space) DPGrainSave(DPSidebarGrain.choice, material, self.space);
    else DPSetChoice(&DPSidebarGrain, material);
    DPRefreshSidebarGrain();
}

- (void)toggleShown:(NSButton *)button {
    DPGrainSave(DPSidebarGrain.key, @(button.state == NSControlStateValueOn), self.space);
    DPRefreshSidebarGrain();
}

- (void)reload {
    __weak DPGrainMenu *menu = self;
    DPGrainRowsFor(self.rows, self.space, ^{ [menu reload]; });
    NSString *material = DPGrainMaterial(self.space);
    for (NSMenuItem *texture in self.picker.menu.itemArray) if ([texture.representedObject isEqual:material]) [self.picker selectItem:texture];
    self.shown.hidden = !self.space;
    self.shown.state = DPGrainShown(self.space) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)chooseScope:(NSPopUpButton *)picker {
    self.space = picker.indexOfSelectedItem ? self.profile : nil;
    [self reload];
}

- (void)editGrain:(NSMenuItem *)item {
    NSView *sidebar = self.sidebar;
    if (!sidebar.window) return;
    static NSPopover *popover;
    [popover close];
    popover = [NSPopover new];
    popover.behavior = NSPopoverBehaviorTransient;
    self.profile = DPGrainSpaceOf(sidebar);
    self.space = DPGrainHasOverrides(self.profile) ? self.profile : nil;
    self.picker = [NSPopUpButton new];
    self.picker.menu = DPGrainTextureMenu();
    self.picker.controlSize = NSControlSizeSmall;
    self.picker.target = self;
    self.picker.action = @selector(chooseTexture:);
    NSStackView *texture = DPGrainLabeledRow(@"Texture", self.picker);
    self.shown = [NSButton checkboxWithTitle:@"Show grain in this profile" target:self action:@selector(toggleShown:)];
    self.rows = DPGrainRows();
    NSMutableArray<NSView *> *views = [@[ texture, self.shown ] arrayByAddingObjectsFromArray:self.rows].mutableCopy;
    if (self.profile) {
        NSPopUpButton *scope = [NSPopUpButton new];
        [scope addItemsWithTitles:@[ @"All Profiles", @"This Profile" ]];
        [scope selectItemAtIndex:self.space != nil];
        scope.controlSize = NSControlSizeSmall;
        scope.target = self;
        scope.action = @selector(chooseScope:);
        [views insertObject:DPGrainLabeledRow(@"Apply to", scope) atIndex:0];
    }
    [self reload];
    NSStackView *rows = [NSStackView stackViewWithViews:views];
    rows.orientation = NSUserInterfaceLayoutOrientationVertical;
    rows.alignment = NSLayoutAttributeLeading;
    rows.spacing = 12;
    rows.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);
    for (NSView *row in rows.arrangedSubviews) [row.widthAnchor constraintEqualToAnchor:rows.widthAnchor constant:-28].active = YES;
    [rows.widthAnchor constraintEqualToConstant:300].active = YES;
    NSViewController *controller = [NSViewController new];
    controller.view = rows;
    controller.representedObject = self;  // Controls' targets are weak: this keeps the menu alive.
    popover.contentViewController = controller;
    BOOL horizontal = DPIsKind(sidebar, DPDiaTabStrip);
    NSRect anchor = horizontal ? NSMakeRect(self.anchor.x, self.anchor.y, 1, 1) :
        NSMakeRect(NSMaxX(sidebar.bounds) - 1, self.anchor.y, 1, 1);
    NSRectEdge edge = horizontal ? (sidebar.isFlipped ? NSRectEdgeMaxY : NSRectEdgeMinY) : NSRectEdgeMaxX;
    [popover showRelativeToRect:anchor ofView:sidebar preferredEdge:edge];
}
@end

NSEvent *DPGrainRightClick(NSEvent *event) {
    if (!DPSidebarGrain.on || !event.window) return event;
    for (NSView *sidebar in DPGrainHosts) {
        if (sidebar.window != event.window || sidebar.hiddenOrHasHiddenAncestor ||
            !DPGrainHostAvailable(sidebar)) continue;
        NSPoint point = [sidebar convertPoint:event.locationInWindow fromView:nil];
        if (!NSPointInRect(point, DPGrainHostBounds(sidebar))) continue;
        NSView *hit = [sidebar hitTest:[sidebar convertPoint:point toView:sidebar.superview]];
        NSCollectionView *collection = nil;
        for (NSView *view = hit; view && view != sidebar && !collection; view = view.superview)
            if ([view isKindOfClass:NSCollectionView.class]) collection = (NSCollectionView *)view;
        BOOL horizontal = DPIsKind(sidebar, DPDiaTabStrip);
        if (horizontal && ([hit isKindOfClass:NSControl.class] ||
            [hit.accessibilityRole isEqual:NSAccessibilityButtonRole] ||
            [hit.accessibilityRole isEqual:NSAccessibilityRadioButtonRole])) return event;
        if (!collection && hit != sidebar && (!horizontal || !hit ||
            NSHeight([sidebar convertRect:hit.bounds fromView:hit]) < NSHeight(sidebar.bounds) - 0.5)) return event;
        if ([collection indexPathForItemAtPoint:[collection convertPoint:event.locationInWindow fromView:nil]]) return event;
        NSMenu *menu = nil;
        if (horizontal) {
            for (NSView *view = hit; view && view != sidebar.superview && !menu; view = view.superview)
                menu = [view menuForEvent:event];
            if (!menu || [menu indexOfItemWithTitle:@"Show Tabs in Sidebar"] < 0) return event;
        } else menu = [collection menuForEvent:event] ?: [sidebar menuForEvent:event] ?: [NSMenu new];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Edit Sidebar Grain…" action:@selector(editGrain:) keyEquivalent:@""];
        DPGrainMenu *target = [DPGrainMenu new];
        target.sidebar = sidebar;
        target.anchor = point;
        item.target = target;
        NSInteger index = [menu indexOfItemWithTitle:@"Auto-Hide Tabs"];
        if (index >= 0) {
            NSMenuItem *autoHide = [menu itemAtIndex:index];
            NSImage *sidebarIcon = [menu itemWithTitle:@"Show Tabs in Sidebar"].image;
            item.indentationLevel = autoHide.indentationLevel;
            NSSize iconSize = autoHide.image ? autoHide.image.size : sidebarIcon.size;
            if (iconSize.width > 0) item.image = [[NSImage alloc] initWithSize:iconSize];
        }
        if (index < 0) index = [menu indexOfItemWithTitle:@"Show Tabs in Sidebar"];
        index = index >= 0 ? index + 1 : MAX(0, [menu indexOfItemWithTitle:@"Close All Tabs"]);
        [menu insertItem:item atIndex:index];
        [NSMenu popUpContextMenu:menu withEvent:event forView:sidebar];
        [menu removeItem:item];
        return nil;
    }
    return event;
}
