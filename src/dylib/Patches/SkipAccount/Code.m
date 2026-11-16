#import "Startup.h"
#import <libkern/OSCacheControl.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach/mach_vm.h>

uint32_t *DPSkipFindCode(const DPSkipInstruction *signature, NSUInteger length) {
    const struct mach_header_64 *header = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++)
        if (_dyld_get_image_header(i)->filetype == MH_EXECUTE) header = (const struct mach_header_64 *)_dyld_get_image_header(i);
    if (!header) return NULL;
    unsigned long size = 0;
    const uint32_t *text = (const uint32_t *)getsectiondata(header, "__TEXT", "__text", &size);
    uint32_t *found = NULL;
    for (NSUInteger i = 0; text && i + length <= size / sizeof *text; i++) {
        NSUInteger j = 0;
        while (j < length && (text[i + j] & signature[j].mask) == signature[j].value) j++;
        if (j != length) continue;
        if (found) return NULL;
        found = (uint32_t *)(text + i);
    }
    return found;
}

BOOL DPSkipWriteCode(uint32_t *site, uint32_t expected, uint32_t value) {
    if (*site != expected) return NO;
    mach_vm_address_t page = (mach_vm_address_t)site & ~((mach_vm_address_t)vm_page_size - 1);
    if (mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY)) return NO;
    *site = value;
    sys_icache_invalidate(site, sizeof *site);
    if (!mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE)) return YES;
    *site = expected;
    sys_icache_invalidate(site, sizeof *site);
    mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    return NO;
}
