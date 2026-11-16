#import "StdPatch/StdPatch.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CompactCommandBar/CompactCommandBar.h"

extern DPPatch DPCommandBar, DPCommandBarBlur, DPCommandBarDarken, DPCommandBarShadow, DPCommandBarInteractive, DPCommandBarKeepText;
static char DPOverlayKey, DPHomeKey, DPRecentKey, DPBlankKey, DPSplitKey, DPOwnBarKey, DPLeftTextKey, DPClosedAtKey;

static NSString *const DPHeightKey = @"commandBarHeight", *const DPDarknessKey = @"commandBarDarkness",
                *const DPBlurRadiusKey = @"commandBarBlurRadius", *const DPBlurWindowKey = @"commandBarBlurWindow",
                *const DPShadowIntensityKey = @"commandBarShadowIntensity";

@interface DPCommandBarOverlay : NSView
@property(weak) NSView *page, *panel;
@property(weak) NSWindow *host;
@property(strong) NSView *shade, *windowBlur;
@property(strong) id openedTab, returnTab, keyMonitor;
@property(strong) NSArray<NSView *> *shownShadows;
@property(strong) NSTimer *watch;
@property(copy) NSString *startURL;
@property CGFloat collapsedHeight, collapsedWidth;
@property CFTimeInterval sizedAt;
@property BOOL picked, overBlank, passingThrough;
@end

@interface NSObject (DPCAFilter)
+ (id)filterWithType:(NSString *)type;
@end

static void DPCancelCommandBar(DPCommandBarOverlay *overlay);

static NSUserDefaults *DPSettings(void) {
    static NSUserDefaults *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return settings;
}

static double DPTuned(NSString *key) {
    NSDictionary *defaults = @{ DPHeightKey : @0.3, DPDarknessKey : @0.24, DPBlurRadiusKey : @4, DPBlurWindowKey : @NO,
                                DPShadowIntensityKey : @0.3 };
    return [([DPSettings() objectForKey:key] ?: defaults[key]) doubleValue];
}

static NSMenuItem *DPMenuItemTitled(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *found = [item.title isEqual:title] ? item : DPMenuItemTitled(item.submenu, title);
        if (found) return found;
    }
    return nil;
}

static const NSEventModifierFlags DPShortcutMods = NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl;

static BOOL DPIsShortcut(NSEvent *event, NSString *menuTitle) {
    if (event.type != NSEventTypeKeyDown && event.type != NSEventTypeKeyUp) return NO;
    NSMenuItem *item = DPMenuItemTitled(NSApp.mainMenu, menuTitle);
    return item.keyEquivalent.length && (event.modifierFlags & DPShortcutMods) == item.keyEquivalentModifierMask
        && [event.charactersIgnoringModifiers caseInsensitiveCompare:item.keyEquivalent] == NSOrderedSame;
}

static void DPNoteActiveTab(NSWindow *window) {
    NSString *active = DPActiveTabID(window);
    NSArray *recent = DPGet(window, &DPRecentKey);
    if (active && ![recent.lastObject isEqual:active]) DPSet(window, &DPRecentKey, recent.count ? @[ recent.lastObject, active ] : @[ active ]);
}

static NSString *DPPreviousTabID(NSWindow *window) {
    NSArray *recent = DPGet(window, &DPRecentKey);
    return recent.count > 1 ? recent.firstObject : nil;
}

static NSMutableSet<NSString *> *DPWindowSet(NSWindow *window, const void *key) {
    NSMutableSet *set = DPGet(window, key);
    if (!set && window) DPSet(window, key, set = [NSMutableSet set]);
    return set;
}

static NSMutableSet<NSString *> *DPBlanks(NSWindow *window) { return DPWindowSet(window, &DPBlankKey); }
static NSMutableSet<NSString *> *DPSplits(NSWindow *window) { return DPWindowSet(window, &DPSplitKey); }

static BOOL DPInSplit(NSView *view) {
    NSView *pane = view;
    while (pane && !DPIsKind(pane, DPDiaSplitPane)) pane = pane.superview;
    for (NSView *other in pane.superview.subviews) if (other != pane && DPIsKind(other, DPDiaSplitPane)) return YES;
    return NO;
}

#pragma mark Overlay

static NSTextView *DPBarText(DPCommandBarOverlay *overlay) {
    return (NSTextView *)DPFindView(overlay.panel, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
}

static void DPFocusBar(DPCommandBarOverlay *overlay) {
    NSTextView *text = DPBarText(overlay);
    if (text && overlay.host.firstResponder != text) [overlay.host makeFirstResponder:text];
}

// Dia closes ⌘L's bar when a new tab opens, which DPGoBack's return to the old tab stops.
static void DPCloseCommandBarPopover(NSWindow *window) {
    NSView *popover = DPFindView(window.contentView.superview, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaPopover) && !DPIsFloatingChat(view); });
    NSView *text = DPFindView(popover, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
    [(NSTextView *)text doCommandBySelector:@selector(cancelOperation:)];
}

static CGFloat DPSuggestionsHeight(NSView *panel) {
    CGFloat height = DPFindView(panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBarSuggestions); }).intrinsicContentSize.height;
    return height > 0 ? height + 8 : 0;
}

static NSView *DPCardIn(NSWindow *window) {
    NSView *pane = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaContentPane) && !view.isHiddenOrHasHiddenAncestor; });
    for (NSView *view = pane; view && view != window.contentView; view = view.superview)
        if (view.layer.cornerRadius > 0 && view.layer.maskedCorners && view.layer.masksToBounds) return view;
    return pane;
}

