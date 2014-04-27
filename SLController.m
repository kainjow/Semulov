//
//  SLController.m
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 - 2011 Kevin Wojniak. All rights reserved.
//

#import "SLController.h"
#import "SLVolume.h"
#import "SLGrowlController.h"
#import "SLNSImageAdditions.h"
#import "NSApplication+LoginItems.h"
#import "SLDeviceManager.h"
#import "SLUnmountedVolume.h"


#define SLShowVolumesNumber		@"SLShowVolumesNumber"
#define SLShowStartupDisk		@"SLShowStartupDisk"
#define SLShowEjectAll			@"SLShowEjectAll"
#define SLLaunchAtStartup		@"SLLaunchAtStartup"
#define SLDisableDiscardWarning	@"SLDisableDiscardWarning"
#define SLShowUnmountedVolumes  @"SLShowUnmountedVolumes"
#define SLIgnoredVolumes        @"SLIgnoredVolumes"


@interface SLController (Private)
- (void)setupBindings;
- (void)setupStatusItem;
- (void)updateStatusItemMenu;
- (void)updateStatusItemMenuWithVolumes:(NSArray *)volumes;
@end

@implementation SLController

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithBool:YES], SLShowVolumesNumber,
		[NSNumber numberWithBool:NO], SLShowStartupDisk,
		[NSNumber numberWithBool:NO], SLShowEjectAll,
		[NSNumber numberWithBool:NO], SLLaunchAtStartup,
		[NSNumber numberWithBool:NO], SLDisableDiscardWarning,
		[NSNumber numberWithBool:NO], SLShowUnmountedVolumes,
        [NSNumber numberWithBool:YES], @"SLPostGrowlNotifications",
		nil]];
}

- (id)init
{
    self = [super init];
    if (self != nil) {
        queue = dispatch_queue_create("com.kainjow.semulov.update", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    }
    return self;
}

- (void)dealoc
{
	[[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self];
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
	
	[[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
	[_statusItem release];

	[_volumes release];
	[_prefs release];

	[super dealloc];
}

- (void)updateIgnoredVolumes
{
    [ignoredVolumes release];
    ignoredVolumes = nil;
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:@"SLIgnoredVolumes"];
    if ([obj isKindOfClass:[NSString class]]) {
        ignoredVolumes = [[obj componentsSeparatedByString:@"\n"] retain];
    }
}

#pragma mark -
#pragma mark App Delegate

- (void)applicationDidFinishLaunching:(NSNotification *)notif
{
    [self updateIgnoredVolumes];
	[self setupStatusItem];
	
	[[SLGrowlController sharedController] setup];
	
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(handleMount:) name:NSWorkspaceDidMountNotification object:nil];
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(handleUnmount:) name:NSWorkspaceDidUnmountNotification object:nil];
	
	deviceManager = [[SLDeviceManager alloc] init];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(unmountedVolumesChanged:) name:SLDeviceManagerUnmountedVolumesDidChangeNotification object:nil];
	
	[self setupBindings];
	
	// At startup make sure we're in the login items if the pref is set (user may have manually removed us)
	if ([[NSUserDefaults standardUserDefaults] boolForKey:SLLaunchAtStartup]) {
		[NSApp addToLoginItems];
	}
}

#pragma mark -
#pragma mark Bindings

