//
//  SLDeviceManager.m
//  Semulov
//
//  Created by Kevin Wojniak on 9/1/11.
//  Copyright 2011 Kevin Wojniak. All rights reserved.
//

#import "SLDeviceManager.h"
#import "SLUnmountedVolume.h"
#import <IOKit/kext/KextManager.h>

NSString * const SLDeviceManagerUnmountedVolumesDidChangeNotification = @"SLDeviceManagerUnmountedVolumesDidChangeNotification";

@interface SLDeviceManager (Private)

- (void)diskChanged:(DADiskRef)disk isGone:(BOOL)gone;

@end

void diskAppearedCallback(DADiskRef disk, void *context)
{
	[(__bridge SLDeviceManager *)context diskChanged:disk isGone:NO];
}

void diskDisappearedCallback(DADiskRef disk, void *context)
{
	[(__bridge SLDeviceManager *)context diskChanged:disk isGone:YES];
}

void diskDescriptionChangedCallback(DADiskRef disk, CFArrayRef keys, void *context)
{
	[(__bridge SLDeviceManager *)context diskChanged:disk isGone:NO];
}

@implementation SLDeviceManager

@synthesize unmountedVolumes;

- (id)init
{
	self = [super init];
	if (self != nil) {
		session = DASessionCreate(kCFAllocatorDefault);
		if (!session) {
			NSLog(@"Failed to create session");
			return nil;
		}
		
		DARegisterDiskAppearedCallback(session, kDADiskDescriptionMatchVolumeMountable, diskAppearedCallback, (__bridge void *)self);
		DARegisterDiskDisappearedCallback(session, kDADiskDescriptionMatchVolumeMountable, diskDisappearedCallback, (__bridge void *)self);
		DARegisterDiskDescriptionChangedCallback(session, kDADiskDescriptionMatchVolumeMountable, kDADiskDescriptionWatchVolumePath, diskDescriptionChangedCallback, (__bridge void *)self);
		DASessionScheduleWithRunLoop(session, [[NSRunLoop currentRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
	}
	return self;
}

- (SLUnmountedVolume *)unmountedVolumeForDiskID:(NSString *)diskID
{
	for (SLUnmountedVolume *vol in unmountedVolumes) {
		if ([vol.diskID isEqualToString:diskID]) {
			return vol;
		}
	}
	return nil;
}

- (void)diskChanged:(DADiskRef)disk isGone:(BOOL)gone
{
	NSDictionary *description = (__bridge_transfer NSDictionary *)DADiskCopyDescription(disk);
	NSString *diskID = [description objectForKey:(NSString *)kDADiskDescriptionMediaBSDNameKey];
	NSString *volumeName = [description objectForKey:(NSString *)kDADiskDescriptionVolumeNameKey];
	if (!diskID || !volumeName) {
		return;
	}
	
	NSString *volumePath = [description objectForKey:(NSString *)kDADiskDescriptionVolumePathKey];
	BOOL isMounted = volumeName && volumePath;
	
	if (gone || isMounted) {
		NSMutableArray *volsToRemove = [NSMutableArray array];
		for (SLUnmountedVolume *vol in unmountedVolumes) {
			if ([vol.diskID hasPrefix:diskID]) {
				[volsToRemove addObject:vol];
			}
		}
		[unmountedVolumes removeObjectsInArray:volsToRemove];
	} else {
		SLUnmountedVolume *vol = [[SLUnmountedVolume alloc] init];
		NSDictionary *mediaIcon = [description objectForKey:(NSString *)kDADiskDescriptionMediaIconKey];
		NSString *bundleIdent = [mediaIcon objectForKey:(NSString *)kCFBundleIdentifierKey];
		NSString *iconFile = [mediaIcon objectForKey:@kIOBundleResourceFileKey];
		if (bundleIdent && iconFile) {
			NSURL *bundleURL = (__bridge_transfer NSURL *)KextManagerCreateURLForBundleIdentifier(kCFAllocatorDefault, (__bridge CFStringRef)bundleIdent);
			if (bundleURL) {
				NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
				vol.icon = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:iconFile ofType:nil]];
			}
		}
		vol.diskID = diskID;
		vol.name = volumeName;
		if (!unmountedVolumes) {
			unmountedVolumes = [[NSMutableArray alloc] init];
		}
		[unmountedVolumes addObject:vol];
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:SLDeviceManagerUnmountedVolumesDidChangeNotification object:nil];
}

- (void)mount:(NSString *)diskID
{
	DADiskRef disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, [diskID UTF8String]);
	if (disk) {
		DADiskMount(disk, NULL, kDADiskMountOptionDefault, NULL, NULL);
		CFRelease(disk);
	}
}

@end
