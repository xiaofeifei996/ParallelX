#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <notify.h>
#import <dlfcn.h>
#import <QuartzCore/QuartzCore.h>
#import "PXSceneBridge.h"

static void (*PXOriginalSceneUpdate)(id, SEL, id, id, id);
static void (*PXOriginalSceneUpdateWithoutCompletion)(id, SEL, id, id);
static void (*PXOriginalKeyboardDidMove)(id, SEL);
static void (*PXOriginalKeyboardLayout)(id, SEL);
static void (*PXOriginalActivateApplication)(id, SEL, id, id, id, id, id);
static void (*PXOriginalFrontDisplayDidChange)(id, SEL, id);
static void (*PXOriginalOrientationChanged)(id, SEL, NSInteger, double, BOOL, BOOL, id);
static void (*PXOriginalActiveOrientationChanged)(id, SEL, BOOL);
static void (*PXOriginalHandleOpenRequest)(id, SEL, id, id, id);
static void (*PXOriginalHandleTrustedOpen)(id, SEL, id, id, id, id, id);
static BOOL (*PXOriginalExecuteTransition)(id, SEL, id);
static id (*PXOriginalFluidAnimationInit)(id, SEL, id, id, id);
static char PXHomeHandoffRequestKey;
static void (*PXOriginalAnimationStart)(id, SEL);
static NSUInteger PXTransitionProbeSamples;

