//
//  SLNotificationController.m
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 Kevin Wojniak. All rights reserved.
//

#import "SLNotificationController.h"
#import "SLVolume.h"

#define SL_VOLUME_MOUNTED	NSLocalizedString(@"Volume Mounted", "")
#define SL_VOLUME_UNMOUNTED	NSLocalizedString(@"Volume Unmounted", "")

@implementation SLNotificationController

+ (id)sharedController
{
	static id instance = nil;
	if (instance == nil)
		instance = [[[self class] alloc] init];
	return instance;
}

- (void)postNotificationCenterWithTitle:(NSString *)title subtitle:(NSString *)subtitle
{
    // We don't yet link against 10.8 SDK so can't use this API directly yet.
    id userNotificationCenterClass = NSClassFromString(@"NSUserNotificationCenter");
    if (userNotificationCenterClass != nil) {
        id note = [[NSClassFromString(@"NSUserNotification") alloc] init];
        [note setValue:title forKey:@"title"];
        [note setValue:subtitle forKey:@"subtitle"];
        [[userNotificationCenterClass performSelector:@selector(defaultUserNotificationCenter)] performSelector:@selector(deliverNotification:) withObject:note];
    }
}

- (void)postVolumeMounted:(SLVolume *)volume
{
    NSString *notifTitle = SL_VOLUME_MOUNTED;
    NSString *notifDescription = [volume name];
    [self postNotificationCenterWithTitle:notifTitle subtitle:notifDescription];
}

- (void)postVolumeUnmounted:(SLVolume *)volume;
{
    NSString *notifTitle = SL_VOLUME_UNMOUNTED;
    NSString *notifDescription = [volume name];
    [self postNotificationCenterWithTitle:notifTitle subtitle:notifDescription];
}

@end
