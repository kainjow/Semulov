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
#define SLShowUnmountedVolumes  @"SLShowUnmountedVolumes"
#define SLIgnoredVolumes        @"SLIgnoredVolumes"
#define SLReverseChooseAction   @"SLReverseChooseAction"
#define SLCustomIconPattern     @"SLCustomIconPattern"
#define SLCustomIconColor       @"SLCustomIconColor"


@interface SLController (Private)
- (void)setupBindings;
- (void)setupStatusItem;
- (void)updateStatusItemMenu;
- (void)updateStatusItemMenuWithVolumes:(NSArray *)volumes;
- (void)updateStatusItemIcon;
@end

@implementation SLController

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithBool:YES], SLShowVolumesNumber,
		[NSNumber numberWithBool:NO], SLShowStartupDisk,
		[NSNumber numberWithBool:NO], SLShowEjectAll,
		[NSNumber numberWithBool:NO], SLLaunchAtStartup,
		[NSNumber numberWithBool:NO], SLShowUnmountedVolumes,
        [NSNumber numberWithBool:NO], SLReverseChooseAction,
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
	
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(handleMount:) name:NSWorkspaceDidMountNotification object:nil];
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(handleUnmount:) name:NSWorkspaceDidUnmountNotification object:nil];
	
	deviceManager = [[SLDeviceManager alloc] init];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(unmountedVolumesChanged:) name:SLDeviceManagerUnmountedVolumesDidChangeNotification object:nil];
	
	[self setupBindings];
	
	// At startup make sure we're in the login items if the pref is set (user may have manually removed us)
	if ([[NSUserDefaults standardUserDefaults] boolForKey:SLLaunchAtStartup]) {
		[NSApp addToLoginItems];
	}
    
    // Handle Command-W for open windows
    [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyDownMask handler:^NSEvent* (NSEvent *event){
        if ([event modifierFlags] & NSCommandKeyMask && [[event characters] characterAtIndex:0] == 'w') {
            NSWindow *win = [[NSApp windows] lastObject];
            if (win) {
                [win performClose:nil];
                return nil;
            }
        }
        return event;
    }];
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
    [sdc addObserver:self forKeyPath:@"values."SLReverseChooseAction options:0 context:SLReverseChooseAction];
    [sdc addObserver:self forKeyPath:@"values."SLCustomIconPattern options:0 context:SLCustomIconPattern];
    [sdc addObserver:self forKeyPath:@"values."SLCustomIconColor options:0 context:SLCustomIconColor];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSString *ctx = (NSString *)context;
	if ([ctx isEqualToString:SLLaunchAtStartup]) {
		if ([[NSUserDefaults standardUserDefaults] boolForKey:SLLaunchAtStartup]) {
			[NSApp addToLoginItems];
		} else {
			[NSApp removeFromLoginItems];
		}
    } else {
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

    NSImage *ejectImageAlt = [[[NSImage imageNamed:@"Eject"] copy] autorelease];
    [ejectImageAlt setTemplate:YES];
    [_statusItem setAlternateImage:ejectImageAlt];

    [self updateStatusItemIcon];
	[self updateStatusItemMenu];
}

- (NSImage *)colorImage:(NSImage *)image withColor:(NSColor *)color
{
    NSImage *newImage = [[[NSImage alloc] initWithSize:[image size]] autorelease];
    [newImage lockFocus];
    [image drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
    [color set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, [image size].width, [image size].height), NSCompositeSourceAtop);
    [newImage unlockFocus];
    return newImage;
}

- (void)updateStatusItemIcon
{
    NSImage *baseImage = [NSImage imageNamed:@"Eject"];
    BOOL setDefault = YES;
    if (NSClassFromString(@"NSRegularExpression")) { // NSRegularExpressionSearch only available on 10.7+
        NSString *iconPattern = [[NSUserDefaults standardUserDefaults] objectForKey:SLCustomIconPattern];
        NSData *iconColorData = [[NSUserDefaults standardUserDefaults] objectForKey:SLCustomIconColor];
        NSColor *iconColor = iconColorData ? (NSColor *)[NSUnarchiver unarchiveObjectWithData:iconColorData] : nil;
        if (iconPattern && iconColor && [iconPattern length] > 0) {
            for (SLVolume *vol in _volumes) {
                if ([vol.name rangeOfString:iconPattern options:NSCaseInsensitiveSearch|NSRegularExpressionSearch].location != NSNotFound) {
                    [_statusItem setImage:[self colorImage:[[baseImage copy] autorelease] withColor:iconColor]];
                    setDefault = NO;
                    break;
                }
            }
        }
    }
    if (setDefault) {
        [_statusItem setImage:[[baseImage copy] autorelease]];
    }
}

- (BOOL)volumeCanBeEjected:(SLVolume *)volume
{
	return ![volume isRoot] && ![self volumeIsOnIgnoreList:volume.name];
}

