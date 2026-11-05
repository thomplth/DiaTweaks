#import "Commands/GroupTabs/GroupTabs.h"
#import <objc/message.h>

extern DPPatch DPColorNewTabGroups;

static NSString *const DPKnownGroupsKey = @"colorNewTabGroupsKnown";
static const long DPGroupColorGrey = 0;
// Dia's groups have no cyan theme (ADK.TabGroupColor value 7), so cyan would look the same as another colour.
static const long DPAssignableColors[] = {1, 2, 3, 4, 5, 6, 8};
static const int64_t DPPassTimeout = 5 * NSEC_PER_SEC;
static const NSTimeInterval DPExistingGroupsRecordingSeconds = 30;
static const int64_t DPLastRecordingPassAfter = 25 * NSEC_PER_SEC;

static NSUserDefaults *DPDefaults;
static BOOL DPPassScheduled, DPPassRunning, DPPassWanted;
static NSUInteger DPCurrentPass;

static void DPRunPass(void);
static void DPSchedulePass(void);

static long DPLeastUsedColor(NSCountedSet<NSNumber *> *used) {
    NSUInteger fewest = NSUIntegerMax;
    NSMutableArray<NSNumber *> *candidates = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(DPAssignableColors) / sizeof(*DPAssignableColors); i++) {
        NSNumber *color = @(DPAssignableColors[i]);
        NSUInteger uses = [used countForObject:color];
        if (uses < fewest) {
            fewest = uses;
            [candidates removeAllObjects];
        }
        if (uses == fewest) [candidates addObject:color];
    }
    return candidates[arc4random_uniform((uint32_t)candidates.count)].longValue;
}

static id DPAsk(id object, SEL sel) {
    return [object respondsToSelector:sel] ? DPMsg(object, sel) : nil;
}

static NSString *DPProfileOf(id browser) {
    return DPText(DPAsk(DPAsk(DPAsk(browser, @selector(context)), @selector(id)), @selector(directoryBasename)));
}

static long DPColorOf(id info) {
    return ((long (*)(id, SEL))objc_msgSend)(info, @selector(color));
}

static void DPFinishPass(NSUInteger pass) {
    if (!DPPassRunning || pass != DPCurrentPass) return;
    DPPassRunning = NO;
    if (!DPPassWanted) return;
    DPPassWanted = NO;
    DPRunPass();
}

static void DPSetGroupColor(id browser, NSString *groupID, long color, dispatch_group_t updates) {
    id properties = [objc_getClass(DPDiaTabGroupProperties) new];
    ((void (*)(id, SEL, id))objc_msgSend)(properties, @selector(setColor:), @(color));
    dispatch_group_enter(updates);
    void (*update)(id, SEL, id, NSString *, id, void (^)(id)) = (void *)objc_msgSend;
    update(DPGroupingDelegate(browser), @selector(browser:updateTabGroupWithId:properties:completion:), browser, groupID, properties, ^(id result) {
        dispatch_group_leave(updates);
    });
}

// Dia lists no groups until it has restored them, so one early read can't stand for the groups a profile already has.
static BOOL DPStillRecordingExistingGroups(NSString *profile, BOOL everSeen) {
    static NSMutableDictionary<NSString *, NSDate *> *recordingEnds;
    if (!recordingEnds) recordingEnds = [NSMutableDictionary dictionary];
    if (!everSeen && !recordingEnds[profile]) {
        recordingEnds[profile] = [NSDate dateWithTimeIntervalSinceNow:DPExistingGroupsRecordingSeconds];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, DPLastRecordingPassAfter), dispatch_get_main_queue(), ^{ DPSchedulePass(); });
    }
    return recordingEnds[profile] && recordingEnds[profile].timeIntervalSinceNow > 0;
}

