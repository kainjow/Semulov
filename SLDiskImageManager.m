//
//  SLDiskImageManager.h
//  Semulov
//
//  Created by Kevin Wojniak on 7/20/14.
//  Copyright (c) 2014 Kevin Wojniak. All rights reserved.
//

#import "SLDiskImageManager.h"
#import "NSTaskAdditions.h"

@implementation SLDiskImageManager
{
    NSDictionary *_info;
}

+ (NSDictionary *)infoPlist
{
    NSString *plistStr = [NSTask outputStringForTaskAtPath:@"/usr/bin/hdiutil" arguments:@[@"info", @"-plist"] encoding:NSUTF8StringEncoding];
    
    // sometimes hdiutil returns an error in the first line or so of it's output.
    // so we try to determine if an error exists, and skip past it to the xml
    
    NSString *xmlStr = @"<?xml";
    NSRange xmlRange = [plistStr rangeOfString:xmlStr];
    if (xmlRange.location == NSNotFound) {
        // not valid xml?!
        return nil;
    }
    
    if (xmlRange.location > 0) {
        // scan up to XML
        NSScanner *scanner = [NSScanner scannerWithString:plistStr];
        [scanner scanUpToString:xmlStr intoString:nil];
        plistStr = [plistStr substringFromIndex:[scanner scanLocation]];
    }
    
    NSDictionary *plistDict = [plistStr propertyList];
    if (!plistDict || ![plistDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    return plistDict;
}

- (void)reloadInfo
{
    _info = [[self class] infoPlist];
}

- (NSString *)diskImageForVolume:(NSString *)volume
{
    for (NSDictionary *imagesDict in [_info objectForKey:@"images"]) {
        NSString *imagePath = imagesDict[@"image-path"];
        
        // if .dmg is mounted from safari, imagePath will be the .dmg within the .download file
        NSRange dotDownloadRange = [imagePath rangeOfString:@".download"];
        if (dotDownloadRange.location != NSNotFound) {
            imagePath = [imagePath substringToIndex:dotDownloadRange.location];
        }
        
        for (NSDictionary *sysEntity in imagesDict[@"system-entities"]) {
            NSString *mountPoint = [sysEntity objectForKey:@"mount-point"];
            
            if ([mountPoint isEqualToString:volume]) {
                return imagePath;
            }
        }
    }
    
    return nil;
}

- (NSString *)diskImageForDiskID:(NSString *)diskID
{
    for (NSDictionary *imagesDict in [_info objectForKey:@"images"]) {
        NSString *imagePath = imagesDict[@"image-path"];
        
        // if .dmg is mounted from safari, imagePath will be the .dmg within the .download file
        NSRange dotDownloadRange = [imagePath rangeOfString:@".download"];
        if (dotDownloadRange.location != NSNotFound) {
            imagePath = [imagePath substringToIndex:dotDownloadRange.location];
        }
        
        for (NSDictionary *sysEntity in imagesDict[@"system-entities"]) {
            NSString *devEntry = [[sysEntity objectForKey:@"dev-entry"] lastPathComponent];
            if ([devEntry isEqualToString:diskID]) {
                return imagePath;
            }
        }
    }
    
    return nil;
}

@end
