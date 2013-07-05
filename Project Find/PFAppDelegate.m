//
//  PFAppDelegate.m
//  Project Find
//
//  Created by Alex Gordon on 28/06/2013.
//  Copyright (c) 2013 Alex Gordon. All rights reserved.
//

#import "PFAppDelegate.h"
#import "PFWindowController.h"

@implementation PFAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    self.projectFind = [[PFWindowController alloc] init];
}

@end
