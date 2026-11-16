#import "StdPatch/StdPatch.h"

extern DPPatch DPDeclineAppConnectPrompts;

static NSArray<NSButton *> *DPDialogButtons(NSView *view) {
    if (DPIsKind(view, DPDiaDialogButton)) return @[ (NSButton *)view ];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSView *sub in view.subviews) [buttons addObjectsFromArray:DPDialogButtons(sub)];
    return buttons;
}

// The dialog lays its buttons out left to right, Not Now first and Connect, the one Return presses, last.
static NSButton *DPNotNowButton(NSView *content) {
    NSView *panel = content;
    while (panel && !DPIsKind(panel, DPDiaDialogPanel)) panel = panel.superview;
    NSArray<NSButton *> *buttons = [DPDialogButtons(panel) sortedArrayUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) {
        return [@(NSMinX([a convertRect:a.bounds toView:nil])) compare:@(NSMinX([b convertRect:b.bounds toView:nil]))];
    }];
    return buttons.count == 2 ? buttons.firstObject : nil;
}

static void DPDecline(NSView *content, NSWindow *dialog, int triesLeft) {
    if (content.window != dialog) return;
    NSButton *notNow = DPNotNowButton(content);
    if (notNow && dialog.visible) return (void)(NSLog(@"DiaPatches: declined Dia's connect-app dialog"), [notNow performClick:nil]);
    if (triesLeft > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPDecline(content, dialog, triesLeft - 1); });
        return;
    }
    // Hidden and unanswered, the dialog would leave Dia waiting with no way to answer it.
    dialog.alphaValue = 1;
    NSLog(@"DiaPatches: couldn't find Not Now in Dia's connect-app dialog, so it stays");
}

static void DPUpsellContent_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPUpsellContent_viewDidMoveToWindow, self);
    NSWindow *dialog = self.window;
    if (!DPDeclineAppConnectPrompts.on || !dialog) return;
    // Only the dialog's own panel: if Dia ever hosts this view in a browser window, hiding it would hide the browser.
    if (DPIsKind(dialog.windowController, DPDiaDialogWindowController)) dialog.alphaValue = 0;
    DPDecline(self, dialog, 40);
}

static void DPInstallDeclineAppConnectPrompts(void) {
    DPHookClass(objc_getClass(DPDiaAppUpsellContent), @selector(viewDidMoveToWindow), (IMP)DPUpsellContent_viewDidMoveToWindow);
}

DP_PATCH(DPDeclineAppConnectPrompts) {
    .key = @"declineAppConnectPrompts",
    .order = 96,
    .title = @"Decline App Connect Prompts",
    .detail = @"Answer Not Now for you when Dia asks to connect an app like Notion or Slack to its chat, in every profile, so the prompt never shows.",
    .symbol = @"link.badge.plus",
    .tint = @"systemPurpleColor",
    .section = @"AI",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Decline-app-connect-prompts.md",
    .classes = DPClasses(DPDiaAppUpsellContent, DPDiaDialogPanel, DPDiaDialogButton),
    .install = DPInstallDeclineAppConnectPrompts,
};
