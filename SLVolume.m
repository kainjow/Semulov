//
//  SLVolume.m
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 - 2011 Kevin Wojniak. All rights reserved.
//

#import "SLVolume.h"
#import <DiskArbitration/DiskArbitration.h>
#import <IOKit/storage/IOStorageDeviceCharacteristics.h>
#import <sys/mount.h>
#import "NSTaskAdditions.h"

@interface SLVolume (Private)

+ (id)volumeWithStatfs:(struct statfs *)statfs mountedDiskImages:(NSDictionary *)diskImages;
- (id)initWithStatfs:(struct statfs *)statfs mountedDiskImages:(NSDictionary *)diskImages;

@end

@implementation SLVolume
{
	NSString *_path;
	NSString *_name;
	NSImage *_image;
	BOOL _local;
	BOOL _root;
	NSURL *_hostURL;
	BOOL _internal;
	NSString *_imagePath;
	
	SLVolumeType _type;
}

+ (NSDictionary *)mountedDiskImages
{
	NSString *plistStr = [NSTask outputStringForTaskAtPath:@"/usr/bin/hdiutil" arguments:[NSArray arrayWithObjects:@"info", @"-plist", nil] encoding:NSUTF8StringEncoding];
	
	// sometimes hdiutil returns an error in the first line or so of it's output.
	// so we try to determine if an error exists, and skip past it to the xml
	
	NSString *xmlStr = @"<?xml";
	NSRange xmlRange = [plistStr rangeOfString:xmlStr];
	if (xmlRange.location == NSNotFound)
	{
		// not valid xml?!
		return nil;
	}
	if (xmlRange.location > 0)
	{
		// scan up to XML
		NSScanner *scanner = [NSScanner scannerWithString:plistStr];
		[scanner scanUpToString:xmlStr intoString:nil];
		plistStr = [plistStr substringFromIndex:[scanner scanLocation]];
	}

	NSDictionary *plistDict = [plistStr propertyList];
	if ((plistDict == nil) || ([plistDict isKindOfClass:[NSDictionary class]] == NO))
		return nil;
	
	NSMutableDictionary *mountPoints = [NSMutableDictionary dictionary];
	NSArray *images = [plistDict objectForKey:@"images"];
	NSDictionary *imagesDict = nil;
	for (imagesDict in images)
	{
		NSString *imagePath = [imagesDict objectForKey:@"image-path"];
		NSArray *sysEntities = [imagesDict objectForKey:@"system-entities"];
		NSDictionary *sysEntity = nil;
		
		// if .dmg is mounted from safari, imagePath will be the .dmg within the .download file
		NSRange dotDownloadRange = [imagePath rangeOfString:@".download"];
		if (dotDownloadRange.location != NSNotFound)
			imagePath = [imagePath substringToIndex:dotDownloadRange.location];
		
		for (sysEntity in sysEntities)
		{
			NSString *mountPoint = [sysEntity objectForKey:@"mount-point"];
			
			if ((imagePath != nil) && (mountPoint != nil))
			{
				[mountPoints setObject:imagePath forKey:mountPoint];
			}
		}
	}
	
	return ([mountPoints count] ? mountPoints : nil);
}

+ (NSArray *)allVolumes
{
	NSMutableArray *volumes = [NSMutableArray array];
	int count = getfsstat(NULL, 0, MNT_NOWAIT);
	if (count > 0) {
		struct statfs *buf = calloc(count, sizeof(struct statfs));
		if (buf) {
			if (getfsstat(buf, count * sizeof(struct statfs), MNT_NOWAIT) > 0) {
				NSDictionary *diskImages = [SLVolume mountedDiskImages];
				for (int i = 0; i < count; i++) {
					SLVolume *vol = [SLVolume volumeWithStatfs:&buf[i] mountedDiskImages:diskImages];
                    if (vol == nil) {
                        continue;
                    }
                    if ([vol.path isEqualToString:@"/Volumes/MobileBackups"]) {
                        // Time Machine temp backups volume, ignore.
                        continue;
                    }
                    [volumes addObject:vol];
				}
			}
			free(buf);
		}
	}
	[volumes sortUsingSelector:@selector(compare:)];
	return volumes;
}

+ (id)volumeWithStatfs:(struct statfs *)statfs mountedDiskImages:(NSDictionary *)diskImages
{
    return [[self alloc] initWithStatfs:statfs mountedDiskImages:diskImages];
}

