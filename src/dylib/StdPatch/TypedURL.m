#import "StdPatch.h"
#import <arpa/inet.h>
#import <dlfcn.h>

// javascript: is left out on purpose: a bar that only navigates has nothing to run it on, so it is searched for.
static BOOL DPKeepsScheme(NSString *scheme) {
    return [@[ @"about", @"chrome", @"data", @"file", @"mailto", @"view-source" ] containsObject:scheme];
}

static BOOL DPIsPort(NSString *text) {
    return text.length && text.length <= 5 && text.integerValue <= 65535 &&
           [text rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
}

static BOOL DPIsIPv4(NSArray<NSString *> *labels) {
    if (labels.count != 4) return NO;
    for (NSString *label in labels)
        if (!DPIsPort(label) || label.length > 3 || label.integerValue > 255) return NO;
    return YES;
}

static BOOL DPIsTopLevel(NSString *label) {
    static Boolean (*system)(CFStringRef);
    static NSDataDetector *links;
    static NSSet<NSString *> *newer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        system = dlsym(RTLD_DEFAULT, "_CFHostIsDomainTopLevel");
        if (system && system(CFSTR("com"))) return;
        system = NULL;
        links = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
        newer = [NSSet setWithArray:[@"dev app page cloud shop blog live store sh gg im io ai xyz tech site online design tools run so to me tv fm co club new zip mov bot pro info biz wiki world today news team work games chat link fun art studio digital software systems network email finance money health edu gov mil int" componentsSeparatedByString:@" "]];
    });
    if (system) return system((__bridge CFStringRef)label);
    NSString *host = [@"foo." stringByAppendingString:label];
    NSTextCheckingResult *match = [links firstMatchInString:host options:0 range:NSMakeRange(0, host.length)];
    return [newer containsObject:label.lowercaseString] || (match && NSEqualRanges(match.range, NSMakeRange(0, host.length)));
}

static BOOL DPIsLocalName(NSString *name) {
    if ([name isEqual:@"localhost"]) return YES;
    for (NSString *suffix in @[ @".localhost", @".test", @".local", @".internal", @".lan", @".home.arpa" ]) if ([name hasSuffix:suffix]) return YES;
    return NO;
}

static BOOL DPIsHostLabel(NSString *label) {
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSCharacterSet.letterCharacterSet mutableCopy];
        [set formUnionWithCharacterSet:NSCharacterSet.decimalDigitCharacterSet];
        [set formUnionWithCharacterSet:NSCharacterSet.nonBaseCharacterSet];
        [set addCharactersInString:@"-_"];
        allowed = set;
    });
    return label.length && ![label hasPrefix:@"-"] && ![label hasSuffix:@"-"] &&
           [label rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

NSURL *DPAddressURL(NSString *typed) {
    NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *text = [typed stringByTrimmingCharactersInSet:space];
    if (!text.length || [text rangeOfCharacterFromSet:space].location != NSNotFound) return nil;

    NSRange colon = [text rangeOfString:@":"];
    NSString *scheme = colon.location == NSNotFound ? @"" : [text substringToIndex:colon.location].lowercaseString;
    NSCharacterSet *schemeLetters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789+.-"];
    if (scheme.length && isalpha([scheme characterAtIndex:0]) && [scheme rangeOfCharacterFromSet:schemeLetters.invertedSet].location == NSNotFound &&
        ![scheme isEqual:@"javascript"] && ([[text substringFromIndex:NSMaxRange(colon)] hasPrefix:@"//"] || DPKeepsScheme(scheme)))
        return [NSURL URLWithString:text];

    NSRange end = [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#"]];
    NSString *authority = end.location == NSNotFound ? text : [text substringToIndex:end.location], *host = authority, *port = nil;
    if ([authority hasPrefix:@"["]) {
        NSRange close = [authority rangeOfString:@"]"];
        if (close.location == NSNotFound) return nil;
        NSString *after = [authority substringFromIndex:NSMaxRange(close)];
        struct in6_addr address;
        if (inet_pton(AF_INET6, [authority substringWithRange:NSMakeRange(1, close.location - 1)].UTF8String, &address) != 1) return nil;
        if (after.length && !([after hasPrefix:@":"] && DPIsPort([after substringFromIndex:1]))) return nil;
        return [NSURL URLWithString:[@"http://" stringByAppendingString:text]];
    }
    NSRange portAt = [authority rangeOfString:@":" options:NSBackwardsSearch];
    if (portAt.location != NSNotFound) {
        host = [authority substringToIndex:portAt.location];
        port = [authority substringFromIndex:NSMaxRange(portAt)];
        if (!DPIsPort(port)) return nil;
    }

    NSString *name = host.lowercaseString;
    if ([name hasSuffix:@"."]) name = [name substringToIndex:name.length - 1];
    NSArray<NSString *> *labels = [name componentsSeparatedByString:@"."];
    for (NSString *label in labels) if (!DPIsHostLabel(label)) return nil;

    if (DPIsIPv4(labels) || DPIsLocalName(name) || port)
        return [NSURL URLWithString:[(port.integerValue == 443 ? @"https://" : @"http://") stringByAppendingString:text]];
    if (labels.count > 1 && ([name hasPrefix:@"www."] || DPIsTopLevel(labels.lastObject))) return [NSURL URLWithString:[@"https://" stringByAppendingString:text]];
    return nil;
}
