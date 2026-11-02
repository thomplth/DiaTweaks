// The helper's launch constraint only looks at its parent as the helper starts. So the original Dia runs just until it
// starts its first subprocess, this diapatch, which takes the host's stdio and becomes the helper; Dia is then quit.
#import <libproc.h>
#import <poll.h>
#import <spawn.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/wait.h>
#import "PasswordsParts.h"

extern char **environ;
int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attrs, int disclaim);  // private: macOS then asks about the copy, not Dia

const char *const DPHandoffVariable = "DIAPATCH_PASSWORDS_HANDOFF";
static const NSTimeInterval kStartupTimeout = 20;

static void logLine(NSString *home, NSString *line) {
    FILE *log = fopen([home stringByAppendingPathComponent:@"diapatch.log"].fileSystemRepresentation, "a");
    if (!log) return;
    char stamp[20];
    time_t now = time(NULL);
    strftime(stamp, sizeof stamp, "%F %T", localtime(&now));
    fprintf(log, "%s passwords[%d] %s\n", stamp, getpid(), line.UTF8String);
    fclose(log);
}

static NSArray<NSString *> *strings(const char *const *list, int count) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (int i = 0; count < 0 ? list[i] != NULL : i < count; i++) {
        NSString *string = [NSString stringWithUTF8String:list[i]];
        if (string) [result addObject:string];
    }
    return result;
}

static int listenAt(NSString *path) {
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof address.sun_path) >= sizeof address.sun_path) return -1;
    unlink(address.sun_path);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd >= 0 && bind(fd, (struct sockaddr *)&address, sizeof address) == 0 && listen(fd, 8) == 0) return fd;
    if (fd >= 0) close(fd);
    return -1;
}

// Headless and in a home of its own, it opens no windows and leaves the patched Dia's settings alone.
static pid_t launchOriginal(NSString *home, NSString *folder, NSString *socket) {
    NSString *dia = [home stringByAppendingPathComponent:@"pristine/Dia.app/Contents/MacOS/Dia"];
    NSString *profile = [@"--user-data-dir=" stringByAppendingString:[folder stringByAppendingPathComponent:@"ud"]];
    NSString *subprocess = [@"--browser-subprocess-path=" stringByAppendingString:NSBundle.mainBundle.executablePath];
    const char *argv[] = { dia.fileSystemRepresentation, profile.UTF8String, subprocess.UTF8String, "--headless=new", "--no-first-run",
                           "--no-default-browser-check", "--use-mock-keychain", "--mute-audio", NULL };
    NSMutableArray<NSString *> *environment = [NSMutableArray arrayWithObjects:[@"CFFIXED_USER_HOME=" stringByAppendingString:folder],
                                                                               [NSString stringWithFormat:@"%s=%@", DPHandoffVariable, socket], nil];
    [environment addObjectsFromArray:strings((const char *const *)environ, -1)];
    const char **envp = calloc(environment.count + 1, sizeof *envp);
    for (NSUInteger i = 0; i < environment.count; i++) envp[i] = environment[i].UTF8String;

    posix_spawn_file_actions_t files;
    posix_spawn_file_actions_init(&files);
    for (int fd = 0; fd < 3; fd++) posix_spawn_file_actions_addopen(&files, fd, "/dev/null", fd ? O_WRONLY : O_RDONLY, 0);
    posix_spawnattr_t attrs;
    posix_spawnattr_init(&attrs);
    posix_spawnattr_setflags(&attrs, POSIX_SPAWN_CLOEXEC_DEFAULT);  // keeps the host's stdio and socket out of Dia
    responsibility_spawnattrs_setdisclaim(&attrs, 1);
    pid_t pid = 0;
    int status = posix_spawn(&pid, argv[0], &files, &attrs, (char *const *)argv, (char *const *)envp);
    posix_spawn_file_actions_destroy(&files);
    posix_spawnattr_destroy(&attrs);
    free(envp);
    return status == 0 ? pid : 0;
}

