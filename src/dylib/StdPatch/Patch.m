#import "StdPatch/StdPatch.h"
#import "StdPatch/Hide.h"
#import "SafeMode/SafeMode.h"
#include <mach-o/getsect.h>
#include <notify.h>

extern const struct mach_header_64 __dso_handle;

static const CFTimeInterval DPAnimationDuration = 0.25;

DPPatch *const *DPPatches;
NSUInteger DPPatchCount;
static NSUserDefaults *DPDefaults;

NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";

DPPatch *DPPatchNamed(NSString *key) {
    for (NSUInteger i = 0; key && i < DPPatchCount; i++) if ([DPPatches[i]->key isEqualToString:key]) return DPPatches[i];
    return NULL;
}

DPPatch *DPRequired(DPPatch *patch) {
    return DPPatchNamed(patch->requires);
}

static void DPAnimate(void) {
    static NSTimer *timer;
    static CFTimeInterval start;
    static CGFloat *from;
    from = from ?: calloc(DPPatchCount, sizeof *from);
    start = CACurrentMediaTime();
    for (NSUInteger i = 0; i < DPPatchCount; i++) from[i] = DPPatches[i]->progress;
    if (timer) return;
    timer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *t) {
        CGFloat elapsed = CACurrentMediaTime() - start, omega = 22;
        BOOL done = elapsed >= DPAnimationDuration * 2;
        CGFloat eased = done ? 1 : 1 - (1 + omega * elapsed) * exp(-omega * elapsed);
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->progress = from[i] + (DPPatches[i]->on - from[i]) * eased;
        for (NSUInteger i = 0; i < DPPatchCount; i++) if (DPPatches[i]->relayout) DPPatches[i]->relayout();
        if (done) {
            [t invalidate];
            timer = nil;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}

BOOL DPTesting;

static void DPEnsureReady(DPPatch *patch) {
    NSString *problem = patch->ready(patch);
    for (int tries = 1; problem && tries < 3; tries++) {
        if (patch->apply) patch->apply(patch);
        problem = patch->ready(patch);
    }
    if (!problem || DPTesting) return;
    NSLog(@"DiaPatches: %@ couldn't turn on: %@", patch->title, problem);
    patch->on = NO;
    [DPDefaults setBool:NO forKey:patch->key];
    if (patch->apply) patch->apply(patch);
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        NSAlert *alert = [NSAlert new];
        alert.messageText = [NSString stringWithFormat:@"Couldn’t turn on %@", patch->title];
        alert.informativeText = problem;
        [alert runModal];
    });
}

void DPSetPatch(DPPatch *patch, BOOL on, BOOL save) {
    if (patch->on == on) return;
    patch->on = on;
    if (save) [DPDefaults setBool:on forKey:patch->key];
    if (DPSafeMode) return;
    if (patch->apply) patch->apply(patch);
    else DPAnimate();
    if (on && patch->ready) DPEnsureReady(patch);
}

NSString *DPAppSupport(NSString *path) {
    return [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:path];
}

NSString *DPRelayProblem(void) {
    for (NSString *path in @[ @"DiaPatches/bin/diapatch", @"DiaPatches/pristine/Dia.app/Contents/MacOS/Dia" ])
        if (![NSFileManager.defaultManager isExecutableFileAtPath:DPAppSupport(path)])
            return [NSString stringWithFormat:@"%@ is missing. Install DiaTweaks again to put it back.", DPAppSupport(path)];
    return nil;
}

// The folder to take back is the one just below the nearest folder above that the user can open and write, which can be several levels up.
static NSString *DPFolderToRepair(NSString *folder) {
    NSString *support = DPAppSupport(@""), *repair = nil;
    for (NSString *dir = folder; [dir hasPrefix:support]; dir = dir.stringByDeletingLastPathComponent) {
        if (access(dir.fileSystemRepresentation, W_OK | X_OK) == 0) return repair && [NSFileManager.defaultManager fileExistsAtPath:repair] ? repair : nil;
        repair = dir;
    }
    return nil;
}

NSString *DPWriteProblem(NSString *path, NSError *error) {
    path = error.userInfo[NSFilePathErrorKey] ?: path;
    NSString *problem = [NSString stringWithFormat:@"Couldn’t write %@: %@", path, error.localizedDescription];
    NSString *folder = error.code == NSFileWriteNoPermissionError ? DPFolderToRepair(path.stringByDeletingLastPathComponent) : nil;
    if (!folder) return problem;
    if ([folder hasPrefix:NSHomeDirectory()]) folder = [@"$HOME" stringByAppendingString:[folder substringFromIndex:NSHomeDirectory().length]];
    return [problem stringByAppendingFormat:@" To fix it, run sudo chown -R \"$(whoami)\" \"%@\" && chmod -R u+rwX \"%@\" in Terminal, then turn this on again.", folder, folder];
}

