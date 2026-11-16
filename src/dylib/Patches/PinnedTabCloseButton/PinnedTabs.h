#import "StdPatch/StdPatch.h"

extern DPPatch DPPinnedTabCloseButton, DPPinnedTabMinusButton;

id DPViewModelDelegate(NSView *view);
NSView *DPEnclosingTab(NSView *view);
void DPRelayoutTabContents(void);

id DPAttributes(NSView *content);
BOOL DPIsOpenPinned(NSView *content);  // A TabContentView, not a TabView.
// NO, without calling `click`, if the tab has no close button style.
BOOL DPClickKeepingTab(NSView *content, void (^click)(void));
BOOL DPCloseKeepingTab(NSView *content);
