// Keeps a patched copy of the user's own Dia in place across updates. The official app stays untouched in
// <support>/pristine; re-signing drops entitlements tied to The Browser Company's profile, or AMFI refuses to launch.

#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "Passkeys.h"
#import "Passwords.h"
#include <libproc.h>
#include <mach-o/getsect.h>
#include <mach-o/ldsyms.h>
#include <mach-o/loader.h>
#include <sys/clonefile.h>
#include <sys/file.h>
#include <sys/stat.h>

#define DYLIB "DiaPatches.dylib"
static NSString *const kFeedOrigin = @"https://releases.diabrowser.com/";
static NSString *const kFeed = @"https://releases.diabrowser.com/BoostBrowser-updates.xml";
static NSString *const kSparkle = @"http://www.andymatuschak.org/xml-namespaces/sparkle";
static NSString *const kLocalIdentity = @"DiaPatches Local Signing";
static NSString *const kTeam = @"S6N382Y83G";
static NSString *const kReleases = @"https://api.github.com/repos/thomplth/DiaTweaks/releases/latest";
static NSString *const kReleaseAsset = @"DiaTweaks.zip";
static NSString *const kReleaseSignature = @"DiaTweaks.zip.sig";
static NSString *const kReleaseSigner = @"diatweaks-release";
static NSString *const kAgent = @"com.diapatches.update";
static NSString *const kPrefsDomain = @"com.diapatches";
static NSString *const kDiaReleaseNotes = @"https://www.diabrowser.com/release-notes/latest";

static NSString *gHome, *gApp, *gCache, *gPristine, *gStaged, *gReady;
static const char *gCommand;
static FILE *gLog;

#pragma mark - Output

static BOOL emit(FILE *out, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static BOOL emit(FILE *out, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (gLog) {
        char stamp[20];
        time_t now = time(NULL);
        strftime(stamp, sizeof stamp, "%F %T", localtime(&now));
        fprintf(gLog, "%s %s[%d] %s%s\n", stamp, gCommand, getpid(), out == stderr ? "error: " : "", line.UTF8String);
    }
    if (out) fprintf(out, "%s%s\n", out == stderr ? "diapatch: " : "", line.UTF8String);
    return out != stderr;
}

#define note(...) emit(NULL, __VA_ARGS__)   // log only
#define say(...) emit(stdout, __VA_ARGS__)  // returns YES
#define fail(...) emit(stderr, __VA_ARGS__) // returns NO

#pragma mark - Files and tools

static NSString *env(const char *name) {
    const char *value = getenv(name);
    return value && *value ? @(value) : nil;
}

static NSString *inHome(NSString *name) { return [gHome stringByAppendingPathComponent:name]; }

static BOOL exists(NSString *path) { return [NSFileManager.defaultManager fileExistsAtPath:path]; }

static BOOL makeDir(NSString *path) {
    NSError *error;
    return [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]
        || fail(@"cannot create %@: %@", path, error.localizedDescription);
}

static BOOL removeTree(NSString *path) {
    NSError *error;
    return [NSFileManager.defaultManager removeItemAtPath:path error:&error] || error.code == NSFileNoSuchFileError
        || fail(@"cannot remove %@: %@", path, error.localizedDescription);
}

// A delete that's cut short leaves part of a bundle; renamed into .trash first, it can't pass for a whole one.
static BOOL discard(NSString *path) {
    NSString *trash = inHome(@".trash");
    if (!removeTree(trash)) return NO;
    if (rename(path.fileSystemRepresentation, trash.fileSystemRepresentation) == 0) return removeTree(trash);
    if (errno == ENOENT) return YES;
    // Only update's download can be on another volume, and only update reads it.
    return errno == EXDEV ? removeTree(path) : fail(@"cannot remove %@: %s", path, strerror(errno));
}

static int runWithInput(NSArray<NSString *> *argv, NSString *input, NSString **output) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:argv[0]];
    task.arguments = [argv subarrayWithRange:NSMakeRange(1, argv.count - 1)];
    if (input) {
        task.standardInput = [NSFileHandle fileHandleForReadingAtPath:input];
        if (!task.standardInput) return -1;
    }
    NSPipe *pipe = NSPipe.pipe;
    task.standardOutput = task.standardError = pipe;
    if (![task launchAndReturnError:NULL]) return -1;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (output) *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return task.terminationStatus;
}

static int run(NSArray<NSString *> *argv, NSString **output) { return runWithInput(argv, nil, output); }

static BOOL check(NSArray<NSString *> *argv) {
    NSString *output;
    int status = run(argv, &output);
    return status == 0
        || fail(@"%@ failed (%d): %@", argv[0].lastPathComponent, status,
                [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
}

// Dia's feed server turns away some HTTP clients but accepts curl.
static int fetch(NSString *url, int seconds, NSString *file, NSString **output) {
    NSArray *argv = @[ @"/usr/bin/curl", @"-fsSL", @"--proto", @"=https,file", @"--proto-redir", @"=https", @"--max-time",
                       @(seconds).stringValue, url ];
    return run(file ? [argv arrayByAddingObjectsFromArray:@[ @"-o", file ]] : argv, output);
}

// Extended attributes (Finder info, resource forks) aren't part of the signature, but `codesign --strict`
// rejects them, and copies of Dia made by Finder or some installers carry them.
static BOOL clone(NSString *from, NSString *to) {
    BOOL copied = clonefile(from.fileSystemRepresentation, to.fileSystemRepresentation, 0) == 0
        || ((errno == EXDEV || errno == ENOTSUP) ? check(@[ @"/usr/bin/ditto", from, to ]) : fail(@"cannot clone %@: %s", from, strerror(errno)));
    return copied && check(@[ @"/usr/bin/xattr", @"-cr", to ]);
}

static int place(NSString *from, NSString *to) {
    const char *source = from.fileSystemRepresentation, *target = to.fileSystemRepresentation;
    return (exists(to) ? renamex_np(source, target, RENAME_SWAP) : rename(source, target)) == 0 ? 0 : errno;
}

// Atomic rename, copying onto the destination volume first if needed.
static BOOL moveBundle(NSString *from, NSString *to) {
    NSString *incoming = [to stringByAppendingString:@".incoming"];
    int error = place(from, to);
    if (error == EXDEV) error = removeTree(incoming) && check(@[ @"/usr/bin/ditto", from, incoming ]) ? place(incoming, to) : -1;
    if (error) {
        removeTree(incoming);
        if (error > 0)
            fail(@"cannot move %@ to %@: %s%@", from, to, strerror(error),
                 error == EPERM ? @" (see System Settings > Privacy & Security > App Management)" : @"");
        return NO;
    }
    return removeTree(incoming) && discard(from);
}

#pragma mark - Apps

static NSDictionary *infoOf(NSString *app) {
    return [NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:[app stringByAppendingPathComponent:@"Contents/Info.plist"]]
                                               error:NULL];
}

static NSString *buildOf(NSString *app) { return infoOf(app)[@"CFBundleVersion"]; }

static NSString *versionOf(NSString *app) {
    NSDictionary *info = infoOf(app);
    return info ? [NSString stringWithFormat:@"%@ (%@)", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]] : nil;
}

