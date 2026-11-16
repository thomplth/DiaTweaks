#import "TidyTabs.h"

static void DPApplyTidyTabs(DPPatch *patch) {
    if (!patch->on)
        for (NSView *list in DPFindViews(DPDiaTabList)) [[DPTidyHover forList:list] detach];
    DPRelayoutTidyLists();
}

static NSString *DPVerifyTidyTabs(DPPatch *patch) {
    for (NSView *list in DPFindViews(DPDiaTabList)) {
        if (list.hiddenOrHasHiddenAncestor) continue;
        DPTidyHover *hover = [DPTidyHover forList:list];
        NSView *row = DPTidyRowIn(list, NO);
        BOOL tracking = hover.tracking && [hover.sidebar.trackingAreas containsObject:hover.tracking];
        if (patch->on && !tracking) return @"sidebar isn't tracking the pointer";
        if (!patch->on && tracking) return @"sidebar still tracks the pointer";
        if (!patch->on && row && !row.hidden) return @"Tidy Tabs row still showing";
    }
    return nil;
}

DP_PATCH(DPTidyTabs) {
    .key = @"tidyTabs",
    .order = 85,
    .section = @"Tabs",
    .title = @"Tidy Tabs",
    .detail = @"Adds a broom to the line above your tabs. Click it to group your tabs by what they’re for, using Apple Intelligence on your Mac; Dia names the groups. Shows with more than 5 tabs.",
    .symbol = @"sparkles",
    .tint = @"systemPinkColor",
    .classes = DPClasses(DPDiaTabList, DPDiaSidebarHeader),
    .install = DPInstallTidyLayout,
    .apply = DPApplyTidyTabs,
    .verify = DPVerifyTidyTabs,
};
