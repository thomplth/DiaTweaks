#import "StdPatch/StdPatch.h"

static BOOL DPIsSidebarButton(NSView *view) { return DPHasLabel(view, @"Toggle sidebar"); }

DP_PATCH(DPHideSidebarButton) {
    .key = @"hideSidebarButton",
    .order = 50,
    .title = @"Hide Sidebar Button",
    .detail = @"Hide the sidebar toggle at the top left of the toolbar.",
    .symbol = @"rectangle.lefthalf.filled",
    .tint = @"systemIndigoColor",
    .section = @"Toolbar",
    .classes = DPClasses(DPDiaToolbar),
    .disabledBy = @"hideToolbar",
    .hides = DPIsSidebarButton,
};
