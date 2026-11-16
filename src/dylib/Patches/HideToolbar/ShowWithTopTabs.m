#import "HideToolbar.h"

DP_PATCH(DPShowToolbarWithTopTabs) {
    .key = @"showToolbarWithTopTabs",
    .order = 48,
    .title = @"Show Toolbar with Tabs at the Top",
    .detail = @"Show the toolbar while tabs are at the top of the window, and hide it again with tabs in the sidebar.",
    .symbol = @"menubar.rectangle",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .section = @"Showing the Toolbar",
    .apply = DPApplyRelayoutPanes,
    .verify = DPVerifyKeptInPlace,
};
