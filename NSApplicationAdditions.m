//
//  NSApplicationAdditions.m
//
//  Created by Kevin Wojniak on 9/2/09.
//  Copyright 2009 - 2011 Kevin Wojniak. All rights reserved.
//

#import "NSApplicationAdditions.h"

@implementation NSApplication (Additions)

- (BOOL)isAppInstalled:(CFStringRef)appName inList:(LSSharedFileListRef)list item:(LSSharedFileListItemRef *)item
{
	CFArrayRef loginItems = LSSharedFileListCopySnapshot(list, NULL);
	if (!loginItems)
		return NO;
	
	BOOL ret = NO;
	for (CFIndex i=0; i<CFArrayGetCount(loginItems); i++)
	{
		LSSharedFileListItemRef listItem = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(loginItems, i);
		CFStringRef displayName = LSSharedFileListItemCopyDisplayName(listItem);
		if (displayName)
		{
			if (CFStringCompare(displayName, appName, kCFCompareCaseInsensitive) == kCFCompareEqualTo)
			{
				ret = YES;
				if (item)
				{
					*item = listItem;
					CFRetain(*item);
				}
			}
			
			CFRelease(displayName);
			
			if (ret)
				break;
		}
	}
	
	CFRelease(loginItems);
	
	return ret;
}

- (void)addToLoginItems
{
	LSSharedFileListRef list = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	if (!list)
		return;
	
	CFStringRef appName = (CFStringRef)[[NSProcessInfo processInfo] processName];

	if (![self isAppInstalled:appName inList:list item:NULL])
	{
		CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
		LSSharedFileListItemRef newItem = LSSharedFileListInsertItemURL(list, kLSSharedFileListItemLast, NULL, NULL, url, NULL, NULL);
		if (newItem)
			CFRelease(newItem);
	}
	
	CFRelease(list);
}

- (void)removeFromLoginItems
{
	LSSharedFileListRef list = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	if (!list)
		return;
	
	CFStringRef appName = (CFStringRef)[[NSProcessInfo processInfo] processName];
	LSSharedFileListItemRef item = NULL;
	if ([self isAppInstalled:appName inList:list item:&item] && item)
	{
		LSSharedFileListItemRemove(list, item);
		CFRelease(item);
	}
	
	CFRelease(list);
}

@end
