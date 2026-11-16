#import "StdPatch/StdPatch.h"
#include <stdatomic.h>

extern DPPatch DPSplitClientHello;
extern _Atomic bool DPSplitting;  // On, and Dia's network service runs in this process.
void DPInstallSplitSend(void);
