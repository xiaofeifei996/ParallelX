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

static void PXTransitionLog(NSString *message)
{
    NSString *path = @"/var/mobile/Documents/com.moxuan.parallelx.transition.log";
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files fileExistsAtPath:path]) [files createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", NSDate.date, message];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch (__unused NSException *exception) { }
    [handle closeFile];
}

static int PXApplicationPID(NSString *bundleID)
{
    id controller = PXCall(NSClassFromString(@"SBApplicationController"), @"sharedInstance");
    id app = nil;
    for (NSString *name in @[@"applicationWithBundleIdentifier:",
                              @"applicationWithDisplayIdentifier:"]) {
        SEL selector = NSSelectorFromString(name);
        if ([controller respondsToSelector:selector]) {
            app = ((id (*)(id, SEL, id))objc_msgSend)(controller, selector, bundleID);
            if (app) break;
        }
    }
    id state = app;
    for (NSUInteger attempt = 0; attempt < 2 && state; attempt++) {
        SEL pidSelector = NSSelectorFromString(@"pid");
        if ([state respondsToSelector:pidSelector]) {
            int pid = ((int (*)(id, SEL))objc_msgSend)(state, pidSelector);
            if (pid > 0) return pid;
        }
        state = PXCall(state, @"processState");
    }
    return 0;
}

@interface PXSceneBridge ()
@property(nonatomic, strong) id scene;
@property(nonatomic, copy) NSString *bundleID;
@property(nonatomic, strong) UIView *hostView;
@property(nonatomic, strong) id presentationContext;
@property(nonatomic, strong) id processAssertion;
@property(nonatomic, weak) UIView *canvas;
@property(nonatomic, weak) UIView *keyboardOverlay;
@property(nonatomic, weak) UIView *keyboardHostView;
@property(nonatomic, strong) UIView *keyboardSlot;
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

- (NSString *)frontmostBundleID
{
    id frontmost = PXCall(UIApplication.sharedApplication,
                          @"_accessibilityFrontMostApplication");
    id bundleID = PXCall(frontmost, @"bundleIdentifier");
    return [bundleID isKindOfClass:NSString.class] ? bundleID : nil;
}

