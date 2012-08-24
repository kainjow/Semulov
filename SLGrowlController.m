//
//  SLGrowlController.m
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "SLGrowlController.h"

#define SL_VOLUME_MOUNTED	@"Volume Mounted"
#define SL_VOLUME_UNMOUNTED	@"Volume Unmounted"


@implementation SLGrowlController

+ (id)sharedController
{
	static id instance = nil;
	if (instance == nil)
		instance = [[[self class] alloc] init];
	return instance;
}

- (void)setup
{
	[GrowlApplicationBridge setGrowlDelegate:self];
}

- (NSDictionary *)registrationDictionaryForGrowl
{
	NSArray *keys = [NSArray arrayWithObjects:
		SL_VOLUME_MOUNTED,
		SL_VOLUME_UNMOUNTED,
		nil];
	
	return [NSDictionary dictionaryWithObjectsAndKeys:
		keys, GROWL_NOTIFICATIONS_ALL,
		keys, GROWL_NOTIFICATIONS_DEFAULT,
		nil];
}

- (void)postVolumeMounted:(SLVolume *)volume
{
	[GrowlApplicationBridge notifyWithTitle:SL_VOLUME_MOUNTED
								description:[volume name]
						   notificationName:SL_VOLUME_MOUNTED
								   iconData:[[volume image] TIFFRepresentation]
								   priority:0
								   isSticky:NO
							   clickContext:[volume path]];
}

- (void)postVolumeUnmounted:(SLVolume *)volume;
{
	[GrowlApplicationBridge notifyWithTitle:SL_VOLUME_UNMOUNTED
								description:[volume name]
						   notificationName:SL_VOLUME_UNMOUNTED
								   iconData:[[volume image] TIFFRepresentation]
								   priority:0
								   isSticky:NO
							   clickContext:NULL];
}

- (void)growlNotificationWasClicked:(id)context
{
	[[NSWorkspace sharedWorkspace] openFile:context];
}

@end
