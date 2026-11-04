#import "Updates/Updates.h"
#import <Security/Security.h>
#include <sys/xattr.h>

#ifndef DP_DIAPATCH_CDHASH
#error Build with make, which pins the diapatch this dylib ships with
#endif

NSString *const DPDia = @"dia", *const DPTweaks = @"tweaks";
NSNotificationName const DPUpdatesDidChangeNotification = @"DPUpdatesDidChange";

NSString *DPPartName(NSString *part) { return [part isEqual:DPDia] ? @"Dia" : @"DiaTweaks"; }

static NSString *DPSupport(NSString *name) {
    return [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"DiaPatches"] stringByAppendingPathComponent:name];
}

static NSString *DPCLI(void) { return DPSupport(@"bin/diapatch"); }

// Dia's signature pins this dylib and this dylib pins diapatch, so a diapatch swapped in by something else never runs as
// Dia's child with Dia's privacy permissions.
BOOL DPCLITrusted(void) {
    SecStaticCodeRef code = NULL;
    SecRequirementRef requirement = NULL;
    BOOL trusted = SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:DPCLI()], kSecCSDefaultFlags, &code) == errSecSuccess
        && SecRequirementCreateWithString((__bridge CFStringRef)@"cdhash H\"" DP_DIAPATCH_CDHASH "\"", kSecCSDefaultFlags, &requirement) == errSecSuccess
        && SecStaticCodeCheckValidity(code, kSecCSStrictValidate, requirement) == errSecSuccess;
    if (requirement) CFRelease(requirement);
    if (code) CFRelease(code);
    if (!trusted) NSLog(@"DiaPatches: %@ isn't the diapatch this build shipped with, so it won't run", DPCLI());
    return trusted;
}

static NSUserDefaults *DPUpdateDefaults(void) { return [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; }

static NSString *DPAutoKey(NSString *part) { return [part isEqual:DPDia] ? @"autoUpdateDia" : @"autoUpdateTweaks"; }

DPAutoLevel DPAutoLevelOf(NSString *part) {
    id level = [DPUpdateDefaults() objectForKey:DPAutoKey(part)];
    return level ? MIN(MAX([level integerValue], DPAutoOff), DPAutoInstall) : DPAutoInstall;
}

void DPSetAutoLevel(NSString *part, DPAutoLevel level) { [DPUpdateDefaults() setInteger:level forKey:DPAutoKey(part)]; }

void DPRunCLI(NSArray<NSString *> *args, void (^completion)(NSString *output)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:DPCLI()];
        task.arguments = args;
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = NSFileHandle.fileHandleWithNullDevice;
        NSString *output = nil;
        if (DPCLITrusted() && [task launchAndReturnError:nil]) {
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            [task waitUntilExit];
            if (task.terminationStatus == 0) output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(output); });
    });
}

void DPHandOffAndQuit(NSArray<NSString *> *args) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:DPCLI()];
    task.arguments = [args arrayByAddingObjectsFromArray:@[@"--wait", @(getpid()).stringValue, @"--relaunch"]];
    if (DPCLITrusted() && [task launchAndReturnError:nil]) [NSApp terminate:nil];
}

@implementation DPUpdates {
    NSMutableDictionary<NSString *, NSMutableArray *> *_whenDownloaded;
    NSMutableArray *_checked;
    NSMutableSet<NSString *> *_failed;
    NSTimer *_progress;
    NSDictionary *_found;
    NSMutableDictionary<NSString *, id> *_pretend;  // part → @"available", the NSDate its download started, or @"staged"
}

+ (instancetype)shared {
    static DPUpdates *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [DPUpdates new]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _whenDownloaded = [NSMutableDictionary new];
    _checked = [NSMutableArray new];
    _failed = [NSMutableSet new];
    _pretend = [NSMutableDictionary new];
    return self;
}

- (void)changed { [NSNotificationCenter.defaultCenter postNotificationName:DPUpdatesDidChangeNotification object:self]; }

