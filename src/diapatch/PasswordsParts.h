// Shared between the iCloud Passwords host and its hand-off; Passwords.h is what the rest of diapatch uses.
#import <Foundation/Foundation.h>

extern const char *const DPAppleExtensions[2];
extern const char *const DPHandoffVariable;  // names the socket the original Dia's subprocess collects the host's stdio from

NSString *DPAppleHelper(void);

BOOL DPRunsPatchedDia(pid_t pid, NSString *app);
BOOL DPRunsThisDiapatch(audit_token_t token);
pid_t DPParentOf(pid_t pid);

// Apple's helper on this process's stdio, started by the original Dia, which has quit by the time this returns.
pid_t DPStartHelperThroughOriginal(NSString *home, int argc, const char *argv[]);
