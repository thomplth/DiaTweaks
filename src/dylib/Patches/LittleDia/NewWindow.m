#import "LittleDia.h"

static NSMenuItem *gItem;
static BOOL gLookScheduled;
static int gLooks;

static NSMenu *DPFileMenu(void) { return [NSApp.mainMenu itemWithTitle:@"File"].submenu; }

static BOOL DPShouldShow(void) { return DPLittleDia.on && DPLittleDiaReady(); }

// The extension is ready some time after launch, and much later with no window, so this polls until it is.
void DPRefreshLittleDiaNewWindow(void) {
    NSMenu *file = DPFileMenu();
    BOOL show = DPShouldShow();
    if (gItem && file) {
        if (show && [file indexOfItem:gItem] < 0) {
            NSInteger after = [file indexOfItemWithTitle:@"New Incognito Window"];
            [file insertItem:gItem atIndex:after >= 0 ? after + 1 : file.numberOfItems];
        }
        gItem.hidden = !show;
    }
    if (show || !DPLittleDia.on || gLookScheduled) return;
    gLookScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (gLooks++ < 120 ? 500 : 5000) * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        gLookScheduled = NO;
        DPRefreshLittleDiaNewWindow();
    });
}

void DPInstallLittleDiaNewWindow(void) {
    gItem = DPMenuItem(@"New Little Dia Window", ^{
        if (DPShouldShow()) DPOpenBlankLittleDia();
        else NSBeep();
    });
    gItem.keyEquivalent = @"n";
    gItem.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    gItem.hidden = YES;
    DPOnLaunch(^{ DPRefreshLittleDiaNewWindow(); });
}

NSString *DPLittleDiaNewWindowProblem(void) {
    BOOL shown = [DPFileMenu() indexOfItem:gItem] >= 0 && !gItem.hidden;
    if (shown && !DPShouldShow()) return @"New Little Dia Window stays in the File menu";
    if (!shown && DPShouldShow()) return @"the File menu has no New Little Dia Window";
    return nil;
}
