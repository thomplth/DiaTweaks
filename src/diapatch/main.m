#import "AppIcon.h"
#import "BriefLanguage.h"
#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "LaunchServices.h"
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
static NSString *const kCompare = @"https://api.github.com/repos/thomplth/DiaTweaks/compare";
static NSString *const kDiaReleaseNotes = @"https://www.diabrowser.com/release-notes/latest";

static NSString *gHome, *gApp, *gCache, *gPristine, *gStaged, *gReady;
static const char *gCommand;
static FILE *gLog;
static NSString *gFailure;

static BOOL emit(FILE *out, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static BOOL emit(FILE *out, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    BOOL failure = out == stderr;
    if (failure) gFailure = line;
    if (gLog) {
        char stamp[20];
        time_t now = time(NULL);
        strftime(stamp, sizeof stamp, "%F %T", localtime(&now));
        fprintf(gLog, "%s %s[%d] %s%s\n", stamp, gCommand, getpid(), failure ? "error: " : "", line.UTF8String);
    }
    if (out) fprintf(out, "%s%s\n", failure ? "diapatch: " : "", line.UTF8String);
    return !failure;
}

#define note(...) emit(NULL, __VA_ARGS__)
#define say(...) emit(stdout, __VA_ARGS__)
#define fail(...) emit(stderr, __VA_ARGS__)

static NSString *env(const char *name) {
    const char *value = getenv(name);
    return value && *value ? @(value) : nil;
}

static NSString *trimmed(NSString *text) { return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }

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

static BOOL removeQuietly(NSString *path) {
    NSError *error;
    if ([NSFileManager.defaultManager removeItemAtPath:path error:&error] || error.code == NSFileNoSuchFileError) return YES;
    for (NSString *item in [NSFileManager.defaultManager enumeratorAtPath:path])
        [NSFileManager.defaultManager setAttributes:@{ NSFileImmutable : @NO } ofItemAtPath:[path stringByAppendingPathComponent:item] error:nil];
    return [NSFileManager.defaultManager removeItemAtPath:path error:nil];
}

// Unremovable leftovers (root-owned files) are set aside, or every later install would fail.
static BOOL emptyTrash(void) {
    NSString *trash = inHome(@".trash"), *aside = [trash stringByAppendingFormat:@"-%@", NSUUID.UUID.UUIDString];
    if (removeQuietly(trash)) return YES;
    if (rename(trash.fileSystemRepresentation, aside.fileSystemRepresentation) != 0) return fail(@"cannot remove %@: %s", trash, strerror(errno));
    note(@"cannot remove everything in %@, so it's set aside as %@", trash, aside.lastPathComponent);
    return YES;
}

static void removeSetAside(void) {
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:gHome error:nil])
        if ([name hasPrefix:@".trash-"]) removeQuietly(inHome(name));
}

// Rename to .trash first: a cut-short delete must not leave half a bundle where a whole one belongs.
static BOOL discard(NSString *path) {
    NSString *trash = inHome(@".trash");
    if (!emptyTrash()) return NO;
    if (rename(path.fileSystemRepresentation, trash.fileSystemRepresentation) == 0) return emptyTrash();
    if (errno == ENOENT) return YES;
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
        || fail(@"%@ failed (%d): %@", argv[0].lastPathComponent, status, trimmed(output));
}

// Dia's feed server turns away some HTTP clients but accepts curl.
static int fetch(NSString *url, int seconds, NSString *file, NSString **output) {
    NSArray *argv = @[ @"/usr/bin/curl", @"-fsSL", @"--proto", @"=https,file", @"--proto-redir", @"=https", @"--max-time",
                       @(seconds).stringValue, url ];
    return run(file ? [argv arrayByAddingObjectsFromArray:@[ @"-o", file ]] : argv, output);
}

// codesign --strict rejects the extended attributes Finder copies carry.
static BOOL clone(NSString *from, NSString *to) {
    BOOL copied = clonefile(from.fileSystemRepresentation, to.fileSystemRepresentation, 0) == 0
        || ((errno == EXDEV || errno == ENOTSUP) ? check(@[ @"/usr/bin/ditto", from, to ]) : fail(@"cannot clone %@: %s", from, strerror(errno)));
    return copied && check(@[ @"/usr/bin/xattr", @"-cr", to ]);
}

