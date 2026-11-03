# anywork Flutter

Windows, Linux and macOS Flutter desktop client for anywork.

## Stack

- Flutter Material 3
- Riverpod state controller and selectors
- go_router page stack
- flutter_rust_bridge v2.13.0
- `pl-studio-bridge` Rust crate in `rust/`

## Commands

Building for macOS requires full Xcode and uses Flutter's Swift Package Manager integration.
The application targets macOS 13 or later.
Build and run through xtask on the desired host architecture. The complete `.app`
is collected at `dist/anywork-release/anywork.app`; `run-gui --release` launches it.
Remote helpers remain Linux targets for SSH hosts: install Zig and `cargo-zigbuild`
or supply the existing `PURE_REMOTE_HELPER_PREBUILT_DIR`. Local builds use ad-hoc
signing and run outside App Sandbox for workspace and tool access. Developer ID,
notarization and in-app updates are not configured for macOS. Stable and RC CI build
Apple Silicon archives on `macos-15`; `release-gui stage` packages the prebuilt `.app`
as a ZIP plus SHA-256, and `verify` extracts it to check version, arm64 and signatures.


On Linux, install the GTK runner dependency before the first native build.
Headless native GUI observation also requires Xvfb:

```bash
sudo apt-get install -y libgtk-3-dev xvfb
```

无头 widget 测试无需 Xvfb，但依赖中的 `cnativeapi` native-assets hook 仍会编译 C++。
Linux 需要可用 C++ 编译器、`pkg-config`、`libgtk-3-dev`、`libx11-dev` 和 `libxi-dev`；
CI 前端作业安装这些宿主依赖，仍不构建 Rust bridge 或启动原生窗口。

```powershell
# Run from repository root. xtask invokes Flutter with
# code/anywork as the working directory.
cargo flutter pub get
cargo flutter analyze
cargo dart format lib
cargo xtask run-gui
cargo xtask build-gui
cargo xtask generate-gui
cargo xtask check-gui-generated
cargo xtask build-gui --check-generated # CI/release: regenerate and reject unstable output

# Isolated native app with local scripted provider and evidence. Scene flag is --preset.
cargo xtask manual-gui --preset gui --inspect
# Optional Flutter content capture on a normal debug run (ext.anywork.capture).
cargo xtask run-gui --capture
# Official Flutter MCP/Driver widget inspection, interaction and screenshots.
cargo xtask run-gui --inspect
# Official browser preview, with project dependency overrides prepared automatically.
cargo xtask preview-gui --headless --no-devtools
# Official desktop / native project suites.
cargo xtask test-project --suite desktop --set smoke
cargo xtask test-project --suite native --set smoke

# Windows/Linux/macOS GUI run/build must use xtask so the runner receives the
# prebuilt Rust bridge artifact. cargo flutter/dart are passthrough commands.

# Use cargo xtask run-gui for live manual observations using installed config.
```

`cargo xtask build-gui` is a reproducible build step based on the checked-in `pubspec.lock` and
the workspace `Cargo.lock`. It may download missing packages, but uses Flutter
`pub get --enforce-lockfile` and Cargo `--locked`, so it cannot update lockfiles or resolve new
versions. The `cargo xtask` wrapper is also compiled with Cargo `--locked`. After intentionally
updating dependencies, run the corresponding dependency update command manually, review the
lockfile, and commit it before building again.

Riverpod、Freezed、l10n 和 FRB 生成必须从仓库根目录使用
`cargo xtask generate-gui`，不得手工修改生成文件。普通 `run-gui` 和 `build-gui` 只消费当前
源码，不执行生成器或可写格式化；修改生成输入后必须先显式生成。`cargo xtask check-gui-generated`
会快照当前输出并检查重新生成前后是否一致，不要求输出已提交；CI/发布构建使用
`build-gui --check-generated`。
生成、格式和静态检查使用 `cargo xtask verify-gui`。xtask 会校验 codegen
版本，并统一 FRB 2.12 用于 Rust crate 和输出的路径表示。

真实协作观察使用根 README 中的 `collaboration_observe` 或隔离 Studio server 的 HTTP/SSE；
GUI 交互通过 `cargo xtask manual-gui --preset` 的隔离模拟服务人工验收；真实供应商人工观察
直接使用用户配置运行 `cargo xtask run-gui`，不作为自动测试通过的证明。

The default app path initializes the native FRB runtime and subscribes only to the selected session stream. `DemoStudioApi` is selected only by an explicit demo build flag or a test override; native runtime failures are surfaced instead of switching implementations.

## 官方技能与原生 MCP 观察

