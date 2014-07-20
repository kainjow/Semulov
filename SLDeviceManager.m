//
//  SLDeviceManager.m
//  Semulov
//
//  Created by Kevin Wojniak on 9/1/11.
//  Copyright 2011-2014 Kevin Wojniak. All rights reserved.
//

#import "SLDeviceManager.h"
#import <AppKit/AppKit.h>
#import <DiskArbitration/DiskArbitration.h>
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

@implementation SLDeviceManager {
	DASessionRef _session;
    NSMutableDictionary *_pendingDisks;
    NSMutableArray *_disks;
}

@dynamic disks;

- (NSArray *)unmountedDisks {
    NSMutableArray *unmountedDisks = [NSMutableArray array];
    for (SLDisk *disk in _disks) {
        if (disk.mountable && !disk.mounted) {
            [unmountedDisks addObject:disk];
        }
        for (SLDisk *childDisk in disk.children) {
            if (childDisk.mountable && !childDisk.mounted) {
                [unmountedDisks addObject:childDisk];
            }
        }
    }
    return [unmountedDisks count] > 0 ? unmountedDisks : nil;
}

- (NSArray *)disks {
    return _disks;
}

- (id)init
{
    if ((self = [super init]) != nil) {
		_session = DASessionCreate(kCFAllocatorDefault);
		if (!_session) {
			NSLog(@"Failed to create session");
			return nil;
		}
        
        _pendingDisks = [[NSMutableDictionary alloc] init];
        _disks = [[NSMutableArray alloc] init];
		
		DARegisterDiskAppearedCallback(_session, NULL, diskAppearedCallback, (__bridge void *)self);
		DARegisterDiskDisappearedCallback(_session, NULL, diskDisappearedCallback, (__bridge void *)self);
		DARegisterDiskDescriptionChangedCallback(_session, kDADiskDescriptionMatchVolumeMountable, kDADiskDescriptionWatchVolumePath, diskDescriptionChangedCallback, (__bridge void *)self);
		DASessionScheduleWithRunLoop(_session, [[NSRunLoop currentRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
	}
	return self;
}

- (void)updateDisk:(SLDisk *)disk fromDescription:(NSDictionary *)description
{
    NSDictionary *mediaIcon = [description objectForKey:(NSString *)kDADiskDescriptionMediaIconKey];
    NSString *bundleIdent = [mediaIcon objectForKey:(NSString *)kCFBundleIdentifierKey];
    NSString *iconFile = [mediaIcon objectForKey:@kIOBundleResourceFileKey];
    NSString *volumeName = [description objectForKey:(NSString *)kDADiskDescriptionVolumeNameKey];
    if (bundleIdent && iconFile) {
        NSURL *bundleURL = (__bridge_transfer NSURL *)KextManagerCreateURLForBundleIdentifier(kCFAllocatorDefault, (__bridge CFStringRef)bundleIdent);
        if (bundleURL) {
            NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
            disk.icon = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:iconFile ofType:nil]];
        }
    }
    disk.name = volumeName;
    disk.volumePath = [description objectForKey:(NSString *)kDADiskDescriptionVolumePathKey];
    disk.mountable = [[description objectForKey:(NSString *)kDADiskDescriptionVolumeMountableKey] boolValue];
}

- (SLDisk *)diskFromDescription:(NSDictionary *)description diskID:(NSString *)diskID
{
    SLDisk *disk = [[SLDisk alloc] init];
    disk.children = [NSMutableArray array];
    disk.diskID = diskID;
    [self updateDisk:disk fromDescription:description];
    return disk;
}

// Converts disk0s4 to disk0
+ (NSString *)diskIDStripSlice:(NSString *)diskID
{
    if ([diskID hasPrefix:@"disk"]) {
        NSRange range = [diskID rangeOfString:@"s" options:NSBackwardsSearch];
        if (range.location > 2) {
            return [diskID substringToIndex:range.location];
        }
    }
    return diskID;
}

- (void)processPendingDisks
{
}

- (void)diskChanged:(DADiskRef)disk isGone:(BOOL)gone
{
	NSDictionary *description = (__bridge_transfer NSDictionary *)DADiskCopyDescription(disk);
	NSString *diskID = [description objectForKey:(NSString *)kDADiskDescriptionMediaBSDNameKey];
	if (!diskID) {
		return;
	}
    
    NSNumber *wholeNum = [description objectForKey:(NSString *)kDADiskDescriptionMediaWholeKey];
    BOOL isWhole = wholeNum && [wholeNum boolValue];
    
    NSLog(@"%@: gone=%d", diskID, gone);
    
    if (gone) {
        // Disk disappeared, remove entire object
        for (NSInteger i = _disks.count - 1; i >= 0; --i) {
            SLDisk *disk = _disks[i];
            if ([disk.diskID isEqualToString:diskID]) {
                [_disks removeObjectAtIndex:i];
                break;
            }
            BOOL removedChild = NO;
            NSMutableArray *children = disk.children;
            for (NSInteger j = children.count - 1; j >= 0; --j) {
                SLDisk *childDisk = children[j];
                if ([childDisk.diskID isEqualToString:diskID]) {
                    [children removeObjectAtIndex:j];
                    removedChild = YES;
                    break;
                }
            }
            if (removedChild) {
                break;
            }
        }
    } else {
        // Disk was added or changed
        BOOL found = NO;
        for (SLDisk *disk in _disks) {
            if ([disk.diskID isEqualToString:diskID]) {
                [self updateDisk:disk fromDescription:description];
                found = YES;
                break;
            }
            for (SLDisk *childDisk in disk.children) {
                if ([childDisk.diskID isEqualToString:diskID]) {
                    [self updateDisk:childDisk fromDescription:description];
                    found = YES;
                    break;
                }
            }
        }
        if (!found) {
            if (isWhole) {
                SLDisk *disk = [self diskFromDescription:description diskID:diskID];
                // Process pending disks
                NSMutableArray *pendingDiskIDsToRemove = [NSMutableArray array];
                [_pendingDisks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    NSString *pendingDiskID = key;
                    if ([[[self class] diskIDStripSlice:pendingDiskID] isEqualToString:diskID]) {
                        [disk.children addObject:[self diskFromDescription:obj diskID:pendingDiskID]];
                        [pendingDiskIDsToRemove addObject:pendingDiskID];
                    }
                }];
                [_pendingDisks removeObjectsForKeys:pendingDiskIDsToRemove];
                [_disks addObject:disk];
            } else {
                NSString *wholeDiskID = [[self class] diskIDStripSlice:diskID];
                for (SLDisk *disk in _disks) {
                    if ([disk.diskID isEqualToString:wholeDiskID]) {
                        [disk.children addObject:[self diskFromDescription:description diskID:diskID]];
                        found = YES;
                        break;
                    }
                }
                if (!found) {
                    // DiskArbitration can send child disks before the parent, so we have to wait for the parent to arrive to process the children
                    if (_pendingDisks[diskID] != nil) {
                        // bug?
                        NSLog(@"Replacing existing pending disk for %@?", diskID);
                    }
                    _pendingDisks[diskID] = description;
                }
            }
        }
    }
		
	[[NSNotificationCenter defaultCenter] postNotificationName:SLDeviceManagerUnmountedVolumesDidChangeNotification object:nil];
}

- (void)mount:(NSString *)diskID
{
	DADiskRef disk = DADiskCreateFromBSDName(kCFAllocatorDefault, _session, [diskID UTF8String]);
	if (disk) {
		DADiskMount(disk, NULL, kDADiskMountOptionDefault, NULL, NULL);
		CFRelease(disk);
	}
}

@end

@implementation SLDisk
            
- (BOOL)mounted {
    return self.volumePath != nil;
}

@end