- (void)setupBindings
{
	NSUserDefaultsController *sdc = [NSUserDefaultsController sharedUserDefaultsController];
	[sdc addObserver:self forKeyPath:@"values.SLShowVolumesNumber" options:0 context:SLShowVolumesNumber];
	[sdc addObserver:self forKeyPath:@"values.SLShowStartupDisk" options:0 context:SLShowStartupDisk];
	[sdc addObserver:self forKeyPath:@"values.SLShowEjectAll" options:0 context:SLShowEjectAll];
	[sdc addObserver:self forKeyPath:@"values."SLLaunchAtStartup options:0 context:SLLaunchAtStartup];
	[sdc addObserver:self forKeyPath:@"values.SLShowUnmountedVolumes" options:0 context:SLShowUnmountedVolumes];
    [sdc addObserver:self forKeyPath:@"values."SLIgnoredVolumes options:0 context:SLIgnoredVolumes];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([(NSString *)context isEqualToString:SLLaunchAtStartup])
	{
		if ([[NSUserDefaults standardUserDefaults] boolForKey:SLLaunchAtStartup])
		{
			// add us to the login items
			[NSApp addToLoginItems];
		}
		else
		{
			[NSApp removeFromLoginItems];
		}
	}
	else
	{
        if ([(NSString*)context isEqualToString:SLIgnoredVolumes]) {
            [self updateIgnoredVolumes];
        }
		[self updateStatusItemMenu];
	}
}

#pragma mark -
#pragma mark Status Item

- (void)setupStatusItem
{
	if (_statusItem)
	{
		[[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
		[_statusItem release];
	}
	_statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
	[_statusItem setHighlightMode:YES];
	
	NSImage *ejectImage = [NSImage imageNamed:@"Eject"];
	[ejectImage setTemplate:YES];
	[_statusItem setImage:ejectImage];
	[self updateStatusItemMenu];
}

- (BOOL)volumeCanBeEjected:(SLVolume *)volume
{
	if ([volume isInternalHardDrive] == NO && [volume isRoot] == NO)
		return YES;
	
	return YES;
}

- (void)updateStatusItemMenu
{
	dispatch_async(queue, ^{
        @autoreleasepool {
		@try {
			NSArray *volumes = [SLVolume allVolumes];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self updateStatusItemMenuWithVolumes:volumes];
			});
		} @catch (NSException *ex) {
			NSLog(@"Caught exception: %@", ex);
		}
        }
	});
}

- (BOOL)volumeIsOnIgnoreList:(NSString *)volume
{
    for (NSString *ignoredVol in ignoredVolumes) {
        if ([ignoredVol compare:volume options:NSCaseInsensitiveSearch] == NSOrderedSame) {
            return YES;
        }
    }
    return NO;
}

- (NSArray *)filterVolumes:(NSArray *)volumes
{
    NSMutableArray *newVolumes = [NSMutableArray array];
    for (SLVolume *vol in volumes) {
        if ([self volumeIsOnIgnoreList:vol.name] == NO) {
            [newVolumes addObject:vol];
        }
    }
    return newVolumes;
}

