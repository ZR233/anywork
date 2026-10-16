#ifndef RUNNER_STUDIO_TRAY_WINDOWS_H_
#define RUNNER_STUDIO_TRAY_WINDOWS_H_

#include <windows.h>

#include "studio_tray.h"

namespace anywork {

// Windows 通知区域托盘宿主：自持隐藏顶层窗口接收 Shell_NotifyIcon 回调
// 与 TaskbarCreated 广播，不从 Flutter 主窗口 WndProc 委派消息。
class WindowsStudioTray final : public StudioTray {
 public:
  WindowsStudioTray();
  ~WindowsStudioTray() override;

  WindowsStudioTray(const WindowsStudioTray&) = delete;
  WindowsStudioTray& operator=(const WindowsStudioTray&) = delete;
  WindowsStudioTray(WindowsStudioTray&&) = delete;
  WindowsStudioTray& operator=(WindowsStudioTray&&) = delete;

  bool Install(const StudioTrayLabels& labels,
               StudioTrayCallbacks callbacks) override;
  void Remove() override;
  bool installed() const override;

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  bool RegisterTrayWindowClass();
  bool CreateTrayWindow();
  bool LoadTrayIcon();
  bool AddIcon();
  void ShowContextMenu(int x, int y);
  void NotifyShowWindow();
  void NotifyExitApp();

  HWND hwnd_ = nullptr;
  HICON icon_ = nullptr;
  UINT taskbar_created_ = 0;
  bool class_registered_ = false;
  bool installed_ = false;
  StudioTrayLabels labels_;
  StudioTrayCallbacks callbacks_;
};

}  // namespace anywork

#endif  // RUNNER_STUDIO_TRAY_WINDOWS_H_
