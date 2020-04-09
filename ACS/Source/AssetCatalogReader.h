//
//  AssetCatalogReader.h
//  Asset Catalog Tinkerer
//
//  Created by Guilherme Rambo on 27/03/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

@import Cocoa;

NS_ASSUME_NONNULL_BEGIN

typedef NSString *AssetCatalogImageKey NS_STRING_ENUM;
typedef NSDictionary<AssetCatalogImageKey, id> *AssetCatalogImage;

/// The name of the asset
extern const AssetCatalogImageKey kACSNameKey NS_SWIFT_NAME(name);
/// An NSImage representing the image for the asset
extern const AssetCatalogImageKey kACSImageKey NS_SWIFT_NAME(image);
/// An NSImage representing a smaller version of the asset's image (suitable for thumbnails)
extern const AssetCatalogImageKey kACSThumbnailKey  NS_SWIFT_NAME(thumbnail);
/// An NSString with the suggested filename for the asset
extern const AssetCatalogImageKey kACSFilenameKey  NS_SWIFT_NAME(filename);
/// An NSData containing PNG image data for the asset
extern const AssetCatalogImageKey kACSPNGDataKey NS_SWIFT_NAME(pngData) DEPRECATED_ATTRIBUTE;
/// An NSBitmapImageRep containing a bitmap representation of the asset
extern const AssetCatalogImageKey kACSImageRepKey NS_SWIFT_NAME(imageRep);

extern const NSErrorDomain kAssetCatalogReaderErrorDomain;

typedef NS_ERROR_ENUM(kAssetCatalogReaderErrorDomain, AssetCatalogReaderErrorCode) {
    kAssetCatalogReaderErrorCouldNotOpenCatalog = 0,
    kAssetCatalogReaderErrorIncompatibleCatalog,
    kAssetCatalogReaderErrorNoImagesFound
};

typedef void(^AssetCatalogReaderCompletionHandler)(NSArray<NSDictionary<AssetCatalogImageKey, id> *> *_Nullable images, NSUInteger count, NSError *_Nullable error);

@interface AssetCatalogReader : NSObject

- (instancetype)initWithFileURL:(NSURL *)URL;

@property (nonatomic) NSSize thumbnailSize;
@property (nonatomic) BOOL distinguishCatalogsFromThemeStores;
@property (nonatomic) BOOL ignorePackedAssets;

- (NSProgress *)readWithCompletionHandler:(AssetCatalogReaderCompletionHandler)callback;

// Performs a more lightweight read (used by the QuickLook PlugIn)
- (NSProgress *)resourceConstrainedReadWithMaxCount:(int64_t)max completionHandler:(AssetCatalogReaderCompletionHandler)callback;

@end

NS_ASSUME_NONNULL_END
