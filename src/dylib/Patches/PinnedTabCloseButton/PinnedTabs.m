#import "Patches/PinnedTabCloseButton/PinnedTabs.h"
#import <objc/message.h>

extern void *swift_unknownObjectWeakLoadStrong(void *reference);

// viewModel.delegate is a Swift weak reference, which DPSwiftValue can't read.
id DPViewModelDelegate(NSView *view) {
    void **viewModel = DPIvar(view, "viewModel");
    void *delegate = viewModel && *viewModel ? DPIvar((__bridge id)*viewModel, "delegate") : NULL;
    return delegate ? (__bridge_transfer id)swift_unknownObjectWeakLoadStrong(delegate) : nil;
}

NSView *DPEnclosingTab(NSView *view) {
    while (view && !DPIsKind(view, DPDiaTabView)) view = view.superview;
    return view;
}

void DPRelayoutTabContents(void) {
    for (NSView *content in DPFindViews(DPDiaTabContentView)) content.needsLayout = YES;
}

// The controller holds an enum whose other cases set top bits; only a web page's attributes pass.
id DPAttributes(NSView *content) {
    void **slot = DPIvar(DPViewModelDelegate(content), "attributesController");
    uintptr_t raw = slot ? (uintptr_t)*slot : 0;
    if (!raw || (raw & 0xF000000000000007)) return nil;
    id attributes = (__bridge id)(void *)raw;
    return DPIsKind(attributes, DPDiaTabPageAttributes) ? attributes : nil;
}

BOOL DPIsOpenPinned(NSView *content) {
    id attributes = DPAttributes(content);
    BOOL *pinned = DPIvar(attributes, "isInFavoritesOrPinnedContainer");
    void **activeURL = DPIvar(attributes, "activeURL");
    return pinned && *pinned && activeURL && *activeURL;
}

enum { DPCloseKeepingTabStyle = 1 };  // TabUI.TabCloseButtonStyle.closeKeepingTab.
static BOOL DPKeeping;  // A click made by DPCloseKeepingTab, which the minus button's hook sees too.

BOOL DPClickKeepingTab(NSView *content, void (^click)(void)) {
    if (DPKeeping) return click(), YES;
    uint8_t *style = DPIvar(DPViewModelDelegate(DPEnclosingTab(content)), "requestedCloseButtonStyle");
    if (!style) return NO;
    uint8_t dia = *style;
    *style = DPCloseKeepingTabStyle;
    DPKeeping = YES;
    click();
    DPKeeping = NO;
    *style = dia;
    // The page is gone, but Dia doesn't lay the tab out again while the pointer is on it, so the minus would stay.
    __weak NSView *weakContent = content;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{ weakContent.needsLayout = YES; });
    return YES;
}

BOOL DPCloseKeepingTab(NSView *content) {
    SEL clicked = NSSelectorFromString(@"closeButtonClicked");
    if (![content respondsToSelector:clicked]) return NO;
    return DPClickKeepingTab(content, ^{ ((void (*)(id, SEL))objc_msgSend)(content, clicked); });
}
