//
//  SLDiskManager.m
//  Semulov
//
//  Created by Kevin Wojniak on 9/1/11.
//  Copyright 2011-2014 Kevin Wojniak. All rights reserved.
//

#import "SLDiskManager.h"
#import <AppKit/AppKit.h>
#import <DiskArbitration/DiskArbitration.h>
#import <IOKit/kext/KextManager.h>
#import <sys/mount.h>
#import "SLDiskImageManager.h"

NSString * const SLDiskManagerUnmountedVolumesDidChangeNotification = @"SLDiskManagerUnmountedVolumesDidChangeNotification";
NSString * const SLDiskManagerDidBlockMountNotification = @"SLDiskManagerDidBlockMountNotification";

@interface SLDiskManager (Private)

- (void)diskChanged:(DADiskRef)disk isGone:(BOOL)gone;

@end

void diskAppearedCallback(DADiskRef disk, void *context)
{
	[(__bridge SLDiskManager *)context diskChanged:disk isGone:NO];
}

void diskDisappearedCallback(DADiskRef disk, void *context)
{
	[(__bridge SLDiskManager *)context diskChanged:disk isGone:YES];
}

void diskDescriptionChangedCallback(DADiskRef disk, CFArrayRef keys, void *context)
{
	[(__bridge SLDiskManager *)context diskChanged:disk isGone:NO];
}

CF_RETURNS_RETAINED DADissenterRef diskMountApproval(DADiskRef disk, void *context)
{
    if (((__bridge SLDiskManager *)context).blockMounts) {
        NSDictionary *description = (__bridge_transfer NSDictionary *)DADiskCopyDescription(disk);
        [[NSNotificationCenter defaultCenter] postNotificationName:SLDiskManagerDidBlockMountNotification object:description userInfo:nil];
        return DADissenterCreate(kCFAllocatorDefault, kDAReturnNotPermitted, NULL);
    }
    return NULL;
}

@implementation SLDiskManager {
	DASessionRef _session;
    NSMutableDictionary *_pendingDisks;
    NSMutableArray *_disks;
    SLDiskImageManager *_diskImageManager;
}

@dynamic disks, diskImageManager;

