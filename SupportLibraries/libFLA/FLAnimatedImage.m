//
//  FLAnimatedImage.m
//  Flipboard
//
//  Created by Raphael Schaad on 7/8/13.
//  Copyright (c) Flipboard. All rights reserved.
//


#import "FLAnimatedImage.h"
#import <ImageIO/ImageIO.h>
#if __has_include(<MobileCoreServices/MobileCoreServices.h>)
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif


#ifndef BYTE_SIZE
    #define BYTE_SIZE 8
#endif

#define MEGABYTE (1024 * 1024)

const NSTimeInterval kFLAnimatedImageDelayTimeIntervalMinimum = 0.02;

typedef NS_ENUM(NSUInteger, FLAnimatedImageDataSizeCategory) {
    FLAnimatedImageDataSizeCategoryAll = 10,
    FLAnimatedImageDataSizeCategoryDefault = 75,
    FLAnimatedImageDataSizeCategoryOnDemand = 250,
    FLAnimatedImageDataSizeCategoryUnsupported
};

typedef NS_ENUM(NSUInteger, FLAnimatedImageFrameCacheSize) {
    FLAnimatedImageFrameCacheSizeNoLimit = 0,
    FLAnimatedImageFrameCacheSizeLowMemory = 1,
    FLAnimatedImageFrameCacheSizeGrowAfterMemoryWarning = 2,
    FLAnimatedImageFrameCacheSizeDefault = 5
};


#if defined(DEBUG) && DEBUG
@protocol FLAnimatedImageDebugDelegate <NSObject>
@optional
- (void)debug_animatedImage:(FLAnimatedImage *)animatedImage didUpdateCachedFrames:(NSIndexSet *)indexesOfFramesInCache;
- (void)debug_animatedImage:(FLAnimatedImage *)animatedImage didRequestCachedFrame:(NSUInteger)index;
- (CGFloat)debug_animatedImagePredrawingSlowdownFactor:(FLAnimatedImage *)animatedImage;
@end
#endif


@interface FLAnimatedImage ()

@property (nonatomic, assign, readonly) NSUInteger frameCacheSizeOptimal;
@property (nonatomic, assign, readonly, getter=isPredrawingEnabled) BOOL predrawingEnabled;
@property (nonatomic, assign) NSUInteger frameCacheSizeMaxInternal;
@property (nonatomic, assign) NSUInteger requestedFrameIndex;
@property (nonatomic, assign, readonly) NSUInteger posterImageFrameIndex;
@property (nonatomic, strong, readonly) NSMutableDictionary *cachedFramesForIndexes;
@property (nonatomic, strong, readonly) NSMutableIndexSet *cachedFrameIndexes;
@property (nonatomic, strong, readonly) NSMutableIndexSet *requestedFrameIndexes;
@property (nonatomic, strong, readonly) NSIndexSet *allFramesIndexSet;
@property (nonatomic, assign) NSUInteger memoryWarningCount;
@property (nonatomic, strong, readonly) dispatch_queue_t serialQueue;
@property (nonatomic, strong, readonly) __attribute__((NSObject)) CGImageSourceRef imageSource;

@property (nonatomic, strong, readonly) FLAnimatedImage *weakProxy;

#if defined(DEBUG) && DEBUG
@property (nonatomic, weak) id<FLAnimatedImageDebugDelegate> debug_delegate;
#endif

@end

static NSHashTable *allAnimatedImagesWeak;

@implementation FLAnimatedImage

#pragma mark - Accessors
#pragma mark Public

- (NSUInteger)frameCacheSizeCurrent
{
    NSUInteger frameCacheSizeCurrent = self.frameCacheSizeOptimal;
    
    if (self.frameCacheSizeMax > FLAnimatedImageFrameCacheSizeNoLimit) {
        frameCacheSizeCurrent = MIN(frameCacheSizeCurrent, self.frameCacheSizeMax);
    }
    
    if (self.frameCacheSizeMaxInternal > FLAnimatedImageFrameCacheSizeNoLimit) {
        frameCacheSizeCurrent = MIN(frameCacheSizeCurrent, self.frameCacheSizeMaxInternal);
    }
    
    return frameCacheSizeCurrent;
}


