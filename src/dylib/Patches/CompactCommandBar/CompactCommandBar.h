#import "StdPatch/StdPatch.h"
#import "Patches/TurnOffAI/TurnOffAI.h"

extern DPPatch DPCompactCommandBar, DPCompactWithChat;

NSView *DPCommandBarPart(NSView *commandBar, const char *className);
BOOL DPChatLocked(NSView *view);
NSView *DPCompactToolbar(NSView *commandBar);
void DPRememberChatLocked(BOOL locked);
NSView *DPGoButton(NSView *toolbar);
void DPApplyCompactCommandBar(DPPatch *patch);
CGFloat DPTrim(NSView *container);
void DPSetTrim(NSView *container, CGFloat trim);
NSSize DPCompactSize(NSView *container, NSSize size);
void DPInstallCommandBarLayout(void);
void DPInstallNewTabLayout(void);
BOOL DPTrimsPanel(NSView *panel);
