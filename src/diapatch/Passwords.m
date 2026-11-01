// Apple's iCloud Passwords helper carries a launch constraint that only lets browsers signed by their own developers
// start it, so the patched Dia, signed on this Mac, gets it killed at launch. The relay has the original Dia start it
// instead: one windowless copy, driven over its DevTools pipe, opens a native port for each port the patched Dia opens.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <launch.h>
#import <libproc.h>
#import <poll.h>
#import <spawn.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/wait.h>
#import "Passwords.h"

NSString *const DPPasswordsAgent = @"com.diapatches.passwords";

extern char **environ;
int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attrs, int disclaim);  // private: macOS then asks about the copy, not Dia

static NSString *const kAppleHost = @"/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json";
static const char *const kAppleExtensions[] = { "chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/",
                                                "chrome-extension://mfbcdcnpokpoajjciilocoachedjkima/" };
// The Chrome Web Store key of Apple's extension. The helper only answers ports from Apple's extension IDs, so the relay
// extension in the original Dia is loaded under this key.
static NSString *const kAppleExtensionKey =
    @"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAk4xPYZla5XqlDN0PPiLCQAYRqdaR06jSl3sntEE5jHoe7XldFqhsdBSp4L8mozwjCwi6z5YtEpTV1L2k4WYmDu"
    @"iwoH7YKGlQD/YbC8QMcPvGLWOr8WYfXWtECKv0Nx7Tahk8nCIDWgJVm8YmPIDhPv4o5VVrq6aUveCKvTOskHWFyRzSTC2VKpzIVX7F65UzqqOmqLfMpo6lfaLcKSC7G6oQLA"
    @"/wS7hcGZEwZ11si6XWR4o/hDuUSt6zdacy/sc7H80eH3lMnEmvb6HoB7+KvxfGIU7dqRmhA/w/X0qkiIJYeoo4tZrNxBj7TTLz9hnHUbMRwJqsoIU+pkoprgFWDQIDAQAB";
static NSString *const kRelayScript =
    @"const ports = new Map();\n"
     "globalThis.relayOpen = (id) => {\n"
     "  const port = chrome.runtime.connectNative('com.apple.passwordmanager');\n"
     "  ports.set(id, port);\n"
     "  port.onMessage.addListener((message) => relayOut(JSON.stringify({ id, message })));\n"
     "  port.onDisconnect.addListener(() => { ports.delete(id); relayOut(JSON.stringify({ id, closed: true })); });\n"
     "};\n"
     "globalThis.relayPost = (id, message) => ports.get(id)?.postMessage(message);\n"
     "globalThis.relayClose = (id) => { ports.get(id)?.disconnect(); ports.delete(id); };\n";
static const uint32_t kMaxFrame = 64 << 20;  // Chromium's own limit for messages to a host
static const NSTimeInterval kIdleQuit = 20;    // before Chromium would stop the relay's idle service worker

BOOL DPIsPasswordsOrigin(const char *origin) {
    for (size_t i = 0; i < sizeof kAppleExtensions / sizeof *kAppleExtensions; i++)
        if (!strcmp(origin, kAppleExtensions[i])) return YES;
    return NO;
}

static NSString *socketPath(NSString *home) { return [home stringByAppendingPathComponent:@"passwords.sock"]; }

NSDictionary *DPPasswordsAgentPlist(NSString *home, NSString *diapatch, NSDictionary *environment) {
    return @{
        @"Label" : DPPasswordsAgent,
        @"ProgramArguments" : @[ diapatch, @"passwords-relay" ],
        @"EnvironmentVariables" : environment,
        @"Sockets" : @{ @"Listener" : @{ @"SockPathName" : socketPath(home), @"SockPathMode" : @0600 } },
        @"ProcessType" : @"Interactive",
    };
}

#pragma mark - Code identity

static NSData *cdhashOfStatic(NSString *path) {
    SecStaticCodeRef code = NULL;
    CFDictionaryRef info = NULL;
    NSData *cdhash = nil;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:path], kSecCSDefaultFlags, &code) == errSecSuccess
        && SecStaticCodeCheckValidity(code, kSecCSDoNotValidateResources, NULL) == errSecSuccess
        && SecCodeCopySigningInformation(code, kSecCSDefaultFlags, &info) == errSecSuccess)
        cdhash = ((__bridge NSDictionary *)info)[(__bridge NSString *)kSecCodeInfoUnique];
    if (info) CFRelease(info);
    if (code) CFRelease(code);
    return cdhash;
}

