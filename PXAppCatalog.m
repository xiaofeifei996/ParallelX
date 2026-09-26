#import "PXAppCatalog.h"
#import <objc/message.h>

static id PXRead(id object, NSString *name)
{
    SEL selector = NSSelectorFromString(name);
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

NSArray<NSDictionary<NSString *, NSString *> *> *PXInstalledApplications(void)
{
    id workspace = PXRead(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    id raw = PXRead(workspace, @"allInstalledApplications");
    if (![raw conformsToProtocol:@protocol(NSFastEnumeration)]) return @[];
    NSMutableArray *apps = [NSMutableArray array];
    for (id proxy in raw) {
        NSString *bundleID = PXRead(proxy, @"bundleIdentifier");
        if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0 ||
            [bundleID isEqualToString:@"com.apple.springboard"]) continue;
        SEL hiddenSelector = NSSelectorFromString(@"isHidden");
        if ([proxy respondsToSelector:hiddenSelector] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(proxy, hiddenSelector)) continue;
        NSString *name = PXRead(proxy, @"localizedName");
        if (![name isKindOfClass:NSString.class] || name.length == 0)
            name = PXRead(proxy, @"itemName");
        if (![name isKindOfClass:NSString.class] || name.length == 0) name = bundleID;
        [apps addObject:@{ @"id": bundleID, @"name": name }];
    }
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return apps;
}

@interface UIImage (PXPrivateIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID
                                              format:(NSInteger)format
                                               scale:(CGFloat)scale;
@end

UIImage *PXApplicationIcon(NSString *bundleID)
{
    if (bundleID.length == 0) return nil;
    @try {
        return [UIImage _applicationIconImageForBundleIdentifier:bundleID
                                                         format:2
                                                          scale:UIScreen.mainScreen.scale];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}
