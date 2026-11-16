#import "LittleDia.h"
#import <objc/message.h>

static char DPLittleKey, DPPageKey, DPChromeKey, DPSourceKey, DPPromotedKey;

static NSMutableArray<NSDictionary *> *DPExpected;
static NSMutableArray *DPPendingPages;
static NSPointerArray *DPWindowsAwaitingPage;

void DPExpectLittleDiaWindow(NSRect frame, NSDictionary *noted, void (^missed)(void), void (^claimed)(NSWindow *window)) {
    NSMutableDictionary *link = [@{@"frame" : [NSValue valueWithRect:frame], @"noted" : noted, @"missed" : [missed copy]} mutableCopy];
    if (claimed) link[@"claimed"] = [claimed copy];
    [DPExpected addObject:link];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, DPLittleDiaWait * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([DPExpected indexOfObjectIdenticalTo:link] == NSNotFound) return;
        [DPExpected removeObjectIdenticalTo:link];
        if (!DPExpected.count) [DPPendingPages removeAllObjects];
        ((void (^)(void))link[@"missed"])();
    });
}

BOOL DPIsLittleDiaWindow(NSWindow *window) { return window && [DPGet(window, &DPLittleKey) boolValue]; }

id DPLittleDiaPage(NSWindow *window) {
    id page = DPGet(window, &DPPageKey);
    BOOL usable = [page respondsToSelector:@selector(url)] && [page respondsToSelector:@selector(title)]
        && [page respondsToSelector:@selector(canGoBack)] && [page respondsToSelector:@selector(canGoForward)];
    return usable ? page : nil;
}

static void DPSetChrome(NSWindow *window, BOOL little) {
    NSView *titlebar = [window standardWindowButton:NSWindowCloseButton].superview.superview;
    NSDictionary *saved = DPGet(window, &DPChromeKey);
    if (little == (saved != nil)) return;
    if (little) {
        DPSet(window, &DPChromeKey, @{@"mask" : @(window.styleMask), @"movable" : @(window.movableByWindowBackground)});
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    } else {
        DPSet(window, &DPChromeKey, nil);
        window.styleMask = [saved[@"mask"] unsignedIntegerValue];
        window.movableByWindowBackground = [saved[@"movable"] boolValue];
    }
    window.titlebarAppearsTransparent = little;
    window.titleVisibility = little ? NSWindowTitleHidden : NSWindowTitleVisible;
    if (little) window.movableByWindowBackground = YES;
    for (NSWindowButton kind = NSWindowCloseButton; kind <= NSWindowZoomButton; kind++) [window standardWindowButton:kind].hidden = little;
    titlebar.hidden = little;
}

static void DPClaim(NSWindow *window) {
    if (!window || !DPIsKind(window, DPDiaPopupWindow) || DPGet(window, &DPLittleKey) || !DPExpected.count) return;
    NSDictionary *link = DPExpected.firstObject, *noted = link[@"noted"];
    [DPExpected removeObjectAtIndex:0];
    DPSet(window, &DPLittleKey, @YES);
    if ([noted[@"source"] intValue]) DPSet(window, &DPSourceKey, noted[@"source"]);
    if (DPPendingPages.count) {
        DPSet(window, &DPPageKey, DPPendingPages.firstObject);
        [DPPendingPages removeObjectAtIndex:0];
    } else [DPWindowsAwaitingPage addPointer:(__bridge void *)window];
    // With no link left a waiting page is some other popup's; kept, later windows would each take the wrong page.
    if (!DPExpected.count) [DPPendingPages removeAllObjects];
    // Chromium adds its title bar to the size it's given, and the title bar is gone here.
    NSRect frame = [link[@"frame"] rectValue];
    [window setFrame:frame display:YES];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    DPRestoreStack(window, noted);
    // Chromium sizes and focuses the new window again a moment later, which can bring Dia's windows forward again.
    __weak NSWindow *weakWindow = window;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [weakWindow setFrame:frame display:YES];
        DPRestoreStack(weakWindow, noted);
    });
    DPRefreshLittleDiaWindows();
    if (link[@"claimed"]) ((void (^)(NSWindow *))link[@"claimed"])(window);
}

