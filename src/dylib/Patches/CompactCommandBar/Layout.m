#import "CompactCommandBar.h"

static const CGFloat DPCommandBarSpacing = 14;
static char DPCompactedKey;

// Drops the bottom row, leaving as much space under the input, or the suggestions once there are some, as above the input.
NSSize DPCompactSize(NSView *container, NSSize size) {
    NSView *commandBar = DPCommandBarPart(container, DPDiaCommandBar), *toolbar = DPCompactToolbar(commandBar);
    NSView *input = DPCommandBarPart(commandBar, DPDiaCommandBarInput), *suggestions = DPCommandBarPart(commandBar, DPDiaCommandBarSuggestions);
    if (toolbar && input && suggestions) {
        CGFloat emptyGap = suggestions.intrinsicContentSize.height > 0 ? 0 : NSMinY(suggestions.frame) - NSMaxY(input.frame);
        size.height -= MAX(0, NSHeight(toolbar.frame) + emptyGap - NSMinY(input.frame));
    }
    return size;
}

static void DPPopover_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    NSSize compact = DPCompactSize(self, size);
    DPSetTrim(self, size.height - compact.height);
    DPCallOriginal(DPPopover_setFrameSize, self, compact);
}

// Shrunk with its container, the command bar would squeeze the suggestions to keep the row, so the container clips the row instead.
static void DPCommandBar_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    CGFloat trim = 0;
    for (NSView *view = self.superview; view && !trim; view = view.superview) trim = DPTrim(view);
    DPCallOriginal(DPCommandBar_setFrameSize, self, NSMakeSize(size.width, size.height + trim));
}

// Dia doesn't resize an open popover when the switch flips.
void DPResizePopovers(void) {
    for (NSView *popover in DPFindViews(DPDiaPopover)) {
        if (!DPCommandBarPart(popover, DPDiaCommandBar)) continue;
        NSRect before = popover.frame;
        [popover setFrameSize:NSMakeSize(NSWidth(before), NSHeight(before) + DPTrim(popover))];
        if (!popover.superview.isFlipped) [popover setFrameOrigin:NSMakePoint(NSMinX(before), NSMaxY(before) - NSHeight(popover.frame))];
    }
}

static void DPPopover_setFrameOrigin(NSView *self, SEL _cmd, NSPoint origin) {
    DPCallOriginal(DPPopover_setFrameOrigin, self, origin);
    NSView *commandBar = DPCommandBarPart(self, DPDiaCommandBar);
    if (DPCompactToolbar(commandBar)) commandBar.needsLayout = YES;
}

// The row moves up over the input, keeping Go at the trailing edge. The popover can run past the window's top, so Go
// centers in the part that shows.
static void DPCommandBar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPCommandBar_layout, self);
    NSView *toolbar = DPCommandBarPart(self, DPDiaCommandBarToolbar);
    NSStackView *stack = toolbar.subviews.firstObject;
    if (![stack isKindOfClass:NSStackView.class]) return;
    BOOL compact = DPCompactToolbar(self) != nil;
    if (!compact && !DPGet(stack, &DPCompactedKey)) return;
    DPSet(stack, &DPCompactedKey, compact ? @YES : nil);
    // Faded, not hidden: the add tabs button stretches to push Go to the trailing edge.
    for (NSView *view in stack.views)
        if (view != DPGoButton(toolbar)) view.alphaValue = !compact;
    NSView *input = DPCommandBarPart(self, DPDiaCommandBarInput), *suggestions = DPCommandBarPart(self, DPDiaCommandBarSuggestions);
    if (!compact || !input || !suggestions || !self.window) return;
    CGFloat gap = NSMinY(suggestions.frame) - NSMaxY(input.frame), rowBottom = NSMinY(suggestions.frame) + NSMinY(input.frame) - gap;
    CGFloat cut = MAX(0, NSMaxY([self convertRect:self.bounds toView:nil]) - NSHeight(self.window.frame));
    NSRect frame = toolbar.frame;
    frame.origin.y = (MIN(cut, NSMinY(input.frame)) + rowBottom - NSHeight(frame)) / 2;
    toolbar.frame = frame;
}

static void DPCommandBarInput_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPCommandBarInput_layout, self);
    NSView *go = DPGoButton(DPCompactToolbar(self.superview)), *text = DPCommandBarPart(self, DPDiaCommandBarText);
    if (!go || !text) return;
    NSRect frame = text.frame;
    frame.size.width = MAX(0, NSWidth(self.bounds) - NSMinX(frame) - go.intrinsicContentSize.width - 2 * DPCommandBarSpacing);
    text.frame = frame;
}

// Labels arrive after the first layout, so a label that changes the verdict lays the command bar out again.
static void DPCommandBarButton_setAccessibilityLabel(NSView *self, SEL _cmd, NSString *label) {
    DPCallOriginal(DPCommandBarButton_setAccessibilityLabel, self, label);
    NSView *commandBar = self;
    while (commandBar && !DPIsKind(commandBar, DPDiaCommandBar)) commandBar = commandBar.superview;
    NSView *toolbar = DPCommandBarPart(commandBar, DPDiaCommandBarToolbar);
    NSStackView *stack = toolbar.subviews.firstObject;
    if (![stack isKindOfClass:NSStackView.class] || ![stack.views containsObject:self] || self == DPGoButton(toolbar)) return;
    DPRememberChatLocked(DPChatLocked(self));
    if ((DPCompactToolbar(commandBar) != nil) == (DPGet(stack, &DPCompactedKey) != nil)) return;
    for (NSView *view = commandBar; view; view = view.superview) view.needsLayout = YES;
}

// The row lies over the input, so only Go takes clicks.
static NSView *DPCommandBarToolbar_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    NSView *hit = DPCallOriginal(DPCommandBarToolbar_hitTest, self, point), *commandBar = self.superview.superview;
    if (!hit || !DPIsKind(commandBar, DPDiaCommandBar) || !DPCompactToolbar(commandBar)) return hit;
    return [hit isDescendantOf:DPGoButton(self)] ? hit : nil;
}

void DPInstallCommandBarLayout(void) {
    DPHook(DPDiaPopover, @selector(setFrameSize:), (IMP)DPPopover_setFrameSize);
    DPHook(DPDiaPopover, @selector(setFrameOrigin:), (IMP)DPPopover_setFrameOrigin);
    DPInstallNewTabLayout();
    DPHook(DPDiaCommandBar, @selector(setFrameSize:), (IMP)DPCommandBar_setFrameSize);
    DPHook(DPDiaCommandBar, @selector(layout), (IMP)DPCommandBar_layout);
    DPHook(DPDiaCommandBarButton, @selector(setAccessibilityLabel:), (IMP)DPCommandBarButton_setAccessibilityLabel);
    DPHook(DPDiaCommandBarInput, @selector(layout), (IMP)DPCommandBarInput_layout);
    DPHook(DPDiaCommandBarToolbar, @selector(hitTest:), (IMP)DPCommandBarToolbar_hitTest);
}
