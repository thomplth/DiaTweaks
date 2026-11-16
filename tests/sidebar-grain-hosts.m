#import "sidebar-grain-render.h"

// Dia's Swift views answer for their properties through this.
@interface DPTestSwiftView : NSView
@property NSDictionary *itemViews;
@property BOOL isSelected;
@end
@implementation DPTestSwiftView
- (id)safeSwiftValueForKey:(NSString *)key { return [self valueForKey:key]; }
@end

static NSView *DPTestHostView(const char *name, NSRect frame) {
    Class cls = objc_getClass(name);
    if (!cls) {
        cls = objc_allocateClassPair(!strcmp(name, DPDiaSpaceSwitcher) ? DPTestSwiftView.class : NSView.class, name, 0);
        objc_registerClassPair(cls);
    }
    return [[cls alloc] initWithFrame:frame];
}

static NSUInteger DPTextureCount(NSView *host) {
    NSUInteger count = 0;
    for (NSView *view in host.subviews) count += [view isKindOfClass:DPSidebarGrainView.class];
    return count;
}

// Each window's grain follows the profile it shows, including when the profile switches.
static void DPTestTextureProfiles(NSWindow *window, NSView *sidebar, NSView *footer) {
    NSUserDefaults *defaults = DPGrainDefaults();
    [window.contentView addSubview:sidebar]; [sidebar addSubview:footer];
    DPTestSwiftView *switcher = (id)DPTestHostView(DPDiaSpaceSwitcher, NSMakeRect(0, 0, 100, 28));
    DPTestSwiftView *first = [DPTestSwiftView new], *second = [DPTestSwiftView new];
    switcher.itemViews = @{ @"A" : first, @"B" : second };
    first.isSelected = YES;
    [sidebar addSubview:switcher];
    assert([DPGrainSpaceOf(sidebar) isEqual:@"A"]);
    DPGrainSave(@"sidebarGrainAmount", @100, @"B");
    DPGrainSave(@"sidebarGrainMaterial", @"denim", @"B");
    DPGrainSave(@"sidebarGrain", @NO, @"A");
    DPRefreshSidebarGrain();
    DPSidebarGrainView *grain = (id)[sidebar.subviews filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self isKindOfClass: %@", DPSidebarGrainView.class]].firstObject;
    grain.tracksWindowActivity = NO;  // The test window is never active.
    [grain reloadSettings];
    assert(grain && [[grain valueForKey:@"_grainOpacity"] doubleValue] == 0);
    first.isSelected = NO; second.isSelected = YES;
    assert([DPGrainSpaceOf(sidebar) isEqual:@"B"]);
    DPRefreshSidebarGrain();
    assert([[grain valueForKey:@"_grainOpacity"] doubleValue] > 0.5 && [[grain valueForKey:@"_material"] isEqual:@"denim"]);
    [defaults removeObjectForKey:@"sidebarGrainProfiles"];
    DPRefreshSidebarGrain();
    assert([[grain valueForKey:@"_grainOpacity"] doubleValue] < 0.5 && ![[grain valueForKey:@"_material"] isEqual:@"denim"]);
    [switcher removeFromSuperview];
}

void DPTestTextureHosts(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSView *sidebar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 500)];
    NSView *footer = DPTestHostView(DPDiaSidebarFooter, NSMakeRect(0, 0, 200, 40));
    NSView *strip = DPTestHostView(DPDiaTabStrip, NSMakeRect(0, 460, 600, 40));
    NSView *content = DPTestHostView(DPDiaContentContainer, NSMakeRect(0, 0, 600, 480));
    [window.contentView addSubview:content];
    [window.contentView addSubview:sidebar]; [sidebar addSubview:footer];
    [window.contentView addSubview:strip];
    DPSidebarGrain.on = YES;
    DPTrackGrainHost(sidebar); DPTrackGrainHost(strip);
    assert(DPTextureCount(sidebar) == 1 && DPTextureCount(strip) == 0);
    sidebar.hidden = YES; footer.hidden = YES;
    DPRefreshSidebarGrain();
    assert(DPTextureCount(strip) == 0); // Auto-hiding does not turn on the horizontal background.
    [footer removeFromSuperview]; DPRefreshSidebarGrain();
    assert(DPTextureCount(sidebar) == 0 && DPTextureCount(strip) == 1);
    DPSidebarGrainView *grain = (id)strip.subviews.firstObject;
    assert([grain isKindOfClass:DPSidebarGrainView.class] && ![grain hitTest:NSMakePoint(10, 10)]);
    grain.frame = NSMakeRect(80, 0, 520, 40);
    assert(NSEqualRects(grain.frame, NSMakeRect(0, 20, 600, 20)));
    content.frame = NSMakeRect(0, 0, 600, 470); DPRefreshSidebarGrain();
    assert(NSEqualRects(grain.frame, NSMakeRect(0, 10, 600, 30)));
    // Another window's vertical sidebar must not suppress this horizontal strip.
    NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 500)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [other.contentView addSubview:sidebar]; [sidebar addSubview:footer];
    DPRefreshSidebarGrain(); assert(DPTextureCount(strip) == 1);
    DPTestTextureMenu(window, strip);
    DPSidebarGrain.on = NO; DPRefreshSidebarGrain();
    assert(DPTextureCount(sidebar) == 0 && DPTextureCount(strip) == 0);
    DPTrackGrainHost(sidebar); DPTrackGrainHost(strip); // Layouts while off leave Dia's views alone.
    assert(DPTextureCount(sidebar) == 0 && DPTextureCount(strip) == 0);
    DPSidebarGrain.on = YES; DPTrackGrainHost(strip);
    assert(DPTextureCount(strip) == 1);
    DPSidebarGrain.on = NO; DPTrackGrainHost(strip);
    assert(DPTextureCount(strip) == 0);
    [strip removeFromSuperview];
    DPSidebarGrain.on = YES;
    DPTestTextureProfiles(window, sidebar, footer);
    DPSidebarGrain.on = NO; DPRefreshSidebarGrain();
    [sidebar removeFromSuperview];
}
