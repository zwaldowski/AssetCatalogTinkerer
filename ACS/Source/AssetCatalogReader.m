//
//  AssetCatalogReader.m
//  Asset Catalog Tinkerer
//
//  Created by Guilherme Rambo on 27/03/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

#import "AssetCatalogReader.h"

#import "CoreUI.h"
#import "CoreUI+TV.h"

NSString * const kACSNameKey = @"name";
NSString * const kACSImageKey = @"image";
NSString * const kACSThumbnailKey = @"thumbnail";
NSString * const kACSFilenameKey = @"filename";
NSString * const kACSPNGDataKey = @"png";
NSString * const kACSImageRepKey = @"imagerep";

NSString * const kAssetCatalogReaderErrorDomain = @"br.com.guilhermerambo.AssetCatalogReader";

@interface AssetCatalogReader ()

@property (nonatomic, copy) NSURL *fileURL;

// These properties are set when the read is initiated by a call to `resourceConstrainedReadWithMaxCount`
@property (nonatomic, getter=isResourceConstrained) BOOL resourceConstrained;
@property (nonatomic) int64_t maxCount;

@property (nonatomic) NSMutableArray *loadedCatalogs;

@end

@implementation AssetCatalogReader
{
    BOOL _computedCatalogHasRetinaContent;
    BOOL _catalogHasRetinaContent;
}

- (instancetype)initWithFileURL:(NSURL *)URL
{
    self = [super init];
    
    _ignorePackedAssets = YES;
    _fileURL = [URL copy];
    _loadedCatalogs = [[NSMutableArray alloc] init];
    
    return self;
}

- (NSProgress *)resourceConstrainedReadWithMaxCount:(int64_t)max completionHandler:(AssetCatalogReaderCompletionHandler)callback {
    self.resourceConstrained = YES;
    self.maxCount = max;

    return [self readWithCompletionHandler:callback];
}

- (NSProgress *)readWithCompletionHandler:(AssetCatalogReaderCompletionHandler)callback {
    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:-1];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSURL *catalogURL = self.fileURL;
        if (!self.resourceConstrained) {
            // we need to figure out if the user selected an app bundle or a specific .car file
            NSBundle *bundle = [NSBundle bundleWithURL:catalogURL];
            if (bundle) {
                catalogURL = [bundle URLForResource:@"Assets" withExtension:@"car"];
            }
        }

        // bundle is nil for some reason
        if (!catalogURL) {
            NSError *error = [NSError errorWithDomain:kAssetCatalogReaderErrorDomain code:kAssetCatalogReaderErrorCouldNotOpenCatalog userInfo:@{NSLocalizedDescriptionKey: @"Unable to find asset catalog path"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                callback(nil, 0, error);
            });
            return;
        }

        if ([self isProThemeStoreAtURL:catalogURL]) {
            NSError *error = [NSError errorWithDomain:kAssetCatalogReaderErrorDomain code:kAssetCatalogReaderErrorIncompatibleCatalog userInfo:@{NSLocalizedDescriptionKey: @"Pro asset catalogs are not supported"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                callback(nil, 0, error);
            });
            return;
        }

        NSError *catalogError;
        CUICatalog *catalog = [[CUICatalog alloc] initWithURL:catalogURL error:&catalogError];
        if (!catalog) {
            dispatch_async(dispatch_get_main_queue(), ^{
                callback(nil, 0, catalogError);
            });
            return;
        }

        if (!self.distinguishCatalogsFromThemeStores || !catalog.allImageNames.count || ![catalog respondsToSelector:@selector(imageWithName:scaleFactor:)]) {
            // CAR is a theme file not an asset catalog
            [self readThemeStore:catalog updatingProgress:progress completionHandler:callback];
        } else {
            [self readCatalog:catalog updatingProgress:progress completionHandler:callback];
        }
    });

    return progress;
}

