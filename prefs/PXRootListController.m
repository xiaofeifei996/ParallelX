#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface PXRootListController : PSListController
@end

@implementation PXRootListController

- (NSArray *)specifiers
{
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if ([cell isKindOfClass:NSClassFromString(@"PSLinkCell")]) {
        cell.textLabel.textColor = UIColor.labelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    PSSpecifier *specifier = [self specifierAtIndex:[self indexForIndexPath:indexPath]];
    NSString *identifier = [specifier propertyForKey:@"id"];
    if ([identifier isEqualToString:@"picker"]) [self openPicker];
    else if ([identifier isEqualToString:@"launcher"]) [self openLauncher];
    else if ([identifier isEqualToString:@"radius"]) [self openRadius];
    else if ([identifier isEqualToString:@"dock"]) [self openDock];
    else if ([identifier isEqualToString:@"gestures"]) [self openGestureArea];
    else if ([identifier isEqualToString:@"urlBlacklist"]) [self openURLBlacklist];
    else { [super tableView:tableView didSelectRowAtIndexPath:indexPath]; return; }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
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

- (void)openDock
{
    Class controllerClass = NSClassFromString(@"PXDockController");
    if (!controllerClass || ![controllerClass isSubclassOfClass:UIViewController.class]) return;
    [self.navigationController pushViewController:[controllerClass new] animated:YES];
}

- (void)openGestureArea
{
    Class controllerClass = NSClassFromString(@"PXGestureAreaController");
    if (!controllerClass || ![controllerClass isSubclassOfClass:UIViewController.class]) return;
    [self.navigationController pushViewController:[controllerClass new] animated:YES];
}

- (void)openLauncher
{
    Class controllerClass = NSClassFromString(@"PXLauncherController");
    if (!controllerClass || ![controllerClass isSubclassOfClass:UIViewController.class]) return;
    [self.navigationController pushViewController:[controllerClass new] animated:YES];
}

- (void)openURLBlacklist
{
    Class controllerClass = NSClassFromString(@"PXExternalBlacklistController");
    if (![controllerClass isSubclassOfClass:UIViewController.class]) return;
    [self.navigationController pushViewController:[controllerClass new] animated:YES];
}

@end
