#import "Patches/EdgeToEdge/EdgeToEdge.h"
#import <objc/message.h>

extern DPPatch DPWindowCorners;
static const CGFloat DPCornerReach = 26, DPMaxRadius = 26;
static NSString *const DPRadiusSetting = @"windowCornerRadius";
static char DPRadiusKey, DPPathKey, DPMaskPathKey, DPShadowPathKey;
#define DPCornerBars (@[ @DPDiaTabStrip, @DPDiaSidebarHeader, @DPDiaSidebarFooter ])

static CGFloat DPCornerRadius(NSWindow *window) { return ((CGFloat (*)(id, SEL))objc_msgSend)(window, @selector(_cornerRadius)); }
static CGFloat DPDiaRadius(id object, CGFloat current) { return [DPDiaValue(object, &DPRadiusKey, @(current)) doubleValue]; }

static NSUserDefaults *DPSettings(void) {
    static NSUserDefaults *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return settings;
}

static CGFloat DPRadius(void) {
    id saved = [DPSettings() objectForKey:DPRadiusSetting];
    return saved ? MIN(MAX([saved doubleValue], 0), DPMaxRadius) : DPMaxRadius;
}

static BOOL DPInFullScreen(NSWindow *window) { return (window.styleMask & NSWindowStyleMaskFullScreen) != 0; }

CGFloat DPWindowCornerGrowth(NSWindow *window) {
    if (!DPWindowCorners.on || !DPIsKind(window, DPDiaWindow) || DPInFullScreen(window)) return 0;
    return DPRadius() - DPDiaRadius(window, DPCornerRadius(window));
}

// AppKit takes a radius under 1 as its default.
static CGFloat DPWindowTarget(NSWindow *window, CGFloat dia) { return DPWindowCorners.on && !DPInFullScreen(window) ? MAX(1, DPRadius()) : dia; }

static void DPRoundWindow(NSWindow *window) {
    CGFloat current = DPCornerRadius(window), dia = DPDiaRadius(window, current);
    CGFloat target = DPWindowTarget(window, dia);
    DPOverride(window, &DPRadiusKey, @(dia), @(target));
    if (current == target) return;
    ((void (*)(id, SEL, CGFloat))objc_msgSend)(window, @selector(_setCornerRadius:), target);
    // macOS 26.7 has no _updateWindowCornerMask, so its older _cornerMaskChanged redraws the mask there.
    SEL update = [window respondsToSelector:@selector(_updateWindowCornerMask)] ? @selector(_updateWindowCornerMask) : @selector(_cornerMaskChanged);
    if ([window respondsToSelector:update]) ((void (*)(id, SEL))objc_msgSend)(window, update);
    [window invalidateShadow];
}

static void DPRoundLayers(CALayer *layer, CGFloat growth) {
    CGFloat dia = DPDiaRadius(layer, layer.cornerRadius);
    if (dia >= 10) {
        CGFloat target = MAX(0, MIN(dia + growth, MAX(dia, MIN(CGRectGetWidth(layer.bounds), CGRectGetHeight(layer.bounds)) / 2)));
        DPOverride(layer, &DPRadiusKey, @(dia), @(target));
        if (layer.cornerRadius != target) layer.cornerRadius = target;
    }
    for (CALayer *sublayer in layer.sublayers) DPRoundLayers(sublayer, growth);
}

static void DPRoundCornerItems(NSView *root) {
    NSView *frame = root.window.contentView.superview;
    if (!frame) return;
    CGFloat growth = DPWindowCornerGrowth(root.window);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DPFindView(root, ^BOOL(NSView *view) {
        if (view == root || view.layer.cornerRadius < 10) return NO;
        NSRect rect = [view convertRect:view.bounds toView:frame], bounds = frame.bounds;
        BOOL side = NSMinX(rect) < DPCornerReach || NSMaxX(rect) > NSMaxX(bounds) - DPCornerReach;
        BOOL end = NSMinY(rect) < DPCornerReach || NSMaxY(rect) > NSMaxY(bounds) - DPCornerReach;
        DPRoundLayers(view.layer, side && end ? growth : 0);
        return NO;
    });
    [CATransaction commit];
}

static CGPathRef DPScaledPath(id owner, char *key, CGPathRef current, CGSize size, CGFloat base, CGFloat scale) {
    CGRect box = CGPathGetBoundingBox(current);
    if (!current || fabs(box.size.width - size.width) > 1 || fabs(box.size.height - size.height) > 1) return NULL;
    id dia = DPDiaValue(owner, key, (__bridge id)current);
    if (dia == (__bridge id)current) dia = CFBridgingRelease(CGPathCreateCopy(current));
    CGPathRef path = DPReshapeCorners((__bridge CGPathRef)dia, base * 1.6, scale, scale);
    DPOverride(owner, key, dia, (__bridge id)path);
    return CGPathEqualToPath(path, current) ? NULL : path;
}

