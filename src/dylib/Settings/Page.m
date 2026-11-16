#import "Settings.h"

static char DPChoicePatchKey;

static NSArray<NSView *> *DPRowsOf(DPPatch *patch) {
    NSArray<NSView *> *rows = patch->rows ? patch->rows() : @[];
    return patch->shortcut ? [@[ DPShortcutRow(patch) ] arrayByAddingObjectsFromArray:rows] : rows;
}

static NSView *DPWideRow(NSView *view) {
    NSView *row = DPRow(view, [NSView new]);
    [view.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12].active = YES;
    return row;
}

@implementation DPPageView {
    DPPatch *_patch;
    NSMutableArray<DPPatchSwitch *> *_switches;
    NSTextField *_note;
    NSArray<NSView *> *_rows;
    NSMutableArray<NSView *> *_optionChoices;
}

- (instancetype)initWithPatch:(DPPatch *)patch {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _patch = patch;
    _switches = [NSMutableArray new];
    _optionChoices = [NSMutableArray new];
    _note = DPLabel(@"", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);

    DPPreviewView *preview = [[DPPreviewView alloc] initWithKey:patch->key];
    [preview.heightAnchor constraintEqualToAnchor:preview.widthAnchor multiplier:10.0 / 16].active = YES;
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObjects:preview, [self headingGroup], nil];

    NSString *const unavailable = @"Not Available in This Version";
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithObject:@"Options"];
    NSMutableDictionary<NSString *, NSMutableArray<NSView *> *> *groups = [NSMutableDictionary dictionaryWithObject:[NSMutableArray new] forKey:@"Options"];
    void (^add)(NSString *, NSView *) = ^(NSString *title, NSView *row) {
        if (!groups[title]) {
            [titles addObject:title];
            groups[title] = [NSMutableArray new];
        }
        [groups[title] addObject:row];
    };
    if (patch->choices) add(@"Options", [self choiceRowFor:patch]);
    DPForEachOption(patch, ^(DPPatch *option) {
        NSString *title = option->unavailable ? unavailable : option->section ?: @"Options";
        NSMutableArray<NSView *> *lines = [NSMutableArray arrayWithObjects:DPLabel(option->title, 13, NSFontWeightRegular, NSColor.labelColor),
                                           DPLabel(option->detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor), nil];
        if (option->unavailable) [lines addObject:DPLabel(DPWhyDisabled(option), 11, NSFontWeightRegular, NSColor.secondaryLabelColor)];
        add(title, DPRow(DPColumn(lines, 2), [self switchFor:option]));
        NSMutableArray<NSView *> *under = [NSMutableArray new];
        if (option->choices) [under addObject:[self choiceRowFor:option]];
        for (NSView *view in DPRowsOf(option)) [under addObject:DPWideRow(view)];
        for (NSView *row in under) {
            DPSet(row, &DPChoicePatchKey, [NSValue valueWithPointer:option]);
            add(title, row);
            [self->_optionChoices addObject:row];
        }
    });
    _rows = DPRowsOf(patch);
    for (NSView *view in _rows) {
        if ([view.identifier isEqual:DPLeadingOption]) [groups[@"Options"] insertObject:DPWideRow(view) atIndex:0];
        else add(view.identifier ?: @"Options", DPWideRow(view));
    }
    if ([titles containsObject:unavailable]) {
        [titles removeObject:unavailable];
        [titles addObject:unavailable];
    }
    for (NSString *title in titles)
        if (groups[title].count) [views addObjectsFromArray:@[DPHeader(title), DPGroup(groups[title])]];

    [views addObject:[self footerGroup]];

    DPFillStack(self, views);
    [self sync];
    return self;
}

- (NSView *)headingGroup {
    NSMutableArray<NSView *> *headingText = [@[
        DPLabel(_patch->title, 13, NSFontWeightSemibold, NSColor.labelColor),
        DPLabel(_patch->detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor),
    ] mutableCopy];
    if (_patch->hint) {
        NSView *gap = [NSView new];
        [gap.heightAnchor constraintEqualToConstant:5].active = YES;
        [headingText addObjectsFromArray:@[gap, DPLabel(_patch->hint, 11, NSFontWeightRegular, NSColor.secondaryLabelColor)]];
    }
    [headingText addObject:_note];
    NSStackView *heading = [NSStackView stackViewWithViews:@[
        DPIconTile(_patch->symbol, [NSColor valueForKey:_patch->tint]),
        DPColumn(headingText, 2),
    ]];
    heading.spacing = 10;
    heading.alignment = NSLayoutAttributeTop;
    return DPGroup(@[DPRow(heading, [self switchFor:_patch])]);
}

