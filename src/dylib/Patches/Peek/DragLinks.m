#import "Patches/Peek/Peek.h"

extern DPPatch DPPeekDragLinks;

static const CGSize DPZoneCard = {120, 84};
static const CGFloat DPZoneGap = 24, DPZoneReach = 20, DPZoneRoom = 90;

@interface DPPeekZone : NSView <NSDraggingDestination>
@property (nonatomic, strong) CALayer *card, *tint, *icon;
@property (nonatomic, strong) CAShapeLayer *dash;
@property (nonatomic, strong) CATextLayer *label;
@property (nonatomic, strong) NSImage *idleIcon, *hoverIcon;
@property (nonatomic, strong) NSColor *idle, *accent, *line;
@property (nonatomic) NSPoint link;
@property (nonatomic) BOOL hovered;
@end

static NSPanel *DPZonePanel;
static NSTimer *DPZoneRelease;

static NSImage *DPZoneIcon(NSColor *color) {
    NSImageSymbolConfiguration *config = [[NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightSemibold]
        configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[ color ]]];
    return [[NSImage imageWithSystemSymbolName:@"eye.fill" accessibilityDescription:nil] imageWithSymbolConfiguration:config];
}

static void DPZoneSpring(CALayer *layer, NSString *keyPath, id to, CFTimeInterval response, CGFloat damping) {
    CASpringAnimation *spring = DPPeekSpring(keyPath, response, damping);
    spring.fromValue = [(layer.presentationLayer ?: layer) valueForKeyPath:keyPath];
    spring.toValue = to;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer setValue:to forKeyPath:keyPath];
    [layer addAnimation:spring forKey:keyPath];
    [CATransaction commit];
}

@implementation DPPeekZone

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    self.layer = [CALayer layer];
    self.wantsLayer = YES;
    [self registerForDraggedTypes:@[ NSPasteboardTypeURL ]];
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.idle = NSColor.secondaryLabelColor;
        self.line = NSColor.separatorColor;
        self.accent = [NSColor colorWithSRGBRed:0 green:0.542 blue:0.789 alpha:1];
        CGRect bounds = {CGPointZero, DPZoneCard};
        self.card = [CALayer layer];
        self.card.bounds = bounds;
        self.card.position = CGPointMake(NSMidX(self.bounds), NSMidY(self.bounds));
        self.card.cornerRadius = 20;
        self.card.cornerCurve = kCACornerCurveContinuous;
        self.card.backgroundColor = NSColor.controlBackgroundColor.CGColor;
        self.card.borderWidth = 0.5;
        self.card.borderColor = self.line.CGColor;
        self.card.shadowOpacity = 0.3;
        self.card.shadowRadius = 16;
        self.card.shadowOffset = CGSizeMake(0, -2);
        self.tint = [CALayer layer];
        self.tint.frame = bounds;
        self.tint.cornerRadius = 20;
        self.tint.cornerCurve = kCACornerCurveContinuous;
        self.tint.backgroundColor = self.accent.CGColor;
        self.tint.opacity = 0;
        self.dash = [CAShapeLayer layer];
        self.dash.frame = bounds;
        self.dash.path = CFAutorelease(CGPathCreateWithRoundedRect(CGRectInset(bounds, 10, 10), 10, 10, NULL));
        self.dash.fillColor = nil;
        self.dash.strokeColor = self.line.CGColor;
        self.dash.lineWidth = 2;
        self.dash.lineDashPattern = @[ @6, @6 ];
        self.idleIcon = DPZoneIcon(self.idle);
        self.hoverIcon = DPZoneIcon(self.accent);
        self.icon = [CALayer layer];
        self.icon.frame = CGRectMake((DPZoneCard.width - 24) / 2, 42, 24, 18);
        self.icon.contentsGravity = kCAGravityResizeAspect;
        self.icon.contents = self.idleIcon;
        self.label = [CATextLayer layer];
        self.label.frame = CGRectMake(0, 21, DPZoneCard.width, 17);
        self.label.string = @"Peek";
        self.label.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        self.label.fontSize = 14;
        self.label.alignmentMode = kCAAlignmentCenter;
        self.label.foregroundColor = self.idle.CGColor;
        self.label.contentsScale = self.icon.contentsScale = 2;
    }];
    for (CALayer *layer in @[ self.tint, self.dash, self.icon, self.label ]) [self.card addSublayer:layer];
    [self.layer addSublayer:self.card];
    return self;
}

- (CGPoint)rest { return CGPointMake(NSMidX(self.bounds), NSMidY(self.bounds)); }

- (void)appear:(BOOL)shown {
    if (shown) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.card.opacity = 0;
        [self.card setValue:@0.65 forKeyPath:@"transform.scale"];
        [CATransaction commit];
    }
    DPZoneSpring(self.card, @"transform.scale", shown ? @1 : @0.65, 0.21, 0.66);
    DPZoneSpring(self.card, @"opacity", shown ? @1 : @0, shown ? 0.21 : 0.15, shown ? 0.66 : 1);
}

- (void)pull:(CGPoint)offset {
    CGPoint from = self.card.position, to = CGPointMake(self.rest.x + offset.x, self.rest.y + offset.y);
    if (hypot(to.x - from.x, to.y - from.y) < 0.25) return;
    CASpringAnimation *spring = DPPeekSpring(@"position", 0.21, 0.66);
    spring.additive = YES;
    spring.fromValue = [NSValue valueWithPoint:NSMakePoint(from.x - to.x, from.y - to.y)];
    spring.toValue = [NSValue valueWithPoint:NSZeroPoint];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.card.position = to;
    [self.card addAnimation:spring forKey:nil];
    [CATransaction commit];
}