- (void)check:(void (^)(void))done {
    if (done) [_checked addObject:done];
    if (_checking) return;
    _checking = YES;
    [self changed];
    DPRunCLI(@[@"check", @"--json"], ^(NSString *output) {
        id found = output ? [NSJSONSerialization JSONObjectWithData:[output dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        self->_found = [found isKindOfClass:NSDictionary.class] ? found : nil;
        self->_checking = NO;
        NSArray *waiting = [self->_checked copy];
        [self->_checked removeAllObjects];
        [self changed];
        for (void (^block)(void) in waiting) block();
    });
}

- (NSDictionary *)found {
    if (!_pretend.count) return _found;
    NSMutableDictionary *found = [_found mutableCopy] ?: [NSMutableDictionary new];
    for (NSString *part in _pretend) {
        BOOL staged = [_pretend[part] isEqual:@"staged"];
        NSString *latest = [part isEqual:DPDia] ? @"1.56.0 (90000)" : @"v1.1.0";
        NSMutableDictionary *entry = [found[part] ?: @{} mutableCopy];
        [entry addEntriesFromDictionary:@{
            @"latest" : latest, @"available" : @(!staged), @"staged" : staged ? latest : NSNull.null,
            @"size" : [part isEqual:DPDia] ? @704038560 : @960161,
            @"releaseNotes" : [part isEqual:DPDia] ? @"https://www.diabrowser.com/release-notes/latest" : @"https://github.com/thomplth/DiaTweaks/releases",
        }];
        found[part] = entry;
    }
    return found;
}

- (BOOL)available:(NSString *)part { return [self.found[part][@"available"] boolValue]; }
- (BOOL)staged:(NSString *)part { return [self.found[part][@"staged"] isKindOfClass:NSString.class]; }
- (BOOL)downloading:(NSString *)part { return _whenDownloaded[part] != nil; }
- (BOOL)failed:(NSString *)part { return [_failed containsObject:part]; }

- (double)progress:(NSString *)part {
    if ([_pretend[part] isKindOfClass:NSDate.class]) return MIN(-[_pretend[part] timeIntervalSinceNow] / 3, 1);
    NSString *file = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"DiaPatches"] stringByAppendingPathComponent:[part isEqual:DPDia] ? @"download/Dia.zip" : @"release/DiaTweaks.zip"];
    double size = [self.found[part][@"size"] doubleValue];
    double got = [[NSFileManager.defaultManager attributesOfItemAtPath:file error:nil][NSFileSize] doubleValue];
    return size > 0 && got < size ? got / size : got > 0 ? -1 : 0;
}

- (void)download:(NSString *)part then:(void (^)(void))done {
    if (_whenDownloaded[part]) {
        if (done) [_whenDownloaded[part] addObject:done];
        return;
    }
    _whenDownloaded[part] = done ? [NSMutableArray arrayWithObject:done] : [NSMutableArray new];
    [_failed removeObject:part];
    if (!_progress) _progress = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *_) { [self tick]; }];
    [self changed];
    if (_pretend[part]) {
        _pretend[part] = NSDate.date;
        return;
    }
    DPRunCLI(@[[part isEqual:DPDia] ? @"update" : @"self-update"], ^(NSString *output) {
        if (!output) [self->_failed addObject:part];
        [self finishDownload:part];
    });
}

- (void)finishDownload:(NSString *)part {
    NSArray *waiting = _whenDownloaded[part];
    [_whenDownloaded removeObjectForKey:part];
    if (!_whenDownloaded.count) {
        [_progress invalidate];
        _progress = nil;
    }
    if (_pretend[part]) {
        _pretend[part] = @"staged";
        [self changed];
        for (void (^block)(void) in waiting) block();
    } else {
        [self check:^{ for (void (^block)(void) in waiting) block(); }];
    }
}

