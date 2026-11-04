#import "TidyTabs.h"
#import "Commands/GroupTabs/GroupTabs.h"

// How many list items sit above Dia's divider in this window's sidebar: the pinned tabs. Read from the collection
// view's layout, which knows every row, not just the ones on screen. 0 when there's no divider.
static NSInteger DPTidyPinnedRows(NSWindow *window) {
    for (NSView *list in DPFindViews(DPDiaTabList)) {
        if (list.window != window || list.hiddenOrHasHiddenAncestor) continue;
        NSView *separator = DPTidySeparatorIn(list);
        NSCollectionView *collection = (NSCollectionView *)DPTidyListScroll(list).documentView;
        if (!separator || ![collection isKindOfClass:NSCollectionView.class]) return 0;
        CGFloat line = NSMinY([collection convertRect:separator.bounds fromView:separator]);
        NSInteger above = 0;
        for (NSInteger section = 0; section < collection.numberOfSections; section++)
            for (NSInteger item = 0; item < [collection numberOfItemsInSection:section]; item++) {
                NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:section];
                NSCollectionViewLayoutAttributes *attrs = [collection.collectionViewLayout layoutAttributesForItemAtIndexPath:path];
                if (attrs && NSMaxY(attrs.frame) <= line + 0.5) above++;
            }
        return above;
    }
    return 0;
}

// The front window's tabs below the divider, by URL, with their titles. Scripting lists tabs in sidebar order:
// favorites (isPinned), then the pinned tabs above the divider, then the rest. A URL open both above and below the
// divider is left out, since Chromium's tabs, which carry the sessions, can't tell those apart.
NSDictionary<NSString *, NSString *> *DPTidyLooseTabs(NSWindow *window) {
    NSArray *tabs = nil;
    for (id each in DPMsg(NSApp.delegate, @selector(appleScriptWindows))) {
        tabs = [each respondsToSelector:@selector(appleScriptTabs)] ? DPMsg(each, @selector(appleScriptTabs)) : nil;
        if ([tabs isKindOfClass:NSArray.class]) break;  // Front to back, so the first is the front window.
    }
    NSInteger pinnedRows = DPTidyPinnedRows(window);
    NSMutableDictionary<NSString *, NSString *> *loose = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *kept = [NSMutableSet set];
    for (id tab in [tabs isKindOfClass:NSArray.class] ? tabs : @[]) {
        NSString *url = [tab respondsToSelector:@selector(URL)] ? DPText(DPMsg(tab, @selector(URL))) : nil;
        if (!url.length) continue;
        BOOL favorite = [tab respondsToSelector:@selector(isPinned)] && DPMsgBool(tab, @selector(isPinned));
        if (favorite || pinnedRows-- > 0) { [kept addObject:url]; continue; }
        NSString *title = [tab respondsToSelector:@selector(title)] ? DPText(DPMsg(tab, @selector(title))) : nil;
        loose[url] = title.length ? title : url;
    }
    [loose removeObjectsForKeys:kept.allObjects];
    return loose;
}

// The site and path, without the query or fragment, which are mostly tracking and session noise: "apple.com/iphone-duo".
NSString *DPTidyAddress(NSString *url, NSString *host) {
    NSString *path = [NSURL URLWithString:url].path ?: @"";
    while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    NSString *address = [host stringByAppendingString:path];
    return address.length > 70 ? [address substringToIndex:70] : address;
}