- (void)updateStatusItemMenuWithVolumes:(NSArray *)volumes
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	[_statusItem setMenu:[[[NSMenu alloc] init] autorelease]];
	
	NSMenu *menu = [[[NSMenu alloc] init] autorelease];
	
	NSDictionary *defaultValues = [[NSUserDefaultsController sharedUserDefaultsController] values];
	BOOL showVolumesNumber = [[defaultValues valueForKey:SLShowVolumesNumber] boolValue];
	BOOL showStartupDisk = [[defaultValues valueForKey:SLShowStartupDisk] boolValue];
	BOOL showEjectAll = [[defaultValues valueForKey:SLShowEjectAll] boolValue];
	BOOL showUnmountedVolumes = [[defaultValues valueForKey:SLShowUnmountedVolumes] boolValue];
	
    volumes = [self filterVolumes:volumes];
	if (_volumes != volumes) {
		[_volumes release];
		_volumes = [volumes retain];
	}
	SLVolumeType _lastType = -1;
	NSInteger vcount = 0;
	NSMenuItem *titleMenu = nil, *menuItem = nil, *altMenu = nil, *altaltMenu;
	NSString *titleName = nil;
	
	for (SLVolume *vol in _volumes)
	{
		if ((showStartupDisk == NO && [vol isRoot]))
		{
			continue;
		}
		
		if ([vol type] != _lastType)
		{
			_lastType = [vol type];
			
			if (_lastType == SLVolumeDrive)
				titleName = NSLocalizedStringFromTable(@"Volumes", @"Labels", nil);
			else if (_lastType == SLVolumeRoot)
				titleName = NSLocalizedStringFromTable(@"Startup Disk", @"Labels", nil);
			else if (_lastType == SLVolumeiPod)
				titleName = NSLocalizedStringFromTable(@"iPods", @"Labels", nil);
			else if (_lastType == SLVolumeNetwork)
				titleName = NSLocalizedStringFromTable(@"Network", @"Labels", nil);
			else if (_lastType == SLVolumeiDisk)
				titleName = NSLocalizedStringFromTable(@"iDisks", @"Labels", nil);
			else if (_lastType == SLVolumeFTP)
				titleName = NSLocalizedStringFromTable(@"FTP", @"Labels", nil);
			else if (_lastType == SLVolumeWebDAV)
				titleName = NSLocalizedStringFromTable(@"WebDAV", @"Labels", nil);
			else if (_lastType == SLVolumeDiskImage)
				titleName = NSLocalizedStringFromTable(@"Disk Images", @"Labels", nil);
			else if (_lastType == SLVolumeDVD)
				titleName = NSLocalizedStringFromTable(@"DVDs", @"Labels", nil);
			else if (_lastType == SLVolumeDVDVideo)
				titleName = NSLocalizedStringFromTable(@"Video DVDs", @"Labels", nil);
			else if (_lastType == SLVolumeCDROM)
				titleName = NSLocalizedStringFromTable(@"CDs", @"Labels", nil);
			else if (_lastType == SLVolumeAudioCDROM)
				titleName = NSLocalizedStringFromTable(@"Audio CDs", @"Labels", nil);
			else if (_lastType == SLVolumeHardDrive)
				titleName = NSLocalizedStringFromTable(@"Hard Drives", @"Labels", nil);
			else if (_lastType == SLVolumeRAMDisk)
				titleName = NSLocalizedStringFromTable(@"RAM Disks", @"Labels", nil);
			titleMenu = [[NSMenuItem alloc] initWithTitle:titleName action:nil keyEquivalent:@""];
		}
		
		SEL mainItemAction = ([vol isRoot] ? nil : @selector(doEject:));
		NSImage *mainItemImage = [[vol image] slResize:NSMakeSize(16, 16)];
		
		// setup the main item
		menuItem = [[[NSMenuItem alloc] initWithTitle:[vol name] action:mainItemAction keyEquivalent:@""] autorelease];
		[menuItem setRepresentedObject:vol];
		[menuItem setImage:mainItemImage];
		[menuItem setIndentationLevel:1];
		[menuItem setTarget:self];
		if (![self volumeCanBeEjected:vol])
			[menuItem setAction:nil];
		
		// setup the first alternate item
		altMenu = [[[NSMenuItem alloc] initWithTitle:[vol name] action:mainItemAction keyEquivalent:@""] autorelease];
		[altMenu setAlternate:YES];
		[altMenu setKeyEquivalentModifierMask:NSAlternateKeyMask | NSCommandKeyMask];
		[altMenu setRepresentedObject:vol];
		[altMenu setImage:mainItemImage];
		[altMenu setIndentationLevel:1];
		[altMenu setTarget:self];
		if ([vol type] == SLVolumeDiskImage)
		{
			[altMenu setTitle:[NSString stringWithFormat:NSLocalizedString(@"Discard %@", nil), [vol name]]];
			[altMenu setAction:@selector(doEjectAndDeleteDiskImage:)];
		}
		if (![self volumeCanBeEjected:vol])
			[altMenu setAction:nil];

		// setup the second alternate item
		altaltMenu = [[[NSMenuItem alloc] initWithTitle:[vol name] action:mainItemAction keyEquivalent:@""] autorelease];
		[altaltMenu setAlternate:YES];
		[altaltMenu setKeyEquivalentModifierMask:NSAlternateKeyMask];
		[altaltMenu setRepresentedObject:vol];
		[altaltMenu setImage:mainItemImage];
		[altaltMenu setIndentationLevel:1];
		[altaltMenu setTitle:[NSString stringWithFormat:NSLocalizedString(@"Show %@", nil), [vol name]]];
		[altaltMenu setAction:@selector(doShowInFinder:)];
		[altaltMenu setTarget:self];
		
		if (titleMenu)
		{
			[menu addItem:titleMenu];
			[titleMenu release];
			titleMenu = nil;
		}

		[menu addItem:menuItem];
		[menu addItem:altMenu];
		[menu addItem:altaltMenu];
		
		vcount++;
	}
	
	if (showVolumesNumber)
		[_statusItem setTitle:[NSString stringWithFormat:@"%ld", (long)vcount]];
	else
		[_statusItem setTitle:nil];
	
	if (vcount)
	{
		if (showEjectAll)
		{
			[menu addItem:[NSMenuItem separatorItem]];
			[menu addItemWithTitle:NSLocalizedString(@"Eject All", nil) action:@selector(doEjectAll:) keyEquivalent:@""];
		}
		
		[menu addItem:[NSMenuItem separatorItem]];
	}
	
	if (showUnmountedVolumes) {
        NSMutableArray *unmountedVols = [NSMutableArray array];
        for (SLUnmountedVolume *uvol in deviceManager.unmountedVolumes) {
            if ([self volumeIsOnIgnoreList:uvol.name] == NO) {
                [unmountedVols addObject:uvol];
            }
        }
		if ([unmountedVols count] > 0) {
			[[menu addItemWithTitle:NSLocalizedString(@"Unmounted", nil) action:@selector(doEjectAll:) keyEquivalent:@""] setAction:nil];
			for (SLUnmountedVolume *uvol in unmountedVols) {
				menuItem = [[[NSMenuItem alloc] initWithTitle:uvol.name action:@selector(doMount:) keyEquivalent:@""] autorelease];
				[menuItem setIndentationLevel:1];
				[menuItem setRepresentedObject:uvol.diskID];
				[menuItem setImage:[uvol.icon slResize:NSMakeSize(16, 16)]];
				[menu addItem:menuItem];
			}
			[menu addItem:[NSMenuItem separatorItem]];
		}
	}
	
	NSMenuItem *slMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Semulov" action:nil keyEquivalent:@""] autorelease];
	NSMenu *slSubmenu = [[[NSMenu alloc] init] autorelease];
	[slSubmenu addItemWithTitle:NSLocalizedString(@"About", nil) action:@selector(doAbout:) keyEquivalent:@""];
	[slSubmenu addItem:[NSMenuItem separatorItem]];
	[slSubmenu addItemWithTitle:NSLocalizedString(@"Preferences\u2026", nil) action:@selector(doPrefs:) keyEquivalent:@""];
	[slSubmenu addItem:[NSMenuItem separatorItem]];
	[slSubmenu addItemWithTitle:NSLocalizedString(@"Send Feedback", nil) action:@selector(doFeedback:) keyEquivalent:@""];
	[slSubmenu addItem:[NSMenuItem separatorItem]];
	[slSubmenu addItemWithTitle:NSLocalizedString(@"Quit", nil) action:@selector(doQuit:) keyEquivalent:@""];
	[slMenuItem setSubmenu:slSubmenu];
	[menu addItem:slMenuItem];

	[_statusItem setMenu:menu];
	
	[pool release];
}

