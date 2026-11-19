#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <libproc.h>
#import <mach-o/getsect.h>
#import <mach-o/ldsyms.h>

// Patching costs Dia the entitlement Apple Passwords requires of browsers, so an extension hands each passkey request to
// diapatch, which runs it in the unpatched Dia.

extern DPPatch DPPasskeys;

static NSString *DPExtensionFolder(void) { return DPAppSupport(@"DiaPatches/passkeys-extension"); }

// Dia's Chromium reads native messaging hosts from Chrome's folder.
static NSString *DPHostManifestPath(void) { return DPAppSupport(@"Google/Chrome/NativeMessagingHosts/com.diapatches.passkeys.json"); }

static NSString *const kFiles[] = { @"manifest.json", @"page.js", @"bridge.js", @"worker.js" };

// SubjectPublicKeyInfo for a 2048-bit RSA key, ahead of its 270-byte PKCS#1 body.
static const uint8_t kRSA2048SPKIHeader[] = { 0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
                                              0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00 };

static NSData *DPNewExtensionKey(void) {
    NSDictionary *attributes = @{ (id)kSecAttrKeyType : (id)kSecAttrKeyTypeRSA, (id)kSecAttrKeySizeInBits : @2048 };
    SecKeyRef private = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, NULL);
    SecKeyRef public = private ? SecKeyCopyPublicKey(private) : NULL;
    NSData *pkcs1 = public ? CFBridgingRelease(SecKeyCopyExternalRepresentation(public, NULL)) : nil;
    if (public) CFRelease(public);
    if (private) CFRelease(private);
    if (pkcs1.length != 270) return nil;
    NSMutableData *spki = [NSMutableData dataWithBytes:kRSA2048SPKIHeader length:sizeof kRSA2048SPKIHeader];
    [spki appendData:pkcs1];
    return spki;
}

// Chromium names an unpacked extension after the key in its manifest. A key published with the code would let any
// extension that copies it reach the host that signs in with passkeys, so each Mac makes its own and keeps it.
static NSData *DPExtensionKey(void) {
    NSString *path = DPAppSupport(@"DiaPatches/passkeys-extension.key");
    NSString *saved = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSData *key = saved ? [[NSData alloc] initWithBase64EncodedString:saved options:0] : nil;
    if (key.length) return key;
    key = DPNewExtensionKey();
    if (!key || ![[key base64EncodedStringWithOptions:0] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) return nil;
    chmod(path.fileSystemRepresentation, 0600);
    return key;
}

static NSString *DPExtensionID(NSData *key) {
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(key.bytes, (CC_LONG)key.length, digest);
    NSMutableString *id = [NSMutableString string];
    for (int i = 0; i < 16; i++) [id appendFormat:@"%c%c", 'a' + (digest[i] >> 4), 'a' + (digest[i] & 0xf)];
    return id;
}

static NSData *DPExtensionFile(NSString *name) {
    NSString *section = [@"__pk_" stringByAppendingString:name.stringByDeletingPathExtension];
    unsigned long size = 0;
    uint8_t *bytes = getsectiondata(&_mh_dylib_header, "__TEXT", section.UTF8String, &size);
    return bytes ? [NSData dataWithBytes:bytes length:size] : nil;
}

static NSError *gWriteError;

static BOOL DPWrite(NSData *data, NSString *path) {
    NSError *error;
    if ([NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]
        && [data writeToFile:path options:NSDataWritingAtomic error:&error])
        return YES;
    gWriteError = error;
    return NO;
}

// Chromium skips registering an extension's service worker while its prefs record a registration for the manifest's
// version, even after that registration is gone from the profile, and then every page's chrome.runtime.connect drops
// unanswered. A version new to each launch makes it register the worker again.
static NSString *DPLaunchVersion(void) {
    static NSString *version;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        unsigned long long seconds = (unsigned long long)NSDate.date.timeIntervalSince1970;
        version = [NSString stringWithFormat:@"1.%llu.%llu.%llu", (seconds >> 32) & 0xffff, (seconds >> 16) & 0xffff, seconds & 0xffff];
    });
    return version;
}

static BOOL DPSetUpPasskeys(void) {
    gWriteError = nil;
    NSData *key = DPExtensionKey();
    if (!DPCLITrusted() || !key) return NO;
    NSMutableDictionary *manifest = [NSJSONSerialization JSONObjectWithData:DPExtensionFile(kFiles[0]) ?: NSData.data options:NSJSONReadingMutableContainers error:nil];
    if (![manifest isKindOfClass:NSMutableDictionary.class]) return NO;
    manifest[@"key"] = [key base64EncodedStringWithOptions:0];
    manifest[@"version"] = DPLaunchVersion();
    if (!DPWrite([NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil], [DPExtensionFolder() stringByAppendingPathComponent:kFiles[0]])) return NO;
    for (int i = 1; i < 4; i++) {
        NSData *file = DPExtensionFile(kFiles[i]);
        if (!file || !DPWrite(file, [DPExtensionFolder() stringByAppendingPathComponent:kFiles[i]])) return NO;
    }
    NSDictionary *host = @{
        @"name" : @"com.diapatches.passkeys",
        @"description" : @"DiaTweaks passkeys",
        @"path" : DPAppSupport(@"DiaPatches/bin/diapatch"),
        @"type" : @"stdio",
        @"allowed_origins" : @[ [NSString stringWithFormat:@"chrome-extension://%@/", DPExtensionID(key)] ],
    };
    return DPWrite([NSJSONSerialization dataWithJSONObject:host options:NSJSONWritingPrettyPrinted error:nil], DPHostManifestPath());
}

