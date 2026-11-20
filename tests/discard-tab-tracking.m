#import "Patches/DiscardInactiveTabs/DiscardInactiveTabs.h"

DPPatch DPDiscardInactiveTabs = { .on = YES };
static NSUInteger dressings;
NSDictionary<NSString *, NSString *> *DPLoadedPaneStates(void) { return @{}; }
NSArray<NSString *> *DPDressTabView(NSView *view, NSDictionary *states) { dressings++; return @[]; }
void DPClearTabView(NSView *view) {}
#import "Patches/DiscardInactiveTabs/TabTracking.m"

static NSUInteger wakeups;

static void runFor(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static NSUInteger wakeupsDuring(NSTimeInterval seconds) {
    NSUInteger before = wakeups;
    runFor(seconds);
    return wakeups - before;
}

int main(void) {
    @autoreleasepool {
        CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeSources, YES, 0,
            ^(CFRunLoopObserverRef _, CFRunLoopActivity __) { wakeups++; });
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
        DPInstallTabTracking();

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:0
                                                         backing:NSBackingStoreBuffered defer:YES];
        window.releasedWhenClosed = NO;
        NSView *kept = [NSView new];
        [window.contentView addSubview:kept];
        DPTrackTabView(kept);
        runFor(0.3);
        NSCAssert(dressings == 2, @"a tracked row is dressed once now and once after Dia configures it");

        @autoreleasepool {
            for (int i = 0; i < 64; i++) {
                NSView *gone = [NSView new];
                [window.contentView addSubview:gone];
                DPTrackTabView(gone);
                [gone removeFromSuperview];
            }
        }
        runFor(0.3);
        NSUInteger idle = wakeupsDuring(0.3);
        NSCAssert(idle < 20, @"rows freed before their dressing leave the main thread idle, not redraining forever");

        NSUInteger before = dressings;
        DPSweepTabViews();
        runFor(0.05);
        NSCAssert(dressings == before + 1, @"a sweep after freed rows still dresses the rows that remain");
        printf("discard-tab-tracking: ok (%lu idle wakeups)\n", (unsigned long)idle);
    }
}
