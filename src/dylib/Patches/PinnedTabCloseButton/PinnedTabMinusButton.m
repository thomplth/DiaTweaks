#import "Patches/PinnedTabCloseButton/PinnedTabs.h"

enum { DPDismiss = 2 };  // TabUI.TabCloseButtonStyle.

static NSImage *DPMinus;
static char DPDiaImageKey;

static id DPMinusController(NSView *content) {
    NSView *tab = DPEnclosingTab(content);
    if (!tab || !DPIsOpenPinned(content) || [DPSwiftValue(tab, @"contentViews") count] != 1) return nil;
    id controller = DPViewModelDelegate(tab);
    uint8_t *style = DPIvar(controller, "requestedCloseButtonStyle");
    return style && *style != DPDismiss ? controller : nil;
}

static BOOL DPMinusOn(void) { return DPPinnedTabCloseButton.on && DPPinnedTabMinusButton.on; }

static NSButton *DPCloseButton(NSView *content) {
    void **button = DPIvar(content, "$__lazy_storage_$_closeButton");
    return button && *button ? (__bridge NSButton *)*button : nil;
}

static void DPContent_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContent_layout, self);
    NSButton *button = DPCloseButton(self);
    NSImage *dia = DPDiaValue(button, &DPDiaImageKey, button.image);
    if (!dia) return;
    BOOL minus = DPMinusOn() && DPMinusController(self);
    if (minus) DPOverride(button, &DPDiaImageKey, dia, DPMinus);
    NSImage *shown = minus ? DPMinus : dia;
    if (button.image != shown) button.image = shown;
}

// The icon decides, so a click does what it showed; a stale icon keeps the tab rather than removing the pin.
static void DPContent_closeButtonClicked(NSView *self, SEL _cmd) {
    BOOL minus = DPMinusOn() && DPCloseButton(self).image == DPMinus;
    if (!(minus && DPClickKeepingTab(self, ^{ DPCallOriginal(DPContent_closeButtonClicked, self); })))
        DPCallOriginal(DPContent_closeButtonClicked, self);
}

static void DPApplyPinnedTabMinusButton(DPPatch *patch) { DPRelayoutTabContents(); }

static NSString *DPVerifyPinnedTabMinusButton(DPPatch *patch) {
    for (NSView *content in DPFindViews(DPDiaTabContentView)) {
        id controller = DPViewModelDelegate(content);
        NSButton *button = DPCloseButton(content);
        if (!controller || !button || content.needsLayout) continue;
        if (!DPIvar(controller, "attributesController")) return @"can't tell which tabs have a page open";
        id attributes = DPAttributes(content);
        if (attributes && !(DPIvar(attributes, "activeURL") && DPIvar(attributes, "isInFavoritesOrPinnedContainer")))
            return @"can't tell which tabs have a page open";
        BOOL minus = button.image == DPMinus;
        if (DPMinusOn() && DPMinusController(content) && !minus) return @"open pinned tab has no minus button";
        if (!DPMinusOn() && minus) return @"tab keeps the minus button";
    }
    return nil;
}

static void DPInstallPinnedTabMinusButton(void) {
    DPMinus = [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Close"];
    DPHook(DPDiaTabContentView, @selector(layout), (IMP)DPContent_layout);
    DPHook(DPDiaTabContentView, NSSelectorFromString(@"closeButtonClicked"), (IMP)DPContent_closeButtonClicked);
}

DP_PATCH(DPPinnedTabMinusButton) {
    .key = @"pinnedTabMinusButton",
    .order = 86,
    .title = @"Minus Button on Open Pinned Tabs",
    .detail = @"Show a minus button instead on pinned tabs with a page open, in or out of a folder, as in Arc. It closes the page and keeps the tab pinned.",
    .symbol = @"minus.circle.fill",
    .tint = @"systemPinkColor",
    .requires = @"pinnedTabCloseButton",
    .classes = DPClasses(DPDiaTabView, DPDiaTabContentView, DPDiaTabPageAttributes),
    .install = DPInstallPinnedTabMinusButton,
    .apply = DPApplyPinnedTabMinusButton,
    .verify = DPVerifyPinnedTabMinusButton,
};
