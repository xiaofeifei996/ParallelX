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
    /*
     * IMPORTANT:
     * Preferences creates detail controllers through
     * initForContentSize:.
     *
     * Do not use initWithNibName: here.
     */
    return [super initForContentSize:contentSize];
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

- (void)viewWillBecomeVisible:(PSSpecifier *)specifier
{
    [self setSpecifier:specifier];
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

    NSString *identifier =
        [specifier propertyForKey:@"id"];

    if (identifier.length == 0) {
        return;
    }

    NSDictionary *pages = @{
        @"picker": @"PXAppPickerController",
        @"launcher": @"PXLauncherController",
        @"radius": @"PXCornerRadiusController",
        @"dock": @"PXDockController",
        @"gestures": @"PXGestureAreaController",
        @"urlBlacklist": @"PXExternalBlacklistController",
        @"backup": @"PXBackupController"
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

    if (![pageClass isSubclassOfClass:UIViewController.class]) {
        NSLog(@"[ParallelX] Invalid page class: %@", className);
        return;
    }

    UIViewController *page =
        [[pageClass alloc] init];

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

    self.title =
        page.title.length > 0
            ? page.title
            : specifier.name;

    self.navigationItem.rightBarButtonItem =
        page.navigationItem.rightBarButtonItem;

    if (@available(iOS 11.0, *)) {

        self.navigationItem.searchController =
            page.navigationItem.searchController;

        self.navigationItem.hidesSearchBarWhenScrolling =
            page.navigationItem.hidesSearchBarWhenScrolling;
    }
}

- (BOOL)canBeShownFromSuspendedState
{
    return YES;
}

@end


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
    if (!_specifiers) {

        NSString *page =
            [self.specifier propertyForKey:@"id"];

        NSDictionary *pages = @{
            @"window": @"Window",
            @"keyboard": @"Keyboard",
            @"external": @"External",
            @"system": @"System"
        };

        NSString *plistName =
            pages[page ?: @""];

        if (plistName.length > 0) {

            _specifiers =
                [self loadSpecifiersFromPlistName:
                    plistName
                    target:self];
        }
    }

    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    PSSpecifier *specifier =
        [self specifierAtIndexPath:indexPath];

    BOOL horizontal =
        [[specifier propertyForKey:@"key"]
            isEqual:@"externalKeyboardHorizontalPercent"];

    BOOL focus =
        [[specifier propertyForKey:@"key"]
            isEqual:@"internalKeyboardZoomPercent"];

    BOOL dim =
        [[specifier propertyForKey:@"key"]
            isEqual:@"keyboardDimOpacity"];

    if (horizontal || focus || dim) {

        NSString *title;

        int minimum;
        int maximum;

        CGFloat multiplier;

        if (focus) {

            title = @"内置键盘放大倍数";
            minimum = 100;
            maximum = 200;
            multiplier = 1.0;

        } else if (horizontal) {

            title = @"横屏外置键盘位置";
            minimum = 0;
            maximum = 100;
            multiplier = 1.0;

        } else {

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

        UILabel *label =
            [[UILabel alloc] init];

        label.font =
            [UIFont preferredFontForTextStyle:
                UIFontTextStyleBody];

        label.translatesAutoresizingMaskIntoConstraints = NO;

        UISlider *slider =
            [[UISlider alloc] init];

        slider.translatesAutoresizingMaskIntoConstraints = NO;

        slider.minimumValue = minimum;
        slider.maximumValue = maximum;

        NSNumber *preference =
            [self readPreferenceValue:specifier];

        slider.value =
            preference != nil
                ? preference.floatValue * multiplier
                : minimum;

        slider.value =
            MAX(minimum,
                MIN(maximum, slider.value));

        label.text =
            [NSString stringWithFormat:
                @"%@：%.0f%%",
                title,
                slider.value];

        UIButton *button =
            [UIButton buttonWithType:
                UIButtonTypeSystem];

        button.translatesAutoresizingMaskIntoConstraints = NO;

        if (@available(iOS 13.0, *)) {

            [button setImage:
                [UIImage systemImageNamed:@"keyboard"]
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
                [NSString stringWithFormat:
                    @"%@：%.0f%%",
                    title,
                    control.value];

            __strong typeof(weakSelf) strongSelf =
                weakSelf;

            if (!strongSelf) {
                return;
            }

            [strongSelf
                setPreferenceValue:
                    @(control.value / multiplier)
                specifier:specifier];

        }]
            forControlEvents:
                UIControlEventValueChanged];

        __weak UISlider *weakSlider = slider;

        [button
            addAction:
                [UIAction actionWithHandler:
                    ^(__kindof UIAction *action) {

            __strong UISlider *strongSlider =
                weakSlider;

            if (!strongSlider) {
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
                    preferredStyle:
                        UIAlertControllerStyleAlert];

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

                if (!strongAlert || !slider) {
                    return;
                }

                NSString *text =
                    strongAlert.textFields
                        .firstObject.text;

                NSScanner *scanner =
                    [NSScanner scannerWithString:
                        text ?: @""];

                int value = 0;

                if (![scanner scanInt:&value] ||
                    !scanner.isAtEnd ||
                    value < minimum ||
                    value > maximum) {

                    return;
                }

                slider.value = value;

                [slider
                    sendActionsForControlEvents:
                        UIControlEventValueChanged];
            }]];

            [weakSelf
                presentViewController:alert
                animated:YES
                completion:nil];

        }]
            forControlEvents:
                UIControlEventTouchUpInside];

        [cell.contentView addSubview:label];
        [cell.contentView addSubview:slider];
        [cell.contentView addSubview:button];

        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor
                constraintEqualToAnchor:
                    cell.contentView.leadingAnchor
                    constant:16],

            [label.trailingAnchor
                constraintEqualToAnchor:
                    cell.contentView.trailingAnchor
                    constant:-16],

            [label.topAnchor
                constraintEqualToAnchor:
                    cell.contentView.topAnchor
                    constant:10],

            [slider.leadingAnchor
                constraintEqualToAnchor:
                    label.leadingAnchor],

            [slider.topAnchor
                constraintEqualToAnchor:
                    label.bottomAnchor
                    constant:5],

            [slider.trailingAnchor
                constraintEqualToAnchor:
                    button.leadingAnchor
                    constant:-10],

            [button.trailingAnchor
                constraintEqualToAnchor:
                    cell.contentView.trailingAnchor
                    constant:-16],

            [button.centerYAnchor
                constraintEqualToAnchor:
                    slider.centerYAnchor],

            [button.widthAnchor
                constraintEqualToConstant:38],

            [button.heightAnchor
                constraintEqualToConstant:38]
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

- (CGFloat)tableView:(UITableView *)tableView
heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *key =
        [[self specifierAtIndexPath:indexPath]
            propertyForKey:@"key"];

    if ([key isEqual:@"keyboardDimOpacity"] ||
        [key isEqual:@"externalKeyboardHorizontalPercent"] ||
        [key isEqual:@"internalKeyboardZoomPercent"]) {

        return 82;
    }

    return
        [super tableView:tableView
            heightForRowAtIndexPath:indexPath];
}

@end


@interface PXRootListController : PXSettingsListController

@end

@implementation PXRootListController

@end