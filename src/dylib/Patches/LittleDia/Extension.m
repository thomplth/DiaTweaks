#import "LittleDia.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *const kKeyword = @"diatweaks-little-dia";

static NSString *const kManifest = @"{\n"
    @"  \"manifest_version\": 3,\n"
    @"  \"name\": \"DiaTweaks Little Dia\",\n"
    @"  \"description\": \"Opens links from other apps in a small window.\",\n"
    @"  \"version\": \"1\",\n"
    @"  \"permissions\": [\"tabs\", \"search\"],\n"
    @"  \"omnibox\": { \"keyword\": \"%@\" },\n"
    @"  \"background\": { \"service_worker\": \"worker.js\" }\n"
    @"}\n";

static NSString *const kWorker = @"const popupTab = async ({ tabId, url }) => {\n"
    @"  const byId = tabId ? await chrome.tabs.get(tabId).catch(() => null) : null;\n"
    @"  if (byId) return byId;\n"
    @"  const tabs = await chrome.tabs.query({ windowType: 'popup' });\n"
    @"  return tabs.find((tab) => tab.url === url) ?? (tabs.length === 1 ? tabs[0] : null);\n"
    @"};\n"
    @"chrome.omnibox.onInputEntered.addListener(async (text) => {\n"
    @"  const request = JSON.parse(text);\n"
    @"  if (request.action === 'open') {\n"
    @"    const { url, left, top, width, height, until } = request;\n"
    @"    if (Date.now() > until) return;\n"
    @"    return chrome.windows.create({ url, type: 'popup', focused: true, left, top, width, height });\n"
    @"  }\n"
    @"  const tab = await popupTab(request);\n"
    @"  if (!tab) return;\n"
    @"  if (request.action === 'search') return chrome.search.query({ text: request.text, tabId: tab.id });\n"
    @"  if (request.action !== 'promote' || !tab.url) return;\n"
    @"  const normal = await chrome.windows.getLastFocused({ windowTypes: ['normal'] }).catch(() => null);\n"
    @"  if (normal) {\n"
    @"    const moved = await chrome.tabs.move(tab.id, { windowId: normal.id, index: -1 }).catch(() => null);\n"
    @"    if (moved) await chrome.tabs.update(tab.id, { active: true });\n"
    @"    else await chrome.tabs.create({ windowId: normal.id, url: tab.url, active: true });\n"
    @"    await chrome.windows.update(normal.id, { focused: true });\n"
    @"  } else {\n"
    @"    await chrome.windows.create({ url: tab.url, focused: true });\n"
    @"  }\n"
    @"  await chrome.windows.remove(tab.windowId).catch(() => {});\n"
    @"});\n";

// Chromium keeps an extension's worker from its first run, so a changed worker needs a new folder.
static NSString *DPExtensionFolder(void) {
    uint32_t hash = 2166136261u;
    for (const char *c = kWorker.UTF8String; *c; c++) hash = (hash ^ (uint8_t)*c) * 16777619u;
    return DPAppSupport([NSString stringWithFormat:@"DiaPatches/little-dia-%08x", hash]);
}

static NSString *gExtensionID;
static NSError *gWriteError;
static NSTimeInterval gLaunchedAt;
static const NSTimeInterval DPLaunchTime = 20;

static NSString *DPExtensionID(NSString *folder) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    const char *path = folder.fileSystemRepresentation;
    CC_SHA256(path, (CC_LONG)strlen(path), digest);
    NSMutableString *id = [NSMutableString string];
    for (int i = 0; i < 16; i++) [id appendFormat:@"%c%c", 'a' + (digest[i] >> 4), 'a' + (digest[i] & 15)];
    return id;
}

static NSDictionary<NSString *, NSString *> *DPExtensionFiles(void) {
    return @{@"manifest.json" : [NSString stringWithFormat:kManifest, kKeyword], @"worker.js" : kWorker};
}

BOOL DPWriteLittleDiaExtension(BOOL on) {
    NSString *folder = DPExtensionFolder(), *parent = folder.stringByDeletingLastPathComponent;
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *name in [files contentsOfDirectoryAtPath:parent error:nil])
        if ([name hasPrefix:@"little-dia-"] && (![name isEqual:folder.lastPathComponent] || !on))
            [files removeItemAtPath:[parent stringByAppendingPathComponent:name] error:nil];
    gWriteError = nil;
    if (!on) return YES;
    NSError *error;
    BOOL written = [files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error];
    NSDictionary<NSString *, NSString *> *contents = DPExtensionFiles();
    for (NSString *name in contents)
        written = written && [contents[name] writeToFile:[folder stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:&error];
    gWriteError = written ? nil : error;
    return written;
}

NSString *DPLittleDiaExtensionProblem(void) {
    NSString *folder = DPExtensionFolder();
    if (gWriteError) return [NSString stringWithFormat:@"Couldn’t write %@: %@", folder, gWriteError.localizedDescription];
    for (NSString *name in DPExtensionFiles()) {
        NSString *path = [folder stringByAppendingPathComponent:name];
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) return [NSString stringWithFormat:@"%@ is missing.", path];
    }
    return nil;
}

void DPInstallLittleDiaExtension(void) {
    gLaunchedAt = NSProcessInfo.processInfo.systemUptime;
    if (!DPWriteLittleDiaExtension(DPLittleDia.on) || !DPLittleDia.on) return;
    DPLoadExtension(DPExtensionFolder());
    gExtensionID = DPExtensionID(DPExtensionFolder());
}

static id DPExtensions(id browser) {
    id context = [browser respondsToSelector:@selector(context)] ? DPMsg(browser, @selector(context)) : nil;
    return [context respondsToSelector:@selector(extensions)] ? DPMsg(context, @selector(extensions)) : nil;
}

// No browser means a launch with no window yet, but only for a while: later it's Dia with every window closed.
BOOL DPLittleDiaStarting(void) {
    id extensions = DPExtensions(DPCommandBrowser());
    if (!extensions) return gExtensionID && NSProcessInfo.processInfo.systemUptime - gLaunchedAt < DPLaunchTime;
    return gExtensionID && [extensions respondsToSelector:@selector(isExtensionSystemReady)] && !DPMsgBool(extensions, @selector(isExtensionSystemReady));
}

// Chromium crashes on input for an extension that isn't loaded and on, as after it's turned off in Extensions.
BOOL DPLittleDiaReady(void) {
    id browser = DPCommandBrowser();
    id extensions = DPExtensions(browser);
    SEL trigger = @selector(triggerExtensionOmniboxInput:inputText:disposition:);
    if (!gExtensionID || ![browser respondsToSelector:trigger] || ![extensions respondsToSelector:@selector(isExtensionSystemReady)]
        || !DPMsgBool(extensions, @selector(isExtensionSystemReady)) || ![extensions respondsToSelector:@selector(getExtensionInfo:)])
        return NO;
    id info = ((id (*)(id, SEL, NSString *))objc_msgSend)(extensions, @selector(getExtensionInfo:), gExtensionID);
    return [info respondsToSelector:@selector(enabled)] && DPMsgBool(info, @selector(enabled));
}

BOOL DPSendToLittleDia(NSDictionary *request) {
    if (!DPLittleDiaReady()) return NO;
    NSData *json = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!text) return NO;
    void (*send)(id, SEL, NSString *, NSString *, long) = (void *)objc_msgSend;
    send(DPCommandBrowser(), @selector(triggerExtensionOmniboxInput:inputText:disposition:), gExtensionID, text, 1);
    return YES;
}
