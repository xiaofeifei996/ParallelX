#import "PXSceneBridge.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

@interface PXKeyboardSlot : UIView
@end

@implementation PXKeyboardSlot
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

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
@property(nonatomic, assign) UIWindowLevel keyboardWindowLevel;
@property(nonatomic, assign) BOOL relocatingKeyboard;
@property(nonatomic, assign) BOOL fullscreenHandoff;
@property(nonatomic, copy) NSString *latestSwitcherBundleID;
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
    SEL selector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    id springBoard = UIApplication.sharedApplication;
    NSMethodSignature *signature = [springBoard methodSignatureForSelector:selector];
    BOOL launched = signature && signature.numberOfArguments == 4 &&
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(springBoard, selector, bundleID, YES);
    if (!launched) {
        id workspace = PXCall(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
        signature = [workspace methodSignatureForSelector:selector];
        launched = signature && signature.numberOfArguments == 4 &&
            ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(workspace, selector, bundleID, YES);
    }
    if (launched && !PXApplicationPID(bundleID)) {
        id manager = PXCall(NSClassFromString(@"FBProcessManager"), @"sharedInstance");
        SEL create = NSSelectorFromString(@"createApplicationProcessForBundleID:");
        if ([manager methodSignatureForSelector:create].numberOfArguments == 3)
            ((void (*)(id, SEL, id))objc_msgSend)(manager, create, bundleID);
    }
    return launched;
}

