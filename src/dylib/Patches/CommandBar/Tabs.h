#import "StdPatch/StdPatch.h"

id DPScriptWindow(NSWindow *window);
id DPScriptTab(NSWindow *window, NSString *tabID);
NSString *DPTabID(id tab);
NSString *DPActiveTabID(NSWindow *window);
void DPFocusTab(id tab);
void DPCloseTab(id tab);
// Dia doesn't say who closes a page: DPCloseTab marks its own close, DPMarkOwnClose one made another way, and the closing page takes the mark.
void DPMarkOwnClose(void);
BOOL DPTakeOwnClose(void);
