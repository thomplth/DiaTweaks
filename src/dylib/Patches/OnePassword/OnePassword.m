#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#include <spawn.h>

extern DPPatch DPOnePassword;

static const char *DPDiapatch(void) {
    static char path[PATH_MAX];
    static dispatch_once_t once;
    dispatch_once(&once, ^{ strlcpy(path, DPAppSupport(@"DiaPatches/bin/diapatch").fileSystemRepresentation, sizeof path); });
    return path;
}

static int DPSpawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *files, const posix_spawnattr_t *attrs, char *const argv[], char *const envp[]) {
    const char *name = path ? strrchr(path, '/') : NULL;
    if (!name || strcmp(name, "/1Password-BrowserSupport")) return posix_spawn(pid, path, files, attrs, argv, envp);
    // Refuse when off: a helper started for the patched Dia waits forever, even after Dia quits.
    if (!DPOnePassword.on) return ENOENT;
    if (!DPCLITrusted()) return EPERM;
    int argc = 0;
    while (argv[argc]) argc++;
    char *redirected[argc + 1];
    memcpy(redirected, argv, (argc + 1) * sizeof *argv);
    redirected[0] = (char *)DPDiapatch();
    return posix_spawn(pid, redirected[0], files, attrs, redirected, envp);
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *replacement, *replacee; } DPInterposeSpawn = {
    (const void *)DPSpawn, (const void *)posix_spawn
};

static NSString *DPOnePasswordProblem(DPPatch *patch) {
    NSString *host = DPAppSupport(@"Google/Chrome/NativeMessagingHosts/com.1password.1password.json");
    if (!DPTesting && ![NSFileManager.defaultManager fileExistsAtPath:host]) return @"The 1Password app isn’t installed, or hasn’t set up its browser support yet. Open 1Password, then try again.";
    return DPRelayProblem();
}

DP_PATCH(DPOnePassword) {
    .key = @"onePassword",
    .order = 102,
    .title = @"Allow 1Password",
    .detail = @"Connect the 1Password extension to the 1Password app. The app turns away a patched Dia, so each time the extension connects, the original Dia runs hidden for a moment to start the app’s helper, then quits. Experimental.",
    .symbol = @"lock.shield.fill",
    .tint = @"systemGreenColor",
    .section = @"Passwords",
    .ready = DPOnePasswordProblem,
};
