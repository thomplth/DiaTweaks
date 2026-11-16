#import "StdPatch/StdPatch.h"

static BOOL DPIsPersonalizeButton(NSView *view) { return DPIsKind(view, DPDiaPersonalizeButton); }

DP_PATCH(DPHidePersonalizeButton) {
    .key = @"hidePersonalizeButton",
    .order = 95,
    .title = @"Hide Personalize Button",
    .detail = @"Hide the Personalization button at the top right of new tab pages.",
    .symbol = @"person.crop.circle.fill",
    .tint = @"systemPurpleColor",
    .section = @"AI",
    .classes = DPClasses(DPDiaToolbar, DPDiaPersonalizeButton),
    .disabledBy = @"hideToolbar",
    .hides = DPIsPersonalizeButton,
    .coveredBy = @"turnOffAI",
};
