//
//  SLVolume.h
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 - 2014 Kevin Wojniak. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class SLDiskImageManager;

typedef enum
{
	SLVolumeRoot,
	SLVolumeDrive,
	SLVolumeiPod,
	SLVolumeNetwork,
	SLVolumeFTP,
	SLVolumeWebDAV,
	SLVolumeDiskImage,
	SLVolumeCD,
	SLVolumeDVD,
	SLVolumeHardDrive,
	SLVolumeRAMDisk,
    SLVolumeBluray,
} SLVolumeType;

@interface SLVolume : NSObject <NSCopying>

+ (NSArray *)allVolumesWithDiskManager:(SLDiskImageManager *)diskImageManager;

- (NSString *)path;
- (NSString *)name;
- (NSImage *)image;
- (BOOL)isLocal;
- (BOOL)isRoot;
- (SLVolumeType)type;
- (NSURL *)hostURL;
- (BOOL)isInternalHardDrive;

- (NSString *)diskImagePath;

- (BOOL)isiPod;

- (BOOL)showInFinder;

@end
