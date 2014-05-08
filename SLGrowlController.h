//
//  SLGrowlController.h
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 Kevin Wojniak. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SLVolume.h"


@interface SLGrowlController : NSObject
{

}

+ (id)sharedController;

- (void)postVolumeMounted:(SLVolume *)volume;
- (void)postVolumeUnmounted:(SLVolume *)volume;

@end
