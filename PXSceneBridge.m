#import "PXSceneBridge.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <string.h>

static id PXCall(id object, NSString *name)
{
    SEL selector = NSSelectorFromString(name);
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static id PXIvar(id object, const char *name)
{
    if (!object) return nil;
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        Ivar ivar = class_getInstanceVariable(cls, name);
        if (ivar) return object_getIvar(object, ivar);
    }
    return nil;
}

static BOOL PXSetBool(id object, NSString *name, BOOL value)
{
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, value);
    return YES;
}

static BOOL PXSetFrame(id object, CGRect frame)
{
    SEL selector = NSSelectorFromString(@"setFrame:");
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3 ||
        strcmp([signature getArgumentTypeAtIndex:2], @encode(CGRect)) != 0) return NO;
    ((void (*)(id, SEL, CGRect))objc_msgSend)(object, selector, frame);
    return YES;
}

static CGRect PXFrame(id object)
{
    SEL selector = NSSelectorFromString(@"frame");
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    return signature && strcmp(signature.methodReturnType, @encode(CGRect)) == 0
        ? ((CGRect (*)(id, SEL))objc_msgSend)(object, selector) : CGRectZero;
}

static BOOL PXUpdateScene(id scene, id settings)
{
    SEL selector = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
    NSMethodSignature *signature = [scene methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 5) return NO;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(scene, selector, settings, nil, nil);
    return YES;
}

static void PXAppendViewGeometry(NSMutableString *log, UIView *view, NSString *label)
{
    [log appendFormat:@"%@ %@ frame=%@ bounds=%@ layer=%@\n", label,
        NSStringFromClass(view.class), NSStringFromCGRect(view.frame),
        NSStringFromCGRect(view.bounds), NSStringFromCGRect(view.layer.frame)];
    id sceneLayer = PXCall(view, @"sceneLayer");
    if ([sceneLayer isKindOfClass:CALayer.class])
        [log appendFormat:@"%@ sceneLayer=%@ bounds=%@\n", label,
            NSStringFromCGRect(((CALayer *)sceneLayer).frame),
            NSStringFromCGRect(((CALayer *)sceneLayer).bounds)];
}

static void PXWriteGeometry(id scene, UIView *canvas, UIView *host)
{
    NSMutableString *log = [NSMutableString stringWithFormat:
        @"scene=%@ screen=%@ window=%@ canvas=%@\n", NSStringFromCGRect(PXFrame(PXCall(scene, @"settings"))),
        NSStringFromCGRect(UIScreen.mainScreen.bounds), NSStringFromCGRect(canvas.window.frame),
        NSStringFromCGRect(canvas.bounds)];
    PXAppendViewGeometry(log, host, @"host");
    NSUInteger count = 0;
    for (UIView *child in host.subviews) {
        if (count++ == 12) break;
        PXAppendViewGeometry(log, child, @"child");
        for (UIView *grandchild in [child.subviews subarrayWithRange:NSMakeRange(0, MIN(child.subviews.count, 4))])
            PXAppendViewGeometry(log, grandchild, @"grandchild");
    }
    [log writeToFile:@"/var/mobile/Library/Preferences/com.moxuan.parallelx.scene.log"
          atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@interface PXSceneBridge ()
@property(nonatomic, strong) id scene;
@property(nonatomic, strong) UIView *hostView;
@property(nonatomic, strong) id presentationContext;
@property(nonatomic, weak) UIView *canvas;
@property(nonatomic, assign) CGRect originalSceneFrame;
@property(nonatomic, assign) NSUInteger generation;
@end

@implementation PXSceneBridge

+ (instancetype)sharedBridge
{
    static PXSceneBridge *bridge;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ bridge = [PXSceneBridge new]; });
    return bridge;
}

- (id)sceneForBundleID:(NSString *)bundleID
{
    id manager = PXCall(NSClassFromString(@"FBSceneManager"), @"sharedInstance");
    id workspace = PXIvar(manager, "_workspace") ?: PXCall(manager, @"workspace");
    id scenes = PXIvar(workspace, "_allScenesByID") ?: PXCall(workspace, @"allScenesByID");
    if (![scenes isKindOfClass:NSDictionary.class]) return nil;
    NSString *marker = [bundleID stringByAppendingString:@"-"];
    for (NSString *key in (NSDictionary *)scenes) {
        if (![key isKindOfClass:NSString.class] || ![key containsString:marker]) continue;
        id scene = scenes[key];
        if ([scene isKindOfClass:NSClassFromString(@"FBScene")]) return scene;
    }
    return nil;
}

