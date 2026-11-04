#import "TidyTabs.h"

static const CGFloat DPLineInset = 11, DPLineGap = 6;  // Dia's divider runs 11pt in from each side.

// The row opened above the tabs when there's no divider of Dia's to sit in: a line like Dia's, and the broom.
@implementation DPTidyRowView {
    DPTidyBrush *_brush;
    CALayer *_line;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    self.clipsToBounds = YES;
    _line = [CALayer layer];
    [self.layer addSublayer:_line];
    _brush = [DPTidyBrush new];
    [self addSubview:_brush];
    return self;
}

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self->_line.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.1].CGColor;
    }];
}

- (void)layout {
    [super layout];
    NSRect bounds = self.bounds;
    CGFloat mid = round(NSMidY(bounds));
    _brush.frame = NSMakeRect(NSMaxX(bounds) - DPLineInset - DPTidyBrushSize + 4, mid - DPTidyBrushSize / 2, DPTidyBrushSize, DPTidyBrushSize);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _line.frame = NSMakeRect(DPLineInset, mid, MAX(0, NSMinX(_brush.frame) - DPLineGap - DPLineInset), 1);
    [CATransaction commit];
    DPTidyWave(self.layer, _line, _line.backgroundColor, DPTidyIsBusy());
}

- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; self.needsLayout = YES; }
@end

DPTidyRowView *DPTidyRowIn(NSView *list, BOOL create) {
    for (NSView *sub in list.subviews) if ([sub isKindOfClass:DPTidyRowView.class]) return (DPTidyRowView *)sub;
    if (!create) return nil;
    DPTidyRowView *row = [[DPTidyRowView alloc] initWithFrame:NSZeroRect];
    [list addSubview:row];
    return row;
}
