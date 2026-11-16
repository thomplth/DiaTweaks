#import "GrainView.h"
#import "TextureNoise.h"

NSArray<NSString *> *DPGrainMaterialKeys(void) {
    return @[@"grain", @"sand", @"tweed", @"denim", @"matte", @"fine"];
}

NSArray<NSString *> *DPGrainMaterialTitles(void) {
    return @[@"Grain", @"Sand", @"Tweed", @"Denim", @"Matte", @"Fine"];
}

BOOL DPIsPatternGrainMaterial(NSString *material) {
    return [@[@"grain", @"sand", @"tweed", @"denim"] containsObject:material];
}

static CGImageRef DPSoftenPatternTile(CGImageRef image) CF_RETURNS_RETAINED {
    NSInteger width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, width, height, 8, width * 4,
        space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return NULL;
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    DPBlurGrainPixels(data.mutableBytes, width, height, 4);
    DPFitGrainTone(data.mutableBytes, width * height);
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}

CGImageRef DPPatternGrainTile(NSString *material, BOOL soft) {
    if (!DPIsPatternGrainMaterial(material)) return NULL;
    static NSDictionary<NSString *, id> *tiles, *softened;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *sharp = [NSMutableDictionary new], *blurred = [NSMutableDictionary new];
        for (NSString *key in @[@"grain", @"sand", @"tweed", @"denim"]) {
            NSMutableData *data = [NSMutableData dataWithLength:200 * 200 * 4];
            DPFillTexturePattern(key, data.mutableBytes);
            CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
            CGImageRef cg = CGImageCreate(200, 200, 8, 32, 800, space,
                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big, provider, NULL, false, kCGRenderingIntentDefault);
            CGDataProviderRelease(provider);
            CGColorSpaceRelease(space);
            if (!cg) continue;
            sharp[key] = CFBridgingRelease(cg);
            CGImageRef smooth = DPSoftenPatternTile(cg);
            if (smooth) blurred[key] = CFBridgingRelease(smooth);
        }
        tiles = [sharp copy];
        softened = [blurred copy];
    });
    return (__bridge CGImageRef)(soft ? softened[material] : tiles[material]);
}
