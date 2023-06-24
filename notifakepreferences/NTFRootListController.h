#import "AltList.h"
#include <RemoteLog.h>
#import "imports.h"
#import "JBBulletinManager.h"
#import "../SupportLibraries/lottie/Lottie.h"

@interface NTFRootListController : PSListController

@property(nonatomic, retain)UIView* PBHeaderView;
@property(nonatomic, retain)UIImageView* PBHeaderImageView;
@property(nonatomic, retain)UIBlurEffect* blurEffect;
@property(nonatomic, retain)UIVisualEffectView* blurOnPBScreen;
@property (nonatomic, retain)LOTAnimationView * animation;

@property(nonatomic, retain)UIView * lottieArea;
@property(nonatomic, retain)UILabel * navigationTitleLabel;

- (void)goGH;
- (void)goTG;

-(void)timerCompletion;

@end