- (BOOL)launchSuspended:(NSString *)bundleID
{
    id workspace = PXCall(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    SEL selector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    NSMethodSignature *signature = [workspace methodSignatureForSelector:selector];
    if (signature && signature.numberOfArguments == 4)
        return ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(workspace, selector, bundleID, YES);
    id springBoard = UIApplication.sharedApplication;
    signature = [springBoard methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments == 4 &&
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(springBoard, selector, bundleID, YES);
}

- (BOOL)foregroundScene:(id)scene inFrame:(CGRect)frame
{
    id settings = PXCall(scene, @"settings");
    id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
    if (!mutable || !PXSetBool(mutable, @"setBackgrounded:", NO)) return NO;
    PXSetBool(mutable, @"setForeground:", YES);
    PXSetBool(mutable, @"setAllowsSelection:", YES);
    if (!PXSetFrame(mutable, frame)) return NO;
    self.originalSceneFrame = PXFrame(settings);
    if (!PXUpdateScene(scene, mutable)) return NO;
    self.scene = scene;
    return YES;
}

- (NSArray *)mainLayersForScene:(id)scene
{
    id manager = PXCall(scene, @"layerManager");
    id layers = PXCall(manager, @"layers");
    if ([layers respondsToSelector:@selector(array)]) layers = [layers array];
    if (![layers isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *main = [NSMutableArray array];
    for (id layer in layers) {
        id external = PXCall(layer, @"externalSceneID");
        if (external) continue;
        SEL keyboard = NSSelectorFromString(@"isKeyboardLayer");
        if ([layer respondsToSelector:keyboard] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(layer, keyboard)) continue;
        [main addObject:layer];
    }
    return main;
}

- (void)openApplication:(NSString *)bundleID
                inView:(UIView *)canvas
            completion:(void (^)(BOOL))completion
{
    NSAssert(NSThread.isMainThread, @"ParallelX Scene access must be on the main thread");
    [self close];
    NSUInteger generation = self.generation;
    if (bundleID.length == 0 || !canvas || ![self launchSuspended:bundleID]) {
        completion(NO);
        return;
    }
    self.canvas = canvas;
    __weak typeof(self) weakSelf = self;
    __block NSUInteger attempts = 0;
    __block id preparedScene = nil;
    __block void (^retry)(void) = nil;
    retry = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.generation != generation || !strongSelf.canvas) {
            retry = nil;
            return;
        }
        @try {
            id scene = [strongSelf sceneForBundleID:bundleID];
            if (scene && scene != preparedScene &&
                [strongSelf foregroundScene:scene inFrame:strongSelf.canvas.bounds])
                preparedScene = scene;
            if (scene && scene == preparedScene) {
                NSArray *layers = [strongSelf mainLayersForScene:scene];
                Class hostClass = NSClassFromString(@"_UISceneLayerHostContainerView");
                Class contextClass = NSClassFromString(@"UIScenePresentationContext");
                SEL initializer = NSSelectorFromString(@"initWithScene:debugDescription:");
                SEL contextInitializer = NSSelectorFromString(@"_initWithDefaultValues");
                SEL bindContext = NSSelectorFromString(@"_setPresentationContext:");
                if (layers.count && [hostClass instancesRespondToSelector:initializer] &&
                    [hostClass instancesRespondToSelector:bindContext] &&
                    [contextClass instancesRespondToSelector:contextInitializer]) {
                    id context = ((id (*)(id, SEL))objc_msgSend)([contextClass alloc],
                                                                   contextInitializer);
                    if (context) {
                        id view = ((id (*)(id, SEL, id, id))objc_msgSend)([hostClass alloc],
                            initializer, scene, @"ParallelX");
                        if ([view isKindOfClass:UIView.class]) {
                            UIView *host = view;
                            SEL style = NSSelectorFromString(@"setAppearanceStyle:");
                            if ([context respondsToSelector:style])
                                ((void (*)(id, SEL, NSInteger))objc_msgSend)(context, style,
                                    UIScreen.mainScreen.traitCollection.userInterfaceStyle);
                            ((void (*)(id, SEL, id))objc_msgSend)(host, bindContext, context);
                            host.frame = strongSelf.canvas.bounds;
                            host.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                                    UIViewAutoresizingFlexibleHeight;
                            [strongSelf.canvas addSubview:host];
                            strongSelf.presentationContext = context;
                            strongSelf.hostView = host;
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                                           dispatch_get_main_queue(), ^{
                                if (strongSelf.generation == generation && strongSelf.canvas)
                                    PXWriteGeometry(scene, strongSelf.canvas, host);
                            });
                            completion(YES);
                            retry = nil;
                            return;
                        }
                    }
                }
            }
        } @catch (__unused NSException *exception) {
            // Private interfaces vary; fail closed instead of crashing SpringBoard.
        }
        if (++attempts >= 24) {
            [strongSelf close];
            completion(NO);
            retry = nil;
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 125 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), retry);
    };
    dispatch_async(dispatch_get_main_queue(), retry);
}

- (void)close
{
    NSAssert(NSThread.isMainThread, @"ParallelX Scene access must be on the main thread");
    self.generation += 1;
    UIView *host = self.hostView;
    id scene = self.scene;
    CGRect originalFrame = self.originalSceneFrame;
    self.hostView = nil;
    self.scene = nil;
    self.canvas = nil;
    self.originalSceneFrame = CGRectZero;
    SEL invalidate = NSSelectorFromString(@"invalidate");
    for (UIView *child in [host.subviews copy]) {
        if ([child respondsToSelector:invalidate])
            ((void (*)(id, SEL))objc_msgSend)(child, invalidate);
    }
    if ([host respondsToSelector:invalidate])
        ((void (*)(id, SEL))objc_msgSend)(host, invalidate);
    [host removeFromSuperview];
    self.presentationContext = nil;
    if (scene && !CGRectIsEmpty(originalFrame)) {
        id settings = PXCall(scene, @"settings");
        id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
        if (PXSetFrame(mutable, originalFrame)) PXUpdateScene(scene, mutable);
    }
}

@end