static void DPRoundFloatingLayers(CALayer *layer, CGSize size, CGFloat base, CGFloat growth) {
    if (fabs(layer.bounds.size.width - size.width) < 1 && fabs(layer.bounds.size.height - size.height) < 1 && layer.cornerRadius > 0) {
        CGFloat dia = DPDiaRadius(layer, layer.cornerRadius);
        CGFloat target = MAX(0, dia + growth);
        DPOverride(layer, &DPRadiusKey, @(dia), @(target));
        if (layer.cornerRadius != target) layer.cornerRadius = target;
    }
    CGFloat scale = MAX(0, base + growth) / base;
    CAShapeLayer *shape = [layer isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)layer : nil;
    CAShapeLayer *mask = [layer.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)layer.mask : nil;
    CGPathRef path;
    if ((path = DPScaledPath(shape, &DPPathKey, shape.path, size, base, scale))) shape.path = path;
    if ((path = DPScaledPath(mask, &DPMaskPathKey, mask.path, size, base, scale))) mask.path = path;
    if ((path = DPScaledPath(layer, &DPShadowPathKey, layer.shadowPath, size, base, scale))) layer.shadowPath = path;
    for (CALayer *sublayer in layer.sublayers) DPRoundFloatingLayers(sublayer, size, base, growth);
}

// Dia also rounds the floating sidebar outside layout, so its corner radius is watched.
static void DPRoundFloatingSidebar(NSView *self);

// The watch holds the layer, so it can't go before the observer does.
@interface DPFloatingCornerWatch : NSObject
@property (nonatomic, weak) NSView *sidebar;
@property (nonatomic, strong) CALayer *layer;
@end

@implementation DPFloatingCornerWatch
- (instancetype)initWithSidebar:(NSView *)sidebar {
    if ((self = [super init])) {
        self.sidebar = sidebar;
        self.layer = sidebar.layer;
        [self.layer addObserver:self forKeyPath:@"cornerRadius" options:0 context:NULL];
    }
    return self;
}

- (void)dealloc { [_layer removeObserver:self forKeyPath:@"cornerRadius"]; }

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(CALayer *)layer change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSView *sidebar = self.sidebar;
        if (sidebar.layer == layer) DPRoundFloatingSidebar(sidebar);
    });
}
@end

static char DPWatchedKey;

static void DPRoundFloatingSidebar(NSView *self) {
    DPFloatingCornerWatch *watch = DPGet(self, &DPWatchedKey);
    if (!DPWindowCorners.on || !self.layer) {
        if (watch) DPSet(self, &DPWatchedKey, nil);
    } else if (watch.layer != self.layer) {
        DPSet(self, &DPWatchedKey, [[DPFloatingCornerWatch alloc] initWithSidebar:self]);
    }
    CGFloat base = DPDiaRadius(self.layer, self.layer.cornerRadius);
    if (base <= 0) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DPRoundFloatingLayers(self.layer, self.bounds.size, base, DPWindowCornerGrowth(self.window));
    [CATransaction commit];
}

static void DPFloatingSidebar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFloatingSidebar_layout, self);
    DPRoundFloatingSidebar(self);
}

static void DPBar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPBar_layout, self);
    DPRoundCornerItems(self);
}

static void DPLayer_addAnimation(CALayer *self, SEL _cmd, CAAnimation *animation, NSString *key) {
    DPCallOriginal(DPLayer_addAnimation, self, DPWindowCorners.on ? DPReshapeDiaAnimation(self, animation) : animation, key);
}

static void DPShapeLayer_setPath(CAShapeLayer *self, SEL _cmd, CGPathRef path) {
    DPCallOriginal(DPShapeLayer_setPath, self, DPWindowCorners.on ? DPReshapeSetPath(self, NO, path) : path);
}

static void DPLayer_setShadowPath(CALayer *self, SEL _cmd, CGPathRef path) {
    DPCallOriginal(DPLayer_setShadowPath, self, DPWindowCorners.on ? DPReshapeSetPath(self, YES, path) : path);
}

// Dia tiles the blurred background around the page. Rounder corners expose the seams, which flash as the sidebar slides.
static void DPBackgroundTile_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    NSView *background = self.superview;
    BOOL whole = DPWindowCorners.on && DPIsKind(background, DPDiaWindowBackground);
    DPCallOriginal(DPBackgroundTile_setFrame, self, whole ? background.bounds : frame);
}

static void DPNavigationBar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPNavigationBar_layout, self);
    NSView *container = self;
    while (container && !DPIsKind(container, DPDiaContentContainer)) container = container.superview;
    if (container) DPRoundCornerControls(container);
}

static void DPWindow_becomeKey(NSWindow *self, SEL _cmd) {
    DPCallOriginal(DPWindow_becomeKey, self);
    DPRoundWindow(self);
}

static void DPApplyWindowCorners(DPPatch *patch) {
    for (NSWindow *window in NSApp.windows) if (DPIsKind(window, DPDiaWindow)) DPRoundWindow(window);
    for (NSString *bar in DPCornerBars) for (NSView *view in DPFindViews(bar.UTF8String)) DPRoundCornerItems(view);
    for (NSView *view in DPFindViews(DPDiaFloatingSidebar)) view.needsLayout = YES;
    for (NSView *background in DPFindViews(DPDiaWindowBackground)) {
        background.needsLayout = YES;
        for (NSView *tile in background.subviews) tile.frame = tile.frame;
    }
    DPEdgeToEdge.relayout();
}

