//  Created by Alex Gordon on 28/06/2013.

#import "PFWindowController.h"
#import "XPCBridge.h"
#import "zlib.h"

#define BEGIN_MATCH "\x02\x11\x01"
#define END_MATCH   "\x19\x12\x03"

#define CHDebug NSLog

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

static uint64_t checksum(const unsigned char* buf, size_t len) {
    uint64_t crc = crc32(0L, Z_NULL, 0);
    return crc32(crc, buf, len);
    
//    uint64_t ad32 = adler32(0L, Z_NULL, 0);
//    ad32 = adler32(ad32, buf, len);
    
//    return (ad32 << 32) | crc;
}
static BOOL performReplacement(NSString* path, const char* repl, NSArray* matches, uint64_t oldChecksum, BOOL isRegex, NSError** error) {
    if (pathIsSCM(path))
        return NO;
    
    CHDebug(@"path = [%@]", path);
    
    // load up path
    NSData* oldData = [NSData dataWithContentsOfFile:path];
    NSMutableData* newData = [NSMutableData dataWithCapacity:[oldData length] * 5u / 4u + 1];
    
    // check its checksum (cityhash?)
    uint64_t newChecksum = checksum((unsigned char*)oldData.bytes, oldData.length); //CityHash64((char*)oldData.bytes, oldData.length);
    if (oldChecksum != newChecksum) {
        oldData = nil;
        newData = nil;
        return NO;
    }
    
    size_t position = 0;
    int replLength = repl ? strlen(repl) : 0;
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
        if (isRegex)
            [newData appendData:regexReplacement(repl, groups)];
        else if (replLength)
            [newData appendBytes:repl length:replLength];
    }
    
    if (position < oldData.length)
        [newData appendBytes:(char*)oldData.bytes + position length:oldData.length - position];
    
    oldData = nil;
    NSError* err = nil;
    CHDebug(@"path = %@", path);
    CHDebug(@"Write data: '''%@'''", [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding]);
    BOOL worked = [newData writeToFile:path options:NSDataWritingAtomic error:&err];
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

#define PFSettingString(k)  [[NSUserDefaults standardUserDefaults] stringForKey:@"CHProjectFind" k]
#define PFSettingBool(k)    [[NSUserDefaults standardUserDefaults] boolForKey:@"CHProjectFind" k]
#define PFSettingInteger(k) [[NSUserDefaults standardUserDefaults] integerForKey:@"CHProjectFind" k]

static NSArray* CHSplitStripNoDot(NSString* s, NSString* bystr) {
    NSMutableCharacterSet* cs = [NSMutableCharacterSet characterSetWithCharactersInString:@" \t\v\f\n\r"];
//    [cs addCharactersInString:@"."];
    NSMutableArray* comps = [NSMutableArray array];
    
    for (NSString* obj in [s componentsSeparatedByString:bystr]) {
        NSString* str = [obj stringByTrimmingCharactersInSet:cs];
        if ([str length])
            [comps addObject:str];
    }
    
    return comps;
}

