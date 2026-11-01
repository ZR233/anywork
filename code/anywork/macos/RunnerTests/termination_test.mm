// Headless AppKit regression fixture. Only Dart cleanup is replaced: the app
// delegate, run loop, termination reply, deadline and native exit are real.
#import <Cocoa/Cocoa.h>
#import "AnyworkHost.h"
#include "studio_host_lifecycle.h"

#include <cstdio>
#include <string>
#include <unistd.h>

@interface AnyworkHost (TerminationTest)
- (void)finishExitWithCode:(int)code;
@end

static BOOL cleanupConfirmed = NO;
static int cleanupRequests = 0;

@interface TerminationTestApplication : NSApplication
@end

@implementation TerminationTestApplication
- (void)replyToApplicationShouldTerminate:(BOOL)reply {
  if (!reply || !cleanupConfirmed) _exit(92);
  std::puts("appkit-reply-after-cleanup");
  std::fflush(stdout);
  [super replyToApplicationShouldTerminate:reply];
}
@end

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 3) return 93;
    const std::string mode(argv[1]);
    const int code = mode == "degraded" ? 1 : 0;
    [TerminationTestApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    id<NSApplicationDelegate> delegate = [[NSClassFromString(@"Runner.AppDelegate") alloc] init];
    if (delegate == nil) return 94;
    NSApp.delegate = delegate;
    auto &lifecycle = anywork::StudioHostLifecycle::Instance();
    lifecycle.ConfigureDiagnostics(argv[2]);
    lifecycle.SetExitRequestCallback([mode, code]() {
      if (++cleanupRequests != 1) _exit(95);
      std::puts("cleanup-requested");
      std::fflush(stdout);
      if (mode == "repeated") {
        // A second request must share the first cleanup and its deadline.
        const auto reply = [NSApp.delegate applicationShouldTerminate:NSApp];
        if (reply != NSTerminateLater) _exit(96);
      }
      NSTimer *finish = [NSTimer timerWithTimeInterval:0.05 repeats:NO block:^(NSTimer *) {
        cleanupConfirmed = YES;
        [AnyworkHost.shared finishExitWithCode:code];
      }];
      [NSRunLoop.mainRunLoop addTimer:finish forMode:NSRunLoopCommonModes];
    });
    dispatch_async(dispatch_get_main_queue(), ^{
      if (mode == "window") {
        // No window is shown; exercise the actual close delegate directly.
        NSWindow *window = [[NSWindow alloc] init];
        if ([AnyworkHost.shared windowShouldClose:window]) _exit(97);
      } else {
        [NSApp terminate:nil];
      }
    });
    // A missing AppKit reply or a stalled callback must fail this test promptly.
    NSTimer *guard = [NSTimer timerWithTimeInterval:5 repeats:NO block:^(NSTimer *) {
      _exit(98);
    }];
    [NSRunLoop.mainRunLoop addTimer:guard forMode:NSRunLoopCommonModes];
    [NSApp run];
    return 99;
  }
}
