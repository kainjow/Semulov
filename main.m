//
//  main.m
//  Semulov
//
//  Created by Kevin Wojniak on 11/5/06.
//  Copyright Kevin Wojniak 2006. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SLController.h"


int main(int argc, char *argv[])
{
    @autoreleasepool {
	[NSApplication sharedApplication];

	SLController *controller = [[SLController alloc] init];
	
	[NSApp setDelegate:controller];
	[NSApp run];
	
	[controller release];
	
    return 0;
    }
}
