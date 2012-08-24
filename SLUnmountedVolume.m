//
//  SLUnmountedVolume.m
//  Semulov
//
//  Created by Kevin Wojniak on 9/1/11.
//  Copyright 2011 Kevin Wojniak. All rights reserved.
//

#import "SLUnmountedVolume.h"


@implementation SLUnmountedVolume

@synthesize diskID, name, icon;

- (void)dealloc
{
	[diskID release];
	[name release];
	[icon release];
	[super dealloc];
}

@end
