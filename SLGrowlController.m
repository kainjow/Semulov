//
//  SLGrowlController.m
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 Kevin Wojniak. All rights reserved.
//

#import "SLGrowlController.h"

#define SL_VOLUME_MOUNTED	NSLocalizedString(@"Volume Mounted", "")
#define SL_VOLUME_UNMOUNTED	NSLocalizedString(@"Volume Unmounted", "")


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

- (void)postNotificationCenterWithTitle:(NSString *)title subtitle:(NSString *)subtitle
{
    // We don't yet link against 10.8 SDK so can't use this API directly yet.
    id userNotificationCenterClass = NSClassFromString(@"NSUserNotificationCenter");
    if (userNotificationCenterClass != nil) {
        id note = [[[NSClassFromString(@"NSUserNotification") alloc] init] autorelease];
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
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"SLPostGrowlNotifications"]) {
        [GrowlApplicationBridge notifyWithTitle:notifTitle
                                    description:notifDescription
                               notificationName:SL_VOLUME_MOUNTED
                                       iconData:[[volume image] TIFFRepresentation]
                                       priority:0
                                       isSticky:NO
                                   clickContext:[volume path]];
    }
}

- (void)postVolumeUnmounted:(SLVolume *)volume;
{
    NSString *notifTitle = SL_VOLUME_UNMOUNTED;
    NSString *notifDescription = [volume name];
    [self postNotificationCenterWithTitle:notifTitle subtitle:notifDescription];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"SLPostGrowlNotifications"]) {
        [GrowlApplicationBridge notifyWithTitle:notifTitle
                                    description:notifDescription
                               notificationName:SL_VOLUME_UNMOUNTED
                                       iconData:[[volume image] TIFFRepresentation]
                                       priority:0
                                       isSticky:NO
                                   clickContext:NULL];
    }
}

- (void)growlNotificationWasClicked:(id)context
{
	[[NSWorkspace sharedWorkspace] openFile:context];
}

@end