static NSRect DPBarFrame(NSView *view, NSSize size, CGFloat collapsedHeight) {
    NSString *position = DPChoice(&DPCommandBar);
    NSView *card = [position isEqual:@"page"] ? DPCardIn(view.window) : nil;
    if (NSIsEmptyRect(card.bounds)) card = nil;
    NSRect bounds = view.bounds, screen = view.window.screen.visibleFrame, page = card ? [view convertRect:card.bounds fromView:card] : bounds;
    NSPoint origin = NSMakePoint(NSMidX(page) - size.width / 2, NSMidY(page) - collapsedHeight / 2);
    if ([position isEqual:@"macos"] && view.window.screen) {
        NSPoint topLeft = NSMakePoint(NSMidX(screen) - size.width / 2, NSMaxY(screen) - (NSHeight(screen) - collapsedHeight) * DPTuned(DPHeightKey));
        origin = [view convertPoint:[view.window convertPointFromScreen:topLeft] fromView:nil];
    }
    NSRect inside = NSInsetRect(bounds, 12, 12);
    CGFloat x = MAX(MIN(origin.x, NSMaxX(inside) - size.width), NSMinX(inside));
    CGFloat y = MAX(MIN(origin.y, NSMaxY(inside) - size.height), NSMinY(inside));
    return NSMakeRect(round(x), round(y), size.width, size.height);
}

#pragma mark Shade

// The only blur that reaches web content, which Dia's GPU process draws.
static CALayer *DPBlurLayer(void) {
    CALayer *backdrop = [NSClassFromString(@"CABackdropLayer") new];
    id blur = [(id)NSClassFromString(@"CAFilter") filterWithType:@"gaussianBlur"];
    if (!backdrop || !blur) return nil;
    [blur setValue:@(DPTuned(DPBlurRadiusKey)) forKey:@"inputRadius"];
    [blur setValue:@YES forKey:@"inputNormalizeEdges"];
    backdrop.filters = @[ blur ];
    return backdrop;
}

@interface DPPassThroughView : NSView
@end

@implementation DPPassThroughView
- (NSView *)hitTest:(NSPoint)point { return nil; }
@end

static NSView *DPLayerView(NSRect frame, NSArray<CALayer *> *layers) {
    NSView *view = [[DPPassThroughView alloc] initWithFrame:frame];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.wantsLayer = YES;
    for (CALayer *layer in layers) {
        layer.frame = view.bounds;
        layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        [view.layer addSublayer:layer];
    }
    return view;
}

static void DPPlaceShade(NSView *shade, NSWindow *window) {
    NSView *card = DPCardIn(window);
    if (!shade || !card || shade.superview == card) return;
    shade.frame = card.bounds;
    [card addSubview:shade];
}

static NSView *DPAddWindowBlur(NSView *bar) {
    CALayer *blur = DPCommandBarBlur.on && DPTuned(DPBlurWindowKey) ? DPBlurLayer() : nil;
    if (!blur) return nil;
    NSView *view = DPLayerView(bar.superview.bounds, @[ blur ]);
    [bar.superview addSubview:view positioned:NSWindowBelow relativeTo:bar];
    return view;
}

static NSView *DPAddShade(NSWindow *window, BOOL blur) {
    NSMutableArray<CALayer *> *layers = [NSMutableArray array];
    CALayer *backdrop = blur && DPCommandBarBlur.on ? DPBlurLayer() : nil;
    if (backdrop) [layers addObject:backdrop];
    if (DPCommandBarDarken.on) {
        CALayer *dim = [CALayer layer];
        dim.backgroundColor = [NSColor colorWithWhite:0 alpha:DPTuned(DPDarknessKey)].CGColor;
        [layers addObject:dim];
    }
    NSView *shade = DPLayerView(NSZeroRect, layers);
    DPPlaceShade(shade, window);
    return shade;
}

static void DPUpdatePanelShadow(NSView *panel) {
    if (!panel) return;
    if (DPCommandBarShadow.on) {
        NSShadow *shadow = [NSShadow new];
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:MIN(MAX(DPTuned(DPShadowIntensityKey), 0), 0.8)];
        shadow.shadowBlurRadius = 32;
        shadow.shadowOffset = NSMakeSize(0, 0);
        panel.shadow = shadow;
    } else {
        panel.shadow = nil;
    }
}

static void DPShowShade(DPCommandBarOverlay *overlay) {
    [overlay.shade removeFromSuperview];
    [overlay.windowBlur removeFromSuperview];
    overlay.shade = overlay.windowBlur = nil;
    DPUpdatePanelShadow(overlay.panel);
    NSString *returnID = DPTabID(overlay.returnTab);
    if (!returnID || [DPBlanks(overlay.host) containsObject:returnID]) return;
    overlay.windowBlur = DPAddWindowBlur(overlay.panel);
    overlay.shade = DPAddShade(overlay.host, !overlay.windowBlur);
}

@implementation DPCommandBarOverlay

- (BOOL)isFlipped { return YES; }

- (NSRect)frameForPanelSize:(NSSize)size {
    if (!DPIsKind(self.page, DPDiaPopover)) {
        // Measured from the bar, since a tweak may clip the panel; a bar restored at launch is first laid out narrow and too tall.
        NSView *bar = DPFindView(self.panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBar); });
        if (!self.collapsedHeight || NSWidth(bar.frame) != self.collapsedWidth) {
            self.collapsedWidth = NSWidth(bar.frame);
            self.collapsedHeight = NSHeight(bar.frame) - DPSuggestionsHeight(self.panel);
        }
        return DPBarFrame(self, size, self.collapsedHeight);
    }
    size.width = MIN(652, NSWidth((DPCardIn(self.host) ?: self).bounds) - 28);
    return DPBarFrame(self, size, size.height - DPSuggestionsHeight(self.panel));
}

