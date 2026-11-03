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
cargo xtask manual-gui --preset gui
# Optional Flutter content capture on a normal debug run (ext.anywork.capture).
cargo xtask run-gui --capture
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

## 官方无头界面对齐与组件预览

界面设计对齐建议优先使用官方无头工具，而不是为排版调整反复启动 X11/Xvfb 原生应用：

- 布局、溢出、展开和滚动行为通过 `cargo flutter test <相关测试路径>` 的生产组件 Widget 测试验证，无需桌面显示服务。
- 人工对照概念稿时，使用 `cargo flutter widget-preview start --headless --no-devtools`，由官方工具启动无头 Chrome，配合成熟浏览器工具检查实际组件、截图和交互；不用另建预览 UI。
- 先核对当前 `cargo flutter widget-preview start --help -v`，并完成下文现有依赖覆盖准备。浏览器、分析服务和 DTD 随本次预览收束，不占用 `1420`。

时间线已有 `features/conversation/timeline/previews/` 下的生产组件预览，覆盖内容、实时状态与回执，可与账号预览复用同一官方入口。`Timeline · 原子工作组` 直接使用共享的 `TimelineDisplayUnitView`，提供实时等待、工作与正文交替和窄窗 160% 字体三个入口；只检查已给定呈现值的布局与展开，不模拟分组接纳或业务完成。按实际目标选择组件约束、主题、语言和状态，不把合成数据或局部回调当作真实业务结果。原生集成、产品截图和性能的证明边界见[测试与人工验收](../../design/24-testing.md#2414-官方无头工具与界面设计对齐)。

### 账号预览入口

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

从仓库根目录操作，生成输入变化后先同步生成物：

```text
cargo xtask generate-gui
cargo dart analyze lib/src/features/settings/accounts
cargo flutter widget-preview start
```

SSH 或需要手动选择浏览器时使用 `cargo flutter widget-preview start --web-server --no-devtools`，
打开命令输出的实际服务地址；不要占用项目保留端口 `1420`。首次仍需 Flutter Web 编译，
后续由官方工具使用 `.widget_preview/` 缓存并响应源文件修改，不构建桌面程序或启动业务运行时。
在预览底部搜索框按场景名称筛选，可直接操作生产组件的搜索、展开与编辑回调。

验证热更新时优先让官方工具启动并连接 Chrome；Linux 无桌面环境可使用
`cargo flutter widget-preview start --headless --no-devtools`，必要时将 `CHROME_EXECUTABLE`
指向实际安装的 Chrome/Chromium。`--web-server` 的完整调试依赖 Dart Debug Chrome 扩展，
不能将不带扩展的浏览器布局截图等同于热更新成功；反复关闭页面后若出现热重载客户端超时，
应退出该服务并切换到官方浏览器模式，不修改预览工具源码或把失败吞掉。关闭预览使用 `Ctrl-C`，
等待命令及所属分析服务、DTD 和浏览器进程退出；临时目录和截图仍遵循会话文件约定。

### 当前依赖覆盖的准备

Flutter 3.47 的预览工程是单独的依赖解析根，不继承应用的 `dependency_overrides`。
当前 `flutter_chat_ui` 依赖的官方 `cross_cache 1.1.1` 尚未适配项目使用的 `cross_file 0.4`，
因此预览必须引用应用已有的同一个兼容包，而非再复制一份实现。
首次启动前，创建 `code/anywork/.widget_preview/pubspec_overrides.yaml`：

```yaml
dependency_overrides:
  cross_cache:
    path: ../packages/cross_cache
```

这是 Dart 官方支持的本地依赖覆盖配置，放在已忽略的预览缓存内，不提交该目录，也不修改 Flutter SDK。
若首次启动曾因版本冲突中断，先执行 `cargo flutter widget-preview clean`，再重新创建上述文件后启动，
避免复用不完整的预览依赖缓存；清理或 SDK 升级后应检查该配置是否仍存在。
应用的 `pubspec.yaml` 和 `pubspec.lock` 不因这一步改变。

当前依赖策略是短期保留 `packages/cross_cache` 兼容补丁，不为去掉该目录而降级
`cross_file` / `desktop_drop`，也不另加缓存库。相对官方 `cross_cache 1.1.1`，本地代码
只适配 `XFile.fileSystem(path: ...)`，并等待图片解码 Future，使异步解码失败进入既有错误处理；
包约束同步适配 `cross_file 0.4`。当上游发布兼容版本后，先核对这两处行为和桌面/Web 依赖解析，
再统一移除本地包、应用及预览 override，更新应用 lockfile 并完成相关图片与预览回归。

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

先按前文准备官方预览缓存的依赖覆盖，再从根目录启动
`cargo flutter widget-preview start`；搜索 `Timeline` 可找到这些入口。预览不创建
`ProviderScope`、`AppGraph`、Client 或 FRB，不复制另一份时间线或 current 状态。
截图须标明合成预览与原生运行的区别，不能用概念稿截图冒充生产组件。

普通功能集成使用 Flutter 官方 `integration_test`，通过
`cargo xtask test-project --suite desktop --case <场景>`
运行真实生产组件。需要隔离配置、严格模拟供应商、持久化与进程回收时使用
`cargo xtask manual-gui --preset` 对应场景，不直接把测试连接到用户的 Studio home。
测试使用 `WidgetTester` 和真实 `AppGraph`，不依赖 `driver_main` 或 `requestData` 协议。
业务就绪与帧推进分别等待，持续旋转或流式输出期间不以 `pumpAndSettle` 等待业务结束。

三个普通呈现场景默认不截图，不依赖平台截图命令。需要 Linux 集成截图时显式设置
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
