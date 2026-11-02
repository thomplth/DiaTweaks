#import <Foundation/Foundation.h>

BOOL DPIsPasswordsOrigin(const char *origin);
BOOL DPIsPasswordsHandoff(int argc, const char *argv[]);
int DPRunPasswordsHost(NSString *home, NSString *app, int argc, const char *argv[]);  // Started by a browser for iCloud Passwords.
int DPRunPasswordsHandoff(void);                                                     // Started by the original Dia as its subprocess.
