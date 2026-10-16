#include "studio_tray.h"

namespace anywork {

// Linux 托盘契约的预留落点：尚未实现宿主，不引入 GTK/StatusNotifier/AppIndicator
// 依赖。StudioTraySupported 为假且工厂返回空，窗口关闭仍直接构成退出请求
// （design/19 §19.14）。
bool StudioTraySupported() { return false; }

std::unique_ptr<StudioTray> CreateStudioTray() { return nullptr; }

}  // namespace anywork
