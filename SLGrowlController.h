//
//  SLGrowlController.h
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Growl/Growl.h>
#import "SLVolume.h"


@interface SLGrowlController : NSObject <GrowlApplicationBridgeDelegate>
{

}

+ (id)sharedController;
- (void)setup;

- (void)postVolumeMounted:(SLVolume *)volume;
- (void)postVolumeUnmounted:(SLVolume *)volume;

@end
