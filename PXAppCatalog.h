#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, NSString *> *> *PXInstalledApplications(void);
FOUNDATION_EXPORT UIImage * _Nullable PXApplicationIcon(NSString *bundleID);
FOUNDATION_EXPORT UIImage * _Nullable PXApplicationIconLarge(NSString *bundleID);
NS_ASSUME_NONNULL_END
