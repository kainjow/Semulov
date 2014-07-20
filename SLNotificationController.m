//
//  SLNotificationController.m
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006-2014 Kevin Wojniak. All rights reserved.
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
    if (NSClassFromString(@"NSUserNotification")) {
        NSUserNotification *note = [[NSUserNotification alloc] init];
        note.title = title;
        note.subtitle = subtitle;
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:note];
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
