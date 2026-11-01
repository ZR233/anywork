#import "AnyworkHost.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "../../runner_common/studio_host_lifecycle.h"
#include "../../runner_common/studio_instance.h"

#include <algorithm>
#include <memory>
#include <optional>
#include <chrono>
#include <thread>
#include <unistd.h>

@interface AnyworkHost () {
  std::unique_ptr<anywork::DesktopInstanceBootstrap> _instance;
  CFMessagePortRef _port;
  BOOL _applicationTerminationPending;
  std::optional<int> _confirmedExitCode;
}
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) FlutterMethodChannel *lifecycle;
@property(nonatomic, strong) FlutterMethodChannel *files;
@property(nonatomic, strong) FlutterMethodChannel *apps;
- (void)activateWindow;
- (void)pick:(FlutterMethodCall *)call result:(FlutterResult)result;
- (void)hostApp:(FlutterMethodCall *)call result:(FlutterResult)result;
- (void)finishExitWithCode:(int)code;
@end

@implementation AnyworkHost

+ (instancetype)shared {
  static AnyworkHost *host;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ host = [[AnyworkHost alloc] init]; });
  return host;
}

// CFMessagePort's synchronous reply confirms that the owning host accepted activation.
// Its context is the process-owned singleton and callbacks run on the AppKit run loop.
static CFDataRef Activate(CFMessagePortRef port, SInt32 message,
                          CFDataRef data, void *context) {
  (void)port;
  (void)message;
  (void)data;
  AnyworkHost *host = (__bridge AnyworkHost *)context;
  [host activateWindow];
  return CFDataCreate(kCFAllocatorDefault, nullptr, 0);
}

