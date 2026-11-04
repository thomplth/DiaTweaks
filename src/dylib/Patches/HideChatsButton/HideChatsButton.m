#import "StdPatch/StdPatch.h"

// One class in the tab bar, another in the sidebar.
static BOOL DPIsChatsButton(NSView *view) { return DPIsKind(view, DPDiaLibraryButton) || DPIsKind(view, DPDiaLibraryCell); }

DP_PATCH(DPHideChatsButton) {
    .key = @"hideChatsButton",
    .order = 70,
    .title = @"Hide Chats Button",
    .detail = @"Hide the Chats button in the tab bar or sidebar.",
    .symbol = @"doc.plaintext.fill",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaLibraryButton, DPDiaLibraryCell),
    .hides = DPIsChatsButton,
};
