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
    if (![identifier isEqualToString:@"urlBlacklist"]) {
        [super tableView:tableView didSelectRowAtIndexPath:indexPath];
        return;
    }
    [self openURLBlacklist];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)openURLBlacklist
{
    Class controllerClass = NSClassFromString(@"PXExternalBlacklistController");
    if (![controllerClass isSubclassOfClass:UIViewController.class]) return;
    [self.navigationController pushViewController:[controllerClass new] animated:YES];
}

@end
