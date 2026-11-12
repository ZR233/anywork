# anywork Flutter

anywork 的 Windows、Linux、macOS 桌面客户端，使用 Material 3、Riverpod、typed GoRouter 和
flutter_rust_bridge；Rust bridge 位于 `rust/`，SDK-only Client 位于 `../anywork_client/`。
所有命令从仓库根执行，Flutter/Dart 包装自动进入 `code/anywork`，不要在 SDK 安装目录运行项目命令。

## 按目标选择最轻入口

| 目标 | 入口 | 边界 |
| --- | --- | --- |
| 纯界面调整、局部交互、截图 | `cargo xtask preview-gui --headless --no-devtools` | 官方 Widget Previewer 复用生产组件；**不编译 Rust bridge**，不启动模型服务，不需要 Xvfb |
| 组件布局/交互回归 | `cargo flutter test --no-pub test/ui/<相关用例>` | 无设备，不准备 bridge；保留确定性产品断言，不为截图新增测试入口 |
| 隔离真实业务观察 | `cargo xtask manual-gui --preset gui --inspect` | 本地严格模拟供应商、真实 AppGraph/FRB/SQLite；官方 Dart MCP 操作和截图 |
| 原生功能集成 | `cargo xtask test-project --suite desktop --case <用例>` | 官方 `integration_test` 在真实应用断言功能 |
| OS 进程退出/重开/多实例 | `cargo xtask test-project --suite native` | 独立进程裁判，不能由截图或 Client 关闭代证 |

统一的场景选择、控件发现、热更新、截图核图、错误检查及资源回收见
[无头实验指南](../../.agents/skills/flutter-studio-build/references/experiments.md)。不同载体不是每轮必跑清单，
不为了纯界面截图启动原生应用。预览标明合成状态，不证明保存、真实供应商、IME 或原生性能。

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

正式桌面测试保留生产资源所有者、受控对端和失败传播；性能采样与真实账号登录仅显式选择。
专项 fixture、保存重开、credit、20k 历史、真实 native 退出仍保留独特信号，不因整理人工流程删除。
证据口径和 CI 职责统一见[测试与人工验收](../../design/24-testing.md)，操作步骤不在本页另行复制。
