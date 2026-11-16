#import "StdPatch/Hide.h"

static BOOL DPIsUpgradeBanner(NSView *view) { return DPIsKind(view, DPDiaChatUsage); }

static void DPChatUsage_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPChatUsage_layout, self);
}

static void DPInstallHideUpgradeBanner(void) {
    DPHook(DPDiaChatUsage, @selector(layout), (IMP)DPChatUsage_layout);
}

DP_PATCH(DPHideUpgradeBanner) {
    .key = @"hideUpgradeBanner",
    .order = 95,
    .section = @"AI",
    .title = @"Hide Upgrade Banner",
    .detail = @"Hide the “Looking for chat?” upgrade banner under the command bar.",
    .symbol = @"crown.fill",
    .tint = @"systemPurpleColor",
    .classes = DPClasses(DPDiaChatUsage),
    .hides = DPIsUpgradeBanner,
    .install = DPInstallHideUpgradeBanner,
    .coveredBy = @"turnOffAI",
};
