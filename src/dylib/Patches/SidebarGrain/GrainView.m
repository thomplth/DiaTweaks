#import "SidebarGrain.h"

@interface NSWindow (DPGrainAppearance)
- (BOOL)_hasActiveAppearance;
@end
@interface NSView (DPGrainAppearance)
- (void)_windowChangedKeyState;
@end

@implementation DPSidebarGrainView {
    CGFloat _grainOpacity, _softness, _scale;
    NSString *_material, *_space;
    BOOL _darkAppearance;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    return self;
}

- (NSView *)hitTest:(NSPoint)point { return nil; }

- (void)setFrame:(NSRect)frame {
    [super setFrame:self.superview ? DPGrainHostBounds(self.superview) : frame];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSArray<NSNotificationName> *windowNames = @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification,
                                                 NSWindowDidBecomeMainNotification, NSWindowDidResignMainNotification];
    NSArray<NSNotificationName> *appNames = @[NSApplicationDidBecomeActiveNotification, NSApplicationDidResignActiveNotification];
    for (NSNotificationName name in [windowNames arrayByAddingObjectsFromArray:appNames]) [center removeObserver:self name:name object:nil];
    if (!self.window || !self.tracksWindowActivity) return;
    for (NSNotificationName name in windowNames) [center addObserver:self selector:@selector(refreshActivity:) name:name object:self.window];
    for (NSNotificationName name in appNames) [center addObserver:self selector:@selector(refreshActivity:) name:name object:NSApp];
    [self refreshActivity:nil];
}

- (void)reloadSettings {
    _space = DPGrainSpaceOf(self.superview);
    [self setGrainAmount:DPGrainShown(_space) ? DPGrainAmount(_space) : 0 softness:DPGrainSoftness(_space) scale:DPGrainScale(_space)];
}

- (void)refreshActivity:(NSNotification *)notification { [self reloadSettings]; }

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self refreshActivity:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)_windowChangedKeyState {
    [super _windowChangedKeyState];
    [self refreshActivity:nil];
}

- (void)setGrainAmount:(double)amount softness:(double)softness scale:(double)scale {
    NSString *material = DPGrainMaterial(_space);
    if (![DPGrainMaterialKeys() containsObject:material]) material = @"sand";
    CGFloat soft = MAX(0, MIN(100, softness)) / 100, zoom = MAX(50, MIN(300, scale)) / 100;
    BOOL fine = [material isEqual:@"fine"];
    CGFloat opacity = MAX(0, MIN(100, amount)) / 100 * (fine ? 0.3 : 0.8 / sqrt(1 - 1.5 * soft * (1 - soft)));
    if (self.tracksWindowActivity && self.window && !self.window._hasActiveAppearance) opacity = 0;
    BOOL dark = DPGrainDarkAppearance(self.effectiveAppearance);
    if (_darkAppearance == dark && _grainOpacity == opacity && _softness == soft && _scale == zoom && [_material isEqual:material]) return;
    _darkAppearance = dark;
    _softness = soft;
    _scale = zoom;
    _grainOpacity = opacity;
    _material = material;
    self.layer.compositingFilter = fine ? nil :
        dark ? @"screenBlendMode" : @"multiplyBlendMode";
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    if (_grainOpacity == 0) return;
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(context);
    CGFloat radius = self.layer.cornerRadius;
    if (radius > 0) {
        CGPathRef clip = CGPathCreateWithRoundedRect(self.bounds, radius, radius, NULL);
        CGContextAddPath(context, clip);
        CGPathRelease(clip);
        CGContextClip(context);
    } else {
        CGContextClipToRect(context, self.bounds);
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    NSInteger percent = lround(_scale * 100);
    if ([_material isEqual:@"fine"]) {
        CGContextSetAlpha(context, _grainOpacity);
        CGFloat size = (120 + 24 * _softness) * _scale;
        CGContextDrawTiledImage(context, CGRectMake(0, 0, size, size), DPGrainAppearanceTile(_material, NO, NO, percent));
    } else {
        CGFloat size = (DPIsPatternGrainMaterial(_material) ? 100 : 128 + 32 * _softness) * _scale;
        CGRect tile = CGRectMake(0, 0, size, size);
        if (_softness < 1) {
            CGContextSetBlendMode(context, kCGBlendModeCopy);
            CGContextSetAlpha(context, _grainOpacity * (1 - _softness));
            CGContextDrawTiledImage(context, tile, DPGrainAppearanceTile(_material, NO, _darkAppearance, percent));
        }
        if (_softness > 0) {
            CGContextSetBlendMode(context, kCGBlendModePlusLighter);
            CGContextSetAlpha(context, _grainOpacity * _softness);
            CGContextDrawTiledImage(context, tile, DPGrainAppearanceTile(_material, YES, _darkAppearance, percent));
        }
    }
    CGContextRestoreGState(context);
}

@end
