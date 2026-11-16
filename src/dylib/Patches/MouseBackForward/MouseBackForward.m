#import "StdPatch/StdPatch.h"
#import <objc/message.h>

extern DPPatch DPMouseBackForward;

static const NSInteger DPWebContentsHidden = 0;
static NSHashTable *DPPages;

static void DPPage_setVisibility(id self, SEL _cmd, NSInteger visibility) {
    [DPPages addObject:self];
    DPCallOriginal(DPPage_setVisibility, self, visibility);
}

static NSInteger DPOffset(NSEvent *event) {
    if (event.type == NSEventTypeSwipe)
        return event.phase == NSEventPhaseNone && fabs(event.deltaX) > fabs(event.deltaY) ? (event.deltaX > 0 ? -1 : 1) : 0;
    return event.buttonNumber == 3 ? -1 : event.buttonNumber == 4 ? 1 : 0;
}

static BOOL DPPageBool(id page, SEL sel) { return ((BOOL (*)(id, SEL))objc_msgSend)(page, sel); }

static id DPPageAt(NSEvent *event) {
    NSWindow *window = event.window;
    NSPoint point = event.locationInWindow;
    if (!window && event.type == NSEventTypeSwipe) {
        NSPoint screen = NSEvent.mouseLocation;
        window = [NSApp windowWithWindowNumber:[NSWindow windowNumberAtPoint:screen belowWindowWithWindowNumber:0]];
        point = [window convertPointFromScreen:screen];
    }
    if (!window) return nil;
    NSView *hit = [window.contentView.superview hitTest:point];
    id focused = nil, only = nil;
    NSUInteger count = 0;
    for (id page in DPPages.allObjects) {
        NSView *view = [page performSelector:@selector(nativeView)];
        if (view.window != window || ((NSInteger (*)(id, SEL))objc_msgSend)(page, @selector(visibility)) == DPWebContentsHidden) continue;
        if ([hit isDescendantOf:view]) return page;
        if (DPPageBool(page, @selector(hasFocus))) focused = page;
        only = page;
        count++;
    }
    return focused ?: (count == 1 ? only : nil);
}

static void DPGo(id page, NSInteger offset) {
    if (!DPPageBool(page, offset < 0 ? @selector(canGoBack) : @selector(canGoForward))) return;
    id controller = [page performSelector:@selector(navigationController)];
    if (offset < 0) [controller performSelector:@selector(goBack)];
    else [controller performSelector:@selector(goForward)];
}

static void DPInstallMouseBackForward(void) {
    DPPages = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaWebContents, @selector(setVisibility:), (IMP)DPPage_setVisibility);
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskOtherMouseDown | NSEventMaskOtherMouseUp | NSEventMaskSwipe handler:^NSEvent *(NSEvent *event) {
        NSInteger offset = DPOffset(event);
        id page = DPMouseBackForward.on && offset ? DPPageAt(event) : nil;
        if (!page) return event;
        if (event.type != NSEventTypeOtherMouseDown) DPGo(page, offset);
        return nil;
    }];
}

static NSString *DPVerifyMouseBackForward(DPPatch *patch) {
    Class page = objc_getClass(DPDiaWebContents), controller = objc_getClass(DPDiaNavigationController);
    SEL needs[] = {@selector(setVisibility:), @selector(nativeView), @selector(visibility), @selector(hasFocus), @selector(canGoBack), @selector(canGoForward), @selector(navigationController)};
    for (size_t i = 0; i < sizeof(needs) / sizeof(*needs); i++)
        if (![page instancesRespondToSelector:needs[i]]) return [NSString stringWithFormat:@"Dia's pages have no %@", NSStringFromSelector(needs[i])];
    if (![controller instancesRespondToSelector:@selector(goBack)] || ![controller instancesRespondToSelector:@selector(goForward)])
        return @"Dia's pages can't go back or forward";
    return nil;
}

DP_PATCH(DPMouseBackForward) {
    .key = @"mouseBackForward",
    .order = 86,
    .title = @"Mouse Back and Forward Buttons",
    .detail = @"Use your mouse’s side buttons to go back and forward, even on sites that block them. In split tabs, navigate the page under the pointer.",
    .symbol = @"computermouse.fill",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaWebContents, DPDiaNavigationController),
    .install = DPInstallMouseBackForward,
    .verify = DPVerifyMouseBackForward,
};
