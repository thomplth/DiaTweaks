#import "TextureNoise.h"
#import "GrainView.h"

static float DPSandCell(NSInteger x, NSInteger y) {
    NSInteger gx = x / 4, gy = y / 4;
    float first = FLT_MAX, second = FLT_MAX, tone = 0;
    for (NSInteger dy = -2; dy <= 2; dy++) for (NSInteger dx = -2; dx <= 2; dx++) {
        NSInteger cx = gx + dx, cy = gy + dy;
        NSInteger wrappedX = (cx + 50) % 50, wrappedY = (cy + 50) % 50;
        float density = DPTextureNoise(wrappedX, wrappedY, 71);
        NSInteger count = density < .26 ? 0 : density < .75 ? 1 : 2;
        for (NSInteger point = 0; point < count; point++) {
            float px = (cx + DPTextureNoise(wrappedX, wrappedY, 83 + point * 31)) * 4;
            float py = (cy + DPTextureNoise(wrappedX, wrappedY, 97 + point * 31)) * 4;
            float distance = hypotf(x + .5 - px, y + .5 - py);
            if (distance < first) {
                second = first; first = distance;
                tone = DPTextureNoise(wrappedX, wrappedY, 149 + point * 31);
            } else if (distance < second) second = distance;
        }
    }
    float edge = fminf(1, (second - first) / 1.2f);
    edge = edge * edge * (3 - 2 * edge);
    return .2 + .5 * edge + .4 * tone + .035 * DPTextureNormal(x, y, 127);
}

void DPFillTexturePattern(NSString *material, uint8_t *pixels) {
    if ([material isEqual:@"grain"]) {
        for (NSInteger y = 0; y < 200; y++) for (NSInteger x = 0; x < 200; x++) {
            float shared = DPTextureCorrelated(x, y, 173);
            for (NSUInteger c = 0; c < 3; c++) {
                float tone = DPGrainTone + DPGrainSpread * (.8f * shared + .6f * DPTextureCorrelated(x, y, 484 + c * 311));
                pixels[(y*200+x)*4+c] = lroundf(fmaxf(0, fminf(1, tone)) * 255);
            }
            pixels[(y*200+x)*4+3] = 255;
        }
        DPFitGrainTone(pixels, 40000);
        return;
    }
    BOOL sand = [material isEqual:@"sand"], denim = [material isEqual:@"denim"];
    float *field = calloc(200*200, sizeof(float));
    double sum = 0, square = 0;
    for (NSInteger y = 0; y < 200; y++) for (NSInteger x = 0; x < 200; x++) {
        float value;
        if (sand) value = DPSandCell(x, y);
        else if (denim) {
            float twill = cosf((x-y) * M_PI_2);
            float threads = sinf((x+y) * M_PI_4) * cosf((x-y) * M_PI_2);
            value = twill + .18 * threads + .32 * DPTextureNormal(x, y, 281);
        } else {
            float fibers = DPTextureNormal(x, y/2, 331) + DPTextureNormal(x/2, y, 367);
            value = .6 * DPTextureCorrelated(x, y, 419) + .28 * fibers +
                .12 * cosf(x * M_PI_2) * sinf(y * M_PI_2);
        }
        field[y*200+x] = value; sum += value; square += value*value;
    }
    double mean = sum/40000, deviation = sqrt(MAX(0, square/40000 - mean*mean));
    for (NSUInteger i = 0; i < 40000; i++) {
        double tone = DPGrainTone + (field[i]-mean) * DPGrainSpread / MAX(deviation, .001);
        uint8_t value = lround(fmax(0, fmin(1, tone)) * 255);
        pixels[i*4] = pixels[i*4+1] = pixels[i*4+2] = value;
        pixels[i*4+3] = 255;
    }
    free(field);
}
