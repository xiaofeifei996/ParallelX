#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "PXSceneBridge.h"

static void (*PXOriginalSceneUpdate)(id, SEL, id, id, id);
static void (*PXOriginalSceneUpdateWithoutCompletion)(id, SEL, id, id);
static void (*PXOriginalKeyboardDidMove)(id, SEL);

static void PXSceneUpdate(id scene, SEL selector, id settings, id context, id completion)
{
    id protected = nil;
    @try { protected = [[PXSceneBridge sharedBridge] protectedSettings:settings forScene:scene]; }
    @catch (__unused NSException *exception) { }
    PXOriginalSceneUpdate(scene, selector, protected ?: settings, context, completion);
}

static void PXSceneUpdateWithoutCompletion(id scene, SEL selector, id settings, id context)
{
    id protected = nil;
    @try { protected = [[PXSceneBridge sharedBridge] protectedSettings:settings forScene:scene]; }
    @catch (__unused NSException *exception) { }
    PXOriginalSceneUpdateWithoutCompletion(scene, selector, protected ?: settings, context);
}

static void PXKeyboardDidMove(id view, SEL selector)
{
    PXOriginalKeyboardDidMove(view, selector);
    __weak UIView *candidate = view;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *keyboard = candidate;
        if (keyboard) [[PXSceneBridge sharedBridge] relocateKeyboardView:keyboard];
    });
}

__attribute__((constructor)) static void PXInitialize(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        Class scene = NSClassFromString(@"FBScene");
        SEL update = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
        SEL updateShort = NSSelectorFromString(@"updateSettings:withTransitionContext:");
        if (scene && class_getInstanceMethod(scene, update))
            MSHookMessageEx(scene, update, (IMP)PXSceneUpdate, (IMP *)&PXOriginalSceneUpdate);
        if (scene && class_getInstanceMethod(scene, updateShort))
            MSHookMessageEx(scene, updateShort, (IMP)PXSceneUpdateWithoutCompletion,
                            (IMP *)&PXOriginalSceneUpdateWithoutCompletion);
        Class keyboard = NSClassFromString(@"_UIKeyboardLayerHostView");
        SEL didMove = @selector(didMoveToWindow);
        if (keyboard && class_getInstanceMethod(keyboard, didMove))
            MSHookMessageEx(keyboard, didMove, (IMP)PXKeyboardDidMove,
                            (IMP *)&PXOriginalKeyboardDidMove);
        Class entry = NSClassFromString(@"PXPanelEntry");
        SEL start = NSSelectorFromString(@"start");
        if ([entry respondsToSelector:start])
            ((void (*)(id, SEL))objc_msgSend)(entry, start);
    });
}
