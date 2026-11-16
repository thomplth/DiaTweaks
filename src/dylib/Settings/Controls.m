#import "Settings.h"

@interface DPSeparatorView : NSView
@end

@implementation DPSeparatorView
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { self.layer.backgroundColor = NSColor.separatorColor.CGColor; }
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, 1); }
// Where NSBox draws its line in the same space.
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0.5, 0, -0.5, 0); }
@end

NSView *DPGroup(NSArray<NSView *> *rows) {
    NSStackView *stack = [NSStackView new];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 0;
    [rows enumerateObjectsUsingBlock:^(NSView *row, NSUInteger i, BOOL *_) {
        if (i > 0) {
            DPSeparatorView *line = [DPSeparatorView new];
            line.wantsLayer = YES;
            [stack addArrangedSubview:line];
            [line.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24].active = YES;
        }
        [stack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }];
    DPFillView *box = [DPFillView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:box.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
    ]];
    return box;
}

NSView *DPRow(NSView *leading, NSView *trailing) {
    NSView *row = [NSView new];
    for (NSView *v in @[leading, trailing]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:v];
    }
    [trailing setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [leading.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [leading.topAnchor constraintEqualToAnchor:row.topAnchor constant:10],
        [leading.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-10],
        [trailing.leadingAnchor constraintGreaterThanOrEqualToAnchor:leading.trailingAnchor constant:12],
        [trailing.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [trailing.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

@interface DPLinkRowView : NSView
@property (nonatomic, copy) void (^open)(void);
@end

@implementation DPLinkRowView
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    BOOL control = [hit isKindOfClass:NSSwitch.class] || [hit isKindOfClass:NSButton.class];
    return !hit || (control && ((NSControl *)hit).enabled) || DPHintOf(hit) ? hit : self;
}
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point, self.bounds)) return;
    NSSwitch *toggle = (NSSwitch *)DPFindView(self, ^BOOL(NSView *v) { return [v isKindOfClass:NSSwitch.class]; });
    NSRect frame = [self convertRect:toggle.bounds fromView:toggle];
    if (toggle.enabled && NSPointInRect(point, frame)) return;
    if (toggle.enabled && NSPointInRect(point, NSInsetRect(frame, -10, -10))) [toggle performClick:nil];
    else self.open();
}
- (BOOL)accessibilityPerformPress {
    self.open();
    return YES;
}
@end

NSView *DPLinkRow(NSView *row, NSString *title, void (^open)(void)) {
    DPLinkRowView *link = [DPLinkRowView new];
    link.open = open;
    link.accessibilityElement = YES;
    link.accessibilityRole = NSAccessibilityButtonRole;
    link.accessibilityLabel = title;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [link addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:link.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:link.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:link.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:link.bottomAnchor],
    ]];
    return link;
}

@interface NSImage (DPPrivateSymbols)
+ (NSImage *)imageWithPrivateSystemSymbolName:(NSString *)name accessibilityDescription:(NSString *)description;
@end

// NSImageView throws on a missing symbol, which crashed Settings.
NSImageView *DPSymbol(NSString *symbols, CGFloat size, NSColor *color) {
    static NSMutableDictionary<NSString *, id> *cache;
    if (!cache) cache = [NSMutableDictionary new];
    NSString *key = [NSString stringWithFormat:@"%@ %g", symbols, size];
    NSImage *image = cache[key];
    if (!image) {
        for (NSString *symbol in [symbols componentsSeparatedByString:@" "]) {
            image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
            if (!image && [NSImage respondsToSelector:@selector(imageWithPrivateSystemSymbolName:accessibilityDescription:)])
                image = [NSImage imageWithPrivateSystemSymbolName:symbol accessibilityDescription:nil];
            if (image) break;
        }
        image = [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightSemibold]];
        cache[key] = image ?: NSNull.null;
    }
    NSImageView *view = [image isKindOfClass:NSImage.class] ? [NSImageView imageViewWithImage:image] : [NSImageView new];
    view.contentTintColor = color;
    return view;
}

void DPFillStack(NSStackView *stack, NSArray<NSView *> *views) {
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    for (NSView *view in views) {
        [stack addArrangedSubview:view];
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        if ([view isMemberOfClass:DPFillView.class]) [stack setCustomSpacing:20 afterView:view];
    }
}

NSStackView *DPColumn(NSArray<NSView *> *views, CGFloat spacing) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = spacing;
    return stack;
}

NSTextField *DPHeader(NSString *text) { return DPLabel(text, 12, NSFontWeightSemibold, NSColor.secondaryLabelColor); }

NSTextField *DPLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.lineBreakStrategy = NSLineBreakStrategyStandard;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    return label;
}

NSView *DPIconTile(NSString *symbol, NSColor *color) { return DPIconTileOfSize(symbol, color, 20); }

static CGFloat DPLinear(CGFloat c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }

static NSColor *DPTileFill(NSColor *color) {
    __block NSColor *rgb;
    [[NSAppearance appearanceNamed:NSAppearanceNameAqua] performAsCurrentDrawingAppearance:^{
        rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    }];
    for (CGFloat dark = 0; dark < 1; dark += 0.01) {
        CGFloat k = 1 - dark;
        CGFloat luminance = 0.2126 * DPLinear(rgb.redComponent * k) + 0.7152 * DPLinear(rgb.greenComponent * k) +
                            0.0722 * DPLinear(rgb.blueComponent * k);
        if (1.05 / (luminance + 0.05) >= 3) return [NSColor colorWithSRGBRed:rgb.redComponent * k green:rgb.greenComponent * k blue:rgb.blueComponent * k alpha:1];
    }
    return NSColor.blackColor;
}

NSView *DPIconTileOfSize(NSString *symbol, NSColor *color, CGFloat size) {
    NSView *tile = [NSView new];
    tile.wantsLayer = YES;
    tile.layer.backgroundColor = DPTileFill(color).CGColor;
    tile.layer.cornerRadius = size / 4;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    NSImageView *glyph = DPSymbol(symbol, size * 0.6, NSColor.whiteColor);
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:glyph];
    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:size],
        [tile.heightAnchor constraintEqualToConstant:size],
        [glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];
    return tile;
}

@implementation DPFillView
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    return self;
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { self.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.05].CGColor; }
@end

@implementation DPFlippedView
- (BOOL)isFlipped { return YES; }
@end
