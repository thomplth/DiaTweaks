#import "sidebar-grain-render.h"

static NSArray<NSString *> *DPSeenMenu;
static void DPRecordMenu(id self, SEL cmd, NSMenu *menu, NSEvent *event, NSView *view) {
    DPSeenMenu = [menu.itemArray valueForKey:@"title"];
}

@interface DPTextureMenuBody : NSView
@end
@implementation DPTextureMenuBody
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:@"Show Tabs in Sidebar" action:NULL keyEquivalent:@""];
    [menu addItemWithTitle:@"Auto-Hide Tabs" action:NULL keyEquivalent:@""];
    [menu addItemWithTitle:@"Close All Tabs" action:NULL keyEquivalent:@""];
    return menu;
}
@end

void DPTestTextureMenu(NSWindow *window, NSView *strip) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DPHookClass(object_getClass(NSMenu.class), @selector(popUpContextMenu:withEvent:forView:), (IMP)DPRecordMenu);
    });
    DPTextureMenuBody *body = [[DPTextureMenuBody alloc] initWithFrame:strip.bounds];
    [strip addSubview:body];
    NSPoint point = [strip convertPoint:NSMakePoint(300, 20) toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0
        timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:0];
    DPSeenMenu = nil;
    assert(DPGrainRightClick(event) == nil);
    assert(([DPSeenMenu isEqual:@[@"Show Tabs in Sidebar", @"Auto-Hide Tabs", @"Edit Sidebar Grain…", @"Close All Tabs"]]));
    // Full-height controls must retain their own menus, even at the same location.
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(280, 0, 40, NSHeight(strip.bounds))];
    [body addSubview:button]; DPSeenMenu = nil;
    assert(DPGrainRightClick(event) == event && !DPSeenMenu);
    [button removeFromSuperview]; [body removeFromSuperview];
}
