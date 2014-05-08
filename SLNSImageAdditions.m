//
//  SLNSImageAdditions.m
//  Semulov
//
//  Created by Kevin Wojniak on 8/26/07.
//  Copyright 2007 Kevin Wojniak. All rights reserved.
//

#import "SLNSImageAdditions.h"


@implementation NSImage (resize)

- (NSImage *)slResize:(NSSize)size
{
    NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];;
    NSImage *imgCopy = [[self copy] autorelease];
    [imgCopy setSize:size];
    [image lockFocus];
    [imgCopy drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
    [image unlockFocus];
    return image;
}

@end
