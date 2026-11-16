#import "StdPatch/StdPatch.h"

extern DPPatch DPHidePinnedTabCard;

static void DPCard_orderWindow(NSWindow *self, SEL _cmd, NSWindowOrderingMode place, NSInteger other) {
    if (DPHidePinnedTabCard.on && place != NSWindowOut) return;
    DPCallOriginal(DPCard_orderWindow, self, place, other);
}

static NSArray<NSWindow *> *DPOpenCards(void) {
    return [NSApp.windows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSWindow *window, id _) {
        return window.visible && DPIsKind(window, DPDiaPinnedTabCard);
    }]];
}

static void DPApplyHidePinnedTabCard(DPPatch *patch) {
    if (patch->on) for (NSWindow *card in DPOpenCards()) [card orderOut:nil];
}

static NSString *DPVerifyHidePinnedTabCard(DPPatch *patch) {
    return patch->on && DPOpenCards().count ? @"a pinned tab's card is showing" : nil;
}

static void DPInstallHidePinnedTabCard(void) {
    DPHook(DPDiaPinnedTabCard, @selector(orderWindow:relativeTo:), (IMP)DPCard_orderWindow);
}

DP_PATCH(DPHidePinnedTabCard) {
    .key = @"hidePinnedTabCard",
    .order = 83,
    .title = @"Hide Pinned Tab Card",
    .detail = @"Stop the card with a pinned tab's title and buttons from showing when you point at the tab.",
    .symbol = @"pin.slash.fill pin.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaPinnedTabCard),
    .install = DPInstallHidePinnedTabCard,
    .apply = DPApplyHidePinnedTabCard,
    .verify = DPVerifyHidePinnedTabCard,
};