- (void)layout {
    [super layout];
    if (self.panel) self.panel.frame = [self frameForPanelSize:self.panel.frame.size];
    DPPlaceShade(self.shade, self.host);
}

- (NSView *)hitTest:(NSPoint)point {
    if (self.passingThrough) return nil;
    NSView *hit = [super hitTest:point];
    return !hit || (self.panel && [hit isDescendantOf:self.panel]) ? hit : self;
}

- (void)mouseDown:(NSEvent *)event { DPCancelCommandBar(self); }
- (void)rightMouseDown:(NSEvent *)event {}
- (void)scrollWheel:(NSEvent *)event {
    if (!DPCommandBarInteractive.on) return;
    NSView *content = self.host.contentView;
    self.passingThrough = YES;
    NSView *under = [content hitTest:[content convertPoint:event.locationInWindow fromView:nil]];
    self.passingThrough = NO;
    [under scrollWheel:event];
}

@end

#pragma mark Presenting

// Relaid out so the toolbar options for new tab pages see it come and go.
static void DPHidePage(NSView *page, BOOL hidden) {
    page.hidden = hidden;
    for (NSView *view = page.superview; view; view = view.superview)
        if (DPIsKind(view, DPDiaContentPane)) view.needsLayout = YES;
}

static void DPMakeBlank(NSView *page) {
    NSString *active = DPActiveTabID(page.window);
    if (!active) return;
    [DPBlanks(page.window) addObject:active];
    DPSet(page, &DPBlankKey, @YES);
    DPHidePage(page, YES);
}

static NSView *DPBlankPage(NSWindow *window) {
    return DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaNewTabPage) && DPGet(view, &DPBlankKey); });
}

static id DPDismissCommandBar(DPCommandBarOverlay *overlay) {
    [overlay.watch invalidate];
    if (overlay.keyMonitor) [NSEvent removeMonitor:overlay.keyMonitor];
    overlay.keyMonitor = nil;
    [overlay.shade removeFromSuperview];
    if (!overlay.host) return nil;
    if (DPGet(overlay.host, &DPOverlayKey) == overlay) DPSet(overlay.host, &DPOverlayKey, nil);
    overlay.host = nil;
    NSView *page = overlay.page, *panel = overlay.panel, *home = DPGet(panel, &DPHomeKey);
    DPSet(page, &DPOverlayKey, nil);
    DPSet(panel, &DPHomeKey, nil);
    panel.shadow = nil;
    if (panel && home) [home addSubview:panel];
    for (NSView *view in overlay.shownShadows) view.hidden = YES;
    DPHidePage(page, NO);
    home.needsLayout = YES;
    [overlay removeFromSuperview];
    return overlay.openedTab;
}

static void DPCancelCommandBar(DPCommandBarOverlay *overlay) {
    NSView *page = overlay.page;
    BOOL overBlank = overlay.overBlank;
    if (DPIsKind(page, DPDiaPopover)) [DPBarText(overlay) doCommandBySelector:@selector(cancelOperation:)];
    else if (DPCommandBarKeepText.on) DPSet(overlay.host, &DPLeftTextKey, DPBarText(overlay).string.copy);
    NSWindow *host = overlay.host;
    BOOL nowhereToGo = !overlay.returnTab || (!DPScriptTab(host, DPTabID(overlay.returnTab)) && [[DPScriptWindow(host) valueForKey:@"appleScriptTabs"] count] < 2);
    id tab = DPDismissCommandBar(overlay);
    if (!tab) return;
    // Closing a window's only tab would close the window, and Dia with it.
    if (overBlank || nowhereToGo) DPMakeBlank(page);
    else DPCloseTab(tab);
}

static void DPWatchNewTab(DPCommandBarOverlay *overlay) {
    NSWindow *window = overlay.host;
    NSView *content = window.contentView;
    if (!window) return (void)DPDismissCommandBar(overlay);
    if (overlay.superview != content) {  // Dia rebuilds the window's views as it restores a window at launch.
        overlay.frame = content.bounds;
        [content addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    }
    DPPlaceShade(overlay.shade, window);
    id tab = DPScriptTab(window, DPTabID(overlay.openedTab));
    if (!tab) return (void)DPDismissCommandBar(overlay);
    NSString *active = DPActiveTabID(window);
    if (active && ![active isEqual:DPTabID(tab)] && ![active isEqual:DPTabID(overlay.returnTab)]) {
        DPDismissCommandBar(overlay);
        return DPCloseTab(tab);
    }
    if (overlay.returnTab && !DPScriptTab(window, DPTabID(overlay.returnTab))) {
        DPDismissCommandBar(overlay);
        return DPFocusTab(tab);
    }
    // A chat loads no page; Dia empties the bar once it has taken what was typed.
    BOOL taken = overlay.picked && !DPBarText(overlay).string.length;
    NSString *url = [tab valueForKey:@"URL"];
    if (!taken && (url == overlay.startURL || [url isEqual:overlay.startURL])) return;
    DPDismissCommandBar(overlay);
    DPFocusTab(tab);
}

static void DPWatchSoon(DPCommandBarOverlay *overlay, int checks) {
    if (!checks || !overlay.host) return;
    __weak DPCommandBarOverlay *weak = overlay;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!weak.host) return;
        DPWatchNewTab(weak);
        DPWatchSoon(weak, checks - 1);
    });
}

