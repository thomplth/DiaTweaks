#import "DiscardInactiveTabs.h"

static NSArray<NSRegularExpression *> *DPKeptSites;

static NSArray<NSString *> *DPBehaviorFiles(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *cached = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Dia/RemoteAssetDirectory"];
    for (NSString *name in [files contentsOfDirectoryAtPath:cached error:nil])
        if ([name hasPrefix:@"WebContentBehaviorConfiguration"]) [paths addObject:[cached stringByAppendingPathComponent:name]];
    NSString *bundled = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"ARC_WebContentBehaviorConfigurationClient.bundle"];
    for (NSString *name in [files subpathsOfDirectoryAtPath:bundled error:nil])
        if ([name.pathExtension isEqual:@"json"]) [paths addObject:[bundled stringByAppendingPathComponent:name]];
    return paths;
}

static void DPAddSite(NSMutableArray<NSRegularExpression *> *sites, id pattern) {
    if (![pattern isKindOfClass:NSString.class]) return;
    NSRegularExpression *site = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    if (site) [sites addObject:site];
}

// The cached behaviour files are downloaded, so any part of their shape can change between Dia sessions.
static void DPAddSitesFromFile(NSMutableArray<NSRegularExpression *> *sites, NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSDictionary *behavior = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![behavior isKindOfClass:NSDictionary.class]) return;
    for (NSString *list in @[ @"keepaliveAllowList", @"tabSuspensionBlocklist" ]) {
        NSArray *rules = behavior[list];
        if (![rules isKindOfClass:NSArray.class]) continue;
        for (NSDictionary *rule in rules)
            if ([rule isKindOfClass:NSDictionary.class]) DPAddSite(sites, rule[@"urlRegex"]);
    }
}

static NSArray<NSRegularExpression *> *DPLoadKeptSites(void) {
    NSMutableArray<NSRegularExpression *> *sites = [NSMutableArray array];
    for (NSString *path in DPBehaviorFiles()) DPAddSitesFromFile(sites, path);
    if (!sites.count) return sites;
    // Dia's Figma rule only matches /file/ URLs, which Figma now redirects to these.
    DPAddSite(sites, @"^(?:https?://)?(?:www\\.)?figma\\.com/(?:design|board)/");
    return sites;
}

BOOL DPIsKeptSite(NSString *url) {
    if (!DPKeptSites.count) DPKeptSites = DPLoadKeptSites();
    // Without rules, Slack or Gmail could lose their state: keeping every tab is the safer failure.
    if (!DPKeptSites.count) return YES;
    for (NSRegularExpression *site in DPKeptSites)
        if ([site firstMatchInString:url options:0 range:NSMakeRange(0, url.length)]) return YES;
    return NO;
}
