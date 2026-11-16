#import "AppIcon.h"
#import <objc/message.h>

// Don't force a redraw by touching the system icon style: it blinks every icon and can leave other apps' tiles wrong.
static NSUInteger DPHandbacks;
static BOOL DPSettingDockIcon, DPDrawsOwnTile;
static NSString *const DPOwnTileKey = @"appIconOwnTile";

static NSUserDefaults *DPTileDefaults(void) { return [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; }

// 0-2 are the default styles (automatic, light, dark), 3-5 clear, 6-8 tinted.
static unsigned DPIconStyle(void) {
    Class configuration = NSClassFromString(@"SLSIconAppearanceConfiguration");
    id current = ((id (*)(id, SEL))objc_msgSend)(configuration, NSSelectorFromString(@"fetchCurrentIconAppearanceConfiguration"));
    return current ? ((unsigned (*)(id, SEL))objc_msgSend)(current, NSSelectorFromString(@"iconAppearanceTheme")) : 1;
}

static void DPSetTileImage(NSImage *image) {
    DPSettingDockIcon = YES;
    NSApp.applicationIconImage = image;
    if (!image) {
        NSApp.dockTile.contentView = nil;
        [NSApp.dockTile display];
    }
    DPSettingDockIcon = NO;
}

static void DPDrawTile(void) {
    NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:NSBundle.mainBundle.bundlePath];
    icon.size = NSMakeSize(512, 512);
    unsigned style = DPIconStyle();
    BOOL dark = style == 5 || (style == 3 && [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]] == NSAppearanceNameDarkAqua);
    DPSetTileImage(style >= 3 && style <= 5 ? DPClearTile(icon, dark) : icon);
}

static void DPIconStyleDidChange(NSNotification *note) {
    if (!DPDrawsOwnTile) return;
    DPDrawTile();
    NSUInteger current = ++DPHandbacks;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 500), dispatch_get_main_queue(), ^{
        if (current != DPHandbacks || !DPDrawsOwnTile) return;
        DPDrawsOwnTile = NO;
        [DPTileDefaults() removeObjectForKey:DPOwnTileKey];
        DPSetTileImage(nil);
    });
}

void DPDrawOwnTile(void) {
    DPDrawsOwnTile = YES;
    [DPTileDefaults() setBool:YES forKey:DPOwnTileKey];
    DPDrawTile();
}

BOOL DPOwnTileInDock(void) { return [DPTileDefaults() boolForKey:DPOwnTileKey]; }

static void DPDockTile_setContentView(NSDockTile *self, SEL _cmd, NSView *view) {
    if (!DPAppIcon.on || DPSettingDockIcon) DPCallOriginal(DPDockTile_setContentView, self, view);
}

void DPInstallDockTile(void) {
    DPHook("NSDockTile", @selector(setContentView:), (IMP)DPDockTile_setContentView);
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:@"NSWorkspaceIconAppearanceConfigurationDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { DPIconStyleDidChange(note); }];
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:@"AppleInterfaceThemeChangedNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { DPIconStyleDidChange(note); }];
}
