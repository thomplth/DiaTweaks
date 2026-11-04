// Tidy Tabs: while the pointer is over the sidebar, a broom button shows above the tabs. With pinned tabs in the list it
// sits in Dia's divider beside Close All; otherwise a row with a line like that divider opens above the tabs.
#import "StdPatch/StdPatch.h"

extern DPPatch DPTidyTabs;
static const CGFloat DPTidyRowHeight = 24, DPTidyBrushSize = 22, DPTidyTabRowHeight = 40;
static const NSInteger DPTidyMinimumTabs = 6;  // The broom only shows with more than 5 tabs below the divider.

// Hover.m: one per tab list. Follows the pointer over the sidebar and eases `progress` toward `revealed` while it's on the divider.
@interface DPTidyHover : NSObject
@property (nonatomic, weak) NSView *list, *sidebar;
@property (nonatomic, strong) NSTrackingArea *tracking;
@property (nonatomic, strong) NSTimer *animation, *hideTimer;
@property (nonatomic) BOOL revealed;
@property (nonatomic) CGFloat progress;
+ (DPTidyHover *)forList:(NSView *)list;
+ (DPTidyHover *)attachToList:(NSView *)list;
- (void)detach;  // Collapses at once and stops tracking.
- (void)track;   // Opens or closes the row for where the pointer is now.
@end

// Brush.m: the broom button. Row.m: the row it sits in when Dia has no divider for it.
@interface DPTidyBrush : NSButton
- (void)showBusy;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL plain;  // Only the icon brightens on hover, like Close All; no background.
@end
@interface DPTidyRowView : NSView
@end
DPTidyRowView *DPTidyRowIn(NSView *list, BOOL create);
NSHashTable<DPTidyBrush *> *DPTidyBrushes(void);  // Every broom, in any window.
void DPTidyBrushesBusy(BOOL busy);  // Waves the lines while the model works; clicks then do nothing.
BOOL DPTidyIsBusy(void);

// Wave.m: while `busy`, `line` (a sublayer of `host`) is hidden under a rolling wave of `color`; after, it comes back.
void DPTidyWave(CALayer *host, CALayer *line, CGColorRef color, BOOL busy);

// Separator.m: the broom in Dia's divider between pinned and other tabs.
NSView *DPTidySeparatorIn(NSView *list);
void DPPlaceSeparatorBrush(NSView *separator);
NSInteger DPTidyTabsBelowLine(NSView *list);  // Shows the broom while Close All shows.
void DPInstallTidySeparator(void);

// Layout.m
void DPInstallTidyLayout(void);
void DPRelayoutTidyLists(void);
NSScrollView *DPTidyListScroll(NSView *list);
NSRect DPTidyHoverZone(NSView *list);

void DPTidyTabsNow(NSWindow *window);  // Action.m
NSString *DPTidyUnavailableReason(void);  // Model.swift: why Apple Intelligence can't tidy now, or nil.

// Tabs.m: which tabs a tidy looks at.
NSDictionary<NSString *, NSString *> *DPTidyLooseTabs(NSWindow *window);  // URL to title, below the divider.
NSString *DPTidyAddress(NSString *url, NSString *host);  // "apple.com/iphone-duo": site and path, no query.
