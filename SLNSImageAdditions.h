//
//  SLNSImageAdditions.h
//  Semulov
//
//  Created by Kevin Wojniak on 8/26/07.
//  Copyright 2007 Kevin Wojniak. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSImage (resize)

- (NSImage *)slResize:(NSSize)size;

@end
