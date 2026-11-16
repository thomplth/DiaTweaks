#import "Settings.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <VideoToolbox/VideoToolbox.h>

#ifndef DP_PREVIEWS
#define DP_PREVIEWS "https://raw.githubusercontent.com/wiki/JaceThings/DiaTweaks/previews/"
#endif

static NSNotificationName const DPTabLayoutMayHaveChanged = @"DPTabLayoutMayHaveChanged";

static void DPSidebarFooter_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPSidebarFooter_viewDidMoveToWindow, self);
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:DPTabLayoutMayHaveChanged object:nil];
    });
}

void DPInstallPreviews(void) {
    DPHook(DPDiaSidebarFooter, @selector(viewDidMoveToWindow), (IMP)DPSidebarFooter_viewDidMoveToWindow);
}

static NSURL *DPCachedPreview(NSString *name) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [caches URLByAppendingPathComponent:@"DiaPatches/previews" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir URLByAppendingPathComponent:name];
}

static NSArray<NSString *> *DPPreviewNames(NSString *key, NSString *layout) {
    NSString *other = [layout isEqual:@"vertical"] ? @"horizontal" : @"vertical";
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (NSString *prefix in @[layout, other])
        for (NSString *suffix in @[@"-onoff.webp", @".mp4", @".png"]) [names addObject:[NSString stringWithFormat:@"%@-%@%@", prefix, key, suffix]];
    return names;
}

static BOOL DPIsPreview(NSData *data, NSString *name) {
    if (data.length < 8) return NO;
    if ([name hasSuffix:@".mp4"]) return !memcmp((const char *)data.bytes + 4, "ftyp", 4);
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    BOOL decoded = image != NULL;
    CGImageRelease(image);
    if (source) CFRelease(source);
    return decoded;
}

static void DPFetchPreview(NSArray<NSString *> *names, void (^done)(NSURL *file, BOOL changed)) {
    if (!names.count) return done(nil, NO);
    NSURL *cached = DPCachedPreview(names[0]);
    NSURL *url = [NSURL URLWithString:[@DP_PREVIEWS stringByAppendingString:names[0]]];
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        BOOL preview = status == 200 && DPIsPreview(data, names[0]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || (status != 200 && status != 404)) return done(nil, NO);
            if (status == 404) {
                [NSFileManager.defaultManager removeItemAtURL:cached error:nil];
                return DPFetchPreview([names subarrayWithRange:NSMakeRange(1, names.count - 1)], done);
            }
            if (!preview) return done(nil, NO);
            BOOL changed = ![[NSData dataWithContentsOfURL:cached] isEqualToData:data];
            if (changed) [data writeToURL:cached atomically:YES];
            done(cached, changed);
        });
    }] resume];
}

@implementation DPPreviewView {
    NSString *_key, *_layout;
    NSArray<NSString *> *_names;
    NSURL *_shown;
    CALayer *_media;
    AVPlayer *_player;
    AVPlayerItemVideoOutput *_output;
    CADisplayLink *_link;
    NSArray *_states;
    NSTimer *_flip;
}

+ (void)preload {
    static NSMutableSet<NSString *> *started;
    if (!started) started = [NSMutableSet new];
    NSString *layout = DPTabLayout();
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        NSArray<NSString *> *names = DPPreviewNames(DPPatches[i]->key, layout);
        if ([started containsObject:names[0]]) continue;
        [started addObject:names[0]];
        DPFetchPreview(names, ^(NSURL *file, BOOL changed) {});
    }
}

- (instancetype)initWithKey:(NSString *)key {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _key = key;
    self.hidden = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(load) name:DPTabLayoutMayHaveChanged object:nil];
    [self load];
    return self;
}

