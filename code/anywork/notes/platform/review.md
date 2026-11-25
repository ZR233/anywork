# 基础边界组质量审查

下列逐文件检查列保留初审时的实际观察与未覆盖边界；后续统一生成、整合测试和官方预览以[总台账](../flutter-quality-audit.md)的验证表为准，不把初审“未运行”当作最终状态，也不把整套通过外推为每项平台行为已验。

## 范围与结论

审查基线：`3db5e10d03db6a13bcc44b37d37555bcaf80e2c7`（本工作区 HEAD；分支 `refactor/flutter-quality-cleanup`）。按基线枚举、排除 `.g.dart`、`.freezed.dart`、生成 l10n 与 Rust/FRB 生成输出后，本组 56 个手写文件：M01 15、M02 3、M03 3（`studio_l10n.dart` 与两份只读 ARB）、M08 31、B02 4。逐文件台账见下表。

本轮没有找到能在不改变架构、路由契约、平台能力或生命周期语义前提下安全删除/合并的生产实现；因此没有为产生代码 diff 而制造改动。生命周期的取消与 join、共享关闭 Future、平台 stub、资源释放和调试/验收入口都有实际职责或调用链证据。没有确认需由父代理修复的 ARB 文案问题。生产改动为 0；本文件是本组唯一新增文件。

## 逐文件台账

“检查与处理”记录逐文件阅读后的结论；同一族的实现与平台分支按其真实边界分别列出，不以文件名中的 `legacy`、`compat` 等词作为删除理由。

### M01：入口、应用装配、生命周期、路由与主题（15）

| 文件 | 检查与处理 |
| --- | --- |
| `lib/main.dart` | 应用启动入口；串接 Flutter binding、启动宿主与应用装配。保留，入口有正式应用调用。 |
| `lib/src/app/anywork_app.dart` | 根应用 widget 与 router/theme 的组合点。保留，承担 Flutter 应用配置边界。 |
| `lib/src/app/app_composition.dart` | 建立应用依赖图并把宿主能力接入 UI。保留，不能与 widget 层的展示职责混并。 |
| `lib/src/app/app_graph.dart` | 持有应用级依赖和拥有者/provider 的组合。保留，属于唯一应用图装配位置；随意移除会改变资源所有权。 |
| `lib/src/app/frb_startup_host.dart` | 启动 Rust/FRB 侧宿主能力的适配入口。保留，正式启动依赖此跨层边界；生成绑定不在本次范围。 |
| `lib/src/app/routing/application_router.dart` | 构建 typed GoRouter 并注册路由。保留；LSP `createApplicationRouter` 引用查询命中 13 个文件，删除或改写会跨调用方改变路由契约。 |
| `lib/src/app/routing/app_route.dart` | 手写路由声明及 typed route 契约。保留；生成的 `app_route.g.dart` 排除，未手改。 |
| `lib/src/app/studio_host_lifecycle.dart` | 管理宿主启动/退出生命周期及其共享关闭过程。保留；取消/join 和幂等关闭关系不能按表面重复状态删减。 |
| `lib/src/app/studio_shutdown.dart` | 协调 Studio 关闭与资源收束。保留，关闭顺序与资源释放有语义；生成的 `studio_shutdown.g.dart` 排除。 |
| `lib/src/app/studio_startup_host.dart` | 启动宿主的统一适配和启动过程。保留，与 FRB 初始化及应用装配有明确边界。 |
| `lib/src/app/theme/material3_theme.dart` | 组装 Material 3 主题。保留，承担 Flutter ThemeData 映射。 |
| `lib/src/app/theme/siamese_scheme.dart` | 构造项目使用的配色方案。保留，为主题层提供具体颜色方案实现。 |
| `lib/src/app/theme/studio_semantic_colors.dart` | 定义语义颜色 token。保留，语义 token 与具体 scheme/Material 映射职责不同。 |
| `lib/src/app/theme/studio_tokens.dart` | 定义共享设计 token。保留，当前主题消费其统一值；未发现可移除的重复事实源。 |
| `lib/src/app/theme/studio_typography.dart` | 组装 Studio 字体样式。保留，主题配置的独立职责。 |

### M02：capture（3）

