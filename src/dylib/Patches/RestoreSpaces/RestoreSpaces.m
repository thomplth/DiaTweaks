#import "StdPatch/StdPatch.h"

typedef int DPConnection;
typedef uint64_t DPSpaceID;
extern DPConnection CGSMainConnectionID(void);
extern CFArrayRef CGSCopyManagedDisplaySpaces(DPConnection connection);
extern CFArrayRef CGSCopySpacesForWindows(DPConnection connection, int mask, CFArrayRef windows);
extern void CGSMoveWindowsToManagedSpace(DPConnection connection, CFArrayRef windows, DPSpaceID space);

enum { DPAllSpaces = 7, DPDesktopSpace = 0 };

@interface NSObject (DPArcBrowser)
- (NSString *)windowIdentifier;
@end

extern DPPatch DPRestoreSpaces;

static NSString *const DPSavedSpacesKey = @"windowSpaces";
static const NSUInteger DPSavedSpacesLimit = 50;
static NSUserDefaults *DPDefaults;
static NSMapTable<NSWindow *, id> *DPBrowserByWindow;
static NSMapTable<NSWindow *, NSString *> *DPPlacedAs;

// Desktops by ManagedSpaceID. Full-screen spaces are left out: Dia puts full-screen windows back itself.
static NSDictionary<NSNumber *, NSDictionary *> *DPDesktops(void) {
    NSMutableDictionary *desktops = [NSMutableDictionary new];
    NSArray *displays = CFBridgingRelease(CGSCopyManagedDisplaySpaces(CGSMainConnectionID()));
    for (NSDictionary *display in displays)
        for (NSDictionary *space in display[@"Spaces"])
            if ([space[@"type"] intValue] == DPDesktopSpace) desktops[space[@"ManagedSpaceID"]] = space;
    return desktops;
}

static NSDictionary *DPDesktopOf(NSWindow *window, NSDictionary<NSNumber *, NSDictionary *> *desktops) {
    if (window.windowNumber <= 0) return nil;
    NSArray *spaces = CFBridgingRelease(CGSCopySpacesForWindows(CGSMainConnectionID(), DPAllSpaces, (__bridge CFArrayRef)@[@(window.windowNumber)]));
    return spaces.count == 1 ? desktops[spaces.firstObject] : nil;
}

// ManagedSpaceIDs are renumbered when macOS restarts, so a desktop is looked up by its UUID first.
static NSNumber *DPResolve(NSDictionary *saved, NSDictionary<NSNumber *, NSDictionary *> *desktops) {
    NSString *uuid = saved[@"uuid"];
    if (uuid.length)
        for (NSDictionary *desktop in desktops.allValues)
            if ([desktop[@"uuid"] isEqual:uuid]) return desktop[@"ManagedSpaceID"];
    return desktops[saved[@"id"]] ? saved[@"id"] : nil;
}

static NSString *DPIdentifierOf(NSWindow *window) {
    id browser = [DPBrowserByWindow objectForKey:window];
    NSString *identifier = [browser respondsToSelector:@selector(windowIdentifier)] ? [browser windowIdentifier] : nil;
    return identifier.length ? identifier : nil;
}

static NSDictionary *DPSavedSpaces(void) {
    return [DPDefaults dictionaryForKey:DPSavedSpacesKey] ?: @{};
}

static NSDictionary *DPKeepNewest(NSDictionary<NSString *, NSDictionary *> *saved) {
    if (saved.count <= DPSavedSpacesLimit) return saved;
    NSArray *newestFirst = [saved keysSortedByValueUsingComparator:^(NSDictionary *a, NSDictionary *b) { return [b[@"seen"] compare:a[@"seen"]]; }];
    return [saved dictionaryWithValuesForKeys:[newestFirst subarrayWithRange:NSMakeRange(0, DPSavedSpacesLimit)]];
}

// Windows closed while Dia quits must keep their entries, so each save only adds to what's there.
static void DPSaveSpaces(void) {
    if (!DPRestoreSpaces.on) return;
    NSDictionary *desktops = DPDesktops();
    NSMutableDictionary *saved = [DPSavedSpaces() mutableCopy];
    BOOL changed = NO;
    for (NSWindow *window in DPPlacedAs.keyEnumerator.allObjects) {
        NSString *identifier = DPIdentifierOf(window);
        NSDictionary *desktop = DPDesktopOf(window, desktops);
        if (![identifier isEqual:[DPPlacedAs objectForKey:window]] || !desktop) continue;
        NSDictionary *entry = @{@"id": desktop[@"ManagedSpaceID"], @"uuid": desktop[@"uuid"] ?: @"", @"seen": NSDate.date};
        NSDictionary *previous = saved[identifier];
        if ([previous[@"id"] isEqual:entry[@"id"]] && [previous[@"uuid"] isEqual:entry[@"uuid"]]) continue;
        saved[identifier] = entry;
        changed = YES;
    }
    if (changed) [DPDefaults setObject:DPKeepNewest(saved) forKey:DPSavedSpacesKey];
}

static NSUInteger DPLatestSaveRequest;

static void DPSaveSpacesSoon(void) {
    NSUInteger request = ++DPLatestSaveRequest;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (request == DPLatestSaveRequest) DPSaveSpaces();
    });
}

