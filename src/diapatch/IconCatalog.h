#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

typedef struct { uint16_t attribute, value; } DPKeyToken;
typedef struct { uint32_t tag, version, count; uint32_t attributes[]; } DPKeyFormat;

@protocol DPAssetStorage <NSObject>
- (instancetype)initWithPath:(NSString *)path;
- (instancetype)initWithPath:(NSString *)path forWriting:(BOOL)writing;
- (const DPKeyFormat *)keyFormat;
- (NSArray<NSString *> *)allRenditionNames;
- (const DPKeyToken *)renditionKeyForName:(const char *)name hotSpot:(CGPoint *)hotSpot;
- (BOOL)enumerateKeysAndObjectsUsingBlock:(void (^)(const DPKeyToken *key, NSData *value))block;
- (NSString *)nameForAppearanceIdentifier:(uint16_t)identifier;
- (uint16_t)appearanceIdentifierForName:(NSString *)name;
- (BOOL)setAsset:(NSData *)asset forKey:(NSData *)key;
- (void)setRenditionKey:(const DPKeyToken *)key hotSpot:(CGPoint)hotSpot forName:(const char *)name;
- (void)setRenditionCount:(unsigned)count;
- (void)updateBitmapInfo;
- (BOOL)writeToDiskAndCompact:(BOOL)compact;
@end

id<DPAssetStorage> DPOpenCatalog(NSString *path, BOOL writing);

// nil on success, else the problem.
NSString *DPMergeCatalog(NSString *sourcePath, NSString *catalogPath);