static void DPBrowser_didCreate(id self, SEL _cmd, id browser, id page, BOOL active) {
    DPCallOriginal(DPBrowser_didCreate, self, browser, page, active);
    long (*type)(id, SEL) = (void *)objc_msgSend;
    if (!page || ![browser respondsToSelector:@selector(type)] || type(browser, @selector(type)) != 2) return;  // 2: a popup
    [DPWindowsAwaitingPage compact];
    if (DPWindowsAwaitingPage.count) {
        NSWindow *window = (__bridge NSWindow *)[DPWindowsAwaitingPage pointerAtIndex:0];
        [DPWindowsAwaitingPage removePointerAtIndex:0];
        DPSet(window, &DPPageKey, page);
        DPRefreshLittleDiaWindows();
    } else if (DPExpected.count) [DPPendingPages addObject:page];
}

static void DPPopupBar_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPopupBar_viewDidMoveToWindow, self);
    DPClaim(self.window);
}

// Only plain new-tab links stay: sized popups keep their opener, which sign-in windows talk back to.
enum { DPCurrentTab = 1, DPForegroundTab = 2 };

static BOOL DPStaysInLittleDia(id page, NSInteger disposition) {
    if (disposition != DPForegroundTab || (NSEvent.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift))) return NO;
    for (NSWindow *window in NSApp.windows)
        if (DPIsLittleDiaWindow(window) && DPLittleDiaPage(window) == page) return YES;
    return NO;
}

@interface DPStayingLink : NSProxy
@property (nonatomic, strong) id action;
@end

@implementation DPStayingLink
- (NSInteger)navigationDisposition { return DPCurrentTab; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [self.action methodSignatureForSelector:selector]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.action]; }
@end

static NSInteger DPPage_decidePolicy(id self, SEL _cmd, id page, id action) {
    if (!DPStaysInLittleDia(page, [[action valueForKey:@"navigationDisposition"] integerValue]))
        return DPCallOriginal(DPPage_decidePolicy, self, page, action);
    DPStayingLink *staying = [DPStayingLink alloc];
    staying.action = action;
    return DPCallOriginal(DPPage_decidePolicy, self, page, staying);
}

void DPPromoteLittleDiaWindow(NSWindow *window) { DPSet(window, &DPPromotedKey, @YES); }

static void DPShowMainWindow(void) {
    for (NSWindow *window in NSApp.orderedWindows)
        if (DPIsKind(window, DPDiaWindow) && window.visible) {
            [NSApp activateIgnoringOtherApps:YES];
            [window makeKeyAndOrderFront:nil];
            return;
        }
}

void DPRefreshLittleDiaWindows(void) {
    for (NSWindow *window in NSApp.windows)
        if (DPIsLittleDiaWindow(window)) DPSetChrome(window, DPLittleDia.on);
    DPRelayoutLittleDiaBars();
}

static void DPWindowWillClose(NSWindow *window) {
    if (!DPLittleDia.on || !DPIsLittleDiaWindow(window)) return;
    pid_t source = [DPGet(window, &DPSourceKey) intValue];
    BOOL key = window.isKeyWindow, promoted = [DPGet(window, &DPPromotedKey) boolValue];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (promoted) {
            DPBringBackPutAway(nil);
            DPShowMainWindow();
        } else if (!DPHideAgain() && key && source) DPReturnToSource(source);
    });
}

void DPInstallLittleDiaWindows(void) {
    DPExpected = [NSMutableArray array];
    DPPendingPages = [NSMutableArray array];
    DPWindowsAwaitingPage = [NSPointerArray weakObjectsPointerArray];
    DPHookClass(objc_getClass(DPDiaPopupBar), @selector(viewDidMoveToWindow), (IMP)DPPopupBar_viewDidMoveToWindow);
    DPHook(DPDiaBrowserDelegate, @selector(browser:didCreateNewWebContents:isActive:), (IMP)DPBrowser_didCreate);
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:decidePolicyForNavigationAction:), (IMP)DPPage_decidePolicy);
    });
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:^(NSNotification *note) { DPClaim(note.object); }];
    [center addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *note) { DPWindowWillClose(note.object); }];
    DPInstallLittleDiaBar();
    DPInstallLittleDiaStack();
}
