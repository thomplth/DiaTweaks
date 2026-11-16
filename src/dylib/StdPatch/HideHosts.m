#import "StdPatch/Hide.h"

const char *const DPHideHostClasses[] = {DPDiaToolbar, DPDiaSidebarHeader, DPDiaSidebarFooter, DPDiaNewTabPage, NULL};
static char DPGrownKey;

static void DPCenterSpaceSwitcher(NSView *footer) {
    NSView *switcher = DPSubview(footer, DPDiaSpaceSwitcher);
    BOOL patched = NO;
    for (NSView *sub in footer.subviews) patched |= [DPSuppressed containsObject:sub];
    if (!switcher || !patched) return;
    CGFloat inset = MAX(NSMinX(switcher.frame), NSWidth(footer.bounds) - NSMaxX(switcher.frame));
    switcher.frame = NSMakeRect(inset, NSMinY(switcher.frame), NSWidth(footer.bounds) - 2 * inset, NSHeight(switcher.frame));
}

static void DPBar_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPBar_layout, self);
    if (DPIsKind(self, DPDiaSidebarFooter)) DPCenterSpaceSwitcher(self);
}

static void DPSetHeight(NSView *view, CGFloat height) {
    [view setFrameSize:NSMakeSize(NSWidth(view.frame), height)];
}

static void DPSidebar_viewDidLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPSidebar_viewDidLayout, self);
    NSView *sidebar = self.view, *footer = DPSubview(sidebar, DPDiaSidebarFooter);
    [DPHideHosts addObject:sidebar];
    if (!footer || !sidebar.isFlipped || !DPMayAdjust(footer)) return;
    DPEnforceHides(footer);
    BOOL empty = NO, hidden = YES;
    for (NSView *item in footer.subviews) {
        DPPatch *patch = DPHider(item);
        hidden &= item.hidden && (!patch || patch->on);
        empty |= patch != NULL;
    }
    empty &= hidden;
    NSHashTable<NSView *> *grown = DPGet(footer, &DPGrownKey);
    if (empty) {
        if (!grown) DPSet(footer, &DPGrownKey, grown = [NSHashTable weakObjectsHashTable]);
        footer.hidden = YES;
        for (NSView *sub in sidebar.subviews) {
            if (sub == footer || fabs(NSMaxY(sub.frame) - NSMinY(footer.frame)) > 0.5) continue;
            DPSetHeight(sub, NSMaxY(footer.frame) - NSMinY(sub.frame));
            [grown addObject:sub];
        }
    } else if (grown) {
        DPSet(footer, &DPGrownKey, nil);
        footer.hidden = NO;
        for (NSView *sub in grown)
            if (fabs(NSMaxY(sub.frame) - NSMaxY(footer.frame)) < 0.5) DPSetHeight(sub, NSMinY(footer.frame) - NSMinY(sub.frame));
    }
}

static void DPTabStrip_viewWillLayout(NSViewController *self, SEL _cmd) {
    [DPHideHosts addObject:self.view];
    for (NSView *sub in self.view.subviews) if (DPHider(sub)) DPEnforceHides(sub);
    DPCallOriginal(DPTabStrip_viewWillLayout, self);
}

void DPInstallHideHosts(void) {
    for (const char *const *host = DPHideHostClasses; *host; host++) DPHook(*host, @selector(layout), (IMP)DPBar_layout);
    DPHook(DPDiaSidebarController, @selector(viewDidLayout), (IMP)DPSidebar_viewDidLayout);
    DPHook(DPDiaTabStripController, @selector(viewWillLayout), (IMP)DPTabStrip_viewWillLayout);
}