- (void)setFrameCacheSizeMax:(NSUInteger)frameCacheSizeMax
{
    if (_frameCacheSizeMax != frameCacheSizeMax) {
        const BOOL willFrameCacheSizeShrink = (frameCacheSizeMax < self.frameCacheSizeCurrent);
        _frameCacheSizeMax = frameCacheSizeMax;
        if (willFrameCacheSizeShrink) { [self purgeFrameCacheIfNeeded]; }
    }
}


#pragma mark Private

- (void)setFrameCacheSizeMaxInternal:(NSUInteger)frameCacheSizeMaxInternal
{
    if (_frameCacheSizeMaxInternal != frameCacheSizeMaxInternal) {
        
        BOOL willFrameCacheSizeShrink = (frameCacheSizeMaxInternal < self.frameCacheSizeCurrent);
        
        _frameCacheSizeMaxInternal = frameCacheSizeMaxInternal;
        
        if (willFrameCacheSizeShrink) { [self purgeFrameCacheIfNeeded]; }
    }
}


#pragma mark - Life Cycle

+ (void)initialize
{
    if (self == [FLAnimatedImage class]) {
        allAnimatedImagesWeak = [NSHashTable weakObjectsHashTable];
        
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSAssert([NSThread isMainThread], @"Received memory warning on non-main thread");
            NSArray *images = nil;
            @synchronized(allAnimatedImagesWeak) {
                images = [[allAnimatedImagesWeak allObjects] copy];
            }
            [images makeObjectsPerformSelector:@selector(didReceiveMemoryWarning:) withObject:note];
        }];
    }
}


- (instancetype)init
{
    FLAnimatedImage *_Nullable const animatedImage = [self initWithAnimatedGIFData:nil];
    if (!animatedImage) {
        FLLog(FLLogLevelError, @"Use `-initWithAnimatedGIFData:` and supply the animated GIF data as an argument to initialize an object of type `FLAnimatedImage`.");
    }
    return animatedImage;
}


- (instancetype)initWithAnimatedGIFData:(NSData *)data
{
    return [self initWithAnimatedGIFData:data optimalFrameCacheSize:0 predrawingEnabled:YES];
}

