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
	NSApplication *app = [NSApplication sharedApplication];

	SLController *controller = [[SLController alloc] init];
	
	[app setDelegate:controller];
	[app run];
	
    return 0;
    }
}
