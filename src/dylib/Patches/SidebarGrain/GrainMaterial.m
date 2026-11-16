#import "GrainView.h"

static CGImageRef DPGrainImage(NSData *data, size_t size) {
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image = CGImageCreate(size, size, 8, 32, size * 4, space,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast, provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return image;
}

static uint32_t DPGrainRandom(uint32_t *state) {
    *state ^= *state << 13; *state ^= *state >> 17; *state ^= *state << 5;
    return *state;
}

static float DPGrainNormal(uint32_t *state) {
    float value = 0;
    for (NSUInteger sample = 0; sample < 6; sample++) value += (DPGrainRandom(state) & 65535) / 65535.0f;
    return (value - 3) * M_SQRT2;
}

void DPBlurGrainPixels(uint8_t *pixels, NSInteger width, NSInteger height, NSUInteger passes) {
    const float weight[] = {.25, .5, .25};
    for (NSUInteger pass = 0; pass < passes; pass++) {
        NSData *source = [NSData dataWithBytes:pixels length:width * height * 4];
        const uint8_t *from = source.bytes;
        for (NSInteger y = 0; y < height; y++) for (NSInteger x = 0; x < width; x++)
            for (NSInteger c = 0; c < 4; c++) {
                float value = 0;
                for (NSInteger dy = -1; dy <= 1; dy++) for (NSInteger dx = -1; dx <= 1; dx++)
                    value += weight[dy+1] * weight[dx+1] * from[(((y+dy+height)%height)*width+(x+dx+width)%width)*4+c];
                pixels[(y*width+x)*4+c] = lroundf(value);
            }
    }
}

void DPFitGrainTone(uint8_t *pixels, NSUInteger count) {
    double mean[3] = {0}, sum = 0, square = 0;
    for (NSUInteger i = 0; i < count; i++) {
        double brightness = 0;
        for (NSUInteger c = 0; c < 3; c++) { mean[c] += pixels[i*4+c]; brightness += pixels[i*4+c]; }
        sum += brightness / 3; square += brightness * brightness / 9;
    }
    double spread = sqrt(MAX(0, square / count - pow(sum / count, 2)));
    double gain = spread > 0.01 ? DPGrainSpread * 255 / spread : 0;
    for (NSUInteger i = 0; i < count; i++) for (NSUInteger c = 0; c < 3; c++)
        pixels[i*4+c] = lround(fmax(0, fmin(255, DPGrainTone * 255 + (pixels[i*4+c] - mean[c] / count) * gain)));
}

CGImageRef DPFineGrainTile(void) {
    static CGImageRef image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        enum { size = 192 };
        NSMutableData *data = [NSMutableData dataWithLength:size * size * 4];
        uint8_t *pixels = data.mutableBytes;
        uint32_t random = 0x19643a8d;
        for (NSUInteger i = 0; i < size * size; i++) {
            DPGrainRandom(&random);
            int tone = (int)(random & 255) + (int)((random >> 8) & 255) - 255;
            uint8_t alpha = (uint8_t)abs(tone);
            pixels[4*i] = pixels[4*i+1] = pixels[4*i+2] = tone > 0 ? alpha : 0;
            pixels[4*i+3] = alpha;
        }
        image = DPGrainImage(data, size);
    });
    return image;
}

CGImageRef DPMatteGrainTile(BOOL soft) {
    static CGImageRef image, softened;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        enum { size = 256 };
        float *noise = calloc(size * size * 3, sizeof(float));
        uint32_t random = 0x643a8d19;
        for (NSUInteger i = 0; i < size * size; i++) {
            float shared = DPGrainNormal(&random);
            for (NSUInteger channel = 0; channel < 3; channel++) noise[i*3+channel] = .8f * shared + .6f * DPGrainNormal(&random);
        }
        NSMutableData *data = [NSMutableData dataWithLength:size * size * 4];
        uint8_t *pixels = data.mutableBytes;
        const float weight[] = {.2, .8, .2};
        for (NSInteger y = 0; y < size; y++) for (NSInteger x = 0; x < size; x++) {
            NSUInteger pixel = y * size + x;
            for (NSUInteger channel = 0; channel < 3; channel++) {
                float value = 0;
                for (NSInteger dy = -1; dy <= 1; dy++) for (NSInteger dx = -1; dx <= 1; dx++)
                    value += weight[dy+1] * weight[dx+1] * noise[(((y+dy+size)%size)*size+(x+dx+size)%size)*3+channel];
                float tone = fmaxf(0, fminf(1, DPGrainTone + DPGrainSpread * value / .72f));
                pixels[pixel*4+channel] = (uint8_t)lroundf(tone * 255);
            }
            pixels[pixel*4+3] = 255;
        }
        free(noise);
        DPFitGrainTone(pixels, size * size);
        image = DPGrainImage(data, size);
        NSMutableData *blurred = [data mutableCopy];
        DPBlurGrainPixels(blurred.mutableBytes, size, size, 1);
        DPFitGrainTone(blurred.mutableBytes, size * size);
        softened = DPGrainImage(blurred, size);
    });
    return soft ? softened : image;
}
