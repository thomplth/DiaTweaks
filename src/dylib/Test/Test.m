#import "Test/Test.h"
#import "SafeMode/SafeMode.h"

static const NSTimeInterval DPSettleSeconds = 1;

static void DPWriteReport(NSArray<NSDictionary *> *results, NSString *path) {
    DPTesting = NO;
    NSMutableArray<NSString *> *unavailable = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPPatchCount; i++) if (DPPatches[i]->unavailable) [unavailable addObject:DPPatches[i]->key];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSDictionary *report = @{
        @"dia": [NSString stringWithFormat:@"%@ (%@)", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]],
        @"layout": DPTabLayout(),
        @"safeMode": @(DPSafeMode),
        @"unavailable": unavailable,
        @"scenarios": results,
    };
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil]
        writeToFile:path atomically:YES];
}

static void DPRunScenario(NSArray<NSArray<NSString *> *> *scenarios, NSUInteger index, NSMutableArray<NSDictionary *> *results, NSString *path) {
    if (index == scenarios.count) return DPWriteReport(results, path);
    NSString *bits = scenarios[index][1];
    for (NSUInteger i = 0; i < DPPatchCount; i++) DPSetPatch(DPPatches[i], [bits characterAtIndex:i] == '1', NO);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DPSettleSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSMutableDictionary<NSString *, id> *states = [NSMutableDictionary new], *failures = [NSMutableDictionary new];
        for (NSUInteger i = 0; i < DPPatchCount; i++) {
            DPPatch *patch = DPPatches[i];
            states[patch->key] = @(patch->on);
            NSString *problem = patch->verify && !patch->unavailable ? patch->verify(patch) : nil;
            if (!problem && patch->on && patch->ready) problem = patch->ready(patch);
            if (!problem && !patch->on && !patch->unavailable && [bits characterAtIndex:i] == '1') problem = @"couldn't turn on";
            if (problem) failures[patch->key] = problem;
        }
        [results addObject:@{@"name": scenarios[index][0], @"states": states, @"failures": failures}];
        DPRunScenario(scenarios, index + 1, results, path);
    });
}

void DPRunTests(NSString *path) {
    DPTesting = YES;
    DPOnLaunch(^{
        __block int polls = 0;
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            if (!DPFindViews(DPDiaContentPane).count && ++polls < 120) return;
            [timer invalidate];
            if (DPSafeMode) return DPWriteReport(@[], path);
            NSMutableArray<NSArray<NSString *> *> *scenarios = DPScenarios();
            int8_t saved[DPPatchCount];
            for (NSUInteger i = 0; i < DPPatchCount; i++) saved[i] = DPSavedOn(DPPatches[i]);
            // First, before any scenario switches anything, so a patch that nothing applies at launch fails here.
            [scenarios insertObject:@[@"at launch", DPBits(saved)] atIndex:0];
            [scenarios addObject:@[@"saved settings", DPBits(saved)]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                DPRunScenario(scenarios, 0, [NSMutableArray new], path);
            });
        }];
    });
}