- (BOOL)openFullscreenApplication:(NSString *)bundleID
{
    if (bundleID.length == 0) return NO;
    SEL selector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    id springBoard = UIApplication.sharedApplication;
    NSMethodSignature *signature = [springBoard methodSignatureForSelector:selector];
    if (signature && signature.numberOfArguments == 4 &&
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(springBoard, selector, bundleID, NO)) {
        self.fullscreenHandoff = YES;
        return YES;
    }
    id workspace = PXCall(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    signature = [workspace methodSignatureForSelector:selector];
    BOOL opened = signature && signature.numberOfArguments == 4 &&
        ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(workspace, selector, bundleID, NO);
    if (opened) self.fullscreenHandoff = YES;
    return opened;
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
                      completion:(void (^)(BOOL success))completion
{
    if (!completion) return;
    NSString *currentID = [self frontmostBundleID];
    BOOL shouldReturnHome = wasFullscreen && [currentID isEqualToString:bundleID];
    void (^finish)(BOOL) = ^(BOOL success){
        if (NSThread.isMainThread) completion(success);
        else dispatch_async(dispatch_get_main_queue(), ^{ completion(success); });
    };
    if (!shouldReturnHome || bundleID.length == 0) {
        finish(YES);
        return;
    }
    id actions = [NSClassFromString(@"SBHomeHardwareButtonActions") new];
    SEL press = NSSelectorFromString(@"performSinglePressUpActions");
    if ([actions respondsToSelector:press]) {
        ((void (*)(id, SEL))objc_msgSend)(actions, press);
        finish(YES);
        return;
    }
    id controller = UIApplication.sharedApplication;
    SEL selector = NSSelectorFromString(@"_returnToHomeScreenWithCompletion:");
    NSMethodSignature *signature = [controller methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3 ||
        signature.methodReturnType[0] != 'v' ||
        [signature getArgumentTypeAtIndex:2][0] != '@') {
        finish(NO);
        return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, nil);
    finish(YES);
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

- (BOOL)promoteSwitcherCard:(NSString *)bundleID
{
    if (![self.latestSwitcherBundleID isEqualToString:bundleID]) return NO;
    id switcher = PXCall(NSClassFromString(@"SBMainSwitcherViewController"), @"sharedInstance");
    NSArray *recent = PXCall(switcher, @"recentAppLayouts");
    SEL add = NSSelectorFromString(@"_addAppLayoutToFront:");
    if (![recent isKindOfClass:NSArray.class] || ![switcher respondsToSelector:add]) return NO;
    for (NSUInteger index = 0; index < recent.count; index++) {
        id layout = recent[index];
        BOOL contains = NO;
        SEL membership = NSSelectorFromString(@"containsItemWithBundleIdentifier:");
        if ([layout respondsToSelector:membership])
            contains = ((BOOL (*)(id, SEL, id))objc_msgSend)(layout, membership, bundleID);
        else for (id item in PXCall(layout, @"allItems")) {
            if ([PXCall(item, @"bundleIdentifier") isEqual:bundleID]) { contains = YES; break; }
        }
        if (!contains) continue;
        if (index) ((void (*)(id, SEL, id))objc_msgSend)(switcher, add, layout);
        return YES;
    }
    return NO;
}

- (void)registerColdSceneInSwitcher:(id)scene bundleID:(NSString *)bundleID
{
    NSString *sceneID = PXCall(scene, @"identifier");
    if (![sceneID isKindOfClass:NSString.class] || sceneID.length == 0) return;
    self.latestSwitcherBundleID = bundleID;
    BOOL existing = [self promoteSwitcherCard:bundleID];
    for (NSNumber *delay in @[@0.25, @0.75, @1.5, @3.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self promoteSwitcherCard:bundleID]; });
    }
    Class itemClass = NSClassFromString(@"SBDisplayItem");
    SEL factory = NSSelectorFromString(@"applicationDisplayItemWithBundleIdentifier:sceneIdentifier:");
    SEL add = NSSelectorFromString(@"addAppLayoutForDisplayItem:completion:");
    id switcher = PXCall(NSClassFromString(@"SBMainSwitcherViewController"), @"sharedInstance");
    Method factoryMethod = class_getClassMethod(itemClass, factory);
    Method addMethod = class_getInstanceMethod([switcher class], add);
    if (!factoryMethod || method_getNumberOfArguments(factoryMethod) != 4 ||
        !addMethod || method_getNumberOfArguments(addMethod) != 4 || existing) return;
    @try {
        id item = ((id (*)(id, SEL, id, id))objc_msgSend)(itemClass,
            factory, bundleID, sceneID);
        if (!item) return;
        ((void (*)(id, SEL, id, id))objc_msgSend)(switcher, add, item, ^{
            dispatch_async(dispatch_get_main_queue(), ^{ [self promoteSwitcherCard:bundleID]; });
        });
    } @catch (__unused NSException *exception) { }
}

- (void)relocateKeyboardView:(UIView *)view
{
    if (self.relocatingKeyboard) return;
    if (view == self.keyboardHostView) {
        if (!view.window || view.superview != self.keyboardSlot) {
            self.keyboardSlot.userInteractionEnabled = NO;
            [self.keyboardSlot removeFromSuperview];
            self.keyboardSlot = nil;
            self.keyboardHostView = nil;
            self.keyboardOverlay.window.windowLevel = self.keyboardWindowLevel;
        }
        else {
            CGSize screen = self.keyboardOverlay.bounds.size;
            CGFloat height = MIN(view.bounds.size.height, screen.height * 0.55);
            if (height <= 0 || screen.width <= 0) return;
            CGRect slotFrame = CGRectMake(0, screen.height - height, screen.width, height);
            self.relocatingKeyboard = YES;
            if (!CGRectEqualToRect(self.keyboardSlot.frame, slotFrame)) self.keyboardSlot.frame = slotFrame;
            CGRect keyboardFrame = CGRectMake(0, height - view.bounds.size.height,
                                               screen.width, view.bounds.size.height);
            if (!CGRectEqualToRect(view.frame, keyboardFrame)) view.frame = keyboardFrame;
            self.relocatingKeyboard = NO;
            return;
        }
    }
    UIView *host = self.hostView;
    UIView *overlay = self.keyboardOverlay;
    if (!host || !overlay || !view.window || ![view isDescendantOfView:host]) return;
    CGSize screen = overlay.bounds.size;
    CGFloat sourceHeight = view.bounds.size.height;
    if (screen.width <= 0 || screen.height <= 0 || sourceHeight <= 0) return;
    self.relocatingKeyboard = YES;
    if (!self.keyboardSlot) self.keyboardWindowLevel = overlay.window.windowLevel;
    overlay.window.windowLevel = MAX(overlay.window.windowLevel, self.canvas.window.windowLevel + 1);
    CGFloat height = MIN(sourceHeight, screen.height * 0.55);
    UIView *previousSlot = self.keyboardSlot;
    self.keyboardHostView = nil;
    self.keyboardSlot = nil;
    previousSlot.userInteractionEnabled = NO;
    [previousSlot removeFromSuperview];
    UIView *slot = [[PXKeyboardSlot alloc] initWithFrame:CGRectMake(0, screen.height - height,
                                                            screen.width, height)];
    slot.backgroundColor = UIColor.clearColor;
    slot.opaque = NO;
    slot.clipsToBounds = YES;
    [overlay addSubview:slot];
    [slot addSubview:view];
    view.frame = CGRectMake(0, height - sourceHeight, screen.width, sourceHeight);
    self.keyboardSlot = slot;
    self.keyboardHostView = view;
    self.relocatingKeyboard = NO;
}

- (void)relocateExistingKeyboard:(UIView *)root
{
    Class keyboard = NSClassFromString(@"_UIKeyboardLayerHostView");
    if (keyboard && [root isKindOfClass:keyboard]) {
        [self relocateKeyboardView:root];
        return;
    }
    for (UIView *child in [root.subviews copy]) [self relocateExistingKeyboard:child];
}

- (void)openApplication:(NSString *)bundleID
                inView:(UIView *)canvas
       keyboardOverlay:(UIView *)keyboardOverlay
            completion:(void (^)(BOOL))completion
{
    NSAssert(NSThread.isMainThread, @"ParallelX Scene access must be on the main thread");
    [self close];
    NSUInteger generation = self.generation;
    if (bundleID.length == 0 || !canvas) {
        completion(NO);
        return;
    }
    BOOL coldStart = ![self sceneForBundleID:bundleID];
    if (coldStart && ![self launchSuspended:bundleID]) {
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
            [strongSelf keepHostedProcessAlive];
            if (scene && scene == preparedScene) {
                NSArray *layers = [strongSelf mainLayersForScene:scene];
                Class hostClass = NSClassFromString(@"_UISceneLayerHostContainerView");
                Class contextClass = NSClassFromString(@"UIScenePresentationContext");
                SEL initializer = NSSelectorFromString(@"initWithScene:debugDescription:");
                SEL contextInitializer = NSSelectorFromString(@"_initWithDefaultValues");
                SEL bindContext = NSSelectorFromString(@"_setPresentationContext:");
                if (!strongSelf.hostView &&
                    [hostClass instancesRespondToSelector:initializer] &&
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
                            strongSelf.presentationContext = context;
                            strongSelf.hostView = host;
                            [strongSelf.canvas addSubview:host];
                            [strongSelf layoutHost];
                        }
                    }
                }
                if (layers.count && strongSelf.hostView) {
                    [strongSelf.hostView layoutIfNeeded];
                    [strongSelf relocateExistingKeyboard:strongSelf.hostView];
                    if (coldStart)
                        [strongSelf registerColdSceneInSwitcher:scene bundleID:bundleID];
                    completion(YES);
                    retry = nil;
                    return;
                }
            }
        } @catch (__unused NSException *exception) {
            // Private interfaces vary; fail closed instead of crashing SpringBoard.
        }
        if (++attempts >= 40) {
            [strongSelf close];
            completion(NO);
            retry = nil;
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (attempts < 10 ? 50 : 125) * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), retry);
    };
    dispatch_async(dispatch_get_main_queue(), retry);
}