static NSData *cdhashOfSelf(void) {
    SecCodeRef code = NULL;
    SecStaticCodeRef staticCode = NULL;
    CFDictionaryRef info = NULL;
    NSData *cdhash = nil;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &code) == errSecSuccess && SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &staticCode) == errSecSuccess
        && SecCodeCopySigningInformation(staticCode, kSecCSDefaultFlags, &info) == errSecSuccess)
        cdhash = ((__bridge NSDictionary *)info)[(__bridge NSString *)kSecCodeInfoUnique];
    if (info) CFRelease(info);
    if (staticCode) CFRelease(staticCode);
    if (code) CFRelease(code);
    return cdhash;
}

static BOOL runs(NSDictionary *guest, NSData *cdhash) {
    if (!cdhash) return NO;
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < cdhash.length; i++) [hex appendFormat:@"%02x", ((const uint8_t *)cdhash.bytes)[i]];
    SecCodeRef code = NULL;
    SecRequirementRef requirement = NULL;
    BOOL matches = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)guest, kSecCSDefaultFlags, &code) == errSecSuccess
        && SecRequirementCreateWithString((__bridge CFStringRef)[NSString stringWithFormat:@"cdhash H\"%@\"", hex], kSecCSDefaultFlags, &requirement) == errSecSuccess
        && SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement) == errSecSuccess;
    if (requirement) CFRelease(requirement);
    if (code) CFRelease(code);
    return matches;
}

static NSString *executableOf(NSString *app) { return [app stringByAppendingPathComponent:@"Contents/MacOS/Dia"]; }

static BOOL isPatchedDia(pid_t pid, NSString *app) {
    return runs(@{ (__bridge NSString *)kSecGuestAttributePid : @(pid) }, cdhashOfStatic(executableOf(app)));
}

static pid_t parentOf(pid_t pid) {
    struct proc_bsdinfo info;
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) == sizeof info ? (pid_t)info.pbi_ppid : 0;
}

#pragma mark - Host

static NSString *appleHelper(void) {
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:kAppleHost] ?: NSData.data options:0 error:nil];
    return [host isKindOfClass:NSDictionary.class] && [host[@"path"] isKindOfClass:NSString.class] ? host[@"path"] : nil;
}

static BOOL copyAll(int from, int to) {
    char buffer[65536];
    ssize_t got = read(from, buffer, sizeof buffer);
    for (ssize_t sent = 0, n; sent < got; sent += n)
        if ((n = write(to, buffer + sent, got - sent)) <= 0) return NO;
    return got > 0;
}

// The host is registered where every Chromium browser looks, so a browser Apple trusts gets Apple's helper itself: exec
// keeps that browser as the helper's parent. Only the patched Dia goes through the relay, which checks it's the caller.
int DPRunPasswordsHost(NSString *home, NSString *app, int argc, const char *argv[]) {
    if (!isPatchedDia(getppid(), app)) {
        NSString *helper = appleHelper();
        if (!helper) return 1;
        argv[0] = helper.fileSystemRepresentation;
        execv(argv[0], (char *const *)argv);
        return 1;
    }
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlcpy(address.sun_path, socketPath(home).fileSystemRepresentation, sizeof address.sun_path) >= sizeof address.sun_path) return 1;
    int relay = socket(AF_UNIX, SOCK_STREAM, 0);
    if (relay < 0 || connect(relay, (struct sockaddr *)&address, sizeof address) != 0) return 1;
    struct pollfd fds[2] = { { .fd = STDIN_FILENO, .events = POLLIN }, { .fd = relay, .events = POLLIN } };
    while (poll(fds, 2, -1) > 0) {
        if (fds[0].revents && !copyAll(STDIN_FILENO, relay)) break;
        if (fds[1].revents && !copyAll(relay, STDOUT_FILENO)) break;
    }
    return 0;
}

#pragma mark - Relay

typedef struct {
    int fd;
    int id;
    NSMutableData *pending;
} Client;

static int gToDia = -1, gFromDia = -1, gNextCall, gNextClient;
static pid_t gDia;
static NSString *gSession;
static NSMutableData *gFromDiaBuffer;
static NSMutableArray<NSDictionary *> *gDiaMessages;
static NSMutableDictionary<NSNumber *, NSValue *> *gClients;

