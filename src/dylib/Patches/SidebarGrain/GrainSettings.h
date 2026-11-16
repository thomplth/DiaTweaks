#import "SidebarGrain.h"

typedef struct {
    __unsafe_unretained NSString *key, *title;
    NSInteger min, max, fallback;
} DPGrainSetting;

extern const DPGrainSetting DPGrainAmountSetting, DPGrainSoftnessSetting, DPGrainScaleSetting;

NSUserDefaults *DPGrainDefaults(void);
NSInteger DPGrainValue(const DPGrainSetting *setting, NSString *space);
void DPGrainSave(NSString *key, id value, NSString *space);
void DPGrainClear(NSString *space);
