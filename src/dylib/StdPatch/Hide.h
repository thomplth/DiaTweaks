#import "StdPatch/StdPatch.h"

extern NSHashTable<NSView *> *DPHideHosts;
extern NSHashTable<NSView *> *DPSuppressed;
extern const char *const DPHideHostClasses[];

DPPatch *DPHider(NSView *view);
void DPEnforceHides(NSView *root);
void DPApplyHides(DPPatch *patch);
NSString *DPVerifyHides(DPPatch *patch);
void DPInstallHides(void);
void DPInstallHideHosts(void);
