#import "IconCatalog.h"
#import <dlfcn.h>

enum { DPElement = 1, DPPart = 2, DPAppearance = 7, DPIdentifier = 17, DPPackedElement = 9, DPIconImagePart = 220 };

id<DPAssetStorage> DPOpenCatalog(NSString *path, BOOL writing) {
    dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_NOW);
    return writing ? [[NSClassFromString(@"CUIMutableCommonAssetStorage") alloc] initWithPath:path forWriting:YES]
                   : [[NSClassFromString(@"CUICommonAssetStorage") alloc] initWithPath:path];
}

static int DPKeyIndex(const DPKeyFormat *format, uint32_t attribute) {
    for (uint32_t i = 0; i < format->count; i++) if (format->attributes[i] == attribute) return (int)i;
    return -1;
}

static NSString *DPCopyNames(id<DPAssetStorage> source, id<DPAssetStorage> catalog, NSSet *taken) {
    for (NSString *name in source.allRenditionNames) {
        CGPoint hotSpot = CGPointZero;
        const DPKeyToken *key = [source renditionKeyForName:name.UTF8String hotSpot:&hotSpot];
        for (const DPKeyToken *token = key; token && (token->attribute || token->value); token++)
            if (token->attribute == DPIdentifier && [taken containsObject:@(token->value)]) return [@"name collision on " stringByAppendingString:name];
        [catalog setRenditionKey:key hotSpot:hotSpot forName:name.UTF8String];
    }
    return nil;
}

static NSData *DPTranslateKey(const DPKeyToken *key, id<DPAssetStorage> source, id<DPAssetStorage> catalog) {
    const DPKeyFormat *format = catalog.keyFormat;
    NSMutableData *translated = [NSMutableData dataWithLength:format->count * sizeof(uint16_t)];
    uint16_t *slots = translated.mutableBytes;
    for (; key->attribute || key->value; key++) {
        uint16_t value = key->value;
        if (key->attribute == DPAppearance && value) {
            value = [catalog appearanceIdentifierForName:[source nameForAppearanceIdentifier:value]];
            if (!value) return nil;
        }
        int slot = DPKeyIndex(format, key->attribute);
        if (slot >= 0) slots[slot] = value;
        else if (value) return nil;
    }
    return translated;
}

NSString *DPMergeCatalog(NSString *sourcePath, NSString *catalogPath) {
    id<DPAssetStorage> catalog = DPOpenCatalog(catalogPath, YES), source = DPOpenCatalog(sourcePath, NO);
    if (!catalog || !source) return @"couldn't open the catalogs";
    __block unsigned count = 0;
    NSMutableSet *taken = [NSMutableSet set];
    [catalog enumerateKeysAndObjectsUsingBlock:^(const DPKeyToken *key, NSData *value) {
        count++;
        for (; key->attribute || key->value; key++) if (key->attribute == DPIdentifier) [taken addObject:@(key->value)];
    }];
    NSString *problem = DPCopyNames(source, catalog, taken);
    if (problem) return problem;
    NSMutableArray<NSArray *> *assets = [NSMutableArray array];
    __block BOOL translated = YES;
    [source enumerateKeysAndObjectsUsingBlock:^(const DPKeyToken *key, NSData *value) {
        uint16_t element = 0, part = 0;
        for (const DPKeyToken *token = key; token->attribute || token->value; token++) {
            if (token->attribute == DPElement) element = token->value;
            if (token->attribute == DPPart) part = token->value;
        }
        // The smallest flat sizes link into a shared atlas keyed like Dia's own; the layered stack draws them.
        if (element == DPPackedElement || (part == DPIconImagePart && value.length < 1024)) return;
        NSData *newKey = DPTranslateKey(key, source, catalog);
        if (newKey) [assets addObject:@[ newKey, value ]];
        else translated = NO;
    }];
    if (!translated) return @"the catalogs' key formats don't match";
    for (NSArray *asset in assets) if (![catalog setAsset:asset[1] forKey:asset[0]]) return @"couldn't add an asset";
    [catalog setRenditionCount:count + (unsigned)assets.count];
    [catalog updateBitmapInfo];
    return [catalog writeToDiskAndCompact:YES] ? nil : @"couldn't write the catalog";
}
