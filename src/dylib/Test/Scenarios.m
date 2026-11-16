#import "Test/Test.h"

static NSUInteger DPIndex(DPPatch *patch) {
    for (NSUInteger i = 0; i < DPPatchCount; i++) if (DPPatches[i] == patch) return i;
    abort();
}

static BOOL DPNeeds(DPPatch *patch, DPPatch *other) {
    for (DPPatch *required = DPRequired(patch); required; required = DPRequired(required)) if (required == other) return YES;
    return NO;
}

static void DPTurnOn(int8_t *state, DPPatch *patch) {
    for (; patch; patch = DPRequired(patch)) state[DPIndex(patch)] = 1;
}

NSString *DPBits(const int8_t *state) {
    NSMutableString *bits = [NSMutableString string];
    for (NSUInteger i = 0; i < DPPatchCount; i++) [bits appendString:state[i] == 1 ? @"1" : @"0"];
    return bits;
}

static NSUInteger DPPair(NSUInteger i, BOOL a, NSUInteger j, BOOL b) { return ((i * DPPatchCount + j) * 2 + a) * 2 + b; }

static int DPGain(const int8_t *state, const BOOL *uncovered, NSUInteger k, BOOL on) {
    int gain = 0;
    for (NSUInteger m = 0; m < DPPatchCount; m++)
        if (m != k && state[m] >= 0) gain += m < k ? uncovered[DPPair(m, state[m], k, on)] : uncovered[DPPair(k, on, m, state[m])];
    return gain;
}

NSMutableArray<NSArray<NSString *> *> *DPScenarios(void) {
    NSUInteger n = DPPatchCount;
    NSMutableArray<NSArray<NSString *> *> *scenarios = [NSMutableArray new];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    BOOL (^add)(NSString *, const int8_t *) = ^BOOL(NSString *name, const int8_t *state) {
        NSString *bits = DPBits(state);
        if ([seen containsObject:bits]) return NO;
        [seen addObject:bits];
        [scenarios addObject:@[name, bits]];
        return YES;
    };
    int8_t state[n];
    memset(state, 0, n);
    add(@"all off", state);
    for (NSUInteger i = 0; i < n; i++) state[i] = !DPPatches[i]->unavailable;
    add(@"all on", state);
    for (NSUInteger i = 0; i < n; i++) {
        if (DPPatches[i]->unavailable) continue;
        memset(state, 0, n);
        DPTurnOn(state, DPPatches[i]);
        add([DPPatches[i]->key stringByAppendingString:@" alone"], state);
    }

    BOOL uncovered[n * n * 4];
    memset(uncovered, 0, sizeof uncovered);
    for (NSUInteger i = 0; i < n; i++)
        for (NSUInteger j = i + 1; j < n; j++)
            for (int a = 0; a < 2; a++)
                for (int b = 0; b < 2; b++)
                    uncovered[DPPair(i, a, j, b)] = !DPPatches[i]->unavailable && !DPPatches[j]->unavailable
                        && !(a && !b && DPNeeds(DPPatches[i], DPPatches[j])) && !(b && !a && DPNeeds(DPPatches[j], DPPatches[i]));
    NSUInteger pairwise = 0;
    for (NSUInteger pair = 0; pair < n * n * 4; pair++) {
        if (!uncovered[pair]) continue;
        NSUInteger i = pair / 4 / n, j = pair / 4 % n;
        memset(state, -1, n);
        state[i] = pair / 2 % 2;
        state[j] = pair % 2;
        if (state[i]) DPTurnOn(state, DPPatches[i]);
        if (state[j]) DPTurnOn(state, DPPatches[j]);
        for (NSUInteger k = 0; k < n; k++) {
            if (state[k] >= 0) continue;
            DPPatch *required = DPRequired(DPPatches[k]);
            BOOL canTurnOn = !DPPatches[k]->unavailable && (!required || state[DPIndex(required)] == 1);
            state[k] = canTurnOn && DPGain(state, uncovered, k, YES) >= DPGain(state, uncovered, k, NO);
        }
        for (NSUInteger p = 0; p < n; p++)
            for (NSUInteger q = p + 1; q < n; q++) uncovered[DPPair(p, state[p], q, state[q])] = NO;
        if (add([NSString stringWithFormat:@"pairwise %lu", (unsigned long)pairwise + 1], state)) pairwise++;
    }
    return scenarios;
}