- (SLDiskImageManager *)diskImageManager
{
    return _diskImageManager;
}

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
        _diskImageManager = [[SLDiskImageManager alloc] init];
		
		DARegisterDiskAppearedCallback(_session, NULL, diskAppearedCallback, (__bridge void *)self);
		DARegisterDiskDisappearedCallback(_session, NULL, diskDisappearedCallback, (__bridge void *)self);
		DARegisterDiskDescriptionChangedCallback(_session, kDADiskDescriptionMatchVolumeMountable, kDADiskDescriptionWatchVolumePath, diskDescriptionChangedCallback, (__bridge void *)self);
        DARegisterDiskMountApprovalCallback(_session, kDADiskDescriptionMatchVolumeMountable, diskMountApproval, (__bridge void *)self);
		DASessionScheduleWithRunLoop(_session, [[NSRunLoop currentRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
	}
	return self;
}

- (void)updateDisk:(SLDisk *)disk fromDescription:(NSDictionary *)description
{
    NSDictionary *mediaIcon = [description objectForKey:(NSString *)kDADiskDescriptionMediaIconKey];
    NSString *bundleIdent = [mediaIcon objectForKey:(NSString *)kCFBundleIdentifierKey];
    NSString *iconFile = [mediaIcon objectForKey:@kIOBundleResourceFileKey];
    if (bundleIdent && iconFile) {
        NSURL *bundleURL = (__bridge_transfer NSURL *)KextManagerCreateURLForBundleIdentifier(kCFAllocatorDefault, (__bridge CFStringRef)bundleIdent);
        if (bundleURL) {
            NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
            disk.icon = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:iconFile ofType:nil]];
        }
    }
    disk.name = [description objectForKey:(NSString *)kDADiskDescriptionVolumeNameKey];
    NSString *model = [[description objectForKey:(NSString *)kDADiskDescriptionDeviceModelKey] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *vendor = [[description objectForKey:(NSString *)kDADiskDescriptionDeviceVendorKey] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (model && vendor) {
        disk.deviceName = [NSString stringWithFormat:@"%@ %@", vendor, model];
    } else if (model) {
        disk.deviceName = model;
    }
    disk.volumePath = [description objectForKey:(NSString *)kDADiskDescriptionVolumePathKey];
    // If the volume exists, use its volume so we show custom icons
    if (disk.volumePath && [disk.volumePath checkResourceIsReachableAndReturnError:nil]) {
        disk.icon = [[NSWorkspace sharedWorkspace] iconForFile:[disk.volumePath path]];
    }
    disk.mountable = [[description objectForKey:(NSString *)kDADiskDescriptionVolumeMountableKey] boolValue];
    disk.whole = [[description objectForKey:(NSString *)kDADiskDescriptionMediaWholeKey] boolValue];
    disk.diskImage = [_diskImageManager diskImageForDiskID:disk.diskID];
    if (disk.diskImage) {
        disk.isDiskImage = YES;
        if (disk.whole) {
            disk.deviceName = [disk.diskImage lastPathComponent];
        }
    }
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

- (void)diskChanged:(DADiskRef)disk isGone:(BOOL)gone
{
    [_diskImageManager reloadInfo];
    
	NSDictionary *description = (__bridge_transfer NSDictionary *)DADiskCopyDescription(disk);
	NSString *diskID = [description objectForKey:(NSString *)kDADiskDescriptionMediaBSDNameKey];
	if (!diskID) {
		return;
	}
    
    NSNumber *wholeNum = [description objectForKey:(NSString *)kDADiskDescriptionMediaWholeKey];
    BOOL isWhole = wholeNum && [wholeNum boolValue];
    
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
                        SLDisk *childDisk = [self diskFromDescription:obj diskID:pendingDiskID];
                        childDisk.parent = disk;
                        [disk.children addObject:childDisk];
                        [pendingDiskIDsToRemove addObject:pendingDiskID];
                    }
                }];
                [_pendingDisks removeObjectsForKeys:pendingDiskIDsToRemove];
                [_disks addObject:disk];
            } else {
                NSString *wholeDiskID = [[self class] diskIDStripSlice:diskID];
                for (SLDisk *disk in _disks) {
                    if ([disk.diskID isEqualToString:wholeDiskID]) {
                        SLDisk *childDisk = [self diskFromDescription:description diskID:diskID];
                        childDisk.parent = disk;
                        [disk.children addObject:childDisk];
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
		
	[[NSNotificationCenter defaultCenter] postNotificationName:SLDiskManagerUnmountedVolumesDidChangeNotification object:nil];
}

- (void)mount:(SLDisk *)disk
{
	DADiskRef diskref = DADiskCreateFromBSDName(kCFAllocatorDefault, _session, [disk.diskID UTF8String]);
	if (disk) {
		DADiskMount(diskref, NULL, kDADiskMountOptionDefault, NULL, NULL);
		CFRelease(diskref);
	}
}

static void diskUnmountCallback(DADiskRef disk, DADissenterRef dissenter, void *context)
{
	NSDictionary *description = (__bridge_transfer NSDictionary *)DADiskCopyDescription(disk);
	NSString *diskID = [description objectForKey:(NSString *)kDADiskDescriptionMediaBSDNameKey];
    if (!diskID) {
        return;
    }
    if (context) {
        SLUnmountHandler handler = (__bridge_transfer SLUnmountHandler)context;
        handler(dissenter == NULL);
        if (dissenter != NULL) {
            NSString *status = (__bridge NSString *)DADissenterGetStatusString(dissenter);
            if (status) {
                NSLog(@"Unmount dissenter status: %@", status);
            }
        }
    }
}

static void diskEjectCallback(DADiskRef disk, DADissenterRef dissenter, void *context)
{
	NSDictionary *description = (__bridge_transfer NSDictionary *)DADiskCopyDescription(disk);
	NSString *diskID = [description objectForKey:(NSString *)kDADiskDescriptionMediaBSDNameKey];
    if (!diskID) {
        return;
    }
    if (dissenter) {
        NSString *status = (__bridge NSString *)DADissenterGetStatusString(dissenter);
        if (status) {
            NSLog(@"Can't eject %@ (%@)", diskID, status);
        } else {
            NSLog(@"Can't eject %@", diskID);
        }
    }
}

- (void)unmountDisk:(SLDisk *)disk handler:(SLUnmountHandler)handler
{
    DADiskRef diskref = DADiskCreateFromBSDName(kCFAllocatorDefault, _session, disk.diskID.UTF8String);
    if (!disk) {
        NSLog(@"Can't create disk for unmounted %@", disk.diskID);
        return;
    }
    DADiskUnmount(diskref, kDADiskUnmountOptionDefault, diskUnmountCallback, (__bridge_retained void *)[handler copy]);
    CFRelease(diskref);
}

- (void)ejectDisk:(SLDisk *)disk
{
    DADiskRef diskref = DADiskCreateFromBSDName(kCFAllocatorDefault, _session, disk.diskID.UTF8String);
    if (!disk) {
        NSLog(@"Can't create disk for ejecting %@", disk.diskID);
        return;
    }
    DADiskEject(diskref, kDADiskEjectOptionDefault, diskEjectCallback, NULL);
    CFRelease(diskref);
}

- (void)unmountAndMaybeEject:(SLDisk *)disk handler:(SLUnmountHandler)handler
{
    if (disk.children.count > 0) {
        // Unmount all children
        for (SLDisk *childDisk in disk.children) {
            if (childDisk.mounted) {
                [self unmountDisk:childDisk handler:nil];
            }
        }
        [self ejectDisk:disk];
    } else if (disk.mounted) {
        unsigned numOtherMounted = 0;
        for (SLDisk *childDisk in disk.parent.children) {
            if (childDisk.mounted && childDisk != disk) {
                ++numOtherMounted;
            }
        }
        [self unmountDisk:disk handler:handler];
        if (numOtherMounted == 0) {
            //  The disk has no other mounted volumes, so eject it.
            [self ejectDisk:disk.parent ? disk.parent : disk];
        }
    }
}

- (NSString *)diskIDForPath:(NSString *)path
{
    struct statfs sb;
    if (statfs([path fileSystemRepresentation], &sb) != 0) {
        return nil;
    }
    return [[NSString stringWithUTF8String:sb.f_mntfromname] lastPathComponent];
}

- (SLDisk *)diskForPath:(NSString *)path
{
    return [self diskForDiskID:[self diskIDForPath:path]];
}

- (SLDisk *)diskForDiskID:(NSString *)diskID
{
    for (SLDisk *disk in _disks) {
        if ([disk.diskID isEqualToString:diskID]) {
            return disk;
        }
        for (SLDisk *childDisk in disk.children) {
            if ([childDisk.diskID isEqualToString:diskID]) {
                return childDisk;
            }
        }
    }
    return nil;
}

@end

@implementation SLDisk
            
- (BOOL)mounted {
    return self.volumePath != nil;
}

- (BOOL)isStartupDisk
{
    return [self.volumePath.path isEqualToString:@"/"];
}

- (BOOL)containsStartupDisk
{
    for (SLDisk *childDisk in self.children) {
        if (childDisk.isStartupDisk) {
            return YES;
        }
    }
    return NO;
}

@end
