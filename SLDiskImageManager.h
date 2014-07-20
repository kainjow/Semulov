//
//  SLDiskImageManager.h
//  Semulov
//
//  Created by Kevin Wojniak on 7/20/14.
//  Copyright (c) 2014 Kevin Wojniak. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SLDiskImageManager : NSObject

- (void)reloadInfo;

- (NSString *)diskImageForVolume:(NSString *)volume;
- (NSString *)diskImageForDiskID:(NSString *)diskID;

@end
