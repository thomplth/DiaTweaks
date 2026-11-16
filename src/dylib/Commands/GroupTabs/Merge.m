#import "GroupTabs.h"

// An apply keeps every toggle from easing and relaying out all patches; Group Tabs reads the switch itself.
static void DPApplyMergeSubdomains(DPPatch *patch) {}

DP_PATCH(DPGroupTabsMergeSubdomains) {
    .key = @"groupTabsMergeSubdomains",
    .order = 86,
    .title = @"Merge Subdomains",
    .detail = @"Group tabs from the same site together, so gist.github.com joins github.com.",
    .symbol = @"arrow.triangle.merge",
    .tint = @"systemPinkColor",
    .requires = @"groupTabsByDomain",
    .apply = DPApplyMergeSubdomains,
};
