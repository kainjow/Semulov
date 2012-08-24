//
//  EjectIconView.m
//  DrawEjectIcon
//
//  Created by Kevin Wojniak on 9/2/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "EjectIconView.h"


@implementation EjectIconView

- (void)awakeFromNib
{
	//NSData *pdf = [self dataWithPDFInsideRect:[self bounds]];
	//[pdf writeToFile:@"/Users/kainjow/Desktop/eject_white.pdf" atomically:YES];
}

- (void)drawRect:(NSRect)rect
{
	NSRect bounds = [self bounds];
	
	//[[NSColor whiteColor] set];
	//NSRectFill(bounds);
	
	[[NSColor blackColor] set];
	//[[NSColor whiteColor] set];
	
	[[NSBezierPath bezierPathWithRect:bounds] stroke];

	float bottomBarWidth = NSWidth(bounds)*0.7; // 0.875;
	float bottomBarHeight = NSHeight(bounds)*0.12; // 0.1875;
	float bottomBarBottom = NSHeight(bounds)*0.2; // 0.125;
	NSRect bottomBar = NSMakeRect((NSWidth(bounds) - bottomBarWidth) / 2,
								  ceil(NSMinY(bounds) + bottomBarBottom),
								  bottomBarWidth,
								  bottomBarHeight);
	NSRectFill(bottomBar);
	
	float triWidth = bottomBarWidth; //*0.9;
	float triHeight = NSHeight(bounds)*0.35; // 0.46666666667;
	float triTop = bottomBarBottom;
	NSRect triBar = NSMakeRect((NSWidth(bounds) - triWidth) / 2,
							   ceil(NSMaxY(bounds) - (triHeight + triTop)),
							   triWidth,
							   triHeight);
	NSBezierPath *bz = [NSBezierPath bezierPath];
	[bz moveToPoint:NSMakePoint(NSMinX(triBar), NSMinY(triBar))];
	[bz lineToPoint:NSMakePoint(NSMidX(triBar), NSMaxY(triBar))];
	[bz lineToPoint:NSMakePoint(NSMaxX(triBar), NSMinY(triBar))];
	[bz lineToPoint:NSMakePoint(NSMinX(triBar), NSMinY(triBar))];
	[bz closePath];
	[bz fill];
}

@end
