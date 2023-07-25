#import "Notifake.h"
#import "libactivator-headers/libactivator.h"

static BOOL isDelayedNotificationEnabled = NO;
static NSString* SCtext = nil;
static NSString *bundleID = @"com.apple.Preferences";
static NSString *title = @"";
static NSString *content = @"";


static void __notifake_remote_log(NSString *text) {

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];

    RLog(@"%@: %@", dateString, text);

}

static void loadPrefs()
{
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"dr.erast.notifakepreferences"];
    if(prefs)
    {
        __notifake_remote_log(@"Preference changed!");
        isDelayedNotificationEnabled = [([prefs objectForKey:@"enableDelayedNotification"] ?: @(false)) boolValue];
        bundleID = [prefs objectForKey:@"selectedAppID"];
        title = [prefs objectForKey: @"NTFNotificationTitle"];
        content = [prefs objectForKey: @"NTFNotificationContent"];
    }

    __notifake_remote_log([NSString stringWithFormat: @"Title: %@\nContent: %@\nBundle: %@", title, content, bundleID]);
}


static void showNotif() {
    __notifake_remote_log(@"Trigger!");
    loadPrefs();
    if (isDelayedNotificationEnabled) {
        [[objc_getClass("JBBulletinManager") sharedInstance] showBulletinWithTitle:title
                                                                           message:content
                                                                          bundleID:bundleID];
    }
    __notifake_remote_log([NSString stringWithFormat: @"Title: %@\nContent: %@\nBundle: %@", title, content, bundleID]);

}


@interface NotifActivatorListener : NSObject<LAListener>
@end

@implementation NotifActivatorListener

-(void)activator:(LAActivator *)activator receiveEvent:(LAEvent *)event {

    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"dr.erast.notifakepreferences"];
    UIApplication *application = [UIApplication sharedApplication];

    double delay = [[prefs objectForKey: @"NTFNotificationDelay"] doubleValue];

    __block UIBackgroundTaskIdentifier backgroundTaskID = [application beginBackgroundTaskWithName:@"BackgroundTask" expirationHandler:^{
        [application endBackgroundTask:backgroundTaskID];
        backgroundTaskID = UIBackgroundTaskInvalid;
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        [NSThread sleepForTimeInterval:delay];
        showNotif();

        [application endBackgroundTask:backgroundTaskID];
        backgroundTaskID = UIBackgroundTaskInvalid;
    });

}

+(void)load {
    [[%c(LAActivator) sharedInstance] registerListener:[self new] forName:@"dr.erast.notifake.listener"];
}
@end



%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)showNotif, CFSTR("dr.erast.showNotifake/buttonpressed"), NULL, CFNotificationSuspensionBehaviorCoalesce);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("dr.erast.notifake/prefschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
    loadPrefs();
}