- (instancetype)initWithAnimatedGIFData:(NSData *)data optimalFrameCacheSize:(NSUInteger)optimalFrameCacheSize predrawingEnabled:(BOOL)isPredrawingEnabled
{
    // Early return if no data supplied!
    const BOOL hasData = (data.length > 0);
    if (!hasData) {
        FLLog(FLLogLevelError, @"No animated GIF data supplied.");
        return nil;
    }
    
    self = [super init];
    if (self) {
        _data = data;
        _predrawingEnabled = isPredrawingEnabled;
        _cachedFramesForIndexes = [[NSMutableDictionary alloc] init];
        _cachedFrameIndexes = [[NSMutableIndexSet alloc] init];
        _requestedFrameIndexes = [[NSMutableIndexSet alloc] init];
        _imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data,
                                                   (__bridge CFDictionaryRef)@{(NSString *)kCGImageSourceShouldCache: @NO});
        if (!_imageSource) {
            FLLog(FLLogLevelError, @"Failed to `CGImageSourceCreateWithData` for animated GIF data %@", data);
            return nil;
        }
        
        const CFStringRef _Nullable imageSourceContainerType = CGImageSourceGetType(_imageSource);
        const BOOL isGIFData = imageSourceContainerType ? UTTypeConformsTo(imageSourceContainerType, kUTTypeGIF) : NO;
        if (!isGIFData) {
            FLLog(FLLogLevelError, @"Supplied data is of type %@ and doesn't seem to be GIF data %@", imageSourceContainerType, data);
            return nil;
        }
        NSDictionary *_Nullable const imageProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyProperties(_imageSource, NULL);
        _loopCount = [[[imageProperties objectForKey:(id)kCGImagePropertyGIFDictionary] objectForKey:(id)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
        
        const size_t imageCount = CGImageSourceGetCount(_imageSource);
        NSUInteger skippedFrameCount = 0;
        NSMutableDictionary *const delayTimesForIndexesMutable = [NSMutableDictionary dictionaryWithCapacity:imageCount];
        for (size_t i = 0; i < imageCount; i++) {
            @autoreleasepool {
                const CGImageRef _Nullable frameImageRef = CGImageSourceCreateImageAtIndex(_imageSource, i, NULL);
                if (frameImageRef) {
                    UIImage *frameImage = [UIImage imageWithCGImage:frameImageRef];
                    if (frameImage) {
                        if (!self.posterImage) {
                            _posterImage = frameImage;
                            _size = _posterImage.size;
                            _posterImageFrameIndex = i;
                            [self.cachedFramesForIndexes setObject:self.posterImage forKey:@(self.posterImageFrameIndex)];
                            [self.cachedFrameIndexes addIndex:self.posterImageFrameIndex];
                        }
                        NSDictionary *_Nullable const frameProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(_imageSource, i, NULL);
                        NSDictionary *_Nullable const framePropertiesGIF = [frameProperties objectForKey:(id)kCGImagePropertyGIFDictionary];
                        NSNumber *_Nullable delayTime = [framePropertiesGIF objectForKey:(id)kCGImagePropertyGIFUnclampedDelayTime];
                        if (delayTime == nil) {
                            delayTime = [framePropertiesGIF objectForKey:(id)kCGImagePropertyGIFDelayTime];
                        }
                        const NSTimeInterval kDelayTimeIntervalDefault = 0.1;
                        if (delayTime == nil) {
                            if (i == 0) {
                                FLLog(FLLogLevelInfo, @"Falling back to default delay time for first frame %@ because none found in GIF properties %@", frameImage, frameProperties);
                                delayTime = @(kDelayTimeIntervalDefault);
                            } else {
                                FLLog(FLLogLevelInfo, @"Falling back to preceding delay time for frame %zu %@ because none found in GIF properties %@", i, frameImage, frameProperties);
                                delayTime = delayTimesForIndexesMutable[@(i - 1)];
                            }
                        }
                        if ([delayTime floatValue] < ((float)kFLAnimatedImageDelayTimeIntervalMinimum - FLT_EPSILON)) {
                            FLLog(FLLogLevelInfo, @"Rounding frame %zu's `delayTime` from %f up to default %f (minimum supported: %f).", i, [delayTime floatValue], kDelayTimeIntervalDefault, kFLAnimatedImageDelayTimeIntervalMinimum);
                            delayTime = @(kDelayTimeIntervalDefault);
                        }
                        delayTimesForIndexesMutable[@(i)] = delayTime;
                    } else {
                        skippedFrameCount++;
                        FLLog(FLLogLevelInfo, @"Dropping frame %zu because valid `CGImageRef` %@ did result in `nil`-`UIImage`.", i, frameImageRef);
                    }
                    CFRelease(frameImageRef);
                } else {
                    skippedFrameCount++;
                    FLLog(FLLogLevelInfo, @"Dropping frame %zu because failed to `CGImageSourceCreateImageAtIndex` with image source %@", i, self->_imageSource);
                }
            }
        }
        _delayTimesForIndexes = [delayTimesForIndexesMutable copy];
        _frameCount = imageCount;
        
        if (self.frameCount == 0) {
            FLLog(FLLogLevelInfo, @"Failed to create any valid frames for GIF with properties %@", imageProperties);
            return nil;
        } else if (self.frameCount == 1) {
            FLLog(FLLogLevelInfo, @"Created valid GIF but with only a single frame. Image properties: %@", imageProperties);
        }
        
        if (optimalFrameCacheSize == 0) {
            const CGFloat animatedImageDataSize = (CGFloat)CGImageGetBytesPerRow(self.posterImage.CGImage) * self.size.height * (CGFloat)(self.frameCount - skippedFrameCount) / (CGFloat)MEGABYTE;
            if (animatedImageDataSize <= FLAnimatedImageDataSizeCategoryAll) {
                _frameCacheSizeOptimal = self.frameCount;
            } else if (animatedImageDataSize <= FLAnimatedImageDataSizeCategoryDefault) {
                _frameCacheSizeOptimal = FLAnimatedImageFrameCacheSizeDefault;
            } else {
                _frameCacheSizeOptimal = FLAnimatedImageFrameCacheSizeLowMemory;
            }
        } else {
            _frameCacheSizeOptimal = optimalFrameCacheSize;
        }
        _frameCacheSizeOptimal = MIN(_frameCacheSizeOptimal, self.frameCount);
        _allFramesIndexSet = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, self.frameCount)];
        _weakProxy = (id)[FLWeakProxy weakProxyForObject:self];
        @synchronized(allAnimatedImagesWeak) {
            [allAnimatedImagesWeak addObject:self];
        }
    }
    return self;
}


