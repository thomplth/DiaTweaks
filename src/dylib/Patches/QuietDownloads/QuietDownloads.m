#import "StdPatch/StdPatch.h"

extern DPPatch DPQuietDownloads;

static Class DPDownloadsMenu;
static __weak NSView *DPPressed;

static BOOL DPButton_press(NSView *self, SEL _cmd) {
    DPPressed = self;
    dispatch_async(dispatch_get_main_queue(), ^{ DPPressed = nil; });
    return DPCallOriginal(DPButton_press, self);
}

static BOOL DPAskedFor(NSView *anchor) {
    if ([DPPressed isDescendantOf:anchor] || [anchor isDescendantOf:DPPressed]) return YES;
    NSEvent *event = NSApp.currentEvent;
    if (event.window != anchor.window || (event.type != NSEventTypeLeftMouseDown && event.type != NSEventTypeLeftMouseUp)) return NO;
    NSView *clicked = [anchor.window.contentView.superview hitTest:event.locationInWindow];
    return [clicked isDescendantOf:anchor] || [anchor isDescendantOf:clicked];
}

static void DPPopover_show(NSPopover *self, SEL _cmd, NSRect rect, NSView *anchor, NSRectEdge edge) {
    if (DPQuietDownloads.on && [self.contentViewController isKindOfClass:DPDownloadsMenu] && !DPAskedFor(anchor)) return;
    DPCallOriginal(DPPopover_show, self, rect, anchor, edge);
}

static void DPInstallQuietDownloads(void) {
    DPDownloadsMenu = objc_getClass(DPDiaDownloadsMenu);
    DPHookClass(NSPopover.class, @selector(showRelativeToRect:ofView:preferredEdge:), (IMP)DPPopover_show);
    DPHook(DPDiaDownloadsButton, @selector(accessibilityPerformPress), (IMP)DPButton_press);
    DPHook(DPDiaTabSurfaceButton, @selector(accessibilityPerformPress), (IMP)DPButton_press);
}

DP_PATCH(DPQuietDownloads) {
    .key = @"quietDownloads",
    .order = 62,
    .title = @"Don’t Open Downloads List",
    .detail = @"Stop the downloads list from opening each time a download starts. The downloads button still shows progress.",
    .symbol = @"arrow.down.circle.fill",
    .tint = @"systemIndigoColor",
    .section = @"Toolbar",
    .classes = DPClasses(DPDiaDownloadsMenu, DPDiaDownloadsButton, DPDiaTabSurfaceButton),
    .install = DPInstallQuietDownloads,
};
