#import "HideVerticalTabGlow.h"

static char DPColorsKey;

static CAGradientLayer *DPBorderIn(NSView *shape) {
    void **slot = DPIvar(shape, "$__lazy_storage_$_gradientBorderLayer");
    id layer = slot ? (__bridge id)*slot : nil;
    return [layer isKindOfClass:CAGradientLayer.class] ? layer : nil;
}

static NSArray *DPUniformColors(NSArray *colors) {
    if (!colors.count) return colors;
    NSArray *sorted = [colors sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        CGFloat x = CGColorGetAlpha((__bridge CGColorRef)a), y = CGColorGetAlpha((__bridge CGColorRef)b);
        return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableArray *flat = [NSMutableArray new];
    for (NSUInteger i = 0; i < colors.count; i++) [flat addObject:sorted[colors.count / 2]];
    return flat;
}

static id DPColorsOf(CAGradientLayer *border) { return border.colors ?: NSNull.null; }

static void DPSetColors(CAGradientLayer *border, id colors) {
    if (![DPColorsOf(border) isEqual:colors]) border.colors = colors == NSNull.null ? nil : colors;
}

static void DPRestoreTabBorder(NSView *shape) {
    CAGradientLayer *border = DPBorderIn(shape);
    if (!DPGet(border, &DPColorsKey)) return;
    id dia = DPDiaValue(border, &DPColorsKey, DPColorsOf(border));
    DPSet(border, &DPColorsKey, nil);
    DPSetColors(border, dia);
}

void DPStyleUniformTabBorder(NSView *shape) {
    CAGradientLayer *border = DPBorderIn(shape);
    if (!border) return;
    if (!DPHideVerticalTabGlow.on || !DPIsVerticalTab(shape)) return DPRestoreTabBorder(shape);
    id dia = DPDiaValue(border, &DPColorsKey, DPColorsOf(border));
    id ours = dia == NSNull.null ? dia : DPUniformColors(dia);
    DPOverride(border, &DPColorsKey, dia, ours);
    DPSetColors(border, ours);
}

NSString *DPVerifyUniformTabBorder(NSView *shape, BOOL on) {
    CAGradientLayer *border = DPBorderIn(shape);
    id saved = DPGet(border, &DPColorsKey);
    if (on && border && !saved) return @"a tab's border isn't flattened";
    if (on && border.colors.count && ![border.colors isEqual:DPUniformColors(border.colors)]) return @"a tab's border still fades";
    return !on && saved ? @"a tab border wasn't restored" : nil;
}