+ (instancetype)animatedImageWithGIFData:(NSData *)data
{
    FLAnimatedImage *const animatedImage = [[FLAnimatedImage alloc] initWithAnimatedGIFData:data];
    return animatedImage;
}


- (void)dealloc
{
    if (_weakProxy) {
        [NSObject cancelPreviousPerformRequestsWithTarget:_weakProxy];
    }
    
    if (_imageSource) {
        CFRelease(_imageSource);
    }
}


#pragma mark - Public Methods

- (UIImage *)imageLazilyCachedAtIndex:(NSUInteger)index
{
    if (index >= self.frameCount) {
        FLLog(FLLogLevelWarn, @"Skipping requested frame %lu beyond bounds (total frame count: %lu) for animated image: %@", (unsigned long)index, (unsigned long)self.frameCount, self);
        return nil;
    }
    self.requestedFrameIndex = index;
#if defined(DEBUG) && DEBUG
    if ([self.debug_delegate respondsToSelector:@selector(debug_animatedImage:didRequestCachedFrame:)]) {
        [self.debug_delegate debug_animatedImage:self didRequestCachedFrame:index];
    }
#endif
    
    if ([self.cachedFrameIndexes count] < self.frameCount) {
        NSMutableIndexSet *frameIndexesToAddToCacheMutable = [self frameIndexesToCache];
        [frameIndexesToAddToCacheMutable removeIndexes:self.cachedFrameIndexes];
        [frameIndexesToAddToCacheMutable removeIndexes:self.requestedFrameIndexes];
        [frameIndexesToAddToCacheMutable removeIndex:self.posterImageFrameIndex];
        NSIndexSet *frameIndexesToAddToCache = [frameIndexesToAddToCacheMutable copy];
        
        if ([frameIndexesToAddToCache count] > 0) {
            [self addFrameIndexesToCache:frameIndexesToAddToCache];
        }
    }
    
    UIImage *const image = self.cachedFramesForIndexes[@(index)];
    
    [self purgeFrameCacheIfNeeded];
    
    return image;
}