static BOOL DPClickSubmits(DPCommandBarOverlay *overlay, NSEvent *event) {
    NSView *hit = [overlay hitTest:[overlay.superview convertPoint:event.locationInWindow fromView:nil]];
    NSView *suggestions = DPCommandBarPart(overlay.panel, DPDiaCommandBarSuggestions), *go = DPGoButton(DPCommandBarPart(overlay.panel, DPDiaCommandBarToolbar));
    return (suggestions && [hit isDescendantOf:suggestions]) || (go && [hit isDescendantOf:go]);
}

static id DPWatchKeys(DPCommandBarOverlay *overlay) {
    __weak DPCommandBarOverlay *weak = overlay;
    return [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskLeftMouseUp handler:^NSEvent *(NSEvent *event) {
        DPCommandBarOverlay *overlay = weak;
        if (!overlay || event.window != overlay.host) return event;
        BOOL click = event.type == NSEventTypeLeftMouseUp;
        if (click || event.keyCode == 36 || event.keyCode == 76) {
            BOOL submits = click ? DPClickSubmits(overlay, event) : !DPBarText(overlay).hasMarkedText;
            overlay.picked = overlay.picked || (submits && DPBarText(overlay).string.length > 0);
            if (overlay.openedTab) DPWatchSoon(overlay, 60);
            return event;
        }
        BOOL escape = event.keyCode == 53;
        // Caps Lock sets a modifier bit and capitalises the character; ⌘W stands in if the menu has no Close Tab.
        BOOL close = DPMenuItemTitled(NSApp.mainMenu, @"Close Tab") ? DPIsShortcut(event, @"Close Tab")
                                                                       : (event.modifierFlags & DPShortcutMods) == NSEventModifierFlagCommand && event.keyCode == 13;
        if (!escape && !close) return event;
        if (escape && DPBarText(overlay).hasMarkedText) return event;
        NSRect bar = [overlay.host convertRectToScreen:[overlay.panel convertRect:overlay.panel.bounds toView:nil]];
        for (NSWindow *child in overlay.host.childWindows)
            if (escape && child.visible && NSIntersectsRect(child.frame, bar)) return event;
        DPCancelCommandBar(overlay);
        return nil;
    }];
}

// Dia, mid-switch, takes the hidden page's web view out of the window and later titles the window after the new tab; both are undone here.
static void DPGoBack(DPCommandBarOverlay *overlay) {
    NSView *web = DPFindView(overlay.host.contentView, ^BOOL(NSView *view) { return DPIsKind(view, "WebContentsHostView") && !view.isHiddenOrHasHiddenAncestor; });
    NSView *paneHost = web.superview;
    NSString *returnID = DPTabID(overlay.returnTab);
    __weak DPCommandBarOverlay *weak = overlay;
    DPFocusTab(overlay.returnTab);
    if (web) {
        CFRunLoopObserverRef beforeDraw = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, NO, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
            if (web.superview || !paneHost.window) return;
            [paneHost addSubview:web positioned:NSWindowBelow relativeTo:nil];
            [NSLayoutConstraint activateConstraints:@[
                [web.topAnchor constraintEqualToAnchor:paneHost.topAnchor], [web.bottomAnchor constraintEqualToAnchor:paneHost.bottomAnchor],
                [web.leadingAnchor constraintEqualToAnchor:paneHost.leadingAnchor], [web.trailingAnchor constraintEqualToAnchor:paneHost.trailingAnchor],
            ]];
            // A bar cancelled before this ran leaves focus on the pane host, which Dia took while the web view was out.
            NSWindow *window = paneHost.window;
            NSResponder *focus = window.firstResponder;
            if (weak.superview || (focus != paneHost && focus != window) || ![DPActiveTabID(window) isEqual:returnID]) return;
            NSView *page = DPFindView(web, ^BOOL(NSView *view) { return DPIsKind(view, "RenderWidgetHostViewCocoa"); });
            if (page) [window makeFirstResponder:page];
        });
        CFRunLoopAddObserver(CFRunLoopGetMain(), beforeDraw, kCFRunLoopCommonModes);
        CFRelease(beforeDraw);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ if (weak.superview) DPFocusBar(weak); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!weak.superview) return;
        DPFocusTab(weak.returnTab);
        dispatch_async(dispatch_get_main_queue(), ^{ if (weak.superview) DPFocusBar(weak); });
    });
}

// Dia keeps putting back ⌘L's 19 point top inset after sizing by it; the new tab page's is 21, its text 16.
static CGFloat DPStyleAsNewTab(NSView *panel) {
    NSView *bar = DPFindView(panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBar); });
    NSView *input = DPFindView(panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBarText); });
    NSTextView *text = (NSTextView *)DPFindView(input, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
    __strong NSFont **font = (__strong NSFont **)DPIvar(input, "font");
    double *top = DPIvar(bar, "layoutConfiguration");
    if (!text || !font || !top) return 0;
    if (text.font.pointSize != 16) *font = text.font = [NSFont systemFontOfSize:16];
    CGFloat grown = 21 - *top;
    *top = 21;
    bar.needsLayout = YES;  // So a tweak measuring it while the panel sizes sees it styled.
    [bar layoutSubtreeIfNeeded];
    [text scrollRangeToVisible:text.selectedRange];
    return grown;
}

