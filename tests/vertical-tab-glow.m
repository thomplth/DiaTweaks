#define DPFindViews DPRealFindViews
#import "StdPatch/Views.m"
#undef DPFindViews
#import "StdPatch/Hook.m"

static NSArray<NSView *> *visibleShapes;
NSArray<NSView *> *DPFindViews(const char *name) { return visibleShapes; }

#import "Patches/HideVerticalTabGlow/HideVerticalTabGlow.m"
#import "Patches/HideVerticalTabGlow/Decorations.m"
#import "Patches/HideVerticalTabGlow/FlatMaterial.m"
#import "Patches/HideVerticalTabGlow/Scope.m"
#import "Patches/HideVerticalTabGlow/UniformBorder.m"

static const char *const Names[] = {"$__lazy_storage_$_shadowLayer", "$__lazy_storage_$_gradientBorderLayer", "rimHighlightView", NULL};
static Class shapeClass;
static int failures;

static void Check(BOOL yes, NSString *message) {
    if (yes) return;
    failures++;
    printf("FAIL %s\n", message.UTF8String);
}
static void Toggle(BOOL on) { DPHideVerticalTabGlow.on = on; DPHideVerticalTabGlow.apply(&DPHideVerticalTabGlow); }
static id Color(CGFloat white, CGFloat alpha) { return (__bridge id)[NSColor colorWithWhite:white alpha:alpha].CGColor; }
static id Part(NSView *shape, NSUInteger index) { return (__bridge id)*(void **)DPIvar(shape, Names[index]); }
static void SetPart(NSView *shape, NSUInteger index, id part) {
    objc_setAssociatedObject(shape, Names[index], part, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    *(void **)DPIvar(shape, Names[index]) = (__bridge void *)part;
}
static void FixtureLayout(NSView *shape, SEL sel) {
    if (!Part(shape, 0)) SetPart(shape, 0, [CALayer layer]);
    if (!Part(shape, 1)) SetPart(shape, 1, [CAGradientLayer layer]);
    if (!Part(shape, 2)) SetPart(shape, 2, [NSView new]);
}
static NSView *NewShape(CGFloat width) {
    NSView *shape = [[shapeClass alloc] initWithFrame:NSMakeRect(0, 0, width, 34)];
    FixtureLayout(shape, @selector(layout));
    return shape;
}

static void TestScopes(NSView *shape, NSView *sidebar, Class stripClass, NSArray *palette) {
    NSView *strip = [[stripClass alloc] initWithFrame:NSMakeRect(0, 0, 800, 34)];
    NSView *horizontal = NewShape(160);
    CAGradientLayer *border = Part(horizontal, 1);
    border.colors = palette;
    [strip addSubview:horizontal];
    visibleShapes = @[shape, horizontal];
    Toggle(YES);
    Check([Part(shape, 0) isHidden] && ![Part(horizontal, 0) isHidden], @"only the vertical tab loses its shadow");
    Check(![Part(horizontal, 2) isHidden] && [border.colors isEqual:palette], @"horizontal rim and fading border are unchanged");
    Check(!DPHideVerticalTabGlow.verify(&DPHideVerticalTabGlow), @"mixed layouts verify independently");

    Class glassClass = NSClassFromString(@"NSGlassEffectView");
    if (glassClass) {
        NSView *glass = [[glassClass alloc] initWithFrame:NSMakeRect(0, 0, 160, 34)];
        [horizontal addSubview:glass];
        Check(!glass.hidden && !DPHasTabOverride(glass), @"late horizontal glass stays native");
        [shape addSubview:glass];
        Check(glass.hidden, @"glass moved into a vertical tab is suppressed");
        [horizontal addSubview:glass];
        Check(!glass.hidden && !DPHasTabOverride(glass), @"glass moved out of a vertical tab is restored");
    }

    [sidebar addSubview:strip];
    Check(!DPIsVerticalTab(horizontal), @"horizontal root wins over any enclosing sidebar");
    [strip addSubview:shape];
    [shape layout];
    CAGradientLayer *moved = Part(shape, 1);
    Check(![Part(shape, 0) isHidden] && ![Part(shape, 2) isHidden], @"vertical-to-horizontal move restores shadow and rim");
    Check([moved.colors isEqual:palette], @"vertical-to-horizontal move restores native border colors");
    [sidebar addSubview:shape];
    [shape layout];
    Check([Part(shape, 0) isHidden] && [moved.colors isEqual:DPUniformColors(palette)], @"horizontal-to-vertical move applies styling again");

    NSView *outside = NewShape(160);
    CAGradientLayer *outsideBorder = Part(outside, 1);
    outsideBorder.colors = palette;
    visibleShapes = @[shape, horizontal, outside];
    Toggle(YES);
    Check(![Part(outside, 0) isHidden] && [outsideBorder.colors isEqual:palette], @"tabs outside a sidebar are left untouched");
    Toggle(NO);
}

int main(void) {
    @autoreleasepool {
        Class sidebarClass = objc_allocateClassPair(NSView.class, DPVerticalSidebarRoot, 0);
        Class stripClass = objc_allocateClassPair(NSView.class, DPDiaTabStrip, 0);
        objc_registerClassPair(sidebarClass);
        objc_registerClassPair(stripClass);
        NSView *sidebar = [[sidebarClass alloc] initWithFrame:NSMakeRect(0, 0, 311, 600)];
        shapeClass = objc_allocateClassPair(NSView.class, DPDiaTabShape, 0);
        for (const char *const *name = Names; *name; name++) class_addIvar(shapeClass, *name, sizeof(void *), 3, "@");
        class_addMethod(shapeClass, @selector(layout), (IMP)FixtureLayout, "v@:");
        objc_registerClassPair(shapeClass);
        NSView *shape = NewShape(311);
        [sidebar addSubview:shape];
        visibleShapes = @[shape];
        DPHideVerticalTabGlow.install();

        CALayer *shadow = Part(shape, 0);
        CAGradientLayer *border = Part(shape, 1);
        NSView *rim = Part(shape, 2);
        NSArray *palette = @[Color(1, .3), Color(1, .15), Color(1, .15), Color(1, 0), Color(1, .15), Color(1, .15), Color(1, .3)];
        NSArray *locations = @[@0, @.1, @.2, @.5, @.8, @.9, @1];
        CALayer *mask = [CALayer layer];
        border.colors = palette;
        border.locations = locations;
        border.mask = mask;
        Toggle(YES);
        Check(shadow.hidden && rim.hidden && !border.hidden, @"glow and rim hidden while the border remains");
        Check(border.colors.count == palette.count && [border.colors.firstObject isEqual:palette[1]], @"border uses Dia's middle opacity");
        Check([border.colors isEqual:DPUniformColors(border.colors)], @"all stops have the same color");
        Check(border.mask == mask && [border.locations isEqual:locations], @"border geometry is untouched");
        Check(!DPHideVerticalTabGlow.verify(&DPHideVerticalTabGlow), @"enabled verification");

        shadow.hidden = NO;
        rim.hidden = NO;
        [shape layout];
        Check(shadow.hidden && rim.hidden, @"decorations Dia shows again are hidden at the next layout");
        NSArray *dark = @[Color(0, .1), Color(0, .2), Color(0, .3)];
        border.colors = dark;
        [shape layout];
        Check([border.colors.firstObject isEqual:dark[1]] && [border.colors isEqual:DPUniformColors(border.colors)], @"new appearance colors stay uniform");
        Toggle(NO);
        Check(!shadow.hidden && !rim.hidden && [border.colors isEqual:dark], @"off restores the latest native state");
        Check(!DPHideVerticalTabGlow.verify(&DPHideVerticalTabGlow), @"disabled verification");
        shadow.hidden = YES;
        rim.hidden = YES;
        Toggle(YES);
        Toggle(NO);
        Check(shadow.hidden && rim.hidden, @"pre-hidden decorations remain hidden");
        shadow.hidden = NO;
        rim.hidden = NO;

        NSView *late = NewShape(311);
        [sidebar addSubview:late];
        visibleShapes = @[late];
        Toggle(YES);
        [late layout];
        Check([Part(late, 0) isHidden] && [Part(late, 2) isHidden], @"lazy decorations are hidden after the original layout");
        DPHideVerticalTabGlow.on = NO;
        [late layout];
        Check(![Part(late, 0) isHidden] && ![Part(late, 2) isHidden], @"a detached tab is restored at its next layout");

        visibleShapes = @[shape];
        Class glassClass = NSClassFromString(@"NSGlassEffectView");
        if (glassClass) {
            NSView *glass = [[glassClass alloc] initWithFrame:NSMakeRect(0, 0, 311, 34)];
            NSView *otherGlass = [[glassClass alloc] initWithFrame:NSMakeRect(0, 0, 311, 34)];
            [shape addSubview:glass];
            Toggle(YES);
            Check(glass.hidden && !otherGlass.hidden, @"only tab glass is hidden");
            NSView *lateGlass = [[glassClass alloc] initWithFrame:NSMakeRect(0, 0, 311, 34)];
            [shape addSubview:lateGlass];
            Check(lateGlass.hidden, @"glass added to a tab is hidden at once");
            Toggle(NO);
            Check(!glass.hidden && !lateGlass.hidden && !otherGlass.hidden, @"off restores tab glass and leaves other glass alone");
        }

        CAGradientLayer *otherBorder = [CAGradientLayer layer];
        otherBorder.colors = palette;
        border.colors = palette;
        for (int i = 0; i < 100; i++) Toggle(YES), Toggle(NO);
        Check([border.colors isEqual:palette] && [otherBorder.colors isEqual:palette], @"100 toggles restore colors");
        Check(![DPGet(border, &DPColorsKey) isKindOfClass:NSArray.class] && !DPHasTabOverride(shadow), @"no overrides left behind");

        TestScopes(shape, sidebar, stripClass, palette);
        DPHideVerticalTabGlow.on = YES;
        Check(DPHideVerticalTabGlow.verify(&DPHideVerticalTabGlow) != nil, @"verification catches missing enforcement");
        DPHideVerticalTabGlow.on = NO;
    }
    if (failures) return 1;
    puts("vertical tab glow: all checks passed");
    return 0;
}