- (void)addFrameIndexesToCache:(NSIndexSet *)frameIndexesToAddToCache
{
    const NSRange firstRange = NSMakeRange(self.requestedFrameIndex, self.frameCount - self.requestedFrameIndex);
    const NSRange secondRange = NSMakeRange(0, self.requestedFrameIndex);
    if (firstRange.length + secondRange.length != self.frameCount) {
        FLLog(FLLogLevelWarn, @"Two-part frame cache range doesn't equal full range.");
    }
    
    [self.requestedFrameIndexes addIndexes:frameIndexesToAddToCache];
    
    if (!self.serialQueue) {
        _serialQueue = dispatch_queue_create("com.flipboard.framecachingqueue", DISPATCH_QUEUE_SERIAL);
    }
    
    __weak __typeof(self) weakSelf = self;
    dispatch_async(self.serialQueue, ^{
        void (^frameRangeBlock)(NSRange, BOOL *) = ^(NSRange range, BOOL *stop) {
            for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
#if defined(DEBUG) && DEBUG
                const CFTimeInterval predrawBeginTime = CACurrentMediaTime();
#endif
                UIImage *const image = [weakSelf imageAtIndex:i];
#if defined(DEBUG) && DEBUG
                const CFTimeInterval predrawDuration = CACurrentMediaTime() - predrawBeginTime;
                CFTimeInterval slowdownDuration = 0.0;
                if ([self.debug_delegate respondsToSelector:@selector(debug_animatedImagePredrawingSlowdownFactor:)]) {
                    CGFloat predrawingSlowdownFactor = [self.debug_delegate debug_animatedImagePredrawingSlowdownFactor:self];
                    slowdownDuration = predrawDuration * predrawingSlowdownFactor - predrawDuration;
                    [NSThread sleepForTimeInterval:slowdownDuration];
                }
                FLLog(FLLogLevelVerbose, @"Predrew frame %lu in %f ms for animated image: %@", (unsigned long)i, (predrawDuration + slowdownDuration) * 1000, self);
#endif
                if (image && weakSelf) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        weakSelf.cachedFramesForIndexes[@(i)] = image;
                        [weakSelf.cachedFrameIndexes addIndex:i];
                        [weakSelf.requestedFrameIndexes removeIndex:i];
#if defined(DEBUG) && DEBUG
                        if ([weakSelf.debug_delegate respondsToSelector:@selector(debug_animatedImage:didUpdateCachedFrames:)]) {
                            [weakSelf.debug_delegate debug_animatedImage:weakSelf didUpdateCachedFrames:weakSelf.cachedFrameIndexes];
                        }
#endif
                    });
                }
            }
        };
        
        [frameIndexesToAddToCache enumerateRangesInRange:firstRange options:0 usingBlock:frameRangeBlock];
        [frameIndexesToAddToCache enumerateRangesInRange:secondRange options:0 usingBlock:frameRangeBlock];
    });
}


+ (CGSize)sizeForImage:(id)image
{
    CGSize imageSize = CGSizeZero;
    
    if (!image) {
        return imageSize;
    }
    
    if ([image isKindOfClass:[UIImage class]]) {
        UIImage *const uiImage = (UIImage *)image;
        imageSize = uiImage.size;
    } else if ([image isKindOfClass:[FLAnimatedImage class]]) {
        FLAnimatedImage *const animatedImage = (FLAnimatedImage *)image;
        imageSize = animatedImage.size;
    } else {
        FLLog(FLLogLevelError, @"`image` isn't of expected types `UIImage` or `FLAnimatedImage`: %@", image);
    }
    
    return imageSize;
}


#pragma mark - Private Methods
#pragma mark Frame Loading

- (UIImage *)imageAtIndex:(NSUInteger)index
{
    const CGImageRef _Nullable imageRef = CGImageSourceCreateImageAtIndex(_imageSource, index, NULL);

    if (!imageRef) {
        return nil;
    }

    UIImage *image = [UIImage imageWithCGImage:imageRef];
    CFRelease(imageRef);
    
    if (self.isPredrawingEnabled) {
        image = [[self class] predrawnImageFromImage:image];
    }
    
    return image;
}


#pragma mark Frame Caching

- (NSMutableIndexSet *)frameIndexesToCache
{
    NSMutableIndexSet *indexesToCache = nil;
    if (self.frameCacheSizeCurrent == self.frameCount) {
        indexesToCache = [self.allFramesIndexSet mutableCopy];
    } else {
        indexesToCache = [[NSMutableIndexSet alloc] init];
        const NSUInteger firstLength = MIN(self.frameCacheSizeCurrent, self.frameCount - self.requestedFrameIndex);
        const NSRange firstRange = NSMakeRange(self.requestedFrameIndex, firstLength);
        [indexesToCache addIndexesInRange:firstRange];
        const NSUInteger secondLength = self.frameCacheSizeCurrent - firstLength;
        if (secondLength > 0) {
            NSRange secondRange = NSMakeRange(0, secondLength);
            [indexesToCache addIndexesInRange:secondRange];
        }
        if ([indexesToCache count] != self.frameCacheSizeCurrent) {
            FLLog(FLLogLevelWarn, @"Number of frames to cache doesn't equal expected cache size.");
        }
        
        [indexesToCache addIndex:self.posterImageFrameIndex];
    }
    
    return indexesToCache;
}


