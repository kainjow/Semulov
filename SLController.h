//
//  SLController.h
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 - 2014 Kevin Wojniak. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class SLDiskManager;

@interface SLController : NSObject <NSApplicationDelegate>
{
	NSStatusItem *_statusItem;
	NSArray *_volumes;
	NSWindowController *_prefs;
	SLDiskManager *deviceManager;
    dispatch_queue_t queue;
    NSArray *ignoredVolumes;
}

@end
