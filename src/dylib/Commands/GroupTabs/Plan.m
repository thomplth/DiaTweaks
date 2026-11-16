#import "GroupTabs.h"

NSString *DPDomainKey(NSString *urlString) {
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return nil;
    NSString *host = url.host.lowercaseString;
    if (!host.length) return nil;
    while ([host hasSuffix:@"."]) host = [host substringToIndex:host.length - 1];
    if ([host hasPrefix:@"www."] && host.length > 4) host = [host substringFromIndex:4];
    return host.length ? host : nil;
}

static NSDictionary<NSString *, NSString *> *DPTitles(NSArray<NSDictionary *> *tabs) {
    NSMutableDictionary<NSString *, NSString *> *friendly = [NSMutableDictionary dictionary];
    for (NSDictionary *tab in tabs) {
        NSString *domain = tab[@"domain"];
        if (domain.length && !friendly[domain]) friendly[domain] = DPGroupTitle(domain);
    }
    NSCountedSet *counts = [NSCountedSet setWithArray:friendly.allValues];
    NSMutableDictionary<NSString *, NSString *> *titles = [NSMutableDictionary dictionary];
    for (NSString *domain in friendly)
        titles[domain] = [counts countForObject:friendly[domain]] > 1 ? domain : friendly[domain];
    return titles;
}

// Older versions titled groups with the host, so those count as home too.
NSArray<NSDictionary *> *DPOps(NSArray<NSDictionary *> *tabs, NSArray *groups) {
    NSMutableDictionary<NSNumber *, NSString *> *groupTitle = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *homeID = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSNumber *> *> *homeMembers = [NSMutableDictionary dictionary];
    for (id info in groups) {
        if (![info respondsToSelector:@selector(groupId)]) continue;
        NSString *groupID = DPText(DPMsg(info, @selector(groupId)));
        NSString *title = [info respondsToSelector:@selector(title)] ? DPText(DPMsg(info, @selector(title))) ?: @"" : @"";
        if (!groupID.length) continue;
        NSArray *rawIDs = [info respondsToSelector:@selector(tabSessionIds)] ? DPMsg(info, @selector(tabSessionIds)) : nil;
        if (title.length && !homeID[title]) {
            homeID[title] = groupID;
            homeMembers[title] = [NSMutableSet set];
        }
        if ([rawIDs isKindOfClass:NSArray.class]) for (id raw in rawIDs) {
            long long sid = DPLongID(raw);
            if (sid <= 0) continue;
            groupTitle[@(sid)] = title;
            [homeMembers[title] addObject:@(sid)];
        }
    }
    NSDictionary<NSString *, NSString *> *titles = DPTitles(tabs);
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *pools = [NSMutableDictionary dictionary];
    for (NSDictionary *tab in tabs) {
        NSNumber *sid = tab[@"session"];
        NSString *domain = tab[@"domain"];
        NSString *want = titles[domain] ?: domain;
        NSString *title = groupTitle[sid];
        if (title && ![title isEqualToString:domain] && ![title isEqualToString:want]) continue;
        NSMutableArray *pool = pools[domain] ?: (pools[domain] = [NSMutableArray array]);
        [pool addObject:tab];
    }
    NSMutableArray<NSDictionary *> *ops = [NSMutableArray array];
    for (NSString *domain in pools) {
        NSArray<NSDictionary *> *pool = pools[domain];
        if (pool.count < 2) continue;
        NSString *want = titles[domain] ?: domain;
        NSMutableSet<NSNumber *> *members = [NSMutableSet set];
        if (homeMembers[want]) [members unionSet:homeMembers[want]];
        if (homeMembers[domain] && ![want isEqualToString:domain]) [members unionSet:homeMembers[domain]];
        NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
        for (NSDictionary *tab in pool) if (![members containsObject:tab[@"session"]]) [ids addObject:tab[@"session"]];
        if (!ids.count) continue;
        NSString *home = homeID[want] ?: homeID[domain];
        if (home) [ops addObject:@{@"op": @"add", @"group": home, @"ids": ids}];
        else if (ids.count >= 2) [ops addObject:@{@"op": @"create", @"title": want, @"ids": ids}];
    }
    return ops;
}
