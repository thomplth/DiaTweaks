#import "StdPatch/StdPatch.h"

static BOOL DPIsChatsButton(NSView *view) { return DPIsKind(view, DPDiaLibraryButton) || DPIsKind(view, DPDiaLibraryCell); }

DP_PATCH(DPHideChatsButton) {
    .key = @"hideChatsButton",
    .order = 95,
    .title = @"Hide Chats Button",
    .detail = @"Hide the Chats button in the tab bar or sidebar.",
    .symbol = @"doc.plaintext.fill",
    .tint = @"systemPurpleColor",
    .section = @"AI",
    .classes = DPClasses(DPDiaLibraryButton, DPDiaLibraryCell),
    .hides = DPIsChatsButton,
    .coveredBy = @"turnOffAI",
};
