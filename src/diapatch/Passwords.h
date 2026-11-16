#import <Foundation/Foundation.h>

extern NSString *const DPCopyFolder;

BOOL DPIsPasswordsOrigin(const char *origin);
BOOL DPIsPasswordsHandoff(int argc, const char *argv[]);
int DPRunPasswordsHost(NSString *home, NSString *app, int argc, const char *argv[]);
int DPRunPasswordsHandoff(void);
