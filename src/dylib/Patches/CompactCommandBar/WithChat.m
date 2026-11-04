#import "CompactCommandBar.h"

DP_PATCH(DPCompactWithChat) {
    .key = @"compactCommandBarWithChat",
    .order = 91,
    .title = @"Compact with Chat Usage Too",
    .detail = @"Also hide Add tabs or files and dictation when you have chat usage. You can’t use them from the command bar while this is on.",
    .symbol = @"exclamationmark.triangle.fill",
    .tint = @"systemOrangeColor",
    .requires = @"compactCommandBar",
    .apply = DPApplyCompactCommandBar,
};
