#import "Patches/Peek/Peek.h"

DP_PATCH(DPPeekPinnedLinks) {
    .key = @"peekPinnedLinks",
    .order = 104,
    .title = @"Peek from Pinned Tabs",
    .detail = @"Open a link that leaves a pinned tab's site in Peek, like Arc, instead of in a new tab. Links on the same site still open in the pinned tab.",
    .symbol = @"pin.fill",
    .tint = @"systemMintColor",
    .requires = @"peek",
    .defaultOn = YES,
};
