#import <Foundation/Foundation.h>
#import <objc/message.h>

__attribute__((constructor)) static void PXInitialize(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        Class entry = NSClassFromString(@"PXPanelEntry");
        SEL start = NSSelectorFromString(@"start");
        if ([entry respondsToSelector:start])
            ((void (*)(id, SEL))objc_msgSend)(entry, start);
    });
}
