#import <Carbon/Carbon.h>
#import "StdPatch/StdPatch.h"

extern DPPatch DPReleaseSecureInput;

static NSInteger DPSecureInputHolds;
static BOOL DPSecureInputWithheld;

// macOS counts these calls per process, and Dia's Chromium still balances its own while withheld, so the count has to
// keep following Dia's calls for the handback to match what Dia currently holds.
static OSStatus DPEnableSecureInput(void) {
    DPSecureInputHolds++;
    return DPSecureInputWithheld ? noErr : EnableSecureEventInput();
}

static OSStatus DPDisableSecureInput(void) {
    DPSecureInputHolds--;
    return DPSecureInputWithheld ? noErr : DisableSecureEventInput();
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *replacement, *replacee; } DPInterposeSecureInput[] = {
    {(const void *)DPEnableSecureInput, (const void *)EnableSecureEventInput},
    {(const void *)DPDisableSecureInput, (const void *)DisableSecureEventInput},
};

static void DPWithholdSecureInput(BOOL withhold) {
    if (withhold == DPSecureInputWithheld) return;
    DPSecureInputWithheld = withhold;
    for (NSInteger hold = 0; hold < DPSecureInputHolds; hold++) {
        if (withhold) DisableSecureEventInput();
        else EnableSecureEventInput();
    }
}

static BOOL DPDiaLacksKeyboardFocus(void) { return !NSApp.active && !NSApp.keyWindow; }

static void DPSyncSecureInput(void) { DPWithholdSecureInput(DPReleaseSecureInput.on && DPDiaLacksKeyboardFocus()); }

static void DPApplyReleaseSecureInput(DPPatch *patch) { DPSyncSecureInput(); }

static NSString *DPVerifyReleaseSecureInput(DPPatch *patch) {
    if (!patch->on && DPSecureInputWithheld) return @"Secure Input is withheld with the tweak off";
    if (patch->on && DPDiaLacksKeyboardFocus() && !DPSecureInputWithheld) return @"Secure Input is kept in the background";
    return nil;
}

static void DPObserve(NSNotificationName name, void (^handler)(void)) {
    [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *_) { handler(); }];
}

static void DPInstallReleaseSecureInput(void) {
    void (^handBack)(void) = ^{ DPWithholdSecureInput(NO); };
    DPObserve(NSApplicationWillBecomeActiveNotification, handBack);
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
    .title = @"Release Secure Input in Background",
    .detail = @"Stop a focused password field from blocking other apps' keyboard shortcuts after you leave Dia. Dia turns the protection back on before you can type in it again.",
    .symbol = @"lock.open.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Release-secure-input-in-background.md",
    .install = DPInstallReleaseSecureInput,
    .apply = DPApplyReleaseSecureInput,
    .verify = DPVerifyReleaseSecureInput,
};
