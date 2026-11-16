#import "StdPatch/StdPatch.h"

extern DPPatch DPBitwarden;

static NSString *const kHost = @"com.8bit.bitwarden";
static NSString *const kExtension = @"chrome-extension://nngceckbapebfimnlniiiahkandclblb/";

// Tells our file from Bitwarden's, which it rewrites whenever it starts and Chrome's folder exists.
static NSString *const kDescription = @"DiaTweaks link to the Bitwarden app";

// Dia reads hosts from Chrome's folder, not its own.
static NSString *DPHostManifestPath(void) { return DPAppSupport(@"Google/Chrome/NativeMessagingHosts/com.8bit.bitwarden.json"); }

static NSDictionary *DPHostAt(NSString *path) {
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] ?: NSData.data options:0 error:nil];
    return [host isKindOfClass:NSDictionary.class] ? host : nil;
}

static NSString *DPProxyPath(void) {
    NSString *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.bitwarden.desktop"].path;
    NSString *proxy = [app stringByAppendingPathComponent:@"Contents/MacOS/desktop_proxy"];
    return app && [NSFileManager.defaultManager isExecutableFileAtPath:proxy] ? proxy : nil;
}

static NSError *gWriteError;

// Only our own file, told apart by its description, is added over nothing or taken away: Bitwarden's stays.
static void DPRegisterHost(BOOL on) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *path = DPHostManifestPath(), *proxy = DPProxyPath();
    BOOL exists = [files fileExistsAtPath:path], ours = [DPHostAt(path)[@"description"] isEqual:kDescription];
    gWriteError = nil;
    if (!on) {
        if (ours) [files removeItemAtPath:path error:nil];
        return;
    }
    if (!proxy || (exists && !ours)) return;
    NSDictionary *manifest = @{ @"name" : kHost, @"description" : kDescription, @"path" : proxy, @"type" : @"stdio", @"allowed_origins" : @[ kExtension ] };
    NSError *error;
    BOOL written = [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]
        && [[NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path options:NSDataWritingAtomic error:&error];
    gWriteError = written ? nil : error;
}

static NSString *DPBitwardenProblem(DPPatch *patch) {
    NSString *path = DPHostManifestPath();
    if (!DPProxyPath()) return DPTesting ? nil : @"The Bitwarden desktop app isn’t installed. Install it, then try again.";
    if (gWriteError) return DPWriteProblem(path, gWriteError);
    NSDictionary *host = DPHostAt(path);
    if (![host[@"name"] isEqual:kHost]) return [NSString stringWithFormat:@"%@ isn’t a valid host file.", path];
    if (![host[@"path"] isKindOfClass:NSString.class] || ![NSFileManager.defaultManager isExecutableFileAtPath:host[@"path"]])
        return [NSString stringWithFormat:@"Bitwarden’s %@ points to %@, which isn’t there. Quit and reopen Bitwarden, then try again.", path, host[@"path"]];
    return nil;
}

static void DPInstallBitwarden(void) { DPRegisterHost(DPBitwarden.on); }

static void DPApplyBitwarden(DPPatch *patch) { DPRegisterHost(patch->on); }

DP_PATCH(DPBitwarden) {
    .key = @"bitwarden",
    .order = 103,
    .title = @"Allow Bitwarden",
    .detail = @"Unlock the Bitwarden extension with the Bitwarden app, such as with Touch ID. Bitwarden only sets this up for browsers it knows, so this adds the file Dia reads when it’s missing, and takes away only that file. Experimental.",
    .symbol = @"shield.lefthalf.filled",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .install = DPInstallBitwarden,
    .apply = DPApplyBitwarden,
    .ready = DPBitwardenProblem,
};