Flutter / Dart 官方技能安装在用户主目录 `.agents/skills/`，不放入本项目。
来源为 [flutter/agent-plugins](https://github.com/flutter/agent-plugins) 和
[dart-lang/skills](https://github.com/dart-lang/skills)；通用教程按任务读取，项目适配见根 `AGENTS.md`。

原生应用从根目录使用 `cargo xtask run-gui --inspect`，隔离模拟观察使用
`cargo xtask manual-gui --preset gui --inspect`。两者通过专用 debug 入口启用官方 Driver extension，
不改变正式入口或集成测试 binding。Dart MCP 使用实际 SDK 的 `dart mcp-server` 直接提供 stdio，
项目通过 roots 指定；不要使用向 stdout 打印日志的 Cargo 包装启动 MCP，也不要让 MCP
`launch_app` 绕过项目的 bridge/helper 准备。

先读取已安装 MCP 的 schema，`dtd.connect` 使用本次日志中的 DTD URI，`appUri` 使用
应用的 VM Service URI；两者不能混用。原生直启仅有 VM Service 时使用官方
`vm_service.connect` 或 Flutter Driver SDK 附着。使用
`widget_inspector` 的 `get_widget_tree` 发现控件，再用 `flutter_driver_command` 获取布局诊断、
点击、输入、滚动和 `screenshot`。多应用显式指定 `appUri`。截图返回后实际查看画面，结合
运行时错误和 canonical 状态判断；复用热更新缩短迭代，不把工具调用成功当作行为断言通过。

这些 Flutter 接口在 Windows 和 Linux 共用。Linux SSH 没有显示服务时，使用
`GDK_BACKEND=x11 xvfb-run -a` 包装原生入口；人工 preset 还需要可写 TTY。
Xvfb 只提供显示环境，Windows 原生应用仍需要桌面会话。Flutter 截图不覆盖窗口装饰、系统菜单
或真实 IME；这些边界按需专项验证。已有 `--capture` 保留带来源元数据的 PNG 落盘，退出仍由
生产关闭协调器和工程进程所有者共同确认。截图、日志及一次性探针不提交。

## 账号组件预览

账号组件的官方预览分为三组入口：

- `previews/accounts_previews.dart` 展示账号整页与状态场景。
- `previews/account_template_previews.dart` 展示 8 个 Native 模板及 Antigravity 的
  List、Details、Editor 状态。
- `previews/account_component_previews.dart` 按生产职责分组提供组件预览入口，直接实例化生产组件，
  覆盖身份与 Native/ACP 列表项、额度/用量/状态、模板选择器的 true/false/unknown usage，
  Native 连接与凭据/计费字段、编辑器默认值和手动模型焦点、菜单的两种触发方式、显式保存的
  Models 列表、模型规格/价格/缺失价格、评价筛选与卡片/摘要、ACP 面板与确认对话框、资料页三标签。
  例如 `accountMenuButtonTriggersPreview`、`accountTemplateSelectorPreview`、
  `accountListItemWithDisplayOriginPreview`、`accountNativeEditorSetDefaultOnCreatePreview`、
  `accountModelSpecificationsPreview` 与 `accountEvaluationFiltersPreview`。

以上入口复用生产组件、主题、本地化和品牌资源，以合成数据展示宽窄布局及状态；它们不通过
ProviderScope、Client 或 FRB 建立业务运行时，预览动作仅改变本地展示或记录回调。纯视图入口
`lib/src/features/settings/accounts/accounts_views.dart` 只导出不可变呈现值与生产视图，
不导出 ViewModel、Connector、Client 或 Rust bridge。合成数据预览不是原生运行、供应商、凭据、
持久化或 canonical 业务状态的证明。

官方工具会编译项目内所有已发现的预览，搜索筛选不是依赖隔离。不要在原生应用壳的
`part` 中注册预览，或通过预览入口导入 AppGraph/FRB；旧工作区聚合预览已移除，
完整工作区和时间线仍使用原生 demo 或 `manual-gui --preset` 观察。纯组件与组合时间线直接使用生产 View，完整业务链路使用隔离原生集成测试。Native 模型声明使用同一套结构化手动模型
字段，不另设自由文本解析器或第二份文本草稿。

预览编写方法使用用户级官方 `flutter-add-widget-preview` 技能；项目的启动与恢复入口为：

```bash
cargo xtask preview-gui --headless --no-devtools
cargo xtask preview-gui --help -v
# 不完整缓存恢复前，先结束所属预览进程：
cargo flutter widget-preview clean
```

入口先按应用锁文件准备依赖，再从应用 `pubspec.yaml` 与可选的 `pubspec_overrides.yaml`
派生 `.widget_preview/pubspec_overrides.yaml`，相对本地包路径转换为绝对路径。
该缓存文件由入口维护，无需手工准备；应用覆盖字段按 Dart Pub 契约替换，不维护第二份包名或版本清单。
应用 lockfile 不随预览升级，官方 scaffold 仍拥有自己的依赖解析和缓存。

预览器负责源码发现、Web 编译与热更新。默认让官方工具启动并连接浏览器；无头模式可用
`CHROME_EXECUTABLE` 指定实际 Chrome/Chromium。需要服务模式时透传 `--web-server`，但
完整热更新调试依赖 Dart Debug Chrome 扩展；仅刷新页面不证明热重载成功。先固定场景、视口、
主题和字号，再对照设计检查画面；退出后等待 Flutter、DTD、分析服务和浏览器回收，不占用 `1420`。
生成输入变化仍先执行 `cargo xtask generate-gui`。

当前依赖策略是短期保留 `packages/cross_cache` 兼容补丁，不为去掉该目录而降级
`cross_file` / `desktop_drop`，也不另加缓存库。相对官方 `cross_cache 1.1.1`，本地代码
只适配 `XFile.fileSystem(path: ...)`，并等待图片解码 Future，使异步解码失败进入既有错误处理；
包约束同步适配 `cross_file 0.4`。当上游发布兼容版本后，先核对这两处行为和桌面/Web 依赖解析，
再统一移除本地包和应用 override；预览入口会更新派生配置，随后更新应用 lockfile 并完成相关图片与预览回归。

预览证明的是组件解耦、Web 渲染和布局，不证明原生插件、FRB、凭据、持久化或进程关闭行为；
这些仍需通过 `cargo xtask manual-gui --preset` 和真实 `run-gui` 验收，PR 产品截图也应来自原生程序。
PR 产品集成截图应来自同次真实应用运行，并区分官方集成测试的离屏渲染表面与操作系统顶层窗口；
合成组件预览只能作为明确标注的组件视觉证据，不能冒充产品集成。
截图和诊断日志写入当前会话产物目录，不放入源码或预览缓存的 Git 提交。

官方参考：[Widget Previewer](https://docs.flutter.dev/tools/widget-previewer)、
[依赖覆盖与 pubspec_overrides.yaml](https://dart.dev/tools/pub/dependencies#pubspec_overridesyaml)。

## 时间线组件预览与原生集成

时间线的官方预览位于 `lib/src/features/conversation/timeline/previews/`：

- `timeline_component_previews.dart` 直接实例化历史条目、过程、工具、等待、问答/Plan
  回执、正文窗口、媒体及组合时间线等生产组件，以合成数据检查展开、窄窗与长内容。
- `conversation_live_status_previews.dart` 展示实时栏的思考、运行活动、流式正文和压缩，
  直接组合同一生产内容组件；展开由组件自身状态处理，current 详情不创建业务读取资源。
- `conversation_current_previews.dart` 展示真实生产 current 纯组件的正文、集合、条目与读取诊断。
- `plan_detail_previews.dart` 以固定不可变场景展示计划详情、全宽模式和窄窗文字缩放，
  不在 Preview 外壳模拟生产工作区的关闭或布局切换。

从根目录启动
`cargo xtask preview-gui --headless --no-devtools`；搜索 `Timeline` 可找到这些入口。预览不创建
`ProviderScope`、`AppGraph`、Client 或 FRB，不复制另一份时间线或 current 状态。
截图须标明合成预览与原生运行的区别，不能用概念稿截图冒充生产组件。

普通功能集成使用 Flutter 官方 `integration_test`，通过
`cargo xtask test-project --suite desktop --case <场景>`
运行真实生产组件。需要隔离配置、严格模拟供应商、持久化与进程回收时使用
`cargo xtask manual-gui --preset` 对应场景，不直接把测试连接到用户的 Studio home。
测试使用 `WidgetTester` 和真实 `AppGraph`，不依赖 `driver_main` 或 `requestData` 协议。
业务就绪与帧推进分别等待，持续旋转或流式输出期间不以 `pumpAndSettle` 等待业务结束。

三个普通呈现场景默认不截图，不依赖平台截图命令。需要 Linux/Windows 集成截图时显式设置
`ANYWORK_CAPTURE_PRESENTATION=1`；未知值在业务环境启动前报错，未启用时清除继承的内部
`ANYWORK_PRESENTATION_SCREENSHOTS` 目录变量。截图保存在该次 `target/manual-gui/` 输出中，
使用官方 `RepaintBoundary.toImage` 捕获同一真实 AppGraph/FRB/SQLite 应用已经绘制的离屏
render surface，不注入业务值，也不增加备用 UI。它不是 X11 顶层窗口或输入法证据；
采集失败使场景失败，PNG 产出后仍须人工核对画面。

`timeline-history` 的官方场景保留流中分页、40 页历史与同一 home 重启恢复；
`question-history` 检查真实分步问答和历史回执；
`realtime-presentation` 使用既有严格 realtime fixture 检查实时正文、思考、工具、停止和失败。
原 `realtime` 的 FRB credit、host cwd 等专项观察，以及 `plan-recovery` 的多生命周期恢复，
仍保留独立入口，不能用普通展示测试或 Preview 的结果替代。

独立的 20k 历史、原生位移和帧耗时采样仍保留各自入口，供人工观察使用；
它们不与普通展示旅程捆绑重跑。覆盖边界见
[测试与人工验收](../../design/24-testing.md) §24.1.3。
