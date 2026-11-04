#import "CompactCommandBar.h"

static char DPFullSizeKey;

// The panel is also Dia's chat, so only the new tab page's and Command bar's are trimmed. Command bar sets the size again
// as it lays out, so a trimmed size maps back to the full one before trimming.
static void DPAssistantPanel_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    NSValue *full = DPDiaValue(self, &DPFullSizeKey, [NSValue valueWithSize:size]);
    BOOL bar = DPIsKind(self.superview.superview, DPDiaNewTabPage) || DPIsKind(self.superview, "DPCommandBarOverlay");
    NSSize compact = bar ? DPCompactSize(self, full.sizeValue) : full.sizeValue;
    DPOverride(self, &DPFullSizeKey, full, [NSValue valueWithSize:compact]);
    DPSetTrim(self, full.sizeValue.height - compact.height);
    DPCallOriginal(DPAssistantPanel_setFrameSize, self, compact);
}

// Dia doesn't resize an open panel when the switch flips.
void DPResizeNewTabPanels(void) {
    for (NSView *panel in DPFindViews(DPDiaAssistantPanel)) {
        if (!DPIsKind(panel.superview.superview, DPDiaNewTabPage)) continue;
        NSSize size = panel.frame.size;
        size.height += DPTrim(panel);
        [panel setFrameSize:size];
        panel.superview.superview.needsLayout = YES;  // Moves the chat usage banner under the panel.
    }
}

void DPInstallNewTabLayout(void) {
    DPHook(DPDiaAssistantPanel, @selector(setFrameSize:), (IMP)DPAssistantPanel_setFrameSize);
}
