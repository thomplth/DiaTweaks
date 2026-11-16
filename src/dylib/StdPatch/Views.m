#import "StdPatch/StdPatch.h"
#import <os/log.h>

NSView *DPFindView(NSView *root, BOOL (^match)(NSView *)) {
    if (!root || match(root)) return root;
    for (NSView *sub in root.subviews) {
        NSView *found = DPFindView(sub, match);
        if (found) return found;
    }
    return nil;
}

static void DPCollectViews(NSView *view, Class cls, NSMutableArray<NSView *> *views) {
    if ([view isKindOfClass:cls]) [views addObject:view];
    for (NSView *sub in view.subviews) DPCollectViews(sub, cls, views);
}

NSArray<NSView *> *DPFindViews(const char *className) {
    Class cls = objc_getClass(className);
    NSMutableArray<NSView *> *views = [NSMutableArray new];
    for (NSWindow *window in NSApp.windows)
        if (cls && window.isVisible) DPCollectViews(window.contentView, cls, views);
    return views;
}

NSString *DPTabLayout(void) { return DPFindViews(DPDiaSidebarFooter).count ? @"vertical" : @"horizontal"; }

NSView *DPSubview(NSView *parent, const char *className) {
    for (NSView *sub in parent.subviews) if (DPIsKind(sub, className)) return sub;
    return nil;
}

BOOL DPIsKind(id object, const char *className) {
    Class cls = objc_getClass(className);
    return cls && [object isKindOfClass:cls];
}

BOOL DPIsFloatingChat(NSView *popover) {
    return DPFindView(popover, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaChatHeader); }) != nil;
}

BOOL DPHasLabel(NSView *view, NSString *accessibilityLabel) {
    return [view.accessibilityLabel isEqualToString:accessibilityLabel];
}

void DPRelayoutViews(NSHashTable<NSView *> *views) {
    for (NSView *view in views.allObjects) {
        view.needsLayout = YES;
        [view layoutSubtreeIfNeeded];
    }
}

static const NSUInteger DPAdjustLimit = 8;

BOOL DPMayAdjust(NSView *view) {
    static NSMapTable<NSView *, NSNumber *> *counts;
    if (!counts) {
        counts = [NSMapTable weakToStrongObjectsMapTable];
        CFRunLoopObserverRef reset = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, true, 0, ^(CFRunLoopObserverRef o, CFRunLoopActivity a) {
            [counts removeAllObjects];
        });
        CFRunLoopAddObserver(CFRunLoopGetMain(), reset, kCFRunLoopCommonModes);
    }
    NSUInteger n = [[counts objectForKey:view] unsignedIntegerValue] + 1;
    [counts setObject:@(n) forKey:view];
    if (n == DPAdjustLimit + 1) {
        os_log(OS_LOG_DEFAULT, "DiaPatches: letting Dia lay out %{public}s for the rest of this turn, which kept undoing a patch", object_getClassName(view));
        // A busy run loop never waits to reset the counts, so retry soon.
        __weak NSView *weak = view;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weak) [counts removeObjectForKey:weak];
            for (NSView *up = weak; up; up = up.superview) up.needsLayout = YES;
        });
    }
    return n <= DPAdjustLimit;
}

void *DPIvar(id object, const char *name) {
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    return ivar ? (uint8_t *)(__bridge void *)object + ivar_getOffset(ivar) : NULL;
}

@interface NSObject (DPSwiftValue)
- (id)safeSwiftValueForKey:(NSString *)key;
@end

id DPSwiftValue(id object, NSString *key) {
    return [object respondsToSelector:@selector(safeSwiftValueForKey:)] ? [object safeSwiftValueForKey:key] : nil;
}

NSArray<NSString *> *DPUUIDsIn(NSString *text) {
    static NSRegularExpression *uuid;
    if (!uuid) uuid = [NSRegularExpression regularExpressionWithPattern:@"[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}" options:0 error:nil];
    NSMutableArray *found = [NSMutableArray new];
    for (NSTextCheckingResult *match in [uuid matchesInString:text ?: @"" options:0 range:NSMakeRange(0, text.length)])
        [found addObject:[text substringWithRange:match.range]];
    return found;
}

NSWindowController *DPOpenTabSwitcher(void) {
    for (NSWindow *window in NSApp.windows)
        if (window.visible && DPIsKind(window.windowController, DPDiaTabSwitcher)) return window.windowController;
    return nil;
}

id DPGet(id object, const void *key) {
    return objc_getAssociatedObject(object, key);
}

void DPSet(id object, const void *key, id value) {
    objc_setAssociatedObject(object, key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DPOverride(id object, const void *key, id dia, id ours) {
    DPSet(object, key, @[dia, ours]);
}

id DPDiaValue(id object, const void *key, id current) {
    NSArray *values = DPGet(object, key);
    return values && [values[1] isEqual:current] ? values[0] : current;
}
