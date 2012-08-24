//
//  SLUnmountedVolume.h
//  Semulov
//
//  Created by Kevin Wojniak on 9/1/11.
//  Copyright 2011 Kevin Wojniak. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface SLUnmountedVolume : NSObject
{
	NSString *diskID;
	NSString *name;
	NSImage *icon;
}

@property (readwrite, retain) NSString *diskID;
@property (readwrite, retain) NSString *name;
@property (readwrite, retain) NSImage *icon;

@end
