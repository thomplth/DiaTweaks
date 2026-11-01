#import <spawn.h>
#import <sys/wait.h>
#import "PasswordsParts.h"

extern char **environ;
int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attrs, int disclaim);  // private: macOS then asks about the copy, not Dia

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

static pid_t gDia;
static NSString *gSession;

static BOOL writeExtension(NSString *folder) {
    NSDictionary *manifest = @{
        @"manifest_version" : @3, @"name" : @"DiaTweaks iCloud Passwords relay", @"version" : @"1", @"key" : kAppleExtensionKey,
        @"permissions" : @[ @"nativeMessaging" ], @"background" : @{ @"service_worker" : @"relay.js" },
    };
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [[NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil] writeToFile:[folder stringByAppendingPathComponent:@"manifest.json"] atomically:YES]
        && [kRelayScript writeToFile:[folder stringByAppendingPathComponent:@"relay.js"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// Its preferences live under CFFIXED_USER_HOME, so the copy never offers to update itself or shows its intro.
static void quieten(NSString *data) {
    NSString *preferences = [data stringByAppendingPathComponent:@"Library/Preferences/company.thebrowser.dia"];
    for (NSArray *setting in @[ @[ @"SUEnableAutomaticChecks", @"NO" ], @[ @"SUAutomaticallyUpdate", @"NO" ], @[ @"hasPresentedOnboardingIntro", @"YES" ] ])
        [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:@[ @"write", preferences, setting[0], @"-bool", setting[1] ]] waitUntilExit];
}

static int highFD(int fd) {
    int moved = fcntl(fd, F_DUPFD_CLOEXEC, 10);
    close(fd);
    return moved;
}

static pid_t launch(NSString *home) {
    NSString *data = [home stringByAppendingPathComponent:@"passwords-helper"], *extension = [data stringByAppendingPathComponent:@"extension"];
    [NSFileManager.defaultManager createDirectoryAtPath:data withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions : @0700 } error:nil];
    if (!writeExtension(extension)) return 0;
    quieten(data);
    int toDia[2], fromDia[2];
    if (pipe(toDia) || pipe(fromDia)) return 0;
    toDia[0] = highFD(toDia[0]), toDia[1] = highFD(toDia[1]), fromDia[0] = highFD(fromDia[0]), fromDia[1] = highFD(fromDia[1]);

    NSString *app = [home stringByAppendingPathComponent:@"pristine/Dia.app/Contents/MacOS/Dia"];
    NSString *profile = [@"--user-data-dir=" stringByAppendingString:[data stringByAppendingPathComponent:@"ud"]];
    NSString *load = [@"--load-extension=" stringByAppendingString:extension];
    const char *argv[] = { app.fileSystemRepresentation, profile.UTF8String, load.UTF8String, "--remote-debugging-pipe", "--no-startup-window", "--mute-audio", NULL };
    NSMutableArray<NSString *> *environment = [NSMutableArray arrayWithObject:[@"CFFIXED_USER_HOME=" stringByAppendingString:data]];
    for (char **e = environ; *e; e++) [environment addObject:@(*e)];
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
    DPDevToolsAttach(toDia[1], fromDia[0]);
    return pid;
}

static NSString *relayWorker(void) {
    for (int tries = 0; tries < 120; tries++, usleep(250000))
        for (NSDictionary *target in DPDevToolsAsk(@"Target.getTargets", nil, nil)[@"result"][@"targetInfos"])
            if ([target[@"type"] isEqual:@"service_worker"] && [target[@"url"] hasPrefix:@(DPAppleExtensions[0])]) return target[@"targetId"];
    return nil;
}

BOOL DPCopyStart(NSString *home) {
    gDia = launch(home);
    NSString *worker = gDia ? relayWorker() : nil;
    gSession = worker ? DPDevToolsAsk(@"Target.attachToTarget", @{ @"targetId" : worker, @"flatten" : @YES }, nil)[@"result"][@"sessionId"] : nil;
    return gSession && DPDevToolsAsk(@"Runtime.addBinding", @{ @"name" : @"relayOut" }, gSession);
}

void DPCopyEvaluate(NSString *expression) { DPDevToolsCall(@"Runtime.evaluate", @{ @"expression" : expression }, gSession); }

void DPCopyQuit(void) {
    if (!gDia) return;
    DPDevToolsCall(@"Browser.close", nil, nil);
    for (int i = 0; i < 50 && waitpid(gDia, NULL, WNOHANG) == 0; i++) usleep(100000);
    kill(gDia, SIGKILL);
    gDia = 0;
}
