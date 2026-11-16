#import "StdPatch/StdPatch.h"

float DPZoomStep(float now, int direction) {
    static const float steps[] = {0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5};
    size_t count = sizeof steps / sizeof *steps;
    if (direction > 0) {
        for (size_t i = 0; i < count; i++) if (steps[i] > now + 0.001) return steps[i];
        return steps[count - 1];
    }
    if (direction < 0) {
        for (size_t i = count; i-- > 0;) if (steps[i] < now - 0.001) return steps[i];
        return steps[0];
    }
    return 1;
}
