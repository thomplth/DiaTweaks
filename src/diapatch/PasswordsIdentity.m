#import <Security/Security.h>
#import <libproc.h>
#import "PasswordsParts.h"

static NSData *cdhashOf(SecStaticCodeRef code) {
    CFDictionaryRef info = NULL;
    NSData *cdhash = nil;
    if (SecCodeCopySigningInformation(code, kSecCSDefaultFlags, &info) == errSecSuccess)
        cdhash = ((__bridge NSDictionary *)info)[(__bridge NSString *)kSecCodeInfoUnique];
    if (info) CFRelease(info);
    return cdhash;
}

static NSData *cdhashOnDisk(NSString *path) {
    SecStaticCodeRef code = NULL;
    NSData *cdhash = nil;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:path], kSecCSDefaultFlags, &code) == errSecSuccess
        && SecStaticCodeCheckValidity(code, kSecCSDoNotValidateResources, NULL) == errSecSuccess)
        cdhash = cdhashOf(code);
    if (code) CFRelease(code);
    return cdhash;
}

static NSData *cdhashOfSelf(void) {
    SecCodeRef code = NULL;
    SecStaticCodeRef staticCode = NULL;
    NSData *cdhash = nil;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &code) == errSecSuccess && SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &staticCode) == errSecSuccess)
        cdhash = cdhashOf(staticCode);
    if (staticCode) CFRelease(staticCode);
    if (code) CFRelease(code);
    return cdhash;
}

static BOOL runs(NSDictionary *guest, NSData *cdhash) {
    if (!cdhash) return NO;
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < cdhash.length; i++) [hex appendFormat:@"%02x", ((const uint8_t *)cdhash.bytes)[i]];
    SecCodeRef code = NULL;
    SecRequirementRef requirement = NULL;
    BOOL matches = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)guest, kSecCSDefaultFlags, &code) == errSecSuccess
        && SecRequirementCreateWithString((__bridge CFStringRef)[NSString stringWithFormat:@"cdhash H\"%@\"", hex], kSecCSDefaultFlags, &requirement) == errSecSuccess
        && SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement) == errSecSuccess;
    if (requirement) CFRelease(requirement);
    if (code) CFRelease(code);
    return matches;
}

static NSString *executableOf(NSString *app) { return [app stringByAppendingPathComponent:@"Contents/MacOS/Dia"]; }

BOOL DPRunsPatchedDia(pid_t pid, NSString *app) {
    return runs(@{ (__bridge NSString *)kSecGuestAttributePid : @(pid) }, cdhashOnDisk(executableOf(app)));
}

BOOL DPRunsThisDiapatch(audit_token_t token) {
    return runs(@{ (__bridge NSString *)kSecGuestAttributeAudit : [NSData dataWithBytes:&token length:sizeof token] }, cdhashOfSelf());
}

pid_t DPParentOf(pid_t pid) {
    struct proc_bsdinfo info;
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) == sizeof info ? (pid_t)info.pbi_ppid : 0;
}
