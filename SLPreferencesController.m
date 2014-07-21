//
//  SLPreferencesController.m
//  Semulov
//
//  Created by Kevin Wojniak on 7/20/14.
//  Copyright (c) 2014 Kevin Wojniak. All rights reserved.
//

#import "SLPreferencesController.h"
#import "MASSHortcut.h"
#import "MASShortcutView+UserDefaults.h"
#import "SLPreferenceKeys.h"

@implementation SLPreferencesController

- (id)init
{
    if ((self = [super initWithWindowNibName:@"Preferences"]) != nil) {
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    self.shortcutView.associatedUserDefaultsKey = SLEjectAllShortcut;
    [self.shortcutView bind:@"enabled" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values."SLShowEjectAll options:nil];
}

@end