static int place(NSString *from, NSString *to) {
    const char *source = from.fileSystemRepresentation, *target = to.fileSystemRepresentation;
    return (exists(to) ? renamex_np(source, target, RENAME_SWAP) : rename(source, target)) == 0 ? 0 : errno;
}

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
    NSString *identity = env("DIAPATCH_IDENTITY") ?: trimmed([NSString stringWithContentsOfFile:inHome(@"identity") encoding:NSUTF8StringEncoding error:NULL]);
    NSArray *codesign = @[ @"/usr/bin/codesign", @"--force", @"--timestamp=none", @"--options", @"runtime", @"--sign" ];
    if (identity.length) {
        codesign = [codesign arrayByAddingObject:identity];
    } else {
        NSString *keychain = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Keychains/login.keychain-db"];
        identity = localIdentity(keychain) ?: createLocalIdentity(keychain);
        if (identity) {
            codesign = [codesign arrayByAddingObjectsFromArray:@[ identity, @"--keychain", keychain ]];
        } else {
            codesign = [codesign arrayByAddingObject:@"-"];
            say(@"warning: signing ad hoc, so Dia will ask for keychain access and screen sharing again after every update");
        }
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

// ready records the inode, which renames keep: a bundle a stopped apply swapped into staged/ never installs.
static NSString *stagedID(void) {
    struct stat info;
    return lstat(gStaged.fileSystemRepresentation, &info) == 0 ? @(info.st_ino).stringValue : nil;
}

static BOOL stagedReady(void) {
    return [[NSString stringWithContentsOfFile:gReady encoding:NSUTF8StringEncoding error:NULL] isEqualToString:stagedID()];
}

static BOOL unstage(void) { return discard(gStaged) && removeTree(gReady); }

static BOOL switchIcon(void) {
    NSString *problem = DPSwitchIcon(gApp, gHome);
    return !problem || fail(@"%@", problem);
}

// A Dia that can't switch icons still works: report the failure, don't fail the build.
static BOOL noteIcon(NSString *outcome) {
    if ([outcome hasPrefix:@"kept "]) say(@"warning: %@", outcome);
    else if (outcome) note(@"%@", outcome);
    return YES;
}

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
        && noteIcon(DPPrepareIcons(work, gApp, gHome)) && noteIcon(DPPrepareBriefLanguage(work)) && sign(work, source, dylibHash) && moveBundle(work, gStaged) && (DPForgetApp(gStaged), YES)
        && ([stagedID() writeToFile:gReady atomically:YES encoding:NSUTF8StringEncoding error:NULL] || fail(@"cannot write %@", gReady));
    if (!ok) removeTree(work);
    return ok;
}

@interface Release : NSObject
@property(nonatomic, copy) NSString *build, *version, *url, *channel, *minimumOS;
@property(nonatomic) long long size;
@end

@implementation Release
@end

static BOOL newer(NSString *a, NSString *b) { return [a compare:b ?: @"" options:NSNumericSearch] == NSOrderedDescending; }

static NSString *sparkle(NSXMLElement *item, NSXMLElement *enclosure, NSString *name) {
    NSString *value = [enclosure attributeForLocalName:name URI:kSparkle].stringValue
        ?: [item elementsForLocalName:name URI:kSparkle].firstObject.stringValue;
    value = trimmed(value);
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
        NSString *suffix = [NSString stringWithFormat:@" (%@)", release.build];
        release.version = [shortVersion hasSuffix:suffix] ? shortVersion : [shortVersion stringByAppendingString:suffix];
        if (release.url && release.build) [releases addObject:release];
    }
    return releases;
}

static Release *offer(NSArray<Release *> *releases) {
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *system = [NSString stringWithFormat:@"%ld.%ld.%ld", os.majorVersion, os.minorVersion, os.patchVersion];
    Release *best;
    for (Release *release in releases)
        if (!release.channel && !newer(release.minimumOS, system) && (!best || newer(release.build, best.build))) best = release;
    return best;
}

// The dylib saves the feed Dia's updater used; Early Birds has its own.
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

static NSString *gStagedTweaks;

