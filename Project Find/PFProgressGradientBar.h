#import <Cocoa/Cocoa.h>

@interface IGKBackgroundProgressBar : NSView {
	BOOL shouldStop;
	
	//The number of pixels to translate right
	CGFloat phase;
	
	//The time interval from the reference date when the progress bar was last phased. Used to update phase
	NSTimeInterval lastUpdate;
    
    dispatch_source_t timer
}

- (IBAction)startAnimation:(id)sender;
- (IBAction)stopAnimation:(id)sender;

@end