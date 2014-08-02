//
//  SLController.m
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 - 2014 Kevin Wojniak. All rights reserved.
//

#import "SLController.h"
#import "SLVolume.h"
#import "SLNotificationController.h"
#import "NSApplication+LoginItems.h"
#import "SLDiskManager.h"
#import "SLDiskImageManager.h"
#import "SLPreferencesController.h"
#import "MASShortcut+UserDefaults.h"
#import "SLPreferenceKeys.h"
#import <Sparkle/Sparkle.h>

@interface SLController (Private)
- (void)setupStatusItem;
- (void)updateStatusItemMenu;
- (void)updateStatusItemMenuWithVolumes:(NSArray *)volumes;
- (void)updateStatusItemIcon;
@end

@implementation SLController
{
	NSStatusItem *_statusItem;
    NSImage *_baseImage;
	NSArray *_volumes;
	SLPreferencesController *_prefs;
	SLDiskManager *deviceManager;
    dispatch_queue_t queue;
    NSArray *ignoredVolumes;
    SUUpdater *_updater;
}

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithBool:YES], SLShowVolumesNumber,
		[NSNumber numberWithBool:NO], SLShowStartupDisk,
		[NSNumber numberWithBool:NO], SLShowEjectAll,
		[NSNumber numberWithBool:NO], SLLaunchAtStartup,
		[NSNumber numberWithBool:NO], SLShowUnmountedVolumes,
        [NSNumber numberWithBool:NO], SLReverseChooseAction,
        @(NO), SLDisksLayout,
        @(NO), SLBlockMounts,
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

- (void)updateIgnoredVolumes
{
    ignoredVolumes = nil;
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:@"SLIgnoredVolumes"];
    if ([obj isKindOfClass:[NSString class]]) {
        ignoredVolumes = [obj componentsSeparatedByString:@"\n"];
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
	
	deviceManager = [[SLDiskManager alloc] init];
    NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
    deviceManager.blockMounts = [uds boolForKey:SLShowBlockMounts] && [uds boolForKey:SLBlockMounts];
    NSNotificationCenter *notifCenter = [NSNotificationCenter defaultCenter];
	[notifCenter addObserver:self selector:@selector(unmountedVolumesChanged:) name:SLDiskManagerUnmountedVolumesDidChangeNotification object:nil];
    [notifCenter addObserverForName:SLDiskManagerDidBlockMountNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSString *volumeName = [note.object objectForKey:(NSString *)kDADiskDescriptionVolumeNameKey];
        [SLNotificationController postVolumeMountBlocked:volumeName];
    }];
    
    [notifCenter addObserver:self selector:@selector(userDefaultsDidChange:) name:NSUserDefaultsDidChangeNotification object:uds];

	// At startup make sure we're in the login items if the pref is set (user may have manually removed us)
	if ([uds boolForKey:SLLaunchAtStartup]) {
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
    
    _updater = [SUUpdater sharedUpdater];
}

#pragma mark -
#pragma mark User Defaults

- (void)userDefaultsDidChange:(NSNotification *)note
{
    NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
    
    if ([uds boolForKey:SLLaunchAtStartup]) {
        [NSApp addToLoginItems];
    } else {
        [NSApp removeFromLoginItems];
    }
    
    deviceManager.blockMounts = [uds boolForKey:SLShowBlockMounts] && [uds boolForKey:SLBlockMounts];
    
    [self updateIgnoredVolumes];
    
    [self updateStatusItemMenu];
}

#pragma mark -
#pragma mark Status Item

