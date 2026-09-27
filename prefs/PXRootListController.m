#import <Preferences/PSListController.h>

@interface PXRootListController : PSListController
@end

@implementation PXRootListController

- (NSArray *)specifiers
{
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)openPicker
{
    Class pickerClass = NSClassFromString(@"PXAppPickerController");
    if (!pickerClass || ![pickerClass isSubclassOfClass:UIViewController.class]) return;
    UIViewController *picker = [pickerClass new];
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)openRadius
{
    Class controllerClass = NSClassFromString(@"PXCornerRadiusController");
    if (!controllerClass || ![controllerClass isSubclassOfClass:UIViewController.class]) return;
    [self.navigationController pushViewController:[controllerClass new] animated:YES];
}

@end
