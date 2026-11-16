#import "HideToolbar.h"

DP_PATCH(DPShowToolbarWithSidebar) {
    .key = @"showToolbarWithSidebar",
    .order = 45,
    .title = @"Show Toolbar with Sidebar",
    .detail = @"Show the toolbar while the sidebar is open.",
    .symbol = @"sidebar.left",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .section = @"Showing the Toolbar",
    .apply = DPApplyRelayoutPanes,
    .verify = DPVerifyKeptInPlace,
};