+ (NSURL *)volumeURL:(NSURL *)url
{
    NSURL *hostURL = nil;
    (void)[url getResourceValue:&hostURL forKey:NSURLVolumeURLForRemountingKey error:nil];
    return hostURL;
}

- (id)initWithStatfs:(struct statfs *)statfs mountedDiskImages:(NSDictionary *)diskImages
{
    self = [super init];
    if (self != nil)
	{
		NSString *fileSystemType = [NSString stringWithCString:statfs->f_fstypename encoding:NSUTF8StringEncoding];
		NSString *path = [NSString stringWithUTF8String:statfs->f_mntonname];
		//NSLog(@"%@: %@", [path lastPathComponent], fileSystemType);
		if (!([path isEqualToString:@"/"] || [path hasPrefix:@"/Volumes"]))
		{
			return nil;
		}
        
        if ([fileSystemType isEqualToString:@"vmhgfs"]) {
            // Ignore VMware Shared Folders internal mounted volume
            return nil;
        }
		
		if ((statfs->f_flags & MNT_LOCAL) == MNT_LOCAL)
			_local = YES;
		if ((statfs->f_flags & MNT_ROOTFS) == MNT_ROOTFS)
			_root = YES;
		
		_path = [path copy];		
		_name = [[[[NSFileManager alloc] init] displayNameAtPath:path] copy];

		if ([self isLocal] == NO)
		{
			_type = SLVolumeNetwork;
			
            NSURL *hostURL = [[self class] volumeURL:[NSURL fileURLWithPath:[self path]]];
			if (hostURL)
			{
                _hostURL = [hostURL copy];
                
                if ([[_hostURL scheme] isEqualToString:@"ftp"]) {
                    _type = SLVolumeFTP;
                } else if ([[_hostURL scheme] isEqualToString:@"afp"]) {
                    // keep as SLVolumeNetwork
                } else if ([[_hostURL scheme] isEqualToString:@"file"]) {
                    // probably file:///Volumes/MobileBackups/ (mtmfs)
                } else {
                    if ([fileSystemType isEqualToString:@"webdav"]) {
                        _type = SLVolumeWebDAV;
                    } else {
                        NSLog(@"unknown URL: %@ (%@)", _hostURL, fileSystemType);
                    }
                }
			}
		}
		else
		{
			if ([self isRoot])
				_type = SLVolumeRoot;
			else if ([self isiPod])
				_type = SLVolumeiPod;
			else
				_type = SLVolumeDrive;
			
			if (diskImages != nil)
			{
				NSString *imgPath = [diskImages objectForKey:[self path]];
				if (imgPath)
				{
					_imagePath = [imgPath copy];
					_type = SLVolumeDiskImage;
				}
			}
			
			DASessionRef session = DASessionCreate(kCFAllocatorDefault);
			if (session)
			{
				DADiskRef disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, statfs->f_mntfromname);
				if (disk)
				{
					CFDictionaryRef desc = DADiskCopyDescription(disk);
					if (desc)
					{
						CFBooleanRef isInternal, isEjectable;
						CFStringRef deviceModel;
                        CFStringRef mediaKind;
						if (!CFDictionaryGetValueIfPresent(desc, kDADiskDescriptionDeviceInternalKey, (void *)&isInternal)) {
							isInternal = kCFBooleanFalse;
						}
						if (!CFDictionaryGetValueIfPresent(desc, kDADiskDescriptionMediaEjectableKey, (void *)&isEjectable)) {
							isEjectable = kCFBooleanFalse;
						}
						if (!CFDictionaryGetValueIfPresent(desc, kDADiskDescriptionDeviceModelKey, (void *)&deviceModel)) {
							deviceModel = NULL;
						}
                        if (!CFDictionaryGetValueIfPresent(desc, kDADiskDescriptionMediaKindKey, (void *)&mediaKind)) {
                            mediaKind = NULL;
                        }
						
						// 2nd check for disk images..
						if (([self type] != SLVolumeDiskImage) && ([(__bridge NSString *)deviceModel isEqualToString:@"Disk Image"]))
						{
							_type = SLVolumeDiskImage;
						}
						else if ([self type] == SLVolumeDrive) // if we haven't been identified by anything else yet, check for being a hd?
						{
							if ((isInternal == kCFBooleanTrue) && (isEjectable == kCFBooleanFalse))
							{
								_internal = YES;
							}
							
							// (will be overridden later if we're a DVD or CD)
							_type = SLVolumeHardDrive;
						}
						
						if ([self type] == SLVolumeDiskImage) {
							DADiskRef parentDisk = DADiskCopyWholeDisk(disk);
							if (parentDisk) {
								io_service_t ioMedia = DADiskCopyIOMedia(parentDisk);
								if (ioMedia) {
									CFTypeRef props = IORegistryEntrySearchCFProperty(ioMedia, kIOServicePlane, CFSTR(kIOPropertyProtocolCharacteristicsKey), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents);
									if (props) {
										//NSLog(@"%@", props);
										if (CFGetTypeID(props) == CFDictionaryGetTypeID()) {
											CFTypeRef location = CFDictionaryGetValue(props, CFSTR(kIOPropertyPhysicalInterconnectLocationKey));
											if (location && CFGetTypeID(location) == CFStringGetTypeID()) {
												if (CFEqual(location, CFSTR(kIOPropertyInterconnectRAMKey))) {
													_type = SLVolumeRAMDisk;
												}
											}
										}
										CFRelease(props);
									}
									IOObjectRelease(ioMedia);
								}
								CFRelease(parentDisk);
							}
						}
						
                        if (mediaKind != NULL) {
                            // could be IODVDMedia, IOCDMedia, IOBDMedia, etc.
                            if ([(__bridge NSString *)mediaKind rangeOfString:@"DVD"].location != NSNotFound) {
                                _type = SLVolumeDVD;
                            } else if ([(__bridge NSString *)mediaKind rangeOfString:@"CD"].location != NSNotFound) {
                                _type = SLVolumeCD;
                            } else if ([(__bridge NSString *)mediaKind rangeOfString:@"BD"].location != NSNotFound) {
                                _type = SLVolumeBluray;
                            }
                        }

						CFRelease(desc);
					}
					CFRelease(disk);
				}
				CFRelease(session);
			}
        }
	}
	
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	SLVolume *copy = [[SLVolume alloc] init];
	copy->_path = [_path copy];
	copy->_name = [_name copy];
	copy->_image = [_image copy];
	copy->_hostURL = [_hostURL copy];
	copy->_imagePath = [_imagePath copy];
	copy->_local = _local;
	copy->_root = _root;
	copy->_internal = _internal;
	copy->_type = _type;
	return copy;
}

