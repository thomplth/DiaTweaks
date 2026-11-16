#import "Patches/Peek/Peek.h"
#import "Patches/CommandBar/Tabs.h"

static id DPTabState(NSView *tab) {
    return DPSwiftValue(DPSwiftValue(DPSwiftValue(tab, @"viewModel"), @"stateSubject"), @"currentValue");
}

// selectionStyle is nil on an unselected pinned tab, "none" on other unselected tabs, above/below beside the selection.
static BOOL DPTabSelected(NSView *tab) {
    NSString *style = [[DPSwiftValue(DPTabState(tab), @"selectionStyle") description] lowercaseString];
    return style && ![style containsString:@"none"] && ![style containsString:@"above"] && ![style containsString:@"below"];
}

static NSArray<NSView *> *DPTabsIn(NSWindow *window) {
    NSMutableArray<NSView *> *tabs = [NSMutableArray array];
    for (NSView *tab in [DPFindViews(DPDiaTabView) arrayByAddingObjectsFromArray:DPFindViews(DPDiaPinnedTab)])
        if (tab.window == window) [tabs addObject:tab];
    return tabs;
}

static NSString *DPPeekPageID(id page) {
    for (NSString *key in @[@"identifier", @"id", @"contentID", @"contentId", @"uuid"]) {
        NSString *value = [DPSwiftValue((NSObject *)page, key) description];
        if (value.length >= 32 && [value containsString:@"-"]) return value;
    }
    return nil;
}

static NSView *DPPeekOriginTab(NSWindow *window, id source) {
    NSString *sourceID = DPPeekPageID(source);
    NSView *selected = nil;
    for (NSView *tab in DPTabsIn(window)) {
        if (sourceID && [[DPTabState(tab) description] containsString:sourceID]) return tab;
        if (!selected && DPTabSelected(tab)) selected = tab;
    }
    return selected;
}

static NSString *DPPeekTabContentKey(NSView *tab) {
    NSString *state = [DPTabState(tab) description];
    NSRange mark = [state rangeOfString:@"contentIDs: ["];
    if (mark.location == NSNotFound || state.length < NSMaxRange(mark) + 36) return nil;
    NSString *key = [state substringWithRange:NSMakeRange(NSMaxRange(mark), 36)];
    return [key containsString:@"-"] ? key : nil;
}

static NSView *DPPeekTabWithContent(NSWindow *window, NSString *key) {
    for (NSView *tab in DPTabsIn(window))
        if ([[DPTabState(tab) description] containsString:key]) return tab;
    return nil;
}

static BOOL DPTabIsTop(NSView *tab) {
    for (NSView *view = tab; view; view = view.superview)
        if ([NSStringFromClass(view.class) containsString:@"TabStrip"]) return YES;
    return NO;
}

@interface DPPeekTabBadge : NSView
@property (nonatomic, weak) DPPeekCard *peek;
@property (nonatomic, copy) NSString *contentKey, *frontIDAtOpen;
@property (nonatomic) BOOL pinned;
@property (nonatomic, strong) NSTrackingArea *tabTracking;
@property (nonatomic, weak) NSView *trackedTab;
@property (nonatomic, strong) NSTimer *watch;
@end

@implementation DPPeekTabBadge
- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    [self.trackedTab removeTrackingArea:self.tabTracking];
    self.tabTracking = nil;
    if (!self.superview || self.pinned) return;
    self.tabTracking = [[NSTrackingArea alloc] initWithRect:self.superview.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self.superview addTrackingArea:self.tabTracking];
    self.trackedTab = self.superview;
}

- (void)mouseEntered:(NSEvent *)event { if (!self.pinned) self.hidden = YES; }
- (void)mouseExited:(NSEvent *)event { self.hidden = NO; }

- (void)watch:(NSTimer *)timer {
    DPPeekCard *peek = self.peek;
    if (!peek || peek.closing) return [self stop];
    NSView *tab = self.superview;
    if (!self.contentKey) {
        // A pinned tab's state is briefly unreadable at times; only a readable, unselected one means it was left.
        if (self.pinned && tab && DPTabState(tab) && !DPTabSelected(tab)) [self closePeek];
        return;
    }
    tab = DPPeekTabWithContent(peek.window, self.contentKey);
    if (!tab) {
        // A missing row says nothing (the sidebar builds rows lazily); only the tab closing or another coming to the front does.
        NSString *front = DPActiveTabID(peek.window);
        if (!peek.source || (self.frontIDAtOpen && front && ![front isEqual:self.frontIDAtOpen])) [self closePeek];
        return;
    }
    if (self.superview != tab) [tab addSubview:self];
    if (!DPTabSelected(tab)) [self closePeek];
}

- (void)closePeek {
    [self stop];
    [self.peek close:DPPeekClose];
}

- (void)stop {
    [self.watch invalidate];
    self.watch = nil;
}
@end

void DPPeekShowTabBadge(DPPeekCard *peek, id source) {
    NSView *tab = DPPeekOriginTab(peek.window, source);
    if (!tab) return;
    BOOL pinned = DPIsKind(tab, DPDiaPinnedTab), top = DPTabIsTop(tab);
    NSTextField *eyes = [NSTextField labelWithString:@"👀"];
    eyes.font = [NSFont systemFontOfSize:pinned ? 11 : 12];
    eyes.alignment = NSTextAlignmentCenter;
    [eyes sizeToFit];
    CGFloat w = NSWidth(eyes.frame), h = NSHeight(eyes.frame);
    NSRect frame;
    NSAutoresizingMaskOptions resize;
    if (pinned) {
        frame = NSMakeRect(top ? NSMidX(tab.bounds) - w / 2 : NSMaxX(tab.bounds) - w - 2, tab.isFlipped ? 2 : NSMaxY(tab.bounds) - h - 2, w, h);
        resize = (top ? NSViewMinXMargin | NSViewMaxXMargin : NSViewMinXMargin) | (tab.isFlipped ? NSViewMaxYMargin : NSViewMinYMargin);
    } else {
        frame = NSMakeRect(NSMaxX(tab.bounds) - w - 6, NSMidY(tab.bounds) - h / 2, w, h);
        resize = NSViewMinXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    }
    DPPeekTabBadge *badge = [[DPPeekTabBadge alloc] initWithFrame:frame];
    badge.autoresizingMask = resize;
    badge.peek = peek;
    badge.pinned = pinned;
    badge.contentKey = DPPeekTabContentKey(tab);
    badge.frontIDAtOpen = DPActiveTabID(peek.window);
    eyes.frame = NSOffsetRect(badge.bounds, 0, !pinned && top ? 2 : 0);
    eyes.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [badge addSubview:eyes];
    [tab addSubview:badge];
    peek.tabBadge = badge;
    badge.watch = [NSTimer scheduledTimerWithTimeInterval:0.6 target:badge selector:@selector(watch:) userInfo:nil repeats:YES];
}

void DPPeekHideTabBadge(DPPeekCard *peek) {
    [(DPPeekTabBadge *)peek.tabBadge stop];
    [peek.tabBadge removeFromSuperview];
    peek.tabBadge = nil;
}