static DPCommandBarOverlay *DPLiftBar(NSView *page, id tabBehind) {
    NSWindow *window = page.window;
    NSView *content = window.contentView, *panel = DPFindView(page, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaAssistantPanel); });
    if (!DPCommandBar.on || !panel || !content || DPGet(page, &DPOverlayKey)) return nil;
    DPCommandBarOverlay *overlay = [[DPCommandBarOverlay alloc] initWithFrame:content.bounds];
    overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    overlay.page = page;
    overlay.panel = panel;
    overlay.host = window;
    overlay.returnTab = tabBehind;
    [content addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    DPSet(page, &DPOverlayKey, overlay);
    DPSet(window, &DPOverlayKey, overlay);
    DPSet(panel, &DPHomeKey, panel.superview);
    [overlay addSubview:panel];
    NSMutableArray<NSView *> *shadows = [NSMutableArray array];
    for (NSView *view in panel.subviews)
        if (DPIsKind(view, DPDiaShadowView) && view.hidden) {
            view.hidden = NO;
            [shadows addObject:view];
        }
    overlay.shownShadows = shadows;
    DPShowShade(overlay);
    panel.frame = [overlay frameForPanelSize:panel.frame.size];
    DPHidePage(page, YES);
    DPFocusBar(overlay);
    overlay.keyMonitor = DPWatchKeys(overlay);
    return overlay;
}

static void DPPresentCommandBar(NSView *page, BOOL overBlank) {
    NSWindow *window = page.window;
    DPCloseCommandBarPopover(window);
    id openedTab = [DPScriptWindow(window) valueForKey:@"activeTab"];
    NSString *openedID = DPTabID(openedTab), *returnID = DPPreviousTabID(window);
    NSArray *recent = DPGet(window, &DPRecentKey);
    if (![recent.lastObject isEqual:openedID]) returnID = recent.lastObject;
    // Going back to a split while Dia is still switching tabs crashes it, so new tabs in or from one keep Dia's own page.
    if (DPInSplit(page) || (!overBlank && [DPSplits(window) containsObject:returnID])) return (void)DPSet(page, &DPOwnBarKey, @YES);
    DPCommandBarOverlay *overlay = openedTab ? DPLiftBar(page, overBlank || !returnID ? nil : DPScriptTab(window, returnID)) : nil;
    if (!overlay) return;
    if (overBlank) {
        [DPBlanks(window) removeObject:openedID];
        DPSet(page, &DPBlankKey, nil);
    }
    NSTextView *text = DPBarText(overlay);
    NSString *left = DPCommandBarKeepText.on ? DPGet(window, &DPLeftTextKey) : nil;
    DPSet(window, &DPLeftTextKey, nil);
    if (overBlank || left.length) [text insertText:left ?: @"" replacementRange:NSMakeRange(0, text.string.length)];
    if (left.length) [text selectAll:nil];
    overlay.overBlank = overBlank;
    overlay.openedTab = openedTab;
    overlay.startURL = [openedTab valueForKey:@"URL"];

    __weak DPCommandBarOverlay *weak = overlay;
    overlay.watch = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        if (weak) DPWatchNewTab(weak); else [timer invalidate];
    }];
    if (!overlay.returnTab) return;
    // Dia can still be showing the new tab when it adds the page, and focusing another tab then crashes it (index out of range).
    // A run loop block runs once Dia is done; a transaction held open until it has gone back keeps the new tab from being drawn.
    [CATransaction begin];
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        @try { if (weak.superview) DPGoBack(weak); } @finally { [CATransaction commit]; }
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

static BOOL DPOpenOverBlank(NSWindow *window) {
    if (!DPCommandBar.on || ![DPBlanks(window) containsObject:DPActiveTabID(window)]) return NO;
    NSView *page = DPBlankPage(window);
    if (page) DPPresentCommandBar(page, YES);
    return page != nil;
}

static void DPCloseLeftBlank(NSWindow *window) {
    if (!window || DPGet(window, &DPOverlayKey)) return;
    NSMutableSet<NSString *> *blanks = DPBlanks(window);
    NSString *previous = DPPreviousTabID(window), *latest = [DPGet(window, &DPRecentKey) lastObject];
    id blank = [blanks containsObject:previous] && ![blanks containsObject:latest] ? DPScriptTab(window, previous) : nil;
    if (!blank || !DPScriptTab(window, latest)) return;
    [blanks removeObject:previous];
    DPCloseTab(blank);
}

#pragma mark Hooks

static void DPPanel_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    DPCommandBarOverlay *overlay = [self.superview isKindOfClass:DPCommandBarOverlay.class] ? (DPCommandBarOverlay *)self.superview : nil;
    if (DPIsKind(overlay.page, DPDiaPopover)) {
        frame.size.height += DPStyleAsNewTab(self);
        overlay.sizedAt = CACurrentMediaTime();
    }
    if (overlay) frame = [overlay frameForPanelSize:frame.size];
    DPCallOriginal(DPPanel_setFrame, self, frame);
}

static DPCommandBarOverlay *DPOverlayAbove(NSView *view) {
    while (view && ![view isKindOfClass:DPCommandBarOverlay.class]) view = view.superview;
    return (DPCommandBarOverlay *)view;
}

static void DPSuggestions_invalidateIntrinsicContentSize(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSuggestions_invalidateIntrinsicContentSize, self);
    DPCommandBarOverlay *overlay = DPOverlayAbove(self);
    if (!overlay || DPIsKind(overlay.page, DPDiaPopover)) return;
    __weak NSView *suggestions = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSView *panel = overlay.panel;
        CGFloat want = overlay.collapsedHeight + DPSuggestionsHeight(panel);
        if (!panel || suggestions.intrinsicContentSize.height < 0 || NSHeight(panel.frame) == want) return;
        panel.frame = [overlay frameForPanelSize:NSMakeSize(NSWidth(panel.frame), want)];
        for (NSView *view = suggestions.superview; view && view != panel; view = view.superview) {
            view.frame = NSMakeRect(0, 0, NSWidth(view.frame), NSHeight(panel.frame));
            view.needsLayout = YES;
        }
        [panel layoutSubtreeIfNeeded];
    });
}

