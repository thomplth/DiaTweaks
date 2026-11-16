#import "HideToolbar.h"

DP_PATCH(DPShowToolbarOnNewTab) {
    .key = @"showToolbarOnNewTab",
    .order = 47,
    .title = @"Show Toolbar on New Tabs",
    .detail = @"Show the toolbar and bookmarks bar on new tab pages, and hide them once a site opens.",
    .symbol = @"plus.square.fill.on.square.fill",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .section = @"Showing the Toolbar",
    .apply = DPApplyRelayoutPanes,
    .verify = DPVerifyKeptInPlace,
};