static void PXTransitionProbeWrite(NSString *message)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.moxuan.parallelx.transition-probe", DISPATCH_QUEUE_SERIAL); });
    NSString *line = [NSString stringWithFormat:@"%.3f %@\n", CFAbsoluteTimeGetCurrent(), message];
    dispatch_async(queue, ^{
        @try {
            NSString *directory = @"/var/mobile/Library/Logs";
            NSString *path = [directory stringByAppendingPathComponent:@"com.moxuan.parallelx.transition.log"];
            NSFileManager *manager = NSFileManager.defaultManager;
            [manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
            if (![manager fileExistsAtPath:path] ||
                [[manager attributesOfItemAtPath:path error:nil] fileSize] > 1024 * 1024)
                [manager createFileAtPath:path contents:nil attributes:nil];
            NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
            [file seekToEndOfFile];
            [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [file closeFile];
        } @catch (__unused NSException *exception) { }
    });
}

static void PXTransitionProbeLayer(CALayer *layer, NSMutableString *output,
                                   NSUInteger depth, NSUInteger *remaining)
{
    if (!layer || depth > 8 || !*remaining) return;
    --*remaining;
    CALayer *presentation = layer.presentationLayer;
    [output appendFormat:@"\n%lu %p %@ delegate=%@ frame=%@ presented=%@ hidden=%d opacity=%.2f presentedOpacity=%.2f contents=%d animations=%@",
        (unsigned long)depth, layer, NSStringFromClass(layer.class),
        layer.delegate ? NSStringFromClass([layer.delegate class]) : @"nil",
        NSStringFromCGRect(layer.frame), presentation ? NSStringFromCGRect(presentation.frame) : @"nil",
        layer.hidden, layer.opacity, presentation ? presentation.opacity : layer.opacity,
        layer.contents != nil, layer.animationKeys ?: @[]];
    for (CALayer *child in layer.sublayers) PXTransitionProbeLayer(child, output, depth + 1, remaining);
}
static void (*PXOriginalSetStyleMode)(id, SEL, NSInteger);
static CFAbsoluteTime PXAppearanceChangeUntil;

static void PXSetStyleMode(id mode, SEL selector, NSInteger value)
{
    Class entry = NSClassFromString(@"PXPanelEntry");
    SEL visible = NSSelectorFromString(@"hasVisibleHost");
    if ([entry respondsToSelector:visible] && ((BOOL (*)(id, SEL))objc_msgSend)(entry, visible))
        PXAppearanceChangeUntil = CFAbsoluteTimeGetCurrent() + 1.0;
    PXOriginalSetStyleMode(mode, selector, value);
}
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

static void PXTransitionProbeCapture(id controller, NSUInteger sample, NSString *phase)
{
    if (!NSThread.isMainThread || !controller) return;
    @try {
        id provider = PXValue(controller, @"transitionContextProvider");
        NSMutableString *output = [NSMutableString stringWithFormat:@"sample=%lu phase=%@ controller=%@ %p provider=%@ %p handoff=%d orientation=%ld screen=%@",
            (unsigned long)sample, phase, NSStringFromClass([controller class]), controller,
            NSStringFromClass([provider class]), provider,
            [objc_getAssociatedObject(provider, &PXHomeHandoffRequestKey) boolValue],
            (long)[PXSceneBridge systemOrientation], NSStringFromCGRect(UIScreen.mainScreen.bounds)];
        UIView *container = PXValue(controller, @"containerView");
        if ([container isKindOfClass:UIView.class]) {
            [output appendFormat:@"\ncontainer=%@ window=%@ level=%.1f", NSStringFromClass(container.class),
                NSStringFromClass(container.window.class), container.window.windowLevel];
            NSUInteger remaining = 100;
            PXTransitionProbeLayer(container.layer, output, 0, &remaining);
        }
        id switcher = PXValue(NSClassFromString(@"SBMainSwitcherViewController"), @"sharedInstance");
        if ([switcher isKindOfClass:UIViewController.class] && [switcher isViewLoaded]) {
            [output appendString:@"\nswitcher:"];
            NSUInteger remaining = 100;
            PXTransitionProbeLayer([(UIViewController *)switcher view].layer, output, 0, &remaining);
        }
        PXTransitionProbeWrite(output);
    } @catch (__unused NSException *exception) {
        PXTransitionProbeWrite(@"capture failed safely");
    }
}

static void PXAnimationStart(id controller, SEL selector)
{
    PXOriginalAnimationStart(controller, selector);
    // Temporary probe: at most 12 departures to Home, three samples each.
    // No screen content/text is read and file writes stay off the UI thread.
    if (!NSThread.isMainThread || PXTransitionProbeSamples >= 12) return;
    id request = PXValue(controller, @"transitionContextProvider");
    id from = PXValue(request, @"fromApplicationSceneEntities");
    id to = PXValue(request, @"toApplicationSceneEntities");
    if (![from respondsToSelector:@selector(count)] || ![to respondsToSelector:@selector(count)] ||
        [from count] == 0 || [to count] != 0) return;
    NSUInteger sample = ++PXTransitionProbeSamples;
    PXTransitionProbeCapture(controller, sample, @"start");
    __weak id weakController = controller;
    for (NSNumber *delay in @[@0.08, @0.22]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PXTransitionProbeCapture(weakController, sample, delay.stringValue);
        });
    }
}

