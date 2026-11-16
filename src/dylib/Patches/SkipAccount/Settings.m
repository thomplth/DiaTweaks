#import "Startup.h"

static NSHashTable<NSView *> *DPAccountSections;

static BOOL DPIsAccountHeader(NSView *header) {
    NSTextField *title = (NSTextField *)DPFindView(header, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextField.class]; });
    return title.stringValue && [@[ @"Account", @"Morning Brief", @"Sync" ] containsObject:title.stringValue];
}

static void DPSection_setHidden(NSView *self, SEL _cmd, BOOL hidden) {
    DPCallOriginal(DPSection_setHidden, self, hidden || [DPAccountSections containsObject:self]);
}

static void DPHeader_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPHeader_layout, self);
    // Hide the arranged section, including its heading, controls, and any account error message.
    if (!DPIsAccountHeader(self) || ![self.superview isKindOfClass:NSStackView.class]) return;
    [DPAccountSections addObject:self.superview];
    self.superview.hidden = YES;
}

void DPSkipAccountSettings(void) {
    DPAccountSections = [NSHashTable weakObjectsHashTable];
    DPHookClass(NSStackView.class, @selector(setHidden:), (IMP)DPSection_setHidden);
    DPHook(DPDiaSettingsHeader, @selector(layout), (IMP)DPHeader_layout);
}

NSString *DPSkipVerifyAccountSettings(void) {
    for (NSView *header in DPFindViews(DPDiaSettingsHeader))
        if (DPIsAccountHeader(header) && !header.isHiddenOrHasHiddenAncestor) return @"account-only settings section is visible";
    for (NSView *button in DPFindViews("NSButton"))
        if (DPHasLabel(button, @"More account options") && !button.isHiddenOrHasHiddenAncestor) return @"account options button is visible";
    return nil;
}
