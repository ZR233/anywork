/// 驱动与验收脚本使用的键值字符串。
///
/// 本文件**只依赖 Dart**：宿主机侧 driver 脚本（`test_driver/*.dart`）在纯 Dart VM
/// 中编译，任何 `package:flutter` 依赖都会因为缺少 `dart:ui` 而编译失败。Flutter 侧
/// 的 `StudioDriverKeys` 从同一常量构造 `ValueKey`，因此键值只有这一份事实源；
/// driver 脚本需要新的键时，把字符串加进这里并在 `StudioDriverKeys` 中引用。
library;

abstract final class StudioDriverKeyValues {
  static const shell = 'studio-shell';
  static const startPage = 'studio-start-page';
  static const newSession = 'sidebar-new-session';
  static const settingsBack = 'settings-back';
  static const sessionMode = 'session-mode-selector';
  static const sessionModeLabel = 'session-mode-label';
  static const startPageSelectors = 'start-page-selectors';
  static const reasoningEffort = 'reasoning-effort-selector';
  static const reasoningEffortLabel = 'reasoning-effort-label';

  static String sessionModeOption(String mode) => 'session-mode-$mode';

  static String reasoningEffortOption(String effort) =>
      'reasoning-effort-$effort';
}
