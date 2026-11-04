#import "StdPatch/StdPatch.h"

@interface NSWindow (DPPrivate)
- (BOOL)_hasActiveAppearance;
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

// Dia's window buttons follow this. Claiming it also shows focus rings in windows without keyboard focus.
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

static NSString *DPVerifyKeepWindowsActive(DPPatch *patch) {
    for (NSWindow *window in NSApp.windows) {
        if (!DPIsBrowserWindow(window) || !window.visible) continue;
        if (patch->on && !window._hasActiveAppearance) return @"a window looks inactive";
        if (!patch->on && window._hasActiveAppearance && !window.isKeyWindow && !window.isMainWindow) return @"a background window looks active";
    }
    return nil;
}

static void DPInstallKeepWindowsActive(void) {
    DPHookClass(NSWindow.class, @selector(_hasActiveAppearance), (IMP)DPWindow_hasActiveAppearance);
    DPHookClass(NSWindow.class, @selector(hasKeyAppearance), (IMP)DPWindow_hasKeyAppearance);
}

DP_PATCH(DPKeepWindowsActive) {
    .key = @"keepWindowsActive",
    .order = 93,
    .title = @"Keep Windows Active",
    .detail = @"Keep windows looking active, with their shadow, sidebar color and window buttons, when you switch to another app. Experimental.",
    .symbol = @"rectangle.fill.on.rectangle.fill",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .install = DPInstallKeepWindowsActive,
    .apply = DPApplyKeepWindowsActive,
    .verify = DPVerifyKeepWindowsActive,
};
