#import "PullRequestRepo.h"

static char DPDiaTextKey, DPCheckedKey, DPInListKey;

static NSString *DPMatch(NSString *pattern, NSString *text) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = text ? [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] : nil;
    return match ? [text substringWithRange:[match rangeAtIndex:match.numberOfRanges - 1]] : nil;
}

BOOL DPIsPRSubtitle(NSView *label) {
    return DPIsKind(label, DPDiaFeatheredLabel) && DPIsKind(label.superview, DPDiaTransitioningLabel);
}

NSView *DPEnclosingView(NSView *view, const char *className) {
    while (view && !DPIsKind(view, className)) view = view.superview;
    return view;
}

static BOOL DPInTabList(NSView *view) { return DPEnclosingView(view, DPDiaTabListCollection) != nil; }

NSDictionary *DPPullRequestOf(NSView *view) {
    view = DPEnclosingView(view, DPDiaTabContentView);
    id controller = DPSwiftValue(DPSwiftValue(view, @"viewModel"), @"delegate");
    NSString *item = [DPSwiftValue(controller, @"currentlyRenderedLiveItem") description];
    if (![item containsString:@".pullRequest("]) return nil;
    NSString *repo = DPMatch(@"github\\.com/[^/\\s]+/([^/\\s)]+)/pull/[0-9]+", item), *number = DPMatch(@"github\\.com/[^\\s)]+/pull/([0-9]+)", item);
    NSString *author = DPMatch(@"author: \"([^\"]+)\"", item), *state = DPMatch(@"PullRequest\\.Status\\.([a-zA-Z]+)", item);
    NSString *tab = DPMatch(@"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", [DPSwiftValue(controller, @"tabID") description]);
    if (!repo || !number || !author) return nil;
    NSString *line = [NSString stringWithFormat:@"%@ #%@", repo, number];
    state = state.length ? [[state substringToIndex:1].uppercaseString stringByAppendingString:[state substringFromIndex:1]] : @"";
    if (state.length) line = [line stringByAppendingFormat:@" · %@", state];
    return @{@"repo": line, @"state": state, @"author": author, @"tab": tab ?: @""};
}

static NSString *DPSplit(NSView *label, NSString *text, NSString **status, NSString **tab) {
    NSDictionary *pr = text.length ? DPPullRequestOf(label) : nil;
    if (!pr || ![text hasPrefix:pr[@"author"]]) return nil;
    NSString *rest = [text substringFromIndex:[pr[@"author"] length]];
    NSString *review = [rest stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" •"]];
    *tab = pr[@"tab"];
    if (!review.length) return [pr[@"repo"] stringByAppendingString:rest];
    NSString *words = [[review componentsSeparatedByCharactersInSet:NSCharacterSet.letterCharacterSet.invertedSet] componentsJoinedByString:@""];
    NSString *repo = pr[@"repo"], *state = pr[@"state"], *from = [rest substringFromIndex:[rest rangeOfString:review].location];
    if (state.length && [words caseInsensitiveCompare:state] == NSOrderedSame)
        return [[repo substringToIndex:repo.length - state.length] stringByAppendingString:from];
    if (!DPInTabList(label)) return [repo stringByAppendingString:rest];
    *status = from;
    return repo;
}

static void DPRelayoutRow(NSView *label) {
    for (NSView *view = label.superview; view; view = view.superview) {
        view.needsLayout = YES;
        if (DPIsKind(view, DPDiaTabContentView)) break;
    }
}

static void DPLabel_setStringValue(NSTextField *self, SEL _cmd, NSString *value) {
    if (!DPIsPRSubtitle(self)) return DPCallOriginal(DPLabel_setStringValue, self, value);
    NSString *status = nil, *tab = nil, *shown = DPPullRequestRepo.on && value ? DPSplit(self, value, &status, &tab) : nil;
    if (shown) DPOverride(self, &DPDiaTextKey, value, shown);
    DPSet(self, &DPCheckedKey, shown ?: value);
    DPSet(self, &DPInListKey, @(DPInTabList(self)));
    DPSetPRStatus(self, tab, status);
    DPCallOriginal(DPLabel_setStringValue, self, shown ?: value);
}

// Dia may set the text before the label is in a row, or move the label in or out of the list later.
static void DPLabel_layout(NSTextField *self, SEL _cmd) {
    DPCallOriginal(DPLabel_layout, self);
    if (!DPPullRequestRepo.on || !DPIsPRSubtitle(self)) return;
    BOOL moved = [DPGet(self, &DPInListKey) boolValue] != DPInTabList(self);
    if (!moved && [self.stringValue isEqual:DPGet(self, &DPCheckedKey)]) return;
    self.stringValue = DPDiaValue(self, &DPDiaTextKey, self.stringValue);
    DPRelayoutRow(self);
}

void DPRefreshPRSubtitles(void) {
    for (NSView *view in DPFindViews(DPDiaFeatheredLabel)) {
        if (!DPIsPRSubtitle(view)) continue;
        NSTextField *label = (NSTextField *)view;
        label.stringValue = DPDiaValue(label, &DPDiaTextKey, label.stringValue);
        DPRelayoutRow(label);
    }
}

void DPInstallPRSubtitles(void) {
    DPHook(DPDiaFeatheredLabel, @selector(setStringValue:), (IMP)DPLabel_setStringValue);
    DPHook(DPDiaFeatheredLabel, @selector(layout), (IMP)DPLabel_layout);
}
