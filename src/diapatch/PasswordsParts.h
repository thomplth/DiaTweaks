#import <Foundation/Foundation.h>

extern const char *const DPHandoffVariable;
NSString *DPAppleHelper(void);
NSString *DPOnePasswordHelper(void);
BOOL DPIsOnePasswordOrigin(const char *origin);
pid_t DPStartHelperThroughOriginal(NSString *home, NSString *helper, BOOL checksBrowser, int argc, const char *argv[]);

BOOL DPRunsPatchedDia(pid_t pid, NSString *app);
BOOL DPRunsThisDiapatch(audit_token_t token);
pid_t DPParentOf(pid_t pid);
