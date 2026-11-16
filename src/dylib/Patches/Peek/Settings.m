#import "Patches/Peek/Peek.h"
#import "Settings/Settings.h"

static NSString *const DPPeekDarknessKey = @"peekDarkness", *const DPPeekSpeedKey = @"peekSpeed", *const DPPeekGenieKey = @"peekGenie",
                *const DPPeekToolbarKey = @"peekToolbar";

static NSUserDefaults *DPSettings(void) {
    static NSUserDefaults *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return settings;
}

static double DPPeekTuned(NSString *key) {
    id value = [DPSettings() objectForKey:key];
    if (value) return [value doubleValue];
    return [@{ DPPeekDarknessKey : @0.45, DPPeekSpeedKey : @0.9, DPPeekGenieKey : @YES, DPPeekToolbarKey : @YES }[key] doubleValue];
}

double DPPeekDarkness(void) { return DPPeekTuned(DPPeekDarknessKey); }
double DPPeekResponse(void) { return 0.24 / MAX(0.1, DPPeekTuned(DPPeekSpeedKey)); }
BOOL DPPeekGenie(void) { return DPPeekTuned(DPPeekGenieKey) != 0; }
BOOL DPPeekShowsToolbar(void) { return DPPeekTuned(DPPeekToolbarKey) != 0; }

@interface DPPeekTuneRow : NSStackView <NSTextFieldDelegate>
@property (copy) NSString *key;
@property double scale;
@property NSSlider *slider;
@property NSTextField *field;
@end

@implementation DPPeekTuneRow
- (void)tune:(NSControl *)control {
    double shown = [control isKindOfClass:NSSwitch.class] ? ((NSSwitch *)control).state
                                                          : round(MIN(MAX(control.doubleValue, self.slider.minValue), self.slider.maxValue));
    self.slider.doubleValue = shown;
    self.field.doubleValue = shown;
    [DPSettings() setDouble:shown / self.scale forKey:self.key];
    for (NSWindow *window in NSApp.windows)
        DPPeekCardIn(window).dim.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:DPPeekDarkness()].CGColor;
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    NSNumber *step = @{ @"moveUp:" : @1, @"moveDown:" : @-1, @"moveUpAndModifySelection:" : @10, @"moveDownAndModifySelection:" : @-10 }[NSStringFromSelector(command)];
    if (!step) return NO;
    self.field.doubleValue = textView.string.doubleValue + step.doubleValue;
    [self tune:self.field];
    [textView selectAll:nil];
    return YES;
}
@end

static DPPeekTuneRow *DPPeekRow(NSString *title, NSString *key, double scale, NSView *control) {
    NSTextField *label = [NSTextField labelWithString:title];
    [label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    DPPeekTuneRow *row = [DPPeekTuneRow stackViewWithViews:@[ label, control ]];
    row.key = key;
    row.scale = scale;
    return row;
}

static NSView *DPPeekSlider(NSString *title, NSString *key, double min, double max, double scale, NSString *unit) {
    double shown = round(DPPeekTuned(key) * scale);
    NSSlider *slider = [NSSlider sliderWithValue:shown minValue:min maxValue:max target:nil action:@selector(tune:)];
    [slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSNumberFormatter *whole = [NSNumberFormatter new];
    whole.maximumFractionDigits = 0;
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.formatter = whole;
    field.doubleValue = shown;
    field.alignment = NSTextAlignmentRight;
    field.action = @selector(tune:);
    [field.widthAnchor constraintEqualToConstant:44].active = YES;
    NSStackView *controls = [NSStackView stackViewWithViews:@[ slider, field, [NSTextField labelWithString:unit] ]];
    DPPeekTuneRow *row = DPPeekRow(title, key, scale, controls);
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    [controls.widthAnchor constraintEqualToAnchor:row.widthAnchor].active = YES;
    row.slider = slider;
    row.field = field;
    slider.target = field.target = field.delegate = row;
    return row;
}

static NSView *DPPeekSwitch(NSString *title, NSString *detail, NSString *key) {
    NSSwitch *toggle = [NSSwitch new];
    toggle.controlSize = NSControlSizeSmall;
    toggle.state = DPPeekTuned(key) ? NSControlStateValueOn : NSControlStateValueOff;
    toggle.action = @selector(tune:);
    NSStackView *lines = DPColumn(@[DPLabel(title, 13, NSFontWeightRegular, NSColor.labelColor),
                                    DPLabel(detail, 11, NSFontWeightRegular, NSColor.secondaryLabelColor)], 2);
    [lines setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [lines setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    DPPeekTuneRow *row = [DPPeekTuneRow stackViewWithViews:@[ lines, toggle ]];
    row.key = key;
    row.scale = 1;
    row.distribution = NSStackViewDistributionFill;
    row.spacing = 12;
    toggle.target = row;
    return row;
}

NSArray<NSView *> *DPPeekSettingsRows(void) {
    NSView *toolbar = DPPeekSwitch(@"Show Address Toolbar",
        @"Show back, forward, reload and the address across the top of the card, like Little Dia. It hides and shows with Hide Toolbar.",
        DPPeekToolbarKey);
    toolbar.identifier = DPLeadingOption;
    return @[
        toolbar,
        DPPeekSwitch(@"Genie Effect", @"Grow the card out of the link you clicked, and shrink it back into it as it closes.", DPPeekGenieKey),
        DPPeekSlider(@"Darken the page behind", DPPeekDarknessKey, 0, 100, 100, @"%"),
        DPPeekSlider(@"Speed", DPPeekSpeedKey, 25, 300, 100, @"%"),
    ];
}
