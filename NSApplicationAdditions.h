//
//  NSApplicationAdditions.h
//
//  Created by Kevin Wojniak on 9/2/09.
//  Copyright 2009 - 2011 Kevin Wojniak. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSApplication (Additions)

- (void)addToLoginItems;
- (void)removeFromLoginItems;

@end
