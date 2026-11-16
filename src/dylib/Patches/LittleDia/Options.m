#import "LittleDia.h"
#import "Patches/Peek/Peek.h"

static NSString *const DPWidthKey = @"littleDiaWidth", *const DPHeightKey = @"littleDiaHeight";

static NSUserDefaults *DPSettings(void) {
    static NSUserDefaults *settings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return settings;
}

NSSize DPLittleDiaSize(void) {
    NSNumber *width = [DPSettings() objectForKey:DPWidthKey], *height = [DPSettings() objectForKey:DPHeightKey];
    return NSMakeSize(width ? width.doubleValue : 1180, height ? height.doubleValue : 860);
}

@interface DPSizeRow : NSStackView <NSTextFieldDelegate>
@property (nonatomic, copy) NSString *key;
@property (nonatomic) NSSlider *slider;
@property (nonatomic) NSTextField *field;
@end

@implementation DPSizeRow

- (void)tune:(NSControl *)control {
    double value = round(MIN(MAX(control.doubleValue, self.slider.minValue), self.slider.maxValue));
    self.slider.doubleValue = value;
    self.field.doubleValue = value;
    [DPSettings() setDouble:value forKey:self.key];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    NSNumber *step = @{ @"moveUp:" : @10, @"moveDown:" : @-10, @"moveUpAndModifySelection:" : @100, @"moveDownAndModifySelection:" : @-100 }[NSStringFromSelector(command)];
    if (!step) return NO;
    self.field.doubleValue = textView.string.doubleValue + step.doubleValue;
    [self tune:self.field];
    [textView selectAll:nil];
    return YES;
}

@end

static NSView *DPSizeSlider(NSString *title, NSString *key, double min, double max, double value) {
    NSSlider *slider = [NSSlider sliderWithValue:value minValue:min maxValue:max target:nil action:@selector(tune:)];
    [slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSNumberFormatter *whole = [NSNumberFormatter new];
    whole.maximumFractionDigits = 0;
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.formatter = whole;
    field.doubleValue = value;
    field.alignment = NSTextAlignmentRight;
    field.action = @selector(tune:);
    [field.widthAnchor constraintEqualToConstant:52].active = YES;
    NSStackView *controls = [NSStackView stackViewWithViews:@[ slider, field, [NSTextField labelWithString:@"pt"] ]];

    NSTextField *label = [NSTextField labelWithString:title];
    DPSizeRow *row = [DPSizeRow stackViewWithViews:@[ label, controls ]];
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    [controls.widthAnchor constraintEqualToAnchor:row.widthAnchor].active = YES;
    row.key = key;
    row.slider = slider;
    row.field = field;
    slider.target = field.target = field.delegate = row;
    return row;
}

NSArray<NSView *> *DPLittleDiaRows(void) {
    NSSize size = DPLittleDiaSize();
    return @[
        DPSizeSlider(@"Window Width", DPWidthKey, 480, 2000, size.width),
        DPSizeSlider(@"Window Height", DPHeightKey, 360, 1400, size.height),
    ];
}

extern DPPatch DPLittleDiaEscape;

// Peek's own monitor takes Escape too and may run first or second, so this one stands aside while a Peek is open.
static BOOL DPEscapeCloses(NSEvent *event) {
    NSWindow *window = event.window;
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl);
    if (!DPLittleDia.on || !DPLittleDiaEscape.on || event.keyCode != 53 || mods || event.isARepeat || !window.isKeyWindow) return NO;
    if (!DPIsLittleDiaWindow(window) || (window.styleMask & NSWindowStyleMaskFullScreen) || DPPeekCardIn(window)) return NO;
    if ([window.firstResponder isKindOfClass:NSText.class] && [(NSText *)window.firstResponder isFieldEditor]) return NO;
    NSResponder<NSTextInputClient> *typing = (id)window.firstResponder;
    if ([typing conformsToProtocol:@protocol(NSTextInputClient)] && typing.hasMarkedText) return NO;
    [window performClose:nil];
    return YES;
}

static void DPInstallEscape(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        return DPEscapeCloses(event) ? nil : event;
    }];
}

DP_PATCH(DPLittleDiaEscape) {
    .key = @"littleDiaEscapeCloses",
    .defaultOn = YES,
    .order = 104,
    .title = @"Close with Escape",
    .detail = @"Press Escape to close the Little Dia window. Pages that use Escape themselves, like a dialog on the page, won’t see it.",
    .symbol = @"escape",
    .tint = @"systemMintColor",
    .requires = @"littleDia",
    .install = DPInstallEscape,
};
