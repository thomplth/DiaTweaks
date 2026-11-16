#import "GroupTabs.h"

static BOOL DPCountryCode(NSString *label) {
    if (label.length != 2) return NO;
    unichar a = [label characterAtIndex:0], b = [label characterAtIndex:1];
    return a >= 'a' && a <= 'z' && b >= 'a' && b <= 'z';
}

static BOOL DPPublicSuffix(NSString *last, NSString *secondLast) {
    static NSSet<NSString *> *countrySeconds, *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        countrySeconds = [NSSet setWithArray:@[ @"ac", @"co", @"com", @"edu", @"go", @"gob", @"gov", @"mil", @"ne", @"net", @"or", @"org" ]];
        shared = [NSSet setWithArray:@[ @"github.io", @"gitlab.io", @"vercel.app", @"netlify.app", @"pages.dev", @"workers.dev", @"web.app",
                                        @"firebaseapp.com", @"herokuapp.com", @"blogspot.com", @"wordpress.com", @"tumblr.com", @"substack.com" ]];
    });
    if (DPCountryCode(last) && [countrySeconds containsObject:secondLast]) return YES;
    return [shared containsObject:[NSString stringWithFormat:@"%@.%@", secondLast, last]];
}

NSString *DPRegistrableDomain(NSString *host) {
    NSArray<NSString *> *labels = [host componentsSeparatedByString:@"."];
    if (labels.count < 3 || [labels.lastObject rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) return host;
    NSUInteger keep = DPPublicSuffix(labels.lastObject, labels[labels.count - 2]) ? 3 : 2;
    if (labels.count <= keep) return host;
    return [[labels subarrayWithRange:NSMakeRange(labels.count - keep, keep)] componentsJoinedByString:@"."];
}
