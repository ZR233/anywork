---
name: flutter-studio-build
description: Use when building anywork on Windows, Linux or macOS, aligning UI designs with official headless Flutter tests or Widget Previewer, connecting Dart MCP to the native GUI, collecting Flutter content evidence, debugging release builds, or troubleshooting flutter_rust_bridge generated bindings.
metadata:
  category: guides
  platforms: windows, linux, macos
---

# anywork 构建

涉及跨层分工、状态与资源所有权或页面路由时，先使用 `flutter-frb-rust-design`；
本技能只维护项目生成、构建、运行与证据边界。通用预览、布局、测试和 Dart 教程使用
用户级官方 `flutter-*` / `dart-*` 技能；发现与命令映射见根 `AGENTS.md`，不在项目复制上游内容。

## 统一实验方法，按边界选择最轻入口

实验、验证和截图统一使用[无头实验指南](references/experiments.md)。纯界面开发默认用官方
Widget Previewer 复用生产组件、主题与本地化，局部交互和截图**不编译 Rust bridge**，
不启动模型服务，也不依赖 X11/Xvfb。确定性行为使用相关 Widget 测试，不新增截图落盘用例。

只有 FRB、持久化、原生插件或资源行为才选择隔离原生应用与官方 Dart MCP；OS 退出等由平台专项证明。
不同载体共享取证方法，不建立第二份 UI、业务状态或操作框架，也不排成每轮必跑清单。

## 会话临时文件

一次性诊断脚本与探针优先使用最新 `studio.session-files` 事实给出的本会话执行 `scratch/`，
不要使用宿主内部会话数据库目录、helper 缓存或其他 Thread 的目录。SSH 的事实路径属于远端；
需要本地捕获时在本地工程工具自己的证据目录准备脚本，不把远端路径传给本地 Dart。
xtask 已定义的 `target/manual-gui/` 证据输出仍遵循工具入口，临时截图、日志和 VM URL 不提交。

## 标准入口

原生 GUI 构建和运行从仓库根目录通过 xtask 执行；官方组件预览只借助项目入口准备依赖，
也支持准备后直接使用 Flutter CLI，详见[预览入口](references/widget-preview.md)：

```powershell
cargo xtask run-gui
cargo xtask run-gui --demo
cargo xtask run-gui --inspect
cargo xtask preview-gui --headless --no-devtools
cargo xtask run-gui --release
cargo xtask test-project --suite desktop
cargo xtask test-project --suite native
cargo xtask build-gui
cargo xtask build-gui --demo
cargo xtask build-gui --no-clean
cargo xtask build-gui --check-generated
```

当前产品支持 Windows、Linux 与 macOS 桌面工程。不要直接执行 `flutter build windows|linux|macos` 或
`flutter run -d windows|linux|macos`；xtask 负责 Rust bridge 预构建、环境注入、Flutter 调用和进程回收。

普通 xtask 不链接 Studio runtime、模型、数据库或 GUI 验收工具。`cargo xtask manual-gui`
仅在调用时编译并启动独立 `pl-studio-acceptance`，参数由该工具唯一解析；路径与平台进程
支持由轻量 `pl-dev-support` 共享。验收工具使用正常 workspace 构建目录并尊重显式
`CARGO_TARGET_DIR`，不复用 xtask alias 专用的 `target/xtask` 参数。全 workspace 门禁
仍会编译验收工具；GUI 构建显式编译 bridge 也仍会编译 runtime，不应误判为依赖回流。

## 依赖与生成文件

`run-gui --release` 仅运行 `dist/anywork-release` 中已有的当前平台原生程序，不执行构建、生成或依赖解析。缺少程序时先执行 `build-gui`；不要将 demo 构建当作真实发布程序。关闭和取消沿用平台进程树所有权。

`run-gui` 和 `build-gui` 直接调用 Flutter 的依赖命令，由 Flutter 自身负责缓存、锁和错误返回。
`xtask` 不维护工作区锁、不写入依赖指纹，也不改写 `pubspec.lock`；构建使用
`flutter pub get --enforce-lockfile`，其他生成或运行入口透传 Flutter/Dart 的依赖错误。