| 文件 | 检查与处理 |
| --- | --- |
| `lib/src/capture/capture_extension.dart` | 为 capture 暴露扩展/适配入口。保留，服务于内部自动化捕获调用。 |
| `lib/src/capture/capture_protocol.dart` | 定义 capture 输入输出协议。保留，CLI/应用端共享边界，不与界面实现重复。 |
| `lib/src/capture/flutter_content_capture.dart` | 捕获 Flutter 内容的实现。保留；LSP `captureFlutterContent` 引用查询命中 7 个调用、分布在 2 个文件，属于现役自动化能力。 |

### M03：本地化适配与只读文案源（3）

| 文件 | 检查与处理 |
| --- | --- |
| `lib/src/l10n/studio_l10n.dart` | Studio 本地化访问适配层。保留，实际承接生成 l10n 与应用用语边界；LSP diagnostics 无诊断。 |
| `lib/l10n/app_en.arb` | 只读审阅英文源文案，共 2461 条用户可见字符串值。未确认需修改的明确错误；本轮不改 ARB、不运行生成。 |
| `lib/l10n/app_zh.arb` | 只读审阅中文源文案，共 2461 条用户可见字符串值。未确认需修改的明确错误；本轮不改 ARB、不运行生成。 |

### M08：平台适配（31）

| 文件 | 检查与处理 |
| --- | --- |
| `lib/src/platform/clipboard_image_reader.dart` | 读取剪贴板图片的平台能力适配。保留，能力入口由平台决定。 |
| `lib/src/platform/desktop_drop_adapter.dart` | 将桌面拖放事件适配为应用输入。保留，事件适配不应与附件领域处理重复。 |
| `lib/src/platform/desktop_tray.dart` | 托盘 API/生命周期抽象。保留，隔离桌面能力边界。 |
| `lib/src/platform/desktop_tray_host.dart` | 托盘宿主及所有权承接。保留，生命周期由宿主集中管理。 |
| `lib/src/platform/desktop_tray_io.dart` | IO/桌面平台托盘实现。保留，提供真实平台行为。 |
| `lib/src/platform/desktop_tray_stub.dart` | 不支持平台的托盘实现。保留，构成条件导入的非 IO 分支，不能用空实现替代正式平台契约。 |
| `lib/src/platform/dropped_attachments.dart` | 将拖入内容整理为附件输入。保留，领域转换与平台事件读取职责不同。 |
| `lib/src/platform/dropped_file.dart` | 拖入文件的数据描述。保留，为平台入口和调用方共享的值类型。 |
| `lib/src/platform/error_log.dart` | 统一错误日志边界。保留，避免调用方直接依赖平台日志实现。 |
| `lib/src/platform/error_log_io.dart` | IO 平台错误日志实现。保留，承担可用平台能力。 |
| `lib/src/platform/error_log_stub.dart` | 非 IO 错误日志分支。保留，支持条件导入和非桌面目标。 |
| `lib/src/platform/external_url_launcher.dart` | 外部链接打开能力适配。保留，平台调用需要从 UI/领域逻辑隔离。 |
| `lib/src/platform/feishu_app_links.dart` | 飞书应用链接处理。保留，特定外部链接协议处理有实际产品语义。 |
| `lib/src/platform/file_picking.dart` | 文件选择平台入口。保留，调用方使用平台无关边界。 |
| `lib/src/platform/host_app_icons.dart` | 读取宿主应用图标的适配入口。保留，桌面宿主集成能力。 |
| `lib/src/platform/local_file_dialogs.dart` | 本地文件对话框能力封装。保留，操作系统 UI 属于平台边界。 |
| `lib/src/platform/studio_platform.dart` | Studio 通用平台能力抽象。保留，向上提供统一契约。 |
| `lib/src/platform/studio_platform_io.dart` | IO 平台能力实现。保留，承接系统/文件能力。 |
| `lib/src/platform/studio_platform_stub.dart` | 非 IO 平台分支。保留，和条件导入配对，不能仅因 stub 名称删除。 |
| `lib/src/platform/terminal_host.dart` | 终端宿主抽象。保留，平台能力与终端启动策略分层。 |
| `lib/src/platform/terminal_host_io.dart` | IO 平台终端宿主实现。保留，管理实际宿主交互资源。 |
| `lib/src/platform/terminal_host_stub.dart` | 非 IO 终端宿主分支。保留，维持平台契约并明确能力边界。 |
| `lib/src/platform/terminal_launcher.dart` | 解析并启动终端的产品逻辑入口。保留，需与 host 实现配合；已检查启动及失败路径。 |
| `lib/src/platform/vscode_host.dart` | VS Code 宿主抽象。保留，编辑器集成的公共边界。 |
| `lib/src/platform/vscode_host_io.dart` | VS Code IO 宿主实现。保留，处理真实宿主能力。 |
| `lib/src/platform/vscode_host_stub.dart` | VS Code 非 IO 分支。保留，平台能力差异由显式分支表达。 |
| `lib/src/platform/vscode_launcher.dart` | VS Code 启动策略。保留，属于仍支持的编辑器适配。 |
| `lib/src/platform/zed_host.dart` | Zed 宿主抽象。保留，编辑器集成的公共边界。 |
| `lib/src/platform/zed_host_io.dart` | Zed IO 宿主实现。保留，处理真实宿主能力。 |
| `lib/src/platform/zed_host_stub.dart` | Zed 非 IO 分支。保留，维持平台条件实现。 |
| `lib/src/platform/zed_launcher.dart` | Zed 启动策略。保留，属于仍支持的编辑器适配。 |

