#import "Patches/Peek/Peek.h"

@interface DPPeekAddress : NSView <NSTextFieldDelegate>
@property (nonatomic, weak) id page;
@property (nonatomic) NSTextField *label, *field;
@property (nonatomic) BOOL hovered, beginning, ending;
@end

@implementation DPPeekAddress

- (instancetype)initWithPage:(id)page {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.page = page;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 8;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    _label = [NSTextField labelWithString:@""];
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_label];
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    if (!hit) return nil;
    return self.field && [hit isDescendantOf:self.field] ? hit : self;
}
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.IBeamCursor]; }
- (void)mouseDown:(NSEvent *)event { [self begin]; }

- (void)updateTrackingAreas {
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
    [super updateTrackingAreas];
}

- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; [self refresh]; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; [self refresh]; }

- (NSURL *)url {
    NSURL *url = [(NSObject *)self.page valueForKey:@"url"];
    return [url isKindOfClass:NSURL.class] ? url : nil;
}

- (void)refresh {
    BOOL open = self.hovered || self.field;
    self.layer.backgroundColor = open ? [NSColor.labelColor colorWithAlphaComponent:0.07].CGColor : nil;
    if (self.field) return;
    NSURL *url = self.url;
    NSString *title = [(NSObject *)self.page valueForKey:@"title"];
    NSString *host = url.host.lowercaseString ?: url.absoluteString ?: @"", *rest = @"";
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    if (self.hovered) {
        NSString *path = [url.path isEqual:@"/"] ? @"" : url.path ?: @"";
        rest = url.query.length ? [NSString stringWithFormat:@"%@?%@", path, url.query] : path;
    } else if ([title isKindOfClass:NSString.class] && title.length && ![title isEqual:url.absoluteString] && ![title isEqual:host]) {
        rest = [@" / " stringByAppendingString:title];
    }
    NSFont *font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:host
        attributes:@{NSFontAttributeName : font, NSForegroundColorAttributeName : NSColor.labelColor}];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:rest
        attributes:@{NSFontAttributeName : font, NSForegroundColorAttributeName : NSColor.secondaryLabelColor}]];
    if (![self.label.attributedStringValue isEqual:text]) self.label.attributedStringValue = text;
    self.label.toolTip = url.absoluteString;
    CGFloat height = ceil(self.label.intrinsicContentSize.height);
    self.label.frame = NSMakeRect(10, round((NSHeight(self.bounds) - height) / 2), MAX(0, NSWidth(self.bounds) - 20), height);
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self refresh];
}

- (void)begin {
    if (self.field) return (void)[self.window makeFirstResponder:self.field];
    NSString *shown = [self.url.absoluteString isEqual:@"about:blank"] ? @"" : self.url.absoluteString;
    NSTextField *field = [NSTextField textFieldWithString:shown ?: @""];
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.font = [NSFont systemFontOfSize:13];
    field.usesSingleLineMode = YES;
    field.cell.scrollable = YES;
    field.delegate = self;
    CGFloat height = ceil(field.intrinsicContentSize.height);
    field.frame = NSMakeRect(8, round((NSHeight(self.bounds) - height) / 2), NSWidth(self.bounds) - 16, height);
    field.autoresizingMask = NSViewWidthSizable;
    [self addSubview:field];
    self.field = field;
    self.label.hidden = YES;
    [self refresh];
    // selectText: focuses the field itself; focusing it first would have it end that editing straight away.
    self.beginning = YES;
    [field selectText:nil];
    self.beginning = NO;
}

- (void)end {
    if (!self.field || self.ending) return;
    self.ending = YES;
    [self.field removeFromSuperview];
    self.field = nil;
    self.label.hidden = NO;
    for (NSView *view = self.superview; view; view = view.superview)
        if ([view isKindOfClass:DPPeekCard.class]) [self.window makeFirstResponder:((DPPeekCard *)view).host];
    self.ending = NO;
    [self refresh];
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    if (self.beginning) return;
    BOOL go = [note.userInfo[@"NSTextMovement"] integerValue] == NSTextMovementReturn;
    NSString *typed = [self.field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self end];
    if (!go || !typed.length) return;
    NSURL *url = DPAddressURL(typed) ?: DPPeekSearchURL(self.page, typed);
    if (url) DPPeekLoad(self.page, url);
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (command != @selector(cancelOperation:)) return NO;
    [self end];
    return YES;
}

@end

NSView *DPPeekAddressFor(id page) { return [[DPPeekAddress alloc] initWithPage:page]; }
void DPPeekRefreshAddress(NSView *address) { if ([address isKindOfClass:DPPeekAddress.class]) [(DPPeekAddress *)address refresh]; }
void DPPeekEditAddress(NSView *address) { if ([address isKindOfClass:DPPeekAddress.class]) [(DPPeekAddress *)address begin]; }
BOOL DPPeekEditingAddress(NSView *address) { return [address isKindOfClass:DPPeekAddress.class] && ((DPPeekAddress *)address).field != nil; }
