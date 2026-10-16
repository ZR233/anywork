#include "studio_tray_windows.h"

#include <shellapi.h>
#include <windowsx.h>

#include <utility>

#include "resource.h"
#include "utils.h"

namespace anywork {
namespace {

constexpr wchar_t kTrayWindowClass[] = L"ANYWORK_TRAY_WINDOW";
constexpr UINT kStudioTrayIconId = 1;
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kCmdShowWindow = 1;
constexpr UINT kCmdExitApp = 2;

#ifndef NOTIFYICON_VERSION_4
#define NOTIFYICON_VERSION_4 4
#endif

void CopyTip(wchar_t* dest, size_t dest_chars, const wchar_t* tip) {
  if (dest == nullptr || dest_chars == 0) {
    return;
  }
  size_t index = 0;
  if (tip != nullptr) {
    for (; tip[index] != L'\0' && index + 1 < dest_chars; ++index) {
      dest[index] = tip[index];
    }
  }
  dest[index] = L'\0';
}

}  // namespace

WindowsStudioTray::WindowsStudioTray()
    : taskbar_created_(RegisterWindowMessageW(L"TaskbarCreated")) {}

WindowsStudioTray::~WindowsStudioTray() { Remove(); }

bool WindowsStudioTray::installed() const { return installed_; }

bool WindowsStudioTray::Install(const StudioTrayLabels& labels,
                                StudioTrayCallbacks callbacks) {
  if (installed_) {
    return true;
  }
  labels_ = labels;
  callbacks_ = std::move(callbacks);
  if (!RegisterTrayWindowClass() || !CreateTrayWindow() || !LoadTrayIcon() ||
      !AddIcon()) {
    LogNativeLifecycleEvent("TRAY_INSTALL_FAILED", 0,
                            static_cast<uintptr_t>(GetLastError()), 0);
    Remove();
    return false;
  }
  installed_ = true;
  LogNativeLifecycleEvent("TRAY_INSTALL_OK");
  return true;
}

void WindowsStudioTray::Remove() {
  if (hwnd_ != nullptr) {
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = hwnd_;
    data.uID = kStudioTrayIconId;
    Shell_NotifyIconW(NIM_DELETE, &data);
    const HWND hwnd = hwnd_;
    hwnd_ = nullptr;
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    DestroyWindow(hwnd);
  }
  if (icon_ != nullptr) {
    DestroyIcon(icon_);
    icon_ = nullptr;
  }
  if (class_registered_) {
    UnregisterClassW(kTrayWindowClass, GetModuleHandle(nullptr));
    class_registered_ = false;
  }
  installed_ = false;
  callbacks_ = {};
}

bool WindowsStudioTray::RegisterTrayWindowClass() {
  if (class_registered_) {
    return true;
  }
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = WindowsStudioTray::WndProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kTrayWindowClass;
  const ATOM atom = RegisterClassW(&window_class);
  if (atom != 0) {
    class_registered_ = true;
    return true;
  }
  if (GetLastError() == ERROR_CLASS_ALREADY_EXISTS) {
    return true;
  }
  return false;
}

bool WindowsStudioTray::CreateTrayWindow() {
  if (hwnd_ != nullptr) {
    return true;
  }
  hwnd_ = CreateWindowExW(0, kTrayWindowClass, L"", WS_POPUP, 0, 0, 0, 0,
                          nullptr, nullptr, GetModuleHandle(nullptr), this);
  return hwnd_ != nullptr;
}

bool WindowsStudioTray::LoadTrayIcon() {
  if (icon_ != nullptr) {
    DestroyIcon(icon_);
    icon_ = nullptr;
  }
  const int cx = GetSystemMetrics(SM_CXSMICON);
  const int cy = GetSystemMetrics(SM_CYSMICON);
  if (cx <= 0 || cy <= 0) {
    return false;
  }
  icon_ = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON, cx,
      cy, LR_DEFAULTCOLOR));
  return icon_ != nullptr;
}

bool WindowsStudioTray::AddIcon() {
  if (hwnd_ == nullptr || icon_ == nullptr) {
    return false;
  }
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = hwnd_;
  data.uID = kStudioTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayCallbackMessage;
  data.hIcon = icon_;
  const wchar_t* tip =
      HostUiPrefersChinese() ? L"\u7cca\u6765\u5e2e" : L"anywork";
  CopyTip(data.szTip, sizeof(data.szTip) / sizeof(data.szTip[0]), tip);
  if (Shell_NotifyIconW(NIM_ADD, &data) == FALSE) {
    return false;
  }
  data.uVersion = NOTIFYICON_VERSION_4;
  if (Shell_NotifyIconW(NIM_SETVERSION, &data) == FALSE) {
    Shell_NotifyIconW(NIM_DELETE, &data);
    return false;
  }
  return true;
}

void WindowsStudioTray::ShowContextMenu(int x, int y) {
  if (hwnd_ == nullptr) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  const std::wstring show_text = Utf16FromUtf8(labels_.show_window);
  const std::wstring exit_text = Utf16FromUtf8(labels_.exit_app);
  const BOOL appended_show =
      AppendMenuW(menu, MF_STRING, kCmdShowWindow, show_text.c_str());
  const BOOL appended_exit =
      AppendMenuW(menu, MF_STRING, kCmdExitApp, exit_text.c_str());
  if (appended_show == FALSE || appended_exit == FALSE) {
    DestroyMenu(menu);
    return;
  }
  SetForegroundWindow(hwnd_);
  const int cmd = TrackPopupMenuEx(
      menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY, x, y, hwnd_,
      nullptr);
  PostMessageW(hwnd_, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (cmd == static_cast<int>(kCmdShowWindow)) {
    NotifyShowWindow();
  } else if (cmd == static_cast<int>(kCmdExitApp)) {
    NotifyExitApp();
  }
}

void WindowsStudioTray::NotifyShowWindow() {
  LogNativeLifecycleEvent("TRAY_SHOW_WINDOW");
  if (callbacks_.show_window) {
    callbacks_.show_window();
  }
}

void WindowsStudioTray::NotifyExitApp() {
  LogNativeLifecycleEvent("TRAY_EXIT_REQUESTED");
  if (callbacks_.exit_app) {
    callbacks_.exit_app();
  }
}

LRESULT CALLBACK WindowsStudioTray::WndProc(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* created = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(created->lpCreateParams));
  }
  auto* self =
      reinterpret_cast<WindowsStudioTray*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self != nullptr) {
    return self->HandleMessage(hwnd, message, wparam, lparam);
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT WindowsStudioTray::HandleMessage(HWND hwnd, UINT message,
                                         WPARAM wparam, LPARAM lparam) {
  if (message == kTrayCallbackMessage) {
    const UINT event = LOWORD(lparam);
    const int x = GET_X_LPARAM(wparam);
    const int y = GET_Y_LPARAM(wparam);
    switch (event) {
      case NIN_SELECT:
      case NIN_KEYSELECT:
      case WM_LBUTTONUP:
      case WM_LBUTTONDBLCLK:
        NotifyShowWindow();
        return 0;
      case WM_CONTEXTMENU:
      case WM_RBUTTONUP:
        ShowContextMenu(x, y);
        return 0;
      default:
        return 0;
    }
  }
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    const bool restored = AddIcon();
    LogNativeLifecycleEvent("TRAY_ICON_READD", message,
                            restored ? 1 : 0, 0);
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

bool StudioTraySupported() { return true; }

std::unique_ptr<StudioTray> CreateStudioTray() {
  return std::make_unique<WindowsStudioTray>();
}

}  // namespace anywork