- (void)readCatalog:(CUICatalog *)catalog updatingProgress:(NSProgress *)progress completionHandler:(AssetCatalogReaderCompletionHandler)callback {
    // limits the total items to be read to the total number of images or the max count set for a resource constrained read
    NSUInteger totalNumberOfAssets = catalog.allImageNames.count;
    int64_t totalItemCount = self.resourceConstrained ? MIN(self.maxCount, totalNumberOfAssets) : totalNumberOfAssets;
    NSMutableArray *mutableImages = [NSMutableArray arrayWithCapacity:totalItemCount];
    NSArray *imageNames = [catalog.allImageNames subarrayWithRange:NSMakeRange(0, totalItemCount)];

    progress.totalUnitCount = totalItemCount;

    __block int hasRetinaContentCacheStatus = -1;
    BOOL(^cachedHasRetinaContent)(void) = ^BOOL{
        if (hasRetinaContentCacheStatus == -1) {
            hasRetinaContentCacheStatus = [self catalogHasRetinaContent:catalog];
        }
        return !!hasRetinaContentCacheStatus;
    };

    for (NSString *imageName in imageNames) {
        for (CUINamedImage *namedImage in [self imagesNamed:imageName fromCatalog:catalog]) {
            if (progress.cancelled) return;

            [progress performAsCurrentWithPendingUnitCount:1 usingBlock:^{ @autoreleasepool {
                if (namedImage == nil || [namedImage isKindOfClass:[CUINamedData class]]) {
                    return;
                }

                NSString *filename;
                CGImageRef image;

                if ([namedImage isKindOfClass:[CUINamedLayerStack class]]) {
                    CUINamedLayerStack *stack = (CUINamedLayerStack *)namedImage;
                    if (!stack.layers.count) {
                        return;
                    }
                    filename = [NSString stringWithFormat:@"%@.png", namedImage.name];
                    image = stack.flattenedImage;
                } else {
                    filename = [self filenameForAssetNamed:namedImage.name scale:namedImage.scale presentationState:kCoreThemeStateNone preservingPathExtension:NO];
                    image = namedImage.image;
                }

                if (!image) {
                    return;
                }

                // when resource constrained and the catalog contains retina images, only load retina images
                if (cachedHasRetinaContent() && self.resourceConstrained && namedImage.scale < 2) {
                    return;
                }

                NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithCGImage:image];
                imageRep.size = namedImage.size;

                NSDictionary *desc = [self imageDescriptionWithName:namedImage.name filename:filename representation:imageRep];
                if (!desc || progress.cancelled) {
                    return;
                }
                [mutableImages addObject:desc];
            }}];
        }
    }

    // we've got no images for some reason (the console will usually contain some information from CoreUI as to why)
    if (!mutableImages.count) {
        NSError *error = [NSError errorWithDomain:kAssetCatalogReaderErrorDomain code:kAssetCatalogReaderErrorNoImagesFound userInfo:@{NSLocalizedDescriptionKey: @"Failed to load images"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(nil, 0, error);
        });
        return;
    }

    NSArray *images = [mutableImages copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.loadedCatalogs addObject:catalog];
        callback(images, totalNumberOfAssets, nil);
    });
}

extern CGDataProviderRef CGPDFDocumentGetDataProvider(CGPDFDocumentRef);

