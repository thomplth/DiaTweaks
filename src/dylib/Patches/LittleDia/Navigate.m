#import "LittleDia.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import <objc/message.h>

static id DPNavigation(NSWindow *window) {
    id page = DPLittleDiaPage(window);
    return [page respondsToSelector:@selector(navigationController)] ? ((id (*)(id, SEL))objc_msgSend)(page, @selector(navigationController)) : nil;
}

void DPLittleDiaGo(NSWindow *window, SEL action) {
    id navigation = DPNavigation(window);
    if ([navigation respondsToSelector:action]) ((id (*)(id, SEL))objc_msgSend)(navigation, action);
}

NSDictionary *DPLittleDiaTab(NSWindow *window, NSString *action) {
    return @{@"action" : action, @"tabId" : @(DPSessionOf(DPLittleDiaPage(window))), @"url" : DPLittleDiaURL(window)};
}

NSString *DPLittleDiaURL(NSWindow *window) {
    NSURL *url = ((id (*)(id, SEL))objc_msgSend)(DPLittleDiaPage(window), @selector(url));
    return [url isKindOfClass:NSURL.class] ? url.absoluteString : @"";
}

void DPLittleDiaNavigate(NSWindow *window, NSString *typed) {
    NSString *text = [typed stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *url = DPAddressURL(text);
    id navigation = DPNavigation(window);
    if (url && [navigation respondsToSelector:@selector(load:initiatorOrigin:)])
        return (void)((id (*)(id, SEL, NSURL *, id))objc_msgSend)(navigation, @selector(load:initiatorOrigin:), url, nil);
    if (url || !text.length) return;
    NSMutableDictionary *request = [DPLittleDiaTab(window, @"search") mutableCopy];
    request[@"text"] = text;
    DPSendToLittleDia(request);
}
