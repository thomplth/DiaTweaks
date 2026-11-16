#import "StdPatch/StdPatch.h"

extern DPPatch DPTidyTabs;
static const CGFloat DPTidyBrushSize = 22, DPTidyLineGap = 6;
static const NSInteger DPTidyMinimumTabs = 6;

@interface DPTidyHover : NSObject
@property (nonatomic, weak) NSView *list, *sidebar;
@property (nonatomic, strong) NSTrackingArea *tracking;
@property (nonatomic, strong) NSTimer *animation, *hideTimer;
@property (nonatomic) BOOL revealed;
@property (nonatomic) CGFloat progress;
+ (DPTidyHover *)forList:(NSView *)list;
+ (DPTidyHover *)attachToList:(NSView *)list;
- (void)detach;
- (void)track;
@end

@interface DPTidyBrush : NSButton
- (void)showBusy;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL plain;
@end
@interface DPTidyRowView : NSView
@end
DPTidyRowView *DPTidyRowIn(NSView *list, BOOL create);
NSHashTable<DPTidyBrush *> *DPTidyBrushes(void);
void DPTidySetBusy(BOOL busy);
BOOL DPTidyIsBusy(void);

void DPTidyWave(CALayer *host, CALayer *line, CGColorRef color, BOOL busy);

NSView *DPTidySeparatorIn(NSView *list);
void DPPlaceSeparatorBrush(NSView *separator);
NSInteger DPTidyTabsBelowLine(NSView *list);
void DPInstallTidySeparator(void);

void DPInstallTidyLayout(void);
void DPRelayoutTidyLists(void);
NSScrollView *DPTidyListScroll(NSView *list);
NSRect DPTidyHoverZone(NSView *list);

void DPTidyTabsNow(NSWindow *window);
NSString *DPTidyUnavailableReason(void);

NSDictionary<NSString *, NSString *> *DPTidyLooseTabs(NSWindow *window);
NSString *DPTidyAddress(NSString *url, NSString *host);
