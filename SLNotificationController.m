//
//  SLNotificationController.m
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006-2014 Kevin Wojniak. All rights reserved.
//

#import "SLNotificationController.h"
#import "SLVolume.h"

@implementation SLNotificationController

+ (void)postNotificationCenterWithTitle:(NSString *)title subtitle:(NSString *)subtitle
{
    NSUserNotification *note = [[NSUserNotification alloc] init];
    note.title = title;
    note.subtitle = subtitle;
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:note];
}

+ (void)postVolumeMounted:(SLVolume *)volume
{
    NSString *notifTitle = NSLocalizedString(@"Volume Mounted", "");
    NSString *notifDescription = [volume name];
    [self postNotificationCenterWithTitle:notifTitle subtitle:notifDescription];
}

+ (void)postVolumeUnmounted:(SLVolume *)volume
{
    NSString *notifTitle = NSLocalizedString(@"Volume Unmounted", "");
    NSString *notifDescription = [volume name];
    [self postNotificationCenterWithTitle:notifTitle subtitle:notifDescription];
}

+ (void)postVolumeMountBlocked:(NSString *)volumeName
{
    [self postNotificationCenterWithTitle:NSLocalizedString(@"Mount Blocked", "") subtitle:volumeName];
}

@end
