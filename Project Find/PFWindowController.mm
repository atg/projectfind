//  Created by Alex Gordon on 28/06/2013.

#import "PFWindowController.h"
#import "XPCBridge.h"
#import "city.h"

#define BEGIN_MATCH "\x02\x11\x01"
#define END_MATCH   "\x19\x12\x03"

static char isValidEscape(char c, int g) {
    return c == '\\'
        || c == '$'
        || (isdigit(c) && c - '0' < g);
}

static NSData* regexReplacement(const char* repl, NSArray* groups) {
    /*
     \\ -> backslash
     \$ -> dollar
     \N -> match N
     $N -> match N
     Everything else is treated literally.
     */
    
    NSMutableData* replacement = [NSMutableData dataWithCapacity:strlen(repl) * 2];
    int g = [groups count];
    while (*repl) {
        if (*repl == '\\' && isValidEscape(repl[1], g)) {
            repl++;
            
            if (*repl == '\\') {
                [replacement appendBytes:"\\" length:1];
            }
            else if (*repl == '$') {
                [replacement appendBytes:"$" length:1];
            }
            else {
                int n = *repl - '0';
                NSData* group = groups[n];
                [replacement appendData:group];
            }
            
        }
        else if (*repl == '$' && isdigit(repl[1]) && repl[1] - '0' < [groups count]) {
            repl++;
            
            int n = *repl - '0';
            NSData* group = groups[n];
            [replacement appendData:group];
        }
        else {
            [replacement appendBytes:repl length:1]; // Literal
        }
        repl++;
    }
    
    return replacement;
}
static BOOL pathIsSCM(NSString* path) {
#define ENSURE_NON_SCM(a) if ([path rangeOfString:a].location != NSNotFound) return YES
    ENSURE_NON_SCM(@"/.git/");
    ENSURE_NON_SCM(@"/.svn/");
    ENSURE_NON_SCM(@"/.hg/");
    ENSURE_NON_SCM(@"/.bzr/");
    ENSURE_NON_SCM(@"/.cvs/");
    ENSURE_NON_SCM(@".backupdb");
    return NO;
}
static BOOL performReplacement(NSString* path, const char* repl, NSArray* matches, uint64_t oldChecksum) {
    if (pathIsSCM(path))
        return NO;
    
    // load up path
    NSData* oldData = [NSData dataWithContentsOfFile:path];
    NSMutableData* newData = [NSMutableData dataWithCapacity:[oldData length] * 5u / 4u + 1];
    
    // check its checksum (cityhash?)
    uint64_t newChecksum = CityHash64((char*)oldData.bytes, oldData.length);
    NSLog(@"NEW checksum:: %llu", newChecksum);
    if (oldChecksum != newChecksum) {
        oldData = nil;
        newData = nil;
        return NO;
    }
    
    size_t position = 0;
    for (NSDictionary* match in matches) {
        size_t index = [match[@"start"] unsignedIntegerValue];
        
        // copy from position to index into newData
        if (position > index)
            return NO;
        
        if (position < index)
            [newData appendBytes:(char*)oldData.bytes + position length:index - position];
        
        position = [match[@"end"] unsignedIntegerValue];
        
        // add the replacement
        NSArray* groups = match[@"groups"];
        [newData appendData:regexReplacement(repl, groups)];
    }
    
    if (position < oldData.length)
        [newData appendBytes:(char*)oldData.bytes + position length:oldData.length - position];
    
    oldData = nil;
    NSError* err = nil;
    NSLog(@"Write data: '''%@'''", [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding]);
    BOOL worked = NO; //[newData writeToFile:path options:NSDataWritingAtomic error:&err];
    newData = nil;
    return worked;
}

@implementation PFWindowController

- (id)init {
    self = [super init];
    if (!self)
        return nil;
    
    [NSBundle loadNibNamed:@"PFProjectFind" owner:self];
    
    // comment out this line when moving to choc
    [self activateForProjectDirectory:(__strong id)nil];
    
    return self;
}

