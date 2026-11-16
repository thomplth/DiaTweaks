#import "Patches/Peek/Peek.h"
#import "Patches/HideToolbar/HideToolbar.h"

static const CGFloat DPPeekHotEdge = 8;
static const NSTimeInterval DPPeekHideDelay = 0.4, DPPeekSlide = 0.2;

@interface DPPeekBarZone : NSView
@property (nonatomic, weak) DPPeekCard *peek;
@property (nonatomic) CGFloat reveal;
@property (nonatomic) BOOL revealed, pinned, hovering;
@property (nonatomic, strong) NSTimer *ease, *hide, *watch;
@property (nonatomic, strong) id patches;
@end

static BOOL DPPeekBarPinned(DPPeekCard *peek) { return !DPHideToolbar.on || (peek.pane && DPKeptInPlace(peek.pane)); }
static BOOL DPPeekEditing(DPPeekBarZone *zone) { return DPPeekEditingAddress(DPPeekToolbarAddress(zone.peek.toolbar)); }
static BOOL DPPeekCanReveal(DPPeekBarZone *zone) { return DPHideToolbar.on && DPRevealToolbarOnHover.on && !zone.pinned; }

@implementation DPPeekBarZone
- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
}

- (void)slideTo:(CGFloat)target {
    [self.ease invalidate];
    CGFloat from = self.reveal;
    CFTimeInterval start = CACurrentMediaTime();
    __weak DPPeekBarZone *weak = self;
    self.ease = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *timer) {
        DPPeekBarZone *zone = weak;
        CGFloat t = MIN(1, (CACurrentMediaTime() - start) / DPPeekSlide);
        if (!zone || t == 1) [timer invalidate];
        zone.reveal = from + (target - from) * t * t * (3 - 2 * t);
        zone.peek.needsLayout = YES;
    }];
    [NSRunLoop.mainRunLoop addTimer:self.ease forMode:NSRunLoopCommonModes];
}

- (void)setRevealed:(BOOL)revealed {
    [self.hide invalidate];
    self.hide = nil;
    if (_revealed == revealed) return;
    _revealed = revealed;
    [self slideTo:revealed ? 1 : 0];
}

- (void)mouseEntered:(NSEvent *)event {
    self.hovering = YES;
    if (DPPeekCanReveal(self)) self.revealed = YES;
}

- (void)mouseExited:(NSEvent *)event {
    self.hovering = NO;
    if (!self.revealed || self.hide) return;
    __weak DPPeekBarZone *weak = self;
    self.hide = [NSTimer scheduledTimerWithTimeInterval:DPPeekHideDelay repeats:NO block:^(NSTimer *timer) {
        DPPeekBarZone *zone = weak;
        zone.hide = nil;
        if (!DPPeekEditing(zone)) zone.revealed = NO;
    }];
}

- (void)check {
    DPPeekCard *peek = self.peek;
    BOOL pinned = DPPeekBarPinned(peek);
    if (pinned != self.pinned) {
        self.pinned = pinned;
        peek.needsLayout = YES;
    }
    BOOL canReveal = DPPeekCanReveal(self);
    if (self.hidden != (!canReveal || peek.grown > 0)) peek.needsLayout = YES;
    BOOL editing = DPPeekEditing(self);
    if (editing && !pinned) self.revealed = YES;
    else if (self.revealed && !editing && (!canReveal || !self.hovering) && !self.hide) self.revealed = NO;
    NSObject *page = (NSObject *)peek.page;
    BOOL outOfSight = !pinned && self.reveal == 0 && DPHideToolbar.progress == 1;
    if (!DPShowLoadingProgress.on || !outOfSight || peek.closing || !page) DPRemoveProgressLine(peek.clip);
    else if ([[page valueForKey:@"isLoading"] boolValue]) DPShowProgressLine(peek.clip, MAX(0.1, [[page valueForKey:@"loadProgress"] doubleValue]));
    else DPFinishProgressLine(peek.clip);
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.watch invalidate];
    [self.ease invalidate];
    [self.hide invalidate];
    self.watch = self.ease = self.hide = nil;
    if (self.patches) [NSNotificationCenter.defaultCenter removeObserver:self.patches];
    self.patches = nil;
    if (!self.window) return;
    __weak DPPeekBarZone *weak = self;
    self.watch = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) { [weak check]; }];
    self.patches = [NSNotificationCenter.defaultCenter addObserverForName:DPPatchesDidChangeNotification object:nil
                                                                    queue:NSOperationQueue.mainQueue
                                                               usingBlock:^(NSNotification *note) { [weak check]; }];
}
@end

void DPPeekAddToolbar(DPPeekCard *peek) {
    peek.toolbar = DPPeekToolbarFor(peek.page);
    DPPeekBarZone *zone = [DPPeekBarZone new];
    zone.peek = peek;
    zone.pinned = DPPeekBarPinned(peek);
    peek.toolbarZone = zone;
    [peek.clip addSubview:peek.toolbar];
    [peek.clip addSubview:zone];
}

CGFloat DPPeekToolbarInset(DPPeekCard *peek) {
    DPPeekBarZone *zone = (DPPeekBarZone *)peek.toolbarZone;
    return peek.toolbar && zone.pinned ? round(DPPeekToolbarHeight * (1 - peek.grown)) : 0;
}

void DPPeekPlaceToolbar(DPPeekCard *peek) {
    DPPeekBarZone *zone = (DPPeekBarZone *)peek.toolbarZone;
    NSView *bar = peek.toolbar;
    if (!bar || !zone) return;
    NSRect clip = peek.clip.bounds;
    BOOL flipped = peek.clip.isFlipped;
    CGFloat full = round(DPPeekToolbarHeight * (1 - peek.grown)), shown = zone.pinned ? full : round(full * zone.reveal);
    CGFloat top = flipped ? 0 : NSHeight(clip), hot = zone.revealed ? full : DPPeekHotEdge;
    bar.frame = NSMakeRect(0, flipped ? shown - full : top - shown, NSWidth(clip), full);
    bar.hidden = shown < 1;
    zone.frame = NSMakeRect(0, flipped ? 0 : top - hot, NSWidth(clip), hot);
    zone.hidden = !DPPeekCanReveal(zone) || peek.grown > 0;
}

void DPPeekEditToolbarAddress(DPPeekCard *peek) {
    DPPeekBarZone *zone = (DPPeekBarZone *)peek.toolbarZone;
    if (!zone) return;
    if (!zone.pinned) zone.revealed = YES;
    DPPeekEditAddress(DPPeekToolbarAddress(peek.toolbar));
}
