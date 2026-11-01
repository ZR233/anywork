#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

NS_ASSUME_NONNULL_BEGIN

// Thin AppKit adapter for the shared instance lease and shutdown coordinator.
@interface AnyworkHost : NSObject <NSWindowDelegate>
+ (instancetype)shared;
- (void)prepare;
- (void)attachWindow:(NSWindow *)window controller:(FlutterViewController *)controller;
- (void)requestExit;
// Defers AppKit termination until the shared coordinator confirms cleanup.
- (NSApplicationTerminateReply)requestApplicationTermination;
- (void)completeApplicationTermination;
@end

NS_ASSUME_NONNULL_END