- (void)close
{
    NSAssert(NSThread.isMainThread, @"ParallelX Scene access must be on the main thread");
    self.generation += 1;
    self.latestSwitcherBundleID = nil;
    if (self.keyboardSlot) self.keyboardOverlay.window.windowLevel = self.keyboardWindowLevel;
    self.keyboardHostView = nil;
    self.keyboardSlot.userInteractionEnabled = NO;
    [self.keyboardSlot removeFromSuperview];
    self.keyboardSlot = nil;
    self.keyboardOverlay = nil;
    UIView *host = self.hostView;
    self.hostView = nil;
    id scene = self.scene;
    NSString *bundleID = self.bundleID;
    BOOL fullscreenHandoff = self.fullscreenHandoff;
    self.fullscreenHandoff = NO;
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
    if (scene && !fullscreenHandoff && ![[self frontmostBundleID] isEqualToString:bundleID]) {
        id settings = PXCall(scene, @"settings");
        id mutable = [settings respondsToSelector:@selector(mutableCopy)] ? [settings mutableCopy] : nil;
        if (mutable && PXSetBool(mutable, @"setBackgrounded:", YES)) {
            PXSetBool(mutable, @"setForeground:", NO);
            PXUpdateScene(scene, mutable);
        }
    }
}

@end
