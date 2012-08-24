//
//  SLVolume.m
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 - 2011 Kevin Wojniak. All rights reserved.
//

#import "SLVolume.h"
#import <DiskArbitration/DiskArbitration.h>
#import <DiscRecording/DiscRecording.h>
#import <DiskArbitration/DiskArbitration.h>
#import <IOKit/storage/IOStorageDeviceCharacteristics.h>
#import "NSTaskAdditions.h"


@implementation SLVolume

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
					SLVolume *vol = [[SLVolume alloc] initWithStatfs:&buf[i] mountedDiskImages:diskImages];
					if (vol) {
						[volumes addObject:vol];
						[vol release];
					}
				}
			}
			free(buf);
		}
	}
	[volumes sortUsingSelector:@selector(compare:)];
	return volumes;
}

- (id)initWithStatfs:(struct statfs *)statfs mountedDiskImages:(NSDictionary *)diskImages
{
	if ([super init])
	{
		NSString *fileSystemType = [NSString stringWithCString:statfs->f_fstypename encoding:NSUTF8StringEncoding];
		NSString *path = [NSString stringWithUTF8String:statfs->f_mntonname];
		//NSLog(@"%@: %@", [path lastPathComponent], fileSystemType);
		if (!([path isEqualToString:@"/"] || [path hasPrefix:@"/Volumes"]))
		{
			[self release];
			return nil;
		}
		
		if ((statfs->f_flags & MNT_LOCAL) == MNT_LOCAL)
			_local = YES;
		if ((statfs->f_flags & MNT_ROOTFS) == MNT_ROOTFS)
			_root = YES;
		
		_path = [path copy];		
		_name = [[[[[NSFileManager alloc] init] autorelease] displayNameAtPath:path] copy];

		BOOL gotCatalogInfo = NO;
		FSRef ref;
		CFURLGetFSRef((CFURLRef)[NSURL fileURLWithPath:[self path]], &ref);
		FSCatalogInfo catalogInfo;
		gotCatalogInfo = (FSGetCatalogInfo(&ref, kFSCatInfoVolume, &catalogInfo, NULL, NULL, NULL) == noErr);
		
		if ([self isLocal] == NO)
		{
			_type = SLVolumeNetwork;
			
			if (gotCatalogInfo)
			{
				CFURLRef hostURL = NULL;
				FSCopyURLForVolume(catalogInfo.volume, &hostURL);
				if (hostURL)
				{
					_hostURL = [(NSURL *)hostURL copy];
					CFRelease(hostURL);
					
					if ([[_hostURL host] isEqualToString:@"idisk.mac.com"]) {
						_type = SLVolumeiDisk;
					} else if ([[_hostURL scheme] isEqualToString:@"ftp"]) {
						_type = SLVolumeFTP;
					} else if ([[_hostURL scheme] isEqualToString:@"afp"]) {
						// keep as SLVolumeNetwork
					} else {
						if ([fileSystemType isEqualToString:@"webdav"]) {
							_type = SLVolumeWebDAV;
						} else {
							NSLog(@"uknown URL: %@ (%@)", _hostURL, fileSystemType);
						}
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
					_imagePath = [imgPath retain];
					_type = SLVolumeDiskImage;
				}
			}

			if (gotCatalogInfo)
			{
				// for use with FSGetVolumeInfo
				//> filesystemID    signature    format
				//>     0            'BD'        HFS
				//>     0            'H+'        HFS+
				//>     0            0xD2D7        MFS
				//>     0            'AG'        ISO 9960
				//					(0x4147)		'
				//		'cu'			'			'
				//		(0x6375)
				//>     0            'BB'        High Sierra
				//>     'cu'        'JH'        Audio CD
				//>     0x55DF        0x75DF        DVD-ROM
				//>     'as'        any            above formats over AppleShare
				//>     'IS'        'BD'        MS-DOS
				
				//		0			0x482B		disk image
				//		0			0x4244		cd-rom
				//	0x4A48 (JH)		0x4244 (BD)
				
				
				FSVolumeInfo volumeInfo;
				if (FSGetVolumeInfo(catalogInfo.volume, 0, NULL, kFSVolInfoFSInfo, &volumeInfo, NULL, NULL) == noErr)
				{
					if (((volumeInfo.filesystemID == 0) && (volumeInfo.signature == 0x4244)) ||
						((volumeInfo.filesystemID == 0x6375) && (volumeInfo.signature == 0x4147)))
					{
						_type = SLVolumeCDROM;
					}
					else if ((volumeInfo.filesystemID == 0x4A48) && (volumeInfo.signature == 0x4244))
					{
						_type = SLVolumeAudioCDROM;
					}
					
					/*NSLog(@"%@: %02X (%c%c) - %02X (%c%c)",
						  [self name],
						  volumeInfo.filesystemID,
						  (volumeInfo.filesystemID%0xFF00)>>8,
						  volumeInfo.filesystemID&0x00FF,
						  volumeInfo.signature,
						  (volumeInfo.signature&0xFF00)>>8,
						  volumeInfo.signature&0x00FF);*/
				}
			}
			
			CFStringRef devicePath = NULL;
			
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
						if (!CFDictionaryGetValueIfPresent(desc, kDADiskDescriptionDeviceInternalKey, (void *)&isInternal)) {
							isInternal = kCFBooleanFalse;
						}
						if (!CFDictionaryGetValueIfPresent(desc, kDADiskDescriptionMediaEjectableKey, (void *)&isEjectable)) {
							isEjectable = kCFBooleanFalse;
						}
						if (!CFDictionaryGetValueIfPresent(desc, kDADiskDescriptionDeviceModelKey, (void *)&deviceModel)) {
							deviceModel = NULL;
						}
						if (!CFDictionaryGetValueIfPresent(desc, kDADiskDescriptionDevicePathKey, (void *)&devicePath)) {
							devicePath = NULL;
						}
						
						// 2nd check for disk images..
						if (([self type] != SLVolumeDiskImage) && ([(NSString *)deviceModel isEqualToString:@"Disk Image"]))
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
						
						CFRelease(desc);
					}
					CFRelease(disk);
				}
				CFRelease(session);
			}
			
			// check for a DVD. TODO: replace this with DiskArb checks.
			if (devicePath) {
				DRDevice *dvdDevice = [DRDevice deviceForBSDName:[NSString stringWithCString:statfs->f_mntfromname encoding:NSUTF8StringEncoding]]; //deviceForIORegistryEntryPath:(NSString *)devicePath];
				if ((dvdDevice != nil) && ([dvdDevice mediaIsPresent]))
				{
					if ([[dvdDevice mediaType] hasPrefix:@"DRDeviceMediaTypeDVD"])
						_type = SLVolumeDVD;
					else if ([[dvdDevice mediaType] hasPrefix:@"DRDeviceMediaTypeCD"])
						_type = SLVolumeCDROM;
				}
				else
				{
					if ([fileSystemType isEqualToString:@"udf"])
						_type = SLVolumeDVD;
				}
			}
		}
	}
	
	return self;
}

