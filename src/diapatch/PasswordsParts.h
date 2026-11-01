// Shared between the iCloud Passwords host and relay; Passwords.h is what the rest of diapatch uses.
#import <Foundation/Foundation.h>

extern const char *const DPAppleExtensions[2];
NSString *DPPasswordsSocket(NSString *home);

BOOL DPRunsPatchedDia(pid_t pid, NSString *app);
BOOL DPPatchedDiaRunning(NSString *app);
BOOL DPTrustedRelayPeer(int fd, NSString *app);

// The DevTools pipe to the original Dia.
void DPDevToolsAttach(int toDia, int fromDia);
void DPDevToolsCall(NSString *method, NSDictionary *params, NSString *session);
NSDictionary *DPDevToolsAsk(NSString *method, NSDictionary *params, NSString *session);
BOOL DPDevToolsRead(void);  // NO once Dia has closed the pipe
NSArray<NSDictionary *> *DPDevToolsTakeEvents(void);
int DPDevToolsInput(void);

// The original Dia, windowless, with the relay extension in it.
BOOL DPCopyStart(NSString *home);
void DPCopyEvaluate(NSString *expression);
void DPCopyQuit(void);
