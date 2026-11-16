#import "StdPatch/StdPatch.h"

extern DPPatch DPCompactSidebarHeader;
static const CGFloat DPHeaderTrim = 10;
static const CGFloat DPTopTabsButtonInset = 14;
static NSHashTable<NSView *> *DPSidebars;
static char DPHeaderFrameKey, DPButtonsKey, DPRetriesKey;

static NSRect DPLaidOutHeader(NSView *header) {
    return [DPDiaValue(header, &DPHeaderFrameKey, @(header.frame)) rectValue];
}

static NSRect DPCloseButtonInWindow(NSView *lights) {
    NSView *close = DPFindView(lights, ^BOOL(NSView *v) { return [v isKindOfClass:NSButton.class] && v == [v.window standardWindowButton:NSWindowCloseButton]; });
    if (!close || !lights.window) return NSZeroRect;
    NSRect r = [close convertRect:close.bounds toView:nil];
    r.origin.y = NSHeight(lights.window.contentView.superview.bounds) - NSMaxY(r);
    return r;
}

// Moved here, not after the header's layout: that makes Dia lay the header out again and put them back, which is the resize jitter.
// Only buttons already near the corner move (a floating sidebar has them elsewhere), and never in full screen, where macOS slides them in each frame.
static NSRect DPCorneredRow(NSView *row, NSRect frame) {
    NSView *lights = DPGet(row, &DPButtonsKey);
    NSWindow *window = row.window;
    if (!DPCompactSidebarHeader.on || lights.superview != row || !window || (window.styleMask & NSWindowStyleMaskFullScreen)) return frame;
    NSRect old = row.frame, close = DPCloseButtonInWindow(lights);
    BOOL flipped = row.superview.isFlipped;
    close.origin.x += frame.origin.x - NSMinX(old);
    close.origin.y += flipped ? frame.origin.y - NSMinY(old) : NSMinY(old) - frame.origin.y;
    CGFloat dx = DPTopTabsButtonInset - NSMinX(close), dy = DPTopTabsButtonInset - NSMinY(close);
    if (!NSIsEmptyRect(close) && fabs(dx) <= 6 && fabs(dy) <= 6) {
        frame.origin.x += dx;
        frame.origin.y += flipped ? dy : -dy;
    }
    return frame;
}

static void DPButtonsRow_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    DPCallOriginal(DPButtonsRow_setFrame, self, DPCorneredRow(self, frame));
}

static NSView *DPNoteButtons(NSView *header) {
    NSView *lights = DPFindView(header, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaTrafficLights); });
    if (lights && lights.superview != header) DPSet(lights.superview, &DPButtonsKey, lights);
    return lights;
}

static void DPHeader_layout(NSView *self, SEL _cmd) {
    DPNoteButtons(self);
    DPCallOriginal(DPHeader_layout, self);
    NSView *lights = DPNoteButtons(self), *row = lights.superview;
    if (!lights || row == self) return;
    // Dia may have set the row, or swapped it, without going through its setter; it must still end the pass in the corner.
    NSRect cornered = DPCorneredRow(row, row.frame);
    if (!NSEqualRects(cornered, row.frame) && DPMayAdjust(row)) row.frame = cornered;
    // At launch Dia lays the header out before the buttons are in it, then not again until the sidebar changes.
    NSUInteger retries = [DPGet(self, &DPRetriesKey) unsignedIntegerValue];
    if (DPCompactSidebarHeader.on && NSIsEmptyRect(DPCloseButtonInWindow(lights)) && self.window && retries < 8) {
        DPSet(self, &DPRetriesKey, @(retries + 1));
        __weak NSView *header = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{ header.needsLayout = YES; });
    }
}