- (void)dealloc
{
	[_path release];
	[_name release];
	[_image release];
	[_hostURL release];
	[_imagePath release];

	[super dealloc];
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
	return [[_path retain] autorelease];
}

- (NSString *)name
{
	return [[_name retain] autorelease];
}

- (NSImage *)image
{
	if (!_image) {
		_image = [[[NSWorkspace sharedWorkspace] iconForFile:_path] copy];
	}
	return [[_image retain] autorelease];
}

- (BOOL)isLocal
{
	return _local;
}

- (BOOL)isRoot
{
	return _root;
}

void volumeUnmountCallback(FSVolumeOperation volumeOp, void *clientData, OSStatus err, FSVolumeRefNum volumeRefNum, pid_t dissenter)
{
	if (err != noErr) {
		NSLog(@"callback err: %ld", (long)err);
	}
}

- (BOOL)eject
{
	BOOL ret = NO;
	
	ret = [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:[self path]];
	
	if (!ret)
	{
		FSRef ref;
		if (FSPathMakeRef((const UInt8 *)[[self path] fileSystemRepresentation], &ref, NULL) == noErr)
		{
			FSCatalogInfo catalogInfo;
			if (FSGetCatalogInfo (&ref, kFSCatInfoVolume, &catalogInfo, NULL, NULL, NULL) == noErr)
			{
				//pid_t *dissenter = NULL;
				FSVolumeUnmountUPP unmountUPP = NewFSVolumeUnmountUPP(volumeUnmountCallback);
				FSVolumeOperation volumeOp;
				if (FSCreateVolumeOperation(&volumeOp) == noErr) {
					if (FSUnmountVolumeAsync(catalogInfo.volume, 0, volumeOp, NULL, unmountUPP, CFRunLoopGetMain(), kCFRunLoopDefaultMode) == noErr)
					//if (FSUnmountVolumeSync(catalogInfo.volume, 0, dissenter) == noErr)
						ret = YES;
					FSDisposeVolumeOperation(volumeOp);
				}
			}
		}
	}
	
	return ret;
}

- (BOOL)showInFinder
{
	return [[NSWorkspace sharedWorkspace] openFile:[self path]];
}

- (SLVolumeType)type
{
	return _type;
}

- (NSURL *)hostURL
{
	return [[_hostURL retain] autorelease];
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
	return ([[NSFileManager defaultManager] fileExistsAtPath:[[self path] stringByAppendingPathComponent:@"iPod_Control"] isDirectory:&isDir] && isDir);
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
