#import "StdPatch/StdPatch.h"

extern DPPatch DPCommandBar, DPCommandBarBlur, DPCommandBarDarken, DPCommandBarKeepText;
static char DPOverlayKey, DPHomeKey, DPRecentKey, DPBlankKey, DPLeftTextKey;

static NSString *const DPHeightKey = @"commandBarHeight", *const DPDarknessKey = @"commandBarDarkness",
                *const DPBlurRadiusKey = @"commandBarBlurRadius", *const DPBlurWindowKey = @"commandBarBlurWindow";

@interface DPCommandBarOverlay : NSView
@property(weak) NSView *page, *panel;
@property(weak) NSWindow *host;
@property(strong) NSView *shade, *windowBlur;
@property(strong) id openedTab, returnTab, keyMonitor;
@property(strong) NSArray<NSView *> *shownShadows;
@property(strong) NSTimer *watch;
@property(copy) NSString *startURL;
@property CGFloat collapsedHeight;
@property CFTimeInterval sizedAt;
@property BOOL picked, overBlank;
@end

@interface NSObject (DPCAFilter)
+ (id)filterWithType:(NSString *)type;
@end

static void DPCancelCommandBar(DPCommandBarOverlay *overlay);

#pragma mark Settings

static NSUserDefaults *DPSettings(void) {
    static NSUserDefaults *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return settings;
}

static double DPTuned(NSString *key) {
    NSDictionary *defaults = @{ DPHeightKey : @0.3, DPDarknessKey : @0.24, DPBlurRadiusKey : @4, DPBlurWindowKey : @NO };
    return [([DPSettings() objectForKey:key] ?: defaults[key]) doubleValue];
}

static NSMenuItem *DPMenuItemTitled(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        NSMenuItem *found = [item.title isEqual:title] ? item : DPMenuItemTitled(item.submenu, title);
        if (found) return found;
    }
    return nil;
}

static BOOL DPIsShortcut(NSEvent *event, NSString *menuTitle) {
    if (event.type != NSEventTypeKeyDown && event.type != NSEventTypeKeyUp) return NO;
    NSMenuItem *item = DPMenuItemTitled(NSApp.mainMenu, menuTitle);
    NSEventModifierFlags mods = NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl;
    return item.keyEquivalent.length && (event.modifierFlags & mods) == item.keyEquivalentModifierMask
        && [event.charactersIgnoringModifiers caseInsensitiveCompare:item.keyEquivalent] == NSOrderedSame;
}

#pragma mark Tabs

static id DPScriptWindow(NSWindow *window) {
    for (id scripted in [(id)NSApp.delegate valueForKey:@"appleScriptWindows"])
        if ([[scripted valueForKey:@"windowId"] isEqual:window.identifier]) return scripted;
    return nil;
}

static id DPScriptTab(NSWindow *window, NSString *tabID) {
    for (id tab in [DPScriptWindow(window) valueForKey:@"appleScriptTabs"])
        if ([[tab valueForKey:@"tabId"] isEqual:tabID]) return tab;
    return nil;
}

static NSString *DPTabID(id tab) { return [tab valueForKey:@"tabId"]; }
static NSString *DPActiveTabID(NSWindow *window) { return DPTabID([DPScriptWindow(window) valueForKey:@"activeTab"]); }
static void DPFocusTab(id tab) { [tab performSelector:@selector(focus:) withObject:nil]; }
static void DPCloseTab(id tab) { [tab performSelector:@selector(close:) withObject:nil]; }

static void DPNoteActiveTab(NSWindow *window) {
    NSString *active = DPActiveTabID(window);
    NSArray *recent = DPGet(window, &DPRecentKey);
    if (active && ![recent.lastObject isEqual:active]) DPSet(window, &DPRecentKey, recent.count ? @[ recent.lastObject, active ] : @[ active ]);
}

static NSString *DPPreviousTabID(NSWindow *window) {
    NSArray *recent = DPGet(window, &DPRecentKey);
    return recent.count > 1 ? recent.firstObject : nil;
}

static NSMutableSet<NSString *> *DPBlanks(NSWindow *window) {
    NSMutableSet *blanks = DPGet(window, &DPBlankKey);
    if (!blanks && window) DPSet(window, &DPBlankKey, blanks = [NSMutableSet set]);
    return blanks;
}

#pragma mark Overlay

static NSView *DPPanelIn(NSView *page) {
    return DPFindView(page, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaAssistantPanel); });
}

