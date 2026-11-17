# anywork Flutter

anywork 的 Windows、Linux、macOS 桌面客户端，使用 Material 3、Riverpod、typed GoRouter 和
flutter_rust_bridge；Rust bridge 位于 `rust/`，SDK-only Client 位于 `../anywork_client/`。
本页的 Cargo 命令从仓库根执行，Flutter/Dart 包装自动进入 `code/anywork`，不要在 SDK 安装目录运行项目命令。
独立组件预览位于 `../anywork_previews/`，依赖准备后也支持在该目录直接使用官方 Flutter CLI。

## 按目标选择最轻入口

场景选择、控件发现、热更新、截图核图、错误检查及资源回收见 [无头实验指南](../../.agents/skills/flutter-studio-build/references/experiments.md)；
自动化命令与真实边界见 [测试基础设施](../../design/24-testing.md)。

纯界面迭代从仓库根使用 `cargo xtask preview-gui --headless --no-devtools`，不编译 Rust bridge。
预览标明合成状态，不证明保存、真实供应商、IME 或原生性能。

现有账号、时间线、输入框、工作模式和侧栏预览直接复用生产 View、主题和本地化；合成数据只提供
呈现输入，不实现第二套分组或业务状态。官方工具会编译全部已发现入口，筛选 UI 不隔离原生依赖；
新增预览不能引入 Client、FRB、`dart:io` 或 `dart:ffi`。项目 Pub overrides 与缓存恢复见
[预览适配](../../.agents/skills/flutter-studio-build/references/widget-preview.md)。

## 构建、依赖与生成

```bash
cargo flutter analyze
cargo dart format lib test tool integration_test
cargo xtask run-gui
cargo xtask build-gui
cargo xtask generate-gui
# 按需选择生成一致性或前端综合检查，不必依次重复：
cargo xtask check-gui-generated
cargo xtask verify-gui
cargo xtask verify-client
```

原生 run/build 必须通过 xtask 准备 bridge/helper，不直接 `flutter run/build -d <桌面平台>`。
普通 run/build 不生成源码；Riverpod、Freezed、本地化和 FRB 只通过 `generate-gui` 统一生成，
不手改产物。`check-gui-generated` 会写入生成文件，比较生成前后 canonical 输出，不以暂存状态判定。
`build-gui --check-generated` 可显式包含该检查，不需要另跑相同入口。

`Cargo.lock` 和 `pubspec.lock` 是 canonical 快照；构建使用 Cargo `--locked` 和
`pub get --enforce-lockfile`，可补齐缓存但不解析新版本。依赖升级单独执行并审查锁文件。
宿主/容器不要同时改写同一 checkout 的 Pub 或生成缓存，切换前先结束原运行。

Linux 构建和 CI 使用[项目 Docker 环境](../../docker/linux/README.md)；Clang、CMake、Ninja、
pkg-config、GTK 3/X11/Xi 等由镜像统一提供，消费作业不补装系统包。无头 Widget 测试不需要
Xvfb，但依赖的官方 native-assets hook 仍可能编译 C++，这不是编译 Rust bridge。
缺少依赖保留原始错误，不禁用 hooks、注入机器专用路径或增加替代 UI。

macOS 使用完整 Xcode 和 Flutter 官方 Swift Package Manager，支持 macOS 13+，构建当前宿主架构。
发布收集到 `dist/anywork-release/anywork.app` 并保留 framework 符号链接；本地仅 ad-hoc 签名，
不包含 Developer ID、公证或发布授权。跨架构 helper、发布打包和平台细节见
[构建技能](../../.agents/skills/flutter-studio-build/SKILL.md)及[发布契约](../../design/23-release-update.md)。
`run-gui --release` 只启动已有 bundle，不执行构建或依赖解析。

## 原生实验的额外边界

需要真实业务时才使用隔离 `manual-gui`；Linux 无桌面可由系统 `xvfb-run` 提供虚拟显示。
管道 stdin 可以发送完成信号，不要求伪终端，不重复录入 UI 动作；隔离验收复用已有 debug
native launcher 及同一官方检查入口，用官方 VM Service 连接能力附着本次应用。截图后发送 `done`，
等待原命令终态并校验真实退出报告及后代回收。EOF/取消、报告缺失、非零退出或强制回收残留都不是成功。
该验收载体不提供 resident 热重载；纯界面迭代用预览，确需跨层开发热重载才用普通 `run-gui --inspect`。
真实供应商仅在具体授权后使用 `run-gui --inspect` 和已有配置，不修改用户凭据。

Dart MCP 使用实际 SDK 的 `dart mcp-server`，先注册当前工作区 roots、发现本次 DTD，再确认目标应用。
DTD URI 与 VM Service URI 不能混用；先读 widget tree，再定位点击、输入、滚动或截图。
不要用 MCP 启动另一个应用绕过 xtask；Driver 调试入口、正式入口和 integration-test binding 分离。
纯预览不一定注册 Driver extension，按真实能力使用成熟浏览器工具，不新增私有桥接协议。

证据口径和 CI 职责统一见[测试与人工验收](../../design/24-testing.md)，操作步骤不在本页另行复制。
