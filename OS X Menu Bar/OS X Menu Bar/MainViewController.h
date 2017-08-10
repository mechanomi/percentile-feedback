//
//  MainViewController.h
//  OS X Menu Bar
//
//  Created by Bruce Roberts on 8/2/17.
//  Copyright © 2017 BIANGLE. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface MainViewController : NSViewController
{
    
    __weak IBOutlet NSTextField *timeLabel, *statusLabel;
    __weak IBOutlet NSButton *addButton, *trackButton;
    
    NSDate *startDate;
    NSTimer *timer;
    
    BOOL trackingTime, addingTime;
    
}

@property (nonatomic, retain) IBOutlet WebView *webView;

- (IBAction)trackTime:(id)sender;
- (IBAction)addTime:(id)sender;

@end