static void callDia(NSString *method, NSDictionary *params, BOOL inSession) {
    NSMutableDictionary *message = [@{ @"id" : @(++gNextCall), @"method" : method, @"params" : params ?: @{} } mutableCopy];
    if (inSession) message[@"sessionId"] = gSession;
    NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:message options:0 error:nil] mutableCopy];
    [data appendBytes:"" length:1];
    for (NSUInteger sent = 0; sent < data.length;) {
        ssize_t n = write(gToDia, (const char *)data.bytes + sent, data.length - sent);
        if (n <= 0) exit(1);  // quitCopy runs at exit
        sent += n;
    }
}

static BOOL readFromDia(void) {
    char buffer[65536];
    ssize_t got = read(gFromDia, buffer, sizeof buffer);
    if (got <= 0) return NO;
    [gFromDiaBuffer appendBytes:buffer length:got];
    for (NSRange end; (end = [gFromDiaBuffer rangeOfData:[NSData dataWithBytes:"" length:1] options:0 range:NSMakeRange(0, gFromDiaBuffer.length)]).location != NSNotFound;) {
        id message = [NSJSONSerialization JSONObjectWithData:[gFromDiaBuffer subdataWithRange:NSMakeRange(0, end.location)] options:0 error:nil];
        [gFromDiaBuffer replaceBytesInRange:NSMakeRange(0, end.location + 1) withBytes:NULL length:0];
        if ([message isKindOfClass:NSDictionary.class]) [gDiaMessages addObject:message];
    }
    return YES;
}

static NSDictionary *awaitReply(int call, int seconds) {
    for (NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds]; until.timeIntervalSinceNow > 0;) {
        for (NSDictionary *message in gDiaMessages)
            if ([message[@"id"] intValue] == call) {
                [gDiaMessages removeObject:message];
                return message;
            }
        struct pollfd fd = { .fd = gFromDia, .events = POLLIN };
        if (poll(&fd, 1, 250) > 0 && !readFromDia()) return nil;
    }
    return nil;
}

static NSDictionary *askDia(NSString *method, NSDictionary *params, BOOL inSession) {
    callDia(method, params, inSession);
    return awaitReply(gNextCall, 15);
}

static int highFD(int fd) {
    int moved = fcntl(fd, F_DUPFD_CLOEXEC, 10);
    close(fd);
    return moved;
}

