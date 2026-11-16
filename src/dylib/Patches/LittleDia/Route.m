#import "LittleDia.h"
#import <Carbon/Carbon.h>

static NSRect DPLittleDiaFrame(void) {
    NSScreen *screen = NSScreen.mainScreen;
    for (NSScreen *each in NSScreen.screens)
        if (NSMouseInRect(NSEvent.mouseLocation, each.frame, NO)) screen = each;
    NSRect visible = screen.visibleFrame;
    NSSize wanted = DPLittleDiaSize();
    NSSize size = NSMakeSize(round(MIN(wanted.width, NSWidth(visible) * 0.95)), round(MIN(wanted.height, NSHeight(visible) * 0.95)));
    return NSMakeRect(round(NSMidX(visible) - size.width / 2), round(NSMidY(visible) - size.height / 2), size.width, size.height);
}

static NSURL *DPLittleDiaLink(NSAppleEventDescriptor *event) {
    if (event.eventClass != kInternetEventClass || event.eventID != kAEGetURL) return nil;
    NSString *string = [event paramDescriptorForKeyword:keyDirectObject].stringValue;
    NSURL *url = string ? [NSURL URLWithString:string] : nil;
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqual:@"http"] && ![scheme isEqual:@"https"]) return nil;
    if ([event attributeDescriptorForKeyword:keySenderPIDAttr].int32Value == getpid()) return nil;
    if (NSEvent.modifierFlags & NSEventModifierFlagOption) return nil;
    return url;
}

// The worker drops requests after `until`, set before the link falls back to a tab, so no second copy opens.
static BOOL DPOpenInLittleDia(NSURL *url, NSDictionary *noted, void (^missed)(void), void (^claimed)(NSWindow *window)) {
    NSRect frame = DPLittleDiaFrame();
    CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame) - NSMaxY(frame);
    long long until = llround((NSDate.date.timeIntervalSince1970 + DPLittleDiaWait - 0.5) * 1000);
    NSDictionary *request = @{@"action" : @"open", @"url" : url.absoluteString, @"left" : @(NSMinX(frame)), @"top" : @(top),
                              @"width" : @(NSWidth(frame)), @"height" : @(NSHeight(frame)), @"until" : @(until)};
    if (!DPSendToLittleDia(request)) return NO;
    DPExpectLittleDiaWindow(frame, noted, missed, claimed);
    return YES;
}

// The stack is noted once, when the link arrives: noted again later it would find Dia in front.
static void DPOpenWhenReady(NSURL *url, NSDictionary *noted, void (^fallback)(void), int tries) {
    if (DPOpenInLittleDia(url, noted, fallback, nil)) return;
    if (tries <= 0 || !DPLittleDiaStarting()) return fallback();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DPOpenWhenReady(url, noted, fallback, tries - 1); });
}

static void DPOpenURLEvents_handle(id self, SEL _cmd, NSAppleEventDescriptor *event, NSAppleEventDescriptor *reply) {
    NSURL *url = DPLittleDia.on ? DPLittleDiaLink(event) : nil;
    if (!url) return DPCallOriginal(DPOpenURLEvents_handle, self, event, reply);
    DPLinkArrived();
    NSAppleEventDescriptor *kept = [event copy];  // The event is the system's and is gone once this returns.
    DPOpenWhenReady(url, DPNoteStackForLink(), ^{
        DPBringBackPutAway(nil);  // Not taken by Little Dia, so the tab opens in a window that must be showing.
        DPCallOriginal(DPOpenURLEvents_handle, self, kept, [NSAppleEventDescriptor nullDescriptor]);
    }, 40);
}

void DPOpenLinkInLittleDia(NSURL *url) {
    DPOpenInLittleDia(url, DPNoteStackForLink(), ^{ NSBeep(); }, nil);
}

void DPOpenBlankLittleDia(void) {
    DPOpenInLittleDia([NSURL URLWithString:@"about:blank"], DPNoteStackForLink(), ^{ NSBeep(); }, ^(NSWindow *window) { DPEditLittleDiaAddress(window); });
}

void DPInstallLittleDiaRoute(void) {
    DPHook(DPDiaOpenURLEvents, @selector(handleEvent:withReplyEvent:), (IMP)DPOpenURLEvents_handle);
}
