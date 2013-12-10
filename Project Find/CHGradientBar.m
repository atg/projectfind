//
//  CHGradientBar.m
//  Chocolat
//
//  Created by Alex Gordon on 28/08/2011.
//  Copyright 2011 Fileability. All rights reserved.
//

#import "CHGradientBar.h"

@implementation CHGradientBar

@synthesize isUpsideDown;
@synthesize drawsTopLine;

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    /*
     
     -	Failed to convert attribute: fillStartingColor=NSDeviceRGBColorSpace 0.92549 0.92549 0.92549 1
     -	Failed to convert attribute: fillEndingColor=NSDeviceRGBColorSpace 0.858824 0.858824 0.858824 1
     -	Failed to convert attribute: fillColor=NSCalibratedRGBColorSpace 0.619601 0.661192 0.719388 1
     -	Failed to convert attribute: bottomBorderColor=NSDeviceRGBColorSpace 0.556863 0.556863 0.556863 1
     -	Failed to convert attribute: topBorderColor=NSCalibratedRGBColorSpace 0.557665 0.598892 0.642857 1
     -	The object was changed to an instance of NSCustomView; when instantiated, -[initWithFrame:] will be called in lieu of -[initWithCoder:].
    */
    
    NSColor *topColor = [NSColor colorWithDeviceWhite:0.92549 alpha:1.0];
    NSColor *bottomColor = [NSColor colorWithDeviceWhite:0.858824 alpha:1.0];
    NSColor *highlightColor = [NSColor colorWithDeviceWhite:240.0 / 255.0 alpha:1.0];
    NSColor *lineColor = [NSColor colorWithDeviceWhite:drawsTopLine ? 0.702 : 0.556863 alpha:1.0];
    NSGradient *grad = [[NSGradient alloc] initWithStartingColor:topColor endingColor:bottomColor];
    [grad drawInRect:[self bounds] angle:270];
    
    [highlightColor set];
    NSRectFillUsingOperation(NSMakeRect(0, isUpsideDown || drawsTopLine ? [self bounds].size.height - 2 : [self bounds].size.height - 1, [self bounds].size.width, 1), NSCompositeSourceOver);
    
    [lineColor set];
    NSRectFillUsingOperation(NSMakeRect(0, isUpsideDown ? [self bounds].size.height - 1 : 0, [self bounds].size.width, 1), NSCompositeSourceOver);
    
    if (drawsTopLine) {
        NSRectFillUsingOperation(NSMakeRect(0, !isUpsideDown ? [self bounds].size.height - 1 : 0, [self bounds].size.width, 1), NSCompositeSourceOver);
    }
}

@end
