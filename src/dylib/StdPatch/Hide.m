#import "StdPatch/Hide.h"
#import <dlfcn.h>

NSHashTable<NSView *> *DPHideHosts, *DPSuppressed;
static char DPHiderKey;

DPPatch *DPHider(NSView *view) {
    NSValue *cached = DPGet(view, &DPHiderKey);
    if (cached) return cached.pointerValue;
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        if (!DPPatches[i]->hides || DPPatches[i]->unavailable || !DPPatches[i]->hides(view)) continue;
        DPSet(view, &DPHiderKey, [NSValue valueWithPointer:DPPatches[i]]);
        return DPPatches[i];
    }
    return NULL;
}

// Dia shows and hides these views itself, so a patch keeps saying no while it's on.
static void DPHidden_setHidden(NSView *self, SEL _cmd, BOOL hidden) {
    DPPatch *patch = DPHider(self);
    BOOL suppress = !hidden && patch && patch->on;
    if (suppress) [DPSuppressed addObject:self];
    else [DPSuppressed removeObject:self];
    DPCallOriginal(DPHidden_setHidden, self, hidden || suppress);
}

// As its window appears, Dia hides some views, but only ones that say they're showing. Until then, a view the patch hid
// tells Dia it's showing, as Dia left it. Dia's layout afterwards and AppKit get the truth, or they'd leave its space.
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
    // As if Dia showed it again: the hook hides it and remembers to restore it.
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
    else for (NSView *view in DPSuppressed.allObjects) if (DPHider(view) == patch) view.hidden = NO;
    DPRelayoutViews(DPHideHosts);
}

static NSString *DPProblem(NSView *view, DPPatch *patch) {
    DPPatch *owner = DPHider(view);
    if (owner) {
        if (owner != patch) return nil;
        if (patch->on && !view.hiddenOrHasHiddenAncestor) return @"button still shows";
        return !patch->on && [DPSuppressed containsObject:view] ? @"button still hidden" : nil;
    }
    for (NSView *sub in view.subviews) {
        NSString *problem = DPProblem(sub, patch);
        if (problem) return problem;
    }
    return nil;
}

// A view that isn't there passes: not every layout has every button.
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
