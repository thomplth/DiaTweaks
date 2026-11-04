#import "HideToolbar.h"

// Dia confirms a copied URL in the address field, which is out of sight while the toolbar is hidden. These options show
// it some other way. Both follow Dia's own menu items, so ⇧⌘C and ⌥⇧⌘C keep doing what Dia does.

// What Dia's address field says after each Copy URL item in the Edit menu.
static NSString *DPCopiedMessage(NSMenuItem *item) {
    if ([item.title isEqual:@"Copy URL"]) return @"Copied current URL";
    if ([item.title isEqual:@"Copy URL as Markdown"]) return @"Copied URL as Markdown";
    return nil;
}

// The pane with the focused page: Dia copies its URL.
static NSView *DPFocusedPane(void) {
    NSWindow *window = NSApp.keyWindow;
    NSResponder *responder = window.firstResponder;
    NSView *first = nil;
    for (NSView *pane in DPPanes) {
        if (pane.window != window || pane.hiddenOrHasHiddenAncestor) continue;
        if ([responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:pane]) return pane;
        first = first ?: pane;
    }
    return first;
}

static void DPCopiedURL(NSNotification *notification) {
    NSString *message = DPCopiedMessage(notification.userInfo[@"MenuItem"]);
    NSView *pane = message && DPHideToolbar.on ? DPFocusedPane() : nil;
    DPToolbarHover *hover = [DPToolbarHover forPane:pane];
    if (!hover || hover.inPlace) return;  // Dia's own message shows in the toolbar.
    if (DPPeekToolbarOnCopy.on) [hover peek];
    else if (DPCopyToast.on && hover.progress == 0) DPShowCopyToast(pane, message);
}

static void DPInstallCopyURL(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidSendActionNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *notification) { DPCopiedURL(notification); }];
    });
}

static void DPApplyPeekOnCopy(DPPatch *patch) {
    if (patch->on) return;
    for (NSView *pane in DPPanes) [[DPToolbarHover forPane:pane] endPeek];
}

static void DPApplyCopyToast(DPPatch *patch) {
    if (!patch->on || DPPeekToolbarOnCopy.on) DPRemoveCopyToasts();
}

static NSString *DPVerifyPeekOnCopy(DPPatch *patch) {
    for (NSView *pane in DPFindViews(DPDiaContentPane))
        if ([DPToolbarHover forPane:pane].peeking && !patch->on) return @"toolbar still peeking";
    return nil;
}

DP_PATCH(DPPeekToolbarOnCopy) {
    .key = @"peekToolbarOnCopy",
    .order = 41,
    .title = @"Show Toolbar When Copying URL",
    .detail = @"Show the toolbar for a moment after ⇧⌘C, so you see Dia's Copied message.",
    .symbol = @"link",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .builtIn = DPClasses(DPDiaToasts),
    .install = DPInstallCopyURL,
    .apply = DPApplyPeekOnCopy,
    .verify = DPVerifyPeekOnCopy,
};

DP_PATCH(DPCopyToast) {
    .key = @"copyURLToast",
    .order = 42,
    .title = @"Show Toast When Copying URL",
    .detail = @"Show a small Copied message at the top of the page after ⇧⌘C, and keep the toolbar hidden.",
    .symbol = @"checkmark.message.fill",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .builtIn = DPClasses(DPDiaToasts),
    .disabledBy = @"peekToolbarOnCopy",
    .install = DPInstallCopyURL,
    .apply = DPApplyCopyToast,
    .verify = DPVerifyNoCopyToast,
};
