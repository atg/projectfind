//
//  CHGradientBar.h
//  Chocolat
//
//  Created by Alex Gordon on 28/08/2011.
//  Copyright 2011 Fileability. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface CHGradientBar : NSView {
    BOOL isUpsideDown;
    BOOL drawsTopLine;
}

@property (assign, setter=setUpsideDown:) BOOL isUpsideDown;
@property (assign) BOOL drawsTopLine;

@end
