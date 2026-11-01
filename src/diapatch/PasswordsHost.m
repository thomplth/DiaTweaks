// Apple's iCloud Passwords helper carries a launch constraint that only lets browsers signed by their own developers
// start it, so the patched Dia, signed on this Mac, gets it killed at launch. This host stands in for it: browsers Apple
// trusts get the helper itself, and the patched Dia goes through the relay, where the original Dia starts the helper.
#import <poll.h>
#import <sys/socket.h>
#import <sys/un.h>
#import "Passwords.h"
#import "PasswordsParts.h"

static NSString *const kAppleHost = @"/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json";
const char *const DPAppleExtensions[2] = { "chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/",
                                           "chrome-extension://mfbcdcnpokpoajjciilocoachedjkima/" };

BOOL DPIsPasswordsOrigin(const char *origin) {
    return !strcmp(origin, DPAppleExtensions[0]) || !strcmp(origin, DPAppleExtensions[1]);
}

NSString *DPPasswordsSocket(NSString *home) { return [home stringByAppendingPathComponent:@"passwords.sock"]; }

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

// exec keeps the browser that started this as the helper's parent, which is what the launch constraint checks.
int DPRunPasswordsHost(NSString *home, NSString *app, int argc, const char *argv[]) {
    if (!DPRunsPatchedDia(getppid(), app)) {
        NSString *helper = appleHelper();
        if (!helper) return 1;
        argv[0] = helper.fileSystemRepresentation;
        execv(argv[0], (char *const *)argv);
        return 1;
    }
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlcpy(address.sun_path, DPPasswordsSocket(home).fileSystemRepresentation, sizeof address.sun_path) >= sizeof address.sun_path) return 1;
    int relay = socket(AF_UNIX, SOCK_STREAM, 0);
    if (relay < 0 || connect(relay, (struct sockaddr *)&address, sizeof address) != 0) return 1;
    struct pollfd fds[2] = { { .fd = STDIN_FILENO, .events = POLLIN }, { .fd = relay, .events = POLLIN } };
    while (poll(fds, 2, -1) > 0) {
        if (fds[0].revents && !copyAll(STDIN_FILENO, relay)) break;
        if (fds[1].revents && !copyAll(relay, STDOUT_FILENO)) break;
    }
    return 0;
}
