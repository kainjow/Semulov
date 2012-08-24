//
//  NSTaskAdditions.h
//
//  Created by Kevin Wojniak on 10/18/11.
//  Copyright 2011 Kevin Wojniak, Inc. All rights reserved.
//


#import <Foundation/Foundation.h>


@interface NSTask (NSTaskAdditions)

+ (NSString *)outputStringForTaskAtPath:(NSString *)taskPath arguments:(NSArray *)args encoding:(NSStringEncoding)encoding;

@end
