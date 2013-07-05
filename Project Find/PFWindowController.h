//
//  PFWindowController.h
//  projectfind
//
//  Created by Alex Gordon on 28/06/2013.
//  Copyright (c) 2013 Alex Gordon. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PFWindowController : NSObject {
    int num_matches;
    int num_lines;
    int num_files;
}

@property IBOutlet NSWindow* window;
@property BOOL isRunning;
@property BOOL canReplace;
@property NSMutableArray* lastMatches;

@property (strong) IBOutlet NSTextField *findField;
@property (strong) IBOutlet NSTextField *replaceField;
@property (strong) IBOutlet NSSegmentedControl *findReplaceButtons;
@property (strong) IBOutlet NSButton *optionsButton;
@property (strong) IBOutlet NSTextField *resultsField;
@property (strong) IBOutlet NSTextView *resultsTextView;
@property (strong) IBOutlet NSPopover *popover;
@property (strong) IBOutlet NSTextField *inDirectoryField;
@property (strong) IBOutlet NSProgressIndicator* progressIndicator;
@property (assign) xpc_connection_t conn;

@property (copy) NSString* lastProjectDirectory;
@property (copy) NSString* rootPath;

- (IBAction)findReplaceButton:(NSSegmentedControl *)sender;
- (IBAction)optionsButton:(id)sender;
- (IBAction)chooseButton:(id)sender;

@end
