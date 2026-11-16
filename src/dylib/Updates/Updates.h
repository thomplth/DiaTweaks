#import "StdPatch/StdPatch.h"

void DPInstallUpdates(void);
void DPRunCLI(NSArray<NSString *> *args, void (^completion)(NSString *output));
void DPRunCLIReporting(NSArray<NSString *> *args, void (^completion)(NSString *output, NSString *reason));
void DPHandOffAndQuit(NSArray<NSString *> *args);
BOOL DPCLITrusted(void);

extern NSString *const DPDia, *const DPTweaks;
NSString *DPPartName(NSString *part);

typedef NS_ENUM(NSInteger, DPAutoLevel) { DPAutoOff, DPAutoNotify, DPAutoDownload, DPAutoInstall };
DPAutoLevel DPAutoLevelOf(NSString *part);
void DPSetAutoLevel(NSString *part, DPAutoLevel level);
BOOL DPIsLocalBuild(NSString *part);

extern NSNotificationName const DPUpdatesDidChangeNotification;

@interface DPUpdates : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSDictionary *found;
@property (nonatomic, readonly) BOOL checking;
@property (nonatomic, readonly) NSString *checkProblem;
- (void)check:(void (^)(void))done;
- (BOOL)available:(NSString *)part;
- (BOOL)staged:(NSString *)part;
- (BOOL)downloading:(NSString *)part;
- (BOOL)failed:(NSString *)part;
- (NSString *)failure:(NSString *)part;
- (double)progress:(NSString *)part;  // 0–1 while downloading, -1 while it's verified and patched.
- (void)download:(NSString *)part then:(void (^)(void))done;
- (void)installAndRelaunch:(NSArray<NSString *> *)parts;

- (void)pretend:(NSString *)part;
- (void)stopPretending;
@end