- (void)setHovered:(BOOL)hovered {
    if (hovered == _hovered) return;
    _hovered = hovered;
    DPZoneSpring(self.card, @"transform.scale", hovered ? @1.15 : @1, 0.2, 0.9);
    DPZoneSpring(self.tint, @"opacity", hovered ? @0.12 : @0, 0.2, 0.9);
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.15];
    self.dash.strokeColor = (hovered ? self.accent : self.line).CGColor;
    self.label.foregroundColor = (hovered ? self.accent : self.idle).CGColor;
    self.icon.contents = hovered ? self.hoverIcon : self.idleIcon;
    [CATransaction commit];
}

- (NSDragOperation)track:(id<NSDraggingInfo>)info {
    NSPoint p = [self convertPoint:info.draggingLocation fromView:nil];
    CGFloat dx = p.x - self.rest.x, dy = p.y - self.rest.y, d = hypot(dx, dy);
    NSRect reach = NSInsetRect(NSMakeRect(self.rest.x - DPZoneCard.width / 2, self.rest.y - DPZoneCard.height / 2, DPZoneCard.width, DPZoneCard.height), -DPZoneReach, -DPZoneReach);
    BOOL over = NSPointInRect(p, reach);
    CGFloat pull = over ? 0.8 / (1 + d / (1.05 * DPZoneCard.width)) : 0;
    [self pull:CGPointMake(dx * pull, dy * pull)];
    self.hovered = over;
    NSDragOperation mask = info.draggingSourceOperationMask;
    return !over ? NSDragOperationNone : mask & NSDragOperationGeneric ?: mask & NSDragOperationCopy ?: mask & NSDragOperationLink;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return [self track:info]; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info { return [self track:info]; }

- (void)draggingExited:(id<NSDraggingInfo>)info {
    [self pull:CGPointZero];
    self.hovered = NO;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    NSURL *url = [NSURL URLFromPasteboard:info.draggingPasteboard];
    if (!self.hovered || !url) return NO;
    NSPoint link = self.link;
    dispatch_async(dispatch_get_main_queue(), ^{ DPPeekOpenDragged(url, link); });
    return YES;
}

@end

static void DPHideZone(void) {
    NSPanel *panel = DPZonePanel;
    if (!panel) return;
    DPZonePanel = nil;
    [DPZoneRelease invalidate];
    DPZoneRelease = nil;
    [(DPPeekZone *)panel.contentView appear:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [panel.parentWindow removeChildWindow:panel];
        [panel orderOut:nil];
    });
}

static void DPShowZone(NSWindow *window, NSPoint pointer) {
    DPHideZone();
    CGFloat above = pointer.y + DPZoneGap + DPZoneCard.height / 2, below = pointer.y - DPZoneGap - DPZoneCard.height / 2;
    CGFloat y = above + DPZoneCard.height / 2 < NSMaxY([window convertRectToScreen:window.contentLayoutRect]) ? above : below;
    NSSize size = NSMakeSize(DPZoneCard.width + 2 * DPZoneRoom, DPZoneCard.height + 2 * DPZoneRoom);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(pointer.x - size.width / 2, y - size.height / 2, size.width, size.height)
                                                styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = NO;
    panel.releasedWhenClosed = NO;
    panel.appearance = window.effectiveAppearance;
    DPPeekZone *zone = [[DPPeekZone alloc] initWithFrame:(NSRect){NSZeroPoint, size}];
    zone.link = pointer;
    panel.contentView = zone;
    [window addChildWindow:panel ordered:NSWindowAbove];
    [zone appear:YES];
    DPZonePanel = panel;
    // A drop elsewhere ends the session only after the drag image slides home, so hide on release.
    DPZoneRelease = [NSTimer timerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) {
        if (!(NSEvent.pressedMouseButtons & 1)) DPHideZone();
    }];
    [NSRunLoop.mainRunLoop addTimer:DPZoneRelease forMode:NSRunLoopCommonModes];
}

static NSDraggingSession *DPPage_beginDrag(NSView *self, SEL _cmd, NSArray<NSDraggingItem *> *items, NSEvent *event, id source) {
    NSDraggingSession *session = DPCallOriginal(DPPage_beginDrag, self, items, event, source);
    NSURL *url = DPPeek.on && DPPeekDragLinks.on ? [NSURL URLFromPasteboard:session.draggingPasteboard] : nil;
    if (!DPPeekIsWeb(url)) return session;
    DPShowZone(self.window, [self.window convertPointToScreen:event.locationInWindow]);
    return session;
}

static void DPPage_dragEnded(NSView *self, SEL _cmd, NSDraggingSession *session, NSPoint point, NSDragOperation operation) {
    DPCallOriginal(DPPage_dragEnded, self, session, point, operation);
    DPHideZone();
}

static void DPInstallPeekDragLinks(void) {
    DPHook("WebContentsViewCocoa", @selector(beginDraggingSessionWithItems:event:source:), (IMP)DPPage_beginDrag);
    DPHook("WebContentsViewCocoa", @selector(draggingSession:endedAtPoint:operation:), (IMP)DPPage_dragEnded);
}

DP_PATCH(DPPeekDragLinks) {
    .key = @"peekDragLinks",
    .order = 104,
    .title = @"Drag Links to Peek",
    .detail = @"Drag a link and a small card appears above it. Drop the link on the card to open it in Peek, no Shift needed.",
    .symbol = @"hand.point.up.left.fill",
    .tint = @"systemMintColor",
    .classes = DPClasses("WebContentsViewCocoa"),
    .install = DPInstallPeekDragLinks,
    .requires = @"peek",
};