- (NSArray*)arguments {
    NSMutableArray* args = [NSMutableArray array];
    [args addObject:@"--nocolor"];
    [args addObject:@"--column"];
    [args addObject:@"--nogroup"];
//    [args addObject:@"--nofollow"];
//    [args addObject:@"--ackmate"];
    
    if (!PFSettingBool(@"Regex"))
		[args addObject:@"--literal"];
    if (PFSettingBool(@"CaseInsensitive"))
		[args addObject:@"--ignore-case"];
	if (PFSettingBool(@"WholeWords"))
		[args addObject:@"--word-regexp"];
    if (PFSettingBool(@"SmartCase"))
		[args addObject:@"--smart-case"];

//    if (!PFSettingBool(@"SourceCodeOnly"))
//		[args addObject:@"--all-text"];
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
        [args addObject:@"--file-search-regex"];
        [args addObject:filenameregex];
    }
    
    NSString* ignoredirs = PFSettingString(@"IgnoreDirectories");
    if ([ignoredirs length]) {
        for (NSString* ignoredir in CHSplitStripNoDot(ignoredirs, @",")) {
//            [args addObject:[@"--ignore-dir=" stringByAppendingString:ignoredir]];
            [args addObject:@"--ignore"];
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
    CHDebug(@"args = %@", args);
    return args;
}

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex {
    NSLayoutManager* lm = [textView layoutManager];
    NSRange glyphRange = [lm glyphRangeForCharacterRange:NSMakeRange(charIndex, 1) actualCharacterRange:NULL];
    NSRect r = [lm boundingRectForGlyphRange:glyphRange inTextContainer:textView.textContainer];
    
    r.origin.x += textView.textContainerOrigin.x;
    r.origin.y += textView.textContainerOrigin.y;
    
    NSDictionary* attrs = [self.resultsTextView.textStorage attributesAtIndex:charIndex effectiveRange:NULL];
    self.actionPopoverMatch = attrs[@"PFMatchAttribute"];
    
    NSDictionary* match = self.actionPopoverMatch[1][0];
//    int startIndex = [match[@"startIndex"] intValue];
//    int endIndex = [match[@"endIndex"] intValue];
//    NSRange range =
    
    self.goToPath = [self.lastMatchesRootPath stringByAppendingPathComponent:self.actionPopoverMatch[0]];
    self.goToLine = [match[@"line"] intValue];//NSMakeRange(NSNotFound, 0);
    
    [self.actionPopover showRelativeToRect:r ofView:textView preferredEdge:NSMaxYEdge];
    
//    NSLog(@"Clicked on link: %@ : %@ : %llu", link, NSStringFromRect(r), charIndex);
    return YES;
}
- (IBAction)perItemAction:(NSSegmentedControl *)sender {
    [self.actionPopover close];
    
    if ([sender selectedSegment] == 0) {
        // Go to
        [self openFileAtPath:self.goToPath linenum:self.goToLine];
    }
    else {
        // Replace one
        [self replaceMatches:@[ self.actionPopoverMatch ]];
    }
    
    self.actionPopoverMatch = nil;
}
- (void)openFileAtPath:(NSString *)path linenum:(int)linenum //range:(NSRange)range
{
    if (![path length])
        return;
    
    NSURL *openURL = [NSURL fileURLWithPath:path isDirectory:NO];

	//Try with the document controller
	NSError *err = nil;
	NSDocument *doc = [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:openURL display:YES error:&err];
//    if ([doc respondsToSelector:@selector(setActiveIn:)])
//        [doc setActiveIn:nil];
    
    
//    if (linenum) {
//        [[[doc bestSplitPreferringWindowController:nil] view] goToLine:linenum];
//        
//        dispatch_async(dispatch_get_main_queue(), ^{
//            CHSplitController* sp = [doc bestSplitPreferringWindowController:nil];
//            [[sp view] goToLine:linenum];
//            [[[[sp tabController] windowController] window] makeKeyAndOrderFront:nil];
//        });
//    }

    /*
    if (range.location != NSNotFound && range.length != 0) {
//        [[[doc bestSplitPreferringWindowController:nil] view] goToLine:linenum];
     
        
        dispatch_async(dispatch_get_main_queue(), ^{
            CHSplitController* sp = [doc bestSplitPreferringWindowController:nil];
            CHGenericRecipe* recp = [[CHGenericRecipe alloc] initWithTextView:[[sp view] textView] document:doc];
            recp.mainBlock = ^BOOL(NSDictionary * unused) {
                recp.selection = range;
                return YES;
            };
            [doc queueRecipe:recp];
            
            [[[[sp tabController] windowController] window] makeKeyAndOrderFront:nil];
        });
    }
     */
    
	if (doc && !err) {        
		//Success!
		return;
	}
	
	//Otherwise try with the global workspace
	if ([[NSWorkspace sharedWorkspace] openURL:openURL])
		return;
	
	//Couldn't open
	NSBeep();
	
}

- (IBAction)findReplaceButton:(NSSegmentedControl *)sender {
    [self findReplaceButtonInner:[sender selectedSegment] == 0];
}
- (void)findReplaceButtonInner:(BOOL)isFind {
    @try {
        if (isFind) {
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
            
            NSString* standardRoot = self.rootPath.stringByStandardizingPath;
            
            // Build message
            xpc_object_t* arg_objs = (xpc_object_t*)calloc(arg_nobjs, sizeof(xpc_object_t));
            for (int i = 0; i < arg_nobjs; i++) {
                arg_objs[i] = xpc_string_create([self.arguments[i] UTF8String]);
            }
            xpc_object_t args = xpc_array_create(arg_objs, arg_nobjs);
            xpc_object_t dirPath = xpc_string_create(standardRoot.fileSystemRepresentation);
            
            const char* keys[] = { "args", "directory" };
            const xpc_object_t values[] = { args, dirPath };
            xpc_object_t msg = xpc_dictionary_create(keys, values, 2);
            
            num_lines = 0;
            num_files = 0;
            num_matches = 0;
            
            self.lastMatchesFindArguments = self.arguments;
            self.lastMatchesRootPath = [standardRoot copy];
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
//                        CHDebug(@"IS ERR");
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
//                        CHDebug(@"IS DONE");
                        [self getRidOfConnection];
                        
                        self.canReplace = YES;
                        self.isRunning = NO;
                        [self.findReplaceButtons setEnabled:self.lastMatches.count > 0 forSegment:1];
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
                    static NSMutableParagraphStyle* paragraphStyle;
                    dispatch_once(&onceToken, ^{
                        paragraphStyle = [[NSMutableParagraphStyle alloc] init];
                        paragraphStyle.lineSpacing = 1;
                        
                        attrs = @{
                            NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:12],
                            NSParagraphStyleAttributeName: paragraphStyle,
                        };
                        boldAttrs = @{
                            NSFontAttributeName: [NSFont fontWithName:@"Menlo-Bold" size:12],
                            NSParagraphStyleAttributeName: paragraphStyle,
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
                    
                    NSAttributedString* (^pathAttributes)(NSString*, NSArray*) = ^ NSAttributedString* (NSString* s, NSArray* obj) {
                        return [[NSAttributedString alloc] initWithString:s attributes:@{
                                                      NSFontAttributeName: [NSFont fontWithName:@"Menlo-Bold" size:12],
                                            NSParagraphStyleAttributeName: paragraphStyle,
                                           NSForegroundColorAttributeName: [NSColor blackColor],
                                                    @"PFMatchAttribute": obj,
                                                      NSLinkAttributeName: [NSURL URLWithString:@"about:blank"],
                                }];
                    };
                    
                    NSDictionary* obj = xpc_to_ns(object);
                    NSMutableAttributedString* amstr = [self.resultsTextView textStorage];
                    NSMutableString* mstr = [amstr mutableString];
                    
                    NSNumber* checksum = obj[@"checksum"];
                    NSString* path = obj[@"path"];
                    
                    NSArray* matches = obj[@"matches"];
                    NSArray* itemArr = @[ path, matches, checksum ];
                    
                    if ([path hasPrefix:@"./"])
                        path = [path substringWithRange:NSMakeRange(2, [path length] - 2)];
                    
                    NSAttributedString* normalNewline = [[NSAttributedString alloc] initWithString:@"\n" attributes:attrs];
                    [amstr appendAttributedString:pathAttributes(path, itemArr)];
                    [amstr appendAttributedString:normalNewline];                    
                    
                    [self.lastMatches addObject:itemArr];
                    
                    for (NSDictionary* lineDict in obj[@"lines"]) {
                        NSString* s = lineDict[@"string"];
                        int lbefore = (int)[mstr length];
                        [mstr appendFormat:@"%5d:%@\n", [lineDict[@"line"] intValue], s];
                        int lafter = (int)[mstr length];
                        int linenumLength = lafter - lbefore - 1;
                        linenumLength -= [s length];
                        int linenumStart = (int)[mstr length] - (lafter - lbefore);
                        
                        [amstr addAttributes:linenumAttrs range:NSMakeRange(linenumStart, linenumLength)];
                        if ([lineDict[@"isContext"] boolValue])
                            [amstr addAttributes:contextAttrs range:NSMakeRange([mstr length] - [s length] - 1, [s length])];
                        
                        int matchIndex = [lineDict[@"matchIndex"] intValue];
                        int numberMatches = [lineDict[@"numberMatches"] intValue];

                        for (int i = matchIndex; i < matchIndex + numberMatches; i++) {
                            NSDictionary* match = matches[i];
                            
                            int startIndex = [match[@"startIndex"] intValue];
                            int endIndex = [match[@"endIndex"] intValue];
                            NSRange highlightRange = NSMakeRange([mstr length] - [s length] - 1 + startIndex, endIndex - startIndex);
                            [amstr addAttributes:highlightAttrs range:highlightRange];
                            
                            NSDictionary* matchAttributes = @{
                                @"PFMatchAttribute": @[ path, @[ match ], checksum ],
//                                NSForegroundColorAttributeName: [NSColor redColor],
                                NSLinkAttributeName: [NSURL URLWithString:@"about:blank"],
                            };
                            [amstr addAttributes:matchAttributes range:highlightRange];
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
//            NSAlert* alert = [[NSAlert alloc] init];
//            [alert setMessageText:@"Danger! Beta feature."];
//            [alert setInformativeText:@"Project replace is new. While we have tested it, it's possible it may do irreparable damage to your data.\n\nMake sure you have a backup!"];
//            [alert setIcon:[NSImage imageNamed:@"ewok"]];
//            [alert addButtonWithTitle:@"I promise have a backup"];
//            [alert addButtonWithTitle:@"Cancel"];
            
//            [alert runModal];
            // nagReplaceButton
            
            self.replacementMatches = [self.lastMatches copy];
            
            NSView* contentView = self.window.contentView;
            NSPoint arrowPoint = NSMakePoint(floor(NSMidX(contentView.bounds)), contentView.bounds.size.height - 5);
            self.nagPopover.behavior = NSPopoverBehaviorTransient;
            self.nagPopover.delegate = self;
            [self.nagPopover showRelativeToRect:(NSRect){arrowPoint, NSMakeSize(2, 2)} ofView:contentView preferredEdge:NSMinYEdge];
//            [self replaceMatches:self.lastMatches];

        }
    }
    @finally {
        [self refreshButton];
    }
}
- (void)replaceMatches:(NSArray*)matches {
    NSString* root = self.lastMatchesRootPath;
    const char* repl = self.replaceField.stringValue.UTF8String;
    
    BOOL isRegex = PFSettingBool(@"Regex");
    for (NSArray* arr in matches) {
        NSString* path = arr[0];
        NSArray* matches = arr[1];
        uint64_t checksum = [arr[2] unsignedLongLongValue];
        
        path = [root stringByAppendingPathComponent:path];
        
        CHDebug(@"[%@] [%@] [%@] [%llu]", path, self.replaceField.stringValue, matches, checksum);
        NSError* err = nil;
        performReplacement(path, repl, matches, checksum, isRegex, &err);
    }
    
    self.canReplace = NO;
    [self.findReplaceButtons setEnabled:NO forSegment:1];
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
    
    [self.findReplaceButtons setEnabled:NO forSegment:1];
    [self.window makeFirstResponder:self.findField];
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

- (IBAction)findField:(id)sender {
    if (![self.findReplaceButtons isEnabledForSegment:0]) {
        NSBeep();
        return;
    }
    
    [self findReplaceButtonInner:YES];
}

- (IBAction)replaceField:(id)sender {
    
    // Can we replace
    if ([self.findReplaceButtons isEnabledForSegment:1] && [self.lastMatchesFindArguments isEqual:[self arguments]] && [self.lastMatchesRootPath isEqual:self.rootPath.stringByStandardizingPath]) {
        [self findReplaceButtonInner:NO]; // Replace
        return;
    }
    
    // Can we find?
    if (![self.findReplaceButtons isEnabledForSegment:0]) {
        NSBeep();
        return;
    }
    
    // Find
    [self findReplaceButtonInner:YES];
}

- (IBAction)nagReplaceButton:(id)sender {
    if ([self.replacementMatches count])
        [self replaceMatches:self.replacementMatches];
    else
        NSBeep();
    
    self.replacementMatches = nil;
    [self.nagPopover performClose:nil];
}
- (void)popoverDidClose:(NSNotification *)notification {
    self.replacementMatches = nil;
}

- (IBAction)toggleRegex:(id)sender {
    BOOL flipRegex = !PFSettingBool(@"Regex");
    
    [[NSUserDefaults standardUserDefaults] setBool:flipRegex forKey:@"CHProjectFindRegex"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


- (void)showWindow:(id)sender {
//    NSString* projectDirectory = [[[[[CHApplicationController sharedController] mostActiveProject] directoryURL] path] copy];
    [self activateForProjectDirectory:(__strong id)nil];
    [self.window makeKeyAndOrderFront:nil];
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
    
    self.resultsTextView.displaysLinkToolTips = NO;
//    self.resultsTextView.linkTextAttributes = @{NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.392 green:0.447 blue:0.581 alpha:1.000]};
    self.resultsTextView.linkTextAttributes = @{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone) };
    
//    self.progressIndicator.controlTint = NSGraphiteControlTint;
    
//    self.resultsTextView.font = [NSFont fontWithName:@"Menlo" size:12];
//    self.resultsTextView.string = @"somefile.m\n  10:a test string";
}
- (void)getRidOfConnection {
    if (_conn) {
        CHDebug(@"Killing");
        const char* const keys[] = {"kill"};
        xpc_object_t xpctrue = xpc_bool_create(true);
        const xpc_object_t values[] = { xpctrue };
        xpc_object_t msg = xpc_dictionary_create(keys, values, 1);
        
        xpc_connection_send_message(_conn, msg);
        
        xpc_release(msg);
        xpc_release(xpctrue); // seems a bit unnecessarily
        
        xpc_connection_cancel(_conn);
        xpc_release(_conn);
    }
    _conn = NULL;
}
- (void)finalize {
    [self getRidOfConnection];
    [super finalize];
}

@end
