#import "AppIcon.h"
#import "IconCatalog.h"

// Dia's own icon isn't always named AppIcon (beta builds use AppIconBeta).
static NSString *const DPIconAlias = @"DiaChosenIcon", *const DPDefaultChoice = @"AppIcon", *const DPOwnIconKey = @"DiaTweaksOwnIcon";

static NSString *DPInfoPath(NSString *app) { return [app stringByAppendingPathComponent:@"Contents/Info.plist"]; }

static NSString *DPOwnIcon(NSString *app) {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:DPInfoPath(app)];
    NSString *name = info[DPOwnIconKey] ?: info[@"CFBundleIconName"];
    return name && ![name isEqual:DPIconAlias] ? name : DPDefaultChoice;
}

static NSString *DPIconsFolder(NSString *app, NSString *home) {
    NSString *build = [NSDictionary dictionaryWithContentsOfFile:DPInfoPath(app)][@"CFBundleVersion"];
    return build ? [home stringByAppendingPathComponent:[@"icons/builds" stringByAppendingPathComponent:build]] : nil;
}

static NSString *DPChosenIcon(NSString *app, NSString *base) {
    CFStringRef domain = CFSTR("com.diapatches");
    CFPreferencesAppSynchronize(domain);
    NSString *own = DPOwnIcon(app);
    if (!CFPreferencesGetAppBooleanValue(CFSTR("appIcon"), domain, NULL)) return own;
    NSString *icon = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("appIconChoice"), domain));
    if (![icon isKindOfClass:NSString.class] || [icon isEqual:DPDefaultChoice]) return own;
    return [DPOpenCatalog(base, NO).allRenditionNames containsObject:icon] ? icon : own;
}

static NSString *DPAddAlias(NSString *path, NSString *icon) {
    id<DPAssetStorage> catalog = DPOpenCatalog(path, YES);
    CGPoint hotSpot = CGPointZero;
    const DPKeyToken *key = [catalog renditionKeyForName:icon.UTF8String hotSpot:&hotSpot];
    if (!key) return [@"no icon named " stringByAppendingString:icon];
    DPKeyToken copy[32];
    int count = 0;
    for (; (key[count].attribute || key[count].value) && count < 31; count++) copy[count] = key[count];
    copy[count] = (DPKeyToken){0, 0};
    [catalog setRenditionKey:copy hotSpot:hotSpot forName:DPIconAlias.UTF8String];
    [catalog updateBitmapInfo];
    return [catalog writeToDiskAndCompact:YES] ? nil : @"couldn't write the catalog";
}

// Write beside and rename: Dia keeps reading the old file until it reopens the catalog.
static NSString *DPWriteCurrent(NSString *app, NSString *folder) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *base = [folder stringByAppendingPathComponent:@"base.car"], *current = [folder stringByAppendingPathComponent:@"current.car"];
    NSString *incoming = [current stringByAppendingString:@".new"];
    [files removeItemAtPath:incoming error:NULL];
    if (![files copyItemAtPath:base toPath:incoming error:NULL]) return @"couldn't copy the catalog";
    NSString *problem = DPAddAlias(incoming, DPChosenIcon(app, base));
    if (!problem && rename(incoming.fileSystemRepresentation, current.fileSystemRepresentation) != 0) problem = @"couldn't replace the catalog";
    [files removeItemAtPath:incoming error:NULL];
    return problem;
}

static NSArray<NSString *> *DPMissingIcons(NSString *catalog, NSString *home) {
    NSString *icons = [home stringByAppendingPathComponent:@"app-icons"];
    NSArray<NSString *> *present = DPOpenCatalog(catalog, NO).allRenditionNames;
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *name in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:icons error:NULL] sortedArrayUsingSelector:@selector(compare:)])
        if ([name.pathExtension isEqual:@"car"] && ![present containsObject:name.stringByDeletingPathExtension]) [missing addObject:[icons stringByAppendingPathComponent:name]];
    return missing;
}

static NSString *DPWriteBase(NSString *catalog, NSString *folder, NSString *home) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *base = [folder stringByAppendingPathComponent:@"base.car"], *incoming = [base stringByAppendingString:@".new"];
    [files removeItemAtPath:incoming error:NULL];
    if (![files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]) return @"couldn't make the icons folder";
    if (![files copyItemAtPath:catalog toPath:incoming error:NULL]) return @"couldn't copy Dia's catalog";
    for (NSString *icon in DPMissingIcons(incoming, home)) {
        NSString *problem = DPMergeCatalog(icon, incoming);
        if (problem) return [files removeItemAtPath:incoming error:NULL], [NSString stringWithFormat:@"%@: %@", icon.lastPathComponent, problem];
    }
    return rename(incoming.fileSystemRepresentation, base.fileSystemRepresentation) == 0 ? nil : @"couldn't save the catalog";
}

static void DPPruneBuilds(NSString *keep, NSString *alsoKeep) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *builds = keep.stringByDeletingLastPathComponent;
    for (NSString *name in [files contentsOfDirectoryAtPath:builds error:NULL]) {
        NSString *path = [builds stringByAppendingPathComponent:name];
        if (![path isEqual:keep] && ![path isEqual:alsoKeep]) [files removeItemAtPath:path error:NULL];
    }
}

NSString *DPPrepareIcons(NSString *app, NSString *installed, NSString *home) {
    NSString *folder = DPIconsFolder(app, home);
    NSString *catalog = [app stringByAppendingPathComponent:@"Contents/Resources/Assets.car"];
    if (!folder) return @"kept Dia's icons: no build number";
    NSString *problem = DPWriteBase(catalog, folder, home) ?: DPWriteCurrent(app, folder);
    if (problem) return [@"kept Dia's icons: " stringByAppendingString:problem];
    NSString *link = [catalog stringByAppendingString:@".link"];
    NSFileManager *files = NSFileManager.defaultManager;
    [files removeItemAtPath:link error:NULL];
    NSString *current = [folder stringByAppendingPathComponent:@"current.car"];
    if (![files createSymbolicLinkAtPath:link withDestinationPath:current error:NULL] || rename(link.fileSystemRepresentation, catalog.fileSystemRepresentation) != 0)
        return @"kept Dia's icons: couldn't link the catalog";
    NSURL *url = [NSURL fileURLWithPath:DPInfoPath(app)];
    NSMutableDictionary *info = [[NSMutableDictionary alloc] initWithContentsOfURL:url error:NULL];
    info[DPOwnIconKey] = DPOwnIcon(app);
    info[@"CFBundleIconName"] = DPIconAlias;
    if (![info writeToURL:url error:NULL]) return @"kept Dia's icon name: couldn't update Info.plist";
    DPPruneBuilds(folder, DPIconsFolder(installed, home));
    return @"linked Dia's catalog for icon switching";
}

NSString *DPSwitchIcon(NSString *app, NSString *home) {
    NSString *folder = DPIconsFolder(app, home), *base = [folder stringByAppendingPathComponent:@"base.car"];
    if (!folder || ![NSFileManager.defaultManager fileExistsAtPath:base]) return @"this Dia wasn't built for icon switching; run `diapatch install`";
    NSString *problem = (DPMissingIcons(base, home).count ? DPWriteBase(base, folder, home) : nil) ?: DPWriteCurrent(app, folder);
    if (problem) return problem;
    // IconServices caches by the bundle's date.
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate : NSDate.date} ofItemAtPath:app error:NULL];
    return nil;
}
