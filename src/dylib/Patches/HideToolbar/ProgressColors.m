#import "HideToolbar.h"
#import <Metal/Metal.h>

static char DPDiaColorsKey;
static __weak id DPDrawing;
static NSData *DPLastDiaColors;

static NSArray<NSString *> *DPPresetNames(void) { return @[@"Blue", @"Purple", @"Pink", @"Orange", @"Green", @"Graphite", @"Jace"]; }

static NSColor *DPHex(uint32_t light, uint32_t dark) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL isDark = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;
        uint32_t hex = isDark ? dark : light;
        return [NSColor colorWithSRGBRed:(hex >> 16 & 0xff) / 255.0 green:(hex >> 8 & 0xff) / 255.0 blue:(hex & 0xff) / 255.0 alpha:1];
    }];
}

static NSArray<NSColor *> *DPPreset(NSString *name) {
    NSDictionary<NSString *, NSArray<NSColor *> *> *presets = @{
        @"Blue" : @[NSColor.systemBlueColor, NSColor.systemTealColor],
        @"Purple" : @[NSColor.systemPurpleColor, NSColor.systemIndigoColor],
        @"Pink" : @[NSColor.systemPinkColor, NSColor.systemPurpleColor],
        @"Orange" : @[NSColor.systemOrangeColor, NSColor.systemRedColor],
        @"Green" : @[NSColor.systemGreenColor, NSColor.systemMintColor],
        @"Graphite" : @[NSColor.systemGrayColor, NSColor.labelColor],
        @"Jace" : @[DPHex(0x73574a, 0x9a918a), DPHex(0x432818, 0xfef1df)],
    };
    return presets[name];
}

NSMenu *DPProgressColorChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Color"];
    [menu addItemWithTitle:@"Match Dia" action:nil keyEquivalent:@""].representedObject = @"dia";
    [menu addItemWithTitle:@"Accent Color" action:nil keyEquivalent:@""].representedObject = @"accent";
    [menu addItem:NSMenuItem.separatorItem];
    for (NSString *name in DPPresetNames()) [menu addItemWithTitle:name action:nil keyEquivalent:@""].representedObject = name.lowercaseString;
    return menu;
}

static simd_float3 DPRGB(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return (simd_float3){rgb.redComponent, rgb.greenComponent, rgb.blueComponent};
}

static NSData *DPDiaColorsIn(NSView *pane) {
    NSView *bar = DPSubview(pane, DPDiaToolbar);
    NSView *indicator = bar ? DPFindView(bar, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaLoadingIndicator); }) : nil;
    __block NSData *colors = DPGet(indicator, &DPDiaColorsKey);
    if (!colors && indicator) DPFindView(indicator, ^BOOL(NSView *view) { return (colors = DPGet(view, &DPDiaColorsKey)) != nil; });
    return colors ?: DPLastDiaColors;
}

void DPProgressColors(NSView *pane, NSString *choice, simd_float3 *primary, simd_float3 *secondary) {
    NSData *dia = [choice isEqual:@"dia"] ? DPDiaColorsIn(pane) : nil;
    if (dia.length == 2 * sizeof(simd_float3)) {
        *primary = ((const simd_float3 *)dia.bytes)[0];
        *secondary = ((const simd_float3 *)dia.bytes)[1];
        return;
    }
    NSArray<NSColor *> *preset = DPPreset(choice.capitalizedString);
    [pane.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSColor *accent = NSColor.controlAccentColor;
        *primary = DPRGB(preset ? preset[0] : accent);
        *secondary = DPRGB(preset ? preset[1] : [accent blendedColorWithFraction:0.5 ofColor:NSColor.systemPurpleColor]);
    }];
}

static void DPIndicator_drawInMTKView(id self, SEL _cmd, id view) {
    DPDrawing = self;
    DPCallOriginal(DPIndicator_drawInMTKView, self, view);
    DPDrawing = nil;
}

static void DPEncoder_setFragmentBytes(id self, SEL _cmd, const void *bytes, NSUInteger length, NSUInteger index) {
    DPCallOriginal(DPEncoder_setFragmentBytes, self, bytes, length, index);
    NSUInteger slots[2];
    id drawing = DPDrawing;
    if (!drawing || length < 3 * sizeof(float) || !DPProgressColorSlots(slots)) return;
    if (index != slots[0] && index != slots[1]) return;
    NSMutableData *colors = DPGet(drawing, &DPDiaColorsKey) ?: [NSMutableData dataWithLength:2 * sizeof(simd_float3)];
    memcpy((simd_float3 *)colors.mutableBytes + (index == slots[1]), bytes, 3 * sizeof(float));
    DPSet(drawing, &DPDiaColorsKey, colors);
    DPLastDiaColors = colors;
}

void DPInstallProgressColors(void) {
    DPHook(DPDiaLoadingIndicator, @selector(drawInMTKView:), (IMP)DPIndicator_drawInMTKView);
    // Encoders are the GPU driver's private class, found by making one.
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    MTLTextureDescriptor *target = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];
    target.usage = MTLTextureUsageRenderTarget;
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor new];
    pass.colorAttachments[0].texture = [device newTextureWithDescriptor:target];
    id<MTLCommandBuffer> commands = [[device newCommandQueue] commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
    if (encoder) DPHookClass(object_getClass(encoder), @selector(setFragmentBytes:length:atIndex:), (IMP)DPEncoder_setFragmentBytes);
    [encoder endEncoding];
}
