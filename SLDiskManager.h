//
//  SLDiskManager.h
//  Semulov
//
//  Created by Kevin Wojniak on 9/1/11.
//  Copyright 2011-2014 Kevin Wojniak. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SLDisk;
@class SLDiskImageManager;

@interface SLDiskManager : NSObject

@property (readonly) NSArray *unmountedDisks;
@property (readonly) NSArray *disks;

- (void)mount:(SLDisk *)disk;

typedef void (^SLUnmountHandler)(BOOL unmounted);
- (void)unmountAndMaybeEject:(SLDisk *)disk handler:(SLUnmountHandler)handler;

@property (readwrite) BOOL blockMounts;

- (SLDisk *)diskForPath:(NSString *)path;
- (SLDisk *)diskForDiskID:(NSString *)diskID;

@property (readonly) SLDiskImageManager *diskImageManager;

@end

extern NSString * const SLDiskManagerUnmountedVolumesDidChangeNotification;
extern NSString * const SLDiskManagerDidBLockMountNotification; // object is DADiskRef dictionary

@interface SLDisk : NSObject

@property (weak) SLDisk *parent;
@property (readwrite, copy) NSString *diskID;
@property (readwrite, copy) NSString *name;
@property (readwrite, copy) NSString *deviceName;
@property (readwrite, strong) NSImage *icon;
@property (readwrite, strong) NSURL *volumePath;
@property (readonly) BOOL mounted;
@property (readwrite) BOOL mountable;
@property (readwrite) BOOL whole;
@property (readonly) BOOL isStartupDisk;
@property (readonly) BOOL containsStartupDisk;
@property (readwrite) BOOL isDiskImage;
@property (readwrite, copy) NSString *diskImage;
@property (readwrite, strong) NSMutableArray *children;

@end
