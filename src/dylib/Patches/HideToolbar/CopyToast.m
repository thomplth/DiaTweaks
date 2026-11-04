#import "HideToolbar.h"

static const CGFloat DPToastHeight = 30, DPToastInset = 10, DPToastDrop = 8;
static const NSTimeInterval DPToastFade = 0.2, DPToastHold = 1.4;
static char DPToastKey;

// A pill at the top of the pane that says what was copied, then goes away. It never takes the pointer.
@interface DPCopyToastView : NSVisualEffectView
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, strong) NSTimer *hideTimer;
@end

@implementation DPCopyToastView

- (instancetype)init {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.material = NSVisualEffectMaterialPopover;
    self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.state = NSVisualEffectStateActive;
    self.wantsLayer = YES;
    self.layer.cornerRadius = DPToastHeight / 2;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [NSColor.separatorColor CGColor];
    self.alphaValue = 0;

    NSImageSymbolConfiguration *weight = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightSemibold];
    NSImageView *icon = [NSImageView imageViewWithImage:[[NSImage imageWithSystemSymbolName:@"checkmark" accessibilityDescription:nil]
                                                            imageWithSymbolConfiguration:weight]];
    icon.contentTintColor = NSColor.secondaryLabelColor;
    self.label = [NSTextField labelWithString:@""];
    self.label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.label.textColor = NSColor.labelColor;
    NSStackView *stack = [NSStackView stackViewWithViews:@[icon, self.label]];
    stack.spacing = 6;
    stack.edgeInsets = NSEdgeInsetsMake(0, 12, 0, 14);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    return self;
}

- (void)dealloc { [_hideTimer invalidate]; }

- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)updateLayer {
    [super updateLayer];
    self.layer.borderColor = [NSColor.separatorColor CGColor];  // Follows light and dark.
}

// Centered at the top of the pane, `drop` points above where it rests.
- (NSRect)frameInPane:(NSView *)pane drop:(CGFloat)drop {
    CGFloat width = ceil(self.fittingSize.width), top = DPToastInset - drop;
    CGFloat y = pane.isFlipped ? top : NSHeight(pane.bounds) - top - DPToastHeight;
    return NSMakeRect(round(NSMidX(pane.bounds) - width / 2), y, width, DPToastHeight);
}

- (void)animateTo:(BOOL)shown in:(NSView *)pane completion:(void (^)(void))completion {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = DPToastFade;
        context.timingFunction = [CAMediaTimingFunction functionWithName:shown ? kCAMediaTimingFunctionEaseOut : kCAMediaTimingFunctionEaseIn];
        self.animator.alphaValue = shown;
        self.animator.frame = [self frameInPane:pane drop:shown ? 0 : DPToastDrop];
    } completionHandler:completion];
}

- (void)showMessage:(NSString *)message in:(NSView *)pane {
    self.label.stringValue = message;
    [self.hideTimer invalidate];
    if (self.superview != pane) self.frame = [self frameInPane:pane drop:DPToastDrop];
    [pane addSubview:self positioned:NSWindowAbove relativeTo:nil];  // Over the page, and over the toolbar if it shows.
    [self animateTo:YES in:pane completion:nil];
    __weak DPCopyToastView *weakSelf = self;
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:DPToastFade + DPToastHold repeats:NO block:^(NSTimer *timer) {
        [weakSelf animateTo:NO in:pane completion:^{
            DPCopyToastView *me = weakSelf;
            if (me.alphaValue == 0) [me removeFromSuperview];  // Unless another copy brought it back.
        }];
    }];
}
@end

void DPShowCopyToast(NSView *pane, NSString *message) {
    DPCopyToastView *toast = DPGet(pane, &DPToastKey);
    if (!toast) DPSet(pane, &DPToastKey, toast = [DPCopyToastView new]);
    [toast showMessage:message in:pane];
}

void DPRemoveCopyToasts(void) {
    for (NSView *pane in DPPanes) {
        DPCopyToastView *toast = DPGet(pane, &DPToastKey);
        [toast.hideTimer invalidate];
        [toast removeFromSuperview];
        toast.alphaValue = 0;
    }
}

NSString *DPVerifyNoCopyToast(DPPatch *patch) {
    for (NSView *pane in DPFindViews(DPDiaContentPane))
        for (NSView *view in pane.subviews)
            if ([view isKindOfClass:DPCopyToastView.class] && !patch->on) return @"toast left on the page";
    return nil;
}
