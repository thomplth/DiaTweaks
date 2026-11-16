#import "StdPatch/StdPatch.h"

typedef struct { Class cls; SEL sel; IMP replacement, original; } DPHookRecord;
static DPHookRecord *DPHooks;
static size_t DPHookCount;

void DPHookClass(Class cls, SEL sel, IMP replacement) {
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!method) return;
    // Already hooked here or in a superclass: a second copy would find itself as the original and recurse.
    for (size_t i = 0; i < DPHookCount; i++) {
        if (DPHooks[i].sel != sel || DPHooks[i].replacement != replacement) continue;
        for (Class c = cls; c; c = class_getSuperclass(c)) if (c == DPHooks[i].cls) return;
    }
    IMP original = method_getImplementation(method);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) method_setImplementation(method, replacement);
    DPHooks = realloc(DPHooks, ++DPHookCount * sizeof *DPHooks);
    DPHooks[DPHookCount - 1] = (DPHookRecord){cls, sel, replacement, original};
}

void DPHook(const char *className, SEL sel, IMP replacement) {
    Class cls = objc_getClass(className);
    if (!class_getInstanceMethod(cls, sel)) NSLog(@"DiaPatches: can't hook -[%s %@]; Dia may have renamed it", className, NSStringFromSelector(sel));
    else DPHookClass(cls, sel, replacement);
}

IMP DPOriginalIMP(id object, SEL sel, IMP replacement) {
    for (Class c = object_getClass(object); c; c = class_getSuperclass(c))
        for (size_t i = 0; i < DPHookCount; i++)
            if (DPHooks[i].cls == c && DPHooks[i].sel == sel && DPHooks[i].replacement == replacement) return DPHooks[i].original;
    abort();
}

IMP DPDiaIMP(Class cls, SEL sel) {
    for (size_t i = 0; i < DPHookCount; i++)
        if (DPHooks[i].cls == cls && DPHooks[i].sel == sel) return DPHooks[i].original;
    return class_getMethodImplementation(cls, sel);
}