#define PFSettingString(k) [[NSUserDefaults standardUserDefaults] stringForKey:@"CHProjectFind" k]
#define PFSettingBool(k) [[NSUserDefaults standardUserDefaults] stringForKey:@"CHProjectFind" k]
#define PFSettingInteger(k) [[NSUserDefaults standardUserDefaults] integerForKey:@"CHProjectFind" k]

static NSArray* CHSplitStrip(NSString* s, NSString* bystr) {
    NSMutableCharacterSet* cs = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    [cs addCharactersInString:@"."];
    NSMutableArray* comps = [NSMutableArray array];
    
    for (NSString* obj in [s componentsSeparatedByString:bystr]) {
        [comps addObject:[obj stringByTrimmingCharactersInSet:cs]];
    }
    
    return comps;
}

- (NSArray*)arguments {
    NSMutableArray* args = [NSMutableArray array];
    [args addObject:@"--nocolor"];
    [args addObject:@"--column"];
    [args addObject:@"--nogroup"];
//    [args addObject:@"--nofollow"];
    [args addObject:@"--ackmate"];
    
    if (!PFSettingBool(@"Regex"))
		[args addObject:@"-Q"];
    if (PFSettingBool(@"CaseInsensitive"))
		[args addObject:@"-i"];
	if (PFSettingBool(@"WholeWords"))
		[args addObject:@"-w"];
    if (PFSettingBool(@"SmartCase"))
		[args addObject:@"-s"];

    if (!PFSettingBool(@"SourceCodeOnly"))
		[args addObject:@"-t"];
    if (PFSettingBool(@"HiddenFiles"))
		[args addObject:@"--hidden"];
    if (PFSettingBool(@"BinaryFiles"))
		[args addObject:@"--search-binary"];
    if (PFSettingBool(@"ZipFiles"))
		[args addObject:@"--search-zip"];
	if (!PFSettingBool(@"Recursive"))
		[args addObject:@"--no-recurse"];
	
	
    if (PFSettingBool(@"WantsContext")) {
        long ctx = PFSettingInteger(@"ContextLines");
        if (ctx > 0) {
            [args addObject:@"-C"];
            [args addObject:[NSString stringWithFormat:@"%ld", ctx]];
        }
    }
    
//    [args addObject:@"--type-add"];
//    [args addObject:@"html=.haml"];
//    [args addObject:@"--type-add"];
//    [args addObject:@"css=.sass,.scss"];
    
    NSString* filenameregex = PFSettingString(@"FilenameRegex");
    if ([filenameregex length]) {
        [args addObject:@"-G"];
        [args addObject:filenameregex];
    }
    
    NSString* ignoredirs = PFSettingString(@"IgnoreDirectories");
    if ([ignoredirs length]) {
        for (NSString* ignoredir in CHSplitStrip(ignoredirs, @",")) {
//            [args addObject:[@"--ignore-dir=" stringByAppendingString:ignoredir]];
            [args addObject:@"--ignore-dir"];
            [args addObject:ignoredir];
        }
    }
    /*
    NSString* additionalextensions = PFSettingString(@"AdditionalSourceExtensions");
    if ([additionalextensions length]) {
        NSString* miscsource = [@"miscsource=." stringByAppendingString:[CHSplitStrip(additionalextensions, @",") componentsJoinedByString:@",."]];
        if ([miscsource length] > [@"miscsource=." length]) {
            [args addObject:@"--type-add"];
            [args addObject:miscsource];
        }
    }
    */
    [args addObject:self.findField.stringValue ?: @""];
    return args;
}
- (IBAction)findReplaceButton:(NSSegmentedControl *)sender {
    @try {
        if ([sender selectedSegment] == 0) {
            [self getRidOfConnection];
            
            if (self.isRunning) {
                // Stop
                self.isRunning = NO;
                [self.progressIndicator stopAnimation:nil];
                return;
            }
            
            int arg_nobjs = self.arguments.count;
            if (!arg_nobjs)
                return;
            
            // Find
            self.isRunning = YES;
            [self.progressIndicator startAnimation:nil];
            
            NSLog(@"arguments = %@", self.arguments);
            
            // Build message
            xpc_object_t* arg_objs = (xpc_object_t*)calloc(arg_nobjs, sizeof(xpc_object_t));
            for (int i = 0; i < arg_nobjs; i++) {
                arg_objs[i] = xpc_string_create([self.arguments[i] UTF8String]);
            }
            xpc_object_t args = xpc_array_create(arg_objs, arg_nobjs);
            xpc_object_t dirPath = xpc_string_create(self.rootPath.fileSystemRepresentation);
            
            const char* keys[] = { "args", "directory" };
            const xpc_object_t values[] = { args, dirPath };
            xpc_object_t msg = xpc_dictionary_create(keys, values, 2);
            
            num_lines = 0;
            num_files = 0;
            num_matches = 0;
            
            self.lastMatches = [NSMutableArray arrayWithCapacity:500];
            self.resultsTextView.string = @"";
            self.resultsField.stringValue = [NSString stringWithFormat:@"Found %d matches, in %d lines, in %d files.", num_matches, num_lines, num_files];
            
            self.canReplace = NO;
            [self.findReplaceButtons setEnabled:NO forSegment:1];
            
            self.conn = xpc_connection_create("com.chocolatapp.Chocolat.projectfind", dispatch_get_main_queue());
            xpc_connection_set_target_queue(self.conn, dispatch_get_main_queue());
            xpc_connection_set_event_handler(self.conn, ^(xpc_object_t object) {
                // Received message
                if (xpc_get_type(object) == XPC_TYPE_ERROR) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSLog(@"IS ERR");
                        [self getRidOfConnection];
                        
                        self.isRunning = NO;
                        self.canReplace = NO;
//                        [self.findReplaceButtons setEnabled:NO forSegment:1];
                        [self.progressIndicator stopAnimation:nil];
                        [self refreshButton];
                    });
                }
                else if (xpc_dictionary_get_bool(object, "done")) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSLog(@"IS DONE");
                        [self getRidOfConnection];
                        
                        self.canReplace = YES;
                        self.isRunning = NO;
                        [self.findReplaceButtons setEnabled:YES forSegment:1];
                        [self.progressIndicator stopAnimation:nil];
                        [self refreshButton];
                    });
                }
                else {
                    static NSDictionary* attrs;
                    static NSDictionary* boldAttrs;
                    static NSDictionary* highlightAttrs;
                    static NSDictionary* linenumAttrs;
                    static NSDictionary* contextAttrs;
                    static dispatch_once_t onceToken;
                    dispatch_once(&onceToken, ^{
                        NSMutableParagraphStyle* ps = [[NSMutableParagraphStyle alloc] init];
                        ps.lineSpacing = 1;
                        
                        attrs = @{
                            NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:12],
                            NSParagraphStyleAttributeName:ps,
                        };
                        boldAttrs = @{
                            NSFontAttributeName: [NSFont fontWithName:@"Menlo-Bold" size:12],
                            NSParagraphStyleAttributeName:ps,
                        };
                        highlightAttrs = @{
                            NSBackgroundColorAttributeName: [NSColor colorWithCalibratedRed:0.975 green:0.972 blue:0.747 alpha:1.000],
                            NSUnderlineColorAttributeName: [NSColor colorWithCalibratedRed:0.890 green:0.786 blue:0.124 alpha:1.000],
                            NSUnderlineStyleAttributeName: @(NSUnderlineStyleThick),
                        };
                        linenumAttrs = @{
                            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1.000],
                        };
                        contextAttrs = @{
                            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.75 green:0.75 blue:0.75 alpha:1.000],
                        };
                    });
                    
                    // [obj[@"path"] mutableCopy];
                    NSAttributedString* (^enbolded)(NSString*) = ^ NSAttributedString* (NSString*s) {
                        return [[NSAttributedString alloc] initWithString:s attributes:boldAttrs];
                    };
                    
