#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSViewController.h>
#import <math.h>

#pragma mark - PXPageHostController

@interface PXPageHostController : PSViewController

@property(nonatomic, strong) UIViewController *contentController;

@end

@implementation PXPageHostController

- (instancetype)initForContentSize:(CGSize)contentSize
{
    self = [super initForContentSize:contentSize];
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self installContentIfReady];
}

- (void)setSpecifier:(PSSpecifier *)specifier
{
    [super setSpecifier:specifier];

    if (self.isViewLoaded) {
        [self installContentIfReady];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

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

    NSDictionary<NSString *, NSString *> *pages = @{
        @"picker"      : @"PXAppPickerController",
        @"launcher"    : @"PXLauncherController",
        @"radius"      : @"PXCornerRadiusController",
        @"dock"        : @"PXDockController",
        @"gestures"    : @"PXGestureAreaController",
        @"urlBlacklist": @"PXExternalBlacklistController",
        @"backup"      : @"PXBackupController"
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
        NSLog(@"[ParallelX] Page class is not UIViewController: %@", className);
        return;
    }

    UIViewController *page = [[pageClass alloc] init];

    if (page == nil) {
        return;
    }

    self.contentController = page;

    [self addChildViewController:page];

    page.view.frame = self.view.bounds;
    page.view.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    [self.view addSubview:page.view];

    [page didMoveToParentViewController:self];

    NSString *pageTitle = page.title;

    if (pageTitle.length > 0) {
        self.title = pageTitle;
    } else if (specifier.name.length > 0) {
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

    /*
     * The root controller and child settings pages use different
     * plist files. Clear the cached specifiers after the specifier
     * has been assigned so the correct plist can be loaded.
     */
    _specifiers = nil;
}

- (NSArray *)specifiers
{
    if (_specifiers == nil) {

        NSString *page =
            [self.specifier propertyForKey:@"id"];

        NSDictionary<NSString *, NSString *> *pages = @{
            @"window"   : @"Window",
            @"keyboard" : @"Keyboard",
            @"external" : @"External",
            @"system"   : @"System"
        };

        NSString *plistName = pages[page];

        /*
         * IMPORTANT:
         *
         * PXRootListController does not have an "id" specifier.
         * Therefore the root page MUST fall back to Root.plist.
         *
         * Without this fallback, Preferences shows a completely
         * blank ParallelX page.
         */
        if (plistName.length == 0) {
            plistName = @"Root";
        }

        _specifiers =
            [self loadSpecifiersFromPlistName:plistName
                                       target:self];
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

    BOOL horizontal =
        [key isEqualToString:@"externalKeyboardHorizontalPercent"];

    BOOL focus =
        [key isEqualToString:@"internalKeyboardZoomPercent"];

    BOOL keyboardDim =
        [key isEqualToString:@"keyboardDimOpacity"];

    /*
     * Custom slider cells.
     */
    if (horizontal || focus || keyboardDim) {

        NSString *title;

        if (focus) {
            title = @"内置键盘放大倍数";
        } else if (horizontal) {
            title = @"横屏外置键盘位置";
        } else {
            title = @"键盘关闭遮罩深度";
        }

        int minimum = focus ? 100 : 0;

        int maximum;

        if (focus) {
            maximum = 200;
        } else if (horizontal) {
            maximum = 100;
        } else {
            maximum = 60;
        }

        CGFloat multiplier =
            (horizontal || focus) ? 1.0 : 100.0;

        UITableViewCell *cell =
            [[UITableViewCell alloc]
                initWithStyle:UITableViewCellStyleDefault
                reuseIdentifier:nil];

        cell.selectionStyle =
            UITableViewCellSelectionStyleNone;

        if (@available(iOS 13.0, *)) {
            cell.backgroundColor =
                [UIColor secondarySystemGroupedBackgroundColor];
        }

        UILabel *label = [[UILabel alloc] init];

        label.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

        label.translatesAutoresizingMaskIntoConstraints = NO;

        UISlider *slider =
            [[UISlider alloc] init];

        slider.translatesAutoresizingMaskIntoConstraints = NO;

        slider.minimumValue = minimum;
        slider.maximumValue = maximum;

        NSNumber *preferenceValue =
            [self readPreferenceValue:specifier];

        CGFloat value =
            [preferenceValue floatValue] * multiplier;

        if (value < minimum) {
            value = minimum;
        }

        if (value > maximum) {
            value = maximum;
        }

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

            if (image != nil) {
                [button setImage:image
                        forState:UIControlStateNormal];
            }
        }

        button.accessibilityLabel =
            [@"输入" stringByAppendingString:title];

        __weak typeof(self) weakSelf = self;

        [slider addAction:
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

            if (strongSelf != nil) {

                [strongSelf setPreferenceValue:
                    @(control.value / multiplier)
                    specifier:specifier];
            }

        }]
        forControlEvents:UIControlEventValueChanged];


        __weak UISlider *weakSlider = slider;

        [button addAction:
            [UIAction actionWithHandler:
                ^(__kindof UIAction *action) {

            __strong typeof(weakSelf) strongSelf =
                weakSelf;

            if (strongSelf == nil) {
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

            [alert addTextFieldWithConfigurationHandler:
                ^(UITextField *field) {

                field.keyboardType =
                    UIKeyboardTypeNumberPad;

                UISlider *currentSlider =
                    weakSlider;

                if (currentSlider != nil) {

                    field.text =
                        [NSString stringWithFormat:
                            @"%.0f",
                            currentSlider.value];
                }
            }];


            [alert addAction:
                [UIAlertAction
                    actionWithTitle:@"取消"
                    style:UIAlertActionStyleCancel
                    handler:nil]];


            __weak UIAlertController *weakAlert =
                alert;

            [alert addAction:
                [UIAlertAction
                    actionWithTitle:@"确定"
                    style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {

                UIAlertController *strongAlert =
                    weakAlert;

                UISlider *strongSlider =
                    weakSlider;

                if (strongAlert == nil ||
                    strongSlider == nil) {
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

                BOOL success =
                    [scanner scanInt:&inputValue];

                if (!success ||
                    !scanner.isAtEnd ||
                    inputValue < minimum ||
                    inputValue > maximum) {

                    return;
                }

                strongSlider.value =
                    inputValue;

                [strongSlider
                    sendActionsForControlEvents:
                        UIControlEventValueChanged];
            }]];


            [strongSelf
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


    /*
     * Normal Preferences cells.
     */
    UITableViewCell *cell =
        [super tableView:tableView
   cellForRowAtIndexPath:indexPath];


    if ([cell isKindOfClass:
            NSClassFromString(@"PSLinkCell")]) {

        cell.textLabel.textColor =
            [UIColor labelColor];

        cell.accessoryType =
            UITableViewCellAccessoryDisclosureIndicator;
    }


    return cell;
}


#pragma mark - Cell Height

- (CGFloat)tableView:(UITableView *)tableView
heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    PSSpecifier *specifier =
        [self specifierAtIndexPath:indexPath];

    NSString *key =
        [specifier propertyForKey:@"key"];


    if ([key isEqualToString:@"keyboardDimOpacity"] ||
        [key isEqualToString:@"externalKeyboardHorizontalPercent"] ||
        [key isEqualToString:@"internalKeyboardZoomPercent"]) {

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