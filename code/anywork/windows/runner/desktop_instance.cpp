#include "desktop_instance.h"

#include <algorithm>
#include <chrono>
#include <string>

namespace {
constexpr wchar_t kEndpointClass[] = L"ANYWORK_INSTANCE_ACTIVATION";
constexpr UINT kActivate = WM_APP + 1;
constexpr auto kActivationBudget = std::chrono::seconds(10);
}

DesktopInstanceActivation::~DesktopInstanceActivation() {
  if (endpoint_ != nullptr) DestroyWindow(endpoint_);
}

anywork::InstanceStartup DesktopInstanceActivation::Initialize() {
  using Clock = std::chrono::steady_clock;
  const auto deadline = Clock::now() + kActivationBudget;
  while (Clock::now() < deadline) {
    const auto claim = bootstrap_.Claim();
    if (claim == anywork::InstanceClaim::Failed) return anywork::InstanceStartup::Failed;
    if (claim == anywork::InstanceClaim::Primary) {
      if (bootstrap_.key().empty() || CreateEndpoint()) return anywork::InstanceStartup::Primary;
      bootstrap_.Report(anywork::InstanceEvent::EndpointFailed);
      return anywork::InstanceStartup::Failed;
    }
    const std::wstring key(bootstrap_.key().begin(), bootstrap_.key().end());
    HWND existing = FindWindowExW(HWND_MESSAGE, nullptr, kEndpointClass, key.c_str());
    if (existing != nullptr) {
      DWORD owner_pid = 0;
      GetWindowThreadProcessId(existing, &owner_pid);
      if (owner_pid != 0) AllowSetForegroundWindow(owner_pid);
      const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now()).count();
      if (remaining <= 0) break;
      DWORD_PTR accepted = 0;
      if (SendMessageTimeoutW(existing, kActivate, 0, 0,
                              SMTO_ABORTIFHUNG | SMTO_ERRORONEXIT,
                              static_cast<UINT>(remaining), &accepted) != 0 && accepted == 1) {
        bootstrap_.Report(anywork::InstanceEvent::Redirected);
        return anywork::InstanceStartup::Redirected;
      }
      // A disappeared owner may release its OS lock. A hung owner keeps that lock, and the
      // next attempt can never start another engine while it still owns the home.
    }
    Sleep(50);
  }
  bootstrap_.Report(anywork::InstanceEvent::Unavailable);
  return anywork::InstanceStartup::Failed;
}

bool DesktopInstanceActivation::CreateEndpoint() {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.lpszClassName = kEndpointClass;
  if (RegisterClassW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
  const std::wstring key(bootstrap_.key().begin(), bootstrap_.key().end());
  endpoint_ = CreateWindowExW(0, kEndpointClass, key.c_str(), 0, 0, 0, 0, 0,
                             HWND_MESSAGE, nullptr, window_class.hInstance, this);
  return endpoint_ != nullptr;
}

LRESULT CALLBACK DesktopInstanceActivation::WindowProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* creation = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(creation->lpCreateParams));
  }
  auto* self = reinterpret_cast<DesktopInstanceActivation*>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (self != nullptr && message == kActivate) {
    if (self->restore_) {
      self->restore_();
      self->bootstrap_.Report(anywork::InstanceEvent::Activated);
    } else {
      self->pending_ = true;
      self->bootstrap_.Report(anywork::InstanceEvent::Pending);
    }
    return 1;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void DesktopInstanceActivation::WindowReady(std::function<void()> restore) {
  restore_ = std::move(restore);
  if (pending_) {
    pending_ = false;
    restore_();
    bootstrap_.Report(anywork::InstanceEvent::Activated);
  }
}

void DesktopInstanceActivation::WindowDestroyed() {
  restore_ = nullptr;
}