- (NSString *)path
{
	return _path;
}

- (NSString *)name
{
	return _name;
}

- (NSImage *)image
{
	if (!_image) {
		_image = [[[NSWorkspace sharedWorkspace] iconForFile:_path] copy];
	}
	return _image;
}

- (BOOL)isLocal
{
	return _local;
}

- (BOOL)isRoot
{
	return _root;
}

- (BOOL)showInFinder
{
    NSString *defaultAppID = [[NSUserDefaults standardUserDefaults] objectForKey:@"SLShowinFinderBundleID"];
    if (defaultAppID && [defaultAppID length] > 0) {
        NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:defaultAppID];
        return [[NSWorkspace sharedWorkspace] openFile:[self path] withApplication:[appURL path]];
    }
    return [[NSWorkspace sharedWorkspace] selectFile:nil inFileViewerRootedAtPath:[self path]];
}

- (SLVolumeType)type
{
	return _type;
}

- (NSURL *)hostURL
{
	return _hostURL;
}

- (BOOL)isInternalHardDrive
{
	return _internal;
}

- (NSString *)diskImagePath
{
	return _imagePath;
}

- (BOOL)isiPod
{
	BOOL isDir;
    NSFileManager *fm = [[NSFileManager alloc] init];
	return ([fm fileExistsAtPath:[[self path] stringByAppendingPathComponent:@"iPod_Control"] isDirectory:&isDir] && isDir);
}

- (NSComparisonResult)compare:(SLVolume *)b
{
	if ([self type] == [b type])
		return [[self name] caseInsensitiveCompare:[b name]];
	if ([self type] < [b type])
		return NSOrderedAscending;
	else if ([self type] > [b type])
		return NSOrderedDescending;
	return NSOrderedSame;
}

@end