- (void)tick {
    for (NSString *part in _pretend.allKeys)
        if ([_pretend[part] isKindOfClass:NSDate.class] && [self progress:part] >= 1) [self finishDownload:part];
    [self changed];
}

- (void)installAndRelaunch:(NSArray<NSString *> *)parts {
    NSMutableArray *args = [NSMutableArray arrayWithObject:@"apply"];
    for (NSString *part in parts) {
        if (_pretend[part]) [_pretend removeObjectForKey:part];
        else [args addObject:[part isEqual:DPDia] ? @"--dia" : @"--tweaks"];
    }
    if (args.count > 1) DPHandOffAndQuit(args);
    else [self changed];
}

- (void)pretend:(NSString *)part {
    _pretend[part] = @"available";
    [self changed];
}

- (void)stopPretending {
    [_pretend removeAllObjects];
    [self changed];
}
@end

static void DPShowUpdateAlert(void) {
    DPUpdates *updates = DPUpdates.shared;
    [updates check:^{
        NSMutableArray<NSString *> *parts = [NSMutableArray new], *names = [NSMutableArray new];
        for (NSString *part in @[DPDia, DPTweaks]) {
            if (![updates available:part] && ![updates staged:part]) continue;
            [parts addObject:part];
            // What's staged can differ from the feed's latest after Dia switches between stable and Early Birds.
            NSString *version = updates.found[part][[updates staged:part] ? @"staged" : @"latest"];
            [names addObject:[NSString stringWithFormat:@"%@ %@", DPPartName(part), version]];
        }
        NSAlert *alert = [NSAlert new];
        if (!parts.count) {
            alert.messageText = updates.found ? @"Dia and DiaTweaks are up to date" : @"Couldn’t check for updates";
            [alert runModal];
            return;
        }
        alert.messageText = [[names componentsJoinedByString:@" and "] stringByAppendingString:@" available"];
        alert.informativeText = parts.count > 1 ? @"Dia relaunches to install them once they’re downloaded."
                                                : @"Dia relaunches to install it once it’s downloaded.";
        [alert addButtonWithTitle:@"Update and Relaunch"];
        [alert addButtonWithTitle:@"Later"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        __block NSUInteger left = parts.count;
        for (NSString *part in parts)
            [updates download:part then:^{ if (--left == 0) [updates installAndRelaunch:parts]; }];
    }];
}

static void DPInstallOnQuit(void) {
    BOOL dia = DPAutoLevelOf(DPDia) == DPAutoInstall && [NSFileManager.defaultManager fileExistsAtPath:DPSupport(@"staged/Dia.app")];
    BOOL tweaks = DPAutoLevelOf(DPTweaks) == DPAutoInstall && [NSFileManager.defaultManager fileExistsAtPath:DPSupport(@"staged/DiaTweaks")];
    if (!dia && !tweaks) return;
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"apply", @"--wait", @(getpid()).stringValue, nil];
    if (dia) [args addObject:@"--dia"];
    if (tweaks) [args addObject:@"--tweaks"];
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:DPCLI()];
    task.arguments = args;
    if (DPCLITrusted()) [task launchAndReturnError:nil];
}

static NSString *DPStagedDiaVersion(void) {
    if (![NSFileManager.defaultManager fileExistsAtPath:DPSupport(@"staged/ready")]) return nil;
    return [NSDictionary dictionaryWithContentsOfFile:DPSupport(@"staged/Dia.app/Contents/Info.plist")][@"CFBundleShortVersionString"];
}

static const NSTimeInterval DPRemindEvery = 24 * 3600, DPLookEvery = 30 * 60;

