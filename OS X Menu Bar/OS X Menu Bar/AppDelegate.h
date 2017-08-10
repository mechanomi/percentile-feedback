//
//  AppDelegate.h
//  OS X Menu Bar
//
//  Created by Bruce Roberts on 8/2/17.
//  Copyright © 2017 BIANGLE. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    IBOutlet NSPopover *popover;
}

@property (strong, nonatomic) NSStatusItem *statusItem;
@property (assign, nonatomic) BOOL darkModeOn;

@end

