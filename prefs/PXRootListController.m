#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSViewController.h>

@interface PXPageHostController : PSViewController
@property(nonatomic, strong) UIViewController *contentController;
@end

@implementation PXPageHostController

- (instancetype)initForContentSize:(CGSize)contentSize
{
    return [super initWithNibName:nil bundle:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self installContentIfReady];
}

- (void)setSpecifier:(PSSpecifier *)specifier
{
    [super setSpecifier:specifier];
    if (self.isViewLoaded) [self installContentIfReady];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self installContentIfReady];
}

- (void)installContentIfReady
{
    if (self.contentController || !self.specifier) return;
    NSString *identifier = [self.specifier propertyForKey:@"id"];
    NSDictionary<NSString *, NSString *> *pages = @{
        @"picker": @"PXAppPickerController",
        @"launcher": @"PXLauncherController",
        @"radius": @"PXCornerRadiusController",
        @"dock": @"PXDockController",
        @"gestures": @"PXGestureAreaController",
        @"urlBlacklist": @"PXExternalBlacklistController"
    };
    NSString *className = pages[identifier ?: @""];
    Class pageClass = className ? NSClassFromString(className) : Nil;
    if (![pageClass isSubclassOfClass:UIViewController.class]) return;
    UIViewController *page = [pageClass new];
    self.contentController = page;
    [self addChildViewController:page];
    page.view.frame = self.view.bounds;
    page.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:page.view];
    [page didMoveToParentViewController:self];
    self.title = page.title ?: self.specifier.name;
    self.navigationItem.rightBarButtonItem = page.navigationItem.rightBarButtonItem;
    self.navigationItem.searchController = page.navigationItem.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = page.navigationItem.hidesSearchBarWhenScrolling;
}

- (BOOL)canBeShownFromSuspendedState { return YES; }

@end

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

@end