static NSDictionary *installedRelease(void) { return [NSDictionary dictionaryWithContentsOfFile:inHome(@"release.plist")]; }
static NSDictionary *stagedRelease(void) {
    return [NSDictionary dictionaryWithContentsOfFile:[gStagedTweaks stringByAppendingPathComponent:@"release.plist"]];
}

static NSDictionary<NSString *, NSString *> *tweaksTargets(void) {
    return @{ @"diapatch" : inHome(@"bin/diapatch"), @"diatweaks" : inHome(@"bin/diatweaks"), @DYLIB : inHome(@DYLIB),
              @"patches.json" : inHome(@"patches.json"), @"app-icons" : inHome(@"app-icons") };
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
        *problem = [NSString stringWithFormat:@"cannot reach %@: %@", url, trimmed(output)];
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

static NSString *sourceCommit(void) {
#ifdef DIATWEAKS_COMMIT
    NSString *commit = env("DIAPATCH_COMMIT") ?: @DIATWEAKS_COMMIT;
#else
    NSString *commit = env("DIAPATCH_COMMIT");
#endif
    NSPredicate *hex = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"[0-9a-f]{7,40}"];
    return !installedRelease()[@"tag"] && [hex evaluateWithObject:commit] ? commit : nil;
}

// Any failure (unknown commit, no network) must leave the release on offer.
static NSString *sourceNotOlder(NSDictionary *latest) {
    NSString *commit = sourceCommit();
    if (!commit || ![latest[@"tag"] isKindOfClass:NSString.class]) return nil;
    NSString *base = env("DIAPATCH_COMPARE") ?: kCompare, *output;
    NSString *tag = [latest[@"tag"] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    // Without per_page the answer lists every commit and file between the two.
    NSString *url = [NSString stringWithFormat:@"%@/%@...%@%@", base, tag, commit, [base hasPrefix:@"https:"] ? @"?per_page=1" : @""];
    if (fetch(url, 10, nil, &output) != 0) return nil;
    NSDictionary *compared = [NSJSONSerialization JSONObjectWithData:[output dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    NSString *status = [compared isKindOfClass:NSDictionary.class] ? compared[@"status"] : nil;
    return [@[ @"ahead", @"identical" ] containsObject:status] ? [commit substringToIndex:7] : nil;
}

// An older updater skips files it doesn't know (v1.1.0 dropped app-icons), so a missing file re-offers the release.
static BOOL tweaksInstalled(NSDictionary *latest) {
    if (![installedRelease()[@"digest"] isEqual:latest[@"digest"]]) return NO;
    for (NSString *path in tweaksTargets().allValues)
        if (!exists(path)) return NO;
    return YES;
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

static BOOL tweaksDiffer(NSDictionary *latest) {
    return latest && !tweaksInstalled(latest) && ![stagedRelease()[@"digest"] isEqual:latest[@"digest"]];
}

static BOOL tweaksAvailable(NSDictionary *latest) { return tweaksDiffer(latest) && !sourceNotOlder(latest); }

// Dia quarantines whatever it and its children write, this run included when Dia started it, and Gatekeeper then won't
// let launchd or Dia run an unnotarized diapatch. The release signature has been checked by the time this runs.
static BOOL unquarantine(NSString *path) { return check(@[ @"/usr/bin/xattr", @"-dr", @"com.apple.quarantine", path ]); }

static NSString *versionNumber(NSString *tag) { return [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag; }

static BOOL stageTweaks(void) {
    NSString *problem, *output;
    NSDictionary *latest = latestTweaks(30, &problem);
    if (!latest) return fail(@"%@", problem);
    if ([stagedRelease()[@"digest"] isEqual:latest[@"digest"]]) return say(@"DiaTweaks %@ is ready to install", latest[@"tag"]);
    if (!tweaksDiffer(latest)) return say(@"DiaTweaks %@ is up to date", latest[@"tag"]);
    NSString *source = sourceNotOlder(latest);
    if (source) return say(@"DiaTweaks %@ is older than the source build %@ installed, so it isn't offered", latest[@"tag"], source);

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
        ok = ok && (exists([building stringByAppendingPathComponent:name]) || fail(@"DiaTweaks %@ has no %@, so it can't replace this install", latest[@"tag"], name));
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

static void removeRelay(void) {
    removeAgent(@"com.diapatches.passwords");
    for (NSString *name in @[ @"passwords-helper", @"passwords.sock", @"onepassword.sock" ]) removeTree(inHome(name));
    removeTree(DPCopyFolder);
}

static BOOL applyTweaks(void) {
    // The staged release may since have been replaced or overtaken.
    NSString *problem;
    NSDictionary *latest = stagedRelease() ? latestTweaks(15, &problem) : nil;
    if (latest && tweaksInstalled(latest)) removeTree(gStagedTweaks);
    else if (tweaksAvailable(latest)) stageTweaks();  // a failure still leaves the staged release to install
    NSString *tag = stagedRelease()[@"tag"];
    if (!tag) return removeTree(gStagedTweaks);
    NSDictionary<NSString *, NSString *> *targets = tweaksTargets();
    removeRelay();
    BOOL ok = makeDir(inHome(@"bin")) && unquarantine(gStagedTweaks);
    // The marker tells a resumed apply (files already moved out) from a release that never had them.
    NSString *started = [gStagedTweaks stringByAppendingPathComponent:@".applying"];
    BOOL resumed = exists(started);
    for (NSString *name in targets)
        ok = ok && (resumed || exists([gStagedTweaks stringByAppendingPathComponent:name]) || fail(@"DiaTweaks %@ has no %@, so it can't replace this install", tag, name));
    ok = ok && (resumed || [NSData.data writeToFile:started atomically:YES] || fail(@"cannot write %@", started));
    for (NSString *name in targets) {
        NSString *from = [gStagedTweaks stringByAppendingPathComponent:name];
        ok = ok && (!exists(from) || moveBundle(from, targets[name]));
    }
    ok = ok && moveBundle([gStagedTweaks stringByAppendingPathComponent:@"release.plist"], inHome(@"release.plist"));
    return ok && removeTree(gStagedTweaks) && say(@"installed DiaTweaks %@", tag);
}

static NSString *signatureOf(NSString *app) {
    NSString *output;
    if (run(@[ @"/usr/bin/codesign", @"-dr", @"-", app ], &output) != 0) return nil;
    NSRange range = [output rangeOfString:@"designated => "];
    return range.location == NSNotFound ? nil : trimmed([output substringFromIndex:NSMaxRange(range)]);
}

// Only a changed signature needs the reset: a stale grant stays on and macOS never prompts again.
static void forgetScreenRecordingIfResigned(NSString *before) {
    NSString *bundleID = infoOf(gApp)[@"CFBundleIdentifier"];
    if (env("DIAPATCH_APP") || !bundleID || [before isEqual:signatureOf(gApp)]) return;
    if (run(@[ @"/usr/bin/tccutil", @"reset", @"ScreenCapture", bundleID ], NULL) == 0)
        say(@"Dia's signature changed, so macOS asks again before Dia can share your screen: allow Dia under System Settings > "
            @"Privacy & Security > Screen & System Audio Recording, then reopen Dia");
}

static BOOL apply(void) {
    if (!exists(gStaged)) return YES;
    if (!stagedReady()) return unstage() && fail(@"deleted %@: a stopped run left it there; run `diapatch build` to stage Dia again", gStaged);
    if (appRunning()) return fail(@"Dia is running; quit it, then run `diapatch apply`");
    // An official Dia that isn't the pristine copy was put there by hand: the staged build is older.
    if (claimsOfficial(gApp) && ![buildOf(gApp) isEqual:buildOf(gPristine)])
        return unstage() && say(@"kept the official Dia %@ at %@; run `diapatch install` to patch it", versionOf(gApp), gApp);
    NSString *signature = signatureOf(gApp);
    if (!(moveBundle(gStaged, gApp) && removeTree(gReady))) return NO;
    forgetScreenRecordingIfResigned(signature);
    return say(@"installed patched Dia %@ at %@", versionOf(gApp), gApp);
}

// The patched Dia only loads the dylib it was signed with, so a new dylib means signing Dia again.
static BOOL applyChosen(BOOL dia, BOOL tweaks) {
    if (!dia && !tweaks) dia = YES, tweaks = installedRelease()[@"tag"] != nil;
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
    removeRelay();
    DPForgetApp(gPristine);  // clears a copy registered before diapatch did this
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

static NSString *unpatchableFile(void) { return inHome(@"unpatchable.plist"); }

static NSString *ownDigest(void) { return sha256(NSBundle.mainBundle.executablePath); }

static void rememberUnpatchable(Release *release) {
    NSString *line = [gFailure componentsSeparatedByString:@"\n"].firstObject;
    note(@"Dia %@ can't be patched by this DiaTweaks, so it isn't downloaded automatically again", release.version);
    [@{ @"build" : release.build, @"diapatch" : ownDigest() ?: @"", @"reason" : [@"Couldn’t patch this version: " stringByAppendingString:line ?: @"unknown error"] }
        writeToFile:unpatchableFile() atomically:YES];
}

static NSString *unpatchableReason(Release *release) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:unpatchableFile()];
    NSString *reason = saved[@"reason"];
    return release && [saved[@"build"] isEqual:release.build] && [saved[@"diapatch"] isEqual:ownDigest()] && [reason isKindOfClass:NSString.class] ? reason : nil;
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
        && verifyOfficial(app);
    // Remember only a failed patch: a bad download or a full disk can pass.
    BOOL built = ok && build(app);
    if (ok && !built) rememberUnpatchable(release);
    ok = built && makeDir(gPristine.stringByDeletingLastPathComponent) && moveBundle(app, gPristine) && (DPForgetApp(gPristine), YES);
    removeTree(work);
    if (ok) removeTree(unpatchableFile());
    return ok && say(@"Dia %@ is staged; relaunch Dia or run `diapatch apply` to install it", release.version);
}

#pragma mark - Background updates

static BOOL loadAgent(NSDictionary *agent) {
    NSString *path = agentPlist(agent[@"Label"]);
    NSError *error;
    removeAgent(agent[@"Label"]);
    return makeDir(path.stringByDeletingLastPathComponent)
        && ([agent writeToURL:[NSURL fileURLWithPath:path] error:&error] || fail(@"cannot write %@: %@", path, error.localizedDescription))
        && check(@[ @"/bin/launchctl", @"bootstrap", agentDomain(), path ]);
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
    return loadAgent(agent);
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

// Only a host pointing at this diapatch is ours to remove; the one kept aside goes back.
static void removePasswordsHost(void) {
    for (NSString *file in @[ @"com.apple.passwordmanager.json", @"io.github.fanckush.betterpasswords.bridge.json", @"com.openpasswords.icloud.json", @"com.diapatches.passkeys.json" ]) {
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:[@"Library/Application Support/Google/Chrome/NativeMessagingHosts" stringByAppendingPathComponent:file]];
        NSDictionary *host = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] ?: NSData.data options:0 error:NULL];
        if (![host isKindOfClass:NSDictionary.class] || ![host[@"path"] isEqual:inHome(@"bin/diapatch")]) continue;
        removeTree(path);
        [NSFileManager.defaultManager moveItemAtPath:inHome(file) toPath:path error:NULL];
    }
}

// Deletes only what DiaPatches creates, in case DIAPATCH_HOME points somewhere shared.
static BOOL purge(void) {
    // Mirrors install.sh's link locations.
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
                              @".diatweaks.lock", @".incoming", @"icons", @"app-icons", @"passwords-helper", @"passwords.sock", @"onepassword.sock", @"passwords-launch",
                              @"passkey-helper", @"passkey-helper.lock", @"passkeys-extension", @"passkeys-extension.key", @"last-check", @"unpatchable.plist",
                              @"methods.txt", @"views.txt", @"layout-loops.txt" ])
        if (!discard(inHome(name))) return NO;
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:gHome error:NULL])
        if (([name hasPrefix:@".update-"] || [name hasPrefix:@"little-dia-"]) && !removeTree(inHome(name))) return NO;
    removeSetAside();
    for (NSString *name in @[ @"download", @"release", @"previews" ])
        if (!removeTree([gCache stringByAppendingPathComponent:name])) return NO;
    rmdir(gCache.fileSystemRepresentation);
    if (rmdir(gHome.fileSystemRepresentation) == 0) return say(@"deleted %@", gHome);
    return say(@"kept %@: it holds files DiaPatches did not create", gHome);
}

