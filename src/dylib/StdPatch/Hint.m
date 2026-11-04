#import "StdPatch.h"

static char DPHintKey;

@interface DPHint : NSObject
@property (nonatomic, weak) NSView *view;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSTrackingArea *area;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation DPHint

- (void)show {
    NSView *view = self.view;
    if (!self.text || self.popover.shown || !view.window || view.hiddenOrHasHiddenAncestor) return;
    NSTextField *label = [NSTextField wrappingLabelWithString:self.text];
    label.preferredMaxLayoutWidth = 240;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *content = [NSView new];
    [content addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [label.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [label.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-8],
    ]];
    content.frame = (NSRect){NSZeroPoint, content.fittingSize};  // Sized up front, or the popover opens as a sliver.
    self.popover = [NSPopover new];
    self.popover.contentViewController = [NSViewController new];
    self.popover.contentViewController.view = content;
    self.popover.contentViewController.preferredContentSize = content.frame.size;
    self.popover.behavior = NSPopoverBehaviorTransient;  // A click anywhere closes it, and still goes where it was aimed.
    [self.popover showRelativeToRect:view.bounds ofView:view preferredEdge:view.isFlipped ? NSRectEdgeMinY : NSRectEdgeMaxY];
}

- (void)hide {
    [self.timer invalidate];
    self.timer = nil;
    [self.popover close];
}

- (void)mouseEntered:(NSEvent *)event {
    [self.timer invalidate];
    __weak DPHint *weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *timer) { [weakSelf show]; }];
}

- (void)mouseExited:(NSEvent *)event { [self hide]; }

- (void)dealloc {
    [_timer invalidate];
    [_popover close];
}
@end

void DPSetHint(NSView *view, NSString *text) {
    DPHint *hint = DPGet(view, &DPHintKey);
    if ([hint.text isEqual:text]) return;
    [hint hide];
    if (!text) {
        if (hint) [view removeTrackingArea:hint.area];  // It doesn't keep its owner alive.
        return DPSet(view, &DPHintKey, nil);
    }
    if (!hint) {
        hint = [DPHint new];
        hint.view = view;
        hint.area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
            options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:hint userInfo:nil];
        [view addTrackingArea:hint.area];
        DPSet(view, &DPHintKey, hint);
    }
    hint.text = text;
}

NSString *DPHintOf(NSView *view) { return [DPGet(view, &DPHintKey) text]; }

void DPShowHint(NSView *view) { [DPGet(view, &DPHintKey) show]; }
