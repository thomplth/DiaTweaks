#import "Patches/UnloadTab/Recent.h"

static NSMapTable<NSWindow *, NSMutableArray<NSString *> *> *DPRecent;

static void DPNoteFront(NSWindow *window) {
    NSString *active = window && DPUnloadTab.on ? DPActiveTabID(window) : nil;
    if (!active) return;
    NSMutableArray *recent = [DPRecent objectForKey:window];
    if (!recent) [DPRecent setObject:(recent = [NSMutableArray array]) forKey:window];
    [recent removeObject:active];
    [recent addObject:active];
    if (recent.count > 20) [recent removeObjectAtIndex:0];
}

id DPTabBefore(NSWindow *window) {
    NSString *active = DPActiveTabID(window);
    NSArray *tabs = [DPScriptWindow(window) valueForKey:@"appleScriptTabs"];
    NSArray<NSString *> *ids = [tabs valueForKey:@"tabId"];
    for (NSString *tabID in [DPRecent objectForKey:window].reverseObjectEnumerator) {
        NSUInteger i = [tabID isEqual:active] ? NSNotFound : [ids indexOfObject:tabID];
        if (i != NSNotFound) return tabs[i];
    }
    NSUInteger i = active ? [ids indexOfObject:active] : NSNotFound;
    if (i == NSNotFound) return nil;
    return i + 1 < tabs.count ? tabs[i + 1] : i > 0 ? tabs[i - 1] : nil;
}

void DPForgetFrontTab(NSWindow *window) {
    NSString *active = DPActiveTabID(window);
    if (active) [[DPRecent objectForKey:window] removeObject:active];
}

static void DPContentPane_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContentPane_viewDidMoveToWindow, self);
    DPNoteFront(self.window);
}

void DPWatchFrontTabs(void) {
    DPRecent = [NSMapTable weakToStrongObjectsMapTable];
    DPHook(DPDiaContentPane, @selector(viewDidMoveToWindow), (IMP)DPContentPane_viewDidMoveToWindow);
}