// `profiles` maps a profile to its groups, each {color, browser} by group ID.
static void DPColorNewGroups(NSDictionary<NSString *, NSDictionary *> *profiles, NSUInteger pass) {
    NSMutableDictionary *known = [[DPDefaults dictionaryForKey:DPKnownGroupsKey] ?: @{} mutableCopy];
    dispatch_group_t updates = dispatch_group_create();
    [profiles enumerateKeysAndObjectsUsingBlock:^(NSString *profile, NSDictionary *groups, BOOL *stop) {
        BOOL recordOnly = DPStillRecordingExistingGroups(profile, known[profile] != nil);
        NSMutableSet *knownIDs = [NSMutableSet setWithArray:known[profile] ?: @[]];
        NSCountedSet *used = [[NSCountedSet alloc] initWithArray:[groups.allValues valueForKey:@"color"]];
        [groups enumerateKeysAndObjectsUsingBlock:^(NSString *groupID, NSDictionary *group, BOOL *stop) {
            if ([knownIDs containsObject:groupID]) return;
            [knownIDs addObject:groupID];
            if (recordOnly || !DPColorNewTabGroups.on || [group[@"color"] longValue] != DPGroupColorGrey) return;
            long color = DPLeastUsedColor(used);
            [used addObject:@(color)];
            DPSetGroupColor(group[@"browser"], groupID, color, updates);
        }];
        known[profile] = knownIDs.allObjects;
    }];
    [DPDefaults setObject:known forKey:DPKnownGroupsKey];
    dispatch_group_notify(updates, dispatch_get_main_queue(), ^{ DPFinishPass(pass); });
}

// Runs while the patch is off too, only recording groups, so turning it on doesn't colour groups made in the meantime.
static void DPRunPass(void) {
    if (DPPassRunning) {
        DPPassWanted = YES;
        return;
    }
    DPPassRunning = YES;
    NSUInteger pass = ++DPCurrentPass;
    // A browser closing as it's asked may never call back, which mustn't stop every later pass.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, DPPassTimeout), dispatch_get_main_queue(), ^{ DPFinishPass(pass); });

    NSMutableDictionary<NSString *, NSMutableDictionary *> *profiles = [NSMutableDictionary dictionary];
    dispatch_group_t reads = dispatch_group_create();
    for (id browser in DPTrackedBrowsers()) {
        NSString *profile = DPProfileOf(browser);
        id delegate = DPGroupingDelegate(browser);
        if (!profile.length || ![delegate respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)]) continue;
        dispatch_group_enter(reads);
        void (*ask)(id, SEL, id, void (^)(NSArray *)) = (void *)objc_msgSend;
        ask(delegate, @selector(browser:getAllTabGroupsWithCompletion:), browser, ^(NSArray *infos) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableDictionary *groups = profiles[profile] ?: (profiles[profile] = [NSMutableDictionary dictionary]);
                for (id info in [infos isKindOfClass:NSArray.class] ? infos : @[]) {
                    NSString *groupID = DPText(DPAsk(info, @selector(groupId)));
                    if (groupID.length) groups[groupID] = @{@"color": @(DPColorOf(info)), @"browser": browser};
                }
                dispatch_group_leave(reads);
            });
        });
    }
    dispatch_group_notify(reads, dispatch_get_main_queue(), ^{
        if (pass == DPCurrentPass && DPPassRunning) DPColorNewGroups(profiles, pass);
    });
}

static void DPSchedulePass(void) {
    if (DPPassScheduled) return;
    DPPassScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        DPPassScheduled = NO;
        DPRunPass();
    });
}

static void DPGroupView_movedToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPGroupView_movedToWindow, self);
    if (self.window) DPSchedulePass();
}

static void DPInstallColorNewTabGroups(void) {
    DPDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    DPHook(DPDiaTabGroupCell, @selector(viewDidMoveToWindow), (IMP)DPGroupView_movedToWindow);
    DPHook(DPDiaTabGroupView, @selector(viewDidMoveToWindow), (IMP)DPGroupView_movedToWindow);
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        DPSchedulePass();
    }];
}

DP_PATCH(DPColorNewTabGroups) {
    .key = @"colorNewTabGroups",
    .order = 80,
    .title = @"Color New Tab Groups",
    .detail = @"Give every new tab group a random color that no other group in the profile is using.",
    .symbol = @"paintpalette.fill paintpalette",
    .tint = @"systemPinkColor",
    .section = @"Sidebar & Tab Bar",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Color-new-tab-groups.md",
    .classes = DPClasses(DPDiaTabGroupCell, DPDiaTabGroupProperties),
    .install = DPInstallColorNewTabGroups,
};
