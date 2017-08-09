//
//  MainViewController.m
//  OS X Menu Bar
//
//  Created by Bruce Roberts on 8/2/17.
//  Copyright © 2017 BIANGLE. All rights reserved.
//

#import "MainViewController.h"

@interface MainViewController ()

@end

@implementation MainViewController
@synthesize webView;

- (void)viewDidAppear {
    [super viewDidAppear];
    
    [self.view setWantsLayer:YES];
    [[self.view layer] setBackgroundColor:[[NSColor whiteColor] CGColor]];
    
    //Load chart (index.html) on to a web view
    NSString *indexFilePath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    NSURL *fileURL = [NSURL fileURLWithPath:indexFilePath];
    NSURLRequest *request = [NSURLRequest requestWithURL:fileURL];
    [[webView mainFrame] loadRequest:request];
    [[webView mainFrame] reload];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screenDidSleep) name:@"screenDidSleep" object:NULL];
    
}

#pragma mark - Time Logging

- (IBAction)trackTime:(id)sender {
    
    if (!addingTime) {
        if (!trackingTime) {
            [self startLogging:self];
        } else {
            [self stopLogging:self dueToSleep:NO];
        }
        trackingTime = !trackingTime;
        addButton.enabled = !addButton.isEnabled;
        timeLabel.stringValue = @"00:00:00";
    }
}

- (void)startLogging:(id)sender {
    
    timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updatetimeLabel) userInfo:nil repeats:YES];
    startDate = [NSDate date];
}

- (void)stopLogging:(id)sender dueToSleep:(BOOL)dueToSleep {
    
    [timer invalidate]; timer = nil;
    NSTimeInterval interval = [[NSDate date] timeIntervalSinceDate:startDate];
    [self logPeriod:(int)interval];
    [[webView mainFrame] reload];
    
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.timeStyle = NSDateFormatterMediumStyle;
    
    if (dueToSleep) {
        trackingTime = FALSE;
        addButton.enabled = TRUE;
        trackButton.state = 1;
        
        statusLabel.stringValue = [NSString stringWithFormat:@"Last session (%@) ended on %@ [computer went to sleep]", stringFromTimeInterval(interval), [dateFormatter stringFromDate:[NSDate date]]];
    } else {
        
        statusLabel.stringValue = [NSString stringWithFormat:@"Last session (%@) ended on %@", stringFromTimeInterval(interval), [dateFormatter stringFromDate:[NSDate date]]];
    }
    
}

- (void)screenDidSleep {
    if (trackingTime) {
        [self stopLogging:self dueToSleep:YES];
    }
}


#pragma mark - Manual Input

- (IBAction)addTime:(id)sender {
    
    if (!trackingTime) {
        if (!addingTime) {
            [self addSessionManually:self];
        } else {
            [self cancelManualAdd:self];
        }
        addingTime = !addingTime;
        trackButton.enabled = !trackButton.isEnabled;
    }
}

- (void)addSessionManually:(id)sender {
    
    if (!trackingTime) {
        if (!addingTime) {
            timeLabel.stringValue = @"";
            timeLabel.placeholderString = @"# seconds";
            timeLabel.editable = TRUE;
            [timeLabel becomeFirstResponder];
        }   
    }
}

- (void)cancelManualAdd:(id)sender {
    
    [timeLabel abortEditing];
    timeLabel.editable = FALSE;
    timeLabel.placeholderString = @"";
    timeLabel.stringValue = @"00:00:00";
}

- (void)submitManuallyAddedSession:(id)sender {
    
    ///Called when the user hits "enter" after editing the label
    
    addingTime = FALSE;
    addButton.state = 0;
    trackButton.enabled = TRUE;
    timeLabel.editable = FALSE;
    timeLabel.placeholderString = @"";
    timeLabel.stringValue = @"00:00:00";
    
    double interval = [timeLabel.stringValue doubleValue];
    if (interval > 0.0) {
        [self logPeriod:(int)interval];
        [[webView mainFrame] reload];
    }
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.timeStyle = NSDateFormatterMediumStyle;
    statusLabel.stringValue = [NSString stringWithFormat:@"Added %@ on %@", stringFromTimeInterval(interval), [dateFormatter stringFromDate:[NSDate date]]];
}



- (void)logPeriod:(int)interval {
    
    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    
    //Adds backslashes where there are spaces in file or directory names so that the command line can understand it
    for (int i = 0; i < resourcePath.length; i++) {
        
        if ([[resourcePath substringWithRange:NSMakeRange(i, 1)] isEqualToString:@" "]) {
            
            NSString *start = [resourcePath substringWithRange:NSMakeRange(0, i)];
            resourcePath = [NSString stringWithFormat:@"%@%@%@", start, @"\\", [resourcePath substringWithRange:NSMakeRange(i, resourcePath.length - i)]];
            i+=2;
        }
    }
    
    //Log time
    NSString *command = [NSString stringWithFormat:@"%@/data.py --log-period %i", resourcePath, interval];
    system([command UTF8String]);
}

- (void)updatetimeLabel{
    
    ///Updates current session label on a timer
    
    NSDate *now = [NSDate date];
    
    //Set session label
    timeLabel.stringValue = stringFromTimeInterval([now timeIntervalSinceDate:startDate]);
}

NSString* stringFromTimeInterval(NSTimeInterval interval){
    
    ///Returns a time interval as a string in the format HH:mm:ss
    
    //get remaining seconds and subtract them from the total
    double seconds = interval;
    int remainingSeconds = (int)seconds % 60;
    
    seconds -= remainingSeconds;
    
    //get remaining minutes and subtract them from the total
    int minutes = seconds / 60;
    int remainingMinutes = (int)minutes % 60;
    
    minutes -= remainingMinutes;
    
    int hours = minutes / 60;
    
    return [NSString stringWithFormat:@"%02i:%02i:%02i", hours, remainingMinutes, remainingSeconds];
}

@end