- (void)setupStatusItem
{
	if (_statusItem)
	{
		[[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
	}
	_statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
	[_statusItem setHighlightMode:YES];

    _baseImage = [[NSImage imageNamed:@"Eject"] copy];
    [_statusItem setAlternateImage:[self colorImage:_baseImage withColor:[NSColor whiteColor]]];

    [self updateStatusItemIcon];
	[self updateStatusItemMenu];
}

- (NSImage *)colorImage:(NSImage *)image withColor:(NSColor *)color
{
    BOOL (^handler)(NSRect dstRect) = ^BOOL(NSRect dstRect) {
        [image drawAtPoint:NSMakePoint(NSMinX(dstRect), NSMinY(dstRect)) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        [color set];
        NSRectFillUsingOperation(NSMakeRect(NSMinX(dstRect), NSMinY(dstRect), NSWidth(dstRect), NSHeight(dstRect)), NSCompositeSourceAtop);
        return YES;
    };
    
    if ([NSImage respondsToSelector:@selector(imageWithSize:flipped:drawingHandler:)]) {
        // 10.8+ method
        return [NSImage imageWithSize:image.size flipped:NO drawingHandler:handler];
    } else {
        NSImage *newImage = [[NSImage alloc] initWithSize:image.size];
        [newImage lockFocus];
        (void)handler(NSMakeRect(0, 0, newImage.size.width, newImage.size.height));
        [newImage unlockFocus];
        return newImage;
    }
}

- (void)updateStatusItemIcon
{
    BOOL setDefault = YES;
    NSString *iconPattern = [[NSUserDefaults standardUserDefaults] objectForKey:SLCustomIconPattern];
    NSData *iconColorData = [[NSUserDefaults standardUserDefaults] objectForKey:SLCustomIconColor];
    NSColor *iconColor = iconColorData ? (NSColor *)[NSUnarchiver unarchiveObjectWithData:iconColorData] : nil;
    if (iconPattern && iconColor && [iconPattern length] > 0) {
        for (SLVolume *vol in _volumes) {
            if ([vol.name rangeOfString:iconPattern options:NSCaseInsensitiveSearch|NSRegularExpressionSearch].location != NSNotFound) {
                [_statusItem setImage:[self colorImage:_baseImage withColor:iconColor]];
                setDefault = NO;
                break;
            }
        }
    }
    if (setDefault) {
        NSImage *img = [_baseImage copy];
        img.template = YES;
        [_statusItem setImage:img];
    }
}

- (BOOL)objectCanBeEjected:(id)obj
{
    if ([obj isKindOfClass:[SLVolume class]]) {
        SLVolume *volume = (SLVolume *)obj;
        return ![volume isRoot] && ![self volumeIsOnIgnoreList:volume.name];
    }
    SLDisk *disk = (SLDisk *)obj;
    return !disk.isStartupDisk && ![self volumeIsOnIgnoreList:disk.name];
}

- (void)updateStatusItemMenu
{
	dispatch_async(queue, ^{
        @autoreleasepool {
		@try {
			NSArray *volumes = [SLVolume allVolumesWithDiskManager:deviceManager.diskImageManager];
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

- (NSImage *)shrinkImageForMenu:(NSImage *)image
{
    NSImage *img = [image copy];
    [img setSize:NSMakeSize(16, 16)];
    return img;
}

- (NSArray *)setupMenuItemsForMoutableObject:(id)obj reverseAction:(BOOL)reverseAction
{
    NSMenuItem *menuItem = nil;
    NSMenuItem *altMenuItem = nil;
    
    SEL mainAction = nil;
    SEL altAction = nil;
    NSString *mainTitle = [obj name];
    NSString *altTitle = nil;

    SLDisk *disk = [obj isKindOfClass:[SLDisk class]] ? (SLDisk *)obj : nil;
    
    if (disk && !disk.mounted) {
        mainAction = @selector(doMount:);
    } else {
        SEL ejectAction = (![self objectCanBeEjected:obj] ? nil : @selector(doEject:));
        SEL showAction = @selector(doShowInFinder:);
        if (reverseAction) {
            mainAction = showAction;
            altAction = ejectAction;
            altTitle = [NSString stringWithFormat:NSLocalizedString(@"Eject %@", nil), [obj name]];
        } else {
            mainAction = ejectAction;
            altAction = showAction;
            altTitle = [NSString stringWithFormat:NSLocalizedString(@"Show %@", nil), [obj name]];
        }
    }

    if (!mainTitle && disk) {
        mainTitle = disk.diskID;
    }
    if (!mainTitle) {
        mainTitle = @"";
    }
    
    NSImage *mainItemImage = [self shrinkImageForMenu:[obj isKindOfClass:[SLVolume class]] ? [obj image] : [obj icon]];
    
    menuItem = [[NSMenuItem alloc] initWithTitle:mainTitle action:mainAction keyEquivalent:@""];
    [menuItem setRepresentedObject:obj];
    [menuItem setImage:mainItemImage];
    [menuItem setIndentationLevel:1];
    [menuItem setTarget:self];
    
    if (disk && !disk.mounted) {
        NSAttributedString *astr = [[NSAttributedString alloc] initWithString:mainTitle attributes:@{
            NSForegroundColorAttributeName: [NSColor grayColor],
            NSFontAttributeName: [NSFont menuFontOfSize:14],
        }];
        menuItem.attributedTitle = astr;
    }
    
    if (altAction && altTitle) {
        altMenuItem = [[NSMenuItem alloc] initWithTitle:altTitle action:altAction keyEquivalent:@""];
        [altMenuItem setAlternate:YES];
        [altMenuItem setKeyEquivalentModifierMask:NSAlternateKeyMask];
        [altMenuItem setRepresentedObject:obj];
        [altMenuItem setImage:mainItemImage];
        [altMenuItem setIndentationLevel:1];
        [altMenuItem setTarget:self];
    }
    
    if (altMenuItem) {
        return @[menuItem, altMenuItem];
    }
    
    return @[menuItem];
}

- (void)updateStatusItemMenuWithVolumes:(NSArray *)volumes
{
	[_statusItem setMenu:[[NSMenu alloc] init]];
	
	NSMenu *menu = [[NSMenu alloc] init];
	
	NSDictionary *defaultValues = [[NSUserDefaultsController sharedUserDefaultsController] values];
	BOOL showVolumesNumber = [[defaultValues valueForKey:SLShowVolumesNumber] boolValue];
	BOOL showStartupDisk = [[defaultValues valueForKey:SLShowStartupDisk] boolValue];
	BOOL showEjectAll = [[defaultValues valueForKey:SLShowEjectAll] boolValue];
	BOOL showUnmountedVolumes = [[defaultValues valueForKey:SLShowUnmountedVolumes] boolValue];
    BOOL reverseAction = [[defaultValues valueForKey:SLReverseChooseAction] boolValue];
    BOOL disksLayout = [[defaultValues valueForKey:SLDisksLayout] boolValue];
	
    volumes = [self filterVolumes:volumes];
    if (_volumes != volumes) {
        _volumes = volumes;
    }
    NSMutableArray *volumesToDisplay = [NSMutableArray array];
    for (SLVolume *vol in volumes) {
        if (vol.isRoot && !showStartupDisk) {
            continue;
        }
        [volumesToDisplay addObject:vol];
    }
    
    NSMenuItem *ejectAllItem = nil;
    [MASShortcut unregisterGlobalShortcutWithUserDefaultsKey:SLEjectAllShortcut];

    if (disksLayout) {
        NSArray *disks = [deviceManager.disks sortedArrayUsingDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"diskID" ascending:YES]]];
        if (disks.count > 0) {
            for (SLDisk *disk in disks) {
                NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:disk.deviceName action:@selector(doEject:) keyEquivalent:@""];
                [menuItem setRepresentedObject:disk];
                NSImage *diskIcon;
                if (disk.isDiskImage && disk.diskImage) {
                    diskIcon = [[NSWorkspace sharedWorkspace] iconForFile:disk.diskImage];
                } else {
                    diskIcon = disk.icon;
                }
                [menuItem setImage:[self shrinkImageForMenu:diskIcon]];
                [menu addItem:menuItem];
                NSArray *children = [disk.children sortedArrayUsingDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"diskID" ascending:YES]]];
                if (!children.count && disk.mountable) {
                    children = @[disk];
                }
                for (SLDisk *childDisk in children) {
                    if (childDisk.isStartupDisk && !showStartupDisk) {
                        continue;
                    }
                    if (!childDisk.mounted && !showUnmountedVolumes) {
                        continue;
                    }
                    for (NSMenuItem *item in [self setupMenuItemsForMoutableObject:childDisk reverseAction:reverseAction]) {
                        [menu addItem:item];
                    }
                }
            }
            [menu addItem:[NSMenuItem separatorItem]];
        }
    } else {
        SLVolumeType _lastType = -1;
        NSMenuItem *titleMenu = nil;
        NSString *titleName = nil;
        
        for (SLVolume *vol in volumesToDisplay) {
            if ([vol type] != _lastType) {
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
            
            if (titleMenu) {
                [menu addItem:titleMenu];
                titleMenu = nil;
            }

            for (NSMenuItem *item in [self setupMenuItemsForMoutableObject:vol reverseAction:reverseAction]) {
                [menu addItem:item];
            }
        }
        
        if (volumesToDisplay.count > 0) {
            if (showEjectAll) {
                [menu addItem:[NSMenuItem separatorItem]];
                ejectAllItem = [menu addItemWithTitle:NSLocalizedString(@"Eject All", nil) action:@selector(doEjectAll:) keyEquivalent:@""];
                MASShortcut *shortcut = [MASShortcut shortcutWithData:[[NSUserDefaults standardUserDefaults] objectForKey:SLEjectAllShortcut]];
                if (shortcut && shortcut.isValid) {
                    ejectAllItem.keyEquivalent = shortcut.keyCodeStringForKeyEquivalent;
                    ejectAllItem.keyEquivalentModifierMask = shortcut.modifierFlags;
                    [MASShortcut registerGlobalShortcutWithUserDefaultsKey:SLEjectAllShortcut handler:^{
                        [self doEjectAll:ejectAllItem.representedObject];
                    }];
                }
            }
            
            [menu addItem:[NSMenuItem separatorItem]];
        }
        
        if (showUnmountedVolumes) {
            NSMutableArray *unmountedVols = [NSMutableArray array];
            for (SLDisk *uvol in deviceManager.unmountedDisks) {
                if ([self volumeIsOnIgnoreList:uvol.name] == NO) {
                    [unmountedVols addObject:uvol];
                }
            }
            if ([unmountedVols count] > 0) {
                [menu addItemWithTitle:NSLocalizedString(@"Unmounted", nil) action:nil keyEquivalent:@""];
                for (SLDisk *uvol in unmountedVols) {
                    NSString *uvolName = uvol.name;
                    if (!uvolName) {
                        uvolName = uvol.diskID;
                    }
                    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:uvolName action:@selector(doMount:) keyEquivalent:@""];
                    [menuItem setIndentationLevel:1];
                    [menuItem setRepresentedObject:uvol.diskID];
                    [menuItem setImage:[self shrinkImageForMenu:uvol.icon]];
                    [menu addItem:menuItem];
                }
                [menu addItem:[NSMenuItem separatorItem]];
            }
        }
    }
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SLShowBlockMounts]) {
        NSMenuItem *blockMountsItem = [menu addItemWithTitle:NSLocalizedString(@"Block Mounts", nil) action:@selector(doToggleBlockMounts:) keyEquivalent:@""];
        blockMountsItem.state = [[NSUserDefaults standardUserDefaults] boolForKey:SLBlockMounts] ? NSOnState : NSOffState;
        [menu addItem:[NSMenuItem separatorItem]];
    }
    
    if (showVolumesNumber) {
        [_statusItem setTitle:[NSString stringWithFormat:@"%lu", (unsigned long)volumesToDisplay.count]];
    } else {
        [_statusItem setTitle:nil];
    }
    
	NSMenuItem *slMenuItem = [[NSMenuItem alloc] initWithTitle:@"Semulov" action:nil keyEquivalent:@""];
	NSMenu *slSubmenu = [[NSMenu alloc] init];
	[slSubmenu addItemWithTitle:NSLocalizedString(@"About", nil) action:@selector(doAbout:) keyEquivalent:@""];
    [slSubmenu addItemWithTitle:NSLocalizedString(@"Check for Updates\u2026", nil) action:@selector(doCheckForUpdates:) keyEquivalent:@""];
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
                [SLNotificationController postVolumeMounted:vol];
            }
        });
    });
}

