#import "HideToolbar.h"

static void DPApplyReveal(DPPatch *patch) { DPRelayoutPanes(); }

static NSString *DPVerifyRevealToolbar(DPPatch *patch) {
    for (NSView *pane in DPFindViews(DPDiaContentPane)) {
        DPToolbarHover *hover = [DPToolbarHover forPane:pane];
        NSView *bar = DPSubview(pane, DPDiaToolbar);
        BOOL watching = patch->on && DPHideToolbar.on && !hover.inPlace && bar && !bar.hiddenOrHasHiddenAncestor;
        if ((hover.tracking != nil) != watching) return watching ? @"nothing watches the top of the page" : @"still watching the top of the page";
        if (watching && !hover.revealed && bar.alphaValue > 0.01) return @"toolbar shows while the pointer is away";
    }
    return nil;
}

DP_PATCH(DPRevealToolbarOnHover) {
    .key = @"revealToolbarOnHover",
    .order = 40,
    .title = @"Show Toolbar on Hover",
    .detail = @"Show the toolbar when you move the pointer to the top of the page.",
    .symbol = @"cursorarrow.rays",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .apply = DPApplyReveal,
    .verify = DPVerifyRevealToolbar,
};
