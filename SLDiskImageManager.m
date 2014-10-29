//
//  SLDiskImageManager.h
//  Semulov
//
//  Created by Kevin Wojniak on 7/20/14.
//  Copyright (c) 2014 Kevin Wojniak. All rights reserved.
//

#import "SLDiskImageManager.h"
#import "NSTaskAdditions.h"
#import <pthread.h>

@interface SLReadWriteLock : NSObject

- (void)readLock;
- (void)writeLock;
- (void)unlock;

@end

@implementation SLReadWriteLock
{
    pthread_rwlock_t _lock;
}

- (id)init
{
    if ((self = [super init]) != nil) {
        if (pthread_rwlock_init(&_lock, NULL) != 0) {
            NSLog(@"rwlock_init error: %s", strerror(errno));
        }
    }
    return self;
}

- (void)dealloc
{
    if (pthread_rwlock_destroy(&_lock) != 0) {
        NSLog(@"rwlock_destroy error: %s", strerror(errno));
    }
}

- (void)readLock
{
    if (pthread_rwlock_rdlock(&_lock) != 0) {
        NSLog(@"rwlock_rdlock error: %s", strerror(errno));
    }
}

- (void)writeLock
{
    if (pthread_rwlock_wrlock(&_lock) != 0) {
        NSLog(@"rwlock_wrlock error: %s", strerror(errno));
    }
}

- (void)unlock
{
    if (pthread_rwlock_unlock(&_lock) != 0) {
        NSLog(@"rwlock_unlock error: %s", strerror(errno));
    }
}

@end

@implementation SLDiskImageManager
{
    NSDictionary *_info;
    SLReadWriteLock *_infoLock;
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

- (id)init
{
    if ((self = [super init]) != nil) {
        _infoLock = [[SLReadWriteLock alloc] init];
    }
    return self;
}

- (void)reloadInfo:(dispatch_block_t)finishedHandler
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            NSDictionary *info = [[self class] infoPlist];
            [_infoLock writeLock];
            _info = info;
            [_infoLock unlock];
            if (finishedHandler) {
                dispatch_async(dispatch_get_main_queue(), finishedHandler);
            }
        }
    });
}

- (NSString *)diskImageForVolume:(NSString *)volume
{
    NSString *ret = nil;
    [_infoLock readLock];
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
                // make a copy so we're not using an object inside _info which may be
                // deallocated after the lock is released.
                ret = [imagePath copy];
                break;
            }
        }
    }
    [_infoLock unlock];
    return ret;
}

- (NSString *)diskImageForDiskID:(NSString *)diskID
{
    NSString *ret = nil;
    [_infoLock readLock];
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
                // make a copy so we're not using an object inside _info which may be
                // deallocated after the lock is released.
                ret = [imagePath copy];
                break;
            }
        }
    }
    [_infoLock unlock];
    return ret;
}

@end