- (void)readThemeStore:(CUICatalog *)catalog updatingProgress:(NSProgress *)progress completionHandler:(AssetCatalogReaderCompletionHandler)callback {
    CUIStructuredThemeStore *themeStore = [catalog _themeStore];
    int64_t realTotalItemCount = themeStore.themeStore.allAssetKeys.count;
    // limits the total items to be read to the total number of images or the max count set for a resource constrained read
    int64_t totalItemCount = self.resourceConstrained ? MIN(_maxCount, realTotalItemCount) : realTotalItemCount;
    NSMutableArray *mutableImages = [NSMutableArray arrayWithCapacity:totalItemCount];
    NSArray *assetKeys = [themeStore.themeStore.allAssetKeys subarrayWithRange:NSMakeRange(0, totalItemCount)];

    progress.totalUnitCount = totalItemCount;

    __block int hasRetinaContentCacheStatus = -1;
    BOOL(^cachedHasRetinaContent)(void) = ^BOOL{
        if (hasRetinaContentCacheStatus == -1) {
            hasRetinaContentCacheStatus = [self catalogHasRetinaContent:catalog];
        }
        return !!hasRetinaContentCacheStatus;
    };

    for (CUIRenditionKey *key in assetKeys) {
        if (progress.cancelled) {
            return;
        }

        [progress performAsCurrentWithPendingUnitCount:1 usingBlock:^{ @autoreleasepool {
            @try {
                CUIThemeRendition *rendition = [themeStore renditionWithKey:key.keyList];

                // when resource constrained and the catalog contains retina images, only load retina images
                if (cachedHasRetinaContent() && self.resourceConstrained && rendition.scale < 2) {
                    return;
                }

                if (self.ignorePackedAssets && [rendition.name containsString:@"ZZPackedAsset"]) {
                    return;
                }

                NSString *filename;
                NSImageRep *imageRep;
                if (rendition.unslicedImage) {
                    filename = [self filenameForAssetNamed:rendition.name scale:rendition.scale presentationState:key.themeState preservingPathExtension:NO];
                    imageRep = [[NSBitmapImageRep alloc] initWithCGImage:rendition.unslicedImage];
                } else if (rendition.pdfDocument) {
                    filename = [self filenameForAssetNamed:rendition.name scale:rendition.scale presentationState:key.themeState preservingPathExtension:YES];

                    CGDataProviderRef dataProvider = CGPDFDocumentGetDataProvider(rendition.pdfDocument);
                    CFDataRef data = CGDataProviderCopyData(dataProvider);
                    imageRep = [[NSPDFImageRep alloc] initWithData:(__bridge_transfer NSData *)data];
                } else {
                    NSLog(@"The rendition %@ doesn't have an image, It is probably an effect or material.", rendition.name);
                }

                if (!filename || !imageRep || progress.cancelled) {
                    return;
                }

                NSDictionary *desc = [self imageDescriptionWithName:rendition.name filename:filename representation:imageRep];
                [mutableImages addObject:desc];
            } @catch (NSException *exception) {
                NSLog(@"Exception while reading theme store: %@", exception);
            }
        }}];
    }

    NSArray *images = [mutableImages copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.loadedCatalogs addObject:catalog];
        callback(images, realTotalItemCount, nil);
    });
}