static BOOL isPatched(NSString *app) { return [infoOf(app)[@"DiaPatches"] boolValue]; }

// What the signature claims, without verifying it; verifyOfficial does that.
static BOOL claimsOfficial(NSString *app) {
    NSString *details;
    return run(@[ @"/usr/bin/codesign", @"-dv", app ], &details) == 0 && [details containsString:[NSString stringWithFormat:@"\nTeamIdentifier=%@\n", kTeam]];
}

static BOOL verifyOfficial(NSString *app) {
    note(@"verifying %@", app);
    return ([infoOf(app)[@"CFBundleIdentifier"] isEqual:@"company.thebrowser.dia"] || fail(@"%@ is not Dia", app))
        && check(@[ @"/usr/bin/codesign", @"--verify", @"--deep", @"--strict", @"-R",
                    [NSString stringWithFormat:@"=anchor apple generic and certificate leaf[subject.OU] = \"%@\"", kTeam], app ])
        && check(@[ @"/usr/sbin/spctl", @"--assess", @"--type", @"execute", app ]);
}

static BOOL appRunning(void) {
    char root[PATH_MAX], path[PROC_PIDPATHINFO_MAXSIZE];
    if (!realpath(gApp.fileSystemRepresentation, root)) return NO;
    strlcat(root, "/", sizeof root);
    int capacity = proc_listallpids(NULL, 0) + 64;
    pid_t pids[capacity];
    int count = proc_listallpids(pids, capacity * (int)sizeof *pids);
    for (int i = 0; i < count; i++)
        if (proc_pidpath(pids[i], path, sizeof path) > 0 && strncmp(path, root, strlen(root)) == 0) return YES;
    return NO;
}

static void waitForQuit(pid_t pid) {
    note(@"waiting for %@ to quit", gApp);
    for (int i = 0; i < 240 && ((pid > 0 && kill(pid, 0) == 0) || appRunning()); i++) usleep(250000);
}

#pragma mark - Building

// Weak load command in the padding after the load commands. The dylib lives outside the bundle so updating
// it doesn't change the app's signature, and with it Dia's keychain access.
static BOOL addLoadCommand(NSString *path, NSString *dylib) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedAlways error:NULL];
    const uint8_t *bytes = data.bytes;
    const struct mach_header_64 *header = data.bytes;
    if (data.length < sizeof *header || header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64)
        return fail(@"%@ is not a thin arm64 executable", path);
    uint64_t end = sizeof *header + header->sizeofcmds, firstSection = data.length;
    for (uint64_t offset = sizeof *header, i = 0; i < header->ncmds; i++, offset += ((const struct load_command *)(bytes + offset))->cmdsize) {
        const struct segment_command_64 *segment = (const void *)(bytes + offset);
        if (end > data.length || offset + sizeof(struct load_command) > end || segment->cmdsize < sizeof(struct load_command)
            || offset + segment->cmdsize > end
            || (segment->cmd == LC_SEGMENT_64 && sizeof *segment + segment->nsects * sizeof(struct section_64) > segment->cmdsize))
            return fail(@"%@ has malformed load commands", path);
        if (segment->cmd != LC_SEGMENT_64 || strncmp(segment->segname, SEG_TEXT, sizeof segment->segname)) continue;
        const struct section_64 *sections = (const void *)(segment + 1);
        for (uint32_t s = 0; s < segment->nsects; s++)
            if (sections[s].size) firstSection = MIN(firstSection, sections[s].offset);
    }
    const char *name = dylib.fileSystemRepresentation;
    uint32_t size = (uint32_t)(sizeof(struct dylib_command) + strlen(name) + 8) & ~7u;
    NSMutableData *command = [NSMutableData dataWithLength:size];
    *(struct dylib_command *)command.mutableBytes = (struct dylib_command){
        .cmd = LC_LOAD_WEAK_DYLIB, .cmdsize = size,
        .dylib = { .name.offset = sizeof(struct dylib_command), .timestamp = 2, .current_version = 0x10000,
                   .compatibility_version = 0x10000 },
    };
    strcpy((char *)command.mutableBytes + sizeof(struct dylib_command), name);
    BOOL room = end + size <= firstSection;
    for (uint64_t i = end; room && i < end + size; i++) room = !bytes[i];
    if (!room) return fail(@"%@ has no room for another load command", path);
    uint32_t counts[2] = { header->ncmds + 1, header->sizeofcmds + size };
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CLOEXEC);
    BOOL written = fd >= 0 && pwrite(fd, command.bytes, size, (off_t)end) == size
        && pwrite(fd, counts, sizeof counts, offsetof(struct mach_header_64, ncmds)) == sizeof counts;
    if (fd >= 0 && close(fd) != 0) written = NO;
    return written || fail(@"cannot write %@: %s", path, strerror(errno));
}