// Only this diapatch, as a subprocess of the original Dia started here, gets the host's stdio.
static int acceptSubprocess(int listener, pid_t *dia, pid_t *peer) {
    for (NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kStartupTimeout]; deadline.timeIntervalSinceNow > 0;) {
        struct pollfd ready = { .fd = listener, .events = POLLIN };
        if (poll(&ready, 1, 100) <= 0) {
            if (waitpid(*dia, NULL, WNOHANG) == *dia) return *dia = 0, -1;
            continue;
        }
        int client = accept(listener, NULL, NULL);
        audit_token_t token;
        socklen_t tokenLength = sizeof token, pidLength = sizeof *peer;
        if (client >= 0 && getsockopt(client, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &tokenLength) == 0
            && getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, peer, &pidLength) == 0 && DPParentOf(*peer) == *dia && DPRunsThisDiapatch(token))
            return client;
        if (client >= 0) close(client);
    }
    return -1;
}

static BOOL handOver(int client, int argc, const char *argv[]) {
    NSDictionary *launch = @{ @"arguments" : strings(argv + 1, argc - 1), @"environment" : strings((const char *const *)environ, -1) };
    NSData *payload = [NSJSONSerialization dataWithJSONObject:launch options:0 error:nil];
    uint32_t length = (uint32_t)payload.length;
    int fds[3] = { STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO };
    char control[CMSG_SPACE(sizeof fds)] = { 0 };
    struct iovec iov = { &length, sizeof length };
    struct msghdr message = { .msg_iov = &iov, .msg_iovlen = 1, .msg_control = control, .msg_controllen = sizeof control };
    struct cmsghdr *header = CMSG_FIRSTHDR(&message);
    *header = (struct cmsghdr){ .cmsg_len = CMSG_LEN(sizeof fds), .cmsg_level = SOL_SOCKET, .cmsg_type = SCM_RIGHTS };
    memcpy(CMSG_DATA(header), fds, sizeof fds);
    if (sendmsg(client, &message, 0) != sizeof length) return NO;
    for (NSUInteger sent = 0; sent < payload.length;) {
        ssize_t n = write(client, (const char *)payload.bytes + sent, payload.length - sent);
        if (n <= 0) return NO;
        sent += n;
    }
    return YES;
}

// The subprocess's end of the socket closes as it execs, or as it gives up.
static BOOL becameHelper(int client, pid_t peer) {
    char byte, path[PROC_PIDPATHINFO_MAXSIZE], helper[PATH_MAX];
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &(struct timeval){ .tv_sec = 5 }, sizeof(struct timeval));
    while (read(client, &byte, 1) > 0) {}
    if (!realpath(DPAppleHelper().fileSystemRepresentation, helper)) return NO;
    for (int tries = 0; tries < 50; tries++, usleep(10000))
        if (proc_pidpath(peer, path, sizeof path) > 0 && !strcmp(path, helper)) return YES;
    return NO;
}

pid_t DPStartHelperThroughOriginal(NSString *home, int argc, const char *argv[]) {
    NSString *launches = [home stringByAppendingPathComponent:@"passwords-launch"];
    NSString *folder = [launches stringByAppendingPathComponent:@(getpid()).stringValue], *socket = [folder stringByAppendingString:@".sock"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions : @0700 } error:nil];
    chmod(launches.fileSystemRepresentation, 0700);
    NSDate *start = NSDate.date;
    int listener = listenAt(socket);
    pid_t dia = listener >= 0 ? launchOriginal(home, folder, socket) : 0, peer = 0, helper = 0;
    int client = dia ? acceptSubprocess(listener, &dia, &peer) : -1;
    if (listener >= 0) close(listener);
    unlink(socket.fileSystemRepresentation);
    if (client >= 0 && handOver(client, argc, argv) && becameHelper(client, peer)) helper = peer;
    if (client >= 0) close(client);
    if (dia) kill(dia, SIGKILL), waitpid(dia, NULL, 0);
    [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
    logLine(home, [NSString stringWithFormat:helper ? @"the original Dia started Apple's helper in %.2f s" : @"the original Dia didn't start Apple's helper (%.2f s)",
                                             -start.timeIntervalSinceNow]);
    return helper;
}
