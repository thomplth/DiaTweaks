#import <Foundation/Foundation.h>

static inline float DPTextureNoise(NSInteger x, NSInteger y, NSUInteger seed) {
    x = (x % 200 + 200) % 200;
    y = (y % 200 + 200) % 200;
    uint32_t n = (uint32_t)x * 0x1f123bb5u ^ (uint32_t)y * 0x5f356495u ^ (uint32_t)seed * 0x9e3779b9u;
    n ^= n >> 16; n *= 0x7feb352du; n ^= n >> 15; n *= 0x846ca68bu; n ^= n >> 16;
    return (n & 0xffffff) / 16777215.0f;
}

static inline float DPTextureNormal(NSInteger x, NSInteger y, NSUInteger seed) {
    float value = 0;
    for (NSUInteger i = 0; i < 6; i++) value += DPTextureNoise(x, y, seed + i * 31);
    return (value - 3) * M_SQRT2;
}

static inline float DPTextureCorrelated(NSInteger x, NSInteger y, NSUInteger seed) {
    const float weights[] = {.17, .83, .17};
    float value = 0;
    for (NSInteger dy = -1; dy <= 1; dy++) for (NSInteger dx = -1; dx <= 1; dx++)
        value += weights[dy+1] * weights[dx+1] * DPTextureNormal(x+dx, y+dy, seed);
    return value / .7467f;
}

void DPFillTexturePattern(NSString *material, uint8_t *pixels);
