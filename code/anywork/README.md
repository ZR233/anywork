# anywork Flutter

Windows and Linux Flutter desktop client for anywork.

## Stack

- Flutter Material 3
- Riverpod state controller and selectors
- go_router page stack
- flutter_rust_bridge v2.13.0
- `pl-studio-bridge` Rust crate in `rust/`

## Commands

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

# Run the native app through the dedicated test_driver entrypoint for Dart MCP
# interaction and GUI acceptance. The driver command owns the resident process
# tree, keeps Flutter's control pipe open, and connects directly to the app VM
# service without a DDS proxy. Release builds never use it.
cargo xtask run-gui --driver
cargo xtask manual-gui # isolated native app with local scripted provider and evidence

# Windows/Linux GUI run/build must use xtask so the runner receives the
# prebuilt Rust bridge artifact. cargo flutter/dart are passthrough commands.

# Use cargo xtask run-gui --driver for live manual observations using installed config.
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
GUI 交互通过 `cargo xtask manual-gui` 的隔离模拟服务人工验收；真实供应商人工观察
直接使用用户配置运行 `cargo xtask run-gui --driver`，不作为自动测试通过的证明。

The default app path initializes the native FRB runtime and subscribes only to the selected session stream. `DemoStudioApi` is selected only by an explicit demo build flag or a test override; native runtime failures are surfaced instead of switching implementations.

## 账号组件预览

账号组件的官方预览分为三组入口：

- `previews/accounts_previews.dart` 展示账号整页与状态场景。
- `previews/account_template_previews.dart` 展示 8 个 Native 模板及 Antigravity 的
  List、Details、Editor 状态。
- `previews/account_component_previews.dart` 按生产职责分组提供 53 个组件预览入口，直接实例化生产组件，
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
完整工作区和时间线仍使用原生 demo/Driver 观察。Native 模型声明使用同一套结构化手动模型
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
这些仍需通过 `cargo xtask manual-gui` 和真实 Driver 验收，PR 产品截图也应来自原生程序。
截图和诊断日志写入当前会话产物目录，不放入源码或预览缓存的 Git 提交。

官方参考：[Widget Previewer](https://docs.flutter.dev/tools/widget-previewer)、
[依赖覆盖与 pubspec_overrides.yaml](https://dart.dev/tools/pub/dependencies#pubspec_overridesyaml)。