- (void)purgeFrameCacheIfNeeded
{
    if ([self.cachedFrameIndexes count] > self.frameCacheSizeCurrent) {
        NSMutableIndexSet *indexesToPurge = [self.cachedFrameIndexes mutableCopy];
        [indexesToPurge removeIndexes:[self frameIndexesToCache]];
        [indexesToPurge enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
            for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
                [self.cachedFrameIndexes removeIndex:i];
                [self.cachedFramesForIndexes removeObjectForKey:@(i)];
#if defined(DEBUG) && DEBUG
                if ([self.debug_delegate respondsToSelector:@selector(debug_animatedImage:didUpdateCachedFrames:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.debug_delegate debug_animatedImage:self didUpdateCachedFrames:self.cachedFrameIndexes];
                    });
                }
#endif
            }
        }];
    }
}


- (void)growFrameCacheSizeAfterMemoryWarning:(NSNumber *)frameCacheSize
{
    self.frameCacheSizeMaxInternal = [frameCacheSize unsignedIntegerValue];
    FLLog(FLLogLevelDebug, @"Grew frame cache size max to %lu after memory warning for animated image: %@", (unsigned long)self.frameCacheSizeMaxInternal, self);
    
    const NSTimeInterval kResetDelay = 3.0;
    [self.weakProxy performSelector:@selector(resetFrameCacheSizeMaxInternal) withObject:nil afterDelay:kResetDelay];
}


- (void)resetFrameCacheSizeMaxInternal
{
    self.frameCacheSizeMaxInternal = FLAnimatedImageFrameCacheSizeNoLimit;
    FLLog(FLLogLevelDebug, @"Reset frame cache size max (current frame cache size: %lu) for animated image: %@", (unsigned long)self.frameCacheSizeCurrent, self);
}


#pragma mark System Memory Warnings Notification Handler

- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
    self.memoryWarningCount++;
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self.weakProxy selector:@selector(growFrameCacheSizeAfterMemoryWarning:) object:@(FLAnimatedImageFrameCacheSizeGrowAfterMemoryWarning)];
    [NSObject cancelPreviousPerformRequestsWithTarget:self.weakProxy selector:@selector(resetFrameCacheSizeMaxInternal) object:nil];
    

    FLLog(FLLogLevelDebug, @"Attempt setting frame cache size max to %lu (previous was %lu) after memory warning #%lu for animated image: %@", (unsigned long)FLAnimatedImageFrameCacheSizeLowMemory, (unsigned long)self.frameCacheSizeMaxInternal, (unsigned long)self.memoryWarningCount, self);
    self.frameCacheSizeMaxInternal = FLAnimatedImageFrameCacheSizeLowMemory;
    
    const NSUInteger kGrowAttemptsMax = 2;
    const NSTimeInterval kGrowDelay = 2.0;
    if ((self.memoryWarningCount - 1) <= kGrowAttemptsMax) {
        [self.weakProxy performSelector:@selector(growFrameCacheSizeAfterMemoryWarning:) withObject:@(FLAnimatedImageFrameCacheSizeGrowAfterMemoryWarning) afterDelay:kGrowDelay];
    }
    
    
}


#pragma mark Image Decoding

