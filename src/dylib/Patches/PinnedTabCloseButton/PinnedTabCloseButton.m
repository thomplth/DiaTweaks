#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

static NSHashTable *DPCleared;

static void DPAllowClose(NSView *tab) {
    id controller = DPViewModelDelegate(tab);
    BOOL *suppress = DPIvar(controller, "suppressesCloseButton");
    if (!suppress || !*suppress) return;
    *suppress = NO;
    [DPCleared addObject:controller];
}

static void DPTracker_mouseEntered(id self, SEL _cmd, NSEvent *event) {
    __autoreleasing id *view = DPPinnedTabCloseButton.on ? (__autoreleasing id *)DPIvar(self, "view") : NULL;
    if (view) DPAllowClose(DPEnclosingTab(objc_loadWeak(view)));
    DPCallOriginal(DPTracker_mouseEntered, self, event);
}

static void DPTab_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTab_layout, self);
    if (DPPinnedTabCloseButton.on) DPAllowClose(self);
}

static void DPApplyPinnedTabCloseButton(DPPatch *patch) {
    DPRelayoutTabContents();
    if (patch->on) {
        for (NSView *tab in DPFindViews(DPDiaTabView)) DPAllowClose(tab);
        return;
    }
    // A tab unpinned since has Dia's own setting; leave it showing the button.
    NSMutableSet *unpinned = [NSMutableSet set];
    for (NSView *content in DPFindViews(DPDiaTabContentView)) {
        BOOL *pinned = DPIvar(DPAttributes(content), "isInFavoritesOrPinnedContainer");
        id controller = pinned && !*pinned ? DPViewModelDelegate(DPEnclosingTab(content)) : nil;
        if (controller) [unpinned addObject:controller];
    }
    for (id controller in DPCleared.allObjects) {
        BOOL *suppress = [unpinned containsObject:controller] ? NULL : DPIvar(controller, "suppressesCloseButton");
        if (suppress) *suppress = YES;
    }
    [DPCleared removeAllObjects];
}

static NSString *DPVerifyPinnedTabCloseButton(DPPatch *patch) {
    for (NSView *tab in DPFindViews(DPDiaTabView)) {
        id controller = DPViewModelDelegate(tab);
        if (!controller || tab.needsLayout) continue;
        BOOL *suppress = DPIvar(controller, "suppressesCloseButton");
        if (!suppress) return @"tab has no close button setting";
        if (patch->on && *suppress) return @"pinned tab hides its close button";
    }
    return nil;
}

static void DPInstallPinnedTabCloseButton(void) {
    DPCleared = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaHoverTracker, @selector(mouseEntered:), (IMP)DPTracker_mouseEntered);
    DPHook(DPDiaTabView, @selector(layout), (IMP)DPTab_layout);
}

DP_PATCH(DPPinnedTabCloseButton) {
    .key = @"pinnedTabCloseButton",
    .order = 86,
    .section = @"Tabs",
    .title = @"Close Button on Pinned Tabs",
    .detail = @"Show the close button when you point at a pinned tab outside a folder, as Dia does for tabs in a pinned folder.",
    .symbol = @"xmark.circle.fill",
    .tint = @"systemPinkColor",
    .classes = DPClasses(DPDiaTabView, DPDiaHoverTracker),
    .install = DPInstallPinnedTabCloseButton,
    .apply = DPApplyPinnedTabCloseButton,
    .verify = DPVerifyPinnedTabCloseButton,
};