- (void)activateWindow {
  NSWindow *window = self.window;
  [window deminiaturize:nil];
  [window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  if (_instance != nullptr) _instance->Report(anywork::InstanceEvent::Activated);
}

- (void)prepare {
#if defined(ANYWORK_DEMO_true)
  return;
#endif
  _instance = std::make_unique<anywork::DesktopInstanceBootstrap>();
  auto claim = _instance->Claim();
  if (claim == anywork::InstanceClaim::Failed) _exit(1);
  // Demo hosts have no data lease and deliberately do not share an activation endpoint.
  if (_instance->key().empty()) return;
  NSString *key = [[NSString alloc] initWithBytes:_instance->key().data()
      length:_instance->key().size() encoding:NSASCIIStringEncoding];
  if (key == nil) _exit(1);
  NSString *name = [@"io.github.zr233.anywork." stringByAppendingString:key];
  if (claim == anywork::InstanceClaim::Occupied) {
    // The owner holds its lease before creating the endpoint. Bound the startup race;
    // never create another engine or activate an unrelated data root on failure.
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (std::chrono::steady_clock::now() < deadline) {
      CFMessagePortRef remote = CFMessagePortCreateRemote(nullptr, (__bridge CFStringRef)name);
      if (remote != nullptr) {
        CFDataRef reply = nullptr;
        const double remaining = std::chrono::duration<double>(
            deadline - std::chrono::steady_clock::now()).count();
        const double budget = std::min(0.25, std::max(0.0, remaining / 2));
        SInt32 status = CFMessagePortSendRequest(remote, 0, nullptr, budget, budget,
                                                kCFRunLoopDefaultMode, &reply);
        CFRelease(remote);
        if (reply != nullptr) CFRelease(reply);
        if (status == kCFMessagePortSuccess) {
          _instance->Report(anywork::InstanceEvent::Redirected);
          _exit(0);
        }
      }
      claim = _instance->Claim();
      if (claim == anywork::InstanceClaim::Primary) break;
      if (claim == anywork::InstanceClaim::Failed) _exit(1);
      std::this_thread::sleep_until(std::min(deadline,
          std::chrono::steady_clock::now() + std::chrono::milliseconds(100)));
    }
    if (claim != anywork::InstanceClaim::Primary) {
      _instance->Report(anywork::InstanceEvent::Unavailable);
      _exit(1);
    }
  }
  CFMessagePortContext context = {0, (__bridge void *)self, nullptr, nullptr, nullptr};
  _port = CFMessagePortCreateLocal(nullptr, (__bridge CFStringRef)name,
                                   Activate, &context, nullptr);
  if (_port == nullptr) {
    _instance->Report(anywork::InstanceEvent::EndpointFailed);
    _exit(1);
  }
  CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(nullptr, _port, 0);
  if (source == nullptr) _exit(1);
  CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
  CFRelease(source);
}

- (void)attachWindow:(NSWindow *)window controller:(FlutterViewController *)controller {
  self.window = window;
  window.delegate = self;
  self.lifecycle = [FlutterMethodChannel methodChannelWithName:
      @"io.github.zr233.anywork/host_lifecycle" binaryMessenger:controller.engine.binaryMessenger];
  __weak AnyworkHost *weakSelf = self;
  [self.lifecycle setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    AnyworkHost *hostAdapter = weakSelf;
    auto &host = anywork::StudioHostLifecycle::Instance();
    NSDictionary *args = [call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : @{};
    if ([call.method isEqualToString:@"beginExit"]) {
      result(@(host.Arm()));
    } else if ([call.method isEqualToString:@"configureDiagnostics"]) {
      NSString *directory = args[@"directory"];
      const char *path = [directory isKindOfClass:NSString.class] ? directory.UTF8String : nullptr;
      if (path == nullptr) {
        result([FlutterError errorWithCode:@"invalid_arguments" message:@"Expected a UTF-8 directory." details:nil]);
        return;
      }
      host.ConfigureDiagnostics(path);
      result(nil);
    } else if ([call.method isEqualToString:@"updateExitDiagnostics"]) {
      anywork::StudioExitDiagnostics diagnostics;
      NSString *stage = args[@"stage"], *code = args[@"code"], *correlation = args[@"correlationId"];
      const char *stageText = [stage isKindOfClass:NSString.class] ? stage.UTF8String : nullptr;
      const char *codeText = [code isKindOfClass:NSString.class] ? code.UTF8String : nullptr;
      const char *correlationText = [correlation isKindOfClass:NSString.class] ? correlation.UTF8String : nullptr;
      if (stageText != nullptr) diagnostics.stage = stageText;
      if (codeText != nullptr) diagnostics.code = codeText;
      if (correlationText != nullptr) diagnostics.correlation_id = correlationText;
      NSNumber *pending = args[@"pendingCommits"];
      if ([pending isKindOfClass:NSNumber.class] && pending.longLongValue >= 0) {
        diagnostics.has_pending_commits = true;
        diagnostics.pending_commits = pending.unsignedLongLongValue;
      }
      host.UpdateDiagnostics(diagnostics);
      result(nil);
    } else if ([call.method isEqualToString:@"finishExit"]) {
      NSNumber *code = args[@"exitCode"];
      [hostAdapter finishExitWithCode:
          [code isKindOfClass:NSNumber.class] && code.intValue == 0 ? 0 : 1];
    } else if ([call.method isEqualToString:@"showMainWindow"]) {
      [hostAdapter activateWindow];
      result(nil);
    } else {
      result(FlutterMethodNotImplemented);
    }
  }];
  anywork::StudioHostLifecycle::Instance().SetExitRequestCallback([weakSelf]() {
    [weakSelf.lifecycle invokeMethod:@"requestExit" arguments:nil];
  });
  self.files = [FlutterMethodChannel methodChannelWithName:
      @"io.github.zr233.anywork/file_dialogs" binaryMessenger:controller.engine.binaryMessenger];
  [self.files setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    [weakSelf pick:call result:result];
  }];
  self.apps = [FlutterMethodChannel methodChannelWithName:
      @"io.github.zr233.anywork/host_apps" binaryMessenger:controller.engine.binaryMessenger];
  [self.apps setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    [weakSelf hostApp:call result:result];
  }];
}

- (void)requestExit {
  anywork::StudioHostLifecycle::Instance().RequestExit();
}

- (NSApplicationTerminateReply)requestApplicationTermination {
  if (!_applicationTerminationPending) {
    _applicationTerminationPending = YES;
    // Arm before deferring so a stalled AppKit loop cannot extend the deadline.
    anywork::StudioHostLifecycle::Instance().Arm();
    // AppKit must receive NSTerminateLater before even a fast cleanup can reply.
    // A main-queue block can itself be inside terminate:'s nested modal loop;
    // use the run loop so cleanup does not wait for that queue block to return.
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes,
                          ^{ [self requestExit]; });
    CFRunLoopWakeUp(CFRunLoopGetMain());
  }
  return NSTerminateLater;
}

