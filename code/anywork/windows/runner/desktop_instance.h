#ifndef RUNNER_DESKTOP_INSTANCE_H_
#define RUNNER_DESKTOP_INSTANCE_H_

#include <windows.h>
#include <functional>

#include "studio_instance.h"

// Platform-thread-only activation route. It owns no directory lock: Rust's one host lease is
// the authority. Its message-only window exists before the Flutter window is constructed.
class DesktopInstanceActivation {
 public:
  explicit DesktopInstanceActivation(anywork::DesktopInstanceBootstrap& bootstrap)
      : bootstrap_(bootstrap) {}
  DesktopInstanceActivation(const DesktopInstanceActivation&) = delete;
  DesktopInstanceActivation& operator=(const DesktopInstanceActivation&) = delete;
  ~DesktopInstanceActivation();
  anywork::InstanceStartup Initialize();
  void WindowReady(std::function<void()> restore);
  void WindowDestroyed();

 private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
  bool CreateEndpoint();
  anywork::DesktopInstanceBootstrap& bootstrap_;
  HWND endpoint_ = nullptr;
  bool pending_ = false;
  std::function<void()> restore_;
};
#endif
