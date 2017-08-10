//
//  AppDelegate.m
//  OS X Menu Bar
//
//  Created by Bruce Roberts on 8/2/17.
//  Copyright © 2017 BIANGLE. All rights reserved.
//

/* TODO:
 - Implement curser activity moniter for timer autostopping
 
 */

#import "AppDelegate.h"
#import "MainViewController.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate
@synthesize statusItem;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.image = [NSImage imageNamed:@"Percent Sign.png"];
    [statusItem.button setImageScaling:NSImageScaleProportionallyUpOrDown];
    [statusItem.button setAction:@selector(itemClicked:)];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(didSleep) name:NSWorkspaceScreensDidSleepNotification object:NULL];
}

- (void)didSleep {
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"screenDidSleep" object:NULL];
    [self showPopover];
}

- (void)itemClicked:(id)sender {
    if (popover.shown) {
        [self hidePopover];
    } else {
        [self showPopover];
    }
    
    NSEvent *event = [NSApp currentEvent];
    if ([event modifierFlags] & NSEventModifierFlagControl) {
        [[NSApplication sharedApplication] terminate:self];
        return;
    }
}

- (void)showPopover {
    
    [popover showRelativeToRect:statusItem.button.bounds ofView:(NSView *)statusItem.button preferredEdge:NSMinYEdge];
}

- (void)hidePopover {
    [popover close];
    
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
