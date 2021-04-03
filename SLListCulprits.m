#import <Foundation/Foundation.h>

NSString* shell(NSString* command) {
    NSTask* task = [NSTask new];
    NSPipe* pipe = [NSPipe new];
    
    task.standardOutput = pipe;
    task.standardError = pipe;
    task.arguments = [NSArray arrayWithObjects: @"-c", command, nil];
    task.launchPath = [NSString stringWithUTF8String:"/bin/zsh"];
    [task launch];
    
    
    NSData* data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString* output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return output;
}

NSString* listCulprits(NSString* volumeName) {
    NSString* prefix = [NSString stringWithFormat:@"/Volumes/%@/", volumeName];
    NSArray* lsofLines = [shell(@"lsof -Fcnp") componentsSeparatedByString:@"\n"];
    
    NSString* command = nil;
    NSString* path = nil;
    NSMutableSet<NSString*>* commandSet = [NSMutableSet setWithCapacity: 30];
    
    for(NSString* line in lsofLines) {
        if ([line length] == 0) continue;
        NSUInteger c = [line characterAtIndex:0];
        NSString* v = [line substringFromIndex: 1];
        
        if (c == 'p') {
            command = nil;
            path = nil;
        } else if ( c == 'c') {
            command = v;
        } else if (c == 'n') {
            path = v;
            
            if ([path hasPrefix:prefix]) {
                [commandSet addObject: command];
            }
        }
    }

    NSArray* commandList =  [commandSet allObjects];
    commandList = [commandList sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return [commandList componentsJoinedByString:@"\n"];
}
