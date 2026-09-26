#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static void PXStartPanel(void)
{
    Class entry = NSClassFromString(@"PXPanelEntry");
    SEL start = NSSelectorFromString(@"start");
    if ([entry respondsToSelector:start])
        ((void (*)(id, SEL))objc_msgSend)(entry, start);
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application
{
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ PXStartPanel(); });
}
%end
