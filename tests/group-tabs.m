#import "Commands/GroupTabs/GroupTabs.h"

@interface DPFakeGroup : NSObject
@property NSString *groupId, *title;
@property NSArray *tabSessionIds;
@end
@implementation DPFakeGroup
@end

static int failures;

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

static void expectEqual(id got, id want, NSString *what) {
    expect([got isEqual:want] || got == want, [NSString stringWithFormat:@"%@: got %@, want %@", what, got, want]);
}

static NSDictionary *tab(long long session, NSString *url) {
    return @{@"session": @(session), @"domain": DPDomainKey(url), @"url": url};
}

static DPFakeGroup *group(NSString *groupID, NSString *title, NSArray *sessions) {
    DPFakeGroup *group = [DPFakeGroup new];
    group.groupId = groupID;
    group.title = title;
    group.tabSessionIds = sessions;
    return group;
}

int main(void) {
    @autoreleasepool {
        expectEqual(DPDomainKey(@"https://www.example.com/a?b"), @"example.com", @"www is dropped");
        expectEqual(DPDomainKey(@"https://Docs.Example.com./"), @"docs.example.com", @"case and trailing dot");
        expectEqual(DPDomainKey(@"https://bücher.example/"), @"xn--bcher-kva.example", @"international hosts group by their ASCII form");
        expectEqual(DPDomainKey(@"file:///tmp/a.html"), nil, @"files have no domain");
        expectEqual(DPDomainKey(@"about:blank"), nil, @"internal pages have no domain");

        NSDictionary *sites = @{
            @"gist.github.com": @"github.com", @"news.bbc.co.uk": @"bbc.co.uk", @"a.b.example.com.au": @"example.com.au",
            @"a.foo.github.io": @"foo.github.io", @"github.io": @"github.io", @"192.168.1.10": @"192.168.1.10",
            @"localhost": @"localhost", @"mail.google.com": @"google.com",
        };
        for (NSString *host in sites) expectEqual(DPRegistrableDomain(host), sites[host], [@"site of " stringByAppendingString:host]);

        NSDictionary *titles = @{
            @"youtube.com": @"YouTube", @"en.wikipedia.org": @"Wikipedia", @"gist.github.com": @"GitHub", @"bbc.co.uk": @"BBC",
            @"example.com": @"Example", @"localhost": @"localhost", @"192.168.1.10": @"192.168.1.10",
        };
        for (NSString *host in titles) expectEqual(DPGroupTitle(host), titles[host], [@"title for " stringByAppendingString:host]);

        NSArray *ops = DPOps(@[ tab(1, @"https://youtube.com/a"), tab(2, @"https://www.youtube.com/b"), tab(3, @"https://github.com") ], @[]);
        expectEqual(ops, (@[ @{@"op": @"create", @"title": @"YouTube", @"ids": @[ @1, @2 ]} ]), @"two tabs of a site make a group named after it");

        ops = DPOps(@[ tab(1, @"https://github.com/a"), tab(2, @"https://github.com/b") ], @[ group(@"g", @"github.com", @[ @1 ]) ]);
        expectEqual(ops, (@[ @{@"op": @"add", @"group": @"g", @"ids": @[ @2 ]} ]), @"a group titled with the host still takes the site's tabs");

        ops = DPOps(@[ tab(1, @"https://youtube.com/a"), tab(2, @"https://youtube.com/b") ], @[ group(@"g", @"YouTube", @[ @1 ]) ]);
        expectEqual(ops, (@[ @{@"op": @"add", @"group": @"g", @"ids": @[ @2 ]} ]), @"a group titled with the site's name takes its tabs");

        ops = DPOps(@[ tab(1, @"https://apple.com"), tab(2, @"https://apple.com/mac"), tab(3, @"https://apple.org"), tab(4, @"https://apple.org/x") ], @[]);
        NSSet *created = [NSSet setWithArray:[ops valueForKey:@"title"]];
        expectEqual(created, ([NSSet setWithArray:@[ @"apple.com", @"apple.org" ]]), @"sites that share a name keep their hosts");

        ops = DPOps(@[ tab(1, @"https://github.com/a"), tab(2, @"https://github.com/b") ], @[ group(@"w", @"Work", @[ @1 ]) ]);
        expectEqual(ops, @[], @"a tab in a group you named stays put");
    }
    if (!failures) printf("all Group Tabs by Domain checks passed\n");
    return failures ? 1 : 0;
}
