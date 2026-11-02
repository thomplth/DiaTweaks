// What the original Dia runs as each of its subprocesses while it starts Apple's helper for a host: the first takes the
// host's stdio and becomes the helper, and the rest find the host has stopped listening and quit.
#import <sys/socket.h>
#import <sys/un.h>
#import "Passwords.h"
#import "PasswordsParts.h"

BOOL DPIsPasswordsHandoff(int argc, const char *argv[]) { return getenv(DPHandoffVariable) && argc > 1 && !strncmp(argv[1], "--type=", 7); }

static NSDictionary *readLaunch(int host, uint32_t length) {
    NSMutableData *payload = [NSMutableData dataWithLength:length];
    for (uint32_t got = 0; got < length;) {
        ssize_t n = read(host, (char *)payload.mutableBytes + got, length - got);
        if (n <= 0) return nil;
        got += n;
    }
    NSDictionary *launch = [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];
    return [launch isKindOfClass:NSDictionary.class] && [launch[@"arguments"] isKindOfClass:NSArray.class]
            && [launch[@"environment"] isKindOfClass:NSArray.class] ? launch : nil;
}

static char *const *cStrings(NSArray *strings) {
    const char **list = calloc(strings.count + 1, sizeof *list);
    for (NSUInteger i = 0; i < strings.count; i++) list[i] = [strings[i] isKindOfClass:NSString.class] ? [strings[i] UTF8String] : "";
    return (char *const *)list;
}

int DPRunPasswordsHandoff(void) {
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    int host = socket(AF_UNIX, SOCK_STREAM, 0);
    if (strlcpy(address.sun_path, getenv(DPHandoffVariable), sizeof address.sun_path) >= sizeof address.sun_path
        || connect(host, (struct sockaddr *)&address, sizeof address) != 0)
        return 0;
    uint32_t length = 0;
    int fds[3];
    char control[CMSG_SPACE(sizeof fds)];
    struct iovec iov = { &length, sizeof length };
    struct msghdr message = { .msg_iov = &iov, .msg_iovlen = 1, .msg_control = control, .msg_controllen = sizeof control };
    if (recvmsg(host, &message, MSG_WAITALL) != sizeof length) return 0;
    struct cmsghdr *header = CMSG_FIRSTHDR(&message);
    if (!header || header->cmsg_type != SCM_RIGHTS || header->cmsg_len != CMSG_LEN(sizeof fds)) return 0;
    memcpy(fds, CMSG_DATA(header), sizeof fds);
    NSDictionary *launch = readLaunch(host, length);
    NSString *helper = DPAppleHelper();
    if (!launch || !helper) return 0;

    // Chromium may start this without some of 0-2 open, so what came over the socket can sit where it goes.
    int moved[3];
    for (int i = 0; i < 3; i++) moved[i] = fcntl(fds[i], F_DUPFD, 3), close(fds[i]);
    for (int i = 0; i < 3; i++) dup2(moved[i], i), close(moved[i]);
    fcntl(host, F_SETFD, FD_CLOEXEC);
    execve(helper.fileSystemRepresentation, cStrings([@[ helper ] arrayByAddingObjectsFromArray:launch[@"arguments"]]), cStrings(launch[@"environment"]));
    return 1;
}