static BOOL configureInfo(NSString *app) {
    NSURL *url = [NSURL fileURLWithPath:[app stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSError *error;
    NSMutableDictionary *info = [[NSMutableDictionary alloc] initWithContentsOfURL:url error:&error];
    info[@"SUEnableAutomaticChecks"] = info[@"SUAutomaticallyUpdate"] = @NO;
    info[@"DiaPatches"] = @YES;
    [info removeObjectForKey:@"SUFeedURL"];
    return [info writeToURL:url error:&error] || fail(@"cannot update %@: %@", url.path, error.localizedDescription);
}

static NSString *localIdentity(NSString *keychain) {
    NSString *list;
    run(@[ @"/usr/bin/security", @"find-identity", @"-p", @"codesigning", keychain ], &list);
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"([0-9A-F]{40}) \"DiaPatches Local Signing\""
                                                                             options:0
                                                                               error:NULL];
    NSTextCheckingResult *match = list ? [pattern firstMatchInString:list options:0 range:NSMakeRange(0, list.length)] : nil;
    return match ? [list substringWithRange:[match rangeAtIndex:1]] : nil;
}

// A stable self-signed identity keeps Dia's keychain items readable across builds.
static NSString *createLocalIdentity(NSString *keychain) {
    note(@"creating the signing identity \"%@\" in %@", kLocalIdentity, keychain);
    char dirTemplate[PATH_MAX];
    snprintf(dirTemplate, sizeof dirTemplate, "%sdiapatch-identity.XXXXXX", NSTemporaryDirectory().fileSystemRepresentation);
    if (!mkdtemp(dirTemplate)) return fail(@"cannot create a folder for the signing identity: %s", strerror(errno)), nil;
    NSString *dir = @(dirTemplate);
    NSString *config = [dir stringByAppendingPathComponent:@"req.cnf"], *key = [dir stringByAppendingPathComponent:@"key.pem"],
             *cert = [dir stringByAppendingPathComponent:@"cert.pem"], *p12 = [dir stringByAppendingPathComponent:@"id.p12"];
    NSString *request = @"[req]\ndistinguished_name = dn\nprompt = no\nx509_extensions = ext\n[dn]\nCN = DiaPatches Local Signing\n"
                        @"[ext]\nbasicConstraints = critical,CA:FALSE\nkeyUsage = critical,digitalSignature\n"
                        @"extendedKeyUsage = critical,codeSigning\nsubjectKeyIdentifier = hash\n";
    NSString *password = [NSString stringWithFormat:@"pass:%@", NSUUID.UUID.UUIDString];
    // The key is unencrypted only inside the mkdtemp folder, which no other user can open, until the keychain holds it.
    BOOL ok = [request writeToFile:config atomically:NO encoding:NSUTF8StringEncoding error:NULL]
        && check(@[ @"/usr/bin/openssl", @"req", @"-x509", @"-new", @"-newkey", @"rsa:2048", @"-nodes", @"-sha256", @"-days", @"7300",
                    @"-config", config, @"-keyout", key, @"-out", cert ])
        && check(@[ @"/usr/bin/openssl", @"pkcs12", @"-export", @"-inkey", key, @"-in", cert, @"-name", kLocalIdentity,
                    @"-passout", password, @"-out", p12 ])
        && check(@[ @"/usr/bin/security", @"import", p12, @"-k", keychain, @"-f", @"pkcs12", @"-P", [password substringFromIndex:5], @"-T",
                    @"/usr/bin/codesign" ]);
    removeTree(dir);
    return ok ? localIdentity(keychain) : nil;
}

static NSData *cdhashOf(NSString *path) {
    SecStaticCodeRef code = NULL;
    CFDictionaryRef info = NULL;
    NSData *cdhash = nil;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:path], kSecCSDefaultFlags, &code) == errSecSuccess
        && SecStaticCodeCheckValidity(code, kSecCSStrictValidate, NULL) == errSecSuccess
        && SecCodeCopySigningInformation(code, kSecCSDefaultFlags, &info) == errSecSuccess)
        cdhash = ((__bridge NSDictionary *)info)[(__bridge NSString *)kSecCodeInfoUnique];
    if (info) CFRelease(info);
    if (code) CFRelease(code);
    return cdhash;
}

static NSDictionary *entitlementsOf(NSString *app) {
    SecStaticCodeRef code = NULL;
    CFDictionaryRef info = NULL;
    NSDictionary *entitlements = nil;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:app], kSecCSDefaultFlags, &code) == errSecSuccess
        && SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info) == errSecSuccess)
        entitlements = ((__bridge NSDictionary *)info)[(__bridge NSString *)kSecCodeInfoEntitlementsDict];
    if (info) CFRelease(info);
    if (code) CFRelease(code);
    return entitlements;
}

// Entitlements outside com.apple.security.* need The Browser Company's provisioning profile, and AMFI kills an app that
// claims them without one. The patched Dia keeps hardened runtime, so it only gives up library validation, which it needs
// to load The Browser Company's frameworks; the library constraint narrows what it can load back down.
static NSDictionary *patchedEntitlements(NSString *official) {
    NSSet *weakening = [NSSet setWithArray:@[
        @"com.apple.security.application-groups", @"com.apple.security.get-task-allow", @"com.apple.security.cs.debugger",
        @"com.apple.security.cs.allow-dyld-environment-variables",
    ]];
    NSMutableDictionary *granted = [NSMutableDictionary dictionary];
    [entitlementsOf(official) enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if ([key hasPrefix:@"com.apple.security."] && ![weakening containsObject:key]) granted[key] = value;
    }];
    granted[@"com.apple.security.cs.disable-library-validation"] = @YES;
    return granted;
}

// Without library validation any signed library could load into Dia. This lets in only macOS, The Browser Company's
// own frameworks and this exact build of the dylib, so swapping the dylib or a framework needs a new signature.
static NSDictionary *libraryConstraint(NSData *dylib) {
    return @{ @"$or" : @{ @"validation-category" : @1, @"team-identifier" : kTeam, @"cdhash" : dylib } };
}

static BOOL sign(NSString *app, NSString *official, NSData *dylib) {
    NSString *identity = env("DIAPATCH_IDENTITY")
        ?: [[NSString stringWithContentsOfFile:inHome(@"identity") encoding:NSUTF8StringEncoding error:NULL]
               stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *codesign = @[ @"/usr/bin/codesign", @"--force", @"--timestamp=none", @"--options", @"runtime", @"--sign" ];
    if (identity.length) {
        codesign = [codesign arrayByAddingObject:identity];
    } else {
        NSString *keychain = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Keychains/login.keychain-db"];
        identity = localIdentity(keychain) ?: createLocalIdentity(keychain);
        if (identity) codesign = [codesign arrayByAddingObjectsFromArray:@[ identity, @"--keychain", keychain ]];
        else codesign = [codesign arrayByAddingObject:@"-"];
        if (!identity) say(@"warning: signing ad hoc, so Dia will ask for keychain access again after every update");
    }
    char dirTemplate[PATH_MAX];
    snprintf(dirTemplate, sizeof dirTemplate, "%sdiapatch-sign.XXXXXX", NSTemporaryDirectory().fileSystemRepresentation);
    if (!mkdtemp(dirTemplate)) return fail(@"cannot create a folder for signing: %s", strerror(errno));
    NSString *dir = @(dirTemplate);
    NSURL *entitlements = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"entitlements.plist"]];
    NSURL *constraint = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"library-constraint.plist"]];
    BOOL ok = ([patchedEntitlements(official) writeToURL:entitlements error:NULL] || fail(@"cannot write %@", entitlements.path))
        && ([libraryConstraint(dylib) writeToURL:constraint error:NULL] || fail(@"cannot write %@", constraint.path))
        && check([codesign arrayByAddingObjectsFromArray:@[ @"--entitlements", entitlements.path, @"--library-constraint", constraint.path, app ]]);
    removeTree(dir);
    if (ok) note(@"signed %@ with %@", app, codesign[6]);
    return ok;
}

// A finished build records the inode of staged/Dia.app, which renames keep. Anything else found there, like the app a
// stopped apply had just swapped out, is never installed.
static NSString *stagedID(void) {
    struct stat info;
    return lstat(gStaged.fileSystemRepresentation, &info) == 0 ? @(info.st_ino).stringValue : nil;
}

static BOOL stagedReady(void) {
    return [[NSString stringWithContentsOfFile:gReady encoding:NSUTF8StringEncoding error:NULL] isEqualToString:stagedID()];
}

static BOOL unstage(void) { return discard(gStaged) && removeTree(gReady); }