#pragma mark -
#pragma mark Mount/Unmount

- (SLVolume *)volumeWithMountPath:(NSString *)mountPath
{
	SLVolume *vol = nil;
	for (vol in _volumes) {
		if ([[vol path] isEqualToString:mountPath])
			return vol;
	}
	return nil;
}

- (void)handleMount:(NSNotification *)not
{
	[self updateStatusItemMenu];
	
    NSString *devicePath = [[not userInfo] objectForKey:@"NSDevicePath"];
    // post on the serial queue so that the volumes list is reloaded by the time we post the note.
    dispatch_async(queue, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[SLGrowlController sharedController] postVolumeMounted:[self volumeWithMountPath:devicePath]];
        });
    });
}

- (void)handleUnmount:(NSNotification *)not
{
	[[SLGrowlController sharedController] postVolumeUnmounted:
		[self volumeWithMountPath:[[not userInfo] objectForKey:@"NSDevicePath"]]];

	[self updateStatusItemMenu];
}

- (void)unmountedVolumesChanged:(NSNotification *)notif
{
	[self updateStatusItemMenu];
}

#pragma mark -
#pragma mark Menu Actions

- (void)doAbout:(id)sender
{
	[NSApp activateIgnoringOtherApps:YES];
	[NSApp orderFrontStandardAboutPanel:nil];
}