static NSString *DPPasskeysProblem(DPPatch *patch) {
    if (!DPCLITrusted()) return [NSString stringWithFormat:@"%@ isn’t the diapatch this build shipped with.", DPAppSupport(@"DiaPatches/bin/diapatch")];
    if (gWriteError) return DPWriteProblem(DPExtensionFolder(), gWriteError);
    for (int i = 0; i < 4; i++) {
        NSString *file = [DPExtensionFolder() stringByAppendingPathComponent:kFiles[i]];
        if (![NSFileManager.defaultManager fileExistsAtPath:file]) return [NSString stringWithFormat:@"%@ is missing.", file];
    }
    return DPRelayProblem() ?: DPHostProblem(DPHostManifestPath(), @"com.diapatches.passkeys");
}

static BOOL gExtensionLoaded;

// Any app can post these notifications, so only the copy of Dia diapatch starts for passkeys gets brought forward.
static BOOL DPIsPasskeyHelper(pid_t pid) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (pid <= 0 || proc_pidpath(pid, path, sizeof path) <= 0) return NO;
    NSString *helper = DPAppSupport(@"DiaPatches/pristine/Dia.app/Contents/MacOS/Dia").stringByResolvingSymlinksInPath;
    return [@(path) isEqualToString:helper];
}

static void DPShowHelper(NSNotification *note) {
    if (![note.object isKindOfClass:NSString.class] || !DPIsPasskeyHelper([note.object intValue])) return;
    NSRunningApplication *helper = [NSRunningApplication runningApplicationWithProcessIdentifier:[note.object intValue]];
    void (^show)(void) = ^{ [helper activateFromApplication:NSRunningApplication.currentApplication options:NSApplicationActivateAllWindows]; };
    if (![note.name hasSuffix:@"signIn"]) return show();
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Sign in to Dia once for passkeys";
    alert.informativeText = @"Passkeys open in a second copy of Dia, which needs you to sign in with your Dia email once. Your passkey carries on after.";
    NSUInteger browser = [NSApp.orderedWindows indexOfObjectPassingTest:^BOOL(NSWindow *window, NSUInteger i, BOOL *stop) { return window.visible && window.canBecomeMainWindow; }];
    if (browser == NSNotFound) return (void)([alert runModal], show());
    [alert beginSheetModalForWindow:NSApp.orderedWindows[browser] completionHandler:^(NSModalResponse _) { show(); }];
}

static void DPInstallPasskeys(void) {
    if (!DPPasskeys.on) {
        [NSFileManager.defaultManager removeItemAtPath:DPExtensionFolder() error:nil];
        [NSFileManager.defaultManager removeItemAtPath:DPHostManifestPath() error:nil];
        return;
    }
    if (!DPSetUpPasskeys()) return (void)NSLog(@"DiaPatches: couldn't set up passkeys");
    DPLoadExtension(DPExtensionFolder());
    gExtensionLoaded = YES;
    for (NSString *name in @[ @"com.diapatches.passkeys.show", @"com.diapatches.passkeys.signIn" ])
        [NSDistributedNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { DPShowHelper(note); }];
}

static void DPApplyPasskeys(DPPatch *patch) {
    if (patch->on) DPSetUpPasskeys();
    if (patch->on == gExtensionLoaded || patch->on != DPSavedOn(patch) || (patch->on && DPPasskeysProblem(patch))) return;  // The self-test flips patches without saving.
    NSAlert *alert = [NSAlert new];
    alert.messageText = patch->on ? @"Relaunch Dia to allow iCloud passkeys" : @"Relaunch Dia to stop using iCloud passkeys";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

DP_PATCH(DPPasskeys) {
    .key = @"passkeys",
    .order = 100,
    .defaultOn = YES,
    .title = @"Allow iCloud Passkeys",
    .detail = @"Sign in to sites with passkeys saved in Apple Passwords. A patched Dia can’t reach them, so the original Dia that DiaTweaks keeps opens behind the Touch ID prompt, then quits. Experimental.",
    .symbol = @"person.badge.key.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .install = DPInstallPasskeys,
    .apply = DPApplyPasskeys,
    .ready = DPPasskeysProblem,
};