static BOOL writeRelayExtension(NSString *folder) {
    NSDictionary *manifest = @{
        @"manifest_version" : @3, @"name" : @"DiaTweaks iCloud Passwords relay", @"version" : @"1", @"key" : kAppleExtensionKey,
        @"permissions" : @[ @"nativeMessaging" ], @"background" : @{ @"service_worker" : @"relay.js" },
    };
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [[NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil] writeToFile:[folder stringByAppendingPathComponent:@"manifest.json"] atomically:YES]
        && [kRelayScript writeToFile:[folder stringByAppendingPathComponent:@"relay.js"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// Its own preferences live under CFFIXED_USER_HOME, so the copy never offers to update itself or shows its intro.
static void quietenCopy(NSString *data) {
    NSString *preferences = [data stringByAppendingPathComponent:@"Library/Preferences/company.thebrowser.dia"];
    for (NSArray *setting in @[ @[ @"SUEnableAutomaticChecks", @"NO" ], @[ @"SUAutomaticallyUpdate", @"NO" ], @[ @"hasPresentedOnboardingIntro", @"YES" ] ])
        [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:@[ @"write", preferences, setting[0], @"-bool", setting[1] ]] waitUntilExit];
}

static pid_t launchCopy(NSString *home) {
    NSString *data = [home stringByAppendingPathComponent:@"passwords-helper"], *extension = [data stringByAppendingPathComponent:@"extension"];
    [NSFileManager.defaultManager createDirectoryAtPath:data withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions : @0700 } error:nil];
    if (!writeRelayExtension(extension)) return 0;
    quietenCopy(data);

    int toDia[2], fromDia[2];
    if (pipe(toDia) || pipe(fromDia)) return 0;
    toDia[0] = highFD(toDia[0]), toDia[1] = highFD(toDia[1]), fromDia[0] = highFD(fromDia[0]), fromDia[1] = highFD(fromDia[1]);
    NSString *app = [home stringByAppendingPathComponent:@"pristine/Dia.app/Contents/MacOS/Dia"];
    NSString *profile = [@"--user-data-dir=" stringByAppendingString:[data stringByAppendingPathComponent:@"ud"]];
    NSString *load = [@"--load-extension=" stringByAppendingString:extension];
    const char *argv[] = { app.fileSystemRepresentation, profile.UTF8String, load.UTF8String, "--remote-debugging-pipe", "--no-startup-window", "--mute-audio", NULL };
    NSMutableArray<NSString *> *environment = [NSMutableArray array];
    for (char **e = environ; *e; e++) [environment addObject:@(*e)];
    [environment addObject:[@"CFFIXED_USER_HOME=" stringByAppendingString:data]];
    const char **envp = calloc(environment.count + 1, sizeof *envp);
    for (NSUInteger i = 0; i < environment.count; i++) envp[i] = environment[i].UTF8String;

    posix_spawn_file_actions_t files;
    posix_spawn_file_actions_init(&files);
    posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&files, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&files, 2, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_adddup2(&files, toDia[0], 3);
    posix_spawn_file_actions_adddup2(&files, fromDia[1], 4);
    posix_spawnattr_t attrs;
    posix_spawnattr_init(&attrs);
    posix_spawnattr_setflags(&attrs, POSIX_SPAWN_CLOEXEC_DEFAULT);  // keeps the relay's sockets out of Dia
    responsibility_spawnattrs_setdisclaim(&attrs, 1);
    pid_t pid = 0;
    int status = posix_spawn(&pid, argv[0], &files, &attrs, (char *const *)argv, (char *const *)envp);
    free(envp);
    close(toDia[0]);
    close(fromDia[1]);
    if (status != 0) return 0;
    gToDia = toDia[1];
    gFromDia = fromDia[0];
    return pid;
}

static NSString *relayWorker(void) {
    for (int tries = 0; tries < 120; tries++, usleep(250000))
        for (NSDictionary *target in askDia(@"Target.getTargets", nil, NO)[@"result"][@"targetInfos"])
            if ([target[@"type"] isEqual:@"service_worker"] && [target[@"url"] hasPrefix:@(kAppleExtensions[0])]) return target[@"targetId"];
    return nil;
}

// The peer must be this diapatch, started by the patched Dia, so nothing else on the Mac gets the original Dia's
// standing with Apple's helper.
static BOOL trustedPeer(int fd, NSString *app) {
    audit_token_t token;
    socklen_t length = sizeof token;
    pid_t pid = 0;
    socklen_t pidLength = sizeof pid;
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) != 0 || getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidLength) != 0) return NO;
    return runs(@{ (__bridge NSString *)kSecGuestAttributeAudit : [NSData dataWithBytes:&token length:sizeof token] }, cdhashOfSelf())
        && isPatchedDia(parentOf(pid), app);
}

static void evaluate(NSString *expression) { callDia(@"Runtime.evaluate", @{ @"expression" : expression }, YES); }

static void dropClient(int id, BOOL tellDia) {
    NSValue *value = gClients[@(id)];
    if (!value) return;
    Client *client = value.pointerValue;
    close(client->fd);
    [gClients removeObjectForKey:@(id)];
    free(client);
    if (tellDia) evaluate([NSString stringWithFormat:@"relayClose(%d)", id]);
}

static BOOL writeFrame(int fd, NSData *json) {
    uint32_t length = (uint32_t)json.length;
    NSMutableData *frame = [NSMutableData dataWithBytes:&length length:4];
    [frame appendData:json];
    for (NSUInteger sent = 0; sent < frame.length;) {
        ssize_t n = write(fd, (const char *)frame.bytes + sent, frame.length - sent);
        if (n <= 0) return NO;
        sent += n;
    }
    return YES;
}

// Messages are parsed and serialized again before they become JavaScript, so a frame can only ever be a JSON value.
static BOOL forwardFrames(Client *client) {
    char buffer[65536];
    ssize_t got = read(client->fd, buffer, sizeof buffer);
    if (got <= 0) return NO;
    [client->pending appendBytes:buffer length:got];
    while (client->pending.length >= 4) {
        uint32_t length;
        memcpy(&length, client->pending.bytes, 4);
        if (length > kMaxFrame) return NO;
        if (client->pending.length < 4 + length) break;
        id message = [NSJSONSerialization JSONObjectWithData:[client->pending subdataWithRange:NSMakeRange(4, length)] options:NSJSONReadingFragmentsAllowed error:nil];
        [client->pending replaceBytesInRange:NSMakeRange(0, 4 + length) withBytes:NULL length:0];
        if (!message) return NO;
        NSData *json = [NSJSONSerialization dataWithJSONObject:message options:NSJSONWritingFragmentsAllowed error:nil];
        evaluate([NSString stringWithFormat:@"relayPost(%d, %@)", client->id, [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]]);
    }
    return YES;
}

