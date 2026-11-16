#import "StdPatch/StdPatch.h"

extern DPPatch DPExtensionsShortcut;
static NSMapTable<NSWindow *, id> *DPBrowsers;

static NSDictionary *DPDefaultExtensionsShortcut(void) {
    return @{ @"keyCode" : @7, @"modifiers" : @(NSEventModifierFlagShift | NSEventModifierFlagCommand), @"key" : @"X" };
}

static void DPBrowser_setWindow(id self, SEL _cmd, NSWindow *window) {
    DPCallOriginal(DPBrowser_setWindow, self, window);
    if (window) [DPBrowsers setObject:self forKey:window];
}

// Chromium's icon can be blank, as Dark Reader's is, so a pinned extension's toolbar icon comes first.
static NSImage *DPIconFor(id info, NSWindow *window) {
    NSView *pinned = DPFindView(window.contentView, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaPinnedExtension) && [view.accessibilityLabel isEqualToString:[info valueForKey:@"name"]];
    });
    NSImage *icon = ((NSImageView *)DPFindView(pinned, ^BOOL(NSView *view) { return [view isKindOfClass:NSImageView.class]; })).image;
    icon = [icon ?: [info valueForKey:@"icon"] ?: [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension" accessibilityDescription:nil] copy];
    icon.size = NSMakeSize(16, 16);
    return icon;
}

static NSMenu *DPExtensionsMenu(id browser, NSWindow *window) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Extensions"];
    id extensions = [[browser performSelector:@selector(context)] performSelector:@selector(extensions)];
    NSArray *all = [[extensions performSelector:@selector(listExtensions)] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a valueForKey:@"name"] localizedCaseInsensitiveCompare:[b valueForKey:@"name"]];
    }];
    for (id info in all) {
        if (![[info valueForKey:@"enabled"] boolValue] || ![[info valueForKey:@"hasAction"] boolValue]) continue;
        NSString *extensionID = [info valueForKey:@"id"];
        NSMenuItem *item = DPMenuItem([info valueForKey:@"name"], ^{ [browser performSelector:@selector(executeExtensionAction:) withObject:extensionID]; });
        item.image = DPIconFor(info, window);
        [menu addItem:item];
    }
    if (!menu.numberOfItems) [menu addItemWithTitle:@"No Extensions" action:nil keyEquivalent:@""];
    return menu;
}

static void DPShowExtensions(NSWindow *window, id browser) {
    NSView *content = window.contentView;
    NSRect page = content.bounds;
    NSPoint corner = NSMakePoint(NSMaxX(page) - 240, content.isFlipped ? 48 : NSMaxY(page) - 48);
    [DPExtensionsMenu(browser, window) popUpMenuPositioningItem:nil atLocation:corner inView:content];
}

static void DPInstallExtensionsShortcut(void) {
    DPBrowsers = [NSMapTable weakToWeakObjectsMapTable];
    DPHook(DPDiaBrowser, @selector(setWindow:), (IMP)DPBrowser_setWindow);
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        NSWindow *window = event.window;
        id browser = window ? [DPBrowsers objectForKey:window] : nil;
        if (!DPExtensionsShortcut.on || !browser || !DPShortcutMatches(event, &DPExtensionsShortcut)) return event;
        if (!event.isARepeat) dispatch_async(dispatch_get_main_queue(), ^{ DPShowExtensions(window, browser); });  // The menu's loop would block this key.
        return nil;
    }];
}

DP_PATCH(DPExtensionsShortcut) {
    .key = @"extensionsShortcut",
    .order = 63,
    .title = @"Extensions Shortcut",
    .detail = @"Press a shortcut, ⇧⌘X unless you set another, for a menu of your extensions. Choosing one opens it as its toolbar button would.",
    .symbol = @"puzzlepiece.extension.fill puzzlepiece.fill",
    .tint = @"systemIndigoColor",
    .section = @"Toolbar",
    .classes = DPClasses(DPDiaBrowser),
    .install = DPInstallExtensionsShortcut,
    .shortcut = @"extensionsMenuShortcut",
    .defaultShortcut = DPDefaultExtensionsShortcut,
};
