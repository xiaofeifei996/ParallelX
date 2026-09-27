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
static void (*PXOriginalHandleOpenRequest)(id, SEL, id, id, id);
static void (*PXOriginalHandleTrustedOpen)(id, SEL, id, id, id, id, id);
static BOOL PXDeviceLocked;
static NSString *PXRecentExternalBundleID;
static CFAbsoluteTime PXRecentExternalTime;

static id PXValue(id object, NSString *selectorName)
{
    SEL selector = NSSelectorFromString(selectorName);
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static NSDictionary *PXOptionsDictionary(id options)
{
    id values = [options isKindOfClass:NSDictionary.class] ? options : PXValue(options, @"dictionary");
    return [values isKindOfClass:NSDictionary.class] ? values : nil;
}

static NSString *PXBundleID(id object)
{
    if ([object isKindOfClass:NSString.class]) return object;
    id value = PXValue(object, @"bundleIdentifier");
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSString *PXRequestBundleID(id request)
{
    for (NSString *selector in @[@"bundleIdentifier", @"targetBundleIdentifier",
                                @"applicationBundleIdentifier", @"applicationIdentifier",
                                @"application", @"targetApplication", @"target"]) {
        NSString *bundleID = PXBundleID(PXValue(request, selector));
        if (bundleID.length) return bundleID;
    }
    return nil;
}

static NSString *PXSuspendedKey(void)
{
    static NSString *key;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *symbol = dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyActivateSuspended");
        id value = symbol ? *(__unsafe_unretained id *)symbol : nil;
        if ([value isKindOfClass:NSString.class]) key = value;
    });
    return key;
}

static NSString *PXSourceBundleID(id source, NSDictionary *values)
{
    NSString *bundleID = PXBundleID(source);
    if (!bundleID.length) bundleID = PXBundleID(PXValue(source, @"clientProcess"));
    if (!bundleID.length) bundleID = PXBundleID(PXValue(source, @"process"));
    if (bundleID.length && ![bundleID hasPrefix:@"com.apple."]) return bundleID;
    void *symbol = dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyPayloadOptions");
    id key = symbol ? *(__unsafe_unretained id *)symbol : nil;
    id payload = [key isKindOfClass:NSString.class] ? values[key] : nil;
    NSString *payloadID = [payload isKindOfClass:NSDictionary.class]
        ? PXBundleID(payload[UIApplicationLaunchOptionsSourceApplicationKey]) : nil;
    return payloadID ?: PXBundleID(values[UIApplicationLaunchOptionsSourceApplicationKey]) ?: bundleID;
}

static BOOL PXExternalTarget(id options, id target, id source, NSString **bundleOut)
{
    NSDictionary *values = PXOptionsDictionary(options);
    NSString *bundleID = PXBundleID(target);
    if (!values || !bundleID.length || PXDeviceLocked || !PXSuspendedKey().length) return NO;
    NSString *origin = values[@"__LaunchOrigin"];
    BOOL notification = [origin isEqualToString:@"BulletinDestinationBanner"] ||
        [origin isEqualToString:@"BulletinDestinationCoverSheet"];
    id url = PXValue(options, @"url") ?: values[@"__PayloadURL"] ?: values[@"__PayloadOpenURL"];
    NSString *sourceID = PXSourceBundleID(source, values);
    BOOL link = ([url isKindOfClass:NSURL.class] || [url isKindOfClass:NSString.class]) &&
        sourceID.length && ![sourceID isEqualToString:bundleID] &&
        ![sourceID isEqualToString:@"com.apple.springboard"];
    if (!notification && !link) return NO;
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.parallelx"];
    BOOL enabled = notification ? [defaults objectForKey:@"notificationSplitEnabled"] == nil ||
        [defaults boolForKey:@"notificationSplitEnabled"] :
        [defaults objectForKey:@"urlSplitEnabled"] == nil || [defaults boolForKey:@"urlSplitEnabled"];
    NSArray *excluded = [defaults stringArrayForKey:@"externalSplitExcluded"];
    BOOL eligible = enabled && ![excluded containsObject:bundleID] &&
        ![bundleID isEqualToString:@"com.apple.springboard"] &&
        ![bundleID isEqualToString:@"com.apple.mobileslideshow"] &&
        ![bundleID isEqualToString:@"com.apple.ReplayKitNotifications"];
    id appController = PXValue(NSClassFromString(@"SBApplicationController"), @"sharedInstance");
    SEL lookup = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    id app = [appController respondsToSelector:lookup]
        ? ((id (*)(id, SEL, id))objc_msgSend)(appController, lookup, bundleID) : nil;
    if (!eligible || !app) return NO;
    id info = PXValue(app, @"info");
    if ([info respondsToSelector:NSSelectorFromString(@"hasHiddenTag")] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(info, NSSelectorFromString(@"hasHiddenTag"))) return NO;
    if (bundleOut) *bundleOut = bundleID;
    return YES;
}

