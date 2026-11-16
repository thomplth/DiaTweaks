#import "HideToolbar.h"
#import <Metal/Metal.h>

static NSString *const DPShaderInputs[] = {@"progress", @"resolution", @"intensity", @"cycleProgress", @"primaryColor", @"secondaryColor"};
enum { DPInputCount = sizeof DPShaderInputs / sizeof *DPShaderInputs };
static id<MTLRenderPipelineState> DPPipeline;
static id<MTLCommandQueue> DPQueue;
static NSUInteger DPSlots[DPInputCount];

static BOOL DPLoadShader(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        NSURL *bundle = [NSBundle.mainBundle URLForResource:@"BoostBrowser_NavigationBar" withExtension:@"bundle"];
        NSURL *url = [[NSBundle bundleWithURL:bundle] URLForResource:@"default" withExtension:@"metallib"];
        id<MTLLibrary> library = url ? [device newLibraryWithURL:url error:nil] : nil;
        MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
        descriptor.vertexFunction = [library newFunctionWithName:@"loadingIndicatorVertex"];
        descriptor.fragmentFunction = [library newFunctionWithName:@"loadingIndicatorFragment"];
        if (!descriptor.vertexFunction || !descriptor.fragmentFunction) return;
        MTLRenderPipelineColorAttachmentDescriptor *color = descriptor.colorAttachments[0];
        color.pixelFormat = MTLPixelFormatBGRA8Unorm;
        color.blendingEnabled = YES;
        color.sourceRGBBlendFactor = color.sourceAlphaBlendFactor = MTLBlendFactorOne;
        color.destinationRGBBlendFactor = color.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        MTLRenderPipelineReflection *reflection;
        id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor options:MTLPipelineOptionBindingInfo
                                                                                reflection:&reflection error:nil];
        NSUInteger found = 0;
        for (NSUInteger i = 0; i < DPInputCount; i++)
            for (id<MTLBinding> binding in reflection.fragmentBindings)
                if ([binding.name isEqual:DPShaderInputs[i]]) DPSlots[i] = binding.index, found++;
        if (!pipeline || found != DPInputCount) return;
        DPPipeline = pipeline;
        DPQueue = [device newCommandQueue];
    });
    return DPPipeline != nil;
}

CAMetalLayer *DPProgressShaderLayer(void) {
    if (!DPLoadShader()) return nil;
    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.device = DPPipeline.device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.opaque = NO;
    layer.framebufferOnly = YES;
    return layer;
}

BOOL DPProgressColorSlots(NSUInteger slots[2]) {
    if (!DPLoadShader()) return NO;
    slots[0] = DPSlots[4];
    slots[1] = DPSlots[5];
    return YES;
}

void DPDrawProgressShader(CAMetalLayer *layer, CGFloat progress, CGFloat cycle, simd_float3 primary, simd_float3 secondary) {
    if (layer.drawableSize.width < 1 || layer.drawableSize.height < 1) return;
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable) return;
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor new];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    float values[] = {progress, 1, cycle};
    simd_float2 resolution = {layer.drawableSize.width, layer.drawableSize.height};
    simd_float3 colors[] = {primary, secondary};
    id<MTLCommandBuffer> commands = [DPQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:DPPipeline];
    [encoder setFragmentBytes:&values[0] length:sizeof(float) atIndex:DPSlots[0]];
    [encoder setFragmentBytes:&resolution length:sizeof resolution atIndex:DPSlots[1]];
    [encoder setFragmentBytes:&values[1] length:sizeof(float) atIndex:DPSlots[2]];
    [encoder setFragmentBytes:&values[2] length:sizeof(float) atIndex:DPSlots[3]];
    [encoder setFragmentBytes:&colors[0] length:sizeof(simd_float3) atIndex:DPSlots[4]];
    [encoder setFragmentBytes:&colors[1] length:sizeof(simd_float3) atIndex:DPSlots[5]];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [encoder endEncoding];
    [commands presentDrawable:drawable];
    [commands commit];
}
