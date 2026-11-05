#import "StdPatch/StdPatch.h"

extern DPPatch DPDiscardInactiveTabs;

BOOL DPDelegateShowsTabPage(id delegate);
NSDictionary<NSString *, NSString *> *DPLoadedPaneStates(void);
NSArray<NSString *> *DPPanesOfRow(NSView *row);
NSArray<NSString *> *DPPanesOfDockItem(NSView *item);
BOOL DPRowHasNoCloseButton(NSView *row);

void DPRefreshTabIndicators(void);
void DPScheduleTabRefresh(void);
void DPClearTabIndicators(void);
NSString *DPVerifyTabIndicators(void);

void DPInstallDiscarder(void);
void DPDiscardIdleTabs(NSTimeInterval limit);
BOOL DPIsKeptSite(NSString *url);
