#ifndef RUNNER_COMMON_STUDIO_TRAY_H_
#define RUNNER_COMMON_STUDIO_TRAY_H_

#include <functional>
#include <memory>
#include <string>

namespace anywork {

// 托盘菜单文案（UTF-8）。调用方须在图标存活期内保持有效；实现内部复制。
struct StudioTrayLabels {
  std::string show_window;
  std::string exit_app;
};

// 托盘菜单命令回调；均在平台主线程被同步调用。
struct StudioTrayCallbacks {
  std::function<void()> show_window;
  std::function<void()> exit_app;
};

// 通知区域托盘宿主契约。
//  - Windows 由 windows/runner/studio_tray_windows.cc 实现真实宿主。
//  - Linux 由 linux/runner/studio_tray_linux.cc 实现「不支持」语义：没有任何托盘宿主，
//    窗口关闭仍直接构成退出请求（design/19 §19.14）。
class StudioTray {
 public:
  virtual ~StudioTray() = default;
  // 注册图标与菜单；幂等；失败返回 false（调用方回退为关闭即退出）。
  virtual bool Install(const StudioTrayLabels& labels,
                       StudioTrayCallbacks callbacks) = 0;
  // 移除图标并释放平台资源；幂等。
  virtual void Remove() = 0;
  virtual bool installed() const = 0;
};

// 当前平台是否具备托盘宿主实现。
bool StudioTraySupported();

// 创建当前平台的托盘宿主；不支持时返回 nullptr。
std::unique_ptr<StudioTray> CreateStudioTray();

}  // namespace anywork

#endif  // RUNNER_COMMON_STUDIO_TRAY_H_
