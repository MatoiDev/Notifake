#import <Foundation/Foundation.h>
#import "NTFRootListController.h"

static void __notifake_remote_log(NSString *text) {

	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
	NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];

	RLog(@"%@: %@", dateString, text);
}



@implementation NTFRootListController
- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}
	return _specifiers;
}


- (NSString *)getPathForFile:(NSString *)fileName {
    NSString *preferencesBundlePath = @"/Library/PreferenceBundles/NotifakePreferences.bundle/";
    NSString *alternativePath = @"/var/jb/Library/PreferenceBundles/NotifakePreferences.bundle/";

    NSString *preferredPath = [preferencesBundlePath stringByAppendingPathComponent:fileName];
    if ([[NSFileManager defaultManager] fileExistsAtPath:preferredPath]) {
        return preferredPath;
    }

    NSString *alternativeFilePath = [alternativePath stringByAppendingPathComponent:fileName];
    if ([[NSFileManager defaultManager] fileExistsAtPath:alternativeFilePath]) {
        return alternativeFilePath;
    }

    return nil;
}


-(void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.titleView = [UIView new];

    self.navigationTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];

    [[self navigationTitleLabel] setFont:[UIFont boldSystemFontOfSize:25]];
    [[self navigationTitleLabel] setText:@"Notifake"];

    #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
        if (@available(iOS 13.0, *)) {
            [[self navigationTitleLabel] setTextColor:[UIColor labelColor]];
        }
    #else
        [[self navigationTitleLabel] setTextColor:[UIColor blackColor]];
    #endif

    [[self navigationTitleLabel] setTextAlignment:NSTextAlignmentCenter];
    [[self navigationTitleLabel] setAlpha:0];

    [[[self navigationItem] titleView] addSubview:[self navigationTitleLabel]];

    self.navigationTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
            [self.navigationTitleLabel.topAnchor constraintEqualToAnchor:self.navigationItem.titleView.topAnchor],
            [self.navigationTitleLabel.leadingAnchor constraintEqualToAnchor:self.navigationItem.titleView.leadingAnchor],
            [self.navigationTitleLabel.trailingAnchor constraintEqualToAnchor:self.navigationItem.titleView.trailingAnchor],
            [self.navigationTitleLabel.bottomAnchor constraintEqualToAnchor:self.navigationItem.titleView.bottomAnchor],
    ]];

    UILabel * notifakeTitleLabel = [UILabel new];
    UILabel * notifakeVersionLabel = [UILabel new];


    #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
        if (@available(iOS 13.0, *)) {
         [notifakeTitleLabel setTextColor:[UIColor labelColor]];
        }
    #else
         [notifakeTitleLabel setTextColor:[UIColor blackColor]];
    #endif

    [notifakeTitleLabel setFont:[UIFont systemFontOfSize:50 weight:UIFontWeightHeavy]];
    [notifakeTitleLabel setText:@"Notifake"];

    notifakeTitleLabel.adjustsFontSizeToFitWidth = YES;
    notifakeTitleLabel.minimumScaleFactor = 0.5;

    [notifakeVersionLabel setTextColor:[UIColor systemGrayColor]];
    [notifakeVersionLabel setFont:[UIFont systemFontOfSize:20 weight:UIFontWeightRegular]];
    [notifakeVersionLabel setText:@"Version 1.0.0"];

    notifakeVersionLabel.adjustsFontSizeToFitWidth = YES;
    notifakeVersionLabel.minimumScaleFactor = 0.5;

    self.PBHeaderView = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 150, 150)];

    [[self PBHeaderView] addSubview:[self lottieArea]];
    [[self PBHeaderView] addSubview:notifakeTitleLabel];
    [[self PBHeaderView] addSubview:notifakeVersionLabel];

    [notifakeTitleLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [notifakeVersionLabel setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.lottieArea = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 150, 150)];
    [[self PBHeaderView] addSubview:[self lottieArea]];
    self.animation = [LOTAnimationView animationWithFilePath: [self getPathForFile:@"notifakeicon.json"]];
    self.lottieArea.translatesAutoresizingMaskIntoConstraints = NO;
    self.animation.translatesAutoresizingMaskIntoConstraints = NO;
    self.animation.contentMode = UIViewContentModeScaleAspectFit;
    [self.lottieArea addSubview:self.animation];

    [NSLayoutConstraint activateConstraints:@[

            [self.lottieArea.topAnchor constraintEqualToAnchor: self.PBHeaderView.topAnchor constant:0],
            [self.lottieArea.leadingAnchor constraintEqualToAnchor:self.PBHeaderView.leadingAnchor constant:-16],
            [[[self lottieArea] widthAnchor] constraintEqualToConstant:150],
            [[[self lottieArea] heightAnchor] constraintEqualToConstant:150],
            [[[self animation] widthAnchor] constraintEqualToConstant:150],
            [[[self animation] heightAnchor] constraintEqualToConstant:150],

            [[notifakeTitleLabel leadingAnchor] constraintEqualToAnchor: [[self lottieArea] trailingAnchor] constant: -8],
            [[notifakeTitleLabel centerYAnchor] constraintEqualToAnchor: [[self lottieArea] centerYAnchor] constant: -8],
            [[notifakeTitleLabel trailingAnchor] constraintLessThanOrEqualToAnchor: [[self PBHeaderView] trailingAnchor] constant: -24],
            [[notifakeVersionLabel centerXAnchor] constraintEqualToAnchor: [notifakeTitleLabel centerXAnchor] constant: 0],
            [[notifakeVersionLabel topAnchor] constraintEqualToAnchor: [notifakeTitleLabel bottomAnchor] constant: -8],

    ]];

    self.blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    self.blurOnPBScreen = [[UIVisualEffectView alloc] initWithEffect:[self blurEffect]];
}