- (void)load {
    NSString *layout = DPTabLayout();
    if ([layout isEqual:_layout]) return;
    _layout = layout;
    NSArray<NSString *> *names = _names = DPPreviewNames(_key, layout);
    for (NSString *name in names)
        if ([DPCachedPreview(name) checkResourceIsReachableAndReturnError:nil]) {
            [self show:DPCachedPreview(name)];
            break;
        }
    __weak DPPreviewView *weakSelf = self;
    DPFetchPreview(names, ^(NSURL *file, BOOL changed) {
        DPPreviewView *view = weakSelf;
        if (!view || view->_names != names) return;
        if (!file) {
            if (!view->_shown) [view show:nil];
        } else if (changed || ![file isEqual:view->_shown]) {
            [view show:file];
        }
    });
}

- (void)show:(NSURL *)file {
    [_media removeFromSuperlayer];
    [_player pause];
    _player = nil;
    _output = nil;
    _states = nil;
    [self updatePlayback];
    _media = nil;
    _shown = file;
    self.hidden = !file;
    if (!file) return;
    _media = [CALayer layer];
    _media.contentsGravity = kCAGravityResizeAspectFill;
    _media.frame = self.bounds;
    [self.layer addSublayer:_media];
    // Off in the top half, on in the bottom.
    if ([file.lastPathComponent hasSuffix:@"-onoff.webp"]) {
        CGImageRef image = [[[NSImage alloc] initWithContentsOfURL:file] CGImageForProposedRect:NULL context:nil hints:nil];
        size_t width = CGImageGetWidth(image), half = CGImageGetHeight(image) / 2;
        id off = (__bridge_transfer id)CGImageCreateWithImageInRect(image, CGRectMake(0, 0, width, half));
        id on = (__bridge_transfer id)CGImageCreateWithImageInRect(image, CGRectMake(0, half, width, half));
        if (!off || !on) return [self show:nil];
        _states = @[ off, on ];
        [self showState];
        [self updatePlayback];
        return;
    }
    if (![file.pathExtension isEqualToString:@"mp4"]) {
        _media.contents = [[NSImage alloc] initWithContentsOfURL:file];
        return;
    }
    // Not an AVPlayerLayer: macOS can hand that to the display hardware, which draws black bars at the preview's edges.
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:file];
    _output = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)}];
    [item addOutput:_output];
    _player = [AVPlayer playerWithPlayerItem:item];
    _player.muted = YES;
    _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(rewind:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [self updatePlayback];
}

- (void)rewind:(NSNotification *)note {
    [_player seekToTime:kCMTimeZero];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidChangeOcclusionStateNotification object:nil];
    if (self.window) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updatePlayback) name:NSWindowDidChangeOcclusionStateNotification object:self.window];
    [self updatePlayback];
}

- (void)showState {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _media.contents = _states[(long)NSDate.date.timeIntervalSince1970 % 2];
    [CATransaction commit];
}

- (void)updatePlayback {
    [_link invalidate];
    _link = nil;
    [_flip invalidate];
    _flip = nil;
    BOOL visible = self.window.occlusionState & NSWindowOcclusionStateVisible;
    if (visible && _states) {
        [self showState];
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        _flip = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSince1970:floor(now) + 1] interval:1 target:self selector:@selector(showState) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_flip forMode:NSRunLoopCommonModes];
    }
    if (!visible || !_player) return [_player pause];
    _link = [self displayLinkWithTarget:self selector:@selector(drawFrame)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [_player play];
}

- (void)drawFrame {
    CMTime time = [_output itemTimeForHostTime:CACurrentMediaTime()];
    if (![_output hasNewPixelBufferForItemTime:time]) return;
    CVPixelBufferRef buffer = [_output copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];
    if (!buffer) return;
    CGImageRef image = NULL;
    VTCreateCGImageFromCVPixelBuffer(buffer, NULL, &image);
    CVPixelBufferRelease(buffer);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _media.contents = (__bridge_transfer id)image;
    [CATransaction commit];
}

- (void)updateLayer {
    [super updateLayer];
    self.layer.borderWidth = 1;
    self.layer.borderColor = NSColor.separatorColor.CGColor;
}

- (void)layout {
    [super layout];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _media.frame = self.bounds;
    [CATransaction commit];
}
@end
