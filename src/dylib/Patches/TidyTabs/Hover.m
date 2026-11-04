#import "TidyTabs.h"

static char DPHoverKey;

static NSTimer *DPTidyEase(CGFloat from, CGFloat to, void (^step)(CGFloat value, BOOL done)) {
    CFTimeInterval start = CACurrentMediaTime();
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *timer) {
        CGFloat t = MIN(1, (CACurrentMediaTime() - start) / 0.2);
        if (t == 1) [timer invalidate];
        step(from + (to - from) * t * t * (3 - 2 * t), t == 1);
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    return timer;
}

// The view holding the sidebar's header, tab list and footer. It tracks the pointer; the divider decides.
static NSView *DPSidebarOf(NSView *list) {
    for (NSView *view = list.superview; view; view = view.superview)
        if (DPSubview(view, DPDiaSidebarHeader) || DPSubview(view, DPDiaSidebarFooter)) return view;
    return list;
}

@implementation DPTidyHover

+ (DPTidyHover *)forList:(NSView *)list { return DPGet(list, &DPHoverKey); }

+ (DPTidyHover *)attachToList:(NSView *)list {
    DPTidyHover *hover = [self forList:list] ?: [DPTidyHover new];
    hover.list = list;
    DPSet(list, &DPHoverKey, hover);
    NSView *sidebar = DPSidebarOf(list);
    // The sidebar's visibleRect spans the whole window, so the area follows its bounds instead.
    if (hover.tracking && hover.sidebar == sidebar && NSEqualRects(hover.tracking.rect, sidebar.bounds)) return hover;
    BOOL first = !hover.tracking;
    if (hover.tracking) [hover.sidebar removeTrackingArea:hover.tracking];
    hover.sidebar = sidebar;
    hover.tracking = [[NSTrackingArea alloc] initWithRect:sidebar.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow owner:hover userInfo:nil];
    [sidebar addTrackingArea:hover.tracking];
    // No enter event comes for a pointer that's already inside.
    if (first) dispatch_async(dispatch_get_main_queue(), ^{ if ([hover containsPointer]) hover.revealed = YES; });
    return hover;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(windowResignedKey:) name:NSWindowDidResignKeyNotification object:nil];
    [center addObserver:self selector:@selector(hide) name:NSApplicationDidResignActiveNotification object:nil];
    return self;
}

- (void)dealloc {
    [_animation invalidate];
    [_hideTimer invalidate];
    if (_tracking) [_sidebar removeTrackingArea:_tracking];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)detach {
    [self.animation invalidate];
    [self.hideTimer invalidate];
    self.animation = self.hideTimer = nil;
    if (self.tracking) [self.sidebar removeTrackingArea:self.tracking];
    self.tracking = nil;
    _revealed = NO;
    self.progress = 0;
}

// The pointer is on the gap under the favorites, or on the row. Dia's own divider needs no tracking: see Separator.m.
- (BOOL)containsPointer {
    NSView *list = self.list;
    NSWindow *window = list.window;
    if (!window.isKeyWindow || !NSApp.isActive || list.hiddenOrHasHiddenAncestor) return NO;
    NSPoint point = [window convertPointFromScreen:NSEvent.mouseLocation];
    return NSPointInRect(point, DPTidyHoverZone(list)) && DPTidyTabsBelowLine(list) >= DPTidyMinimumTabs;
}

- (void)setRevealed:(BOOL)revealed {
    if (_revealed == revealed || (revealed && !DPTidyTabs.on)) return;
    _revealed = revealed;
    [self.animation invalidate];
    self.animation = nil;
    __weak DPTidyHover *weakSelf = self;
    self.animation = DPTidyEase(self.progress, revealed, ^(CGFloat value, BOOL done) {
        DPTidyHover *me = weakSelf;
        NSView *list = me.list;
        if (!list) return;
        me.progress = value;
        if (done) me.animation = nil;
        list.needsLayout = YES;
        [list layoutSubtreeIfNeeded];
    });
}

- (void)hide { if (!DPTidyIsBusy()) self.revealed = NO; }

- (void)windowResignedKey:(NSNotification *)notification {
    if (notification.object == self.sidebar.window) [self hide];
}

- (void)mouseEntered:(NSEvent *)event { [self track]; }
- (void)mouseMoved:(NSEvent *)event { [self track]; }
- (void)mouseExited:(NSEvent *)event { [self track]; }

// A short wait keeps the broom from flickering as the pointer crosses the divider's edge, and while a tab is dragged.
- (void)track {
    if ([self containsPointer]) {
        [self.hideTimer invalidate];
        self.hideTimer = nil;
        self.revealed = YES;
        return;
    }
    if (!self.revealed || self.hideTimer) return;
    __weak DPTidyHover *weakSelf = self;
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *timer) {
        DPTidyHover *me = weakSelf;
        if (!me) return [timer invalidate];
        if (NSEvent.pressedMouseButtons && [me containsPointer]) return;
        [timer invalidate];
        me.hideTimer = nil;
        if (![me containsPointer]) [me hide];
    }];
}
@end
