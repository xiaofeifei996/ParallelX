#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <notify.h>
#import <dlfcn.h>
#import "PXSceneBridge.h"

static void (*PXOriginalSceneUpdate)(id, SEL, id, id, id);
static void (*PXOriginalSceneUpdateWithoutCompletion)(id, SEL, id, id);
static void (*PXOriginalKeyboardDidMove)(id, SEL);
static void (*PXOriginalKeyboardLayout)(id, SEL);
static void (*PXOriginalActivateApplication)(id, SEL, id, id, id, id, id);
static void (*PXOriginalSetOpenOptions)(id, SEL, id);
static BOOL PXDeviceLocked;

static id PXValue(id object, NSString *selectorName)
{
    SEL selector = NSSelectorFromString(selectorName);
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static void PXSetOpenOptions(id request, SEL selector, id options)
{
    id raw = PXValue(request, @"dictionary") ?: PXValue(options, @"dictionary");
    if (!raw && [options isKindOfClass:NSDictionary.class]) raw = options;
    NSDictionary *values = [raw isKindOfClass:NSDictionary.class] ? raw : nil;
    id target = PXValue(request, @"target");
    id identifier = PXValue(target ?: request, @"bundleIdentifier");
    NSString *bundleID = [identifier isKindOfClass:NSString.class] ? identifier : nil;
    NSString *origin = values[@"__LaunchOrigin"];
    BOOL notification = [origin isEqualToString:@"BulletinDestinationBanner"] ||
        [origin isEqualToString:@"BulletinDestinationCoverSheet"];
    BOOL link = values[@"__PayloadURL"] || values[@"__PayloadOpenURL"] ||
        values[@"__AppLink4LS"];
    if ((!notification && !link) || !bundleID.length) {
        PXOriginalSetOpenOptions(request, selector, options);
        return;
    }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.parallelx"];
    BOOL enabled = notification ? [defaults objectForKey:@"notificationSplitEnabled"] == nil ||
        [defaults boolForKey:@"notificationSplitEnabled"] :
        [defaults objectForKey:@"urlSplitEnabled"] == nil || [defaults boolForKey:@"urlSplitEnabled"];
    NSArray *excluded = [defaults stringArrayForKey:@"externalSplitExcluded"];
    BOOL eligible = enabled && !PXDeviceLocked && ![excluded containsObject:bundleID] &&
        ![bundleID isEqualToString:@"com.apple.springboard"] &&
        ![bundleID isEqualToString:@"com.apple.mobileslideshow"] &&
        ![bundleID isEqualToString:@"com.apple.ReplayKitNotifications"];
    NSString **key = dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyActivateSuspended");
    SEL setDictionary = NSSelectorFromString(@"setDictionary:");
    if (eligible && key && *key && [request respondsToSelector:setDictionary]) {
        NSMutableDictionary *updated = [values mutableCopy];
        updated[*key] = @YES;
        ((void (*)(id, SEL, id))objc_msgSend)(request, setDictionary, updated);
        SEL trust = NSSelectorFromString(@"setTrusted:");
        if ([request respondsToSelector:trust])
            ((void (*)(id, SEL, BOOL))objc_msgSend)(request, trust, YES);
    } else { eligible = NO; }
    PXOriginalSetOpenOptions(request, selector, options);
    if (eligible) {
        dispatch_async(dispatch_get_main_queue(), ^{
            Class entry = NSClassFromString(@"PXPanelEntry");
            SEL open = NSSelectorFromString(@"externalOpenApplication:");
            if ([entry respondsToSelector:open])
                ((void (*)(id, SEL, id))objc_msgSend)(entry, open, bundleID);
        });
    }
}

static void PXActivateApplication(id controller, SEL selector, id application, id icon,
                                  id location, id settings, id actions)
{
    PXOriginalActivateApplication(controller, selector, application, icon, location, settings, actions);
    SEL bundleSelector = NSSelectorFromString(@"bundleIdentifier");
    id bundleID = [application respondsToSelector:bundleSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(application, bundleSelector) : nil;
    Class entry = NSClassFromString(@"PXPanelEntry");
    SEL activated = NSSelectorFromString(@"applicationActivated:");
    if ([bundleID isKindOfClass:NSString.class] && [entry respondsToSelector:activated])
        ((void (*)(id, SEL, id))objc_msgSend)(entry, activated, bundleID);
}

static void PXKeyboardLayout(id view, SEL selector)
{
    PXOriginalKeyboardLayout(view, selector);
    [PXSceneBridge relocateAnyKeyboardView:view];
}

static void PXSceneUpdate(id scene, SEL selector, id settings, id context, id completion)
{
    id protected = nil;
    @try { protected = [PXSceneBridge protectedSettings:settings forAnyScene:scene]; }
    @catch (__unused NSException *exception) { }
    PXOriginalSceneUpdate(scene, selector, protected ?: settings, context, completion);
}

static void PXSceneUpdateWithoutCompletion(id scene, SEL selector, id settings, id context)
{
    id protected = nil;
    @try { protected = [PXSceneBridge protectedSettings:settings forAnyScene:scene]; }
    @catch (__unused NSException *exception) { }
    PXOriginalSceneUpdateWithoutCompletion(scene, selector, protected ?: settings, context);
}

static void PXKeyboardDidMove(id view, SEL selector)
{
    PXOriginalKeyboardDidMove(view, selector);
    __weak UIView *candidate = view;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *keyboard = candidate;
        if (keyboard) [PXSceneBridge relocateAnyKeyboardView:keyboard];
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
        Class ui = NSClassFromString(@"SBUIController");
        SEL activate = NSSelectorFromString(@"activateApplication:fromIcon:location:activationSettings:actions:");
        if (ui && class_getInstanceMethod(ui, activate))
            MSHookMessageEx(ui, activate, (IMP)PXActivateApplication,
                            (IMP *)&PXOriginalActivateApplication);
        Class openRequest = NSClassFromString(@"FBSystemServiceOpenApplicationRequest");
        SEL setOptions = NSSelectorFromString(@"setOptions:");
        if (openRequest && class_getInstanceMethod(openRequest, setOptions))
            MSHookMessageEx(openRequest, setOptions, (IMP)PXSetOpenOptions,
                            (IMP *)&PXOriginalSetOpenOptions);
        Class keyboard = NSClassFromString(@"_UIKeyboardLayerHostView");
        SEL didMove = @selector(didMoveToWindow);
        if (keyboard && class_getInstanceMethod(keyboard, didMove))
            MSHookMessageEx(keyboard, didMove, (IMP)PXKeyboardDidMove,
                            (IMP *)&PXOriginalKeyboardDidMove);
        if (keyboard && class_getInstanceMethod(keyboard, @selector(layoutSubviews)))
            MSHookMessageEx(keyboard, @selector(layoutSubviews), (IMP)PXKeyboardLayout,
                            (IMP *)&PXOriginalKeyboardLayout);
        static int lockToken;
        notify_register_dispatch("com.apple.springboard.lockstate", &lockToken,
            dispatch_get_main_queue(), ^(int token) {
                uint64_t state = 0;
                if (notify_get_state(token, &state) == NOTIFY_STATUS_OK) {
                    PXDeviceLocked = state != 0;
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"PXLockStateChanged"
                        object:nil userInfo:@{@"locked": @(state != 0)}];
                }
            });
        uint64_t initialLockState = 0;
        if (notify_get_state(lockToken, &initialLockState) == NOTIFY_STATUS_OK)
            PXDeviceLocked = initialLockState != 0;
        Class entry = NSClassFromString(@"PXPanelEntry");
        SEL start = NSSelectorFromString(@"start");
        if ([entry respondsToSelector:start])
            ((void (*)(id, SEL))objc_msgSend)(entry, start);
    });
}