static void DPCapability_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    DPCommandBarOverlay *overlay = DPOverlayAbove(self);
    if (!overlay.returnTab) return DPCallOriginal(DPCapability_mouseDown, self, event);
    DPFocusBar(overlay);
    [DPBarText(overlay) insertText:@"@" replacementRange:DPBarText(overlay).selectedRange];
}

static void DPNewTabButton_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    DPSet(self.window, &DPClosedAtKey, nil);
    if (!DPOpenOverBlank(self.window)) DPCallOriginal(DPNewTabButton_mouseDown, self, event);
}

static NSEvent *DPCommandBarKey(NSEvent *event) {
    NSWindow *window = event.window;
    if (!DPCommandBar.on || !window) return event;
    if (DPIsShortcut(event, @"Close Tab")) DPSet(window, &DPClosedAtKey, @(event.timestamp));
    if (!(DPIsShortcut(event, @"New Tab") || DPIsShortcut(event, @"Open Command Bar"))) return event;
    DPSet(window, &DPClosedAtKey, nil);  // Closing a tab that wasn't the last leaves the stamp unread, which would hide this new tab as a blank.
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    if (overlay) DPFocusBar(overlay);
    return overlay || DPOpenOverBlank(window) ? nil : event;
}

static BOOL DPToolbarShowing(NSWindow *window) {
    return DPFindView(window.contentView, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaToolbar) && !view.isHiddenOrHasHiddenAncestor && view.alphaValue > 0;
    }) != nil;
}

static void DPRemoveAnimations(CALayer *layer) {
    [layer removeAllAnimations];
    for (CALayer *sublayer in layer.sublayers) DPRemoveAnimations(sublayer);
}

static void DPShowWhenBuilt(DPCommandBarOverlay *overlay) {
    overlay.alphaValue = overlay.shade.alphaValue = 0;
    CFTimeInterval opened = CACurrentMediaTime();
    __weak DPCommandBarOverlay *weak = overlay;
    NSTimer *check = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *timer) {
        DPCommandBarOverlay *overlay = weak;
        NSView *toolbar = DPFindView(overlay.panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBarToolbar); });
        CFTimeInterval now = CACurrentMediaTime();
        if (overlay && !(toolbar.alphaValue == 1 && now - overlay.sizedAt > 0.02) && now - opened < 0.5) return;
        [timer invalidate];
        DPRemoveAnimations(overlay.panel.layer);
        overlay.alphaValue = overlay.shade.alphaValue = 1;
    }];
    [NSRunLoop.mainRunLoop addTimer:check forMode:NSRunLoopCommonModes];
}

static void DPPopover_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPopover_viewDidMoveToWindow, self);
    DPCommandBarOverlay *overlay = DPGet(self, &DPOverlayKey);
    if (overlay) return (void)DPDismissCommandBar(overlay);
    if (!DPCommandBar.on || !self.window || DPToolbarShowing(self.window) || DPIsFloatingChat(self)) return;
    overlay = DPLiftBar(self, [DPScriptWindow(self.window) valueForKey:@"activeTab"]);
    if (overlay) DPShowWhenBuilt(overlay);
}

static void DPContentPane_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContentPane_viewDidMoveToWindow, self);
    __weak NSWindow *window = self.window;
    if (!window || !DPCommandBar.on) return;
    DPNoteActiveTab(window);
    NSString *active = DPActiveTabID(window);
    if (active && DPInSplit(self)) [DPSplits(window) addObject:active];
    else if (active) [DPSplits(window) removeObject:active];
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    if (overlay.openedTab) DPWatchNewTab(overlay);
    dispatch_async(dispatch_get_main_queue(), ^{ DPCloseLeftBlank(window); });
}

static void DPNewTabPage_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPNewTabPage_viewDidMoveToWindow, self);
    NSWindow *window = self.window;
    if (!window || !DPCommandBar.on) return;
    DPNoteActiveTab(window);
    NSString *active = DPActiveTabID(window), *previous = DPPreviousTabID(window);
    NSMutableSet<NSString *> *blanks = DPBlanks(window);
    DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
    if (overlay && [active isEqual:DPTabID(overlay.openedTab)]) {
        if (overlay.returnTab) dispatch_async(dispatch_get_main_queue(), ^{ if (overlay.host) DPFocusTab(overlay.returnTab); });
        return;
    }
    // Dia opens a closing last tab's replacement before closing it, and closes a pinned tab only after ⌘W is let go; going back to a tab Dia is still closing crashes Dia.
    NSNumber *closedAt = DPGet(window, &DPClosedAtKey);
    DPSet(window, &DPClosedAtKey, nil);
    BOOL justClosed = closedAt && NSProcessInfo.processInfo.systemUptime - closedAt.doubleValue < 1;
    BOOL closing = DPIsShortcut(NSApp.currentEvent, @"Close Tab") || justClosed || (previous && !DPScriptTab(window, previous));
    if (active && ([blanks containsObject:active] || closing)) {
        DPMakeBlank(self);
        if (overlay.returnTab && !DPScriptTab(window, DPTabID(overlay.returnTab))) DPCancelCommandBar(overlay);
        return;
    }
    if (overlay) DPCancelCommandBar(overlay);
    id blank = [blanks containsObject:previous] ? DPScriptTab(window, previous) : nil;
    if (blank) {
        [blanks removeObject:previous];
        DPCloseTab(blank);
    }
    // The bar takes its size from the page, which has none until its pane lays it out.
    NSView *pane = self.superview;
    while (pane && !DPIsKind(pane, DPDiaContentPane)) pane = pane.superview;
    [pane layoutSubtreeIfNeeded];
    DPPresentCommandBar(self, blank != nil);
}

