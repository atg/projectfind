//
//  PFAppDelegate.h
//  Project Find
//
//  Created by Alex Gordon on 28/06/2013.
//  Copyright (c) 2013 Alex Gordon. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PFWindowController;

@interface PFAppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (strong) PFWindowController* projectFind;

@end
