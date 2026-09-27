#import "PXSceneBridge.h"
#import <objc/message.h>
#import <objc/runtime.h>
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

static CGRect PXRect(id object, NSString *name)
{
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    return signature && strcmp(signature.methodReturnType, @encode(CGRect)) == 0
        ? ((CGRect (*)(id, SEL))objc_msgSend)(object, selector) : CGRectZero;
}

static BOOL PXSetSceneFrame(id settings, CGSize size)
{
    SEL selector = NSSelectorFromString(@"setFrame:");
    NSMethodSignature *signature = [settings methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3 ||
        strcmp([signature getArgumentTypeAtIndex:2], @encode(CGRect)) != 0) return NO;
    ((void (*)(id, SEL, CGRect))objc_msgSend)(settings, selector,
        (CGRect){CGPointZero, size});
    return YES;
}

static CGSize PXSourceSize(id settings)
{
    // The server frame can retain a stale floating size. The display is the
    // canonical full-screen source that every hosted app renders into.
    CGSize size = PXRect(PXCall(settings, @"displayConfiguration"), @"bounds").size;
    if (size.width <= 0 || size.height <= 0)
        size = UIScreen.mainScreen.bounds.size;
    CGRect sceneFrame = PXRect(settings, @"frame");
    if (sceneFrame.size.width > sceneFrame.size.height && size.width < size.height)
        size = CGSizeMake(size.height, size.width);
    return size;
}

static BOOL PXUpdateScene(id scene, id settings)
{
    SEL selector = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
    NSMethodSignature *signature = [scene methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 5) return NO;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(scene, selector, settings, nil, nil);
    return YES;
}

@interface PXSceneBridge ()
@property(nonatomic, strong) id scene;
@property(nonatomic, strong) UIView *hostView;
@property(nonatomic, strong) id presentationContext;
@property(nonatomic, weak) UIView *canvas;
@property(nonatomic, assign) CGSize sourceSize;
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

- (BOOL)openFullscreenApplication:(NSString *)bundleID
{
    if (bundleID.length == 0) return NO;
    SEL selector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    id springBoard = UIApplication.sharedApplication;
    NSMethodSignature *signature = [springBoard methodSignatureForSelector:selector];
    if (signature && signature.numberOfArguments == 4 &&
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(springBoard, selector, bundleID, NO))
        return YES;
    id workspace = PXCall(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    signature = [workspace methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments == 4 &&
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(workspace, selector, bundleID, NO);
}

- (void)prepareWindowForBundleID:(NSString *)bundleID
                      completion:(dispatch_block_t)completion
{
    if (!completion) return;
    dispatch_block_t finish = ^{
        if (NSThread.isMainThread) completion();
        else dispatch_async(dispatch_get_main_queue(), completion);
    };
    id frontmost = PXCall(UIApplication.sharedApplication,
                          @"_accessibilityFrontMostApplication");
    NSString *currentID = PXCall(frontmost, @"bundleIdentifier");
    if (![currentID isKindOfClass:NSString.class] ||
        ![currentID isEqualToString:bundleID]) {
        finish();
        return;
    }
    id controller = PXCall(NSClassFromString(@"SBUIController"), @"sharedInstance");
    SEL selector = NSSelectorFromString(@"_returnToHomeScreenWithCompletion:");
    NSMethodSignature *signature = [controller methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3 ||
        signature.methodReturnType[0] != 'v' ||
        [signature getArgumentTypeAtIndex:2][0] != '@') {
        finish();
        return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, [finish copy]);
}

- (void)layoutHost
{
    UIView *host = self.hostView;
    UIView *canvas = self.canvas;
    CGSize source = self.sourceSize;
    CGSize target = canvas.bounds.size;
    if (!host || !canvas || source.width <= 0 || source.height <= 0 ||
        target.width <= 0 || target.height <= 0) return;
    CGFloat scale = MIN(target.width / source.width, target.height / source.height);
    host.transform = CGAffineTransformIdentity;
    host.bounds = (CGRect){CGPointZero, source};
    host.center = CGPointMake(target.width / 2, target.height / 2);
    host.transform = CGAffineTransformMakeScale(scale, scale);
}

- (CGSize)hostedSourceSize
{
    return self.sourceSize;
}

- (BOOL)foregroundScene:(id)scene
{
    id settings = PXCall(scene, @"settings");
    id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
    if (!mutable || !PXSetBool(mutable, @"setBackgrounded:", NO)) return NO;
    PXSetBool(mutable, @"setForeground:", YES);
    PXSetBool(mutable, @"setAllowsSelection:", YES);
    CGSize sourceSize = PXSourceSize(settings);
    if (!PXSetSceneFrame(mutable, sourceSize)) return NO;
    if (!PXUpdateScene(scene, mutable)) return NO;
    self.scene = scene;
    self.sourceSize = sourceSize;
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
                [strongSelf foregroundScene:scene])
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
                            [strongSelf.canvas addSubview:host];
                            strongSelf.presentationContext = context;
                            strongSelf.hostView = host;
                            [strongSelf layoutHost];
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
    self.hostView = nil;
    self.scene = nil;
    self.canvas = nil;
    self.sourceSize = CGSizeZero;
    SEL invalidate = NSSelectorFromString(@"invalidate");
    for (UIView *child in [host.subviews copy]) {
        if ([child respondsToSelector:invalidate])
            ((void (*)(id, SEL))objc_msgSend)(child, invalidate);
    }
    if ([host respondsToSelector:invalidate])
        ((void (*)(id, SEL))objc_msgSend)(host, invalidate);
    [host removeFromSuperview];
    self.presentationContext = nil;
}

@end
