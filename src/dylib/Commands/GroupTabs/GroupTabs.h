#import "StdPatch/StdPatch.h"

extern DPPatch DPGroupTabs, DPGroupTabsMergeSubdomains;

void DPInstallGroupTabs(void);

id DPCommandBrowser(void);
NSWindow *DPBrowserWindow(id browser);
id DPBrowserOfWindow(NSWindow *window);
NSArray *DPTrackedBrowsers(void);
id DPGroupingDelegate(id browser);
NSArray *DPTrackedContents(id browser);
long long DPSessionOf(id contents);
long long DPActiveSession(id browser);  // 0 when the tab in front can't be told from the others.

long long DPLongID(id value);
id DPMsg(id object, SEL sel);
BOOL DPMsgBool(id object, SEL sel);
NSString *DPText(id value);

NSString *DPDomainKey(NSString *urlString);
NSString *DPGroupTitle(NSString *domain);
NSArray<NSDictionary *> *DPOps(NSArray<NSDictionary *> *tabs, NSArray *groups);
NSString *DPRegistrableDomain(NSString *host);

void DPMoveTab(id delegate, id browser, NSNumber *sid, NSInteger index, void (^done)(void), void (^failed)(void));
NSDictionary *DPTabPlaces(NSDictionary<NSNumber *, NSString *> *urls);
void DPRestorePlaces(id delegate, id browser, NSDictionary *places);

void DPGroupTabsOnce(void);
void DPGroupSelectedTabsOnce(void);
NSSet<NSNumber *> *DPSelectedSessions(id browser);
BOOL DPCanReadSelection(id browser);
void DPSetAllGroupsCollapsed(BOOL collapsed);
extern CFTimeInterval DPFoldedAt;
void DPUngroupDomain(void);
void DPUngroupAllDomains(void);
void DPRunOps(id delegate, id browser, NSArray<NSDictionary *> *ops, NSUInteger index, void (^done)(void));
void DPOfferUndo(id delegate, id browser, NSArray *ids, NSDictionary *places);
void DPOfferRegroup(id delegate, id browser, NSArray<NSDictionary *> *ops);
BOOL DPCanUndoGrouping(void);
void DPForgetGroupingUndo(void);
void DPInstallGroupMenus(void);
void DPInstallGroupTabsShortcut(void);
NSDictionary *DPDefaultGroupTabsShortcut(void);
