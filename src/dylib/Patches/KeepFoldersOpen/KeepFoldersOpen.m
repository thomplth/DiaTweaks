#import "StdPatch/StdPatch.h"
#import "Commands/GroupTabs/GroupTabs.h"

extern DPPatch DPKeepFoldersOpen;

static char DPExpandedKey, DPClickedKey, DPReopenedKey, DPModelKey;
static NSHashTable<NSView *> *DPCollapsedFolders;
static BOOL DPReopening;

static id DPObjectIvar(id object, const char *name) {
    void *slot = DPIvar(object, name);
    return slot ? *(__unsafe_unretained id *)slot : nil;
}

static NSView *DPTopHeader(NSView *folder) {
    id header = DPObjectIvar(folder, "$__lazy_storage_$_headerView");
    return [header isKindOfClass:NSView.class] ? header : nil;
}

static NSNumber *DPFolderExpanded(NSView *folder) {
    if (DPIsKind(folder, DPDiaTabGroupView)) {
        BOOL *flag = DPIvar(folder, "shouldDisplayExpandedContainer");
        return flag ? @(*flag) : nil;
    }
    Ivar ivar = class_getInstanceVariable(object_getClass(folder), "$__lazy_storage_$_chevronIconView");
    id chevron = ivar ? object_getIvar(folder, ivar) : nil;
    CALayer *layer = [chevron isKindOfClass:NSView.class] ? ((NSView *)chevron).layer : nil;
    if (!layer) return nil;
    return @(fabs(atan2(layer.transform.m12, layer.transform.m11)) < 0.1);
}

static void DPClickHeader(NSView *folder) {
    NSView *header = DPTopHeader(folder);
    NSView *target = header ?: folder;
    NSPoint point = [target convertPoint:header ? NSMakePoint(NSMidX(header.bounds), NSMidY(header.bounds)) : NSMakePoint(NSMidX(folder.bounds), 18) toView:nil];
    DPReopening = YES;
    for (NSEventType type = NSEventTypeLeftMouseDown; type <= NSEventTypeLeftMouseUp; type++) {
        NSEvent *event = [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                        windowNumber:folder.window.windowNumber context:nil eventNumber:0 clickCount:1
                                            pressure:type == NSEventTypeLeftMouseDown];
        if (type == NSEventTypeLeftMouseDown) [target mouseDown:event];
        else [target mouseUp:event];
    }
    DPReopening = NO;
}

static void DPReopenFolders(void) {
    NSArray<NSView *> *folders = DPCollapsedFolders.allObjects;
    [DPCollapsedFolders removeAllObjects];
    // Several at once is a collapse-all, not a folder that emptied.
    if (!DPKeepFoldersOpen.on || folders.count != 1 || !folders[0].window || [DPFolderExpanded(folders[0]) boolValue]) return;
    DPSet(folders[0], &DPReopenedKey, @(CACurrentMediaTime()));
    DPClickHeader(folders[0]);
}

static void DPCheckFolder(NSView *folder) {
    NSNumber *expanded = DPFolderExpanded(folder);
    if (!expanded || !folder.window) return;
    id model = DPObjectIvar(folder, "viewModel");
    // A top folder view that now shows another folder starts over.
    if (model && DPGet(folder, &DPModelKey) != model) DPSet(folder, &DPExpandedKey, nil);
    DPSet(folder, &DPModelKey, model);
    BOOL collapsed = [DPGet(folder, &DPExpandedKey) boolValue] && !expanded.boolValue;
    DPSet(folder, &DPExpandedKey, expanded);
    CFTimeInterval now = CACurrentMediaTime();
    if (!collapsed || !DPKeepFoldersOpen.on || now - [DPGet(folder, &DPClickedKey) doubleValue] < 1) return;
    if (now - DPFoldedAt < 2) return;
    if (now - [DPGet(folder, &DPReopenedKey) doubleValue] < 1) return;
    if (!DPCollapsedFolders.count)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{ DPReopenFolders(); });
    [DPCollapsedFolders addObject:folder];
}

static void DPFolder_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFolder_layout, self);
    DPCheckFolder(self);
}

static void DPFolder_mouse(NSView *self, SEL _cmd, NSEvent *event) {
    if (!DPReopening) DPSet(self, &DPClickedKey, @(CACurrentMediaTime()));
    DPCallOriginal(DPFolder_mouse, self, event);
}

static void DPHeader_mouse(NSView *self, SEL _cmd, NSEvent *event) {
    NSView *folder = self.superview;
    while (folder && !DPIsKind(folder, DPDiaTabGroupView)) folder = folder.superview;
    if (folder && !DPReopening) DPSet(folder, &DPClickedKey, @(CACurrentMediaTime()));
    DPCallOriginal(DPHeader_mouse, self, event);
}

static void DPFolder_prepareForReuse(NSView *self, SEL _cmd) {
    DPCallOriginal(DPFolder_prepareForReuse, self);
    DPSet(self, &DPExpandedKey, nil);
}

static void DPInstallKeepFoldersOpen(void) {
    DPCollapsedFolders = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaTabGroupCell, @selector(layout), (IMP)DPFolder_layout);
    DPHook(DPDiaTabGroupCell, @selector(mouseDown:), (IMP)DPFolder_mouse);
    DPHook(DPDiaTabGroupCell, @selector(mouseUp:), (IMP)DPFolder_mouse);
    DPHook(DPDiaTabGroupCell, @selector(prepareForReuse), (IMP)DPFolder_prepareForReuse);
    DPHook(DPDiaTabGroupView, @selector(layout), (IMP)DPFolder_layout);
    DPHook(DPDiaTabGroupHeader, @selector(mouseDown:), (IMP)DPHeader_mouse);
    DPHook(DPDiaTabGroupHeader, @selector(mouseUp:), (IMP)DPHeader_mouse);
}

DP_PATCH(DPKeepFoldersOpen) {
    .key = @"keepFoldersOpen",
    .order = 79,
    .title = @"Keep Folders Open",
    .detail = @"Stop folders collapsing on their own when they empty, in the sidebar or at the top, so new tabs and live folder items show up.",
    .symbol = @"folder.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaTabGroupCell, DPDiaTabGroupView, DPDiaTabGroupHeader),
    .install = DPInstallKeepFoldersOpen,
};
