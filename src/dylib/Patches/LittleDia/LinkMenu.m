#import "LittleDia.h"

static char DPItemKey;
static NSURL *gLink;
static NSDate *gLinkAt;

static NSString *const DPItemTitle = @"Open Link in Little Dia";

static BOOL DPPage_willShowMenu(id self, SEL _cmd, id page, id menu, id element) {
    NSURL *url = [element respondsToSelector:@selector(linkURL)] ? [element valueForKey:@"linkURL"] : nil;
    NSString *scheme = [url isKindOfClass:NSURL.class] ? url.scheme.lowercaseString : nil;
    BOOL web = [scheme isEqual:@"http"] || [scheme isEqual:@"https"];
    gLink = DPLittleDia.on && web ? url : nil;
    gLinkAt = NSDate.date;
    return DPCallOriginal(DPPage_willShowMenu, self, page, menu, element);
}

static void DPAddLinkItem(NSMenu *menu) {
    for (NSMenuItem *old in menu.itemArray)
        if (DPGet(old, &DPItemKey)) [menu removeItem:old];
    NSURL *url = gLink;
    BOOL fresh = gLinkAt.timeIntervalSinceNow > -2;
    gLink = nil;
    if (!url || !fresh || !DPLittleDia.on || !DPLittleDiaReady()) return;
    NSMenuItem *item = DPMenuItem(DPItemTitle, ^{ DPOpenLinkInLittleDia(url); });
    DPSet(item, &DPItemKey, @YES);
    NSInteger at = 0;
    for (NSMenuItem *each in menu.itemArray)
        if ([each.title rangeOfString:@"Open Link" options:NSCaseInsensitiveSearch | NSAnchoredSearch].location != NSNotFound) at = [menu indexOfItem:each] + 1;
    [menu insertItem:item atIndex:at];
}

static void DPMenu_popUpContext(id self, SEL _cmd, NSMenu *menu, NSEvent *event, NSView *view) {
    DPAddLinkItem(menu);
    DPCallOriginal(DPMenu_popUpContext, self, menu, event, view);
}

static void DPMenu_popUpContextFont(id self, SEL _cmd, NSMenu *menu, NSEvent *event, NSView *view, NSFont *font) {
    DPAddLinkItem(menu);
    DPCallOriginal(DPMenu_popUpContextFont, self, menu, event, view, font);
}

static BOOL DPMenu_popUpAt(NSMenu *self, SEL _cmd, NSMenuItem *item, NSPoint location, NSView *view) {
    DPAddLinkItem(self);
    return DPCallOriginal(DPMenu_popUpAt, self, item, location, view);
}

void DPInstallLittleDiaLinkMenu(void) {
    Class menus = object_getClass(NSMenu.class);
    DPHookClass(menus, @selector(popUpContextMenu:withEvent:forView:), (IMP)DPMenu_popUpContext);
    DPHookClass(menus, @selector(popUpContextMenu:withEvent:forView:withFont:), (IMP)DPMenu_popUpContextFont);
    DPHookClass(NSMenu.class, @selector(popUpMenuPositioningItem:atLocation:inView:), (IMP)DPMenu_popUpAt);
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:willShowContextMenu:withElement:), (IMP)DPPage_willShowMenu);
    });
}

NSString *DPLittleDiaLinkMenuProblem(void) {
    Class page = objc_getClass(DPDiaWebContent);
    if (class_getMethodImplementation(page, @selector(webContents:willShowContextMenu:withElement:)) != (IMP)DPPage_willShowMenu)
        return @"link menus don't reach Little Dia";
    return nil;
}