static NSString *DPVerifyWindowCorners(DPPatch *patch) {
    for (NSWindow *window in NSApp.windows) {
        if (!DPIsKind(window, DPDiaWindow) || !window.isVisible) continue;
        CGFloat radius = DPCornerRadius(window);
        if (radius != DPWindowTarget(window, DPDiaRadius(window, radius)))
            return patch->on ? @"window corners aren't the chosen radius" : @"window corners keep the chosen radius";
    }
    return nil;
}

@interface DPRadiusRow : NSStackView <NSTextFieldDelegate>
@property NSSlider *slider;
@property NSTextField *field;
@end

@implementation DPRadiusRow
- (void)tune:(NSControl *)control {
    double radius = round(MIN(MAX(control.doubleValue, 0), DPMaxRadius));
    self.slider.doubleValue = self.field.doubleValue = radius;
    [DPSettings() setDouble:radius forKey:DPRadiusSetting];
    if (DPWindowCorners.on) DPApplyWindowCorners(&DPWindowCorners);
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

static NSArray<NSView *> *DPWindowCornersRows(void) {
    DPRadiusRow *row = [DPRadiusRow new];
    row.slider = [NSSlider sliderWithValue:DPRadius() minValue:0 maxValue:DPMaxRadius target:row action:@selector(tune:)];
    row.field = [NSTextField textFieldWithString:@""];
    NSNumberFormatter *whole = [NSNumberFormatter new];
    whole.maximumFractionDigits = 0;
    row.field.formatter = whole;
    row.field.doubleValue = DPRadius();
    row.field.alignment = NSTextAlignmentRight;
    row.field.target = row.field.delegate = row;
    row.field.action = @selector(tune:);
    [row.field.widthAnchor constraintEqualToConstant:44].active = YES;
    [row.slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSTextField *hint = [NSTextField wrappingLabelWithString:@"26 pt is macOS 26, 10 pt is macOS 11 to 15, and 0 is square."];
    hint.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    hint.textColor = NSColor.secondaryLabelColor;
    NSStackView *controls = [NSStackView stackViewWithViews:@[ row.slider, row.field, [NSTextField labelWithString:@"pt"] ]];
    [row setViews:@[ [NSTextField labelWithString:@"Radius"], controls, hint ] inGravity:NSStackViewGravityTop];
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    [controls.widthAnchor constraintEqualToAnchor:row.widthAnchor].active = YES;
    return @[ row ];
}

static void DPInstallWindowCorners(void) {
    DPHook(DPDiaWindow, @selector(becomeKeyWindow), (IMP)DPWindow_becomeKey);
    DPHook(DPDiaFloatingSidebar, @selector(layout), (IMP)DPFloatingSidebar_layout);
    DPHook(DPDiaWindowBackgroundTile, @selector(setFrame:), (IMP)DPBackgroundTile_setFrame);
    DPHook(DPDiaToolbar, @selector(layout), (IMP)DPNavigationBar_layout);
    DPHookClass(CALayer.class, @selector(addAnimation:forKey:), (IMP)DPLayer_addAnimation);
    DPHookClass(CALayer.class, @selector(setShadowPath:), (IMP)DPLayer_setShadowPath);
    DPHookClass(CAShapeLayer.class, @selector(setPath:), (IMP)DPShapeLayer_setPath);
    for (NSString *bar in DPCornerBars) DPHook(bar.UTF8String, @selector(layout), (IMP)DPBar_layout);
    // AppKit flips the style mask just after each will, and a screen-sized window doesn't lay out.
    NSArray<NSNotificationName> *names = @[NSWindowWillEnterFullScreenNotification, NSWindowDidEnterFullScreenNotification,
                                           NSWindowWillExitFullScreenNotification, NSWindowDidExitFullScreenNotification];
    for (NSNotificationName name in names)
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *_) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (DPWindowCorners.on) DPApplyWindowCorners(&DPWindowCorners); });
        }];
    DPOnLaunch(^{ DPApplyWindowCorners(&DPWindowCorners); });
}

DP_PATCH(DPWindowCorners) {
    .key = @"windowCorners",
    .order = 97,
    .title = @"Window Corners",
    .detail = @"Round Dia’s windows like other apps on macOS 26, or pick a smaller radius down to square, with the page’s corners to match.",
    .symbol = @"app.fill",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .classes = DPClasses(DPDiaWindow, DPDiaToolbar, DPDiaFloatingSidebar, DPDiaWindowBackgroundTile, DPDiaWindowBackground, DPDiaTabStrip, DPDiaSidebarHeader, DPDiaSidebarFooter),
    .rows = DPWindowCornersRows,
    .install = DPInstallWindowCorners,
    .apply = DPApplyWindowCorners,
    .verify = DPVerifyWindowCorners,
};
