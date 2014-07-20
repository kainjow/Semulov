//
//  SLDiskManager.h
//  Semulov
//
//  Created by Kevin Wojniak on 9/1/11.
//  Copyright 2011-2014 Kevin Wojniak. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SLDisk;

@interface SLDiskManager : NSObject

@property (readonly) NSArray *unmountedDisks;
@property (readonly) NSArray *disks;

- (void)mount:(NSString *)diskID;

typedef void (^SLUnmountHandler)(BOOL unmounted);
- (void)unmountAndMaybeEject:(SLDisk *)disk handler:(SLUnmountHandler)handler;

- (SLDisk *)diskForPath:(NSString *)path;

@end

extern NSString * const SLDiskManagerUnmountedVolumesDidChangeNotification;

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
@property (readwrite, strong) NSMutableArray *children;

@end
