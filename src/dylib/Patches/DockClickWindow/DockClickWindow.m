#import "StdPatch/StdPatch.h"

extern DPPatch DPDockClickWindow;

// With the Dock's switch-to-Space setting off, ordering a window front shows nothing, so Dia's own new window is left to open.
static BOOL DPSwitchesToWindows(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("workspaces-auto-swoosh"), CFSTR("com.apple.dock"));
    BOOL on = !value || CFEqual(value, kCFBooleanTrue) || ([(__bridge id)value respondsToSelector:@selector(boolValue)] && [(__bridge id)value boolValue]);
    if (value) CFRelease(value);
    return on;
}

static NSWindow *DPWindowToShow(void) {
    NSMutableArray<NSWindow *> *windows = [NSApp.orderedWindows mutableCopy];
    for (NSWindow *window in NSApp.windows) if (![windows containsObject:window]) [windows addObject:window];
    for (NSWindow *window in windows)
        if (DPIsKind(window, DPDiaWindow) && window.visible && !window.miniaturized && window.level == NSNormalWindowLevel) return window;
    return nil;
}

static BOOL DPApp_shouldHandleReopen(id self, SEL _cmd, NSApplication *app, BOOL hasVisibleWindows) {
    NSWindow *window = DPDockClickWindow.on && !hasVisibleWindows && DPSwitchesToWindows() ? DPWindowToShow() : nil;
    if (!window) return DPCallOriginal(DPApp_shouldHandleReopen, self, app, hasVisibleWindows);
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    return NO;
}

static void DPInstallDockClickWindow(void) {
    DPHook(DPDiaAppDelegate, @selector(applicationShouldHandleReopen:hasVisibleWindows:), (IMP)DPApp_shouldHandleReopen);
}

DP_PATCH(DPDockClickWindow) {
    .key = @"dockClickWindow",
    .order = 99,
    .title = @"Dock Click Shows Existing Window",
    .detail = @"Clicking Dia’s Dock icon from another Desktop takes you to the window Dia already has, instead of opening a new one. Needs “When switching to an application, switch to a Space with open windows” in Desktop & Dock.",
    .symbol = @"dock.rectangle",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaAppDelegate),
    .install = DPInstallDockClickWindow,
};
