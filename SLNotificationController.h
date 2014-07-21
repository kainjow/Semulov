//
//  SLNotificationController.h
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006-2014 Kevin Wojniak. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class SLVolume;

@interface SLNotificationController : NSObject

+ (id)sharedController;

- (void)postVolumeMounted:(SLVolume *)volume;
- (void)postVolumeUnmounted:(SLVolume *)volume;
- (void)postVolumeMountBlocked:(NSString *)volumeName;

@end