- (NSImage *)constrainImage:(NSImage *)image toSize:(NSSize)size
{
    if (image.size.width <= size.width && image.size.height <= size.height) return [image copy];
    
    CGFloat newWidth, newHeight = 0;
    double rw = image.size.width / size.width;
    double rh = image.size.height / size.height;
    
    if (rw > rh)
    {
        newHeight = MAX(roundl(image.size.height / rw), 1);
        newWidth = size.width;
    }
    else
    {
        newWidth = MAX(roundl(image.size.width / rh), 1);
        newHeight = size.height;
    }
    
    NSImage *newImage = [[NSImage alloc] initWithSize:NSMakeSize(newWidth, newHeight)];
    [newImage lockFocus];
    [image drawInRect:NSMakeRect(0, 0, newWidth, newHeight) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [newImage unlockFocus];
    
    return newImage;
}

- (BOOL)isProThemeStoreAtURL:(NSURL *)url
{
    static const int proThemeTokenLength = 18;
    static const char proThemeToken[proThemeTokenLength] = { 0x50,0x72,0x6F,0x54,0x68,0x65,0x6D,0x65,0x44,0x65,0x66,0x69,0x6E,0x69,0x74,0x69,0x6F,0x6E };

    @try {
        NSData *catalogData = [[NSData alloc] initWithContentsOfURL:url options:NSDataReadingMappedAlways|NSDataReadingUncached error:nil];

        NSData *proThemeTokenData = [NSData dataWithBytes:(const void *)proThemeToken length:proThemeTokenLength];
        if ([catalogData rangeOfData:proThemeTokenData options:0 range:NSMakeRange(0, catalogData.length)].location != NSNotFound) {
            return YES;
        } else {
            return NO;
        }
    } @catch (NSException *exception) {
        NSLog(@"Unable to determine if catalog is pro, exception: %@", exception);
        return NO;
    }
}

- (NSArray <CUINamedImage *> *)imagesNamed:(NSString *)name fromCatalog:(CUICatalog *)catalog
{
    NSMutableArray <CUINamedImage *> *images = [[NSMutableArray alloc] initWithCapacity:3];

    for (NSNumber *factor in @[@1,@2,@3]) {
        CUINamedImage *image = [catalog imageWithName:name scaleFactor:factor.doubleValue];
        if (!image || image.scale != factor.doubleValue) continue;

        [images addObject:image];
    }

    return images;
}

- (NSDictionary *)imageDescriptionWithName:(NSString *)name filename:(NSString *)filename representation:(NSImageRep *)imageRep
{
    if (_resourceConstrained) {
        return @{
                 kACSNameKey : name,
                 kACSFilenameKey: filename,
                 kACSImageRepKey: imageRep
                 };
    } else {
        NSImage *originalImage = [[NSImage alloc] initWithSize:CGSizeZero];
        [originalImage addRepresentation:imageRep];

        NSImage *thumbnail = [self constrainImage:originalImage toSize:self.thumbnailSize];

        CGImageRef cgImage = [originalImage CGImageForProposedRect:NULL context:nil hints:nil];
        NSBitmapImageRep *bitmapImageRep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
        NSData *pngData = [bitmapImageRep representationUsingType:NSBitmapImageFileTypePNG properties:@{NSImageInterlaced:@(NO)}];

        return @{
                 kACSNameKey : name,
                 kACSImageKey : originalImage,
                 kACSThumbnailKey: thumbnail,
                 kACSFilenameKey: filename,
                 kACSPNGDataKey: pngData
                 };
    }
}

- (NSString *)filenameForAssetNamed:(NSString *)name scale:(CGFloat)scale presentationState:(NSInteger)presentationState preservingPathExtension:(BOOL)preservingPathExtension
{
    NSString *pathExtension = (preservingPathExtension ? name.pathExtension : nil) ?: @"png";
    NSString *baseName = [[name.stringByDeletingPathExtension componentsSeparatedByString:@"@"] firstObject];
    if (scale > 1.0) {
        if (presentationState != kCoreThemeStateNone) {
            return [NSString stringWithFormat:@"%@_%@@%.0fx.%@", baseName, themeStateNameForThemeState(presentationState), scale, pathExtension];
        } else {
            return [NSString stringWithFormat:@"%@@%.0fx.%@", baseName, scale, pathExtension];
        }
    } else {
        if (presentationState != kCoreThemeStateNone) {
            return [NSString stringWithFormat:@"%@_%@.%@", baseName, themeStateNameForThemeState(presentationState), pathExtension];
        } else {
            return [NSString stringWithFormat:@"%@.%@", baseName, pathExtension];
        }
    }
}

- (NSString *)filenameForAssetNamed:(NSString *)name scale:(CGFloat)scale presentationState:(NSInteger)presentationState DEPRECATED_ATTRIBUTE
{
    NSString *pathExtension = name.pathExtension ?: @"png";
    NSString *baseName = [[name.stringByDeletingPathExtension componentsSeparatedByString:@"@"] firstObject];
    if (scale > 1.0) {
        if (presentationState != kCoreThemeStateNone) {
            return [NSString stringWithFormat:@"%@_%@@%.0fx.%@", baseName, themeStateNameForThemeState(presentationState), scale, pathExtension];
        } else {
            return [NSString stringWithFormat:@"%@@%.0fx.%@", baseName, scale, pathExtension];
        }
    } else {
        if (presentationState != kCoreThemeStateNone) {
            return [NSString stringWithFormat:@"%@_%@.%@", baseName, themeStateNameForThemeState(presentationState), pathExtension];
        } else {
            return [NSString stringWithFormat:@"%@.%@", baseName, pathExtension];
        }
    }
}

- (BOOL)catalogHasRetinaContent:(CUICatalog *)catalog
{
    for (NSString *name in catalog.allImageNames) {
        for (CUINamedImage *namedImage in [self imagesNamed:name fromCatalog:catalog]) {
            if (namedImage.scale > 1) {
                return YES;
            }
        }
    }

    return NO;
}

@end
