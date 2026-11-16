#import "StdPatch/StdPatch.h"

// Capture the installed AppKit monitor; send it events without posting input to the user's desktop.
static NSEvent *(^monitor)(NSEvent *);
static NSPoint pointer;
static NSInteger windowAtPointer;
static NSPoint mouseLocation(id self, SEL cmd) { return pointer; }
static NSInteger windowNumberAtPoint(id self, SEL cmd, NSPoint point, NSInteger below) { return windowAtPointer; }
static id capture(id self, SEL cmd, NSEventMask mask, NSEvent *(^handler)(NSEvent *)) {
    NSCAssert(mask == (NSEventMaskOtherMouseDown | NSEventMaskOtherMouseUp | NSEventMaskSwipe), @"side buttons and driver swipes");
    return monitor = [handler copy];
}

@interface ArcWebContentsNavigationController : NSObject
@property NSInteger index;
@end
@implementation ArcWebContentsNavigationController
- (void)goBack { self.index--; }
- (void)goForward { self.index++; }
@end

@interface ArcWebContents : NSObject
@property NSView *nativeView;
@property NSInteger visibility;
@property BOOL hasFocus, canGoBack, canGoForward;
@property ArcWebContentsNavigationController *navigationController;
@end
@implementation ArcWebContents
@end

@interface MouseEvent : NSEvent
@property NSWindow *window;
@property NSEventType type;
@property NSInteger buttonNumber;
@property NSPoint locationInWindow;
@property CGFloat deltaX, deltaY;
@property NSEventPhase phase;
@end
@implementation MouseEvent
@synthesize window = _window, type = _type, buttonNumber = _buttonNumber, locationInWindow = _locationInWindow;
@synthesize deltaX = _deltaX, deltaY = _deltaY, phase = _phase;
@end

#import "Patches/MouseBackForward/MouseBackForward.m"

static ArcWebContents *page(NSWindow *window, NSRect frame) {
    ArcWebContents *page = [ArcWebContents new];
    page.nativeView = [[NSView alloc] initWithFrame:frame];
    [window.contentView addSubview:page.nativeView];
    page.navigationController = [ArcWebContentsNavigationController new];
    page.canGoBack = page.canGoForward = YES;
    page.visibility = 2;  // Calls the real registration hook.
    return page;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPHookClass(object_getClass(NSEvent.class), @selector(addLocalMonitorForEventsMatchingMask:handler:), (IMP)capture);
        DPHookClass(object_getClass(NSEvent.class), @selector(mouseLocation), (IMP)mouseLocation);
        DPHookClass(object_getClass(NSWindow.class), @selector(windowNumberAtPoint:belowWindowWithWindowNumber:), (IMP)windowNumberAtPoint);
        DPInstallMouseBackForward();
        NSCAssert(!DPVerifyMouseBackForward(&DPMouseBackForward), @"required Dia methods exist");
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        ArcWebContents *left = page(window, NSMakeRect(100, 0, 350, 550));
        ArcWebContents *right = page(window, NSMakeRect(450, 0, 350, 550));
        left.hasFocus = YES;
        MouseEvent *event = [MouseEvent new];
        event.window = window; event.locationInWindow = NSMakePoint(600, 300);
        event.buttonNumber = 3; event.type = NSEventTypeOtherMouseUp;
        NSCAssert(monitor(event) == event, @"disabled patch preserves input");
        DPMouseBackForward.on = YES;
        for (NSInteger button = 0; button <= 5; button++) {
            NSInteger before = right.navigationController.index;
            event.buttonNumber = button;
            event.type = NSEventTypeOtherMouseDown;
            BOOL side = button == 3 || button == 4;
            NSCAssert((monitor(event) == nil) == side, @"consume only Back and Forward");
            NSCAssert(right.navigationController.index == before, @"no navigation on press");
            event.type = NSEventTypeOtherMouseUp;
            NSCAssert((monitor(event) == nil) == side, @"consume releases too, avoiding native double navigation");
            NSCAssert(right.navigationController.index == (button == 3 ? -1 : 0), @"one step per release");
            NSCAssert(left.navigationController.index == 0, @"hovered split page wins over focused page");
        }
        event.buttonNumber = 3; right.canGoBack = NO;
        NSCAssert(!monitor(event) && right.navigationController.index == 0, @"no back history: consume without navigating");
        event.buttonNumber = 4; right.canGoForward = NO;
        NSCAssert(!monitor(event) && right.navigationController.index == 0, @"no forward history: consume without navigating");
        event.buttonNumber = 3; event.locationInWindow = NSMakePoint(50, 300);
        NSCAssert(!monitor(event) && left.navigationController.index == -1, @"sidebar uses focused page");
        left.hasFocus = NO;
        NSCAssert(monitor(event) == event, @"ambiguous split without focus preserves input");
        right.visibility = 0;
        NSCAssert(!monitor(event) && left.navigationController.index == -2, @"ignore hidden tabs, fall back to sole page");
        left.visibility = 1;
        NSCAssert(!monitor(event) && left.navigationController.index == -3, @"occluded window can navigate without activation");
        NSView *rightView = right.nativeView;
        right.nativeView = nil; event.window = nil;
        NSCAssert(monitor(event) == event, @"windowless events cannot select detached pages");
        event.window = window; left.visibility = 0;
        NSCAssert(monitor(event) == event, @"windows without a visible page preserve input");
        __weak id closed;
        @autoreleasepool { closed = page(window, NSZeroRect); }
        NSCAssert(!closed, @"tracking does not retain closed pages");
        left.visibility = 2; DPMouseBackForward.on = NO;
        NSCAssert(monitor(event) == event && left.navigationController.index == -3, @"turning off restores input immediately");
        DPMouseBackForward.on = YES; right.nativeView = rightView; right.visibility = 2; right.canGoBack = right.canGoForward = YES;
        event.type = NSEventTypeSwipe; event.window = nil; event.deltaX = 1;
        windowAtPointer = window.windowNumber;
        pointer = [window convertPointToScreen:NSMakePoint(600, 300)];
        NSCAssert(!monitor(event) && right.navigationController.index == -1, @"real driver Back: windowless swipe targets hovered split");
        event.deltaX = -1;
        NSCAssert(!monitor(event) && right.navigationController.index == 0, @"driver Forward moves once");
        event.deltaY = 2;
        NSCAssert(monitor(event) == event, @"vertical swipes pass through");
        event.deltaY = 0; event.phase = NSEventPhaseBegan;
        NSCAssert(monitor(event) == event, @"leave phased gestures to Dia");
        event.phase = NSEventPhaseNone; windowAtPointer = 0;
        NSCAssert(monitor(event) == event, @"swipe over another app must not navigate Dia");
        windowAtPointer = window.windowNumber; DPMouseBackForward.on = NO;
        NSCAssert(monitor(event) == event && right.navigationController.index == 0, @"disabled patch preserves driver swipes");
        puts("all Mouse Back and Forward checks passed");
    }
}
