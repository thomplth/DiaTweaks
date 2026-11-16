#import "StdPatch/StdPatch.h"

typedef struct { uint32_t value, mask; } DPSkipInstruction;
uint32_t *DPSkipFindCode(const DPSkipInstruction *signature, NSUInteger length);
BOOL DPSkipWriteCode(uint32_t *site, uint32_t expected, uint32_t value);
BOOL DPSkipAccountStartup(void);
void DPSkipAccountMenus(void);
void DPSkipAccountSettings(void);
NSString *DPSkipVerifyAccountSettings(void);