NSString *DPHostProblem(NSString *manifest, NSString *name) {
    NSData *data = [NSData dataWithContentsOfFile:manifest];
    if (!data) return [NSString stringWithFormat:@"%@ couldn’t be written.", manifest];
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![host isKindOfClass:NSDictionary.class] || ![host[@"name"] isEqual:name]) return [NSString stringWithFormat:@"%@ isn’t a valid host file.", manifest];
    if (![host[@"path"] isEqual:DPAppSupport(@"DiaPatches/bin/diapatch")])
        return [NSString stringWithFormat:@"Another app has replaced %@, so its extension goes to %@ instead.", manifest, host[@"path"]];
    return nil;
}

BOOL DPSavedOn(DPPatch *patch) {
    id value = [DPDefaults objectForKey:patch->key];
    return !patch->unavailable && (value ? [value boolValue] : patch->defaultOn);
}

NSString *DPChoice(DPPatch *patch) {
    id value = [DPDefaults objectForKey:patch->choice];
    return [value isKindOfClass:NSString.class] ? value : patch->defaultChoice;
}

void DPSetChoice(DPPatch *patch, NSString *value) {
    [DPDefaults setObject:value forKey:patch->choice];
    if (!DPSafeMode && patch->on && patch->apply) patch->apply(patch);
}

static int DPCompareOrder(const void *a, const void *b) {
    return (*(DPPatch *const *)a)->order - (*(DPPatch *const *)b)->order;
}

static void DPReadPatches(void) {
    unsigned long size = 0;
    DPPatch **entries = (DPPatch **)getsectiondata(&__dso_handle, "__DATA", "__dppatches", &size);
    DPPatch **sorted = malloc(size);
    memcpy(sorted, entries, size);
    DPPatchCount = size / sizeof *sorted;
    qsort(sorted, DPPatchCount, sizeof *sorted, DPCompareOrder);
    DPPatches = sorted;
    NSMutableArray<NSString *> *sections = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = sorted[i];
        NSString *section = patch->section ?: DPRequired(patch)->section ?: @"Other";
        if (![sections containsObject:section]) [sections addObject:section];
        patch->order = (int)([sections indexOfObject:section] << 24 | [patch->title hasPrefix:@"Hide "] << 16 | patch->title.length << 8 | i);
    }
    qsort(sorted, DPPatchCount, sizeof *sorted, DPCompareOrder);
}

void DPLoadPatches(void) {
    DPDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    DPReadPatches();

    for (NSUInteger i = 0; i < DPPatchCount; i++)
        for (const char *const *name = DPPatches[i]->classes; name && *name; name++) DPPatches[i]->unavailable |= !objc_getClass(*name);
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i];
        for (DPPatch *required = DPRequired(patch); required; required = DPRequired(required)) patch->unavailable |= required->unavailable;
        patch->on = DPSavedOn(patch);
        patch->progress = patch->on;
        if (!patch->hides) continue;
        patch->apply = patch->apply ?: DPApplyHides;
        patch->verify = patch->verify ?: DPVerifyHides;
    }
}

static void DPApplySavedSettings(void) {
    CFPreferencesAppSynchronize(CFSTR("com.diapatches"));
    for (NSUInteger i = 0; i < DPPatchCount; i++) DPSetPatch(DPPatches[i], DPSavedOn(DPPatches[i]), NO);
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

// Hooks install in Settings order (section, non-"Hide" first, then title length): a later hook runs first, and the sidebar drag tweaks rely on it.
void DPInstallPatches(void) {
    for (NSUInteger i = 0; i < DPPatchCount; i++) if (!DPPatches[i]->unavailable && DPPatches[i]->install) DPPatches[i]->install();
    DPOnLaunch(^{
        for (NSUInteger i = 0; i < DPPatchCount; i++) if (DPPatches[i]->on && DPPatches[i]->ready) DPEnsureReady(DPPatches[i]);
    });
    DPInstallHides();
    int token;
    notify_register_dispatch("com.diapatches.changed", &token, dispatch_get_main_queue(), ^(int _) { DPApplySavedSettings(); });
}

BOOL DPWriteManifest(NSString *path) {
    DPReadPatches();
    NSMutableArray<NSDictionary *> *patches = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i], *required = DPRequired(patch), *disabler = DPPatchNamed(patch->disabledBy);
        NSMutableDictionary *entry = [@{
            @"key": patch->key,
            @"title": patch->title,
            @"detail": patch->detail,
            @"defaultOn": @(patch->defaultOn),
            @"requires": required ? required->key : NSNull.null,
            @"disabledBy": disabler ? disabler->key : NSNull.null,
            @"section": patch->section ?: NSNull.null,
            @"tint": patch->tint ?: NSNull.null,
            @"symbol": patch->symbol ?: NSNull.null,
        } mutableCopy];
        if (patch->page) entry[@"page"] = patch->page;
        [patches addObject:entry];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"patches": patches}
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    return [json writeToFile:path atomically:YES];
}
