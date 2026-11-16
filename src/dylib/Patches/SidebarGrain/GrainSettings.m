#import "GrainSettings.h"

const DPGrainSetting DPGrainAmountSetting = {@"sidebarGrainAmount", @"Grain", 0, 100, 50};
const DPGrainSetting DPGrainSoftnessSetting = {@"sidebarGrainSoftness", @"Softness", 0, 100, 0};
const DPGrainSetting DPGrainScaleSetting = {@"sidebarGrainScale", @"Scale", 50, 300, 100};

NSUserDefaults *DPGrainDefaults(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return defaults;
}

static NSString *const DPGrainProfilesKey = @"sidebarGrainProfiles";

static NSDictionary *DPGrainProfile(NSString *space) {
    NSDictionary *profile = space ? [DPGrainDefaults() dictionaryForKey:DPGrainProfilesKey][space] : nil;
    return [profile isKindOfClass:NSDictionary.class] ? profile : nil;
}

void DPGrainSave(NSString *key, id value, NSString *space) {
    if (!space) return [DPGrainDefaults() setObject:value forKey:key];
    NSMutableDictionary *profiles = [[DPGrainDefaults() dictionaryForKey:DPGrainProfilesKey] mutableCopy] ?: [NSMutableDictionary new];
    NSMutableDictionary *profile = [DPGrainProfile(space) mutableCopy] ?: [NSMutableDictionary new];
    profile[key] = value;
    profiles[space] = profile;
    [DPGrainDefaults() setObject:profiles forKey:DPGrainProfilesKey];
}

BOOL DPGrainHasOverrides(NSString *space) { return DPGrainProfile(space).count > 0; }

void DPGrainClear(NSString *space) {
    NSMutableDictionary *profiles = [[DPGrainDefaults() dictionaryForKey:DPGrainProfilesKey] mutableCopy];
    profiles[space] = nil;
    if (profiles.count) [DPGrainDefaults() setObject:profiles forKey:DPGrainProfilesKey];
    else [DPGrainDefaults() removeObjectForKey:DPGrainProfilesKey];
}

NSInteger DPGrainValue(const DPGrainSetting *setting, NSString *space) {
    NSNumber *saved = DPGrainProfile(space)[setting->key];
    if (![saved isKindOfClass:NSNumber.class]) saved = [DPGrainDefaults() objectForKey:setting->key];
    return [saved isKindOfClass:NSNumber.class] ? MAX(setting->min, MIN(setting->max, saved.integerValue)) : setting->fallback;
}

NSInteger DPGrainAmount(NSString *space) { return DPGrainValue(&DPGrainAmountSetting, space); }
NSInteger DPGrainSoftness(NSString *space) { return DPGrainValue(&DPGrainSoftnessSetting, space); }
NSInteger DPGrainScale(NSString *space) { return DPGrainValue(&DPGrainScaleSetting, space); }

NSString *DPGrainMaterial(NSString *space) {
    NSString *material = DPGrainProfile(space)[DPSidebarGrain.choice];
    return [DPGrainMaterialKeys() containsObject:material] ? material : DPChoice(&DPSidebarGrain);
}

BOOL DPGrainShown(NSString *space) {
    return ![DPGrainProfile(space)[DPSidebarGrain.key] isEqual:@NO];
}

NSString *DPGrainSpaceOf(NSView *host) {
    __block NSString *space = nil;
    DPFindView(host, ^BOOL(NSView *view) {
        if (DPIsKind(view, DPDiaSpaceSwitcher)) {
            NSDictionary *items = DPSwiftValue(view, @"itemViews");
            for (id key in items) if ([DPSwiftValue(items[key], @"isSelected") boolValue]) space = [key description];
        } else if (DPIsKind(view, DPDiaPageIndicatorDot)) {
            space = [DPSwiftValue(view.superview, @"focusedSpaceID") description];
        }
        return space != nil;
    });
    return space;
}

NSMenu *DPGrainTextureMenu(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Texture"];
    [DPGrainMaterialTitles() enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        item.representedObject = DPGrainMaterialKeys()[i];
        [menu addItem:item];
    }];
    return menu;
}
