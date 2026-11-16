#import "StdPatch/StdPatch.h"

extern DPPatch DPPullRequestRepo;

BOOL DPIsPRSubtitle(NSView *label);
NSView *DPEnclosingView(NSView *view, const char *className);
NSDictionary *DPPullRequestOf(NSView *view);
void DPRefreshPRSubtitles(void);
void DPInstallPRSubtitles(void);

@interface DPPRStatusLine : NSTextField
@end
void DPSetPRStatus(NSView *subtitle, NSString *tab, NSString *status);
void DPResetPRRows(void);
void DPInstallPRRows(void);
