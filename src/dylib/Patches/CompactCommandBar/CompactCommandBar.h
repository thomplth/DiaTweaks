#import "StdPatch/StdPatch.h"

extern DPPatch DPCompactCommandBar, DPCompactWithChat;

NSView *DPCommandBarPart(NSView *commandBar, const char *className);
BOOL DPChatLocked(NSView *view);
NSView *DPCompactToolbar(NSView *commandBar);  // The bottom row while the patch applies to this command bar, else nil.
void DPRememberChatLocked(BOOL locked);
NSView *DPGoButton(NSView *toolbar);
void DPApplyCompactCommandBar(DPPatch *patch);
CGFloat DPTrim(NSView *container);  // How much the patch shortened a popover or panel.
void DPSetTrim(NSView *container, CGFloat trim);

// Layout.m
NSSize DPCompactSize(NSView *container, NSSize size);
void DPInstallCommandBarLayout(void);
void DPResizePopovers(void);

// NewTab.m
void DPInstallNewTabLayout(void);
void DPResizeNewTabPanels(void);