//                    [NSColor colorWithCalibratedRed:0.890 green:0.786 blue:0.124 alpha:1.000] // underline
                    NSDictionary* obj = xpc_to_ns(object);
//                    NSLog(@"Found: %@", obj);
                    NSMutableAttributedString* amstr = [self.resultsTextView textStorage];
                    NSMutableString* mstr = [amstr mutableString];
                    
                    NSString* path = obj[@"path"];
                    if ([path hasPrefix:@"./"])
                        path = [path substringWithRange:NSMakeRange(2, [path length] - 2)];
                    
                    [amstr appendAttributedString:enbolded(path)];
                    [mstr appendString:@"\n"];
                    [amstr addAttributes:attrs range:NSMakeRange([mstr length] - 1, 1)];
                    
                    NSArray* matches = obj[@"matches"];
                    
                    [self.lastMatches addObject:@[ path, matches, obj[@"checksum"] ]];
                    
                    for (NSDictionary* lineDict in obj[@"lines"]) {
                        NSLog(@"lineDict = %@", lineDict);
                        NSString* s = lineDict[@"string"];
                        int lbefore = (int)[mstr length];
                        [mstr appendFormat:@"%5d:%@\n", [lineDict[@"line"] intValue], s];
                        int lafter = (int)[mstr length];
                        int linenumLength = lafter - lbefore - 1;
                        linenumLength -= [s length];
                        int linenumStart = (int)[mstr length] - (lafter - lbefore);
                        
//                        [s rangeOfString:@(BEGIN_MATCH) options:NSLiteralSearch range:NSMakeRange(0, [s length])];
                        
                        
                        [amstr addAttributes:linenumAttrs range:NSMakeRange(linenumStart, linenumLength)];
                        if ([lineDict[@"isContext"] boolValue])
                            [amstr addAttributes:contextAttrs range:NSMakeRange([mstr length] - [s length] - 1, [s length])];
                        
                        int matchIndex = [lineDict[@"matchIndex"] intValue];
                        int numberMatches = [lineDict[@"numberMatches"] intValue];

                        for (int i = matchIndex; i < matchIndex + numberMatches; i++) {
                            NSDictionary* match = matches[i];
//                            NSLog(@"match = %@", match);
                            
                            int startIndex = [match[@"startIndex"] intValue];
                            int endIndex = [match[@"endIndex"] intValue];
                            [amstr addAttributes:highlightAttrs range:NSMakeRange([mstr length] - [s length] - 1 + startIndex, endIndex - startIndex)];
                        }
                    }
                    
                    int last_line = -1;
                    for (NSDictionary* match in matches) {
                        int this_line = [match[@"line"] intValue];
                        if (last_line != this_line) {
                            num_lines += 1;
                            last_line = this_line;
                        }
                    }
                    /*
                    for (NSDictionary* match in obj[@"matches"]) {
                        int this_line = [match[@"line"] intValue];
                        if (last_line != this_line) {
                            num_lines += 1;
                            last_line = this_line;
                        }
                        
                        NSString* s = match[@"string"];
                        int lbefore = (int)[mstr length];
                        [mstr appendFormat:@"%5d:%@\n", [match[@"line"] intValue], s];
                        int lafter = (int)[mstr length];
                        int linenumLength = lafter - lbefore - 1;
                        linenumLength -= [s length];
                        int linenumStart = (int)[mstr length] - (lafter - lbefore);
                        
                        [amstr addAttributes:linenumAttrs range:NSMakeRange(linenumStart, linenumLength)];
                        [amstr addAttributes:highlightAttrs range:NSMakeRange([mstr length] - [s length] - 1, [s length])];
                    }
                    */
                    num_matches += [obj[@"matches"] count];
                    num_files += 1;
                    
                    self.resultsField.stringValue = [NSString stringWithFormat:@"Found %d matches, in %d lines, in %d files.", num_matches, num_lines, num_files];
                    