static id PXOptionsWithSuspendedLaunch(id options)
{
    NSDictionary *values = PXOptionsDictionary(options);
    SEL setDictionary = NSSelectorFromString(@"setDictionary:");
    if (!values) return nil;
    NSMutableDictionary *updated = [values mutableCopy];
    updated[PXSuspendedKey()] = @YES;
    if ([options isKindOfClass:NSDictionary.class]) return updated;
    if (![options respondsToSelector:setDictionary]) return nil;
    ((void (*)(id, SEL, id))objc_msgSend)(options, setDictionary, updated);
    return options;
}

static void PXExternalOpen(NSString *bundleID)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        Class entry = NSClassFromString(@"PXPanelEntry");
        SEL open = NSSelectorFromString(@"externalOpenApplication:");
        if ([entry respondsToSelector:open])
            ((void (*)(id, SEL, id))objc_msgSend)(entry, open, bundleID);
    });
}

static BOOL PXRouteRecentlyHandled(NSString *bundleID)
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    return [PXRecentExternalBundleID isEqualToString:bundleID] && now - PXRecentExternalTime < 1;
}

static void PXRememberRoute(NSString *bundleID)
{
    PXRecentExternalBundleID = [bundleID copy];
    PXRecentExternalTime = CFAbsoluteTimeGetCurrent();
}

static void PXHandleOpenRequest(id workspace, SEL selector, id service, id request, id completion)
{
    id options = PXValue(request, @"options");
    NSString *bundleID = nil;
    id source = PXValue(request, @"clientProcess");
    BOOL route = PXExternalTarget(options, PXRequestBundleID(request), source, &bundleID) &&
        !PXRouteRecentlyHandled(bundleID) && PXOptionsWithSuspendedLaunch(options) != nil;
    if (route) PXRememberRoute(bundleID);
    id routed = completion;
    if (route) {
        void (^original)(NSError *) = completion;
        routed = [^(NSError *error) {
            if (original) original(error);
            if (!error) PXExternalOpen(bundleID);
        } copy];
    }
    PXOriginalHandleOpenRequest(workspace, selector, service, request, routed);
}

static void PXHandleTrustedOpen(id workspace, SEL selector, id application, id options,
                                id settings, id origin, id result)
{
    NSString *bundleID = nil;
    BOOL candidate = PXExternalTarget(options, application, origin, &bundleID) &&
        !PXRouteRecentlyHandled(bundleID);
    id prepared = candidate ? PXOptionsWithSuspendedLaunch(options) : nil;
    BOOL route = prepared != nil;
    if (route) PXRememberRoute(bundleID);
    id routed = result;
    if (route) {
        void (^original)(NSError *) = result;
        routed = [^(NSError *error) {
            if (original) original(error);
            if (!error) PXExternalOpen(bundleID);
        } copy];
    }
    PXOriginalHandleTrustedOpen(workspace, selector, application, prepared ?: options,
                                settings, origin, routed);
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
        Class workspace = NSClassFromString(@"SBMainWorkspace");
        SEL openRequest = NSSelectorFromString(@"systemService:handleOpenApplicationRequest:withCompletion:");
        if (workspace && class_getInstanceMethod(workspace, openRequest))
            MSHookMessageEx(workspace, openRequest, (IMP)PXHandleOpenRequest,
                            (IMP *)&PXOriginalHandleOpenRequest);
        SEL trustedOpen = NSSelectorFromString(@"_handleTrustedOpenRequestForApplication:options:activationSettings:origin:withResult:");
        if (workspace && class_getInstanceMethod(workspace, trustedOpen))
            MSHookMessageEx(workspace, trustedOpen, (IMP)PXHandleTrustedOpen,
                            (IMP *)&PXOriginalHandleTrustedOpen);
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
