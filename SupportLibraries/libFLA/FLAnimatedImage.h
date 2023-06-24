//
//  FLAnimatedImage.h
//  Flipboard
//
//  Created by Raphael Schaad on 7/8/13.
//  Copyright (c) Flipboard. All rights reserved.
//


#import <UIKit/UIKit.h>

#import "FLAnimatedImageView.h"

#ifndef NS_DESIGNATED_INITIALIZER
    #if __has_attribute(objc_designated_initializer)
        #define NS_DESIGNATED_INITIALIZER __attribute((objc_designated_initializer))
    #else
        #define NS_DESIGNATED_INITIALIZER
    #endif
#endif

extern const NSTimeInterval kFLAnimatedImageDelayTimeIntervalMinimum;

@interface FLAnimatedImage : NSObject

@property (nonatomic, strong, readonly) UIImage *posterImage;
@property (nonatomic, assign, readonly) CGSize size;

@property (nonatomic, assign, readonly) NSUInteger loopCount;
@property (nonatomic, strong, readonly) NSDictionary *delayTimesForIndexes;
@property (nonatomic, assign, readonly) NSUInteger frameCount;

@property (nonatomic, assign, readonly) NSUInteger frameCacheSizeCurrent;
@property (nonatomic, assign) NSUInteger frameCacheSizeMax;

- (UIImage *)imageLazilyCachedAtIndex:(NSUInteger)index;

+ (CGSize)sizeForImage:(id)image;

- (instancetype)initWithAnimatedGIFData:(NSData *)data;
- (instancetype)initWithAnimatedGIFData:(NSData *)data optimalFrameCacheSize:(NSUInteger)optimalFrameCacheSize predrawingEnabled:(BOOL)isPredrawingEnabled NS_DESIGNATED_INITIALIZER;
+ (instancetype)animatedImageWithGIFData:(NSData *)data;

@property (nonatomic, strong, readonly) NSData *data;

@end

typedef NS_ENUM(NSUInteger, FLLogLevel) {
    FLLogLevelNone = 0,
    FLLogLevelError,
    FLLogLevelWarn,
    FLLogLevelInfo,
    FLLogLevelDebug,
    FLLogLevelVerbose
};

@interface FLAnimatedImage (Logging)

+ (void)setLogBlock:(void (^)(NSString *logString, FLLogLevel logLevel))logBlock logLevel:(FLLogLevel)logLevel;
+ (void)logStringFromBlock:(NSString *(^)(void))stringBlock withLevel:(FLLogLevel)level;

@end

#define FLLog(logLevel, format, ...) [FLAnimatedImage logStringFromBlock:^NSString *{ return [NSString stringWithFormat:(format), ## __VA_ARGS__]; } withLevel:(logLevel)]

@interface FLWeakProxy : NSProxy

+ (instancetype)weakProxyForObject:(id)targetObject;

@end