static BOOL build(NSString *source) {
    NSString *executable = infoOf(source)[@"CFBundleExecutable"], *dylib = inHome(@DYLIB);
    if (!executable) return fail(@"no official Dia at %@; reinstall Dia from https://www.diabrowser.com", source);
    if (!exists(dylib)) return fail(@"%@ is missing; reinstall DiaPatches", dylib);
    NSData *dylibHash = cdhashOf(dylib);
    if (!dylibHash) return fail(@"%@ isn't validly signed; reinstall DiaPatches", dylib);
    note(@"building patched Dia %@", versionOf(source));
    NSString *work = [gStaged stringByAppendingString:@".building"], *contents = [work stringByAppendingPathComponent:@"Contents"];
    BOOL ok = removeTree(work) && makeDir(gStaged.stringByDeletingLastPathComponent) && clone(source, work)
        && addLoadCommand([contents stringByAppendingPathComponent:[@"MacOS" stringByAppendingPathComponent:executable]], dylib)
        && configureInfo(work) && removeTree([contents stringByAppendingPathComponent:@"embedded.provisionprofile"])
        && sign(work, source, dylibHash) && moveBundle(work, gStaged)
        && ([stagedID() writeToFile:gReady atomically:YES encoding:NSUTF8StringEncoding error:NULL] || fail(@"cannot write %@", gReady));
    if (!ok) removeTree(work);
    return ok;
}

#pragma mark - Updates

@interface Release : NSObject
@property(nonatomic, copy) NSString *build, *version, *url, *channel, *minimumOS;
@property(nonatomic) long long size;
@end

@implementation Release
@end

static BOOL newer(NSString *a, NSString *b) { return [a compare:b ?: @"" options:NSNumericSearch] == NSOrderedDescending; }

// sparkle:<name> as an attribute of `enclosure`, else as an element of `item`.
static NSString *sparkle(NSXMLElement *item, NSXMLElement *enclosure, NSString *name) {
    NSString *value = [enclosure attributeForLocalName:name URI:kSparkle].stringValue
        ?: [item elementsForLocalName:name URI:kSparkle].firstObject.stringValue;
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return value.length ? value : nil;
}

static NSArray<Release *> *releasesIn(NSXMLDocument *feed) {
    NSMutableArray<Release *> *releases = [NSMutableArray array];
    for (NSXMLElement *item in [feed nodesForXPath:@"/rss/channel/item" error:NULL]) {
        NSXMLElement *enclosure = [item nodesForXPath:@"enclosure[@url and not(@*[local-name()='deltaFrom'])]" error:NULL].firstObject;
        Release *release = [Release new];
        release.url = [enclosure attributeForName:@"url"].stringValue;
        release.build = sparkle(item, enclosure, @"version");
        release.channel = sparkle(item, nil, @"channel");
        release.minimumOS = sparkle(item, nil, @"minimumSystemVersion");
        release.size = [enclosure attributeForName:@"length"].stringValue.longLongValue;
        NSString *shortVersion = sparkle(item, enclosure, @"shortVersionString") ?: @"?";
        NSString *suffix = [NSString stringWithFormat:@" (%@)", release.build];  // Dia's feed already has it
        release.version = [shortVersion hasSuffix:suffix] ? shortVersion : [shortVersion stringByAppendingString:suffix];
        if (release.url && release.build) [releases addObject:release];
    }
    return releases;
}

// The newest build this Mac can run. Like Sparkle, it skips items tagged with a channel.
static Release *offer(NSArray<Release *> *releases) {
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *system = [NSString stringWithFormat:@"%ld.%ld.%ld", os.majorVersion, os.minorVersion, os.patchVersion];
    Release *best;
    for (Release *release in releases)
        if (!release.channel && !newer(release.minimumOS, system) && (!best || newer(release.build, best.build))) best = release;
    return best;
}

// Early Birds is its own feed, which Dia only uses once it has let the account switch App Build to it. The dylib saves
// the feed Dia's updater asked for; until it has, the official build's own feed.
static NSString *diaFeed(void) {
    // Any process of this user can write com.diapatches, and a feed served elsewhere could hold Dia back from its fixes.
    NSString *saved = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("diaFeed"), CFSTR("com.diapatches")));
    BOOL official = [saved isKindOfClass:NSString.class] && [saved hasPrefix:kFeedOrigin];
    return env("DIAPATCH_FEED") ?: (official ? saved : nil) ?: infoOf(gPristine)[@"SUFeedURL"] ?: kFeed;
}

static Release *latest(int seconds, NSString **channel, NSString **problem) {
    NSString *url = diaFeed(), *output;
    NSError *error;
    *channel = [url containsString:@"/release-candidate/"] ? @"Early Birds" : nil;
    NSXMLDocument *feed = fetch(url, seconds, nil, &output) == 0 ? [[NSXMLDocument alloc] initWithXMLString:output options:0 error:&error] : nil;
    Release *release = offer(releasesIn(feed));
    if (!release)
        *problem = [NSString stringWithFormat:@"no update from %@: %@", url,
                                              feed ? @"nothing for this Mac" : error.localizedDescription ?: output];
    return release;
}

// A DiaTweaks release is identified by its asset's digest, so replacing the asset on a published release counts as an update.
static NSString *gStagedTweaks;

static NSDictionary *installedRelease(void) { return [NSDictionary dictionaryWithContentsOfFile:inHome(@"release.plist")]; }
static NSDictionary *stagedRelease(void) {
    return [NSDictionary dictionaryWithContentsOfFile:[gStagedTweaks stringByAppendingPathComponent:@"release.plist"]];
}

static NSDictionary<NSString *, NSString *> *tweaksTargets(void) {
    return @{ @"diapatch" : inHome(@"bin/diapatch"), @"diatweaks" : inHome(@"bin/diatweaks"), @DYLIB : inHome(@DYLIB),
              @"patches.json" : inHome(@"patches.json") };
}

static NSString *sha256(NSString *file) {
    NSData *data = [NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:NULL];
    if (!data) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [@"sha256:" stringByAppendingString:hex];
}

