#import "GrainView.h"

extern DPPatch DPSidebarGrain;
extern NSHashTable<NSView *> *DPGrainHosts;

NSInteger DPGrainAmount(NSString *space);
NSInteger DPGrainSoftness(NSString *space);
NSInteger DPGrainScale(NSString *space);
NSString *DPGrainMaterial(NSString *space);
BOOL DPGrainShown(NSString *space);
NSString *DPGrainSpaceOf(NSView *host);
NSMenu *DPGrainTextureMenu(void);
NSArray<NSView *> *DPGrainRows(void);
void DPGrainRowsFor(NSArray<NSView *> *rows, NSString *space, void (^reset)(void));
BOOL DPGrainHasOverrides(NSString *space);
void DPRefreshSidebarGrain(void);
NSEvent *DPGrainRightClick(NSEvent *event);

BOOL DPGrainHostAvailable(NSView *host);
void DPTrackGrainHost(NSView *host);
NSString *DPVerifyGrainHosts(DPPatch *patch);