static NSArray<NSNumber *> *DPWindowNumbersWithChildren(NSWindow *window) {
    NSMutableArray *numbers = [NSMutableArray arrayWithObject:@(window.windowNumber)];
    for (NSWindow *child in window.childWindows) [numbers addObjectsFromArray:DPWindowNumbersWithChildren(child)];
    return numbers;
}

static void DPMoveToSavedSpace(NSWindow *window, NSString *identifier) {
    NSDictionary *saved = DPSavedSpaces()[identifier];
    if (!saved || (window.styleMask & NSWindowStyleMaskFullScreen)) return;
    NSDictionary *desktops = DPDesktops();
    NSNumber *target = DPResolve(saved, desktops);
    NSDictionary *current = DPDesktopOf(window, desktops);
    if (!target || !current || [current[@"ManagedSpaceID"] isEqual:target]) return;
    CGSMoveWindowsToManagedSpace(CGSMainConnectionID(), (__bridge CFArrayRef)DPWindowNumbersWithChildren(window), target.unsignedLongLongValue);
}

static BOOL DPIsPlaced(NSWindow *window) {
    NSString *identifier = DPIdentifierOf(window);
    return identifier && [identifier isEqual:[DPPlacedAs objectForKey:window]];
}

// A window is placed the first time it's on screen while its browser knows which saved window it is, and again if
// that identifier changes. Until then it sits on whichever Space Dia opened it on, so it isn't saved: that would
// overwrite where it belongs. Dia can hold windows back for a long time, behind the keychain prompt after an install
// for one, so nothing here gives up waiting.
static void DPPlace(NSWindow *window) {
    if (!window || !DPRestoreSpaces.on || !window.visible || window.windowNumber <= 0 || DPIsPlaced(window)) return;
    NSString *identifier = DPIdentifierOf(window);
    if (!identifier) return;
    DPMoveToSavedSpace(window, identifier);
    [DPPlacedAs setObject:identifier forKey:window];
    DPSaveSpacesSoon();
}

static void DPPlaceSoon(NSWindow *window) {
    __weak NSWindow *weakWindow = window;
    dispatch_async(dispatch_get_main_queue(), ^{ DPPlace(weakWindow); });
}

static const NSTimeInterval DPUnplacedCheckInterval = 0.25;
static const NSTimeInterval DPUnplacedCheckLimit = 120;

// Showing a window calls the hooks below, but Dia can give a shown window its identifier later without any of them.
static void DPPlaceUnplacedWindows(NSDate *since) {
    BOOL waiting = NO;
    for (NSWindow *window in DPBrowserByWindow.keyEnumerator.allObjects) {
        DPPlace(window);
        waiting |= window.visible && !DPIsPlaced(window);
    }
    if (!waiting || !DPRestoreSpaces.on || -since.timeIntervalSinceNow > DPUnplacedCheckLimit) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DPUnplacedCheckInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DPPlaceUnplacedWindows(since);
    });
}

static void DPBrowser_setWindow(id self, SEL _cmd, NSWindow *window) {
    DPCallOriginal(DPBrowser_setWindow, self, window);
    if (!window) return;
    [DPBrowserByWindow setObject:self forKey:window];
    dispatch_async(dispatch_get_main_queue(), ^{ DPPlaceUnplacedWindows(NSDate.date); });
}

static void DPWindow_orderWindow(NSWindow *self, SEL _cmd, NSWindowOrderingMode place, NSInteger otherWindow) {
    DPCallOriginal(DPWindow_orderWindow, self, place, otherWindow);
    if (place != NSWindowOut && [DPBrowserByWindow objectForKey:self] && !DPIsPlaced(self)) DPPlaceSoon(self);
}

static void DPApplyRestoreSpaces(DPPatch *patch) {
    if (!patch->on) return;
    for (NSWindow *window in DPBrowserByWindow.keyEnumerator.allObjects) {
        NSString *identifier = DPIdentifierOf(window);
        if (identifier) [DPPlacedAs setObject:identifier forKey:window];
    }
    DPSaveSpacesSoon();
}

static void DPInstallRestoreSpaces(void) {
    DPDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    DPBrowserByWindow = [NSMapTable weakToWeakObjectsMapTable];
    DPPlacedAs = [NSMapTable weakToStrongObjectsMapTable];
    DPHook(DPDiaBrowser, @selector(setWindow:), (IMP)DPBrowser_setWindow);
    DPHookClass(NSWindow.class, @selector(orderWindow:relativeTo:), (IMP)DPWindow_orderWindow);

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidChangeOcclusionStateNotification])
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            if (![DPBrowserByWindow objectForKey:note.object]) return;
            if (DPIsPlaced(note.object)) DPSaveSpacesSoon();
            else DPPlaceSoon(note.object);
        }];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification object:nil queue:nil
                                                            usingBlock:^(NSNotification *_) { DPSaveSpacesSoon(); }];
}

DP_PATCH(DPRestoreSpaces) {
    .key = @"restoreSpaces",
    .order = 92,
    .title = @"Reopen windows on their Spaces",
    .detail = @"When Dia restarts, after an update for example, each window goes back to the desktop Space it was on instead of all opening on the current one.",
    .symbol = @"rectangle.3.group",
    .tint = @"systemTealColor",
    .section = @"Window",
    .page = @"https://github.com/thomplth/DiaTweaks/blob/main/docs/tweaks/Reopen-windows-on-their-Spaces.md",
    .classes = DPClasses(DPDiaBrowser),
    .install = DPInstallRestoreSpaces,
    .apply = DPApplyRestoreSpaces,
};
