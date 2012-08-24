//
//  SLController.h
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright 2006 - 2011 Kevin Wojniak. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class SLDeviceManager;

@interface SLController : NSObject
{
	NSStatusItem *_statusItem;
	NSArray *_volumes;
	NSWindowController *_prefs;
	SLDeviceManager *deviceManager;
}

@end