static NSDictionary *latestTweaks(int seconds, NSString **problem) {
    NSString *url = env("DIAPATCH_RELEASES") ?: kReleases, *output;
    if (fetch(url, seconds, nil, &output) != 0) {
        *problem = [NSString stringWithFormat:@"cannot reach %@: %@", url,
                                              [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
        return nil;
    }
    NSDictionary *release = [NSJSONSerialization JSONObjectWithData:[output dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    NSDictionary *asset, *signature;
    for (NSDictionary *candidate in [release isKindOfClass:NSDictionary.class] ? release[@"assets"] : nil) {
        if ([candidate[@"name"] isEqual:kReleaseAsset]) asset = candidate;
        if ([candidate[@"name"] isEqual:kReleaseSignature]) signature = candidate;
    }
    NSString *digest = asset[@"digest"];
    if (![digest isKindOfClass:NSString.class] || ![digest hasPrefix:@"sha256:"] || ![release[@"tag_name"] isKindOfClass:NSString.class]
        || ![signature[@"browser_download_url"] isKindOfClass:NSString.class]) {
        *problem = [NSString stringWithFormat:@"no signed %@ in the latest DiaTweaks release", kReleaseAsset];
        return nil;
    }
    return @{ @"tag" : release[@"tag_name"], @"digest" : digest, @"size" : asset[@"size"] ?: @0,
              @"releaseNotes" : release[@"html_url"] ?: @"", @"url" : asset[@"browser_download_url"],
              @"signatureURL" : signature[@"browser_download_url"] };
}

static BOOL tweaksAvailable(NSDictionary *latest) {
    return latest && ![installedRelease()[@"digest"] isEqual:latest[@"digest"]] && ![stagedRelease()[@"digest"] isEqual:latest[@"digest"]];
}

// GitHub's digest only shows the download arrived intact. The signature shows a release key made it, so taking over the
// repository or its CI isn't enough to put code into Dia.
static BOOL verifyReleaseSignature(NSString *zip, NSString *signature, NSString *work) {
    unsigned long size = 0;
    const uint8_t *bytes = getsectiondata(&_mh_execute_header, "__TEXT", "__signers", &size);
    NSString *signers = [work stringByAppendingPathComponent:@"allowed_signers"], *output;
    if (!bytes || !size || ![[NSData dataWithBytes:bytes length:size] writeToFile:signers atomically:YES])
        return fail(@"this diapatch has no release keys to check DiaTweaks downloads with");
    int status = runWithInput(@[ @"/usr/bin/ssh-keygen", @"-Y", @"verify", @"-f", signers, @"-I", kReleaseSigner, @"-n", kReleaseSigner,
                                 @"-s", signature ], zip, &output);
    return status == 0
        || fail(@"the DiaTweaks download isn't signed with a release key: %@",
                [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
}

// Dia quarantines whatever it and its children write, this run included when Dia started it, and Gatekeeper then won't
// let launchd or Dia run an unnotarized diapatch. The release signature has been checked by the time this runs.
static BOOL unquarantine(NSString *path) { return check(@[ @"/usr/bin/xattr", @"-dr", @"com.apple.quarantine", path ]); }

static NSString *versionNumber(NSString *tag) { return [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag; }

static BOOL stageTweaks(void) {
    NSString *problem, *output;
    NSDictionary *latest = latestTweaks(30, &problem);
    if (!latest) return fail(@"%@", problem);
    if ([stagedRelease()[@"digest"] isEqual:latest[@"digest"]]) return say(@"DiaTweaks %@ is ready to install", latest[@"tag"]);
    if (!tweaksAvailable(latest)) return say(@"DiaTweaks %@ is up to date", latest[@"tag"]);

    NSString *installed = installedRelease()[@"tag"];
    if (installed && !newer(versionNumber(latest[@"tag"]), versionNumber(installed)))
        return fail(@"the latest DiaTweaks release, %@, isn't newer than the installed %@", latest[@"tag"], installed);

    NSString *work = [gCache stringByAppendingPathComponent:@"release"], *zip = [work stringByAppendingPathComponent:kReleaseAsset];
    NSString *signature = [work stringByAppendingPathComponent:kReleaseSignature];
    NSString *building = [gStagedTweaks stringByAppendingString:@".building"];
    if (!removeTree(work) || !makeDir(work)) return NO;
    note(@"downloading DiaTweaks %@ from %@", latest[@"tag"], latest[@"url"]);
    if (fetch(latest[@"url"], 600, zip, &output) != 0 || fetch(latest[@"signatureURL"], 60, signature, &output) != 0) {
        removeTree(work);
        return fail(@"cannot download DiaTweaks %@: %@", latest[@"tag"], output);
    }
    BOOL ok = ([sha256(zip) isEqual:latest[@"digest"]] || fail(@"the DiaTweaks %@ download doesn't match its digest", latest[@"tag"]))
        && verifyReleaseSignature(zip, signature, work)
        && removeTree(building) && makeDir(building) && check(@[ @"/usr/bin/ditto", @"-x", @"-k", zip, building ])
        && unquarantine(building);
    for (NSString *name in [tweaksTargets().allKeys arrayByAddingObject:@"VERSION"])
        ok = ok && (exists([building stringByAppendingPathComponent:name]) || fail(@"DiaTweaks %@ has no %@", latest[@"tag"], name));
    // The tag on GitHub can be moved; the one inside the signed zip can't, so an old release can't come back as the latest.
    NSString *signedTag = [[NSString stringWithContentsOfFile:[building stringByAppendingPathComponent:@"VERSION"] encoding:NSUTF8StringEncoding error:NULL]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    ok = ok && ([signedTag isEqualToString:latest[@"tag"]] || fail(@"DiaTweaks %@ was signed as %@", latest[@"tag"], signedTag));
    ok = ok && [@{ @"digest" : latest[@"digest"], @"tag" : latest[@"tag"] } writeToFile:[building stringByAppendingPathComponent:@"release.plist"] atomically:YES]
        && removeTree(gStagedTweaks) && moveBundle(building, gStagedTweaks);
    removeTree(work);
    removeTree(building);
    return ok && say(@"DiaTweaks %@ is ready to install", latest[@"tag"]);
}

static BOOL applyTweaks(void) {
    // A release staged a while ago may since have been replaced, or overtaken by what's installed.
    NSString *problem;
    NSDictionary *latest = stagedRelease() ? latestTweaks(15, &problem) : nil;
    if ([installedRelease()[@"digest"] isEqual:latest[@"digest"]]) removeTree(gStagedTweaks);
    else if (tweaksAvailable(latest)) stageTweaks();  // if this fails, the staged release still installs
    NSString *tag = stagedRelease()[@"tag"];
    if (!tag) return removeTree(gStagedTweaks);
    NSDictionary<NSString *, NSString *> *targets = tweaksTargets();
    BOOL ok = makeDir(inHome(@"bin")) && unquarantine(gStagedTweaks);
    for (NSString *name in targets) ok = ok && moveBundle([gStagedTweaks stringByAppendingPathComponent:name], targets[name]);
    ok = ok && moveBundle([gStagedTweaks stringByAppendingPathComponent:@"release.plist"], inHome(@"release.plist"));
    return ok && removeTree(gStagedTweaks) && say(@"installed DiaTweaks %@", tag);
}

#pragma mark - Commands

static BOOL apply(void) {
    if (!exists(gStaged)) return YES;
    if (!stagedReady()) return unstage() && fail(@"deleted %@: a stopped run left it there; run `diapatch build` to stage Dia again", gStaged);
    if (appRunning()) return fail(@"Dia is running; quit it, then run `diapatch apply`");
    return moveBundle(gStaged, gApp) && removeTree(gReady) && say(@"installed patched Dia %@ at %@", versionOf(gApp), gApp);
}

// The patched Dia only loads the dylib it was signed with, so a new dylib means signing Dia again.
static BOOL applyChosen(BOOL dia, BOOL tweaks) {
    if (!dia && !tweaks) dia = tweaks = YES;
    BOOL newDylib = tweaks && stagedRelease()[@"tag"];
    if (tweaks && !applyTweaks()) return NO;
    if (newDylib) return build(gPristine) && apply();
    return !dia || apply();
}

static BOOL install(BOOL relaunch) {
    NSString *identity = env("DIAPATCH_IDENTITY");
    if (!exists(gApp)) return fail(@"Dia is not installed at %@; get it from https://www.diabrowser.com", gApp);
    if (identity && ![identity writeToFile:inHome(@"identity") atomically:YES encoding:NSUTF8StringEncoding error:NULL])
        return fail(@"cannot save the signing identity");
    if (claimsOfficial(gApp) && ![buildOf(gApp) isEqual:buildOf(gPristine)]) {
        NSString *copy = [gPristine stringByAppendingString:@".new"];
        BOOL adopted = removeTree(copy) && makeDir(gPristine.stringByDeletingLastPathComponent) && clone(gApp, copy)
            && verifyOfficial(copy) && moveBundle(copy, gPristine);
        if (!adopted) return removeTree(copy), NO;
    }
    if (!build(gPristine)) return NO;
    if (appRunning() && relaunch) {
        run(@[ @"/usr/bin/osascript", @"-e", @"tell application id \"company.thebrowser.dia\" to quit" ], NULL);
        waitForQuit(0);
    }
    if (!appRunning()) return apply();
    if (isPatched(gApp)) return say(@"patched Dia %@ is staged and replaces Dia when it quits", versionOf(gStaged));
    return say(@"patched Dia %@ is staged: quit Dia, then run \"%@\" apply (or install --relaunch to do both)", versionOf(gStaged),
               inHome(@"bin/diapatch"));
}

static BOOL update(void) {
    NSString *channel, *problem, *output;
    Release *release = latest(60, &channel, &problem);
    if (!release) return say(@"%@", problem);
    if (!newer(release.build, buildOf(gPristine))) {
        if (stagedReady()) return say(@"Dia %@ is staged; relaunch Dia or run `diapatch apply` to install it", versionOf(gStaged));
        return say(@"Dia %@ is up to date", release.version);
    }
    NSString *work = [gCache stringByAppendingPathComponent:@"download"];
    NSString *zip = [work stringByAppendingPathComponent:@"Dia.zip"], *app = [work stringByAppendingPathComponent:@"Dia.app"];
    if (!removeTree(work) || !makeDir(work)) return NO;
    note(@"downloading Dia %@ (%@) from %@", release.version, channel ?: @"stable", release.url);
    if (fetch(release.url, 3600, zip, &output) != 0) {
        removeTree(work);
        return fail(@"cannot download Dia %@: %@", release.version, output);
    }
    BOOL ok = check(@[ @"/usr/bin/ditto", @"-x", @"-k", zip, work ]) && check(@[ @"/usr/bin/xattr", @"-cr", work ])
        && ([buildOf(app) isEqual:release.build] || fail(@"the download holds build %@, not %@", buildOf(app), release.build))
        && verifyOfficial(app) && build(app) && makeDir(gPristine.stringByDeletingLastPathComponent) && moveBundle(app, gPristine);
    removeTree(work);
    return ok && say(@"Dia %@ is staged; relaunch Dia or run `diapatch apply` to install it", release.version);
}

#pragma mark - Background updates

static NSString *agentPlist(NSString *label) {
    return [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Library/LaunchAgents/%@.plist", label]];
}

static NSString *agentDomain(void) { return [NSString stringWithFormat:@"gui/%d", getuid()]; }

// bootout returns before a busy job has exited, and bootstrapping it again before then fails with an I/O error.
static void removeAgent(NSString *label) {
    NSString *service = [NSString stringWithFormat:@"%@/%@", agentDomain(), label];
    run(@[ @"/bin/launchctl", @"bootout", service ], NULL);
    for (int i = 0; i < 100 && run(@[ @"/bin/launchctl", @"print", service ], NULL) == 0; i++) usleep(100000);
    removeTree(agentPlist(label));
}

static BOOL loadAgent(NSDictionary *agent) {
    NSString *path = agentPlist(agent[@"Label"]);
    NSError *error;
    removeAgent(agent[@"Label"]);
    return makeDir(path.stringByDeletingLastPathComponent)
        && ([agent writeToURL:[NSURL fileURLWithPath:path] error:&error] || fail(@"cannot write %@: %@", path, error.localizedDescription))
        && check(@[ @"/bin/launchctl", @"bootstrap", agentDomain(), path ]);
}

static NSString *passwordsHostManifest(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json"];
}

// Only the copy the dylib registered: another app's override of Apple's host isn't DiaTweaks' to remove.
static void removePasswordsHost(void) {
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:passwordsHostManifest()] ?: NSData.data options:0 error:NULL];
    if ([host isKindOfClass:NSDictionary.class] && [host[@"path"] isEqual:inHome(@"bin/diapatch")]) removeTree(passwordsHostManifest());
}

// launchd starts the relay when the patched Dia's 1Password extension first connects.
static NSDictionary *relayAgent(void) {
    NSMutableDictionary *environment = [NSMutableDictionary dictionary];
    for (NSString *name in @[ @"DIAPATCH_HOME", @"DIAPATCH_APP" ]) environment[name] = env(name.UTF8String);
    return DPPasswordsAgentPlist(gHome, inHome(@"bin/diapatch"), environment);
}

static BOOL relayAgentCurrent(void) { return [[NSDictionary dictionaryWithContentsOfFile:agentPlist(DPPasswordsAgent)] isEqual:relayAgent()]; }

// The diapatch a self-update replaces is the one that applies it, so the new one's first host updates the agent.
static void refreshRelayAgent(void) {
    if (env("DIAPATCH_NO_AGENT") || relayAgentCurrent()) return;
    FILE *lock = fopen(inHome(@"diapatch.log").fileSystemRepresentation, "a");
    if (lock && flock(fileno(lock), LOCK_EX | LOCK_NB) == 0 && !relayAgentCurrent()) loadAgent(relayAgent());
    if (lock) fclose(lock);
}

// Dia's own updater is switched off, so this stands in for it: it checks whether or not Dia is open, and doesn't need
// the dylib, which safe mode or a mismatched Dia may keep from loading.
static BOOL installAgent(void) {
    if (env("DIAPATCH_NO_AGENT")) return YES;
    NSMutableDictionary *environment = [NSMutableDictionary dictionary];
    for (NSString *name in @[ @"DIAPATCH_HOME", @"DIAPATCH_APP", @"DIAPATCH_CACHE", @"DIATWEAKS_DOMAIN" ])
        environment[name] = env(name.UTF8String);
    NSDictionary *agent = @{
        @"Label" : kAgent,
        @"ProgramArguments" : @[ inHome(@"bin/diapatch"), @"scheduled" ],
        @"EnvironmentVariables" : environment,
        @"StartInterval" : @900,
        @"RunAtLoad" : @YES,
        @"ProcessType" : @"Background",
        @"LowPriorityIO" : @YES,
    };
    return loadAgent(agent) && loadAgent(relayAgent()) && removeTree(inHome(@"passwords.sock"));
}

typedef NS_ENUM(NSInteger, AutoLevel) { AutoOff, AutoNotify, AutoDownload, AutoInstall };

static AutoLevel autoLevel(NSString *key) {
    id level = [[[NSUserDefaults alloc] initWithSuiteName:env("DIATWEAKS_DOMAIN") ?: kPrefsDomain] objectForKey:key];
    return level ? MIN(MAX([level integerValue], AutoOff), AutoInstall) : AutoInstall;
}

static const NSTimeInterval kCheckEvery = 3600;

// Runs every 15 minutes: checks the feeds at most hourly, and installs what's staged as soon as Dia isn't open.
static BOOL scheduled(void) {
    if (!isPatched(gApp)) return YES;
    AutoLevel dia = autoLevel(@"autoUpdateDia"), tweaks = autoLevel(@"autoUpdateTweaks");
    NSString *stamp = inHome(@"last-check"), *channel, *problem;
    NSDate *checked = [NSFileManager.defaultManager attributesOfItemAtPath:stamp error:NULL].fileModificationDate;
    if ((dia >= AutoDownload || tweaks >= AutoDownload) && (!checked || -checked.timeIntervalSinceNow >= kCheckEvery)
        && latest(60, &channel, &problem)) {
        [NSData.data writeToFile:stamp atomically:YES];
        if (dia >= AutoDownload) update();
        if (tweaks >= AutoDownload) stageTweaks();
    }
    BOOL installDia = dia == AutoInstall && stagedReady(), installTweaks = tweaks == AutoInstall && stagedRelease()[@"tag"];
    if (appRunning() || !(installDia || installTweaks)) return YES;
    return applyChosen(installDia, installTweaks);
}

// Deletes only what DiaPatches creates, in case DIAPATCH_HOME points somewhere shared.
static BOOL purge(void) {
    // install.sh links the diatweaks command into the first of these it can write to.
    NSArray<NSString *> *linkDirs = env("DIATWEAKS_LINK_DIR") ? @[ env("DIATWEAKS_LINK_DIR") ]
        : @[ @"/opt/homebrew/bin", @"/usr/local/bin", [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"] ];
    for (NSString *dir in linkDirs) {
        NSString *link = [dir stringByAppendingPathComponent:@"diatweaks"];
        NSString *target = [NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:link error:NULL];
        if (![target hasPrefix:[gHome stringByAppendingString:@"/"]]) continue;
        if (!removeTree(link)) return NO;
        say(@"deleted %@", link);
    }
    for (NSString *name in @[ @"bin", @DYLIB, @"patches.json", @"release.plist", @"pristine", @"staged", @"identity", @"diapatch.log", @"safe-mode.plist",
                              @".diatweaks.lock", @".incoming", @"last-check", @"passkey-helper", @"passkey-helper.lock", @"passkeys-extension",
                              @"passkeys-extension.key", @"passwords-helper", @"passwords.sock", @"onepassword.sock", @"passwords-launch" ])
        if (!discard(inHome(name))) return NO;
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:gHome error:NULL])
        if ([name hasPrefix:@".update-"] && !removeTree(inHome(name))) return NO;  // checkouts left by an interrupted diatweaks update
    if (!removeTree([gCache stringByAppendingPathComponent:@"download"]) || !removeTree([gCache stringByAppendingPathComponent:@"release"])) return NO;
    rmdir(gCache.fileSystemRepresentation);
    if (rmdir(gHome.fileSystemRepresentation) == 0) return say(@"deleted %@", gHome);
    return say(@"kept %@: it holds files DiaPatches did not create", gHome);
}

static BOOL uninstall(BOOL purgeFiles) {
    if (appRunning()) return fail(@"Dia is running; quit it, then run `diapatch uninstall`");
    removeAgent(kAgent);
    removeAgent(DPPasswordsAgent);
    // The official Dia has its own passkeys and reaches iCloud Passwords itself, and nothing else should reach diapatch.
    removeTree([NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Google/Chrome/NativeMessagingHosts/com.diapatches.passkeys.json"]);
    removePasswordsHost();
    if (!removeTree(DPCopyFolder)) return NO;
    if (!claimsOfficial(gApp)) {
        NSString *copy = [gPristine stringByAppendingString:@".restore"];
        if (!exists(gPristine)) return fail(@"no official Dia at %@; reinstall Dia from https://www.diabrowser.com", gPristine);
        if (!removeTree(copy) || !clone(gPristine, copy) || !moveBundle(copy, gApp)) return removeTree(copy), NO;
    }
    say(@"%@ is the official Dia %@", gApp, versionOf(gApp));
    return unstage() && (!purgeFiles || purge());
}

static BOOL status(BOOL json) {
    NSString *channel, *problem;
    Release *release = latest(15, &channel, &problem);
    NSDictionary *status = @{
        @"official" : versionOf(gPristine) ?: NSNull.null,
        @"installed" : versionOf(gApp) ?: NSNull.null,
        @"patched" : @(isPatched(gApp)),
        @"staged" : (stagedReady() ? versionOf(gStaged) : nil) ?: NSNull.null,
        @"feed" : release.version ?: NSNull.null,
        @"channel" : channel ?: @"stable",
        @"release" : installedRelease()[@"tag"] ?: NSNull.null,
    };
    if (json) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:status
                                                       options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                         error:NULL];
        printf("%.*s\n", (int)data.length, (const char *)data.bytes);
        return YES;
    }
    for (NSString *key in @[ @"official", @"installed", @"patched", @"staged", @"feed", @"channel", @"release" ]) {
        id value = status[key];
        if (value == NSNull.null) value = [key isEqualToString:@"feed"] ? problem : @"none";
        else if ([key isEqualToString:@"patched"]) value = [value boolValue] ? @"yes" : @"no";
        printf("%-10s%s\n", key.UTF8String, [value UTF8String]);
    }
    return YES;
}

// Like status, it runs without taking the lock.
static BOOL checkUpdates(void) {
    NSString *channel, *problem, *tweaksProblem;
    Release *dia = latest(15, &channel, &problem);
    NSDictionary *tweaks = latestTweaks(15, &tweaksProblem);
    BOOL diaStaged = stagedReady() && [buildOf(gStaged) isEqual:dia.build];
    NSDictionary *result = @{
        @"dia" : @{
            @"installed" : versionOf(gPristine) ?: NSNull.null,
            @"latest" : dia.version ?: NSNull.null,
            @"size" : @(dia.size),
            @"releaseNotes" : kDiaReleaseNotes,
            @"staged" : (stagedReady() ? versionOf(gStaged) : nil) ?: NSNull.null,
            @"available" : @((BOOL)(dia && newer(dia.build, buildOf(gPristine)) && !diaStaged)),
            @"error" : dia ? NSNull.null : problem,
        },
        @"tweaks" : @{
            @"installed" : installedRelease()[@"tag"] ?: NSNull.null,
            @"latest" : tweaks[@"tag"] ?: NSNull.null,
            @"size" : tweaks[@"size"] ?: @0,
            @"releaseNotes" : tweaks[@"releaseNotes"] ?: NSNull.null,
            @"staged" : stagedRelease()[@"tag"] ?: NSNull.null,
            @"available" : @((BOOL)tweaksAvailable(tweaks)),
            @"error" : tweaks ? NSNull.null : tweaksProblem,
        },
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:NULL];
    printf("%.*s\n", (int)data.length, (const char *)data.bytes);
    return YES;
}

static const char kUsage[] =
    "usage: diapatch <command>\n"
    "  install [--relaunch]\n"
    "                   keep the official Dia as the pristine copy, patch it and put it in place;\n"
    "                   --relaunch quits a running Dia first and reopens it afterwards\n"
    "  build            rebuild the staged patched Dia from the pristine copy\n"
    "  update           download, verify and stage a newer Dia from your channel (stable or Early Birds)\n"
    "  self-update      download, verify and stage the latest DiaTweaks release if it isn't the one installed\n"
    "  apply [--wait PID] [--relaunch] [--dia] [--tweaks]\n"
    "                   install what's staged once PID and Dia have quit, then reopen Dia; --dia or --tweaks limits it\n"
    "  check --json     what's installed, available and staged for Dia and DiaTweaks\n"
    "  uninstall [--wait PID] [--relaunch] [--purge]\n"
    "                   put the official Dia back; --purge also deletes DiaPatches' files and the diatweaks command\n"
    "  status [--json]  official, installed, staged and offered versions, and the update channel\n"
    "  scheduled        what the background agent runs: check hourly, stage updates and install them while Dia is closed\n"
    "  passwords-relay  what launchd runs when the patched Dia's 1Password extension connects\n"
    "environment: DIAPATCH_IDENTITY (codesigning identity, remembered by install), DIAPATCH_HOME,\n"
    "  DIAPATCH_APP, DIAPATCH_CACHE, DIAPATCH_FEED, DIAPATCH_RELEASES, DIATWEAKS_LINK_DIR, DIAPATCH_NO_RELAUNCH (ignore --relaunch),\n"
    "  DIAPATCH_NO_AGENT (install leaves the background agents alone)\n";

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (DPIsPasswordsHandoff(argc, argv)) return DPRunPasswordsHandoff();
        signal(SIGPIPE, SIG_IGN);
        gHome = env("DIAPATCH_HOME") ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DiaPatches"];
        gApp = env("DIAPATCH_APP") ?: @"/Applications/Dia.app";
        gCache = env("DIAPATCH_CACHE") ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/DiaPatches"];
        gPristine = inHome(@"pristine/Dia.app");
        gStaged = inHome(@"staged/Dia.app");
        gReady = inHome(@"staged/ready");
        gStagedTweaks = inHome(@"staged/DiaTweaks");
        // Started by a browser as a native messaging host.
        if (argc > 1 && !strncmp(argv[1], "chrome-extension://", 19)) {
            if (!DPIsPasswordsOrigin(argv[1])) return DPRunPasskeyHost(gHome);
            refreshRelayAgent();
            return DPRunPasswordsHost(gHome, gApp, argc, argv);
        }
        if (argc > 1 && !strcmp(argv[1], "passwords-relay")) return DPRunPasswordsRelay(gHome, gApp);

        NSString *command = argc > 1 ? @(argv[1]) : @"";
        NSArray<NSString *> *allowed = @{
            @"install" : @[ @"--relaunch" ], @"build" : @[], @"update" : @[], @"self-update" : @[], @"status" : @[ @"--json" ],
            @"apply" : @[ @"--wait", @"--relaunch", @"--dia", @"--tweaks" ], @"check" : @[ @"--json" ], @"uninstall" : @[ @"--wait", @"--relaunch", @"--purge" ],
            @"scheduled" : @[],
        }[command];
        NSMutableSet<NSString *> *flags = [NSMutableSet set];
        pid_t pid = 0;
        for (int i = 2; allowed && i < argc; i++) {
            [flags addObject:@(argv[i])];
            if (![allowed containsObject:@(argv[i])] || (!strcmp(argv[i], "--wait") && (++i == argc || (pid = atoi(argv[i])) <= 0)))
                allowed = nil;
        }
        if (!allowed) {
            BOOL help = argc == 2 && [@[ @"help", @"-h", @"--help" ] containsObject:command];
            fputs(kUsage, help ? stdout : stderr);
            return help ? 0 : 2;
        }
        // Tests patch a copy of Dia: opening it would share the real one's profile, and quitting by bundle ID can hit the real one.
        if (env("DIAPATCH_NO_RELAUNCH")) [flags removeObject:@"--relaunch"];
        if ([command isEqualToString:@"status"]) return status([flags containsObject:@"--json"]) ? 0 : 1;
        if ([command isEqualToString:@"check"]) return checkUpdates() ? 0 : 1;

        if (pid) setsid();  // the caller (Dia) is about to quit: leave its process group
        gCommand = argv[1];
        if (!makeDir(gHome)) return 1;
        gLog = fopen(inHome(@"diapatch.log").fileSystemRepresentation, "a");
        if (!gLog) return fail(@"cannot open %@: %s", inHome(@"diapatch.log"), strerror(errno)), 1;
        setvbuf(gLog, NULL, _IOLBF, 0);
        if (pid) waitForQuit(pid);
        if (flock(fileno(gLog), LOCK_EX | LOCK_NB) != 0) {  // the log doubles as the lock: one run at a time
            if ([command isEqualToString:@"scheduled"]) return 0;
            say(@"waiting for another diapatch run to finish");
            flock(fileno(gLog), LOCK_EX);
        }
        removeTree(inHome(@".trash"));  // what a run stopped mid-delete left
        BOOL ok = [command isEqualToString:@"install"] ? install([flags containsObject:@"--relaunch"]) && installAgent()
            : [command isEqualToString:@"build"]       ? build(gPristine) && say(@"staged patched Dia %@", versionOf(gStaged))
            : [command isEqualToString:@"update"]      ? update()
            : [command isEqualToString:@"self-update"] ? stageTweaks()
            : [command isEqualToString:@"scheduled"]   ? scheduled()
            : [command isEqualToString:@"apply"]       ? applyChosen([flags containsObject:@"--dia"], [flags containsObject:@"--tweaks"])
                                                       : uninstall([flags containsObject:@"--purge"]);
        // open sometimes fails with -600 right after Dia quits itself.
        for (int i = 0; [flags containsObject:@"--relaunch"] && i < 20; i++) {
            if (check(@[ @"/usr/bin/open", gApp ])) break;
            usleep(500000);
        }
        return ok ? 0 : 1;
    }
}
