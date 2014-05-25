//
//  SLVolume.h
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 - 2011 Kevin Wojniak. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include <sys/mount.h>

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
{
	NSString *_path;
	NSString *_name;
	NSImage *_image;
	BOOL _local;
	BOOL _root;
	NSURL *_hostURL;
	BOOL _internal;
	NSString *_imagePath;
	
	SLVolumeType _type;
}

+ (NSArray *)allVolumes;

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

- (BOOL)eject;
- (BOOL)showInFinder;

@end
