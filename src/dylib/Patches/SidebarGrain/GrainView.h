#import "StdPatch/StdPatch.h"

@interface DPSidebarGrainView : NSView
@property BOOL tracksWindowActivity;
- (void)setGrainAmount:(double)amount softness:(double)softness scale:(double)scale;
- (void)reloadSettings;
@end

static const CGFloat DPGrainTone = 0.88, DPGrainSpread = 0.068;

void DPBlurGrainPixels(uint8_t *pixels, NSInteger width, NSInteger height, NSUInteger passes);
void DPFitGrainTone(uint8_t *pixels, NSUInteger count);
CGImageRef DPFineGrainTile(void);
CGImageRef DPMatteGrainTile(BOOL soft);
NSArray<NSString *> *DPGrainMaterialKeys(void);
NSArray<NSString *> *DPGrainMaterialTitles(void);
BOOL DPIsPatternGrainMaterial(NSString *material);
CGImageRef DPPatternGrainTile(NSString *material, BOOL soft);

NSRect DPGrainHostBounds(NSView *host);

BOOL DPGrainDarkAppearance(NSAppearance *appearance);
CGImageRef DPGrainAppearanceTile(NSString *material, BOOL soft, BOOL dark, NSInteger scale);
