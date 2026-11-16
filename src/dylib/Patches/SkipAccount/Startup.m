#import "Startup.h"

// Dia 1.57.1 (90935), arm64. Unknown or ambiguous code stays untouched.
// initializeAuth() has finished initializing auth here. With no user it waits for sign-in; otherwise it returns .restored.
static const DPSkipInstruction DPLaunch[] = {
    {0xb24403bd, 0xffffffff},
    {0xd10083ff, 0xffffffff},
    {0xa9017bfd, 0xffffffff},
    {0xf90007f6, 0xffffffff},
    {0x910043fd, 0xffffffff},
    {0x3944e6c8, 0xffffffff},
    {0x7100051f, 0xffffffff},
    {0x540001a1, 0xffffffff},
    {0xf940b2c0, 0xffffffff},
    {0xf940aad4, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0x528000e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xf94006c1, 0xffffffff},
    {0x52800040, 0xffffffff},
    {0xd2800014, 0xffffffff},
    {0xa9417bfd, 0xffffffff},
    {0x9243fbbd, 0xffffffff},
    {0x910083ff, 0xffffffff},
    {0xd61f0020, 0xffffffff},
};

// Window creation separately rejects a signed-out user. Keep the readiness and termination checks around it.
// The first load's field offset changes in every Dia release (0xf28, 0xf78, 0xf68), so only its registers are matched.
static const DPSkipInstruction DPWindow[] = {
    {0xf9400114, 0xffc003ff},
    {0xb4000014, 0xff00001f},
    {0xaa1403e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0x94000000, 0xfc000000},
    {0xaa0003f3, 0xffffffff},
    {0xaa1403e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0x36002133, 0xffffffff},
    {0xf946eed4, 0xffffffff},
    {0xf946eac0, 0xffffffff},
    {0x52800021, 0xffffffff},
};

BOOL DPSkipAccountStartup(void) {
    uint32_t *launch = DPSkipFindCode(DPLaunch, sizeof DPLaunch / sizeof *DPLaunch);
    uint32_t *window = DPSkipFindCode(DPWindow, sizeof DPWindow / sizeof *DPWindow);
    if (!launch || !window) return NO;
    if (!DPSkipWriteCode(launch + 7, DPLaunch[7].value, 0xd503201f)) return NO;
    if (DPSkipWriteCode(window + 8, DPWindow[8].value, 0xd503201f)) return YES;
    DPSkipWriteCode(launch + 7, 0xd503201f, DPLaunch[7].value);
    return NO;
}
