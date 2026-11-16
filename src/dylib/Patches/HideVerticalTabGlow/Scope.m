#import "HideVerticalTabGlow.h"

BOOL DPIsVerticalTab(NSView *shape) {
    BOOL sidebar = NO;
    for (NSView *up = shape; up; up = up.superview) {
        if (DPIsKind(up, DPDiaTabStrip)) return NO;
        if (DPIsKind(up, DPVerticalSidebarRoot)) sidebar = YES;
    }
    return sidebar;
}