- (void)updateStatusItemMenu
{
	dispatch_async(queue, ^{
        @autoreleasepool {
		@try {
			NSArray *volumes = [SLVolume allVolumes];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self updateStatusItemMenuWithVolumes:volumes];
                [self updateStatusItemIcon];
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
	[_statusItem setMenu:[[[NSMenu alloc] init] autorelease]];
	
	NSMenu *menu = [[[NSMenu alloc] init] autorelease];
	
	NSDictionary *defaultValues = [[NSUserDefaultsController sharedUserDefaultsController] values];
	BOOL showVolumesNumber = [[defaultValues valueForKey:SLShowVolumesNumber] boolValue];
	BOOL showStartupDisk = [[defaultValues valueForKey:SLShowStartupDisk] boolValue];
	BOOL showEjectAll = [[defaultValues valueForKey:SLShowEjectAll] boolValue];
	BOOL showUnmountedVolumes = [[defaultValues valueForKey:SLShowUnmountedVolumes] boolValue];
    BOOL reverseAction = [[defaultValues valueForKey:SLReverseChooseAction] boolValue];
	
    volumes = [self filterVolumes:volumes];
	if (_volumes != volumes) {
		[_volumes release];
		_volumes = [volumes retain];
	}
	SLVolumeType _lastType = -1;
	NSInteger vcount = 0;
	NSMenuItem *titleMenu = nil, *menuItem = nil, *altMenu = nil;
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
			else if (_lastType == SLVolumeFTP)
				titleName = NSLocalizedStringFromTable(@"FTP", @"Labels", nil);
			else if (_lastType == SLVolumeWebDAV)
				titleName = NSLocalizedStringFromTable(@"WebDAV", @"Labels", nil);
			else if (_lastType == SLVolumeDiskImage)
				titleName = NSLocalizedStringFromTable(@"Disk Images", @"Labels", nil);
			else if (_lastType == SLVolumeDVD)
				titleName = NSLocalizedStringFromTable(@"DVDs", @"Labels", nil);
			else if (_lastType == SLVolumeCD)
				titleName = NSLocalizedStringFromTable(@"CDs", @"Labels", nil);
			else if (_lastType == SLVolumeHardDrive)
				titleName = NSLocalizedStringFromTable(@"Hard Drives", @"Labels", nil);
			else if (_lastType == SLVolumeRAMDisk)
				titleName = NSLocalizedStringFromTable(@"RAM Disks", @"Labels", nil);
            else if (_lastType == SLVolumeBluray)
                titleName = NSLocalizedStringFromTable(@"Blurays", @"Labels", nil);
			titleMenu = [[NSMenuItem alloc] initWithTitle:titleName action:nil keyEquivalent:@""];
		}
		
		SEL ejectAction = (![self volumeCanBeEjected:vol] ? nil : @selector(doEject:));
        SEL showAction = @selector(doShowInFinder:);
        NSString *mainTitle = [vol name];
        NSString *altTitle;
        SEL mainAction, altAction;
        if (reverseAction) {
            mainAction = showAction;
            altAction = ejectAction;
            altTitle = [NSString stringWithFormat:NSLocalizedString(@"Eject %@", nil), [vol name]];
        } else {
            mainAction = ejectAction;
            altAction = showAction;
            altTitle = [NSString stringWithFormat:NSLocalizedString(@"Show %@", nil), [vol name]];
        }
        
		NSImage *mainItemImage = [[vol image] slResize:NSMakeSize(16, 16)];
        
		// setup the main item
		menuItem = [[[NSMenuItem alloc] initWithTitle:mainTitle action:mainAction keyEquivalent:@""] autorelease];
		[menuItem setRepresentedObject:vol];
		[menuItem setImage:mainItemImage];
		[menuItem setIndentationLevel:1];
		[menuItem setTarget:self];
		
		// setup the alternate item
		altMenu = [[[NSMenuItem alloc] initWithTitle:altTitle action:altAction keyEquivalent:@""] autorelease];
		[altMenu setAlternate:YES];
		[altMenu setKeyEquivalentModifierMask:NSAlternateKeyMask];
		[altMenu setRepresentedObject:vol];
		[altMenu setImage:mainItemImage];
		[altMenu setIndentationLevel:1];
		[altMenu setTarget:self];
		
		if (titleMenu)
		{
			[menu addItem:titleMenu];
			[titleMenu release];
			titleMenu = nil;
		}

		[menu addItem:menuItem];
		[menu addItem:altMenu];
		
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
            SLVolume *vol = [self volumeWithMountPath:devicePath];
            if (vol) {
                [[SLGrowlController sharedController] postVolumeMounted:vol];
            }
        });
    });
}

- (void)handleUnmount:(NSNotification *)not
{
    SLVolume *vol = [self volumeWithMountPath:[[not userInfo] objectForKey:@"NSDevicePath"]];
    if (vol) {
        [[SLGrowlController sharedController] postVolumeUnmounted:vol];
    }

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
