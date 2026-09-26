#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface PXSceneBridge : NSObject
+ (instancetype)sharedBridge;
- (void)openApplication:(NSString *)bundleID
                inView:(UIView *)canvas
            completion:(void (^)(BOOL success))completion;
- (void)close;
@end
NS_ASSUME_NONNULL_END
