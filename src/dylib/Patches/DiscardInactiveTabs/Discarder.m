#import "DiscardInactiveTabs.h"
#import <objc/message.h>

typedef NS_ENUM(long, DPVisibility) { DPVisibilityHidden = 0 };
typedef NS_ENUM(long, DPWebContentsState) { DPWebContentsAlive = 0 };
typedef NS_OPTIONS(NSUInteger, DPKeepReason) { DPKeepPiP = 1 << 0, DPKeepSharing = 1 << 1 };

static NSMapTable<id, NSDate *> *DPHiddenSince;
static NSMapTable<id, id> *DPUIDelegates;
static NSMapTable<id, NSNumber *> *DPKeepReasons;

static long DPLongOf(id object, const char *selector) {
    return ((long (*)(id, SEL))objc_msgSend)(object, sel_registerName(selector));
}

static BOOL DPBoolOf(id object, const char *selector) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, sel_registerName(selector));
}

static id DPObjectOf(id object, const char *selector) {
    return ((id (*)(id, SEL))objc_msgSend)(object, sel_registerName(selector));
}

static void DPNoteVisibility(id contents, long visibility) {
    if (visibility != DPVisibilityHidden) {
        [DPHiddenSince setObject:NSDate.distantFuture forKey:contents];
        return;
    }
    NSDate *since = [DPHiddenSince objectForKey:contents];
    if (!since || [since isEqual:NSDate.distantFuture]) [DPHiddenSince setObject:NSDate.date forKey:contents];
}

static id DPWebContents_init(id self, SEL _cmd, void *native) {
    id contents = DPCallOriginal(DPWebContents_init, self, native);
    if (contents) [DPHiddenSince setObject:NSDate.date forKey:contents];
    DPScheduleTabRefresh();
    return contents;
}

static void DPWebContents_setVisibility(id self, SEL _cmd, long visibility) {
    DPCallOriginal(DPWebContents_setVisibility, self, visibility);
    DPNoteVisibility(self, visibility);
    DPScheduleTabRefresh();
}

static void DPWebContents_setUIDelegate(id self, SEL _cmd, id delegate) {
    DPCallOriginal(DPWebContents_setUIDelegate, self, delegate);
    if (delegate) [DPUIDelegates setObject:delegate forKey:self];
    else [DPUIDelegates removeObjectForKey:self];
}

static void DPWebContents_setState(id self, SEL _cmd, long state) {
    DPCallOriginal(DPWebContents_setState, self, state);
    DPScheduleTabRefresh();
}

static void DPSetKept(id contents, DPKeepReason reason, BOOL kept) {
    NSUInteger reasons = [DPKeepReasons objectForKey:contents].unsignedIntegerValue;
    [DPKeepReasons setObject:@(kept ? reasons | reason : reasons & ~reason) forKey:contents];
}

static void DPDelegate_pipCreated(id self, SEL _cmd, id contents, id controller) {
    DPCallOriginal(DPDelegate_pipCreated, self, contents, controller);
    DPSetKept(contents, DPKeepPiP, YES);
}

static void DPDelegate_pipDestroyed(id self, SEL _cmd, id contents) {
    DPCallOriginal(DPDelegate_pipDestroyed, self, contents);
    DPSetKept(contents, DPKeepPiP, NO);
}

static void DPDelegate_pipShown(id self, SEL _cmd, id contents) {
    DPCallOriginal(DPDelegate_pipShown, self, contents);
    DPSetKept(contents, DPKeepPiP, YES);
}

static void DPDelegate_pipHidden(id self, SEL _cmd, id contents) {
    DPCallOriginal(DPDelegate_pipHidden, self, contents);
    DPSetKept(contents, DPKeepPiP, NO);
}

static void DPDelegate_pipClosed(id self, SEL _cmd, id contents) {
    DPCallOriginal(DPDelegate_pipClosed, self, contents);
    DPSetKept(contents, DPKeepPiP, NO);
}

static void DPDelegate_shareChanged(id self, SEL _cmd, id contents, long state) {
    DPCallOriginal(DPDelegate_shareChanged, self, contents, state);
    DPSetKept(contents, DPKeepSharing, state != 0);
}

static BOOL DPIsInUse(id contents) {
    return DPBoolOf(contents, "audible") || [DPKeepReasons objectForKey:contents].unsignedIntegerValue;
}

static BOOL DPCanDiscard(id contents) {
    NSString *url = [DPObjectOf(contents, "url") description];
    return DPLongOf(contents, "state") == DPWebContentsAlive && DPLongOf(contents, "visibility") == DPVisibilityHidden
        && !DPBoolOf(contents, "hasFocus") && !DPBoolOf(contents, "isLoading") && !DPBoolOf(contents, "isFullscreen")
        && !DPBoolOf(contents, "hadFormOrUserEdits") && !DPBoolOf(contents, "hasDirtyTextField")
        && url.length && !DPIsKeptSite(url);
}

// Lowering the timeouts in WebContentLifecycleController's config instead changed no tab's state in about 9 minutes at a
// 1-minute limit (seen in a VM, on a small tab set), so what gates its optimizer is unknown and can't be relied on.
void DPDiscardIdleTabs(NSTimeInterval limit) {
    for (id contents in DPHiddenSince.keyEnumerator.allObjects) {
        NSDate *hidden = [DPHiddenSince objectForKey:contents];
        if (DPIsInUse(contents) && ![hidden isEqual:NSDate.distantFuture]) {
            [DPHiddenSince setObject:NSDate.date forKey:contents];
            continue;
        }
        if (-hidden.timeIntervalSinceNow < limit || !DPCanDiscard(contents)) continue;
        id delegate = [DPUIDelegates objectForKey:contents];
        if (delegate && DPDelegateShowsTabPage(delegate)) ((void (*)(id, SEL))objc_msgSend)(contents, sel_registerName("discard"));
    }
}

void DPInstallDiscarder(void) {
    DPHiddenSince = [NSMapTable weakToStrongObjectsMapTable];
    DPUIDelegates = [NSMapTable weakToWeakObjectsMapTable];
    DPKeepReasons = [NSMapTable weakToStrongObjectsMapTable];
    DPHook(DPDiaWebContents, sel_registerName("initWithWebContents:"), (IMP)DPWebContents_init);
    DPHook(DPDiaWebContents, sel_registerName("setVisibility:"), (IMP)DPWebContents_setVisibility);
    DPHook(DPDiaWebContents, sel_registerName("setState:"), (IMP)DPWebContents_setState);
    DPHook(DPDiaWebContents, sel_registerName("setUIDelegate:"), (IMP)DPWebContents_setUIDelegate);
    DPHook(DPDiaWebContentDelegate, sel_registerName("webContents:pipControllerCreated:"), (IMP)DPDelegate_pipCreated);
    DPHook(DPDiaWebContentDelegate, sel_registerName("webContentsPiPControllerDestroyed:"), (IMP)DPDelegate_pipDestroyed);
    DPHook(DPDiaWebContentDelegate, sel_registerName("webContentsShowPiP:"), (IMP)DPDelegate_pipShown);
    DPHook(DPDiaWebContentDelegate, sel_registerName("webContentsHidePiP:"), (IMP)DPDelegate_pipHidden);
    DPHook(DPDiaWebContentDelegate, sel_registerName("webContentsClosePiP:"), (IMP)DPDelegate_pipClosed);
    DPHook(DPDiaWebContentDelegate, sel_registerName("webContents:onShareThisTabStateChanged:"), (IMP)DPDelegate_shareChanged);
}
