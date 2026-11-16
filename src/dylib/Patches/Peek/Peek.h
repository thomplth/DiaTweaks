#import "StdPatch/StdPatch.h"

extern DPPatch DPPeek, DPPeekPinnedLinks;

typedef NS_ENUM(NSInteger, DPPeekExit) { DPPeekClose, DPPeekTab, DPPeekSplit };  // Also the controls' button tags.
typedef NS_ENUM(NSInteger, DPPeekStep) { DPPeekBack, DPPeekForward, DPPeekReload };

// Dia's ArcWebContentsNavigationDisposition, numbered differently from Chromium's.
enum { DPIgnoreAction = 0, DPCurrentTab = 1, DPForegroundTab = 2, DPBackgroundTab = 3, DPNewWindow = 5, DPPopup = 6, DPSplitView = 9 };

@protocol DPPeekPage <NSObject>
- (NSView *)createPaneHostView;
- (void)attachToPaneHostView:(NSView *)host;
- (void)detachFromPaneHostView:(NSView *)host;
@end

@interface DPPeekCard : NSView
@property (nonatomic, strong) NSView *dim, *card, *shade, *clip, *host, *controls, *tabBadge, *toolbar, *toolbarZone;
@property (nonatomic, strong) id<DPPeekPage> page;
@property (nonatomic, weak) id sourceDelegate, source;
@property (nonatomic, weak) NSView *pane;
@property (nonatomic, strong) id paneObserver, monitor;
@property (nonatomic) NSRect link;
@property (nonatomic) CGFloat grown;
@property (nonatomic) BOOL closing;
@property (nonatomic) NSInteger paneMoves;
- (NSRect)cardFrame;
- (void)close:(DPPeekExit)exit;
- (void)handOver;
@end

@interface DPPeekCard (Motion)
- (void)animateIn;
- (void)animateOut:(void (^)(void))completion;
- (void)animateExpand:(void (^)(void))completion;
@end

@interface DPPeekCard (Handoff)
- (void)finish:(DPPeekExit)exit;
@end

DPPeekCard *DPPeekCardIn(NSWindow *window);
DPPeekCard *DPPeekShowCard(NSWindow *window, id<DPPeekPage> page, NSView *warmHost, NSRect screenLink);
NSView *DPPeekWarmHost(NSWindow *window, id<DPPeekPage> page);

NSView *DPPeekControls(id target, SEL action);
extern const CGFloat DPPeekToolbarHeight;
NSView *DPPeekToolbarFor(id page);
void DPPeekAddToolbar(DPPeekCard *peek);
CGFloat DPPeekToolbarInset(DPPeekCard *peek);
void DPPeekPlaceToolbar(DPPeekCard *peek);
void DPPeekNavigate(id page, DPPeekStep step);
NSView *DPPeekToolbarAddress(NSView *toolbar);
NSView *DPPeekAddressFor(id page);
NSView *DPPeekGlowFor(id page);
void DPPeekRefreshAddress(NSView *address);
void DPPeekEditAddress(NSView *address);
BOOL DPPeekEditingAddress(NSView *address);
void DPPeekEditToolbarAddress(DPPeekCard *peek);
NSURL *DPPeekSearchURL(id page, NSString *text);
BOOL DPPeekCopyURL(DPPeekCard *peek, NSEvent *event);
BOOL DPPeekIsShortcut(NSEvent *event, NSMenuItem *item);
BOOL DPPeekZoomShortcut(DPPeekCard *peek, NSEvent *event);
void DPPeekInstallZoom(void);
NSString *DPPeekZoomProblem(void);
void DPPeekLayoutHints(NSView *controls, CGFloat availableRight);
CATransform3D DPPeekScaled(NSView *view, CGFloat scale);
CASpringAnimation *DPPeekSpring(NSString *keyPath, CFTimeInterval response, CGFloat dampingRatio);

void DPPeekShowTabBadge(DPPeekCard *peek, id source);
void DPPeekHideTabBadge(DPPeekCard *peek);

double DPPeekDarkness(void);
double DPPeekResponse(void);
BOOL DPPeekGenie(void);
BOOL DPPeekShowsToolbar(void);
NSArray<NSView *> *DPPeekSettingsRows(void);

extern BOOL DPPeekGiving;

void DPPeekInstallPages(void);
BOOL DPPeekCanOpen(id source);
BOOL DPPeekShows(id page);
void DPPeekLoad(id page, NSURL *url);
void DPPeekOpen(NSWindow *window, NSURL *url, NSPoint origin, id delegate, id source);
void DPPeekWarm(NSWindow *window, id source, NSURL *url);
void DPPeekCool(void);
void DPPeekOpenDragged(NSURL *url, NSPoint origin);
BOOL DPPeekIsWeb(NSURL *url);
