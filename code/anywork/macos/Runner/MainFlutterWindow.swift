import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // The packaged bridge claims the data root before any engine or Dart code starts.
    AnyworkHost.shared().prepare()
    let controller = FlutterViewController()
    let windowFrame = frame
    contentViewController = controller
    setFrame(windowFrame, display: true)
    minSize = NSSize(width: 900, height: 600)
    title = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "糊来帮" : "anywork"
    RegisterGeneratedPlugins(registry: controller)
    AnyworkHost.shared().attach(self, controller: controller)
    super.awakeFromNib()
  }
}
