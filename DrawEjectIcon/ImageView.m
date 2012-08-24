//
//  ImageView.m
//  DrawEjectIcon
//
//  Created by Kevin Wojniak on 9/3/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "ImageView.h"


@implementation ImageView

- (void)drawRect:(NSRect)rect
{
	NSRect bounds = [self bounds];
	[[NSColor blackColor] set];
	[[NSBezierPath bezierPathWithRect:bounds] stroke];
	NSImage *img = [NSImage imageNamed:@"AirPort_4"];
	[img drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
}

@end
