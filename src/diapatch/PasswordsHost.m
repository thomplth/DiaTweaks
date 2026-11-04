// Apple's iCloud Passwords helper carries a launch constraint that only lets browsers signed by their own developers
// start it, and 1Password's helper checks the browser's signature, so neither works from the patched Dia, signed on this
// Mac. This host stands in for them: browsers Apple trusts get Apple's helper itself, the original Dia starts Apple's
// helper on this host's stdio for the patched Dia, and 1Password goes through the relay.
#import <poll.h>
#import <sys/event.h>
#import <sys/socket.h>
#import <sys/un.h>
#import "Passwords.h"
#import "PasswordsParts.h"

static NSString *const kAppleHost = @"/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json";

static const char *const kAppleOrigins[] = { "chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/",
                                             "chrome-extension://mfbcdcnpokpoajjciilocoachedjkima/" };

const DPPasswordsService DPPasswordsServices[DPPasswordsServiceCount] = {
    {
        .origins = { "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/" },
        .host = "com.1password.1password",
        .key =
        "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnHpaUll4uWujpAdbIXOQY2WE6hk8PllsYsnoUaj5qHXwv4IB6A9pONqGaTL2KL20u6E6XVhncY"
        "6Ae6SQSBQqiIkgjPsiG0NDNsDlju/kzBnfimKFC/bpzOrqFqbhswQHifnet5uHlpG97whTzLO3ka0M5aqB9V9mD/0qVXvNgAVVnSTULH254YqpeCcAhmsK"
        "iFZSL6OrOZmCp8kZ/OeOUK9iYWYylL7VcOXVrZf10EPrlaCNXzVk7K35dPuQ7svhA0Pgju3kngB4RLa5Iojhw3IT+B5+m8pisjOSd1oKMrRmhGs7rDhF5I"
        "EtAiVxqVp7uOOMPQj3vrbMDAzf7vqLtQIDAQAB",
        .socket = "onepassword.sock",
    },
};

const DPPasswordsService *DPPasswordsServiceFor(const char *origin) {
    for (const DPPasswordsService *service = DPPasswordsServices; service < DPPasswordsServices + DPPasswordsServiceCount; service++)
        for (const char *const *known = service->origins; *known; known++)
            if (!strcmp(origin, *known)) return service;
    return NULL;
}

static BOOL isAppleOrigin(const char *origin) { return !strcmp(origin, kAppleOrigins[0]) || !strcmp(origin, kAppleOrigins[1]); }

BOOL DPIsPasswordsOrigin(const char *origin) { return isAppleOrigin(origin) || DPPasswordsServiceFor(origin) != NULL; }

NSString *DPPasswordsSocket(NSString *home, const DPPasswordsService *service) { return [home stringByAppendingPathComponent:@(service->socket)]; }

NSString *DPAppleHelper(void) {
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

static void waitForExit(pid_t pid) {
    int queue = kqueue();
    struct kevent change, event;
    EV_SET(&change, pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    if (queue >= 0 && kevent(queue, &change, 1, NULL, 0, NULL) == 0) kevent(queue, NULL, 0, &event, 1, NULL);
}

// Chromium hears the helper has gone from the pipes closing, which they only do once this holds no end of them.
static int runThroughOriginal(NSString *home, int argc, const char *argv[]) {
    pid_t helper = DPStartHelperThroughOriginal(home, argc, argv);
    if (!helper) return 1;
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    waitForExit(helper);
    return 0;
}

// exec keeps the browser that started this as the helper's parent, which is what the launch constraint checks.
int DPRunPasswordsHost(NSString *home, NSString *app, int argc, const char *argv[]) {
    const DPPasswordsService *service = DPPasswordsServiceFor(argv[1]);
    if (!DPRunsPatchedDia(getppid(), app)) {
        if (service) return 1;  // only Apple's host is registered for other browsers
        NSString *helper = DPAppleHelper();
        if (!helper) return 1;
        argv[0] = helper.fileSystemRepresentation;
        execv(argv[0], (char *const *)argv);
        return 1;
    }
    if (!service) return runThroughOriginal(home, argc, argv);
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlcpy(address.sun_path, DPPasswordsSocket(home, service).fileSystemRepresentation, sizeof address.sun_path) >= sizeof address.sun_path) return 1;
    int relay = socket(AF_UNIX, SOCK_STREAM, 0);
    if (relay < 0 || connect(relay, (struct sockaddr *)&address, sizeof address) != 0) return 1;
    struct pollfd fds[2] = { { .fd = STDIN_FILENO, .events = POLLIN }, { .fd = relay, .events = POLLIN } };
    while (poll(fds, 2, -1) > 0) {
        if (fds[0].revents && !copyAll(STDIN_FILENO, relay)) break;
        if (fds[1].revents && !copyAll(relay, STDOUT_FILENO)) break;
    }
    return 0;
}
