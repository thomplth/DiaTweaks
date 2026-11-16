#import "StdPatch/StdPatch.h"
#import <objc/message.h>

extern DPPatch DPHideHistorySuggestions;

static BOOL DPFromHistory(id match) {
    if ([[match valueForKey:@"hasTabMatch"] boolValue]) return NO;
    NSString *provider = [match valueForKey:@"providerType"], *type = [match valueForKey:@"matchType"];
    // The address as typed is made by the history provider too but isn't a suggestion; without it Return searches the text.
    if ([type isEqualToString:@"url-what-you-typed"]) return NO;
    return [provider hasPrefix:@"History"] || [provider isEqualToString:@"Shortcuts"] || [type hasPrefix:@"history-"] || [type isEqualToString:@"search-history"];
}

static id DPWithoutHistory(id result) {
    SEL make = @selector(init:perProviderMatches:);
    if (![[result class] instancesRespondToSelector:make]) return result;
    NSPredicate *kept = [NSPredicate predicateWithBlock:^BOOL(id match, id _) { return !DPFromHistory(match); }];
    NSDictionary<NSString *, NSArray *> *perProvider = [result valueForKey:@"perProviderMatches"];
    NSMutableDictionary *filtered = [NSMutableDictionary dictionaryWithCapacity:perProvider.count];
    for (NSString *provider in perProvider) {
        NSArray *matches = [perProvider[provider] filteredArrayUsingPredicate:kept];
        if (matches.count) filtered[provider] = matches;
    }
    NSArray *combined = [[result valueForKey:@"combinedMatches"] filteredArrayUsingPredicate:kept];
    return ((id (*)(id, SEL, id, id))objc_msgSend)([[result class] alloc], make, combined, filtered);
}

static BOOL DPBrowser_autocomplete(id self, SEL _cmd, NSString *text, int cursor, BOOL prevent, BOOL fresh, id keyword, id *error, void (^completion)(id, BOOL)) {
    if (!DPHideHistorySuggestions.on || !completion) return DPCallOriginal(DPBrowser_autocomplete, self, text, cursor, prevent, fresh, keyword, error, completion);
    return DPCallOriginal(DPBrowser_autocomplete, self, text, cursor, prevent, fresh, keyword, error, ^(id result, BOOL done) {
        completion(result && DPHideHistorySuggestions.on ? DPWithoutHistory(result) : result, done);
    });
}

static void DPInstallHideHistorySuggestions(void) {
    DPHook(DPDiaBrowser, @selector(autocomplete:cursorPosition:preventInlineAutocomplete:startFresh:keyword:error:completion:), (IMP)DPBrowser_autocomplete);
}

DP_PATCH(DPHideHistorySuggestions) {
    .key = @"hideHistorySuggestions",
    .order = 92,
    .title = @"Hide History Suggestions",
    .detail = @"Leave pages you've visited out of the suggestions in the address field and command bar. Searches and open tabs still show.",
    .symbol = @"clock.badge.xmark.fill clock.fill",
    .tint = @"systemOrangeColor",
    .section = @"Command Bar",
    .classes = DPClasses(DPDiaBrowser),
    .install = DPInstallHideHistorySuggestions,
};
