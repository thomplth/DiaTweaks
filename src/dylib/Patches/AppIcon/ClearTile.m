#import "AppIcon.h"

static NSData *DPErodedShape(const uint8_t *pixels, size_t size, size_t radius) {
    NSMutableData *across = [NSMutableData dataWithLength:size * size], *eroded = [NSMutableData dataWithLength:size * size];
    uint8_t *a = across.mutableBytes, *e = eroded.mutableBytes;
    for (size_t y = 0; y < size; y++) for (size_t x = 0; x < size; x++) {
        uint8_t lowest = 255;
        for (size_t i = x < radius ? 0 : x - radius; i <= MIN(x + radius, size - 1); i++) lowest = MIN(lowest, pixels[(y * size + i) * 4 + 3]);
        a[y * size + x] = (x < radius || x + radius >= size) ? 0 : lowest;
    }
    for (size_t y = 0; y < size; y++) for (size_t x = 0; x < size; x++) {
        uint8_t lowest = 255;
        for (size_t i = y < radius ? 0 : y - radius; i <= MIN(y + radius, size - 1); i++) lowest = MIN(lowest, a[i * size + x]);
        e[y * size + x] = (y < radius || y + radius >= size) ? 0 : lowest;
    }
    return eroded;
}

// Opacities and gains are measured against real clear Dock tiles.
NSImage *DPClearTile(NSImage *icon, BOOL dark) {
    NSRect rect = NSMakeRect(0, 0, 512, 512);
    CGImageRef source = [icon CGImageForProposedRect:&rect context:nil hints:nil];
    if (!source) return icon;
    size_t size = 512;
    NSMutableData *data = [NSMutableData dataWithLength:size * size * 4];
    uint8_t *pixels = data.mutableBytes;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, size, size, 8, size * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, size, size), source);
    const uint8_t *body = pixels + (size_t)(size * 0.14) * size * 4 + size / 2 * 4;
    double level = body[3] ? (double)body[0] / body[3] : 0.5, gain = dark ? 0.565 : 0.943;
    NSData *shapes = DPErodedShape(pixels, size, 6);
    const uint8_t *eroded = shapes.bytes;
    for (size_t y = 0; y < size; y++) for (size_t x = 0; x < size; x++) {
        uint8_t *pixel = pixels + (y * size + x) * 4;
        double shape = pixel[3] / 255.0, value = shape > 0 ? pixel[0] / 255.0 / shape : 0;
        if (shape > 0 && eroded[y * size + x] < 128) {
            pixel[0] = pixel[1] = pixel[2] = 0;
            pixel[3] = (uint8_t)(0.85 * shape * 255);
            continue;
        }
        double sheen = 0.15 * MAX(0, 0.45 - (double)y / size) / 0.45;
        double opacity = 0.20 + sheen + gain * (value - level) / MAX(1 - level, 0.01);
        pixel[0] = pixel[1] = pixel[2] = pixel[3] = (uint8_t)(MIN(MAX(opacity, 0), 1) * shape * 255);
    }
    CGImageRef result = CGBitmapContextCreateImage(context);
    NSImage *clear = [[NSImage alloc] initWithCGImage:result size:NSMakeSize(512, 512)];
    CGImageRelease(result);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return clear;
}