- (NSView *)footerGroup {
    NSURL *wiki = DPWikiURL(_patch);
    NSView *wikiRow = DPLinkRow(DPRow(DPLabel(@"Read more on the wiki", 13, NSFontWeightRegular, NSColor.labelColor),
                                      DPSymbol(@"arrow.up.right", 11, NSColor.secondaryLabelColor)),
                                @"Read more on the wiki", ^{ [NSWorkspace.sharedWorkspace openURL:wiki]; });
    NSTextField *how = DPLabel([@"diatweaks enable " stringByAppendingString:_patch->key], 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
    how.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    how.selectable = YES;
    NSView *howRow = DPRow(DPColumn(@[DPLabel(@"Turn on from Terminal", 13, NSFontWeightRegular, NSColor.labelColor), how], 2), [NSStackView new]);
    return DPGroup(@[wikiRow, howRow]);
}

- (NSView *)switchFor:(DPPatch *)patch {
    DPPatchSwitch *toggle = [[DPPatchSwitch alloc] initWithPatch:patch];
    [_switches addObject:toggle];
    return toggle.withHiddenIcon;
}

- (NSView *)choiceRowFor:(DPPatch *)patch {
    NSMenu *menu = patch->choices();
    NSPopUpButton *picker = [NSPopUpButton new];
    picker.menu = menu;
    picker.controlSize = NSControlSizeSmall;
    picker.target = self;
    picker.action = @selector(choose:);
    DPSet(picker, &DPChoicePatchKey, [NSValue valueWithPointer:patch]);
    for (NSMenuItem *item in menu.itemArray) if ([item.representedObject isEqual:DPChoice(patch)]) [picker selectItem:item];
    return DPRow(DPLabel(menu.title, 13, NSFontWeightRegular, NSColor.labelColor), picker);
}

- (void)choose:(NSPopUpButton *)picker {
    DPSetChoice([DPGet(picker, &DPChoicePatchKey) pointerValue] ?: _patch, picker.selectedItem.representedObject);
}

- (void)sync {
    for (DPPatchSwitch *toggle in _switches) [toggle sync];
    for (NSView *row in _rows)
        DPFindView(row, ^BOOL(NSView *view) {
            BOOL label = [view isKindOfClass:NSTextField.class] && !((NSTextField *)view).editable;
            if ([view isKindOfClass:NSControl.class] && !label) ((NSControl *)view).enabled = self->_patch->on && !DPSafeMode;
            return NO;
        });
    // Fade in after the group has grown, or the row rides over the one above.
    NSMutableArray<NSView *> *appeared = [NSMutableArray new];
    for (NSView *row in _optionChoices) {
        BOOL shown = ((DPPatch *)[DPGet(row, &DPChoicePatchKey) pointerValue])->on;
        if (row.hidden != shown) continue;
        NSArray<NSView *> *rows = ((NSStackView *)row.superview).arrangedSubviews;
        NSUInteger i = [rows indexOfObject:row];
        NSArray<NSView *> *views = i != NSNotFound && i > 0 ? @[row, rows[i - 1]] : @[row];
        // Hidden inside an animation, AppKit fades it out while it moves, which leaves a ghost behind.
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0;
            context.allowsImplicitAnimation = NO;
            for (NSView *view in views) {
                view.hidden = !shown;
                if (shown) view.alphaValue = 0;
            }
        }];
        if (shown) [appeared addObjectsFromArray:views];
    }
    if (appeared.count)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.2;
                for (NSView *view in appeared) view.animator.alphaValue = 1;
            }];
        });
    _note.stringValue = DPWhyDisabled(_patch) ?: @"";
    _note.hidden = !_note.stringValue.length;
}
@end
