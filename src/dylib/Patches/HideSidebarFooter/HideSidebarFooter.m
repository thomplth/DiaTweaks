#import "StdPatch/StdPatch.h"

static BOOL DPIsSidebarFooterItem(NSView *view) { return DPIsKind(view.superview, DPDiaSidebarFooter); }

DP_PATCH(DPHideSidebarFooter) {
    .key = @"hideSidebarFooter",
    .order = 80,
    .title = @"Hide Sidebar Footer",
    .detail = @"Hide the bar at the bottom of the sidebar, with its space dots and buttons, and give its room to the tabs.",
    .symbol = @"rectangle.bottomthird.inset.filled",
    .tint = @"systemIndigoColor",
    .section = @"Sidebar & Tab Bar",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Hide-sidebar-footer.md",
    .classes = DPClasses(DPDiaSidebarFooter),
    .hides = DPIsSidebarFooterItem,
};
