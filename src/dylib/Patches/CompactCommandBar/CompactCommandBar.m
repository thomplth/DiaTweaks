#import "CompactCommandBar.h"

NSView *DPCommandBarPart(NSView *commandBar, const char *className) {
    return DPFindView(commandBar, ^BOOL(NSView *view) { return DPIsKind(view, className); });
}

BOOL DPChatLocked(NSView *view) {
    return DPFindView(view, ^BOOL(NSView *v) { return [v.accessibilityLabel hasSuffix:@"only available when you have chat usage"]; }) != nil;
}

// Dia labels the buttons a moment after the command bar shows, so until then the last label decides.
static NSString *const DPChatLockedKey = @"commandBarChatLocked";

static NSUserDefaults *DPCommandBarDefaults(void) {
    static NSUserDefaults *defaults;
    if (!defaults) defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    return defaults;
}

void DPRememberChatLocked(BOOL locked) {
    if ([DPCommandBarDefaults() boolForKey:DPChatLockedKey] != locked) [DPCommandBarDefaults() setBool:locked forKey:DPChatLockedKey];
}

static BOOL DPCompacts(NSView *toolbar) {
    return DPCompactWithChat.on || DPChatLocked(toolbar);
}

NSView *DPCompactToolbar(NSView *commandBar) {
    NSView *toolbar = DPCommandBarPart(commandBar, DPDiaCommandBarToolbar);
    BOOL compacts = toolbar && (DPCompacts(toolbar) || [DPCommandBarDefaults() boolForKey:DPChatLockedKey]);
    return DPCompactCommandBar.on && compacts ? toolbar : nil;
}

NSView *DPGoButton(NSView *toolbar) {
    NSStackView *stack = toolbar.subviews.firstObject;
    return [stack isKindOfClass:NSStackView.class] ? stack.views.lastObject : nil;
}

static char DPTrimKey;

CGFloat DPTrim(NSView *container) {
    return [DPGet(container, &DPTrimKey) doubleValue];
}

void DPSetTrim(NSView *container, CGFloat trim) {
    DPSet(container, &DPTrimKey, trim > 0 ? @(trim) : nil);
}

void DPApplyCompactCommandBar(DPPatch *patch) {
    for (NSView *commandBar in DPFindViews(DPDiaCommandBar)) commandBar.needsLayout = YES;
    DPResizeNewTabPanels();
    DPResizePopovers();
}

static NSString *DPVerifyCompactCommandBar(DPPatch *patch) {
    for (NSView *commandBar in DPFindViews(DPDiaCommandBar)) {
        NSView *toolbar = DPCommandBarPart(commandBar, DPDiaCommandBarToolbar), *go = DPGoButton(toolbar);
        NSView *input = DPCommandBarPart(commandBar, DPDiaCommandBarInput);
        if (!go || !input || !DPCompacts(toolbar)) continue;
        NSRect goFrame = [go convertRect:go.bounds toView:input.superview];
        BOOL beside = NSMinY(goFrame) < NSMaxY(input.frame) && NSMaxY(goFrame) > NSMinY(input.frame);
        if (beside != patch->on) return patch->on ? @"Go is still under the input" : @"Go is still beside the input";
        NSView *panel = commandBar.superview.superview;
        if (DPIsKind(panel, DPDiaAssistantPanel) && DPIsKind(panel.superview.superview, DPDiaNewTabPage)
            && (NSHeight(panel.frame) < NSHeight(commandBar.frame) - 0.5) != patch->on)
            return patch->on ? @"new tab page keeps the empty row" : @"new tab page is still trimmed";
    }
    return nil;
}

DP_PATCH(DPCompactCommandBar) {
    .key = @"compactCommandBar",
    .order = 90,
    .section = @"Command Bar",
    .title = @"Compact Command Bar",
    .detail = @"Without chat usage, hide Add tabs or files and dictation so the command bar fits on one line.",
    .symbol = @"rectangle.compress.vertical",
    .tint = @"systemOrangeColor",
    .classes = DPClasses(DPDiaPopover, DPDiaAssistantPanel, DPDiaNewTabPage, DPDiaCommandBar, DPDiaCommandBarInput, DPDiaCommandBarText, DPDiaCommandBarSuggestions, DPDiaCommandBarToolbar, DPDiaCommandBarButton),
    .install = DPInstallCommandBarLayout,
    .apply = DPApplyCompactCommandBar,
    .verify = DPVerifyCompactCommandBar,
};
