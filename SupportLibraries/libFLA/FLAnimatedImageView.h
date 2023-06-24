//
//  FLAnimatedImageView.h
//  Flipboard
//
//  Created by Raphael Schaad on 7/8/13.
//  Copyright (c) Flipboard. All rights reserved.
//


#import <UIKit/UIKit.h>

@class FLAnimatedImage;
@protocol FLAnimatedImageViewDebugDelegate;

@interface FLAnimatedImageView : UIImageView

@property (nonatomic, strong) FLAnimatedImage *animatedImage;
@property (nonatomic, copy) void(^loopCompletionBlock)(NSUInteger loopCountRemaining);

@property (nonatomic, strong, readonly) UIImage *currentFrame;
@property (nonatomic, assign, readonly) NSUInteger currentFrameIndex;

@property (nonatomic, copy) NSRunLoopMode runLoopMode;

@end