- (void)doQuit:(id)sender
{
	[NSApp terminate:nil];
}

- (BOOL)ejectVolumeWithFeedback:(SLVolume *)volume
{
	if (![volume eject])
	{
		[NSApp activateIgnoringOtherApps:YES];
		NSRunAlertPanel(NSLocalizedString(@"Unmount failed", nil), NSLocalizedString(@"Failed to eject volume.", nil), nil, nil, nil);
		return NO;
	}
	return YES;
}

- (void)doEject:(id)sender
{
	[self ejectVolumeWithFeedback:[sender representedObject]];
}

- (void)doEjectAll:(id)sender
{
	NSArray *volumesCopy = [[_volumes copy] autorelease];
	for (SLVolume *vol in volumesCopy) {
		if ([self volumeCanBeEjected:vol]) {
			[vol eject];
		}
	}
}

- (void)doShowInFinder:(id)sender
{
	if (![[sender representedObject] showInFinder])
	{
		[NSApp activateIgnoringOtherApps:YES];
		NSBeep();
	}
}

- (void)doEjectAndDeleteDiskImage:(id)sender
{
	SLVolume *vol = [sender representedObject];
	NSString *imagePath = [vol diskImagePath];

	[NSApp activateIgnoringOtherApps:YES];

	if (![[NSFileManager defaultManager] fileExistsAtPath:imagePath])
	{
		NSRunAlertPanel(NSLocalizedString(@"Disk image not found", nil), NSLocalizedString(@"The corresponding disk image file for the mounted volume could not be found.", nil), nil, nil, nil);
		return;
	}
	
	BOOL showWarning = [[NSUserDefaults standardUserDefaults] boolForKey:@"SLDisableDiscardWarning"];
	if (
		(showWarning == YES) ||
		((showWarning == NO) && (NSRunAlertPanel(NSLocalizedString(@"Are you sure you want to unmount this volume and delete its associated disk image?", nil), NSLocalizedString(@"You cannot undo this action.", nil), NSLocalizedString(@"No", nil), NSLocalizedString(@"Yes", nil), nil) == NSCancelButton))
		)
	{
		if ([self ejectVolumeWithFeedback:vol])
			[[NSFileManager defaultManager] removeItemAtPath:imagePath error:nil];
	}
}

- (void)doMount:(id)sender
{
	[deviceManager mount:[sender representedObject]];
}

- (void)doFeedback:(id)sender
{
	NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
	NSString *urlString = [[NSString stringWithFormat:@"mailto:kainjow@kainjow.com?subject=Semulov %@ Feedback", appVersion] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]];
}

- (void)doPrefs:(id)sender
{
	if (_prefs == nil)
		_prefs = [[NSWindowController alloc] initWithWindowNibName:@"Preferences"];
	[_prefs window];
	[NSApp activateIgnoringOtherApps:YES];
	[_prefs showWindow:nil];
}

@end