-(void)viewWillAppear:(BOOL)animated {

    [[self blurOnPBScreen] setFrame:[[self view] bounds]];
    [[self blurOnPBScreen] setAlpha:1];
    [[self view] addSubview:[self blurOnPBScreen]];

    [self.animation setLoopAnimation: YES];
    [self.animation play];

    [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [[self blurOnPBScreen] setAlpha:0];
    } completion:nil];

}

- (void)viewWillDisappear:(BOOL)animated {

    [super viewWillDisappear:animated];

    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        [[self blurOnPBScreen] setAlpha:1];
    } completion:nil];

}

- (void)postNotifakeation {

    [self.view endEditing:YES];

    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"dr.erast.notifakepreferences"];
    UIApplication *application = [UIApplication sharedApplication];

    double delay = [[prefs objectForKey: @"NTFNotificationDelay"] doubleValue];

    __block UIBackgroundTaskIdentifier backgroundTaskID = [application beginBackgroundTaskWithName:@"BackgroundTask" expirationHandler:^{
        [application endBackgroundTask:backgroundTaskID];
        backgroundTaskID = UIBackgroundTaskInvalid;
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        [NSThread sleepForTimeInterval:delay];
        [self timerCompletion];


        [application endBackgroundTask:backgroundTaskID];
        backgroundTaskID = UIBackgroundTaskInvalid;
    });
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    tableView.tableHeaderView = [self PBHeaderView];
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    return [super tableView:tableView cellForRowAtIndexPath:indexPath];

}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView.contentOffset.y > 21.5) {
        [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            [[self navigationTitleLabel] setAlpha:1];
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            [[self navigationTitleLabel] setAlpha:0];
        } completion:nil];
    }
    __notifake_remote_log([NSString stringWithFormat:@"%f", scrollView.contentOffset.y]);
}

-(void)timerCompletion {
    CFStringRef notificationName = CFSTR("dr.erast.showNotifake/buttonpressed");
    CFNotificationCenterRef notificationCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(notificationCenter, notificationName, NULL, NULL, true);
}

- (void)goGH {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/MatoiDev"] options:@{} completionHandler:nil];
}

- (void)goTG {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://t.me/Uncle_Milty"] options:@{} completionHandler:nil];
}

@end