static BOOL PXExecuteTransition(id workspace, SEL selector, id request)
{
    id context = PXValue(request, @"applicationContext");
    id from = PXValue(request, @"fromApplicationSceneEntities");
    id to = PXValue(request, @"toApplicationSceneEntities");
    SEL disable = NSSelectorFromString(@"setAnimationDisabled:");
    // Match only this app's departure to Home, after the request is prepared.
    if ([context respondsToSelector:disable] && [to respondsToSelector:@selector(count)] &&
        [to count] == 0 && [from conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id entity in from) {
            id bundleID = PXValue(PXValue(entity, @"application"), @"bundleIdentifier");
            if ([bundleID isKindOfClass:NSString.class] &&
                [PXSceneBridge consumeHomeHandoffForBundleID:bundleID]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(context, disable, YES);
                objc_setAssociatedObject(request, &PXHomeHandoffRequestKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                break;
            }
        }
    }
    static NSUInteger recordedRequests;
    if (NSThread.isMainThread && recordedRequests < 24 &&
        [to respondsToSelector:@selector(count)] && [to count] == 0) {
        ++recordedRequests;
        PXTransitionProbeWrite([NSString stringWithFormat:@"request=%@ %p context=%@ from=%lu to=0 handoff=%d",
            NSStringFromClass([request class]), request, NSStringFromClass([context class]),
            [from respondsToSelector:@selector(count)] ? (unsigned long)[from count] : 0,
            [objc_getAssociatedObject(request, &PXHomeHandoffRequestKey) boolValue]]);
    }
    return PXOriginalExecuteTransition(workspace, selector, request);
}

static id PXFluidAnimationInit(id controller, SEL selector, id request, id settings, id block)
{
    // The fluid switcher receives its own settings, independently of the
    // application context's animationDisabled flag. Only replace our Home
    // handoff's settings; keep the animation block and system cleanup intact.
    if ([objc_getAssociatedObject(request, &PXHomeHandoffRequestKey) boolValue]) {
        Class animation = NSClassFromString(@"BSAnimationSettings");
        SEL zero = NSSelectorFromString(@"settingsWithDuration:");
        if ([animation respondsToSelector:zero]) {
            id immediate = ((id (*)(id, SEL, double))objc_msgSend)(animation, zero, 0);
            if (immediate) settings = immediate;
        }
    }
    id result = PXOriginalFluidAnimationInit(controller, selector, request, settings, block);
    static NSUInteger recordedInitializers;
    if (NSThread.isMainThread && recordedInitializers < 24) {
        ++recordedInitializers;
        PXTransitionProbeWrite([NSString stringWithFormat:@"fluid-init controller=%p request=%p settings=%@ handoff=%d",
            result, request, NSStringFromClass([settings class]),
            [objc_getAssociatedObject(request, &PXHomeHandoffRequestKey) boolValue]]);
    }
    return result;
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
    NSArray *excluded = !notification && link ? [defaults stringArrayForKey:@"urlSplitExcluded"] : nil;
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

static void PXDismissOpenedNotificationBanner(id options)
{
    // Only an accepted banner tap, never a URL launch or an unrelated notification.
    if (![PXOptionsDictionary(options)[@"__LaunchOrigin"] isEqual:@"BulletinDestinationBanner"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            id dispatcher = PXValue(UIApplication.sharedApplication, @"notificationDispatcher");
            id destination = PXValue(dispatcher, @"bannerDestination");
            SEL dismiss = NSSelectorFromString(@"_dismissPresentedBannerOnly:reason:animated:forceIfSticky:");
            if ([destination respondsToSelector:dismiss]) {
                ((void (*)(id, SEL, BOOL, id, BOOL, BOOL))objc_msgSend)(destination, dismiss,
                    YES, @"ParallelXNotificationOpen", NO, YES);
                return;
            }
            id controller = PXValue(NSClassFromString(@"SBBannerController"), @"sharedInstance");
            SEL fallback = NSSelectorFromString(@"dismissBannerWithAnimation:reason:forceEvenIfBusy:");
            if ([controller respondsToSelector:fallback])
                ((void (*)(id, SEL, BOOL, long long, BOOL))objc_msgSend)(controller, fallback, NO, 0, YES);
        } @catch (__unused NSException *exception) { }
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
    if (route) {
        PXRememberRoute(bundleID);
        PXDismissOpenedNotificationBanner(options);
    }
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
    if (route) {
        PXRememberRoute(bundleID);
        PXDismissOpenedNotificationBanner(options);
    }
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

static void PXFrontDisplayDidChange(id springBoard, SEL selector, id application)
{
    PXOriginalFrontDisplayDidChange(springBoard, selector, application);
    NSString *bundleID = PXBundleID(application);
    Class entry = NSClassFromString(@"PXPanelEntry");
    SEL changed = NSSelectorFromString(@"frontDisplayChanged:");
    if ([entry respondsToSelector:changed])
        ((void (*)(id, SEL, id))objc_msgSend)(entry, changed, bundleID);
}

static void PXOrientationChanged(id manager, SEL selector, NSInteger orientation,
                                 double duration, BOOL mirrored, BOOL force, id message)
{
    PXOriginalOrientationChanged(manager, selector, orientation, duration, mirrored, force, message);
    [PXSceneBridge noteSystemOrientation:(UIInterfaceOrientation)orientation];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:@"PXScreenGeometryChanged" object:nil];
    });
}

static void PXActiveOrientationChanged(id application, SEL selector, BOOL animated)
{
    PXOriginalActiveOrientationChanged(application, selector, animated);
    dispatch_async(dispatch_get_main_queue(), ^{
        SEL active = NSSelectorFromString(@"activeInterfaceOrientation");
        if ([application respondsToSelector:active])
            [PXSceneBridge noteSystemOrientation:((NSInteger (*)(id, SEL))objc_msgSend)(application, active)];
        [NSNotificationCenter.defaultCenter postNotificationName:@"PXScreenGeometryChanged" object:nil];
    });
}

static void PXKeyboardLayout(id view, SEL selector)
{
    PXOriginalKeyboardLayout(view, selector);
    [PXSceneBridge relocateAnyKeyboardView:view];
}

static id PXHostedAppearanceContext(id context, BOOL hosted)
{
    if (!hosted || !context || CFAbsoluteTimeGetCurrent() > PXAppearanceChangeUntil) return context;
    Class settingsClass = NSClassFromString(@"BSAnimationSettings");
    SEL zeroDuration = NSSelectorFromString(@"settingsWithDuration:");
    SEL setAnimation = NSSelectorFromString(@"setAnimationSettings:");
    if (![settingsClass respondsToSelector:zeroDuration] ||
        ![context respondsToSelector:@selector(mutableCopy)] ||
        ![context respondsToSelector:setAnimation])
        return context;
    @try {
        id copy = [context mutableCopy];
        id settings = ((id (*)(id, SEL, double))objc_msgSend)(settingsClass, zeroDuration, 0);
        if (!copy || !settings) return context;
        ((void (*)(id, SEL, id))objc_msgSend)(copy, setAnimation, settings);
        return copy;
    } @catch (__unused NSException *exception) { return context; }
}

static void PXSceneUpdate(id scene, SEL selector, id settings, id context, id completion)
{
    id protected = nil;
    @try { protected = [PXSceneBridge protectedSettings:settings forAnyScene:scene]; }
    @catch (__unused NSException *exception) { }
    PXOriginalSceneUpdate(scene, selector, protected ?: settings,
                          PXHostedAppearanceContext(context, protected != nil), completion);
}

static void PXSceneUpdateWithoutCompletion(id scene, SEL selector, id settings, id context)
{
    id protected = nil;
    @try { protected = [PXSceneBridge protectedSettings:settings forAnyScene:scene]; }
    @catch (__unused NSException *exception) { }
    PXOriginalSceneUpdateWithoutCompletion(scene, selector, protected ?: settings,
                                           PXHostedAppearanceContext(context, protected != nil));
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
        Class styleMode = NSClassFromString(@"UISUserInterfaceStyleMode");
        if (class_getInstanceMethod(styleMode, @selector(setModeValue:)))
            MSHookMessageEx(styleMode, @selector(setModeValue:), (IMP)PXSetStyleMode,
                            (IMP *)&PXOriginalSetStyleMode);
        Class ui = NSClassFromString(@"SBUIController");
        SEL activate = NSSelectorFromString(@"activateApplication:fromIcon:location:activationSettings:actions:");
        if (ui && class_getInstanceMethod(ui, activate))
            MSHookMessageEx(ui, activate, (IMP)PXActivateApplication,
                            (IMP *)&PXOriginalActivateApplication);
        Class springBoard = NSClassFromString(@"SpringBoard");
        SEL orientation = NSSelectorFromString(@"noteInterfaceOrientationChanged:duration:updateMirroredDisplays:force:logMessage:");
        Method rotation = class_getInstanceMethod(springBoard, orientation);
        if (rotation && method_getNumberOfArguments(rotation) == 7)
            MSHookMessageEx(springBoard, orientation, (IMP)PXOrientationChanged,
                            (IMP *)&PXOriginalOrientationChanged);
        else {
            SEL active = NSSelectorFromString(@"_postActiveInterfaceOrientationChangedNotificationAnimated:");
            Method changed = class_getInstanceMethod(springBoard, active);
            if (changed && method_getNumberOfArguments(changed) == 3)
                MSHookMessageEx(springBoard, active, (IMP)PXActiveOrientationChanged,
                                (IMP *)&PXOriginalActiveOrientationChanged);
        }
        SEL frontDisplay = NSSelectorFromString(@"frontDisplayDidChange:");
        if (springBoard && class_getInstanceMethod(springBoard, frontDisplay))
            MSHookMessageEx(springBoard, frontDisplay, (IMP)PXFrontDisplayDidChange,
                            (IMP *)&PXOriginalFrontDisplayDidChange);
        Class workspace = NSClassFromString(@"SBMainWorkspace");
        SEL execute = NSSelectorFromString(@"_executeApplicationTransitionRequest:");
        Method execution = class_getInstanceMethod(workspace, execute);
        char result[8] = {0};
        if (execution) method_getReturnType(execution, result, sizeof(result));
        if (execution && method_getNumberOfArguments(execution) == 3 &&
            (result[0] == 'B' || result[0] == 'c'))
            MSHookMessageEx(workspace, execute, (IMP)PXExecuteTransition,
                            (IMP *)&PXOriginalExecuteTransition);
        Class fluid = NSClassFromString(@"SBFluidSwitcherAnimationController");
        SEL fluidInit = NSSelectorFromString(@"initWithWorkspaceTransitionRequest:animationSettings:animationBlock:");
        Method initializer = class_getInstanceMethod(fluid, fluidInit);
        char initResult[8] = {0};
        if (initializer) method_getReturnType(initializer, initResult, sizeof(initResult));
        if (initializer && method_getNumberOfArguments(initializer) == 5 && initResult[0] == '@')
            MSHookMessageEx(fluid, fluidInit, (IMP)PXFluidAnimationInit,
                            (IMP *)&PXOriginalFluidAnimationInit);
        Class animationController = NSClassFromString(@"SBUIAnimationController");
        SEL startAnimation = NSSelectorFromString(@"__startAnimation");
        Method animationStartMethod = class_getInstanceMethod(animationController, startAnimation);
        char startResult[8] = {0};
        if (animationStartMethod) method_getReturnType(animationStartMethod, startResult, sizeof(startResult));
        BOOL probeInstalled = animationStartMethod && method_getNumberOfArguments(animationStartMethod) == 2 && startResult[0] == 'v';
        if (probeInstalled)
            MSHookMessageEx(animationController, startAnimation, (IMP)PXAnimationStart,
                            (IMP *)&PXOriginalAnimationStart);
        PXTransitionProbeWrite([NSString stringWithFormat:@"alpha101 probe ready animationStart=%d fluid=%d",
            probeInstalled, initializer != NULL]);
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
        static int captureToken;
        notify_register_dispatch("com.moxuan.parallelx.capture-updated", &captureToken,
            dispatch_get_main_queue(), ^(__unused int token) {
                SEL refresh = NSSelectorFromString(@"updateCaptureVisibility");
                if ([entry respondsToSelector:refresh])
                    ((void (*)(id, SEL))objc_msgSend)(entry, refresh);
            });
        SEL start = NSSelectorFromString(@"start");
        if ([entry respondsToSelector:start])
            ((void (*)(id, SEL))objc_msgSend)(entry, start);
    });
}
