#import "TurnOffAI.h"

#define DPDiaShortcutsPane     "_TtC11Preferences45KeyboardShortcutsPreferencePaneViewController"
#define DPDiaPreferencesTable  "_TtC11Preferences20PreferencesTableView"
#define DPDiaSuggestionCell    "_TtC15BoostCommandBar23SuggestionTableViewCell"
#define DPDiaIconContainer     "_TtC15BoostCommandBar17IconContainerView"

static char DPAIRowsKey, DPPickKey;
static CFTimeInterval gArrowAt;

static BOOL DPFoldsRows(NSTableView *table) {
    id owner = table.delegate;
    return DPIsKind(owner, DPDiaCommandBarSuggestions) || DPIsKind(owner, DPDiaSettingsSidebar) || DPIsKind(owner, DPDiaShortcutsPane)
        || DPIsKind(owner, DPDiaPreferencesTable);
}

static BOOL DPIsAIRowView(NSTableView *table, NSView *row) {
    BOOL sidebar = DPIsKind(table.delegate, DPDiaSettingsSidebar), suggestions = DPIsKind(table.delegate, DPDiaCommandBarSuggestions);
    return DPFindView(row, ^BOOL(NSView *view) {
        if ([view isKindOfClass:NSImageView.class]) return [view.accessibilityLabel isEqual:@"chat"];
        // Suggestion text can start with "Chat with" too: only the icon says it's chat.
        if (suggestions) return NO;
        NSString *text = [view isKindOfClass:NSTextField.class] ? [(NSTextField *)view stringValue] : view.accessibilityLabel;
        if (sidebar) return [text isEqual:@"Apps"] || [text isEqual:@"Skills"];
        return DPIsAITitle(text);
    }) != nil;
}

static BOOL DPArrowJustPressed(void) { return CACurrentMediaTime() - gArrowAt < 0.3; }

static NSString *DPTrimmed(NSString *text) { return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }

static id DPFirstOfClass(NSView *root, Class cls) {
    return DPFindView(root, ^BOOL(NSView *view) { return [view isKindOfClass:cls]; });
}

static NSView *DPFirstOfKind(NSView *root, const char *className) {
    return DPFindView(root, ^BOOL(NSView *view) { return DPIsKind(view, className); });
}

static NSView *DPBarOf(NSView *view) {
    while (view && !DPIsKind(view, DPDiaCommandBar)) view = view.superview;
    return view;
}

static NSView *DPTypedCell(NSTableView *table, NSString *typed) {
    NSIndexSet *hidden = DPGet(table, &DPAIRowsKey);
    for (NSInteger row = 0; row < table.numberOfRows; row++) {
        if ([hidden containsIndex:row]) continue;
        NSView *cell = DPFirstOfKind([table rowViewAtRow:row makeIfNecessary:YES], DPDiaSuggestionCell);
        if (DPFindView(cell, ^BOOL(NSView *view) {
                return [view isKindOfClass:NSTextField.class] && [DPTrimmed(((NSTextField *)view).stringValue) isEqual:typed];
            }))
            return cell;
    }
    return nil;
}

static NSImageView *DPIconIn(NSView *root) {
    return DPFirstOfClass(DPFirstOfKind(root, DPDiaIconContainer), NSImageView.class);
}

static NSString *DPTrailingName(NSView *cell, NSString *typed) {
    NSTextField *other = (NSTextField *)DPFindView(cell, ^BOOL(NSView *view) {
        NSString *text = [view isKindOfClass:NSTextField.class] ? DPTrimmed(((NSTextField *)view).stringValue) : nil;
        return text.length && ![text isEqual:typed];
    });
    NSString *label = DPTrimmed(other.stringValue);
    if (label.length < 2 || ![@"—–-" containsString:[label substringToIndex:1]]) return nil;
    return DPTrimmed([label substringFromIndex:1]);
}

// Dia's pick can't be moved from here, so the button and icon show what Return will do instead.
static void DPShowTypedAction(NSTableView *table) {
    if (!DPTurnOffAI.on || !DPGet(table, &DPPickKey)) return;
    NSView *bar = DPBarOf(table);
    NSTextView *input = DPFirstOfClass(bar, NSTextView.class);
    NSString *typed = DPTrimmed(input.string);
    NSView *cell = typed.length ? DPTypedCell(table, typed) : nil;
    NSString *name = DPTrailingName(cell, typed);
    NSImageView *rowIcon = DPIconIn(cell), *fieldIcon = DPIconIn(DPFirstOfKind(bar, DPDiaCommandBarInput));
    NSView *button = DPFindView(bar, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaCommandBarButton)
            && DPFindView(view, ^BOOL(NSView *sub) { return [sub isKindOfClass:NSImageView.class] && DPHasLabel(sub, @"Return"); });
    });
    NSTextField *label = DPFirstOfClass(button, NSTextField.class);
    if (name && label && ![label.stringValue isEqual:name]) label.stringValue = name;
    if (rowIcon.image && fieldIcon && fieldIcon.image != rowIcon.image) {
        fieldIcon.image = rowIcon.image;
        fieldIcon.accessibilityLabel = rowIcon.accessibilityLabel;
    }
}

static void DPPickedHiddenRow(NSTableView *table) {
    DPSet(table, &DPPickKey, @YES);
    dispatch_async(dispatch_get_main_queue(), ^{ DPShowTypedAction(table); });
}

