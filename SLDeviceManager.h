//
//  SLDeviceManager.h
//  Semulov
//
//  Created by Kevin Wojniak on 9/1/11.
//  Copyright 2011 Kevin Wojniak. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <DiskArbitration/DiskArbitration.h>


@interface SLDeviceManager : NSObject
{
	DASessionRef session;
	NSMutableArray *unmountedVolumes;
}

@property (readonly) NSArray *unmountedVolumes;

- (void)mount:(NSString *)diskID;

@end


extern NSString * const SLDeviceManagerUnmountedVolumesDidChangeNotification;