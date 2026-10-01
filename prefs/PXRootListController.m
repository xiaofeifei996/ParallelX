#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSViewController.h>
#import <UIKit/UIKit.h>
#import <math.h>
#pragma mark - PXPageHostController
@interface PXPageHostController : PSViewController
@property(nonatomic, strong) UIViewController *contentController;
@end
@implementation PXPageHostController
- (instancetype)initForContentSize:(CGSize)contentSize
{
    self = [super initForContentSize:contentSize];
    if (self) {
        self.preferredContentSize = contentSize;
    }
    return self;
}
- (void)setSpecifier:(PSSpecifier *)specifier
{
    [super setSpecifier:specifier];
    if (self.isViewLoaded) {
        [self installContentIfReady];
    }
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    [self installContentIfReady];
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self installContentIfReady];
}
- (void)viewWillBecomeVisible:(PSSpecifier *)specifier
{
    [self setSpecifier:specifier];
    [self installContentIfReady];
}
- (void)installContentIfReady
{
    if (self.contentController != nil) {
        return;
    }
    PSSpecifier *specifier = self.specifier;
    if (specifier == nil) {
        return;
    }
    NSString *identifier = [specifier propertyForKey:@"id"];
    if (identifier.length == 0) {
        return;
    }
    NSDictionary<NSString *, NSString *> *pages = @{
        @"picker" :
            @"PXAppPickerController",
        @"launcher" :
            @"PXLauncherController",
        @"radius" :
            @"PXCornerRadiusController",
        @"dock" :
            @"PXDockController",
        @"gestures" :
            @"PXGestureAreaController",
        @"urlBlacklist" :
            @"PXExternalBlacklistController",
        @"backup" :
            @"PXBackupController"
    };
    NSString *className = pages[identifier];
    if (className.length == 0) {
        return;
    }
    Class pageClass = NSClassFromString(className);
    if (pageClass == Nil) {
        NSLog(@"[ParallelX] Page class not found: %@", className);
        return;
    }
    if (![pageClass isSubclassOfClass:[UIViewController class]]) {
        NSLog(@"[ParallelX] Invalid page class: %@", className);
        return;
    }
    UIViewController *page = [[pageClass alloc] init];
    if (page == nil) {
        NSLog(@"[ParallelX] Failed to create page: %@", className);
        return;
    }
    self.contentController = page;
    [self addChildViewController:page];
    UIView *pageView = page.view;
    if (pageView == nil) {
        [page didMoveToParentViewController:self];
        return;
    }
    pageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:pageView];
    [NSLayoutConstraint activateConstraints:@[
        [pageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [pageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [pageView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [pageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [page didMoveToParentViewController:self];
    NSString *pageTitle = page.title;
    if (pageTitle.length > 0) {
        self.title = pageTitle;
    }
    else if (specifier.name.length > 0) {
        self.title = specifier.name;
    }
    if (page.navigationItem.rightBarButtonItem != nil) {
        self.navigationItem.rightBarButtonItem =
            page.navigationItem.rightBarButtonItem;
    }
    if (@available(iOS 11.0, *)) {
        if (page.navigationItem.searchController != nil) {
            self.navigationItem.searchController =
                page.navigationItem.searchController;
            self.navigationItem.hidesSearchBarWhenScrolling =
                page.navigationItem.hidesSearchBarWhenScrolling;
        }
    }
}
- (BOOL)canBeShownFromSuspendedState
{
    return YES;
}
@end
#pragma mark - PXSettingsListController
@interface PXSettingsListController : PSListController
@end
@implementation PXSettingsListController
- (void)setSpecifier:(PSSpecifier *)specifier
{
    [super setSpecifier:specifier];
    _specifiers = nil;
}
- (NSArray *)specifiers
{
    if (_specifiers == nil) {
        NSString *page =
            [self.specifier propertyForKey:@"id"];
        NSDictionary<NSString *, NSString *> *pages = @{
            @"window" :
                @"Window",
            @"keyboard" :
                @"Keyboard",
            @"external" :
                @"External",
            @"system" :
                @"System"
        };
        NSString *plistName = pages[page];
        if (plistName.length > 0) {
            _specifiers =
                [self loadSpecifiersFromPlistName:plistName
                                           target:self];
        }
        if (_specifiers == nil) {
            _specifiers = @[];
        }
    }
    return _specifiers;
}
#pragma mark - Custom Slider Cells
- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    PSSpecifier *specifier =
        [self specifierAtIndexPath:indexPath];
    NSString *key =
        [specifier propertyForKey:@"key"];
    BOOL isHorizontal =
        [key isEqualToString:@"externalKeyboardHorizontalPercent"];
    BOOL isZoom =
        [key isEqualToString:@"internalKeyboardZoomPercent"];
    BOOL isDim =
        [key isEqualToString:@"keyboardDimOpacity"];
    if (isHorizontal || isZoom || isDim) {
        NSString *title = nil;
        int minimum = 0;
        int maximum = 0;
        CGFloat multiplier = 1.0;
        if (isZoom) {
            title = @"内置键盘放大倍数";
            minimum = 100;
            maximum = 200;
            multiplier = 1.0;
        }
        else if (isHorizontal) {
            title = @"横屏外置键盘位置";
            minimum = 0;
            maximum = 100;
            multiplier = 1.0;
        }
        else {
            title = @"键盘关闭遮罩深度";
            minimum = 0;
            maximum = 60;
            multiplier = 100.0;
        }
        UITableViewCell *cell =
            [[UITableViewCell alloc]
                initWithStyle:UITableViewCellStyleDefault
                reuseIdentifier:nil];
        cell.selectionStyle =
            UITableViewCellSelectionStyleNone;
        cell.backgroundColor =
            UIColor.secondarySystemGroupedBackgroundColor;
        UILabel *label = [[UILabel alloc] init];
        label.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        UISlider *slider = [[UISlider alloc] init];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.minimumValue = minimum;
        slider.maximumValue = maximum;
        NSNumber *storedValue =
            [self readPreferenceValue:specifier];
        CGFloat value =
            storedValue != nil
                ? storedValue.floatValue * multiplier
                : minimum;
        value =
            MAX(minimum, MIN(maximum, value));
        slider.value = value;
        label.text =
            [NSString stringWithFormat:@"%@：%.0f%%",
                title,
                slider.value];
        UIButton *button =
            [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(iOS 13.0, *)) {
            UIImage *image =
                [UIImage systemImageNamed:@"keyboard"];
            [button setImage:image
                   forState:UIControlStateNormal];
        }
        button.accessibilityLabel =
            [@"输入" stringByAppendingString:title];
        __weak typeof(self) weakSelf = self;
        [slider
            addAction:
                [UIAction actionWithHandler:
                    ^(__kindof UIAction *action) {
            UISlider *control =
                (UISlider *)action.sender;
            control.value =
                roundf(control.value);
            label.text =
                [NSString stringWithFormat:@"%@：%.0f%%",
                    title,
                    control.value];
            __strong typeof(weakSelf) strongSelf =
                weakSelf;
            if (strongSelf == nil) {
                return;
            }
            CGFloat saveValue =
                control.value / multiplier;
            [strongSelf
                setPreferenceValue:@(saveValue)
                specifier:specifier];
        }]
            forControlEvents:UIControlEventValueChanged];
        __weak UISlider *weakSlider = slider;
        [button
            addAction:
                [UIAction actionWithHandler:
                    ^(__kindof UIAction *action) {
            __strong UISlider *strongSlider =
                weakSlider;
            if (strongSlider == nil) {
                return;
            }
            UIAlertController *alert =
                [UIAlertController
                    alertControllerWithTitle:title
                    message:
                        [NSString stringWithFormat:
                            @"输入 %d–%d（%%）",
                            minimum,
                            maximum]
                    preferredStyle:UIAlertControllerStyleAlert];
            [alert
                addTextFieldWithConfigurationHandler:
                    ^(UITextField *field) {
                field.keyboardType =
                    UIKeyboardTypeNumberPad;
                field.text =
                    [NSString stringWithFormat:
                        @"%.0f",
                        strongSlider.value];
            }];
            [alert
                addAction:
                    [UIAlertAction
                        actionWithTitle:@"取消"
                        style:UIAlertActionStyleCancel
                        handler:nil]];
            __weak UIAlertController *weakAlert =
                alert;
            __weak typeof(weakSelf) weakController =
                weakSelf;
            [alert
                addAction:
                    [UIAlertAction
                        actionWithTitle:@"确定"
                        style:UIAlertActionStyleDefault
                        handler:
                            ^(UIAlertAction *action) {
                __strong UIAlertController *strongAlert =
                    weakAlert;
                __strong UISlider *slider =
                    weakSlider;
                __strong typeof(weakController) controller =
                    weakController;
                if (strongAlert == nil ||
                    slider == nil ||
                    controller == nil) {
                    return;
                }
                NSString *text =
                    strongAlert.textFields.firstObject.text;
                if (text.length == 0) {
                    return;
                }
                NSScanner *scanner =
                    [NSScanner scannerWithString:text];
                int inputValue = 0;
                BOOL valid =
                    [scanner scanInt:&inputValue] &&
                    scanner.isAtEnd &&
                    inputValue >= minimum &&
                    inputValue <= maximum;
                if (!valid) {
                    return;
                }
                slider.value = inputValue;
                [slider
                    sendActionsForControlEvents:
                        UIControlEventValueChanged];
            }]];
            [weakSelf
                presentViewController:alert
                animated:YES
                completion:nil];
        }]
            forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:label];
        [cell.contentView addSubview:slider];
        [cell.contentView addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor
                constraintEqualToAnchor:
                    cell.contentView.leadingAnchor
                    constant:16.0],
            [label.trailingAnchor
                constraintEqualToAnchor:
                    cell.contentView.trailingAnchor
                    constant:-16.0],
            [label.topAnchor
                constraintEqualToAnchor:
                    cell.contentView.topAnchor
                    constant:10.0],
            [slider.leadingAnchor
                constraintEqualToAnchor:
                    label.leadingAnchor],
            [slider.topAnchor
                constraintEqualToAnchor:
                    label.bottomAnchor
                    constant:5.0],
            [slider.trailingAnchor
                constraintEqualToAnchor:
                    button.leadingAnchor
                    constant:-10.0],
            [button.trailingAnchor
                constraintEqualToAnchor:
                    cell.contentView.trailingAnchor
                    constant:-16.0],
            [button.centerYAnchor
                constraintEqualToAnchor:
                    slider.centerYAnchor],
            [button.widthAnchor
                constraintEqualToConstant:38.0],
            [button.heightAnchor
                constraintEqualToConstant:38.0]
        ]];
        return cell;
    }
    UITableViewCell *cell =
        [super tableView:tableView
            cellForRowAtIndexPath:indexPath];
    if ([cell isKindOfClass:
            NSClassFromString(@"PSLinkCell")]) {
        cell.textLabel.textColor =
            UIColor.labelColor;
        cell.accessoryType =
            UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
#pragma mark - Row Height
- (CGFloat)tableView:(UITableView *)tableView
heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    PSSpecifier *specifier =
        [self specifierAtIndexPath:indexPath];
    NSString *key =
        [specifier propertyForKey:@"key"];
    if ([key isEqualToString:@"keyboardDimOpacity"] ||
        [key isEqualToString:
            @"externalKeyboardHorizontalPercent"] ||
        [key isEqualToString:
            @"internalKeyboardZoomPercent"]) {
        return 82.0;
    }
    return
        [super tableView:tableView
            heightForRowAtIndexPath:indexPath];
}
@end
#pragma mark - PXRootListController
@interface PXRootListController : PXSettingsListController
@end
@implementation PXRootListController
@end