#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"

DPPatch DPBriefLanguage;

// diapatch writes this heading into Dia's brief prompt as it builds: keep the two in step.
static NSString *const DPBriefHeading = @"## Output language: ";
static BOOL DPBuilding, DPStale, DPBuilt;

static NSString *DPBriefPrompt(void) {
    NSString *path = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"agent-server-resources/dist/prompts/skills/morning-brief/SKILL.md"];
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

// The language this Dia was built to write in, or nil for Dia's own.
static NSString *DPInstalledLanguage(void) {
    NSString *prompt = DPBriefPrompt();
    NSRange heading = [prompt rangeOfString:DPBriefHeading options:NSBackwardsSearch];
    if (!heading.length) return nil;
    NSString *rest = [prompt substringFromIndex:NSMaxRange(heading)];
    return [rest substringToIndex:[rest rangeOfString:@"\n"].location == NSNotFound ? rest.length : [rest rangeOfString:@"\n"].location];
}

static NSString *DPWantedLanguage(void) { return DPBriefLanguage.on ? DPChoice(&DPBriefLanguage) : nil; }

static BOOL DPSame(NSString *a, NSString *b) { return a == b || [a isEqual:b]; }

static NSString *DPKeptReason(NSString *output) {
    NSString *prefix = @"warning: kept the Morning Brief's language: ";
    for (NSString *line in [output componentsSeparatedByString:@"\n"])
        if ([line hasPrefix:prefix]) return [line substringFromIndex:prefix.length];
    return nil;
}

static void DPAlert(NSString *message, NSString *detail) {
    NSAlert *alert = [NSAlert new];
    alert.messageText = message;
    alert.informativeText = detail;
    [alert runModal];
}

// The prompt is sealed by Dia's signature, so a new language means a new build, like a new icon catalog.
static void DPRebuild(void) {
    if (DPBuilding) return (void)(DPStale = YES);
    DPBuilding = YES;
    CFPreferencesAppSynchronize(CFSTR("com.diapatches"));
    DPRunCLI(@[ @"build" ], ^(NSString *output) {
        DPBuilding = NO;
        DPBuilt = YES;
        if (DPStale) return DPStale = NO, DPRebuild();
        if (!output) return DPAlert(@"Couldn’t change the Morning Brief’s language", @"Dia keeps writing it as it does now.");
        NSString *kept = DPKeptReason(output);
        if (kept) return DPAlert(@"Couldn’t change the Morning Brief’s language", [NSString stringWithFormat:@"Dia keeps writing it as it does now: %@.", kept]);
        if (DPSame(DPWantedLanguage(), DPInstalledLanguage())) return;
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Relaunch Dia to change the Morning Brief’s language";
        alert.informativeText = @"Until then, Dia keeps writing it as it does now. The next brief Dia writes uses the new language.";
        [alert addButtonWithTitle:@"Relaunch"];
        [alert addButtonWithTitle:@"Later"];
        if ([alert runModal] == NSAlertFirstButtonReturn) DPHandOffAndQuit(@[ @"apply" ]);
    });
}

static void DPApplyBriefLanguage(DPPatch *patch) {
    if (DPTesting || !DPBriefPrompt()) return;
    // diapatch reads only saved settings, so save the language picked from macOS before it builds.
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    if (patch->on && ![defaults stringForKey:patch->choice]) [defaults setObject:DPChoice(patch) forKey:patch->choice];
    // Once a build is staged it has to follow every change, back to this Dia's own language too.
    if (DPBuilt || DPBuilding || !DPSame(DPWantedLanguage(), DPInstalledLanguage())) DPRebuild();
}

static NSString *DPVerifyBriefLanguage(DPPatch *patch) { return DPBriefPrompt() ? nil : @"Dia’s Morning Brief prompt isn’t in its bundle"; }

// Its own name, the name the prompt uses, and the macOS language that picks it before you choose.
static NSArray<NSArray<NSString *> *> *DPLanguages(void) {
    return @[
        @[ @"English", @"English", @"en" ], @[ @"日本語", @"Japanese", @"ja" ], @[ @"简体中文", @"Chinese (Simplified)", @"zh-Hans" ],
        @[ @"繁體中文", @"Chinese (Traditional)", @"zh-Hant" ], @[ @"한국어", @"Korean", @"ko" ], @[ @"Español", @"Spanish", @"es" ],
        @[ @"Français", @"French", @"fr" ], @[ @"Deutsch", @"German", @"de" ], @[ @"Italiano", @"Italian", @"it" ], @[ @"Português", @"Portuguese", @"pt" ],
        @[ @"Nederlands", @"Dutch", @"nl" ], @[ @"Русский", @"Russian", @"ru" ], @[ @"Türkçe", @"Turkish", @"tr" ], @[ @"Bahasa Indonesia", @"Indonesian", @"id" ],
        @[ @"Tiếng Việt", @"Vietnamese", @"vi" ], @[ @"ไทย", @"Thai", @"th" ], @[ @"हिन्दी", @"Hindi", @"hi" ], @[ @"العربية", @"Arabic", @"ar" ],
    ];
}

static NSString *DPSystemLanguage(void) {
    for (NSString *preferred in NSLocale.preferredLanguages)
        for (NSArray<NSString *> *language in DPLanguages())
            if ([preferred isEqual:language[2]] || [preferred hasPrefix:[language[2] stringByAppendingString:@"-"]]) return language[1];
    return @"English";
}

static void DPInstallBriefLanguage(void) { DPBriefLanguage.defaultChoice = DPSystemLanguage(); }

static NSMenu *DPBriefLanguageChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Language"];
    for (NSArray<NSString *> *language in DPLanguages()) [menu addItemWithTitle:language[0] action:nil keyEquivalent:@""].representedObject = language[1];
    return menu;
}

DP_PATCH(DPBriefLanguage) {
    .key = @"briefLanguage",
    .order = 117,
    .title = @"Morning Brief Language",
    .detail = @"Choose the language Dia writes your Morning Brief in, whatever language your messages and documents are in. "
              @"Dia is rebuilt with that language added to its Morning Brief prompt, then relaunches. The next brief uses it. Experimental.",
    .symbol = @"character.bubble.fill character.bubble",
    .tint = @"systemPurpleColor",
    .section = @"AI",
    .disabledBy = @"turnOffAI",
    .choice = @"briefLanguageChoice",
    .choices = DPBriefLanguageChoices,
    .install = DPInstallBriefLanguage,
    .apply = DPApplyBriefLanguage,
    .verify = DPVerifyBriefLanguage,
    .ready = DPVerifyBriefLanguage,
};
