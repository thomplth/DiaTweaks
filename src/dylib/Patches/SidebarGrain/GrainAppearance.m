#import "GrainView.h"

BOOL DPGrainDarkAppearance(NSAppearance *appearance) {
    return [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
        isEqual:NSAppearanceNameDarkAqua];
}

static CGImageRef DPScaledGrainTile(CGImageRef image, NSInteger scale, BOOL fit, BOOL soft, BOOL dark) CF_RETURNS_RETAINED {
    size_t width = CGImageGetWidth(image) * scale / 100, height = CGImageGetHeight(image) * scale / 100;
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return NULL;
    CGContextSetInterpolationQuality(context, soft ? kCGInterpolationHigh : kCGInterpolationNone);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    uint8_t *pixels = data.mutableBytes;
    if (fit && scale != 100) DPFitGrainTone(pixels, width * height);
    if (dark) for (size_t i = 0; i < width * height; i++) for (NSUInteger c = 0; c < 3; c++) pixels[i*4+c] = 255 - pixels[i*4+c];
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}

CGImageRef DPGrainAppearanceTile(NSString *material, BOOL soft, BOOL dark, NSInteger scale) {
    BOOL fine = [material isEqual:@"fine"];
    CGImageRef image = fine ? DPFineGrainTile() : DPIsPatternGrainMaterial(material) ? DPPatternGrainTile(material, soft) : DPMatteGrainTile(soft);
    dark = dark && !fine;
    if (!image || (scale == 100 && !dark)) return image;
    static NSMutableDictionary<NSString *, id> *tiles;
    static NSInteger tilesScale;
    if (!tiles || tilesScale != scale) {
        tiles = [NSMutableDictionary new];
        tilesScale = scale;
    }
    NSString *key = [NSString stringWithFormat:@"%@-%d-%d", material, soft, dark];
    if (!tiles[key]) {
        CGImageRef tile = DPScaledGrainTile(image, scale, !fine, soft, dark);
        if (tile) tiles[key] = CFBridgingRelease(tile);
    }
    return (__bridge CGImageRef)tiles[key] ?: image;
}