- (void)prepareWindowForBundleID:(NSString *)bundleID
            wasFullscreen:(BOOL)wasFullscreen
                      completion:(dispatch_block_t)completion
{
    if (!completion) return;
    NSString *currentID = [self frontmostBundleID];
    BOOL shouldReturnHome = wasFullscreen || [currentID isEqualToString:bundleID];
    PXTransitionLog([NSString stringWithFormat:@"select=%@ cachedFullscreen=%d current=%@ returnHome=%d",
                     bundleID, wasFullscreen, currentID, shouldReturnHome]);
    dispatch_block_t finish = ^{
        PXTransitionLog([NSString stringWithFormat:@"home completion current=%@",
                         [self frontmostBundleID]]);
        if (NSThread.isMainThread) completion();
        else dispatch_async(dispatch_get_main_queue(), completion);
    };
    if (!shouldReturnHome || bundleID.length == 0) {
        finish();
        return;
    }
    id controller = UIApplication.sharedApplication;
    SEL selector = NSSelectorFromString(@"_returnToHomeScreenWithCompletion:");
    NSMethodSignature *signature = [controller methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3 ||
        signature.methodReturnType[0] != 'v' ||
        [signature getArgumentTypeAtIndex:2][0] != '@') {
        id actions = [NSClassFromString(@"SBHomeHardwareButtonActions") new];
        SEL press = NSSelectorFromString(@"performSinglePressUpActions");
        if ([actions respondsToSelector:press]) {
            PXTransitionLog(@"home hardware action invoked");
            ((void (*)(id, SEL))objc_msgSend)(actions, press);
            finish();
        } else {
            PXTransitionLog(@"home action unavailable; window not opened");
        }
        return;
    }
    PXTransitionLog(@"home selector invoked");
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
    if (!CGSizeEqualToSize(host.bounds.size, source))
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

- (void)keepHostedProcessAlive
{
    if (self.processAssertion || self.bundleID.length == 0) return;
    int pid = PXApplicationPID(self.bundleID);
    Class targetClass = NSClassFromString(@"RBSTarget");
    Class attributeClass = NSClassFromString(@"RBSLegacyAttribute");
    Class assertionClass = NSClassFromString(@"RBSAssertion");
    SEL targetSelector = NSSelectorFromString(@"targetWithPid:");
    SEL attributeSelector = NSSelectorFromString(@"attributeWithReason:flags:");
    SEL initSelector = NSSelectorFromString(@"initWithExplanation:target:attributes:");
    if (pid <= 0 || ![targetClass respondsToSelector:targetSelector] ||
        ![attributeClass respondsToSelector:attributeSelector] ||
        ![assertionClass instancesRespondToSelector:initSelector]) return;
    @try {
        id target = ((id (*)(id, SEL, int))objc_msgSend)(targetClass,
            targetSelector, pid);
        // Background UI must stay renderable while another app is full screen.
        NSUInteger flags = 1 | 2 | 8 | 32;
        id attribute = ((id (*)(id, SEL, NSUInteger, NSUInteger))objc_msgSend)(
            attributeClass, attributeSelector, 7, flags);
        if (!target || !attribute) return;
        id assertion = ((id (*)(id, SEL, id, id, id))objc_msgSend)([assertionClass alloc],
            initSelector,
            @"ParallelX visible window", target, @[attribute]);
        if (![assertion respondsToSelector:NSSelectorFromString(@"acquireWithError:")]) return;
        NSError *error = nil;
        if (((BOOL (*)(id, SEL, NSError **))objc_msgSend)(assertion,
            NSSelectorFromString(@"acquireWithError:"), &error)) self.processAssertion = assertion;
    } @catch (__unused NSException *exception) { }
}

- (id)protectedSettings:(id)settings forScene:(id)scene
{
    if (!scene || scene != self.scene || !self.canvas ||
        ![settings respondsToSelector:@selector(mutableCopy)]) return nil;
    id mutable = [settings mutableCopy];
    if (!PXSetBool(mutable, @"setBackgrounded:", NO)) return nil;
    PXSetBool(mutable, @"setForeground:", YES);
    PXSetBool(mutable, @"setAllowsSelection:", YES);
    SEL deactivation = NSSelectorFromString(@"setDeactivationReasons:");
    NSMethodSignature *signature = [mutable methodSignatureForSelector:deactivation];
    if (signature && signature.numberOfArguments == 3)
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(mutable, deactivation, 0);
    return mutable;
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

- (void)relocateKeyboardView:(UIView *)view
{
    if (view == self.keyboardHostView) {
        if (!view.window) {
            [self.keyboardSlot removeFromSuperview];
            self.keyboardSlot = nil;
            self.keyboardHostView = nil;
        }
        return;
    }
    UIView *host = self.hostView;
    UIView *overlay = self.keyboardOverlay;
    if (!host || !overlay || !view.window || ![view isDescendantOfView:host]) return;
    CGSize screen = overlay.bounds.size;
    CGFloat sourceHeight = view.bounds.size.height;
    if (screen.width <= 0 || screen.height <= 0 || sourceHeight <= 0) return;
    CGFloat height = MIN(sourceHeight, screen.height * 0.4);
    UIView *slot = [[UIView alloc] initWithFrame:CGRectMake(0, screen.height - height,
                                                            screen.width, height)];
    slot.backgroundColor = UIColor.clearColor;
    slot.opaque = NO;
    slot.clipsToBounds = YES;
    [overlay addSubview:slot];
    [slot addSubview:view];
    view.frame = CGRectMake(0, height - sourceHeight, screen.width, sourceHeight);
    self.keyboardSlot = slot;
    self.keyboardHostView = view;
    PXTransitionLog([NSString stringWithFormat:@"keyboard outside height=%.1f source=%.1f",
                     height, sourceHeight]);
}

- (void)openApplication:(NSString *)bundleID
                inView:(UIView *)canvas
       keyboardOverlay:(UIView *)keyboardOverlay
            completion:(void (^)(BOOL))completion
{
    NSAssert(NSThread.isMainThread, @"ParallelX Scene access must be on the main thread");
    [self close];
    NSUInteger generation = self.generation;
    if (bundleID.length == 0 || !canvas ||
        (![self sceneForBundleID:bundleID] && ![self launchSuspended:bundleID])) {
        completion(NO);
        return;
    }
    self.canvas = canvas;
    self.keyboardOverlay = keyboardOverlay;
    self.bundleID = bundleID;
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
            if (scene == preparedScene) [strongSelf keepHostedProcessAlive];
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
    self.keyboardHostView = nil;
    [self.keyboardSlot removeFromSuperview];
    self.keyboardSlot = nil;
    self.keyboardOverlay = nil;
    UIView *host = self.hostView;
    self.hostView = nil;
    id scene = self.scene;
    NSString *bundleID = self.bundleID;
    self.scene = nil;
    self.bundleID = nil;
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
    id assertion = self.processAssertion;
    self.processAssertion = nil;
    @try {
        if ([assertion respondsToSelector:NSSelectorFromString(@"invalidate")])
            ((void (*)(id, SEL))objc_msgSend)(assertion, NSSelectorFromString(@"invalidate"));
    } @catch (__unused NSException *exception) { }
    if (scene && ![[self frontmostBundleID] isEqualToString:bundleID]) {
        id settings = PXCall(scene, @"settings");
        id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
        if (mutable && PXSetBool(mutable, @"setBackgrounded:", YES)) {
            PXSetBool(mutable, @"setForeground:", NO);
            PXUpdateScene(scene, mutable);
        }
    }
}

@end
