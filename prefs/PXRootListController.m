#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSViewController.h>
#import <math.h>

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
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([[specifier propertyForKey:@"key"] isEqual:@"keyboardDimOpacity"]) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        UILabel *label = [UILabel new];
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        UISlider *slider = [UISlider new];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.minimumValue = 0;
        slider.maximumValue = 60;
        slider.value = [[self readPreferenceValue:specifier] floatValue] * 100;
        label.text = [NSString stringWithFormat:@"键盘关闭遮罩深度：%.0f%%", slider.value];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button setImage:[UIImage systemImageNamed:@"keyboard"] forState:UIControlStateNormal];
        button.accessibilityLabel = @"输入键盘关闭遮罩深度";
        __weak typeof(self) weakSelf = self;
        [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            UISlider *control = (UISlider *)action.sender;
            control.value = roundf(control.value);
            label.text = [NSString stringWithFormat:@"键盘关闭遮罩深度：%.0f%%", control.value];
            [weakSelf setPreferenceValue:@(control.value / 100) specifier:specifier];
        }] forControlEvents:UIControlEventValueChanged];
        __weak UISlider *weakSlider = slider;
        [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"键盘关闭遮罩深度"
                message:@"输入 0–60（%）" preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
                field.keyboardType = UIKeyboardTypeNumberPad;
                field.text = [NSString stringWithFormat:@"%.0f", weakSlider.value];
            }];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            __weak UIAlertController *weakAlert = alert;
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSScanner *scanner = [NSScanner scannerWithString:weakAlert.textFields.firstObject.text ?: @""];
                int value;
                if (![scanner scanInt:&value] || !scanner.isAtEnd || value < 0 || value > 60) return;
                weakSlider.value = value;
                [weakSlider sendActionsForControlEvents:UIControlEventValueChanged];
            }]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
        }] forControlEvents:UIControlEventTouchUpInside];
        for (UIView *view in @[label, slider, button]) [cell.contentView addSubview:view];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
            [slider.leadingAnchor constraintEqualToAnchor:label.leadingAnchor],
            [slider.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:5],
            [slider.trailingAnchor constraintEqualToAnchor:button.leadingAnchor constant:-10],
            [button.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [button.centerYAnchor constraintEqualToAnchor:slider.centerYAnchor],
            [button.widthAnchor constraintEqualToConstant:38], [button.heightAnchor constraintEqualToConstant:38]
        ]];
        return cell;
    }
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if ([cell isKindOfClass:NSClassFromString(@"PSLinkCell")]) {
        cell.textLabel.textColor = UIColor.labelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([[[self specifierAtIndexPath:indexPath] propertyForKey:@"key"] isEqual:@"keyboardDimOpacity"]) return 82;
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

@end