static void DPApplyCommandBar(DPPatch *patch) {
    BOOL on = DPCommandBar.on;
    for (NSWindow *window in NSApp.windows) {
        if (!on) DPSet(window, &DPBlankKey, nil);
        DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
        if (!overlay) continue;
        if (on) {
            DPShowShade(overlay);
            continue;
        }
        id tab = DPDismissCommandBar(overlay);
        if (tab && overlay.returnTab) DPFocusTab(tab);
    }
    for (NSView *page in DPFindViews(DPDiaNewTabPage)) {
        BOOL blank = DPGet(page, &DPBlankKey) != nil;
        if (on && !blank) DPPresentCommandBar(page, NO);
        if (!on && blank) {
            DPSet(page, &DPBlankKey, nil);
            DPHidePage(page, NO);
        }
    }
}

static NSString *DPVerifyCommandBar(DPPatch *patch) {
    for (NSView *page in DPFindViews(DPDiaNewTabPage)) {
        DPCommandBarOverlay *overlay = DPGet(page, &DPOverlayKey);
        BOOL blank = DPGet(page, &DPBlankKey) != nil;
        if (blank && !page.hidden) return @"a blank tab shows its new tab page";
        if (DPCommandBar.on && !overlay && !blank && !DPGet(page, &DPOwnBarKey)) return @"a new tab page shows without the bar over it";
        if (overlay && overlay.panel.superview != overlay) return @"the bar isn't on the overlay";
    }
    for (NSWindow *window in NSApp.windows) {
        DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
        if (!overlay) continue;
        if (!DPCommandBar.on) return @"the bar is still open";
        BOOL hasShadow = overlay.panel.shadow != nil;
        if (DPCommandBarShadow.on && !hasShadow) return @"the bar has no shadow";
        if (!DPCommandBarShadow.on && hasShadow) return @"the bar still has a shadow";
        if (overlay.superview != window.contentView) return @"the bar is outside the content view, where hovering can't highlight suggestions";
        NSString *active = DPActiveTabID(window);
        if (overlay.openedTab && active && ![active isEqual:DPTabID(overlay.openedTab)] && ![active isEqual:DPTabID(overlay.returnTab)])
            return @"the bar stays over a tab it wasn't opened for";
    }
    return nil;
}

static void DPInstallCommandBar(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPCommandBarKey(event); }];
    DPHook(DPDiaPopover, @selector(viewDidMoveToWindow), (IMP)DPPopover_viewDidMoveToWindow);
    DPHook(DPDiaNewTabButton, @selector(mouseDown:), (IMP)DPNewTabButton_mouseDown);
    DPHook(DPDiaContentPane, @selector(viewDidMoveToWindow), (IMP)DPContentPane_viewDidMoveToWindow);
    DPHook(DPDiaNewTabPage, @selector(viewDidMoveToWindow), (IMP)DPNewTabPage_viewDidMoveToWindow);
    DPHook(DPDiaAssistantPanel, @selector(setFrame:), (IMP)DPPanel_setFrame);
    DPHook(DPDiaCommandBarSuggestions, @selector(invalidateIntrinsicContentSize), (IMP)DPSuggestions_invalidateIntrinsicContentSize);
    DPHook(DPDiaCapabilityButton, @selector(mouseDown:), (IMP)DPCapability_mouseDown);
}

#pragma mark Settings rows

@interface DPCommandBarTuneRow : NSStackView <NSTextFieldDelegate>
@property(copy) NSString *key;
@property double scale;
@property NSSlider *slider;
@property NSTextField *field;
@end

@implementation DPCommandBarTuneRow

