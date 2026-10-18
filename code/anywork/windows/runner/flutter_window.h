#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Restores and foregrounds the existing window without touching the app
  // graph, sessions or exit coordinator.
  void ShowMainWindow();

  // Hands a real window close to the existing coordinated exit path.
  void RequestCoordinatedExit();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // True only after Dart created a visible tray icon. Until then a close must
  // keep the existing exit path instead of hiding an unrecoverable window.
  bool tray_available_ = false;

  // True once a close/system event entered the coordinated exit path.
  bool exit_requested_ = false;

  // True between WM_QUERYENDSESSION and a cancelled WM_ENDSESSION.
  bool session_ending_ = false;

  // Hosts the host-apps method channel used by the Studio UI.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      host_apps_channel_;

  // Hosts the native-host lifecycle channel: exit deadline + redacted diagnostics.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      lifecycle_channel_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      file_dialogs_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