//                    [amstr addAttributes:attrs range:NSMakeRange(0, [mstr length])];
                }
            });
            
            xpc_connection_resume(self.conn);
            xpc_connection_send_message(self.conn, msg);
            
            xpc_release(msg);
            xpc_release(args);
            xpc_release(dirPath);
        }
        else {
            // Replace
            // For each match
            NSAlert* alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Danger! Beta feature."];
            [alert setInformativeText:@"Project replace is brand new. While we have tested it, it's possible it may do irreparable damage to your data.\n\nBe safe, have a backup."];
            [alert setIcon:[NSImage imageNamed:@"ewok"]];
            [alert addButtonWithTitle:@"I promise have a backup"];
            [alert addButtonWithTitle:@"Cancel"];
            [alert runModal];
            
            for (NSArray* arr in self.lastMatches) {
                NSString* path = arr[0];
                NSArray* matches = arr[1];
                uint64_t checksum = [arr[2] unsignedLongLongValue];
                
                NSLog(@"[%@] [%@] [%@] [%llu]", path, self.replaceField.stringValue, matches, checksum);
                performReplacement(path, self.replaceField.stringValue.UTF8String, matches, checksum);
            }
        }
    }
    @finally {
        [self refreshButton];
    }
}
- (void)refreshButton {
    NSString* label = self.isRunning ? @"Stop" : @"Find";
    [self.findReplaceButtons setLabel:label forSegment:0];
}
- (IBAction)optionsButton:(id)sender {
    if (self.popover.shown) {
        [self.popover close];
    }
    else {
        [self.popover showRelativeToRect:[self.optionsButton bounds] ofView:self.optionsButton preferredEdge:NSMaxYEdge];
    }
}