static NSTextView *DPBarText(DPCommandBarOverlay *overlay) {
    return (NSTextView *)DPFindView(overlay.panel, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
}

static void DPFocusBar(DPCommandBarOverlay *overlay) {
    NSTextView *text = DPBarText(overlay);
    if (text && overlay.host.firstResponder != text) [overlay.host makeFirstResponder:text];
}

static CGFloat DPSuggestionsHeight(NSView *panel) {
    CGFloat height = DPFindView(panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBarSuggestions); }).intrinsicContentSize.height;
    return height > 0 ? height + 8 : 0;
}

// Like NSWindow.center(), macOS center leaves a share of the screen's spare height above the bar.
static NSRect DPBarFrame(NSView *view, NSSize size, CGFloat collapsedHeight) {
    NSRect bounds = view.bounds, screen = view.window.screen.visibleFrame;
    NSPoint origin = NSMakePoint(NSMidX(bounds) - size.width / 2, NSMidY(bounds) - collapsedHeight / 2);
    if ([DPChoice(&DPCommandBar) isEqual:@"macos"] && view.window.screen) {
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

static NSView *DPCardIn(NSWindow *window) {
    NSView *pane = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaContentPane) && !view.isHiddenOrHasHiddenAncestor; });
    for (NSView *view = pane; view && view != window.contentView; view = view.superview)
        if (view.layer.cornerRadius > 0 && view.layer.maskedCorners && view.layer.masksToBounds) return view;
    return pane;
}

static NSView *DPLayerView(NSRect frame, NSArray<CALayer *> *layers) {
    NSView *view = [[NSView alloc] initWithFrame:frame];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.wantsLayer = YES;
    for (CALayer *layer in layers) {
        layer.frame = view.bounds;
        layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        [view.layer addSublayer:layer];
    }
    return view;
}

// In the card, so it moves with it as the sidebar slides.
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

static void DPShowShade(DPCommandBarOverlay *overlay) {
    [overlay.shade removeFromSuperview];
    [overlay.windowBlur removeFromSuperview];
    overlay.shade = overlay.windowBlur = nil;
    NSString *returnID = DPTabID(overlay.returnTab);
    if (!returnID || [DPBlanks(overlay.host) containsObject:returnID]) return;
    overlay.windowBlur = DPAddWindowBlur(overlay.panel);
    overlay.shade = DPAddShade(overlay.host, !overlay.windowBlur);
}

@implementation DPCommandBarOverlay

- (BOOL)isFlipped { return YES; }

// ⌘L's popover resizes its bar through heights that come and go as it opens, so its collapsed height can't be kept.
- (NSRect)frameForPanelSize:(NSSize)size {
    if (!DPIsKind(self.page, DPDiaPopover)) {
        if (!self.collapsedHeight) {  // From the bar, since a tweak may clip the panel.
            NSView *bar = DPFindView(self.panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaCommandBar); });
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
    NSView *hit = [super hitTest:point];
    return !hit || (self.panel && [hit isDescendantOf:self.panel]) ? hit : self;
}

- (void)mouseDown:(NSEvent *)event { DPCancelCommandBar(self); }
- (void)rightMouseDown:(NSEvent *)event {}
- (void)scrollWheel:(NSEvent *)event {}

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
    id tab = DPDismissCommandBar(overlay);
    if (overBlank) DPMakeBlank(page);
    else if (tab) DPCloseTab(tab);
}

static void DPWatchNewTab(DPCommandBarOverlay *overlay) {
    NSWindow *window = overlay.host;
    NSView *frame = window.contentView.superview;
    if (!window) return (void)DPDismissCommandBar(overlay);
    if (overlay.superview != frame) {  // Dia rebuilds the frame view as it restores a window at launch.
        overlay.frame = frame.bounds;
        [frame addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    }
    DPPlaceShade(overlay.shade, window);
    id tab = DPScriptTab(window, DPTabID(overlay.openedTab));
    if (!tab) return (void)DPDismissCommandBar(overlay);
    // A chat loads no page; Dia empties the bar once it has taken what was typed.
    BOOL taken = overlay.picked && !DPBarText(overlay).string.length;
    NSString *url = [tab valueForKey:@"URL"];
    if (!taken && (url == overlay.startURL || [url isEqual:overlay.startURL])) return;
    DPDismissCommandBar(overlay);
    DPFocusTab(tab);
}

static void DPWatchSoon(DPCommandBarOverlay *overlay, int checks) {
    __weak DPCommandBarOverlay *weak = overlay;
    if (checks && overlay.host)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (!weak.host) return;
            DPWatchNewTab(weak);
            DPWatchSoon(weak, checks - 1);
        });
}

