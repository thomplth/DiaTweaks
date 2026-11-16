#import "StdPatch/StdPatch.h"

@interface NSWindow (DPPrivate)
- (BOOL)_hasActiveAppearance;
- (BOOL)hasKeyAppearance;
- (void)_setShadowParameters;
@end

@interface NSView (DPPrivate)
- (void)_windowChangedKeyState;
@end

extern DPPatch DPKeepWindowsActive;

static BOOL DPIsBrowserWindow(NSWindow *window) {
    return (window.styleMask & NSWindowStyleMaskTitled) && ![window isKindOfClass:NSPanel.class];
}

static BOOL DPKeptActive(NSWindow *window) {
    return DPKeepWindowsActive.on && DPIsBrowserWindow(window);
}

static BOOL DPWindow_hasActiveAppearance(NSWindow *self, SEL _cmd) {
    return DPKeptActive(self) || DPCallOriginal(DPWindow_hasActiveAppearance, self);
}

static BOOL DPWindow_hasKeyAppearance(NSWindow *self, SEL _cmd) {
    return DPKeptActive(self) || DPCallOriginal(DPWindow_hasKeyAppearance, self);
}

static void DPRefreshKeyState(NSView *view) {
    [view _windowChangedKeyState];
    view.needsDisplay = YES;
    for (NSView *subview in view.subviews) DPRefreshKeyState(subview);
}

static void DPApplyKeepWindowsActive(DPPatch *patch) {
    for (NSWindow *window in NSApp.windows) {
        if (!DPIsBrowserWindow(window)) continue;
        [window _setShadowParameters];
        DPRefreshKeyState(window.contentView.superview);
    }
}

static BOOL DPAppKitAnswer(NSWindow *window, SEL sel) {
    return ((BOOL (*)(id, SEL))DPDiaIMP(NSWindow.class, sel))(window, sel);
}

// A never-shown titled window is inactive to AppKit alone; the pool frees it before any check can list it.
static NSString *DPProbeProblem(BOOL on) {
    @autoreleasepool {
        NSWindow *probe = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered defer:YES];
        probe.releasedWhenClosed = NO;
        BOOL active = probe._hasActiveAppearance, key = probe.hasKeyAppearance;
        if (on) return active && key ? nil : @"a window looks inactive";
        return active == DPAppKitAnswer(probe, @selector(_hasActiveAppearance)) && key == DPAppKitAnswer(probe, @selector(hasKeyAppearance))
            ? nil : @"a background window looks active";
    }
}

static NSString *DPVerifyKeepWindowsActive(DPPatch *patch) {
    NSString *problem = DPProbeProblem(patch->on);
    if (problem || !patch->on) return problem;
    for (NSWindow *window in NSApp.windows)
        if (DPIsBrowserWindow(window) && window.visible && !window._hasActiveAppearance) return @"a window looks inactive";
    return nil;
}

static void DPInstallKeepWindowsActive(void) {
    DPHookClass(NSWindow.class, @selector(_hasActiveAppearance), (IMP)DPWindow_hasActiveAppearance);
    DPHookClass(NSWindow.class, @selector(hasKeyAppearance), (IMP)DPWindow_hasKeyAppearance);
}

DP_PATCH(DPKeepWindowsActive) {
    .key = @"keepWindowsActive",
    .order = 96,
    .title = @"Keep Windows Active",
    .detail = @"Keep windows looking active, with their shadow, sidebar color and window buttons, when you switch to another app. Experimental.",
    .symbol = @"rectangle.fill.on.rectangle.fill",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .install = DPInstallKeepWindowsActive,
    .apply = DPApplyKeepWindowsActive,
    .verify = DPVerifyKeepWindowsActive,
};
