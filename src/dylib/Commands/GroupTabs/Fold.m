// ArcTabGroupProperties.collapsed is an NSNumber (nil leaves the group alone); ArcTabGroupInfo.collapsed is a BOOL.
#import "GroupTabs.h"
#import <objc/message.h>

CFTimeInterval DPFoldedAt;

static id DPFoldProperties(BOOL collapsed) {
    Class cls = objc_getClass(DPDiaTabGroupProperties);
    id props = cls ? [cls new] : nil;
    if (![props respondsToSelector:@selector(setCollapsed:)]) return nil;
    void (*set)(id, SEL, id) = (void *)objc_msgSend;
    set(props, @selector(setCollapsed:), @(collapsed));
    return props;
}

static void DPFoldNext(id delegate, id browser, NSArray<NSString *> *ids, NSUInteger index, BOOL collapsed) {
    if (index >= ids.count) return;
    id props = DPFoldProperties(collapsed);
    if (!props) return;
    void (*update)(id, SEL, id, NSString *, id, void (^)(id)) = (void *)objc_msgSend;
    if (collapsed) DPFoldedAt = CACurrentMediaTime();
    update(delegate, @selector(browser:updateTabGroupWithId:properties:completion:), browser, ids[index], props, ^(id _) {
        dispatch_async(dispatch_get_main_queue(), ^{ DPFoldNext(delegate, browser, ids, index + 1, collapsed); });
    });
}

void DPSetAllGroupsCollapsed(BOOL collapsed) {
    id browser = DPCommandBrowser();
    id delegate = browser ? DPGroupingDelegate(browser) : nil;
    if (![delegate respondsToSelector:@selector(browser:getAllTabGroupsWithCompletion:)]) return;
    if (![delegate respondsToSelector:@selector(browser:updateTabGroupWithId:properties:completion:)]) return;
    void (*ask)(id, SEL, id, void (^)(NSArray *)) = (void *)objc_msgSend;
    ask(delegate, @selector(browser:getAllTabGroupsWithCompletion:), browser, ^(NSArray *groups) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![groups isKindOfClass:NSArray.class]) return;
            BOOL canTell = groups.count && [groups.firstObject respondsToSelector:@selector(collapsed)];
            NSMutableArray<NSString *> *ids = [NSMutableArray array];
            for (id info in groups) {
                if (canTell && DPMsgBool(info, @selector(collapsed)) == collapsed) continue;
                NSString *groupID = [info respondsToSelector:@selector(groupId)] ? DPText(DPMsg(info, @selector(groupId))) : nil;
                if (groupID.length) [ids addObject:[groupID copy]];
            }
            DPFoldNext(delegate, browser, ids, 0, collapsed);
        });
    });
}
