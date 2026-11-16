#import "TurnOffAI.h"
#import "Updates/Updates.h"

#define DPDiaCapabilitiesToolbar "_TtC23AssistantCapabilitiesUI32AssistantCapabilitiesToolbarView"
#define DPDiaTabCardActions      "_TtC5TabUI21TabPopoverActionsView"
#define DPDiaPlaceholderText     "_TtC5ARCUI23TextViewWithPlaceholder"
#define DPDiaChatSidebar         "_TtC6Window30AssistantSidebarViewController"

BOOL DPIsAITitle(NSString *title) {
    if (![title isKindOfClass:NSString.class] || [title hasPrefix:@"Chat with Support"]) return NO;
    NSString *lower = title.lowercaseString;
    return [@[ @"Chat…", @"New Chat", @"Focus Chat", @"Send Chat Prompt Now", @"Open Daily Brief", @"Personalize Dia", @"Chat events", @"Daily report" ]
               containsObject:title]
        || [lower hasPrefix:@"chat with "] || [lower hasPrefix:@"ask dia"];
}

static BOOL DPIsAIView(NSView *view) {
    return DPHasLabel(view, @"Chat with this tab") || DPIsKind(view, DPDiaLibraryButton) || DPIsKind(view, DPDiaLibraryCell)
        || DPIsKind(view, DPDiaSkillsSuggestions) || DPIsKind(view, DPDiaPersonalizeButton) || DPIsKind(view, DPDiaChatUsage)
        || DPIsKind(view, DPDiaCapabilityButton);
}

static void DPHost_layout(NSView *self, SEL _cmd) {
    [DPHideHosts addObject:self];
    DPEnforceHides(self);
    DPCallOriginal(DPHost_layout, self);
}

static NSHashTable<NSView *> *DPMorningBriefs;

static void DPSettingsHeader_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSettingsHeader_layout, self);
    NSTextField *title = (NSTextField *)DPFindView(self, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextField.class]; });
    if (![title.stringValue isEqual:@"Morning Brief"] || !self.superview) return;
    [DPMorningBriefs addObject:self.superview];
    if (DPTurnOffAI.on) self.superview.hidden = YES;
}

static NSHashTable<NSViewController *> *DPChatSidebars;

static void DPCloseChat(NSViewController *sidebar) {
    if (!DPTurnOffAI.on) return;
    NSView *hide = DPFindView(sidebar.view, ^BOOL(NSView *view) { return DPHasLabel(view, @"Hide chat"); });
    if (!hide.isHiddenOrHasHiddenAncestor) [hide accessibilityPerformPress];
}

static void DPChatSidebar_viewWillLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPChatSidebar_viewWillLayout, self);
    [DPChatSidebars addObject:self];
    dispatch_async(dispatch_get_main_queue(), ^{ DPCloseChat(self); });
}

static NSHashTable<NSTextView *> *DPPlaceholderViews;

static NSAttributedString *DPPlaceholder_get(NSTextView *self, SEL _cmd) {
    NSAttributedString *dia = DPCallOriginal(DPPlaceholder_get, self);
    [DPPlaceholderViews addObject:self];
    if (!DPTurnOffAI.on || ![dia.string.lowercaseString hasPrefix:@"ask "]) return dia;
    NSMutableAttributedString *ours = [dia mutableCopy];
    [ours replaceCharactersInRange:NSMakeRange(0, ours.length) withString:@"Search or enter address"];
    return ours;
}

static NSHashTable<NSMenuItem *> *DPAIItems;
static char DPDiaHiddenKey;

static void DPItem_setHidden(NSMenuItem *self, SEL _cmd, BOOL hidden) {
    BOOL ai = [DPAIItems containsObject:self];
    if (ai) DPSet(self, &DPDiaHiddenKey, @(hidden));
    DPCallOriginal(DPItem_setHidden, self, hidden || (ai && DPTurnOffAI.on));
}

static void DPTrack(NSMenuItem *item) {
    if (!DPIsAITitle(item.title)) return;
    if (![DPAIItems containsObject:item]) {
        DPSet(item, &DPDiaHiddenKey, @(item.hidden));
        [DPAIItems addObject:item];
    }
    item.hidden = [DPGet(item, &DPDiaHiddenKey) boolValue];
}

static void DPTrackMenu(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        DPTrack(item);
        if (item.submenu) DPTrackMenu(item.submenu);
    }
}

static void DPMenu_addItem(NSMenu *self, SEL _cmd, NSMenuItem *item) {
    DPCallOriginal(DPMenu_addItem, self, item);
    DPTrack(item);
}

static void DPMenu_insertItem(NSMenu *self, SEL _cmd, NSMenuItem *item, NSInteger index) {
    DPCallOriginal(DPMenu_insertItem, self, item, index);
    DPTrack(item);
}

static const NSEventModifierFlags DPModifiers = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;

