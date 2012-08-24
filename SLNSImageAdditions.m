//
//  SLNSImageAdditions.m
//  Semulov
//
//  Created by Kevin Wojniak on 8/26/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "SLNSImageAdditions.h"


@implementation NSImage (resize)

- (NSImage *)slResize:(NSSize)size
{
    NSImage *image = [[NSImage alloc] initWithSize:size];
    
    [image setSize:size];
    
 	[self setScalesWhenResized: YES];
	[self setSize:size];
	
    [image lockFocus];
	[self compositeToPoint:NSZeroPoint operation:NSCompositeCopy];
    [image unlockFocus];
	
    return [image autorelease];
}

@end
