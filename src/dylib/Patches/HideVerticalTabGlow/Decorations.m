#import "HideVerticalTabGlow.h"

static char DPDiaHiddenKey;

id DPTabDecoration(NSView *shape, const char *name) {
    void **slot = DPIvar(shape, name);
    id part = slot ? (__bridge id)*slot : nil;
    return [part isKindOfClass:CALayer.class] || [part isKindOfClass:NSView.class] ? part : nil;
}

BOOL DPHasTabOverride(id part) { return DPGet(part, &DPDiaHiddenKey) != nil; }

void DPRestoreTabDecoration(id part) {
    if (!DPHasTabOverride(part)) return;
    BOOL hidden = [DPDiaValue(part, &DPDiaHiddenKey, @([part isHidden])) boolValue];
    DPSet(part, &DPDiaHiddenKey, nil);
    [part setHidden:hidden];
}

void DPHideTabDecoration(id part, NSView *shape) {
    if (!part) return;
    if (!DPHideVerticalTabGlow.on || !DPIsVerticalTab(shape)) return DPRestoreTabDecoration(part);
    DPOverride(part, &DPDiaHiddenKey, DPDiaValue(part, &DPDiaHiddenKey, @([part isHidden])), @YES);
    [part setHidden:YES];
}
