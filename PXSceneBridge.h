#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface PXSceneBridge : NSObject
+ (instancetype)sharedBridge;
- (void)openApplication:(NSString *)bundleID
                inView:(UIView *)canvas
       keyboardOverlay:(UIView *)keyboardOverlay
            completion:(void (^)(BOOL success))completion;
- (void)relocateKeyboardView:(UIView *)view;
- (void)layoutHost;
- (CGSize)hostedSourceSize;
- (nullable NSString *)frontmostBundleID;
- (void)prepareWindowForBundleID:(NSString *)bundleID
            wasFullscreen:(BOOL)wasFullscreen
                      completion:(void (^)(BOOL success))completion
    NS_SWIFT_NAME(prepareWindow(for:wasFullscreen:completion:));
- (nullable id)protectedSettings:(id)settings forScene:(id)scene;
- (BOOL)openFullscreenApplication:(NSString *)bundleID;
- (void)close;
@end
NS_ASSUME_NONNULL_END
