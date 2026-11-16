#import "GrainSettings.h"

static const DPGrainSetting *const DPGrainSettings[] = { &DPGrainAmountSetting, &DPGrainSoftnessSetting, &DPGrainScaleSetting };
#define DPGrainSettingCount (sizeof DPGrainSettings / sizeof *DPGrainSettings)
static NSHashTable<NSView *> *DPGrainSliders;

@interface DPGrainSliderRow : NSStackView <NSTextFieldDelegate>
@property const DPGrainSetting *setting;
@property (nonatomic) NSString *space;
@property NSSlider *slider;
@property NSTextField *field;
@end

@implementation DPGrainSliderRow

- (void)sync {
    self.slider.integerValue = self.field.integerValue = DPGrainValue(self.setting, self.space);
}

- (void)setSpace:(NSString *)space {
    _space = space;
    [self sync];
}

- (void)tune:(NSControl *)control {
    NSInteger value = MAX(self.setting->min, MIN(self.setting->max, lround(control.doubleValue)));
    DPGrainSave(self.setting->key, @(value), self.space);
    [self sync];
    DPRefreshSidebarGrain();
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

static NSView *DPGrainSliderRowFor(const DPGrainSetting *setting) {
    DPGrainSliderRow *row = [DPGrainSliderRow new];
    row.setting = setting;
    row.slider = [NSSlider sliderWithValue:0 minValue:setting->min maxValue:setting->max target:row action:@selector(tune:)];
    [row.slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSNumberFormatter *whole = [NSNumberFormatter new];
    whole.maximumFractionDigits = 0;
    row.field = [NSTextField textFieldWithString:@""];
    row.field.formatter = whole;
    row.field.alignment = NSTextAlignmentRight;
    row.field.target = row.field.delegate = row;
    row.field.action = @selector(tune:);
    [row.field.widthAnchor constraintEqualToConstant:44].active = YES;
    NSStackView *controls = [NSStackView stackViewWithViews:@[ row.slider, row.field, [NSTextField labelWithString:@"%"] ]];
    [row setViews:@[ [NSTextField labelWithString:setting->title], controls ] inGravity:NSStackViewGravityTop];
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    [controls.widthAnchor constraintEqualToAnchor:row.widthAnchor].active = YES;
    [row sync];
    if (!DPGrainSliders) DPGrainSliders = [NSHashTable weakObjectsHashTable];
    [DPGrainSliders addObject:row];
    return row;
}

@interface DPGrainResetRow : NSStackView
@property (nonatomic) NSString *space;
@property (copy) void (^afterReset)(void);
@property NSTextField *label;
@end

@implementation DPGrainResetRow
- (void)setSpace:(NSString *)space {
    _space = space;
    self.label.stringValue = space ? @"Reset this profile to the defaults" : @"Reset Grain, Softness and Scale";
}

- (void)reset:(NSButton *)button {
    if (self.space) DPGrainClear(self.space);
    else for (NSUInteger i = 0; i < DPGrainSettingCount; i++) [DPGrainDefaults() removeObjectForKey:DPGrainSettings[i]->key];
    for (DPGrainSliderRow *row in DPGrainSliders) [row sync];
    DPRefreshSidebarGrain();
    if (self.afterReset) self.afterReset();
}
@end

NSArray<NSView *> *DPGrainRows(void) {
    DPGrainResetRow *reset = [DPGrainResetRow new];
    NSButton *button = [NSButton buttonWithTitle:@"Reset" target:reset action:@selector(reset:)];
    button.controlSize = NSControlSizeSmall;
    [button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    button.accessibilityLabel = @"Reset grain settings";
    reset.label = [NSTextField labelWithString:@"Reset Grain, Softness and Scale"];
    [reset.label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    reset.distribution = NSStackViewDistributionFill;
    [reset setViews:@[ reset.label, button ] inGravity:NSStackViewGravityLeading];
    NSMutableArray<NSView *> *rows = [NSMutableArray new];
    for (NSUInteger i = 0; i < DPGrainSettingCount; i++) [rows addObject:DPGrainSliderRowFor(DPGrainSettings[i])];
    [rows addObject:reset];
    return rows;
}

void DPGrainRowsFor(NSArray<NSView *> *rows, NSString *space, void (^reset)(void)) {
    for (NSView *row in rows) {
        if ([row isKindOfClass:DPGrainSliderRow.class]) ((DPGrainSliderRow *)row).space = space;
        else if ([row isKindOfClass:DPGrainResetRow.class]) {
            ((DPGrainResetRow *)row).space = space;
            ((DPGrainResetRow *)row).afterReset = reset;
        }
    }
}