static id DPWatchKeys(DPCommandBarOverlay *overlay) {
    __weak DPCommandBarOverlay *weak = overlay;
    return [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskLeftMouseUp handler:^NSEvent *(NSEvent *event) {
        DPCommandBarOverlay *overlay = weak;
        if (!overlay || event.window != overlay.host) return event;
        if (event.type == NSEventTypeLeftMouseUp || event.keyCode == 36 || event.keyCode == 76) {
            overlay.picked = overlay.picked || DPBarText(overlay).string.length > 0;
            if (overlay.openedTab) DPWatchSoon(overlay, 60);
            return event;
        }
        BOOL escape = event.keyCode == 53;
        BOOL close = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand
                     && [event.charactersIgnoringModifiers isEqualToString:@"w"];
        if (!escape && !close) return event;
        NSRect bar = [overlay.host convertRectToScreen:[overlay.panel convertRect:overlay.panel.bounds toView:nil]];
        for (NSWindow *child in overlay.host.childWindows)  // The @ menu, which Escape closes first.
            if (escape && child.visible && NSIntersectsRect(child.frame, bar)) return event;
        DPCancelCommandBar(overlay);
        return nil;
    }];
}

// Going back before Dia first draws the new tab hides the new tab page, but Dia, mid-switch, then takes the page's web
// view out of the window, leaving it unclickable, and later titles the window after the new tab. Both are undone here.
static void DPGoBack(DPCommandBarOverlay *overlay) {
    NSView *web = DPFindView(overlay.host.contentView, ^BOOL(NSView *view) { return DPIsKind(view, "WebContentsHostView") && !view.isHiddenOrHasHiddenAncestor; });
    NSView *paneHost = web.superview;
    DPFocusTab(overlay.returnTab);
    if (web) {
        CFRunLoopObserverRef beforeDraw = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, NO, 0, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
            if (web.superview || !paneHost.window) return;
            [paneHost addSubview:web positioned:NSWindowBelow relativeTo:nil];
            [NSLayoutConstraint activateConstraints:@[
                [web.topAnchor constraintEqualToAnchor:paneHost.topAnchor], [web.bottomAnchor constraintEqualToAnchor:paneHost.bottomAnchor],
                [web.leadingAnchor constraintEqualToAnchor:paneHost.leadingAnchor], [web.trailingAnchor constraintEqualToAnchor:paneHost.trailingAnchor],
            ]];
        });
        CFRunLoopAddObserver(CFRunLoopGetMain(), beforeDraw, kCFRunLoopCommonModes);
        CFRelease(beforeDraw);
    }
    __weak DPCommandBarOverlay *weak = overlay;
    dispatch_async(dispatch_get_main_queue(), ^{ if (weak.superview) DPFocusBar(weak); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!weak.superview) return;
        DPFocusTab(weak.returnTab);
        dispatch_async(dispatch_get_main_queue(), ^{ if (weak.superview) DPFocusBar(weak); });
    });
}

// ⌘L's bar has 13 point text with 19 points above it, where the new tab page's has 16 and 21. Dia keeps putting back the
// 19 after sizing the bar by it, so this returns the height the 21 adds.
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
    return grown;
}

