#import "StdPatch/StdPatch.h"

void DPApplyWindowMaterial(DPPatch *patch);
NSString *DPVerifyWindowMaterial(DPPatch *patch);

DP_PATCH(DPTranslucentSidebar) {
    .key = @"translucentSidebar",
    .order = 84,
    .title = @"Translucent Sidebar",
    .detail = @"Show the page through the sidebar when it floats over it, in the window’s material or the one chosen in Window material.",
    .symbol = @"app.translucent rectangle.lefthalf.inset.filled",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaWindowFrame, DPDiaWindowTint, DPDiaFloatingSidebar),
    .apply = DPApplyWindowMaterial,
    .verify = DPVerifyWindowMaterial,
};
