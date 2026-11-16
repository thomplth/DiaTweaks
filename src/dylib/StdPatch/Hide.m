#import "StdPatch/Hide.h"
#import <dlfcn.h>

NSHashTable<NSView *> *DPHideHosts, *DPSuppressed;
static char DPHidersKey;

// Only a match is cached: some views only match once Dia labels them.
static NSArray<NSValue *> *DPHiders(NSView *view) {
    NSArray<NSValue *> *cached = DPGet(view, &DPHidersKey);
    if (cached) return cached;
    NSMutableArray<NSValue *> *hiders = [NSMutableArray array];
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPPatches[i]->hides && !DPPatches[i]->unavailable && DPPatches[i]->hides(view)) [hiders addObject:[NSValue valueWithPointer:DPPatches[i]]];
    if (hiders.count) DPSet(view, &DPHidersKey, hiders);
    return hiders;
}

DPPatch *DPHider(NSView *view) {
    NSArray<NSValue *> *hiders = DPHiders(view);
    for (NSValue *hider in hiders)
        if (((DPPatch *)hider.pointerValue)->on) return hider.pointerValue;
    return hiders.firstObject.pointerValue;
}

static void DPHidden_setHidden(NSView *self, SEL _cmd, BOOL hidden) {
    DPPatch *patch = DPHider(self);
    BOOL suppress = !hidden && patch && patch->on;
    if (suppress) [DPSuppressed addObject:self];
    else [DPSuppressed removeObject:self];
    DPCallOriginal(DPHidden_setHidden, self, hidden || suppress);
}

// Before the window shows, Dia only hides views that report visible, so lie to Dia's code then.
static BOOL DPHidden_isHidden(NSView *self, SEL _cmd) {
    Dl_info caller;
    if (!self.window.isVisible && [DPSuppressed containsObject:self] && dladdr(__builtin_return_address(0), &caller)
        && strstr(caller.dli_fname, "/Dia.app/"))
        return NO;
    return DPCallOriginal(DPHidden_isHidden, self);
}

static void DPEnforce(NSView *view) {
    DPPatch *patch = DPHider(view);
    if (!patch) return;
    DPHookClass(view.class, @selector(setHidden:), (IMP)DPHidden_setHidden);
    DPHookClass(view.class, @selector(isHidden), (IMP)DPHidden_isHidden);
    if (!patch->on || view.hidden) return;
    DPHidden_setHidden(view, @selector(setHidden:), NO);
}

static void DPHidden_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPHidden_viewDidMoveToWindow, self);
    DPEnforce(self);
}

void DPEnforceHides(NSView *root) {
    if (!DPHider(root)) {
        for (NSView *sub in root.subviews) DPEnforceHides(sub);
        return;
    }
    DPHookClass(root.class, @selector(viewDidMoveToWindow), (IMP)DPHidden_viewDidMoveToWindow);
    DPEnforce(root);
}

void DPApplyHides(DPPatch *patch) {
    if (patch->on) for (NSView *host in DPHideHosts.allObjects) DPEnforceHides(host);
    else for (NSView *view in DPSuppressed.allObjects) if (!DPHider(view)->on) view.hidden = NO;
    DPRelayoutViews(DPHideHosts);
}

static NSString *DPProblem(NSView *view, DPPatch *patch) {
    DPPatch *owner = DPHider(view);
    if (owner) {
        if (![DPHiders(view) containsObject:[NSValue valueWithPointer:patch]]) return nil;
        if (patch->on && !view.hiddenOrHasHiddenAncestor) return @"button still shows";
        return !owner->on && [DPSuppressed containsObject:view] ? @"button still hidden" : nil;
    }
    for (NSView *sub in view.subviews) {
        NSString *problem = DPProblem(sub, patch);
        if (problem) return problem;
    }
    return nil;
}

NSString *DPVerifyHides(DPPatch *patch) {
    NSHashTable<NSView *> *hosts = [DPHideHosts copy];
    for (const char *const *name = DPHideHostClasses; *name; name++) for (NSView *host in DPFindViews(*name)) [hosts addObject:host];
    if (!hosts.count) return @"no toolbar or tab bar found";
    for (NSView *host in hosts) {
        NSString *problem = host.window.isVisible ? DPProblem(host, patch) : nil;
        if (problem) return problem;
    }
    return nil;
}

void DPInstallHides(void) {
    DPHideHosts = [NSHashTable weakObjectsHashTable];
    DPSuppressed = [NSHashTable weakObjectsHashTable];
    for (NSUInteger i = 0; i < DPPatchCount; i++) if (DPPatches[i]->hides) return DPInstallHideHosts();
}
