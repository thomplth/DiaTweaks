#import "HideToolbar.h"

static void DPApplyShowOnNewTab(DPPatch *patch) { DPRelayoutPanes(); }

DP_PATCH(DPShowToolbarOnNewTab) {
    .key = @"showToolbarOnNewTab",
    .order = 47,
    .title = @"Show Toolbar on New Tabs",
    .detail = @"Show the toolbar and bookmarks bar on new tab pages, and hide them once a site opens.",
    .symbol = @"plus.square.fill.on.square.fill",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .apply = DPApplyShowOnNewTab,
    .verify = DPVerifyKeptInPlace,
};