- (void)handleUnmount:(NSNotification *)not
{
    SLVolume *vol = [self volumeWithMountPath:[[not userInfo] objectForKey:@"NSDevicePath"]];
    if (vol) {
        [SLNotificationController postVolumeUnmounted:vol];
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

- (void)runAlertWithTitle:(NSString *)title message:(NSString *)message
{
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    if (title) {
        alert.messageText = title;
    }
    if (message) {
        alert.informativeText = message;
    }
    (void)[alert runModal];
}

- (void)eject:(id)object withUIFeedback:(BOOL)uiFeedback
{
    SLDisk *disk = nil;
    
    if ([object isKindOfClass:[SLVolume class]]) {
        SLVolume *volume = (SLVolume *)object;
        if (!volume.isLocal) {
            NSError *err = nil;
            if (![[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtURL:[NSURL fileURLWithPath:volume.path] error:&err] && uiFeedback) {
                NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Failed to unmount %@.", nil), volume.name];
                [self runAlertWithTitle:title message:[err localizedDescription]];
            }
            return;
        }
        
        disk = [deviceManager diskForPath:volume.path];
        if (!disk) {
            NSLog(@"Can't get disk for volume: %@", volume.path);
            return;
        }
    } else if ([object isKindOfClass:[SLDisk class]]) {
        disk = (SLDisk *)object;
    }
    
    [deviceManager unmountAndMaybeEject:disk handler:^(BOOL unmounted) {
        if (!unmounted && uiFeedback) {
            NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Failed to unmount %@.", nil), disk.name];
            [self runAlertWithTitle:title message:nil];
        }
    }];
}

- (void)doEject:(id)sender
{
    [self eject:[sender representedObject] withUIFeedback:YES];
}

- (SLVolume *)volumeForDisk:(SLDisk *)disk
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSDictionary *attrs = [fm attributesOfItemAtPath:disk.volumePath.path error:nil];
    if (!attrs || err) {
        return nil;
    }
    NSInteger diskFSNum = [attrs fileSystemNumber];
    for (SLVolume *vol in _volumes) {
        err = nil;
        attrs = [fm attributesOfItemAtPath:vol.path error:&err];
        if (!attrs || err) {
            continue;
        }
        if ([attrs fileSystemNumber] == diskFSNum) {
            return vol;
        }
    }
    return nil;
}

- (void)doEjectAll:(id)sender
{
    NSMutableArray *vols = [NSMutableArray array];
    
    // First collect volums that can be ejected
    for (SLVolume *vol in _volumes) {
		if ([self objectCanBeEjected:vol]) {
            [vols addObject:vol];
        }
    }
    
    NSMutableArray *disksToEject = [NSMutableArray array];
    
    // For each disk, if all ejectable volumes for that disk are to be unmounted, eject that disk.
    for (SLDisk *disk in deviceManager.disks) {
        SLVolume *vol = [self volumeForDisk:disk];
        if ([vols containsObject:vol]) {
            [disksToEject addObject:disk];
            [vols removeObject:vol];
        } else {
            BOOL containsAllChildren = YES;
            NSMutableArray *diskVols = [NSMutableArray array];
            for (SLDisk *childDisk in disk.children) {
                vol = [self volumeForDisk:childDisk];
                if (![vols containsObject:vol]) {
                    containsAllChildren = NO;
                    break;
                }
                [diskVols addObject:vol];
            }
            if (containsAllChildren) {
                [vols removeObjectsInArray:diskVols];
                [disksToEject addObject:disk];
            }
        }
    }
    
    for (SLDisk *disk in disksToEject) {
        [self eject:disk withUIFeedback:YES];
    }
    for (SLVolume *vol in vols) {
        [self eject:vol withUIFeedback:YES];
	}
}

- (void)doShowInFinder:(id)sender
{
    id obj = [sender representedObject];
    NSString *path = nil;
    if ([obj isKindOfClass:[SLVolume class]]) {
        path = [(SLVolume *)obj path];
    } else if ([obj isKindOfClass:[SLDisk class]]) {
        path = [(SLDisk *)obj volumePath].path;
    }
    if (path) {
        NSString *defaultAppID = [[NSUserDefaults standardUserDefaults] objectForKey:@"SLShowinFinderBundleID"];
        if (defaultAppID && [defaultAppID length] > 0) {
            NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:defaultAppID];
            (void)[[NSWorkspace sharedWorkspace] openFile:path withApplication:[appURL path]];
        }
        (void)[[NSWorkspace sharedWorkspace] selectFile:nil inFileViewerRootedAtPath:path];
    }
}

- (void)doMount:(id)sender
{
    id obj = [sender representedObject];
    if ([obj isKindOfClass:[NSString class]]) {
        [deviceManager mount:[deviceManager diskForDiskID:obj]];
    } else if ([obj isKindOfClass:[SLDisk class]]) {
        [deviceManager mount:(SLDisk *)obj];
    }
}

- (void)doFeedback:(id)sender
{
	NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
	NSString *urlString = [[NSString stringWithFormat:@"mailto:kainjow@kainjow.com?subject=Semulov %@ Feedback", appVersion] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]];
}

- (void)doPrefs:(id)sender
{
	if (!_prefs) {
		_prefs = [[SLPreferencesController alloc] init];
    }
	[_prefs window];
	[NSApp activateIgnoringOtherApps:YES];
	[_prefs showWindow:nil];
}

- (void)doToggleBlockMounts:(id)sender
{
    NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
    BOOL block = ![uds boolForKey:SLBlockMounts];
    deviceManager.blockMounts = block;
    [uds setBool:block forKey:SLBlockMounts];
    [self updateStatusItemMenu];
}

- (void)doCheckForUpdates:(id)sender
{
    [_updater checkForUpdates:sender];
}

@end