### B02：tool（4）

| 文件 | 检查与处理 |
| --- | --- |
| `tool/capture_ui.dart` | capture 自动化命令入口；调用 `code/pl-studio-acceptance/src/manual_gui.rs` 的 capture 命令。保留，属于现役验收入口，不是人工截图入口。 |
| `tool/inspect_main.dart` | 官方 Dart Driver 检查入口；由 xtask `run-gui --inspect` 使用。保留，承担 Inspector/Driver 集成。 |
| `tool/native_shutdown_main.dart` | 原生关闭验证入口；由 `manual_gui/shutdown.rs` 的 `run-gui --native-launch-target` 启动，xtask native 测试目标使用。保留，核验原生退出及进程树收束。 |
| `tool/profile_timeline_probe.dart` | 时间线原生测量探针；由 `manual_gui/conversation_read_work/profile.rs` 启动并回读报告。保留，具有自动化调用方。LSP diagnostics 无诊断；`isFreshObservation` 与 `requireFreshObservation` 还被 `test/unit/profile_timeline_probe_test.dart` 调用，测试不在本组写权限内。 |

## 实际检查与验证边界

- 文件范围从基线提交枚举，并排除生成路由/关闭代码、生成 l10n、Freezed 与 Rust/FRB 生成物；已阅读所有 56 个手写目标文件。长源码分段阅读；ARB 每个 locale 的 2461 条用户可见字符串值分段审阅。
- 在已有 ready Dart LSP 上执行语义查询：`createApplicationRouter` 有 13 个引用、位于 13 个文件；`captureFlutterContent` 有 7 个引用、位于 2 个文件。四个自动化入口沿 xtask、manual-gui 与 Rust 验收工具调用路径核对，详见 B02 台账。
- Dart LSP diagnostics 对 `main.dart`、`studio_host_lifecycle.dart`、`terminal_launcher.dart`、`studio_l10n.dart`、`profile_timeline_probe.dart` 均未报告诊断。查询期间初次 `textDocument/references` 曾超时；之后相关引用查询已成功。未把单次失败当作无引用证据。
- `test/ui/app_lifecycle_cleanup_test.dart` 与 `test/unit/platform_cleanup_test.dart` 在检查时不存在。因未确认有需改变行为的缺陷，本轮没有新增回归测试。
- 本轮按授权不运行格式化、完整 analyze/test、GUI、生成、pub/依赖或构建命令；没有 Dart 生产源改动，因此也没有生产文件需格式化或针对改动重跑 LSP。父代理统一执行整体验证。
- 仅当前 Linux workspace 可见；未执行 Linux/Windows/macOS 平台构建或运行，平台条件分支及真实系统对话框、托盘、编辑器和终端行为未做运行时验证。单平台静态检查不能外推为跨平台通过。

## 交付差异

- 新增：`code/anywork/notes/platform/review.md`。
- 生产代码、ARB、生成文件和测试均未修改；未执行 Git 写操作。工作区中其他代理的已有差异保留。
- 建议父代理后续最窄回归：针对若将来修改某一具体关闭/平台适配实现，再选择对应的授权生命周期或 platform cleanup 测试；本轮没有行为差异可据以要求新增或运行回归。完整验证仍由父代理按整体 diff 选择。