static BOOL uninstall(BOOL purgeFiles) {
    if (appRunning()) return fail(@"Dia is running; quit it, then run `diapatch uninstall`");
    removeAgent(kAgent);
    removeRelay();
    removePasswordsHost();
    if (!removeTree(DPCopyFolder)) return NO;
    NSString *signature = signatureOf(gApp);
    if (!claimsOfficial(gApp)) {
        NSString *copy = [gPristine stringByAppendingString:@".restore"];
        if (!exists(gPristine)) return fail(@"no official Dia at %@; reinstall Dia from https://www.diabrowser.com", gPristine);
        if (!removeTree(copy) || !clone(gPristine, copy) || !moveBundle(copy, gApp)) return removeTree(copy), NO;
    }
    forgetScreenRecordingIfResigned(signature);
    say(@"%@ is the official Dia %@", gApp, versionOf(gApp));
    return unstage() && (!purgeFiles || purge());
}

static BOOL printJSON(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:NULL];
    printf("%.*s\n", (int)data.length, (const char *)data.bytes);
    return YES;
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
    if (json) return printJSON(status);
    for (NSString *key in @[ @"official", @"installed", @"patched", @"staged", @"feed", @"channel", @"release" ]) {
        id value = status[key];
        if (value == NSNull.null) value = [key isEqualToString:@"feed"] ? problem : @"none";
        else if ([key isEqualToString:@"patched"]) value = [value boolValue] ? @"yes" : @"no";
        printf("%-10s%s\n", key.UTF8String, [value UTF8String]);
    }
    return YES;
}

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
            @"unpatchable" : unpatchableReason(dia) ?: NSNull.null,
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
    return printJSON(result);
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
    "                   install what's staged once PID and Dia have quit, then reopen Dia; --dia or --tweaks limits it,\n"
    "                   and only --tweaks installs a staged DiaTweaks release over a source build\n"
    "  check --json     what's installed, available and staged for Dia and DiaTweaks\n"
    "  set-icon         use the icon chosen in the App Icon tweak\n"
    "  uninstall [--wait PID] [--relaunch] [--purge]\n"
    "                   put the official Dia back; --purge also deletes DiaPatches' files and the diatweaks command\n"
    "  status [--json]  official, installed, staged and offered versions, and the update channel\n"
    "  scheduled        what the background agent runs: check hourly, stage updates and install them while Dia is closed\n"
    "environment: DIAPATCH_IDENTITY (codesigning identity, remembered by install), DIAPATCH_HOME,\n"
    "  DIAPATCH_APP, DIAPATCH_CACHE, DIAPATCH_FEED, DIAPATCH_RELEASES, DIAPATCH_COMMIT (the source commit installed), DIAPATCH_COMPARE, DIATWEAKS_LINK_DIR, DIAPATCH_NO_RELAUNCH (ignore --relaunch),\n"
    "  DIAPATCH_NO_AGENT (install leaves the background update agent alone)\n"
    "  DIAPATCH_APP (also keeps apply and uninstall from clearing Dia's Screen Recording permission)\n";

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
            return DPRunPasswordsHost(gHome, gApp, argc, argv);
        }

        NSString *command = argc > 1 ? @(argv[1]) : @"";
        NSArray<NSString *> *allowed = @{
            @"install" : @[ @"--relaunch" ], @"build" : @[], @"set-icon" : @[], @"update" : @[], @"self-update" : @[], @"status" : @[ @"--json" ],
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
        // Tests patch a copy of Dia: relaunching or quitting by bundle ID could hit the real one.
        if (env("DIAPATCH_NO_RELAUNCH")) [flags removeObject:@"--relaunch"];
        if ([command isEqualToString:@"status"]) return status([flags containsObject:@"--json"]) ? 0 : 1;
        if ([command isEqualToString:@"check"]) return checkUpdates() ? 0 : 1;

        if (pid) setsid();  // Dia is about to quit: leave its process group
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
        removeSetAside(), emptyTrash();
        BOOL ok = [command isEqualToString:@"install"] ? install([flags containsObject:@"--relaunch"]) && installAgent()
            : [command isEqualToString:@"set-icon"]    ? switchIcon()
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
