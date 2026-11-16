#import "StdPatch/StdPatch.h"
#import "SafeMode/SafeMode.h"
#import "Settings/Settings.h"
#import "Updates/Updates.h"
#import "Test/Test.h"
#import "DevTools/DevTools.h"

__attribute__((constructor)) static void DPInit(void) {
    // Checking the process keeps a DIAPATCH_MANIFEST left in a shell from making Dia quit at launch.
    NSString *manifest = NSProcessInfo.processInfo.environment[@"DIAPATCH_MANIFEST"];
    if (manifest && [NSProcessInfo.processInfo.processName isEqualToString:@"diapatch"]) _exit(DPWriteManifest(manifest) ? 0 : 1);
    DPBeginLaunch();
    if (DPSafeMode == 2) return;
    DPLoadPatches();
    if (!DPSafeMode) DPInstallPatches();
    DPInstallSettings();
    DPInstallUpdates();
    DPInstallDevTools();

    NSString *report = NSProcessInfo.processInfo.environment[@"DIAPATCH_TEST"];
    unsetenv("DIAPATCH_TEST");  // A relaunched Dia would inherit it and test again.
    if (report) DPRunTests(report);
}
