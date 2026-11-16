#import "HideToolbar.h"

extern DPPatch DPToggleToolbarVisibility;
static id DPKeyMonitor;
static NSDictionary *DPDefaultToggleToolbarShortcut(void) { return @{ @"keyCode" : @2, @"modifiers" : @(NSEventModifierFlagControl), @"key" : @"D" }; }

static void DPInstallToggleToolbar(void) {
    DPKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (!DPToggleToolbarVisibility.on || !DPShortcutMatches(event, &DPToggleToolbarVisibility)) return event;
        if (!event.isARepeat) {
            DPSetPatch(&DPHideToolbar, !DPHideToolbar.on, YES);
            [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        }
        return nil;
    }];
}

// Without an apply, toggling eases and relayouts every patch.
static void DPApplyToggleToolbar(DPPatch *patch) {}

static NSString *DPVerifyToggleToolbar(DPPatch *patch) { return DPKeyMonitor ? nil : @"nothing listens for the shortcut"; }

DP_PATCH(DPToggleToolbarVisibility) {
    .key = @"toggleToolbarVisibility",
    .order = 35,
    .title = @"Toggle toolbar visibility",
    .detail = @"Hide or show the toolbar with a keyboard shortcut, ⌃D unless you set another.",
    .symbol = @"command",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .section = @"Showing the Toolbar",
    .classes = DPClasses(DPDiaContentPane, DPDiaToolbar),
    .install = DPInstallToggleToolbar,
    .shortcut = @"toggleToolbarShortcut",
    .defaultShortcut = DPDefaultToggleToolbarShortcut,
    .apply = DPApplyToggleToolbar,
    .verify = DPVerifyToggleToolbar,
};
