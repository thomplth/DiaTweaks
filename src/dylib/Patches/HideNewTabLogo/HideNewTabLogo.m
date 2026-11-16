#import "StdPatch/StdPatch.h"

static BOOL DPIsNewTabLogo(NSView *view) {
    if (!DPIsKind(view, DPDiaNewTabLogo) && !DPIsKind(view, DPDiaNewTabLogoParticles)) return NO;
    for (NSView *up = view.superview; up; up = up.superview)
        if (DPIsKind(up, DPDiaNewTabPage)) return YES;
    return NO;
}

DP_PATCH(DPHideNewTabLogo) {
    .key = @"hideNewTabLogo",
    .order = 93,
    .section = @"New Tab Page",
    .title = @"Hide New Tab Logo",
    .detail = @"Hide the Dia logo above the search field on new tab pages.",
    .symbol = @"circle.dashed",
    .tint = @"systemGrayColor",
    .classes = DPClasses(DPDiaNewTabPage, DPDiaNewTabLogo, DPDiaNewTabLogoParticles),
    .hides = DPIsNewTabLogo,
};
