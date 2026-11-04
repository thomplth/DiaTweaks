// Shared between the passwords host, its hand-off and the relay; Passwords.h is what the rest of diapatch uses.
#import <Foundation/Foundation.h>

// `key` gives the relay extension the manager's extension ID, as each helper only answers its own extension.
typedef struct {
    const char *origins[3];
    const char *host;
    const char *key;
    const char *socket;
} DPPasswordsService;

// The managers relayed through the original Dia. Apple's helper only checks its parent as it starts, so it isn't one.
enum { DPPasswordsServiceCount = 1 };
extern const DPPasswordsService DPPasswordsServices[DPPasswordsServiceCount];
const DPPasswordsService *DPPasswordsServiceFor(const char *origin);
NSString *DPPasswordsSocket(NSString *home, const DPPasswordsService *service);

extern const char *const DPHandoffVariable;  // names the socket the original Dia's subprocess collects the host's stdio from
NSString *DPAppleHelper(void);
// Apple's helper on this process's stdio, started by the original Dia, which has quit by the time this returns.
pid_t DPStartHelperThroughOriginal(NSString *home, int argc, const char *argv[]);

BOOL DPRunsPatchedDia(pid_t pid, NSString *app);
BOOL DPRunsThisDiapatch(audit_token_t token);
pid_t DPParentOf(pid_t pid);
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
void DPCopyEvaluate(const DPPasswordsService *service, NSString *expression);
void DPCopyQuit(void);