// Can't work out how to do this
//   self.inDirectoryField should be filled with whatever the path is (use bindings)
//   but when do we set the path? I guess only set it if it changes

- (void)activateForProjectDirectory:(NSString*)projectDirectory {
    if (![projectDirectory length])
        projectDirectory = NSHomeDirectory();
    
    projectDirectory = [projectDirectory stringByStandardizingPath];
    self.lastProjectDirectory = [self.lastProjectDirectory stringByStandardizingPath];
    
    if (![self.lastProjectDirectory isEqual:projectDirectory]) {
        self.lastProjectDirectory = projectDirectory;
        self.rootPath = projectDirectory;
    }
}

- (IBAction)chooseButton:(id)sender {
    NSOpenPanel* op = [NSOpenPanel openPanel];
    op.canChooseDirectories = YES;
    op.canChooseFiles = NO;
    op.allowsMultipleSelection = NO;
    op.directoryURL = [NSURL fileURLWithPath:self.rootPath isDirectory:YES];
    
    if ([op runModal] != NSFileHandlingPanelOKButton)
        return;
    NSString* path = [[[op URL] path] stringByStandardizingPath];
    if (!path)
        return;
    
    self.rootPath = path;
}

- (void)awakeFromNib {
    [self refreshButton];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    self.popover.behavior = NSPopoverBehaviorTransient;
    [self.findReplaceButtons setEnabled:NO forSegment:1];
    
//    [self.replaceField setEnabled:NO];
    self.resultsField.stringValue = @"";
    
    NSTextFieldCell* tfc = self.resultsField.cell;
    tfc.backgroundStyle = NSBackgroundStyleRaised;
    
//    self.progressIndicator.controlTint = NSGraphiteControlTint;
    
//    self.resultsTextView.font = [NSFont fontWithName:@"Menlo" size:12];
//    self.resultsTextView.string = @"somefile.m\n  10:a test string";
}
- (void)getRidOfConnection {
    if (_conn) {
        NSLog(@"Killing");
        const char* const keys[] = {"kill"};
        xpc_object_t xpctrue = xpc_bool_create(true);
        const xpc_object_t values[] = { xpctrue };
        xpc_object_t msg = xpc_dictionary_create(keys, values, 1);
        
        NSLog(@"Sending");
        xpc_connection_send_message(_conn, msg);
        
        xpc_release(msg);
        xpc_release(xpctrue); // seems a bit unnecessarily
        
        NSLog(@"Cancelling");
        xpc_connection_cancel(_conn);
        NSLog(@"Cancellated");
        xpc_release(_conn);
        NSLog(@"Done");
    }
    _conn = NULL;
}
- (void)finalize {
    [self getRidOfConnection];
    [super finalize];
}

@end
