#import <Foundation/Foundation.h>

// `installed` is the Dia in use: its icons folder survives the pruning.
NSString *DPPrepareIcons(NSString *app, NSString *installed, NSString *home);

// nil on success, else the problem.
NSString *DPSwitchIcon(NSString *app, NSString *home);
