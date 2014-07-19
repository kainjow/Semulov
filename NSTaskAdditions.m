//
//  NSTaskAdditions.m
//
//  Created by Kevin Wojniak on 10/18/11.
//  Copyright 2011 Kevin Wojniak, Inc. All rights reserved.
//

#import "NSTaskAdditions.h"


@implementation NSTask (NSTaskAdditions)

+ (NSData *)outputDataForTaskAtPath:(NSString *)taskPath arguments:(NSArray *)args
{
	NSTask *task = nil;
	NSPipe *inPipe = nil, *outPipe = nil;
	NSFileHandle *inHandle = nil, *outHandle = nil;
	NSData *outputData = nil;
	NSFileManager *fm = [[NSFileManager alloc] init];
	
	if (!taskPath || ![fm fileExistsAtPath:taskPath] || ![fm isExecutableFileAtPath:taskPath]) {
		return nil;
	}
	
	task = [[NSTask alloc] init];
	[task setLaunchPath:taskPath];
	if ((args != nil) && ([args count] > 0)) {
		[task setArguments:args];
	}
	
	// NSPipe can return nil
	outPipe = [[NSPipe alloc] init];
	if (outPipe != nil) {
		outHandle = [outPipe fileHandleForReading];
		[task setStandardOutput:outPipe];
		[task setStandardError:outPipe];
	}

	inPipe = [[NSPipe alloc] init];
	if (inPipe != nil) {
		inHandle = [inPipe fileHandleForWriting];
		[task setStandardInput:inPipe];
	}
	
	[task launch];
	[inHandle closeFile];
	
	if (outHandle != nil) {
		outputData = [outHandle readDataToEndOfFile];
		[outHandle closeFile];
	}
	
	[task waitUntilExit];
	
	return outputData;
}

+ (NSString *)outputStringForTaskAtPath:(NSString *)taskPath arguments:(NSArray *)args encoding:(NSStringEncoding)encoding
{
	NSData *data = [[self class] outputDataForTaskAtPath:taskPath arguments:args];
	if (data && [data length]) {
		return [[NSString alloc] initWithData:data encoding:encoding];
	}
	return @"";
}

@end
