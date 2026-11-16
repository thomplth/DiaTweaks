#import "StdPatch/StdPatch.h"
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <libkern/OSCacheControl.h>

extern DPPatch DPOpenSidebarInstantly;

static const uint32_t DPLoadDelay = 0x9E670100;
static const uint32_t DPNoDelay = 0x9E6703E0;
static const NSUInteger DPSiteIndex = 28;
static uint32_t *DPSite;

static const struct { uint32_t value, mask; } DPSignature[] = {
    {0xcb0c0119, 0xffffffff},
    {0x9100033f, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xfd002a80, 0xffffffff},
    {0x90000000, 0x9f000000},
    {0xf9400100, 0xffc003ff},
    {0x94000000, 0xfc000000},
    {0xaa0003fb, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0x6d058680, 0xffffffff},
    {0xf9401a98, 0xffffffff},
    {0xb4000000, 0xff000000},
    {0xf9401f54, 0xffffffff},
    {0xaa1b03e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xd63f0300, 0xffffffff},
    {0xfd402b48, 0xffffffff},
    {0xd2800000, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xaa0003f4, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xaa0003fb, 0xffffffff},
    {0xaa1c03e8, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xd2828f68, 0xffffffff},
    {0xf2a8f5c8, 0xffffffff},
    {0xf2cf5c28, 0xffffffff},
    {0xf2e7f688, 0xffffffff},
    {0x00000000, 0x00000000},
    {0xaa1903e8, 0xffffffff},
    {0xaa1c03e0, 0xffffffff},
};

static BOOL DPMatchesAt(const uint32_t *code) {
    for (NSUInteger i = 0; i < sizeof DPSignature / sizeof *DPSignature; i++)
        if ((code[i] & DPSignature[i].mask) != DPSignature[i].value) return NO;
    return code[DPSiteIndex] == DPLoadDelay || code[DPSiteIndex] == DPNoDelay;
}

static NSUInteger DPSearch(const uint32_t *text, NSUInteger first, NSUInteger end, uint32_t **found) {
    NSUInteger count = 0;
    for (NSUInteger i = first; i < end; i++)
        if (DPMatchesAt(text + i)) count++, *found = (uint32_t *)(text + i + DPSiteIndex);
    return count;
}

// Measured on Dia 1.57.0: searched first, the whole 100 MB only as a fallback.
static uint32_t *DPFindSite(void) {
    unsigned long size = 0;
    const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(0);
    const uint32_t *text = (const uint32_t *)getsectiondata(header, "__TEXT", "__text", &size);
    if (!text) return NULL;
    NSUInteger words = size / 4 - sizeof DPSignature / sizeof *DPSignature, near = 0x1ff629, reach = 0x10000;
    uint32_t *found = NULL;
    if (near + reach < words && DPSearch(text, near - reach, near + reach, &found) == 1) return found;
    return DPSearch(text, 0, words, &found) == 1 ? found : NULL;
}

static BOOL DPRewrite(uint32_t expected, uint32_t value) {
    if (!DPSite || *DPSite != expected) return NO;
    mach_vm_address_t page = (mach_vm_address_t)DPSite & ~((mach_vm_address_t)vm_page_size - 1);
    if (mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY)) return NO;
    *DPSite = value;
    mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    sys_icache_invalidate(DPSite, sizeof *DPSite);
    return YES;
}

// Looked for the first time the switch is on, so Dia launches without the search while it's off.
static BOOL DPSearched;

static uint32_t *DPLocate(void) {
    if (!DPSearched) DPSite = DPFindSite(), DPSearched = YES;
    return DPSite;
}

static void DPApplyOpenSidebarInstantly(DPPatch *patch) {
    if (!patch->on) return (void)DPRewrite(DPNoDelay, DPLoadDelay);
    if (DPLocate()) return (void)DPRewrite(DPLoadDelay, DPNoDelay);
    patch->unavailable = YES;
    DPSetPatch(patch, NO, !DPTesting);
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil]; });
}

// Off in memory only: the saved switch stays on for a release that knows this Dia's code.
static void DPInstallOpenSidebarInstantly(void) {
    if (!DPOpenSidebarInstantly.on) return;
    if (DPLocate()) return DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly);
    DPOpenSidebarInstantly.unavailable = YES;
    DPOpenSidebarInstantly.on = NO;
    NSLog(@"DiaPatches: Open Sidebar Instantly doesn't know this Dia's sidebar code, so it stays off");
}

static NSString *DPVerifyOpenSidebarInstantly(DPPatch *patch) {
    if (!patch->on && !DPSite) return nil;
    if (!DPSite) return @"the delay isn't where it was";
    uint32_t expected = patch->on ? DPNoDelay : DPLoadDelay;
    return *DPSite == expected ? nil : patch->on ? @"the delay is still there" : @"the delay is gone";
}

DP_PATCH(DPOpenSidebarInstantly) {
    .key = @"openSidebarInstantly",
    .order = 116,
    .title = @"Open Sidebar Instantly",
    .detail = @"With the sidebar hidden, open it the moment the pointer reaches the left edge instead of after Dia's short wait. A hidden tab bar at the top shows sooner too. Dia's animation and how it closes stay as they are. May need an update after some Dia releases.",
    .symbol = @"arrow.right.to.line.circle.fill arrow.right.to.line",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .install = DPInstallOpenSidebarInstantly,
    .apply = DPApplyOpenSidebarInstantly,
    .verify = DPVerifyOpenSidebarInstantly,
};