`test-project` 的 native 套件继承同次调用的 debug 准备租约；相同 Flutter 构建参数只构建一次，
完整程序包独立复制并在每次启动前校验，入口或 capture 不同的程序包互不覆盖。
该准备不供 profile/demo、独立调用或其他 CI 作业消费；失效与损坏直接失败，不能用跳过构建参数替代。
Linux CI 另通过同次 workflow 的受控交接共享验收工具、debug bridge、release 模拟供应商和原生 Host MCP 二进制；逐文件核对 profile、摘要及源码、镜像、工具链、工作区和运行编号，损坏直接失败。它不共享可变构建目录或场景状态。
执行编译的作业管理 Cargo 缓存；默认 CI desktop 分片与 native 作业只恢复同次产物，不恢复或保存 Rust 缓存。同一 job 内的步骤共享本地 `target`，无需额外交接整份目录；没有上游编译产物的独立验证作业保留自身缓存。
具体身份、计时与清理边界见[原生 GUI 观察与隔离](../../../design/24-testing.md#243-原生-gui-观察与隔离)。

桌面准备身份覆盖整个 checkout 的 HEAD、已跟踪差异及未跟踪源码，不只覆盖所选 case。
从 `test-project` 准备开始到整次命令终态，须协调停止同 checkout 的源码、Git 和生成写入；
其他文件的并行编辑也会使准备失效。收到 `desktop preparation source changed` 时保留原件，
区分用例尚未启动与业务断言失败；先建立稳定源码窗口再显式安排新尝试，不跳过身份校验。
只读调查或各自会话产物准备可以并行，未知邻居 checkout 的进程不自动证明共享缓存争用。

普通运行和构建不执行生成器或可写格式化。Riverpod、Freezed、本地化或 FRB 的生成与一致性检查入口为：

```powershell
cargo xtask generate-gui
cargo xtask check-gui-generated
```

`check-gui-generated`、`verify-gui` 与 `build-gui --check-generated` 比较重新生成前后的 canonical
输出，拒绝生成不稳定或输入未同步；它们不以 Git 暂存或提交状态作为判断依据。生成文件不得手工
修改，也不得绕过 xtask 直接调用单个生成器。

FRB 会在生成前以 `frb_expand` 配置展开手写 Rust API。生成输出不是展开输入，bridge 的手写
模块声明用 `#[cfg(not(frb_expand))]` 排除该生成模块，避免旧绑定或合并冲突阻止重新生成；
不得手工造 stub、选一侧绑定或跳过一致性检查。正常构建不设置此 cfg，仍须完整编译生成模块，
并验证桥接消费者；展开或生成成功不能代替正常构建通过。

共享 checkout 中先等待生成命令完整结束，再启动消费生成物的分析、Client 适配测试或原生构建。
生成器可能先替换输入再重建 Freezed 等产物；此时并发测试看到的缺失 `part` 文件属于不完整
生成窗口，不能据此修改生成物或判断业务失败。`verify-client` 只检查 SDK-only Client；应用适配与 UI 闭包由 `verify-gui` 和 `flutter test --no-pub test/ui` 覆盖。接口返修后重新生成受影响产物，再补失败或受影响的消费者证据。

## Rust bridge

`pl-studio-bridge` 由 Cargo 预构建；flutter_rust_bridge 负责生成 Dart/Rust 绑定，不负责生成
DLL 或共享库。xtask 从 Cargo profile 目录定位 Windows DLL/PDB 或 Linux `.so`，通过
`ANYWORK_BRIDGE_LIBRARY` 等环境变量交给 CMake staging。CMake 不再启动 Cargo。

Linux remote helper 不嵌入 bridge：xtask 独立构建、校验并准备两种架构的压缩资源，CMake
随 Flutter bundle 安装到可执行文件旁的 `data/remote-helper/<target>/`。运行时从该目录
按架构加载资源并校验元数据与摘要，不依赖构建环境变量，不回退到 PATH 或源码目录。
排查缺资源时检查完整 bundle，而不是仅复制 bridge 动态库。仅 helper 资源变化不应导致
runtime 重编译或 bridge 重链接；用 Cargo Fresh 状态与 bridge 摘要验证，不单靠构建耗时。

绑定不同步常表现为 Dart 方法缺失、联合类型匹配不完整或 Rust/Dart 类型字段不一致；
生成产物与输入的差异可帮助定位原因。

Rust 模块移动后，同时核对生成文件集合而非只看已有文件内容：旧模块的 Dart 文件可能仍在目录
中引用已删除的绑定。`lib/src/rust/` 只保存 FRB 生成物，不放手写转发或业务默认值；手写 typed 导出入口属于
`infrastructure/frb/`；孤儿产物由统一生成入口清理，不手改生成文件或新增旧 API 转发。分析中的
加载错误消除只说明生成或分析边界恢复，不证明 adapter、布局或交互行为正确。生成失败必须原样
传播，不能将不完整的输出集合判为一致。

```powershell
cargo build -p pl-studio-bridge
cargo xtask verify-gui
```

## 原生崩溃取证

遇到原生信号退出、跨动态库回溯或只有退出码而没有故障栈时，按
[原生崩溃取证边界](references/native-crash-evidence.md) 保留真实进程、原始日志与调试证据；
不绕过 xtask、不改全局调试权限，也不把诊断阶段或首次信号停止当作根因。

## 构建产物

Flutter 原始 release 输出位于：

- Windows：`code/anywork/build/windows/x64/runner/Release/`
- Linux：`code/anywork/build/linux/x64/release/bundle/`
- macOS：`code/anywork/build/macos/Build/Products/Release/anywork.app`

`cargo xtask build-gui` 完成后再把可发布文件收集到 `dist/anywork-release/`。Windows/macOS PR 编译使用这一默认 Release/AOT 路线并保留 bundle 与工程工具检查点，不发布；Rust 测试与依赖 VM service 的 GUI 测试继续使用开发配置。讨论故障时明确区分
Flutter 原始输出与 xtask 最终收集目录。

Windows 稳定发布将编译与打包分开：先运行 `cargo xtask build-gui`，再以
`release-gui stage --version <x.y.z> --bundle <路径>` 消费显式提供的预构建 bundle。
`stage` 不启动 Flutter/Rust 编译；运行 bundle 与小型发布工具分别归档，下游对各自有效载荷
核对一次生产者摘要，并核对工具编译工作区与源码/版本身份，禁止缺失时回退重新编译。
不收集独立符号包，不为重复身份创建自述清单；`finalize` 已执行完整自检，同一作业不重复
核验未改变的资产，跨作业和正式发布前的安全校验仍保留。构件过期或完整重跑不属于断点续跑保证；
后置失败优先仅重跑失败/指定作业。阶段、权限与安全验证边界见
[发布与更新](../../../design/23-release-update.md#231-版本与发布流)。

Windows 发布目录只收集运行所需的 `anywork.exe`、Flutter/bridge/插件 DLL、
应用目录部署的 VC++ Release 运行库及完整 `data/`，不收集 PDB、导入库或编译中间物。
`data/app.so` 是 Windows Dart AOT 产物，不可当作 Linux 文件删除。Linux 发布目录包含对应可执行文件、Flutter 库、
`libpl_studio_bridge.so` 与数据目录。两平台 `data/remote-helper/` 均包含两个架构的
`pl-remote-helper.zst` 和 `pl-remote-helper.metadata.json`，应随安装包一并交付。

## macOS

macOS 使用完整 Xcode 和 Flutter 官方 Swift Package Manager 集成；现有插件无需 CocoaPods。
xtask 将 Flutter/Xcode 的架构与 Cargo 当前宿主对齐（Apple Silicon 为 `arm64`），不直接使用
可能返回 `arm64e` 的 `NATIVE_ARCH_ACTUAL`。Rust bridge 放入 `.app/Contents/Frameworks/`，
helper 压缩资源放入 `.app/Contents/Resources/data/remote-helper/`。SSH helper 仍为两个 Linux
musl 目标，可复用现有 Zig/cargo-zigbuild 或 `PURE_REMOTE_HELPER_PREBUILT_DIR` 入口。

最终收集目录为 `dist/anywork-release/anywork.app`，必须保留 framework 版本符号链接；
`run-gui --release` 直接启动包内 `Contents/MacOS/anywork`。本地与 CI 使用 ad-hoc 签名，
不启用 App Sandbox，不包含 Developer ID、公证或应用内更新。稳定版与 RC 共享 `macos-15`
Apple Silicon 构建、预构建打包作业；`release-gui stage` 通过 Apple `ditto` 生成完整 `.app` ZIP
及 SHA-256，`verify` 解包核对版本、arm64 架构、资源和完整签名。编译检查点以 tar 保留
framework 符号链接与执行权限，跨作业仍按构件 ID、生产者摘要与工具工作区验证，不回退编译。
关闭窗口与 `Cmd+Q` 复用标准退出协调器和共享原生期限。原生测试与人工验收使用 `process-wrap` 进程组回收；
macOS 没有 Linux subreaper，主动脱离进程组的子进程不在该机制覆盖内，不能外推 Linux 回收结论。

## 入口的证明范围

构建、生成检查、Client 测试、Widget Previewer、内容捕获和原生人工操作各有不同的观察边界，
可按实际风险选用，不构成固定先后顺序或每次 GUI 修改的必跑清单。
`verify-gui` 不接受 `--integration`；其成功不等同于实际业务交互通过。

Linux 缺少编译器、CMake、Ninja、pkg-config 或 GTK 3 开发文件时，保留 xtask 返回的真实预检命令
和原始错误，不注入机器专用 include/library 路径。

## 原生实验的补充边界

共同操作按[无头实验指南](references/experiments.md)，隔离数据、系统凭据及平台进程责任按
[原生补充](references/manual-gui.md)。管道 stdin 可以驱动完成信号，不依赖伪终端；
截图由官方 MCP 完成，自定义 capture 仅保留自动化及原生测量的内部职责。

## 官方组件预览

组件作者使用用户级 `flutter-add-widget-preview`；本项目启动与依赖适配见
[预览入口](references/widget-preview.md)。已有预览直接复用生产 View、主题及合成数据。
原生交互用 `run-gui --inspect` 或 `manual-gui --preset gui --inspect`，自动化业务断言用
`test-project --suite desktop`；组件截图、原生交互和持久化分别报告覆盖，不层层重复验收。