// Dia runs its shortcuts, including ones set in its settings, ahead of the menus, so a hidden menu item's shortcut still works.
static BOOL DPIsAIShortcut(NSEvent *event) {
    NSEventModifierFlags mods = event.modifierFlags & DPModifiers;
    NSString *key = event.charactersIgnoringModifiers.lowercaseString;
    for (NSMenuItem *item in DPAIItems)
        if (item.keyEquivalent.length && [item.keyEquivalent.lowercaseString isEqual:key] && (item.keyEquivalentModifierMask & DPModifiers) == mods) return YES;
    BOOL inBar = [NSStringFromClass([event.window.firstResponder class]) hasPrefix:@"_TtCC15BoostCommandBar"];
    return inBar && (event.keyCode == 36 || event.keyCode == 76) && mods == (NSEventModifierFlagCommand | NSEventModifierFlagControl);
}

static BOOL gCutOff;

static void DPCutOffAIServers(void) {
    gCutOff = DPTurnOffAI.on;
    if (!gCutOff) return;
    NSMutableArray<NSString *> *rules = [NSMutableArray array];
    for (NSString *host in @[ @"ai-service", @"aiproxy", @"webresultproxy", @"websearch", @"artifactcdn", @"tools-cache" ])
        [rules addObject:[NSString stringWithFormat:@"MAP %@.diabrowser.engineering ~NOTFOUND", host]];
    DPAddLaunchFlag([@"--host-resolver-rules=" stringByAppendingString:[rules componentsJoinedByString:@", "]]);
}

static void DPOfferRelaunch(DPPatch *patch) {
    if (patch->on == gCutOff || patch->on != DPSavedOn(patch)) return;  // the self-test flips patches without saving
    NSAlert *alert = [NSAlert new];
    alert.messageText = patch->on ? @"Relaunch Dia to cut off its AI servers" : @"Relaunch Dia to reconnect its AI servers";
    alert.informativeText = patch->on ? @"Until then, AI is hidden, but Dia can still reach its AI servers." : @"Until then, chat can’t reach them.";
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
}

static void DPInstallTurnOffAI(void) {
    DPCutOffAIServers();
    DPAIItems = [NSHashTable weakObjectsHashTable];
    DPPlaceholderViews = [NSHashTable weakObjectsHashTable];
    DPMorningBriefs = [NSHashTable weakObjectsHashTable];
    DPChatSidebars = [NSHashTable weakObjectsHashTable];
    DPHookClass(NSMenu.class, @selector(addItem:), (IMP)DPMenu_addItem);
    DPHookClass(NSMenu.class, @selector(insertItem:atIndex:), (IMP)DPMenu_insertItem);
    DPHookClass(NSMenuItem.class, @selector(setHidden:), (IMP)DPItem_setHidden);
    DPHook(DPDiaCapabilitiesToolbar, @selector(layout), (IMP)DPHost_layout);
    DPHook(DPDiaTabCardActions, @selector(layout), (IMP)DPHost_layout);
    DPHook(DPDiaSettingsHeader, @selector(layout), (IMP)DPSettingsHeader_layout);
    DPHook(DPDiaPlaceholderText, @selector(placeholderAttributedString), (IMP)DPPlaceholder_get);
    DPHook(DPDiaChatSidebar, @selector(viewWillLayout), (IMP)DPChatSidebar_viewWillLayout);
    DPInstallAIRows();
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        return DPTurnOffAI.on && !DPShortcutRecording() && DPIsAIShortcut(event) ? nil : event;
    }];
    DPOnLaunch(^{ DPTrackMenu(NSApp.mainMenu); });
}

static void DPApplyTurnOffAI(DPPatch *patch) {
    DPApplyHides(patch);
    for (NSMenuItem *item in DPAIItems.allObjects) DPTrack(item);
    for (NSTextView *view in DPPlaceholderViews.allObjects) view.needsDisplay = YES;
    for (NSView *section in DPMorningBriefs.allObjects) section.hidden = patch->on;
    for (NSViewController *sidebar in DPChatSidebars.allObjects) DPCloseChat(sidebar);
    DPApplyAIRows();
    DPOfferRelaunch(patch);
}

DP_PATCH(DPTurnOffAI) {
    .key = @"turnOffAI",
    .order = 95,
    .section = @"AI",
    .title = @"Turn Off AI",
    .detail = @"Turn off every AI feature in Dia: chat and its buttons, menus and shortcuts, Skills, Ask Dia, Morning Brief, and Settings' Apps and Skills. After a relaunch, Dia can't reach its AI servers either. To send questions to search, set Address Bar to Prefer Search Engine in Advanced.",
    .symbol = @"bubble.left.and.exclamationmark.bubble.right.fill bubble.left.fill",
    .tint = @"systemPurpleColor",
    .hides = DPIsAIView,
    .install = DPInstallTurnOffAI,
    .apply = DPApplyTurnOffAI,
};