// The background agent downloads Dia's fixes within the hour, but they only take effect once Dia relaunches, which a
// browser left open can put off for weeks.
static void DPRemindToRelaunch(void) {
    static NSString *remindedFor;
    static NSDate *remindedAt;
    NSString *version = DPStagedDiaVersion();
    if (!version || ([version isEqual:remindedFor] && -remindedAt.timeIntervalSinceNow < DPRemindEvery)) return;
    NSWindow *window = NSApp.keyWindow ?: NSApp.mainWindow;
    if (window.attachedSheet || NSApp.modalWindow) return;
    remindedFor = version;
    remindedAt = NSDate.date;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Relaunch to finish updating Dia to %@", version];
    alert.informativeText = @"It's downloaded and patched. Browser updates usually fix security problems, and this one only takes effect once Dia relaunches.";
    [alert addButtonWithTitle:@"Relaunch Now"];
    [alert addButtonWithTitle:@"Later"];
    void (^answered)(NSModalResponse) = ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) [DPUpdates.shared installAndRelaunch:@[DPDia]];
    };
    if (window) [alert beginSheetModalForWindow:window completionHandler:answered];
    else answered([alert runModal]);
}

// Dia's own updater would put the official app over the patched one, so its checks go to DiaTweaks instead. Dia's feed
// is stable or, once Dia lets the account switch App Build to Early Birds, the Early Birds one; diapatch updates from it.
@protocol DPSparkleUpdater
@property (nonatomic, readonly) NSURL *feedURL;
@end

static void DPSaveDiaFeed(id<DPSparkleUpdater> updater) {
    NSString *feed = updater.feedURL.absoluteString;
    if (feed) [DPUpdateDefaults() setObject:feed forKey:@"diaFeed"];
}

static BOOL DPUpdater_startUpdater(id self, SEL _cmd, NSError **error) {
    DPSaveDiaFeed(self);
    return DPCallOriginal(DPUpdater_startUpdater, self, error);
}

static void DPUpdater_checkForUpdates(id self, SEL _cmd) {
    DPSaveDiaFeed(self);
    DPShowUpdateAlert();
}

static void DPUpdater_checkForUpdatesInBackground(id self, SEL _cmd) {
    DPSaveDiaFeed(self);
}

// Sparkle's own schedule skips the methods above, and Dia's "Automatically update Dia" can turn it on.
static BOOL DPUpdater_automaticallyChecksForUpdates(id self, SEL _cmd) { return NO; }

// An older diapatch run from Dia left its updates quarantined under Dia's name, and macOS then won't run diapatch, for
// updates or as the passkeys host. Loaded into Dia, this can still lift it.
static void DPLiftQuarantine(void) {
    for (NSString *name in @[ @"bin/diapatch", @"bin/diatweaks", @"DiaPatches.dylib", @"patches.json" ])
        removexattr(DPSupport(name).fileSystemRepresentation, "com.apple.quarantine", 0);
}

void DPInstallUpdates(void) {
    DPLiftQuarantine();
    DPHook("SPUUpdater", @selector(startUpdater:), (IMP)DPUpdater_startUpdater);
    DPHook("SPUUpdater", @selector(checkForUpdates), (IMP)DPUpdater_checkForUpdates);
    DPHook("SPUUpdater", @selector(checkForUpdatesInBackground), (IMP)DPUpdater_checkForUpdatesInBackground);
    DPHook("SPUUpdater", @selector(automaticallyChecksForUpdates), (IMP)DPUpdater_automaticallyChecksForUpdates);
    DPOnLaunch(^{
        DPOnMenuItem(nil, @"Check for Updates", ^{ DPShowUpdateAlert(); });
        [NSTimer scheduledTimerWithTimeInterval:DPLookEvery repeats:YES block:^(NSTimer *_) { DPRemindToRelaunch(); }];
        if (DPAutoLevelOf(DPDia) == DPAutoOff && DPAutoLevelOf(DPTweaks) == DPAutoOff) return;
        DPUpdates *updates = DPUpdates.shared;
        [updates check:^{
            for (NSString *part in @[DPDia, DPTweaks])
                if (DPAutoLevelOf(part) >= DPAutoDownload && [updates available:part]) [updates download:part then:nil];
        }];
    });
    DPOnQuit(^{ DPInstallOnQuit(); });
}
