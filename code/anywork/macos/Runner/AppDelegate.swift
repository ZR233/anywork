import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Keep logout/shutdown pending while the shared coordinator drains resources.
    return AnyworkHost.shared().requestApplicationTermination()
  }

  override func applicationWillTerminate(_ notification: Notification) {
    // AppKit normally exits with 0; preserve the coordinator's real exit code.
    AnyworkHost.shared().completeApplicationTermination()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