static DPCommandBarOverlay *DPLiftBar(NSView *page, id tabBehind) {
    NSWindow *window = page.window;
    NSView *frame = window.contentView.superview, *panel = DPPanelIn(page);
    if (!DPCommandBar.on || !panel || !frame || DPGet(page, &DPOverlayKey)) return nil;
    DPCommandBarOverlay *overlay = [[DPCommandBarOverlay alloc] initWithFrame:frame.bounds];
    overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    overlay.page = page;
    overlay.panel = panel;
    overlay.host = window;
    overlay.returnTab = tabBehind;
    [frame addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    DPSet(page, &DPOverlayKey, overlay);
    DPSet(window, &DPOverlayKey, overlay);
    DPSet(panel, &DPHomeKey, panel.superview);
    [overlay addSubview:panel];
    NSMutableArray<NSView *> *shadows = [NSMutableArray array];
    for (NSView *view in panel.subviews)  // ⌘L's popover hides one, drawing its own.
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
    id openedTab = [DPScriptWindow(window) valueForKey:@"activeTab"];
    NSString *openedID = DPTabID(openedTab), *returnID = DPPreviousTabID(window);
    NSArray *recent = DPGet(window, &DPRecentKey);
    if (![recent.lastObject isEqual:openedID]) returnID = recent.lastObject;
    DPCommandBarOverlay *overlay = openedTab ? DPLiftBar(page, overBlank || !returnID ? nil : DPScriptTab(window, returnID)) : nil;
    if (!overlay) return;
    if (overBlank) {
        [DPBlanks(window) removeObject:openedID];
        DPSet(page, &DPBlankKey, nil);
    }
    // What was typed before Escape comes back selected, like Arc, so it can be carried on or typed over.
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
    if (overlay.returnTab) DPGoBack(overlay);
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

// The new tab page sizes its bar to the suggestions, so out of it, the bar is sized here. ⌘L's popover sizes its own.
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

// "Add tabs or files" only opens its menu on a showing new tab page, but @ opens the same one.
static void DPCapability_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    DPCommandBarOverlay *overlay = DPOverlayAbove(self);
    if (!overlay.returnTab) return DPCallOriginal(DPCapability_mouseDown, self, event);
    DPFocusBar(overlay);
    [DPBarText(overlay) insertText:@"@" replacementRange:DPBarText(overlay).selectedRange];
}

static void DPNewTabButton_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    if (!DPOpenOverBlank(self.window)) DPCallOriginal(DPNewTabButton_mouseDown, self, event);
}

static NSEvent *DPCommandBarKey(NSEvent *event) {
    NSWindow *window = event.window;
    if (!DPCommandBar.on || !window || !(DPIsShortcut(event, @"New Tab") || DPIsShortcut(event, @"Open Command Bar"))) return event;
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

// Dia builds ⌘L's bar over a few frames, then fades it in. It's shown once its toolbar is in and resizing has stopped.
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

// ⌘L's bar is the same panel, in a popover under the address field. With no toolbar showing, it's lifted like a new tab's.
static void DPPopover_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPopover_viewDidMoveToWindow, self);
    DPCommandBarOverlay *overlay = DPGet(self, &DPOverlayKey);
    if (overlay) return (void)DPDismissCommandBar(overlay);
    if (!DPCommandBar.on || !self.window || DPToolbarShowing(self.window)) return;
    overlay = DPLiftBar(self, [DPScriptWindow(self.window) valueForKey:@"activeTab"]);
    if (overlay) DPShowWhenBuilt(overlay);
}

static void DPContentPane_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContentPane_viewDidMoveToWindow, self);
    __weak NSWindow *window = self.window;
    if (!window || !DPCommandBar.on) return;
    DPNoteActiveTab(window);
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
    // Dia opens the tab replacing a closing last tab before closing it, so only the shortcut, or later the old tab
    // being gone, tells a close.
    BOOL closing = DPIsShortcut(NSApp.currentEvent, @"Close Tab") || (previous && !DPScriptTab(window, previous));
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

#pragma mark Patch

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
        if (DPCommandBar.on && !overlay && !blank) return @"a new tab page shows without the bar over it";
        if (overlay && overlay.panel.superview != overlay) return @"the bar isn't on the overlay";
    }
    for (NSWindow *window in NSApp.windows)
        if (!DPCommandBar.on && DPGet(window, &DPOverlayKey)) return @"the bar is still open";
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
    return @[
        DPSliderRow(@"Space Above Bar", DPHeightKey, 50, 100, @"%"),
        DPSliderRow(@"Darkness", DPDarknessKey, 80, 100, @"%"),
        DPSliderRow(@"Blur Radius", DPBlurRadiusKey, 60, 1, @"pt"),
        DPSwitchRow(@"Blur Sidebar Too", DPBlurWindowKey),
    ];
}

static NSMenu *DPCommandBarPositions(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Position"];
    for (NSArray *item in @[ @[ @"Like Spotlight", @"macos" ], @[ @"Center of Window", @"window" ] ]) {
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
    .section = @"Command Bar",
    .requires = @"commandBar",
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
    .section = @"Command Bar",
    .requires = @"commandBar",
    .apply = DPApplyCommandBar,
};

DP_PATCH(DPCommandBarKeepText) {
    .key = @"commandBarKeepText",
    .order = 90,
    .title = @"Remember What You Typed",
    .detail = @"Bring back what you typed when you open the bar again after Escape, selected so you can carry on or type over it.",
    .symbol = @"text.cursor",
    .tint = @"systemOrangeColor",
    .section = @"Command Bar",
    .requires = @"commandBar",
};
