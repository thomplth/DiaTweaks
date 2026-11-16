#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#include <libproc.h>

extern DPPatch DPICloudPasswords;

static NSString *const kAppleHost = @"/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json";

// Dia reads hosts from Chrome's folder, not its own.
static NSString *DPHostManifestPath(NSString *name) { return DPAppSupport([NSString stringWithFormat:@"Google/Chrome/NativeMessagingHosts/%@.json", name]); }

static NSDictionary *DPHostAt(NSString *path) {
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] ?: NSData.data options:0 error:nil];
    return [host isKindOfClass:NSDictionary.class] ? host : nil;
}

static NSError *gWriteError;

// Replace another app's manifest only if it points at a helper a patched Dia can't start, and keep it aside to restore.
static NSError *DPRegisterHost(NSString *name, NSString *description, NSArray<NSString *> *origins, BOOL on) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *path = DPHostManifestPath(name), *relay = DPAppSupport(@"DiaPatches/bin/diapatch");
    NSString *kept = DPAppSupport([NSString stringWithFormat:@"DiaPatches/%@.json", name]);
    NSDictionary *host = DPHostAt(path);
    NSError *error;
    if ([files fileExistsAtPath:path] && ![host[@"path"] isEqual:relay]) {
        BOOL replaceable = [host[@"path"] isEqual:DPHostAt(kAppleHost)[@"path"]] || [[host[@"path"] lastPathComponent] isEqual:@"OpenPasswordsHelper"];
        if (!on || !replaceable) return nil;
        [files removeItemAtPath:kept error:nil];
        if (![files moveItemAtPath:path toPath:kept error:&error]) return error;
    }
    if (!on) {
        [files removeItemAtPath:path error:nil];
        [files moveItemAtPath:kept toPath:path error:nil];
        return nil;
    }
    NSDictionary *manifest = @{ @"name" : name, @"description" : description, @"path" : relay, @"type" : @"stdio", @"allowed_origins" : origins };
    BOOL written = [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]
        && [[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path options:NSDataWritingAtomic error:&error];
    return written ? nil : error;
}

static void DPRegisterHosts(BOOL on) {
    on = on && DPCLITrusted();
    gWriteError = DPRegisterHost(@"com.apple.passwordmanager", @"DiaTweaks relay to iCloud Passwords",
                                 @[ @"chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/", @"chrome-extension://mfbcdcnpokpoajjciilocoachedjkima/" ], on);
    NSError *betterPasswords = DPRegisterHost(@"io.github.fanckush.betterpasswords.bridge", @"DiaTweaks relay for Better Passwords to iCloud Passwords",
                                              @[ @"chrome-extension://ocongmkplhijgajnipnhhggfcjfdilgj/" ], on);
    NSError *openPasswords = DPRegisterHost(@"com.openpasswords.icloud", @"DiaTweaks relay for Open Passwords to iCloud Passwords",
                                            @[ @"chrome-extension://iaojbcjndjmmblmoemilknlnjijokkfg/", @"chrome-extension://abpahgnajbkclfhpodhjhlmgfjhpibaa/" ], on);
    gWriteError = gWriteError ?: betterPasswords ?: openPasswords;
}

static NSString *DPICloudPasswordsProblem(DPPatch *patch) {
    NSString *apple = DPHostAt(kAppleHost)[@"path"];
    if (![apple isKindOfClass:NSString.class] || ![NSFileManager.defaultManager isExecutableFileAtPath:apple])
        return @"This Mac doesn’t have Apple’s iCloud Passwords helper, which comes with macOS 14 and later.";
    if (gWriteError) return DPWriteProblem(DPHostManifestPath(@"com.apple.passwordmanager"), gWriteError);
    return DPRelayProblem() ?: DPHostProblem(DPHostManifestPath(@"com.apple.passwordmanager"), @"com.apple.passwordmanager");
}

// The hand-off's original Dia outlives this one and blocks Dia's launch check, so this runs in install.
static void DPStopOriginalDia(void) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    NSString *pristine = DPAppSupport(@"DiaPatches/pristine/Dia.app/Contents/MacOS/Dia").stringByResolvingSymlinksInPath;
    int capacity = proc_listallpids(NULL, 0) + 64;
    pid_t pids[capacity];
    int count = proc_listallpids(pids, capacity * (int)sizeof *pids);
    for (int i = 0; i < count; i++) {
        if (proc_pidpath(pids[i], path, sizeof path) <= 0 || (strcmp(path, pristine.fileSystemRepresentation) && ![@(path) hasPrefix:@"/Applications/.DiaTweaks/"])) continue;
        kill(pids[i], SIGKILL);
        for (int tries = 0; tries < 50 && kill(pids[i], 0) == 0; tries++) usleep(20000);
    }
}

static void DPInstallICloudPasswords(void) {
    DPStopOriginalDia();
    DPRegisterHosts(DPICloudPasswords.on);
}

static void DPApplyICloudPasswords(DPPatch *patch) { DPRegisterHosts(patch->on); }

DP_PATCH(DPICloudPasswords) {
    .key = @"icloudPasswords",
    .order = 101,
    .defaultOn = YES,
    .title = @"Allow iCloud Passwords",
    .detail = @"AutoFill passwords from Apple Passwords with the iCloud Passwords, Better Passwords or Open Passwords extension. A patched Dia can’t start Apple’s helper, so each time one connects, the original Dia that DiaTweaks keeps opens briefly, without windows, to start it. Experimental.",
    .symbol = @"apple.passwords key.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Allow-iCloud-Passwords.md",
    .install = DPInstallICloudPasswords,
    .apply = DPApplyICloudPasswords,
    .ready = DPICloudPasswordsProblem,
};