- (void)finishExitWithCode:(int)code {
  _confirmedExitCode = code == 0 ? 0 : 1;
  if (_applicationTerminationPending) {
    // This resumes a pending logout/shutdown instead of cancelling it. AppKit
    // calls applicationWillTerminate before its normal exit(0); that delegate
    // hands off to completeApplicationTermination with the real code.
    [NSApp replyToApplicationShouldTerminate:YES];
  }
  // Window-close exits have no AppKit termination request to acknowledge.
  anywork::StudioHostLifecycle::Instance().Finish(*_confirmedExitCode);
}

- (void)completeApplicationTermination {
  // Never let AppKit convert degraded or unconfirmed cleanup into exit(0).
  anywork::StudioHostLifecycle::Instance().Finish(_confirmedExitCode.value_or(1));
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
  (void)sender;
  [self requestExit];
  return NO;
}

- (void)pick:(FlutterMethodCall *)call result:(FlutterResult)result {
  BOOL directory = [call.method isEqualToString:@"pickDirectory"];
  if (!directory && ![call.method isEqualToString:@"pickFiles"]) {
    result(FlutterMethodNotImplemented);
    return;
  }
  NSOpenPanel *panel = NSOpenPanel.openPanel;
  panel.canChooseDirectories = directory;
  panel.canChooseFiles = !directory;
  panel.allowsMultipleSelection = !directory;
  if (!directory) {
    if (![call.arguments isKindOfClass:NSArray.class]) {
      result([FlutterError errorWithCode:@"invalid_arguments" message:@"Expected file extensions." details:nil]);
      return;
    }
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    NSCharacterSet *invalid = NSCharacterSet.alphanumericCharacterSet.invertedSet;
    for (id value in call.arguments) {
      if (![value isKindOfClass:NSString.class]) {
        result([FlutterError errorWithCode:@"invalid_arguments" message:@"Invalid file extension." details:nil]);
        return;
      }
      NSString *extension = value;
      if (extension.length == 0 || [extension rangeOfCharacterFromSet:invalid].location != NSNotFound) {
        result([FlutterError errorWithCode:@"invalid_arguments" message:@"Invalid file extension." details:nil]);
        return;
      }
      UTType *type = [UTType typeWithFilenameExtension:extension];
      if (type != nil) [types addObject:type];
    }
    if (types.count > 0) panel.allowedContentTypes = types;
  }
  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    if (directory) {
      NSString *path = panel.URL.path;
      if (response == NSModalResponseOK && path == nil) {
        result([FlutterError errorWithCode:@"file_dialog_failed" message:@"No local directory was selected." details:nil]);
      } else {
        result(response == NSModalResponseOK ? path : nil);
      }
    } else {
      NSMutableArray<NSString *> *paths = [NSMutableArray array];
      if (response == NSModalResponseOK) {
        for (NSURL *url in panel.URLs) {
          NSString *path = url.path;
          if (!url.isFileURL || path == nil) {
            result([FlutterError errorWithCode:@"file_dialog_failed" message:@"No local file was selected." details:nil]);
            return;
          }
          [paths addObject:path];
        }
      }
      result(paths);
    }
  }];
}

- (void)hostApp:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSString *identifier = nil, *binary = nil;
  if ([call.method hasPrefix:@"vsCode"]) {
    identifier = @"com.microsoft.VSCode";
    binary = @"Contents/Resources/app/bin/code";
  } else if ([call.method hasPrefix:@"zed"]) {
    identifier = @"dev.zed.Zed";
    binary = @"Contents/MacOS/cli";
  } else if ([call.method isEqualToString:@"terminalIcon"]) {
    identifier = @"com.apple.Terminal";
  } else {
    result(FlutterMethodNotImplemented);
    return;
  }
  NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier];
  if ([call.method hasSuffix:@"Executable"]) {
    NSString *path = [app URLByAppendingPathComponent:binary].path;
    result(path != nil && [NSFileManager.defaultManager isExecutableFileAtPath:path] ? path : nil);
  } else if ([call.method hasSuffix:@"Icon"]) {
    NSString *path = app.path;
    if (path == nil) { result(nil); return; }
    NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:path];
    NSData *tiff = icon.TIFFRepresentation;
    if (tiff == nil) { result(nil); return; }
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiff];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    result(png == nil ? nil : [FlutterStandardTypedData typedDataWithBytes:png]);
  } else {
    result(FlutterMethodNotImplemented);
  }
}
@end
