#import "LaunchServices.h"

void DPForgetApp(NSString *app) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"];
    task.arguments = @[ @"-u", app ];
    task.standardOutput = task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if ([task launchAndReturnError:NULL]) [task waitUntilExit];
}
