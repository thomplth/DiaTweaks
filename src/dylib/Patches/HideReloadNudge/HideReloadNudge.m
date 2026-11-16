#import "StdPatch/StdPatch.h"

extern DPPatch DPHideReloadNudge;
static Class DPReloadNudge;

static void DPPopover_show(NSPopover *self, SEL _cmd, NSRect rect, NSView *anchor, NSRectEdge edge) {
    if (DPHideReloadNudge.on && [self.contentViewController isKindOfClass:DPReloadNudge]) return;
    DPCallOriginal(DPPopover_show, self, rect, anchor, edge);
}

static void DPInstallHideReloadNudge(void) {
    DPReloadNudge = objc_getClass(DPDiaReloadNudge);
    DPHookClass(NSPopover.class, @selector(showRelativeToRect:ofView:preferredEdge:), (IMP)DPPopover_show);
}

DP_PATCH(DPHideReloadNudge) {
    .key = @"hideReloadNudge",
    .order = 64,
    .title = @"Hide Site Not Working Prompt",
    .detail = @"Stop the “not working correctly?” prompt that offers to turn off the ad blocker after you reload a page a few times.",
    .symbol = @"exclamationmark.bubble.fill",
    .tint = @"systemIndigoColor",
    .section = @"Toolbar",
    .classes = DPClasses(DPDiaReloadNudge),
    .install = DPInstallHideReloadNudge,
};
