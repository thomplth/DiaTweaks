#import "CompactCommandBar.h"

static char DPFullSizeKey;

BOOL DPTrimsPanel(NSView *panel) {
    return DPIsKind(panel.superview.superview, DPDiaNewTabPage) || DPIsKind(panel.superview, "DPCommandBarOverlay");
}

static void DPAssistantPanel_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    NSValue *full = DPDiaValue(self, &DPFullSizeKey, [NSValue valueWithSize:size]);
    NSSize compact = DPTrimsPanel(self) ? DPCompactSize(self, full.sizeValue) : full.sizeValue;
    DPOverride(self, &DPFullSizeKey, full, [NSValue valueWithSize:compact]);
    DPSetTrim(self, full.sizeValue.height - compact.height);
    DPCallOriginal(DPAssistantPanel_setFrameSize, self, compact);
}

void DPInstallNewTabLayout(void) {
    DPHook(DPDiaAssistantPanel, @selector(setFrameSize:), (IMP)DPAssistantPanel_setFrameSize);
}