// No typed row: swallow Return, since letting it through opens a chat that can't answer.
static BOOL DPOpenTypedRow(NSTextView *text) {
    NSTableView *table = (NSTableView *)DPFindView(DPBarOf(text), ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTableView.class] && DPIsKind(((NSTableView *)view).delegate, DPDiaCommandBarSuggestions);
    });
    NSString *typed = DPTrimmed(text.string);
    if (!DPGet(table, &DPPickKey) || text.hasMarkedText || !typed.length) return NO;
    NSView *cell = DPTypedCell(table, typed);
    DPSet(table, &DPPickKey, nil);
    if (!cell) return YES;
    NSEvent *key = NSApp.currentEvent;
    NSPoint middle = [cell convertPoint:NSMakePoint(NSMidX(cell.bounds), NSMidY(cell.bounds)) toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:middle
                                   modifierFlags:key.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask
                                       timestamp:key.timestamp windowNumber:cell.window.windowNumber context:nil
                                     eventNumber:0 clickCount:1 pressure:1];
    [cell mouseDown:click];
    return YES;
}

static BOOL DPInput_command(NSView *self, SEL _cmd, NSTextView *text, SEL command) {
    if (DPTurnOffAI.on) {
        if (command == @selector(moveUp:) || command == @selector(moveDown:)) gArrowAt = CACurrentMediaTime();
        else if (command == @selector(insertNewline:) && DPOpenTypedRow(text)) return YES;
    }
    return DPCallOriginal(DPInput_command, self, text, command);
}

// Asking a table for a row view during an update throws, and hidden rows have none: unhide, look, hide.
static void DPFindAIRows(NSTableView *table) {
    // Hiding and showing rows are updates too.
    static BOOL finding;
    if (finding) return;
    finding = YES;
    // The table keeps its hidden rows in step as rows come and go, so what was found before may point past the end.
    if ([DPGet(table, &DPAIRowsKey) count] && table.hiddenRowIndexes.count)
        [table unhideRowsAtIndexes:table.hiddenRowIndexes withAnimation:NSTableViewAnimationEffectNone];
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (NSInteger row = 0; DPTurnOffAI.on && row < table.numberOfRows; row++) {
        NSView *view = [table rowViewAtRow:row makeIfNecessary:YES];
        if (view && DPIsAIRowView(table, view)) [rows addIndex:row];
    }
    BOOL changed = ![rows isEqualToIndexSet:DPGet(table, &DPAIRowsKey) ?: [NSIndexSet indexSet]];
    DPSet(table, &DPAIRowsKey, rows);
    if (rows.count) [table hideRowsAtIndexes:rows withAnimation:NSTableViewAnimationEffectNone];
    finding = NO;
    if (!DPIsKind(table.delegate, DPDiaCommandBarSuggestions)) return;
    if (!DPTurnOffAI.on) DPSet(table, &DPPickKey, nil);
    else if (DPGet(table, &DPPickKey) || (!DPArrowJustPressed() && [rows containsIndex:table.selectedRow])) DPPickedHiddenRow(table);
    if (changed) DPBarOf(table).needsLayout = YES;
}

CGFloat DPHiddenSuggestionsHeight(NSView *suggestions) {
    if (!DPTurnOffAI.on) return 0;
    NSTableView *table = DPFirstOfClass(suggestions, NSTableView.class);
    __block CGFloat height = 0;
    [DPGet(table, &DPAIRowsKey) enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        height += [(id<NSTableViewDelegate>)table.delegate tableView:table heightOfRow:row];
    }];
    return height;
}

static void DPTable_endUpdates(NSTableView *self, SEL _cmd) {
    DPCallOriginal(DPTable_endUpdates, self);
    if (DPFoldsRows(self)) DPFindAIRows(self);
}

static void DPTable_reloadData(NSTableView *self, SEL _cmd) {
    DPCallOriginal(DPTable_reloadData, self);
    if (DPFoldsRows(self)) DPFindAIRows(self);
}

// An arrow onto the chat row moves on; Dia's own pick of it must not, or the field fills with the next suggestion.
static void DPTable_selectRows(NSTableView *self, SEL _cmd, NSIndexSet *rows, BOOL extend) {
    NSInteger from = self.selectedRow;
    DPCallOriginal(DPTable_selectRows, self, rows, extend);
    if (!DPTurnOffAI.on || !DPIsKind(self.delegate, DPDiaCommandBarSuggestions)) return;
    BOOL hidden = rows.count == 1 && [DPGet(self, &DPAIRowsKey) containsIndex:rows.firstIndex];
    if (hidden && !DPArrowJustPressed()) return DPPickedHiddenRow(self);
    DPSet(self, &DPPickKey, nil);
    if (!hidden) return;
    NSUInteger row = rows.firstIndex;
    BOOL up = (from > (NSInteger)row && row > 0) || row + 1 >= (NSUInteger)self.numberOfRows;
    NSResponder *editor = self.window.firstResponder;
    dispatch_async(dispatch_get_main_queue(), ^{ [editor doCommandBySelector:up ? @selector(moveUp:) : @selector(moveDown:)]; });
}

void DPApplyAIRows(void) {
    for (NSTableView *table in DPFindViews("NSTableView"))
        if (DPFoldsRows(table)) DPFindAIRows(table);
}

void DPInstallAIRows(void) {
    DPHookClass(NSTableView.class, @selector(endUpdates), (IMP)DPTable_endUpdates);
    DPHookClass(NSTableView.class, @selector(reloadData), (IMP)DPTable_reloadData);
    DPHookClass(NSTableView.class, @selector(selectRowIndexes:byExtendingSelection:), (IMP)DPTable_selectRows);
    DPHook(DPDiaCommandBarText, @selector(textView:doCommandBySelector:), (IMP)DPInput_command);
}
