#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "StdPatch/Dia.h"

typedef struct DPPatch DPPatch;
struct DPPatch {
    __unsafe_unretained NSString *key;
    BOOL defaultOn;
    int order;
    __unsafe_unretained NSString *title, *detail;
    __unsafe_unretained NSString *hint;
    __unsafe_unretained NSString *symbol, *tint;  // symbol: space-separated fallbacks for older macOS. tint: an NSColor class property.
    __unsafe_unretained NSString *section;
    __unsafe_unretained NSString *page;  // Fork-only tweaks link their docs/tweaks page; the upstream wiki can't hold them.
    const char *const *classes;
    __unsafe_unretained NSString *requires;
    __unsafe_unretained NSString *disabledBy;
    __unsafe_unretained NSString *coveredBy;
    __unsafe_unretained NSString *choice, *defaultChoice;  // Saved as the chosen item's representedObject.
    NSMenu *(*choices)(void);
    NSArray<NSView *> *(*rows)(void);
    __unsafe_unretained NSString *shortcut, *sharesShortcutWith;
    NSDictionary *(*defaultShortcut)(void);
    BOOL (*hides)(NSView *view);
    void (*install)(void);  // Runs at launch whether or not the patch is on.
    void (*apply)(DPPatch *patch);  // Without it, `progress` eases toward `on` and every `relayout` runs each frame.
    void (*relayout)(void);
    // nil if Dia's views match `on`, else what's wrong. Use DPFindViews, not your hooks, so a hook that never ran fails.
    NSString *(*verify)(DPPatch *patch);
    NSString *(*ready)(DPPatch *patch);
    BOOL on, unavailable;
    CGFloat progress;
};

#define DPClasses(...) ((const char *const []){__VA_ARGS__, NULL})

#define DP_PATCH(name)                                                                              \
    DPPatch name;                                                                                   \
    __attribute__((used, section("__DATA,__dppatches"))) static DPPatch *const name##Entry = &name; \
    DPPatch name =

extern DPPatch *const *DPPatches;
extern NSUInteger DPPatchCount;
DPPatch *DPPatchNamed(NSString *key);
DPPatch *DPRequired(DPPatch *patch);
void DPSetPatch(DPPatch *patch, BOOL on, BOOL save);
BOOL DPSavedOn(DPPatch *patch);
NSString *DPChoice(DPPatch *patch);
void DPSetChoice(DPPatch *patch, NSString *value);
void DPLoadPatches(void);
void DPInstallPatches(void);
BOOL DPWriteManifest(NSString *path);  // Reads no settings.
NSString *DPAppSupport(NSString *path);
NSString *DPRelayProblem(void);
NSString *DPHostProblem(NSString *manifest, NSString *name);
NSString *DPWriteProblem(NSString *path, NSError *error);
extern NSNotificationName const DPPatchesDidChangeNotification;
#define DPLeadingOption @"DPLeadingOption"
extern BOOL DPTesting;

void DPHook(const char *className, SEL sel, IMP replacement);
void DPHookClass(Class cls, SEL sel, IMP replacement);
IMP DPDiaIMP(Class cls, SEL sel);
IMP DPOriginalIMP(id object, SEL sel, IMP replacement);

#define DPCallOriginal(hook, self, ...) \
    ((__typeof__(&hook))DPOriginalIMP(self, _cmd, (IMP)hook))(self, _cmd, ##__VA_ARGS__)

NSView *DPFindView(NSView *root, BOOL (^match)(NSView *view));
NSArray<NSView *> *DPFindViews(const char *className);
NSString *DPTabLayout(void);
NSView *DPSubview(NSView *parent, const char *className);
BOOL DPIsKind(id object, const char *className);
BOOL DPIsFloatingChat(NSView *popover);
BOOL DPHasLabel(NSView *view, NSString *accessibilityLabel);
void DPRelayoutViews(NSHashTable<NSView *> *views);
// Call before changing a frame during layout: if Dia keeps restoring it, the two loop until AppKit aborts Dia.
BOOL DPMayAdjust(NSView *view);
void *DPIvar(id object, const char *name);
id DPSwiftValue(id object, NSString *key);
NSArray<NSString *> *DPUUIDsIn(NSString *text);
NSWindowController *DPOpenTabSwitcher(void);

void DPSetHint(NSView *view, NSString *text);
NSString *DPHintOf(NSView *view);
void DPShowHint(NSView *view);

NSView *DPShortcutRow(DPPatch *patch);
BOOL DPShortcutMatches(NSEvent *event, DPPatch *patch);
BOOL DPShortcutRecording(void);
BOOL DPEventIsKey(NSEvent *event, NSString *key);

id DPGet(id object, const void *key);
void DPSet(id object, const void *key, id value);

void DPOverride(id object, const void *key, id dia, id ours);
id DPDiaValue(id object, const void *key, id current);

NSURL *DPAddressURL(NSString *typed);

float DPZoomStep(float now, int direction);

// Chromium reads extensions and launch flags once as Dia starts: call DPLoadExtension and DPAddLaunchFlag from an `install`.
void DPLoadExtension(NSString *folder);
void DPAddLaunchFlag(NSString *flag);
void DPDropLaunchFeature(NSString *feature);  // From a tweak that is off, for a feature it adds when on.

void DPOnLaunch(void (^block)(void));
void DPOnQuit(void (^block)(void));

// Menus exist once Dia has launched: call these from DPOnLaunch.
NSMenuItem *DPMenuItem(NSString *title, void (^action)(void));
NSMenuItem *DPAddMenuItem(NSString *menu, NSString *title, void (^action)(void));
void DPOnMenuItem(NSString *menu, NSString *titlePrefix, void (^action)(void));
