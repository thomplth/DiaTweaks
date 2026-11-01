#import "StdPatch/StdPatch.h"

extern DPPatch DPQuietDownloads;

static BOOL DPIsMouseEvent(NSEvent *event) {
    switch (event.type) {
    case NSEventTypeLeftMouseDown: case NSEventTypeLeftMouseUp: case NSEventTypeRightMouseDown: case NSEventTypeRightMouseUp:
    case NSEventTypeOtherMouseDown: case NSEventTypeOtherMouseUp: return YES;
    default: return NO;
    }
}

// Dia opens the popover itself when a download starts, usually while the click on the page's link is still the current
// event, so a click only counts if it landed on the button the popover hangs from. The popover is a plain NSPopover
// whose content is Dia's downloads list, so it's recognised by that.
static BOOL DPAskedFor(NSView *anchor) {
    NSEvent *event = NSApp.currentEvent;
    if (event.type == NSEventTypeKeyDown) return (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (!DPIsMouseEvent(event)) return NO;
    if (event.window != anchor.window) return [NSStringFromClass(event.window.class) containsString:@"Menu"];
    NSView *clicked = [anchor.window.contentView.superview hitTest:event.locationInWindow];  // the frame view has no superview
    return [clicked isDescendantOf:anchor] || [anchor isDescendantOf:clicked];
}

static Class DPDownloadsMenu;

static void DPPopover_show(NSPopover *self, SEL _cmd, NSRect rect, NSView *anchor, NSRectEdge edge) {
    if (DPQuietDownloads.on && [self.contentViewController isKindOfClass:DPDownloadsMenu] && !DPAskedFor(anchor)) return;
    DPCallOriginal(DPPopover_show, self, rect, anchor, edge);
}

static void DPInstallQuietDownloads(void) {
    DPDownloadsMenu = objc_getClass("_TtC15DownloadsButton27DownloadsMenuViewController");
    DPHookClass(NSPopover.class, @selector(showRelativeToRect:ofView:preferredEdge:), (IMP)DPPopover_show);
}

DP_PATCH(DPQuietDownloads) {
    .key = @"quietDownloads",
    .order = 95,
    .title = @"Don't pop up downloads",
    .detail = @"Stops the downloads list opening by itself each time a download starts. The downloads button still shows progress, and clicking it opens the list.",
    .symbol = @"arrow.down.circle",
    .tint = @"systemOrangeColor",
    .section = @"Toolbar",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Dont-pop-up-downloads.md",
    .classes = DPClasses("_TtC15DownloadsButton27DownloadsMenuViewController"),
    .install = DPInstallQuietDownloads,
};