+ (UIImage *)predrawnImageFromImage:(UIImage *)imageToPredraw
{

    const CGColorSpaceRef _Nullable colorSpaceDeviceRGBRef = CGColorSpaceCreateDeviceRGB();
    if (!colorSpaceDeviceRGBRef) {
        FLLog(FLLogLevelError, @"Failed to `CGColorSpaceCreateDeviceRGB` for image %@", imageToPredraw);
        return imageToPredraw;
    }

    const size_t numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpaceDeviceRGBRef) + 1; // 4: RGB + A

    void *_Nullable data = NULL;
    const size_t width = imageToPredraw.size.width;
    const size_t height = imageToPredraw.size.height;
    const size_t bitsPerComponent = CHAR_BIT;
    
    const size_t bitsPerPixel = (bitsPerComponent * numberOfComponents);
    const size_t bytesPerPixel = (bitsPerPixel / BYTE_SIZE);
    const size_t bytesPerRow = (bytesPerPixel * width);
    
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(imageToPredraw.CGImage);
    
    if (alphaInfo == kCGImageAlphaNone || alphaInfo == kCGImageAlphaOnly) {
        alphaInfo = kCGImageAlphaNoneSkipFirst;
    } else if (alphaInfo == kCGImageAlphaFirst) {
        alphaInfo = kCGImageAlphaPremultipliedFirst;
    } else if (alphaInfo == kCGImageAlphaLast) {
        alphaInfo = kCGImageAlphaPremultipliedLast;
    }
    bitmapInfo |= alphaInfo;

    const CGContextRef _Nullable bitmapContextRef = CGBitmapContextCreate(data, width, height, bitsPerComponent, bytesPerRow, colorSpaceDeviceRGBRef, bitmapInfo);
    CGColorSpaceRelease(colorSpaceDeviceRGBRef);

    if (!bitmapContextRef) {
        FLLog(FLLogLevelError, @"Failed to `CGBitmapContextCreate` with color space %@ and parameters (width: %zu height: %zu bitsPerComponent: %zu bytesPerRow: %zu) for image %@", colorSpaceDeviceRGBRef, width, height, bitsPerComponent, bytesPerRow, imageToPredraw);
        return imageToPredraw;
    }
    
    CGContextDrawImage(bitmapContextRef, CGRectMake(0.0, 0.0, imageToPredraw.size.width, imageToPredraw.size.height), imageToPredraw.CGImage);
    const CGImageRef _Nullable predrawnImageRef = CGBitmapContextCreateImage(bitmapContextRef);
    UIImage *_Nullable predrawnImage = predrawnImageRef ? [UIImage imageWithCGImage:predrawnImageRef scale:imageToPredraw.scale orientation:imageToPredraw.imageOrientation] : nil;
    CGImageRelease(predrawnImageRef);
    CGContextRelease(bitmapContextRef);
    
    if (!predrawnImage) {
        FLLog(FLLogLevelError, @"Failed to `imageWithCGImage:scale:orientation:` with image ref %@ created with color space %@ and bitmap context %@ and properties and properties (scale: %f orientation: %ld) for image %@", predrawnImageRef, colorSpaceDeviceRGBRef, bitmapContextRef, imageToPredraw.scale, (long)imageToPredraw.imageOrientation, imageToPredraw);
        return imageToPredraw;
    }
    
    return predrawnImage;
}


#pragma mark - Description

- (NSString *)description
{
    NSString *description = [super description];
    
    description = [description stringByAppendingFormat:@" size=%@", NSStringFromCGSize(self.size)];
    description = [description stringByAppendingFormat:@" frameCount=%lu", (unsigned long)self.frameCount];
    
    return description;
}


@end

#pragma mark - Logging

@implementation FLAnimatedImage (Logging)

static void (^_logBlock)(NSString *logString, FLLogLevel logLevel) = nil;
static FLLogLevel _logLevel;

+ (void)setLogBlock:(void (^_Nullable)(NSString *logString, FLLogLevel logLevel))logBlock logLevel:(FLLogLevel)logLevel
{
    _logBlock = [logBlock copy];
    _logLevel = logLevel;
}

+ (void)logStringFromBlock:(NSString *(^_Nullable)(void))stringBlock withLevel:(FLLogLevel)level
{
    if (level <= _logLevel && _logBlock && stringBlock) {
        _logBlock(stringBlock(), level);
    }
}

@end


#pragma mark - FLWeakProxy

@interface FLWeakProxy ()

@property (nonatomic, weak) id target;

@end


@implementation FLWeakProxy

#pragma mark Life Cycle

+ (instancetype)weakProxyForObject:(id)targetObject
{
    FLWeakProxy *weakProxy = [FLWeakProxy alloc];
    weakProxy.target = targetObject;
    return weakProxy;
}


#pragma mark Forwarding Messages

- (id)forwardingTargetForSelector:(SEL)selector
{
    return _target;
}


#pragma mark - NSWeakProxy Method Overrides
#pragma mark Handling Unimplemented Methods

- (void)forwardInvocation:(NSInvocation *)invocation
{
    void *_Nullable nullPointer = NULL;
    [invocation setReturnValue:&nullPointer];
}


- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    return [NSObject instanceMethodSignatureForSelector:@selector(init)];
}


@end
