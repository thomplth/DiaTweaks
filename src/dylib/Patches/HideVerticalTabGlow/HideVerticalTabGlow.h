#import "StdPatch/StdPatch.h"

#define DPVerticalSidebarRoot "_TtC10TabSidebar15SidebarRootView"
extern DPPatch DPHideVerticalTabGlow;
BOOL DPIsVerticalTab(NSView *shape);
id DPTabDecoration(NSView *shape, const char *name);
BOOL DPHasTabOverride(id part);
void DPHideTabDecoration(id part, NSView *shape);
void DPRestoreTabDecoration(id part);
void DPFlattenTabMaterial(NSView *view, NSView *shape);
NSString *DPVerifyFlatTabMaterial(NSView *shape, BOOL on);
void DPInstallFlatTabMaterial(void);
void DPStyleUniformTabBorder(NSView *shape);
NSString *DPVerifyUniformTabBorder(NSView *shape, BOOL on);
