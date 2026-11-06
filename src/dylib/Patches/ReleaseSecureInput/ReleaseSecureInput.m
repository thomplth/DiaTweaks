#import <Carbon/Carbon.h>
#import "StdPatch/StdPatch.h"

extern DPPatch DPReleaseSecureInput;

@interface NSView (DPWebTextInput)
- (int)textInputType;
- (int)textInputFlags;
@end

static const int DPTextInputTypePassword = 2;
static const int DPTextInputFlagsOfPasswordFields = 0x5000;

static NSInteger DPSecureInputHolds;
static BOOL DPSecureInputWithheld;

static void DPWithholdSecureInput(BOOL withhold) {
    if (withhold == DPSecureInputWithheld) return;
    DPSecureInputWithheld = withhold;
    for (NSInteger hold = 0; hold < DPSecureInputHolds; hold++) {
        if (withhold) DisableSecureEventInput();
        else EnableSecureEventInput();
    }
}

static BOOL DPDiaLacksKeyboardFocus(void) { return !NSApp.active && !NSApp.keyWindow; }

// macOS counts these calls per process, and Dia's Chromium still balances its own while withheld, so the count has to
// keep following Dia's calls for the handback to match what Dia currently holds.
static OSStatus DPEnableSecureInput(void) {
    DPSecureInputHolds++;
    if (!DPSecureInputWithheld) return EnableSecureEventInput();
    if (!DPDiaLacksKeyboardFocus()) DPWithholdSecureInput(NO);
    return noErr;
}

static OSStatus DPDisableSecureInput(void) {
    DPSecureInputHolds--;
    return DPSecureInputWithheld ? noErr : DisableSecureEventInput();
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *replacement, *replacee; } DPInterposeSecureInput[] = {
    {(const void *)DPEnableSecureInput, (const void *)EnableSecureEventInput},
    {(const void *)DPDisableSecureInput, (const void *)DisableSecureEventInput},
};

// Dia's Chromium only rechecks its hold when focus or the key window changes, so it outlives a field that blurs, is
// removed or is navigated away from. Anything but a web view keeps what Dia decided, which covers native secure fields.
static BOOL DPWebViewLeftPasswordField(void) {
    NSView *responder = (NSView *)NSApp.keyWindow.firstResponder;
    if (!DPIsKind(responder, DPDiaWebView)) return NO;
    return responder.textInputType != DPTextInputTypePassword && !(responder.textInputFlags & DPTextInputFlagsOfPasswordFields);
}

static BOOL DPSecureInputIsStale(void) { return DPDiaLacksKeyboardFocus() || DPWebViewLeftPasswordField(); }

static void DPSyncSecureInput(void) { DPWithholdSecureInput(DPReleaseSecureInput.on && DPSecureInputIsStale()); }

static void DPSyncSecureInputSoon(void) { dispatch_async(dispatch_get_main_queue(), ^{ DPSyncSecureInput(); }); }

static void DPWebView_setTextInputType(NSView *self, SEL _cmd, int type) {
    DPCallOriginal(DPWebView_setTextInputType, self, type);
    DPSyncSecureInput();
}

static void DPWebView_setTextInputFlags(NSView *self, SEL _cmd, int flags) {
    DPCallOriginal(DPWebView_setTextInputFlags, self, flags);
    DPSyncSecureInput();
}

static BOOL DPWebView_resignFirstResponder(NSView *self, SEL _cmd) {
    BOOL resigned = DPCallOriginal(DPWebView_resignFirstResponder, self);
    DPSyncSecureInputSoon();
    return resigned;
}

static void DPApplyReleaseSecureInput(DPPatch *patch) { DPSyncSecureInput(); }

static NSString *DPVerifyReleaseSecureInput(DPPatch *patch) {
    if (!patch->on && DPSecureInputWithheld) return @"Secure Input is withheld with the tweak off";
    if (patch->on && DPSecureInputIsStale() && !DPSecureInputWithheld) return @"Secure Input is kept without a password field";
    return nil;
}

static void DPObserve(NSNotificationName name, void (^handler)(void)) {
    [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *_) { handler(); }];
}

static void DPInstallReleaseSecureInput(void) {
    DPHook(DPDiaWebView, @selector(setTextInputType:), (IMP)DPWebView_setTextInputType);
    DPHook(DPDiaWebView, @selector(setTextInputFlags:), (IMP)DPWebView_setTextInputFlags);
    DPHook(DPDiaWebView, @selector(resignFirstResponder), (IMP)DPWebView_resignFirstResponder);
    void (^handBack)(void) = ^{
        DPWithholdSecureInput(NO);
        DPSyncSecureInputSoon();
    };
    DPObserve(NSApplicationWillBecomeActiveNotification, ^{ DPWithholdSecureInput(NO); });
    DPObserve(NSWindowDidBecomeKeyNotification, handBack);
    DPObserve(NSApplicationDidBecomeActiveNotification, ^{ DPSyncSecureInput(); });
    DPObserve(NSApplicationDidResignActiveNotification, ^{ DPSyncSecureInput(); });
    DPObserve(NSWindowDidResignKeyNotification, ^{ DPSyncSecureInput(); });
    DPSyncSecureInput();
}

DP_PATCH(DPReleaseSecureInput) {
    .key = @"releaseSecureInput",
    .defaultOn = YES,
    .order = 103,
    .title = @"Release Secure Input Outside Password Fields",
    .detail = @"Stop Dia blocking other apps' keyboard shortcuts after you leave a password field or switch to another app. The protection stays on while you type a password.",
    .symbol = @"lock.open.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Release-secure-input-outside-password-fields.md",
    .classes = DPClasses(DPDiaWebView),
    .install = DPInstallReleaseSecureInput,
    .apply = DPApplyReleaseSecureInput,
    .verify = DPVerifyReleaseSecureInput,
};