static BOOL deliverFromDia(void) {
    NSArray *messages = [gDiaMessages copy];
    [gDiaMessages removeAllObjects];
    for (NSDictionary *message in messages) {
        if ([message[@"method"] isEqual:@"Target.detachedFromTarget"]) return NO;
        if (![message[@"method"] isEqual:@"Runtime.bindingCalled"] || ![message[@"params"][@"name"] isEqual:@"relayOut"]) continue;
        NSDictionary *out = [NSJSONSerialization JSONObjectWithData:[message[@"params"][@"payload"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        int id = [out[@"id"] intValue];
        Client *client = [gClients[@(id)] pointerValue];
        if (!client) continue;
        if (out[@"closed"] || !writeFrame(client->fd, [NSJSONSerialization dataWithJSONObject:out[@"message"] options:NSJSONWritingFragmentsAllowed error:nil]))
            dropClient(id, NO);
    }
    return YES;
}

static void quitCopy(void) {
    if (!gDia) return;
    if (gToDia >= 0) {
        int toDia = gToDia;
        gToDia = -1;
        NSData *close = [@"{\"id\":0,\"method\":\"Browser.close\"}" dataUsingEncoding:NSUTF8StringEncoding];
        write(toDia, close.bytes, close.length) == (ssize_t)close.length && write(toDia, "", 1);
    }
    for (int i = 0; i < 50 && waitpid(gDia, NULL, WNOHANG) == 0; i++) usleep(100000);
    kill(gDia, SIGKILL);
    gDia = 0;
}

static BOOL startCopy(NSString *home) {
    gDia = launchCopy(home);
    NSString *worker = gDia ? relayWorker() : nil;
    gSession = worker ? askDia(@"Target.attachToTarget", @{ @"targetId" : worker, @"flatten" : @YES }, NO)[@"result"][@"sessionId"] : nil;
    return gSession && askDia(@"Runtime.addBinding", @{ @"name" : @"relayOut" }, YES);
}

int DPRunPasswordsRelay(NSString *home, NSString *app) {
    signal(SIGPIPE, SIG_IGN);
    int *listeners = NULL;
    size_t listenerCount = 0;
    if (launch_activate_socket("Listener", &listeners, &listenerCount) != 0 || !listenerCount) return 1;
    gFromDiaBuffer = [NSMutableData data];
    gDiaMessages = [NSMutableArray array];
    gClients = [NSMutableDictionary dictionary];

    atexit(quitCopy);

    NSDate *idleSince = NSDate.date;
    while (gClients.count || -idleSince.timeIntervalSinceNow < kIdleQuit) {
        NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
        struct pollfd fds[listenerCount + 1 + gClients.count];
        nfds_t count = 0;
        for (size_t i = 0; i < listenerCount; i++) fds[count++] = (struct pollfd){ .fd = listeners[i], .events = POLLIN };
        fds[count++] = (struct pollfd){ .fd = gFromDia, .events = POLLIN };
        for (NSNumber *id in gClients) {
            fds[count++] = (struct pollfd){ .fd = ((Client *)gClients[id].pointerValue)->fd, .events = POLLIN };
            [ids addObject:id];
        }
        if (poll(fds, count, 1000) < 0 && errno != EINTR) break;
        for (size_t i = 0; i < listenerCount; i++) {
            if (!fds[i].revents) continue;
            int fd = accept(listeners[i], NULL, NULL);
            if (fd < 0) continue;
            // The copy only starts for a trusted caller, so nothing else can make it run.
            if (!trustedPeer(fd, app) || (!gSession && !startCopy(home))) {
                close(fd);
                if (gDia && !gSession) return 1;
                continue;
            }
            Client *client = calloc(1, sizeof *client);
            *client = (Client){ .fd = fd, .id = ++gNextClient, .pending = [NSMutableData data] };
            gClients[@(client->id)] = [NSValue valueWithPointer:client];
            evaluate([NSString stringWithFormat:@"relayOpen(%d)", client->id]);
        }
        if ((fds[listenerCount].revents && !readFromDia()) || !deliverFromDia()) break;
        for (NSUInteger i = 0; i < ids.count; i++) {
            Client *client = [gClients[ids[i]] pointerValue];
            if (client && fds[listenerCount + 1 + i].revents && !forwardFrames(client)) dropClient(ids[i].intValue, YES);
        }
        if (gClients.count) idleSince = NSDate.date;
    }
    for (NSNumber *id in gClients.allKeys) dropClient(id.intValue, NO);
    return 0;
}
