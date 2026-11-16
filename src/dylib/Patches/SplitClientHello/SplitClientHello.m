#import "SplitClientHello.h"
#import "Updates/Updates.h"
#include <libproc.h>
#include <sys/sysctl.h>

// Chromium runs its network service in a sandboxed helper that the dylib isn't loaded into, so while this is on the
// service runs inside Dia, where Send.m sees what it sends. Chromium decides that only as Dia starts.

static BOOL gInProcess;

// Whether a helper Dia started runs the network service, which a Dia that ignores the flag would do.
static BOOL DPNetworkServiceInHelper(void) {
    pid_t children[512];
    int bytes = proc_listpids(PROC_PPID_ONLY, (uint32_t)getpid(), children, sizeof children);
    static const char service[] = "--utility-sub-type=network.mojom.NetworkService";
    for (int i = 0; i < bytes / (int)sizeof *children; i++) {
        char arguments[16384];
        size_t size = sizeof arguments;
        int name[] = { CTL_KERN, KERN_PROCARGS2, children[i] };
        if (sysctl(name, 3, arguments, &size, NULL, 0) == 0 && memmem(arguments, size, service, sizeof service - 1)) return YES;
    }
    return NO;
}

static void DPCheckInProcess(void) {
    if (!gInProcess || !DPNetworkServiceInHelper()) return;
    NSLog(@"DiaPatches: Split TLS ClientHello is off: this Dia keeps its network service in a helper");
    gInProcess = NO;  // so turning it off doesn't offer a relaunch
    DPSplitClientHello.unavailable = YES;
    DPSetPatch(&DPSplitClientHello, NO, NO);
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

static void DPInstallSplitClientHello(void) {
    DPInstallSplitSend();
    DPSplitting = gInProcess = DPSplitClientHello.on;
    if (!gInProcess) {
        DPDropLaunchFeature(@"NetworkServiceInProcess2");
        return;
    }
    DPAddLaunchFlag(@"--enable-features=NetworkServiceInProcess2");
    DPOnLaunch(^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPCheckInProcess(); }); });
}

static void DPApplySplitClientHello(DPPatch *patch) {
    DPSplitting = patch->on && gInProcess;
    if (patch->on == gInProcess || patch->on != DPSavedOn(patch)) return;  // the self-test flips patches without saving
    NSAlert *alert = [NSAlert new];
    alert.messageText = patch->on ? @"Relaunch Dia to split ClientHellos" : @"Relaunch Dia to sandbox its network service again";
    alert.informativeText = patch->on ? @"Until then, Dia sends them whole. After, its network code runs outside its sandbox." : @"Until then, its network code keeps running outside its sandbox.";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

DP_PATCH(DPSplitClientHello) {
    .key = @"splitClientHello",
    .order = 120,
    .section = @"Network",
    .title = @"Split TLS ClientHello",
    .detail = @"Send each HTTPS connection’s first message in two pieces, cut inside the site’s name, to get past networks that block sites by name. Not HTTP/3, DNS or address blocks, and a few servers refuse it. While on, Dia’s network code runs inside Dia, outside its sandbox. Experimental.",
    .symbol = @"network.badge.shield.half.filled network",
    .tint = @"systemCyanColor",
    .install = DPInstallSplitClientHello,
    .apply = DPApplySplitClientHello,
};
