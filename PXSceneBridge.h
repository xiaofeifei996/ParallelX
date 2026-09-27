#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface PXSceneBridge : NSObject
+ (instancetype)sharedBridge;
+ (nullable id)protectedSettings:(id)settings forAnyScene:(id)scene;
+ (void)relocateAnyKeyboardView:(UIView *)view;
- (void)openApplication:(NSString *)bundleID
                inView:(UIView *)canvas
       keyboardOverlay:(UIView *)keyboardOverlay
            completion:(void (^)(BOOL success))completion;
- (void)relocateKeyboardView:(UIView *)view;
- (void)layoutHost;
- (void)setHostedInteractionEnabled:(BOOL)enabled;
- (CGSize)hostedSourceSize;
- (BOOL)isKeyboardRelocated;
- (CGRect)relocatedKeyboardFrame;
- (BOOL)hasSceneForApplication:(NSString *)bundleID;
- (nullable UIImage *)launchImageForApplication:(NSString *)bundleID size:(CGSize)size;
- (nullable NSString *)frontmostBundleID;
- (void)prepareWindowForBundleID:(NSString *)bundleID
            wasFullscreen:(BOOL)wasFullscreen
                      completion:(void (^)(BOOL success))completion
    NS_SWIFT_NAME(prepareWindow(for:wasFullscreen:completion:));
- (nullable id)protectedSettings:(id)settings forScene:(id)scene;
- (BOOL)openFullscreenApplication:(NSString *)bundleID;
- (BOOL)restartApplication:(NSString *)bundleID
                 suspended:(BOOL)suspended
                completion:(void (^)(BOOL success))completion;
- (BOOL)performShortcut:(NSString *)identifier;
- (BOOL)setBrightnessLevel:(float)level;
- (BOOL)shortcutIsActive:(NSString *)identifier;
- (nullable NSString *)recentApplicationSkipping:(NSArray<NSString *> *)excluded rank:(NSInteger)rank;
- (void)close;
- (void)closeForFullscreen;
@end
NS_ASSUME_NONNULL_END
