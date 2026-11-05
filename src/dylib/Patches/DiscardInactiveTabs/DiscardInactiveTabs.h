#import "StdPatch/StdPatch.h"

extern DPPatch DPDiscardInactiveTabs;

BOOL DPDelegateShowsTabPage(id delegate);
NSDictionary<NSString *, NSString *> *DPLoadedPaneStates(void);
NSArray<NSString *> *DPPanesOfRow(NSView *row);
NSArray<NSString *> *DPPanesOfDockItem(NSView *item);
BOOL DPRowHasNoCloseButton(NSView *row);

NSArray<NSString *> *DPPanesOfTabView(NSView *view);
NSArray<NSString *> *DPDressTabView(NSView *view, NSDictionary *states);
void DPClearTabView(NSView *view);
NSString *DPVerifyTabIndicators(void);

void DPInstallTabTracking(void);
void DPTrackTabView(NSView *view);
BOOL DPIsTabViewTracked(NSView *view);
void DPRequestTabStates(void);
void DPSweepTabViews(void);
void DPRefreshTabIndicators(void);
void DPClearTabIndicators(void);

void DPInstallDiscarder(void);
void DPDiscardIdleTabs(NSTimeInterval limit);
BOOL DPIsKeptSite(NSString *url);
