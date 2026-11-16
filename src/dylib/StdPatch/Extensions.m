#import "StdPatch/StdPatch.h"

static NSMutableArray<NSString *> *DPExtensionFolders, *DPLaunchFlags, *DPDroppedFeatures;

// Chromium keeps only the last of a flag, so a list flag given more than once becomes one listing every value.
static void DPMergeListFlag(NSMutableArray<NSString *> *args, NSString *flag) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSUInteger first = NSNotFound;
    for (NSUInteger i = args.count; i-- > 0;)
        if ([args[i] hasPrefix:flag]) {
            [values insertObject:[args[i] substringFromIndex:flag.length] atIndex:0];
            [args removeObjectAtIndex:(first = i)];
        }
    if (values.count) [args insertObject:[flag stringByAppendingString:[values componentsJoinedByString:@","]] atIndex:first];
}

// A relaunch Dia starts itself repeats the flags it ran with, so a feature a tweak is off for has to come out again.
static void DPDropFeatures(NSMutableArray<NSString *> *args) {
    static NSString *const flag = @"--enable-features=";
    for (NSUInteger i = args.count; i-- > 0;) {
        if (![args[i] hasPrefix:flag]) continue;
        NSMutableArray<NSString *> *kept = [[[args[i] substringFromIndex:flag.length] componentsSeparatedByString:@","] mutableCopy];
        [kept removeObjectsInArray:DPDroppedFeatures];
        if (kept.count) args[i] = [flag stringByAppendingString:[kept componentsJoinedByString:@","]];
        else [args removeObjectAtIndex:i];
    }
}

// Chromium keeps only the last --load-extension, so one flag lists every folder, Dia's own first.
static id DPConfiguration_init(id self, SEL _cmd, int argc, NSArray<NSString *> *argv, NSString *profilePath, NSUInteger applicationID,
                               BOOL isProduction, NSUInteger restorationPolicy, BOOL loadAllProfiles, BOOL quitRunLoop, NSString *suiteName) {
    static NSString *const flag = @"--load-extension=";
    NSMutableArray<NSString *> *args = [argv mutableCopy], *folders = [NSMutableArray array];
    for (NSString *arg in argv)
        if ([arg hasPrefix:flag]) {
            [folders addObject:[arg substringFromIndex:flag.length]];
            [args removeObject:arg];
        }
    [folders addObjectsFromArray:DPExtensionFolders];
    if (folders.count) [args addObject:[flag stringByAppendingString:[folders componentsJoinedByString:@","]]];
    [args addObjectsFromArray:DPLaunchFlags];
    DPDropFeatures(args);
    DPMergeListFlag(args, @"--enable-features=");
    DPMergeListFlag(args, @"--disable-features=");
    return DPCallOriginal(DPConfiguration_init, self, argc + ((int)args.count - (int)argv.count), args, profilePath, applicationID, isProduction,
                          restorationPolicy, loadAllProfiles, quitRunLoop, suiteName);
}

static void DPHookConfiguration(void) {
    if (DPExtensionFolders) return;
    DPExtensionFolders = [NSMutableArray array];
    DPLaunchFlags = [NSMutableArray array];
    DPDroppedFeatures = [NSMutableArray array];
    DPHook("ArcBrowserApplicationConfiguration", @selector(init:argv:profilePath:applicationID:isProduction:sessionRestorationPolicy:shouldLoadAllProfilesAtStartup:quitRunLoopOnTermination:userDefaultsSuiteName:),
           (IMP)DPConfiguration_init);
}

void DPLoadExtension(NSString *folder) {
    DPHookConfiguration();
    if (![DPExtensionFolders containsObject:folder]) [DPExtensionFolders addObject:folder];
}

void DPAddLaunchFlag(NSString *flag) {
    DPHookConfiguration();
    [DPLaunchFlags addObject:flag];
}

void DPDropLaunchFeature(NSString *feature) {
    DPHookConfiguration();
    if (![DPDroppedFeatures containsObject:feature]) [DPDroppedFeatures addObject:feature];
}
