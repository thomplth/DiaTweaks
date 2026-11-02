// Apple's iCloud Passwords helper carries a launch constraint that only lets browsers signed by their own developers
// start it, so the patched Dia, signed on this Mac, gets it killed at launch. This host stands in for it: browsers Apple
// trusts get the helper itself, and for the patched Dia the original Dia starts the helper on this host's stdio.
#import <sys/event.h>
#import "Passwords.h"
#import "PasswordsParts.h"

static NSString *const kAppleHost = @"/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json";
const char *const DPAppleExtensions[2] = { "chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/",
                                           "chrome-extension://mfbcdcnpokpoajjciilocoachedjkima/" };

BOOL DPIsPasswordsOrigin(const char *origin) {
    return !strcmp(origin, DPAppleExtensions[0]) || !strcmp(origin, DPAppleExtensions[1]);
}

NSString *DPAppleHelper(void) {
    NSDictionary *host = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:kAppleHost] ?: NSData.data options:0 error:nil];
    return [host isKindOfClass:NSDictionary.class] && [host[@"path"] isKindOfClass:NSString.class] ? host[@"path"] : nil;
}

static void waitForExit(pid_t pid) {
    int queue = kqueue();
    struct kevent change, event;
    EV_SET(&change, pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    if (queue >= 0 && kevent(queue, &change, 1, NULL, 0, NULL) == 0) kevent(queue, NULL, 0, &event, 1, NULL);
}

// exec keeps the browser that started this as the helper's parent, which is what the launch constraint checks.
int DPRunPasswordsHost(NSString *home, NSString *app, int argc, const char *argv[]) {
    if (!DPRunsPatchedDia(getppid(), app)) {
        NSString *helper = DPAppleHelper();
        if (!helper) return 1;
        argv[0] = helper.fileSystemRepresentation;
        execv(argv[0], (char *const *)argv);
        return 1;
    }
    pid_t helper = DPStartHelperThroughOriginal(home, argc, argv);
    if (!helper) return 1;
    // Chromium hears the helper has gone from the pipes closing, which they only do once this holds no end of them.
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    waitForExit(helper);
    return 0;
}
