#import "Patches/Peek/Peek.h"
#import <objc/message.h>

#define DPDiaWindowController "_TtC6Window24PlatformWindowController"

static NSArray<NSString *> *DPPeekZoomActions(void) {
    static NSArray<NSString *> *actions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ actions = @[ @"zoomIn:", @"zoomInAlternate:", @"zoomOut:", @"resetZoom:" ]; });
    return actions;
}

static BOOL DPPeekIsZoom(SEL action) { return action && [DPPeekZoomActions() containsObject:NSStringFromSelector(action)]; }

static BOOL DPPeekZoomFrom(id page, SEL action, float *now, float *next) {
    BOOL reset = action == @selector(resetZoom:);
    if (![page respondsToSelector:@selector(zoomFactor)] || ![page respondsToSelector:reset ? @selector(resetZoomAndScaleFactors) : @selector(setZoomFactor:)]) return NO;
    *now = ((float (*)(id, SEL))objc_msgSend)(page, @selector(zoomFactor));
    *next = reset ? 1 : DPZoomStep(*now, action == @selector(zoomOut:) ? -1 : 1);
    return YES;
}

static BOOL DPPeekZoom(DPPeekCard *peek, SEL action) {
    id page = peek.page;
    float now, next;
    if (!DPPeekZoomFrom(page, action, &now, &next)) return NO;
    if (action == @selector(resetZoom:)) ((void (*)(id, SEL))objc_msgSend)(page, @selector(resetZoomAndScaleFactors));
    else ((void (*)(id, SEL, float))objc_msgSend)(page, @selector(setZoomFactor:), next);
    return YES;
}

static SEL DPPeekZoomShortcutIn(NSMenu *menu, NSEvent *event) {
    for (NSMenuItem *item in menu.itemArray) {
        if (DPPeekIsZoom(item.action) && DPPeekIsShortcut(event, item)) return item.action;
        SEL action = DPPeekZoomShortcutIn(item.submenu, event);
        if (action) return action;
    }
    return NULL;
}

BOOL DPPeekZoomShortcut(DPPeekCard *peek, NSEvent *event) {
    SEL action = DPPeekZoomShortcutIn(NSApp.mainMenu, event);
    return action && DPPeekZoom(peek, action);
}

static void DPWindow_zoom(NSWindowController *self, SEL _cmd, id sender) {
    DPPeekCard *peek = DPPeekCardIn(self.window);
    if (!peek || !DPPeekZoom(peek, _cmd)) DPCallOriginal(DPWindow_zoom, self, sender);
}

static BOOL DPWindow_validate(NSWindowController *self, SEL _cmd, NSMenuItem *item) {
    DPPeekCard *peek = DPPeekIsZoom(item.action) ? DPPeekCardIn(self.window) : nil;
    float now, next;
    if (!peek || !DPPeekZoomFrom(peek.page, item.action, &now, &next)) return DPCallOriginal(DPWindow_validate, self, item);
    return fabsf(next - now) > 0.001;
}

void DPPeekInstallZoom(void) {
    for (NSString *action in DPPeekZoomActions()) DPHook(DPDiaWindowController, NSSelectorFromString(action), (IMP)DPWindow_zoom);
    DPHook(DPDiaWindowController, @selector(validateMenuItem:), (IMP)DPWindow_validate);
}

NSString *DPPeekZoomProblem(void) {
    Class controller = objc_getClass(DPDiaWindowController);
    for (NSString *action in DPPeekZoomActions())
        if (class_getMethodImplementation(controller, NSSelectorFromString(action)) != (IMP)DPWindow_zoom) return @"zoom doesn't reach Peek";
    return class_getMethodImplementation(controller, @selector(validateMenuItem:)) == (IMP)DPWindow_validate ? nil : @"zoom menu items don't reach Peek";
}