// Rewritten in the setters, not after the pass: trimming afterwards makes Dia lay out again and put the content back, which jumps it by DPHeaderTrim.
static void DPCompactFrame_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    if (DPCompactSidebarHeader.on && DPSidebars) {
        if (DPIsKind(self, DPDiaSidebarHeader)) {
            NSArray *values = DPGet(self, &DPHeaderFrameKey);
            if (!values || ![values[1] isEqual:[NSValue valueWithRect:frame]]) {
                NSRect laidOut = frame;
                frame.size.height = MAX(0, NSHeight(laidOut) - DPHeaderTrim);
                DPOverride(self, &DPHeaderFrameKey, [NSValue valueWithRect:laidOut], [NSValue valueWithRect:frame]);
            }
        } else if ([DPSidebars containsObject:self.superview]) {
            NSView *header = DPSubview(self.superview, DPDiaSidebarHeader);
            NSRect laidOut = header ? DPLaidOutHeader(header) : NSZeroRect;
            if (header && !NSIsEmptyRect(laidOut) && fabs(NSMinY(frame) - NSMaxY(laidOut)) < 0.5) {
                frame.origin.y = MAX(0, NSMaxY(laidOut) - DPHeaderTrim);
                frame.size.height += DPHeaderTrim;
            }
        }
    }
    DPCallOriginal(DPCompactFrame_setFrame, self, frame);
}

static void DPSidebar_viewWillLayout(NSViewController *self, SEL _cmd) {
    [DPSidebars addObject:self.view];
    for (NSView *sub in self.view.subviews)
        DPHookClass([sub class], @selector(setFrame:), (IMP)DPCompactFrame_setFrame);
    DPCallOriginal(DPSidebar_viewWillLayout, self);
}

static void DPSidebar_viewDidLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPSidebar_viewDidLayout, self);
    [DPSidebars addObject:self.view];
}

static void DPInstallCompactSidebarHeader(void) {
    DPSidebars = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaSidebarController, @selector(viewWillLayout), (IMP)DPSidebar_viewWillLayout);
    DPHook(DPDiaSidebarController, @selector(viewDidLayout), (IMP)DPSidebar_viewDidLayout);
    DPHook(DPDiaSidebarHeader, @selector(layout), (IMP)DPHeader_layout);
    DPHook(DPDiaSidebarHeader, @selector(setFrame:), (IMP)DPCompactFrame_setFrame);
    DPHookClass(NSStackView.class, @selector(setFrame:), (IMP)DPButtonsRow_setFrame);
}

static void DPApplyCompactSidebarHeader(DPPatch *patch) { DPRelayoutViews(DPSidebars); }

static NSString *DPVerifyCompactSidebarHeader(DPPatch *patch) {
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        if (header.hiddenOrHasHiddenAncestor || !header.superview.isFlipped) continue;
        CGFloat trimmed = NSHeight(DPLaidOutHeader(header)) - NSHeight(header.frame);
        if (fabs(trimmed - (patch->on ? DPHeaderTrim : 0)) > 0.5) return patch->on ? @"header is full height" : @"header is still trimmed";
        NSView *lights = DPFindView(header, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaTrafficLights); });
        NSRect close = lights ? DPCloseButtonInWindow(lights) : NSZeroRect;
        BOOL cornered = fabs(NSMinX(close) - DPTopTabsButtonInset) < 0.5 && fabs(NSMinY(close) - DPTopTabsButtonInset) < 0.5;
        BOOL fullScreen = (header.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
        if (patch->on && !fullScreen && !NSIsEmptyRect(close) && !cornered) return @"window buttons aren't where top tabs put them";
    }
    return nil;
}

DP_PATCH(DPCompactSidebarHeader) {
    .key = @"compactSidebarHeader",
    .order = 76,
    .section = @"Sidebar & Tab Bar",
    .title = @"Compact Sidebar Header",
    .detail = @"Move the pinned tabs up into the empty space under the window buttons.",
    .symbol = @"arrow.up.to.line.square.fill",
    .tint = @"systemTealColor",
    .classes = DPClasses(DPDiaSidebarController, DPDiaSidebarHeader, DPDiaTrafficLights),
    .install = DPInstallCompactSidebarHeader,
    .apply = DPApplyCompactSidebarHeader,
    .verify = DPVerifyCompactSidebarHeader,
};
