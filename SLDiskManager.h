//
//  SLDiskManager.h
//  Semulov
//
//  Created by Kevin Wojniak on 9/1/11.
//  Copyright 2011-2014 Kevin Wojniak. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SLDiskManager : NSObject

@property (readonly) NSArray *unmountedDisks;
@property (readonly) NSArray *disks;

- (void)mount:(NSString *)diskID;

@end

extern NSString * const SLDiskManagerUnmountedVolumesDidChangeNotification;

@interface SLDisk : NSObject

@property (readwrite, copy) NSString *diskID;
@property (readwrite, copy) NSString *name;
@property (readwrite, strong) NSImage *icon;
@property (readwrite, strong) NSURL *volumePath;
@property (readonly) BOOL mounted;
@property (readwrite) BOOL mountable;
@property (readwrite, strong) NSMutableArray *children;

@end
