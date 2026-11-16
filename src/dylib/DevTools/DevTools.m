#import "DevTools/DevTools.h"
#import "Updates/Updates.h"
#include <dlfcn.h>

static void DPDescribe(NSView *view, NSUInteger depth, NSMutableString *out) {
    NSString *label = view.accessibilityLabel;
    [out appendFormat:@"%*s%@ %@", (int)depth * 2, "", NSStringFromClass(view.class), NSStringFromRect(view.frame)];
    if (label.length) [out appendFormat:@" label=\"%@\"", label];
    if (view.layer.cornerRadius > 0)
        [out appendFormat:@" radius=%g corners=%lu", view.layer.cornerRadius, (unsigned long)view.layer.maskedCorners];
    if ([view isKindOfClass:NSTextField.class] && [(NSTextField *)view stringValue].length)
        [out appendFormat:@" text=\"%@\"", [(NSTextField *)view stringValue]];
    if ([view isKindOfClass:NSTableRowView.class] && [(NSTableRowView *)view isSelected]) [out appendString:@" selected"];
    if (view.hidden) [out appendString:@" hidden"];
    [out appendString:@"\n"];
    for (NSView *sub in view.subviews) DPDescribe(sub, depth + 1, out);
}

NSString *DPBesideDylib(NSString *name) {
    Dl_info dylib;
    dladdr((const void *)DPInstallDevTools, &dylib);
    return [@(dylib.dli_fname).stringByDeletingLastPathComponent stringByAppendingPathComponent:name];
}

NSString *DPDescribeViews(NSView *root) {
    NSMutableString *out = [NSMutableString new];
    if (root) DPDescribe(root, 0, out);
    return out;
}

static void DPCopyViewTree(void) {
    NSWindow *window = NSApp.keyWindow ?: NSApp.orderedWindows.firstObject;
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:DPDescribeViews(window.contentView.superview) forType:NSPasteboardTypeString];
}

static void DPScriptSet(NSNotification *note) {
    NSArray<NSString *> *parts = [note.object componentsSeparatedByString:@"="];
    DPPatch *patch = parts.count == 2 ? DPPatchNamed(parts[0]) : NULL;
    if (patch) DPSetPatch(patch, parts[1].boolValue, YES);
    for (NSUInteger i = 0; parts.count == 2 && i < DPPatchCount; i++)
        if ([DPPatches[i]->choice isEqualToString:parts[0]]) DPSetChoice(DPPatches[i], parts[1]);
}

static void DPScriptType(NSNotification *note) {
    id responder = (NSApp.keyWindow ?: NSApp.orderedWindows.firstObject).firstResponder;
    if (![responder isKindOfClass:NSTextView.class] || ![note.object isKindOfClass:NSString.class]) return;
    NSString *text = note.object;
    if ([text hasPrefix:@"@"]) @try { [responder doCommandBySelector:NSSelectorFromString([text substringFromIndex:1])]; } @catch (NSException *e) {}
    else if ([text hasPrefix:@"="]) [responder insertText:[text substringFromIndex:1] replacementRange:NSMakeRange(0, [[responder string] length])];
    else [responder insertText:text replacementRange:[responder selectedRange]];
}

static void DPScriptMethods(NSNotification *note) {
    NSMutableString *out = [NSMutableString new];
    NSView *live = DPFindViews([note.object UTF8String]).firstObject;
    NSMutableArray *classes = [NSMutableArray arrayWithObjects:note.object, nil];
    for (NSString *key in @[@"delegate", @"dataSource"])
        if ([live respondsToSelector:NSSelectorFromString(key)]) {
            id value = [live valueForKey:key];
            [out appendFormat:@"%@: %s\n", key, value ? object_getClassName(value) : "nil"];
            if (value) [classes addObject:@(object_getClassName(value))];
        }
    for (NSString *name in classes)
        for (Class cls = NSClassFromString(name); cls && cls != NSObject.class && cls != NSView.class && cls != NSResponder.class; cls = class_getSuperclass(cls)) {
            unsigned count = 0;
            Method *methods = class_copyMethodList(cls, &count);
            [out appendFormat:@"== %s\n", class_getName(cls)];
            for (unsigned i = 0; i < count; i++) [out appendFormat:@"  %s %s\n", sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i])];
            free(methods);
        }
    [out writeToFile:DPBesideDylib(@"methods.txt") atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void DPScriptDump(NSNotification *note) {
    NSMutableString *out = [NSMutableString new];
    for (NSWindow *window in NSApp.windows)
        [out appendFormat:@"== window \"%@\"\n%@", window.title, DPDescribeViews(window.contentView.superview)];
    [out writeToFile:DPBesideDylib(@"views.txt") atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void DPListen(NSString *name, void (*handler)(NSNotification *)) {
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                           usingBlock:^(NSNotification *note) { handler(note); }];
}

static void DPListenForScripts(void) {
    DPListen(@"com.diapatches.dev.set", DPScriptSet);
    DPListen(@"com.diapatches.dev.type", DPScriptType);
    DPListen(@"com.diapatches.dev.methods", DPScriptMethods);
    DPListen(@"com.diapatches.dev.dump", DPScriptDump);
}

void DPInstallDevTools(void) {
    if (![[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] boolForKey:@"devTools"]) return;
    DPListenForScripts();
    DPTraceLayoutLoops();
    DPOnLaunch(^{
        DPAddMenuItem(@"Help", @"DiaPatches: Copy View Tree", ^{ DPCopyViewTree(); });
        NSMenu *debug = [[NSMenu alloc] initWithTitle:@"Debug"];
        [debug addItem:DPMenuItem(@"Pretend Dia Has an Update", ^{ [DPUpdates.shared pretend:DPDia]; })];
        [debug addItem:DPMenuItem(@"Pretend DiaTweaks Has an Update", ^{ [DPUpdates.shared pretend:DPTweaks]; })];
        [debug addItem:DPMenuItem(@"Stop Pretending", ^{ [DPUpdates.shared stopPretending]; })];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Debug" action:nil keyEquivalent:@""];
        item.submenu = debug;
        [NSApp.mainMenu insertItem:item atIndex:1];
    });
}