- (void)tune:(NSControl *)control {
    double shown = [control isKindOfClass:NSSwitch.class] ? ((NSSwitch *)control).state
                                                          : round(MIN(MAX(control.doubleValue, 0), self.slider.maxValue));
    self.slider.doubleValue = shown;
    self.field.doubleValue = shown;
    [DPSettings() setDouble:shown / self.scale forKey:self.key];
    for (NSWindow *window in NSApp.windows) {
        DPCommandBarOverlay *overlay = DPGet(window, &DPOverlayKey);
        if (overlay) DPShowShade(overlay);
        overlay.needsLayout = YES;
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    NSNumber *step = @{ @"moveUp:" : @1, @"moveDown:" : @-1, @"moveUpAndModifySelection:" : @10, @"moveDownAndModifySelection:" : @-10 }[NSStringFromSelector(command)];
    if (!step) return NO;
    self.field.doubleValue = textView.string.doubleValue + step.doubleValue;
    [self tune:self.field];
    [textView selectAll:nil];
    return YES;
}

@end

static DPCommandBarTuneRow *DPTuneRow(NSString *title, NSString *key, double scale, NSView *control) {
    NSTextField *label = [NSTextField labelWithString:title];
    [label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    DPCommandBarTuneRow *row = [DPCommandBarTuneRow stackViewWithViews:@[ label, control ]];
    row.key = key;
    row.scale = scale;
    return row;
}

static NSView *DPSliderRow(NSString *title, NSString *key, double max, double scale, NSString *unit) {
    double shown = round(DPTuned(key) * scale);
    NSSlider *slider = [NSSlider sliderWithValue:shown minValue:0 maxValue:max target:nil action:@selector(tune:)];
    [slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSNumberFormatter *whole = [NSNumberFormatter new];
    whole.maximumFractionDigits = 0;
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.formatter = whole;
    field.doubleValue = shown;
    field.alignment = NSTextAlignmentRight;
    field.action = @selector(tune:);
    [field.widthAnchor constraintEqualToConstant:44].active = YES;
    NSStackView *controls = [NSStackView stackViewWithViews:@[ slider, field, [NSTextField labelWithString:unit] ]];

    DPCommandBarTuneRow *row = DPTuneRow(title, key, scale, controls);
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    [controls.widthAnchor constraintEqualToAnchor:row.widthAnchor].active = YES;
    row.slider = slider;
    row.field = field;
    slider.target = field.target = field.delegate = row;
    return row;
}

static NSView *DPSwitchRow(NSString *title, NSString *key) {
    NSSwitch *toggle = [NSSwitch new];
    toggle.state = DPTuned(key) ? NSControlStateValueOn : NSControlStateValueOff;
    toggle.action = @selector(tune:);
    DPCommandBarTuneRow *row = DPTuneRow(title, key, 1, toggle);
    row.distribution = NSStackViewDistributionFill;
    toggle.target = row;
    return row;
}

static NSArray<NSView *> *DPCommandBarRows(void) {
    NSView *darkness = DPSliderRow(@"Darkness", DPDarknessKey, 80, 100, @"%"), *radius = DPSliderRow(@"Blur Radius", DPBlurRadiusKey, 60, 1, @"pt"),
           *sidebar = DPSwitchRow(@"Blur Sidebar Too", DPBlurWindowKey),
           *intensity = DPSliderRow(@"Shadow Intensity", DPShadowIntensityKey, 80, 100, @"%");
    darkness.identifier = @"Darken";
    radius.identifier = sidebar.identifier = @"Blur";
    intensity.identifier = @"Shadow";
    return @[ DPSliderRow(@"Space Above Bar", DPHeightKey, 50, 100, @"%"), radius, sidebar, darkness, intensity ];
}

static NSMenu *DPCommandBarPositions(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Position"];
    for (NSArray *item in @[ @[ @"Like Spotlight", @"macos" ], @[ @"Center of Window", @"window" ], @[ @"Center of Page", @"page" ] ]) {
        NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:item[0] action:nil keyEquivalent:@""];
        entry.representedObject = item[1];
        [menu addItem:entry];
    }
    return menu;
}

DP_PATCH(DPCommandBar) {
    .key = @"commandBar",
    .order = 87,
    .title = @"Open New Tabs in Command Bar",
    .detail = @"Open new tabs as Dia’s command bar over the current page, like Arc. Choose a result to open it in a new tab, or press Escape to go back.",
    .symbol = @"command.square.fill",
    .tint = @"systemOrangeColor",
    .section = @"Command Bar",
    .classes = DPClasses(DPDiaContentPane, DPDiaNewTabPage, DPDiaAssistantPanel, DPDiaCommandBarSuggestions),
    .choice = @"commandBarPosition",
    .defaultChoice = @"macos",
    .choices = DPCommandBarPositions,
    .rows = DPCommandBarRows,
    .install = DPInstallCommandBar,
    .apply = DPApplyCommandBar,
    .verify = DPVerifyCommandBar,
};

DP_PATCH(DPCommandBarBlur) {
    .key = @"commandBarBlur",
    .defaultOn = YES,
    .order = 88,
    .title = @"Blur Page Behind",
    .detail = @"Blur the page behind the command bar.",
    .symbol = @"aqi.medium",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Blur",
    .apply = DPApplyCommandBar,
};

DP_PATCH(DPCommandBarDarken) {
    .key = @"commandBarDarken",
    .defaultOn = YES,
    .order = 89,
    .title = @"Darken Page Behind",
    .detail = @"Darken the page behind the command bar.",
    .symbol = @"moon.fill",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Darken",
    .apply = DPApplyCommandBar,
};

DP_PATCH(DPCommandBarShadow) {
    .key = @"commandBarShadow",
    .defaultOn = YES,
    .order = 90,
    .title = @"Shadow Behind Bar",
    .detail = @"Add a shadow behind the command bar so it stands out when Blur and Darken are off, like Arc.",
    .symbol = @"shadow rectangle.fill.on.rectangle.fill",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Shadow",
    .apply = DPApplyCommandBar,
};

DP_PATCH(DPCommandBarInteractive) {
    .key = @"commandBarInteractive",
    .defaultOn = YES,
    .order = 91,
    .title = @"Scroll Page Behind",
    .detail = @"Scroll the page behind the command bar while it's open, like Arc. The pointer doesn't highlight it, and clicking outside closes the bar without clicking the page.",
    .symbol = @"cursorarrow.rays",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Interaction",
    .apply = DPApplyCommandBar,
};

DP_PATCH(DPCommandBarKeepText) {
    .key = @"commandBarKeepText",
    .order = 92,
    .title = @"Remember What You Typed",
    .detail = @"Bring back what you typed when you open the bar again after Escape, selected so you can carry on or type over it.",
    .symbol = @"text.cursor",
    .tint = @"systemOrangeColor",
    .requires = @"commandBar",
    .section = @"Typing",
};
