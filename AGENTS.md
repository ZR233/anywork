# 糊来帮 Agent 协作规范

本文件是本仓库面向 Codex、Claude 和其他 AI agent 的唯一项目级协作规范。与用户交流、计划、总结和 PR 描述默认使用中文。命令、路径、代码标识符和正式技术名称保留原文；通用质量方法通过下文技能入口按需读取。

## 协作与变更原则

- 将“帮我”“修复”“实现”等明确行动请求视为执行授权；在用户指定范围内连续完成必要的读取、修改、相关文档同步、验证和失败修复，不在步骤之间反复询问是否继续。已有授权持续有效，常规实现选择按现有约定自行处理。
- 先从会话、代码和文档核实缺失信息；只有无法推断且会改变业务语义、交付目标或授权范围的信息才询问。明确指出缺什么及影响，等待期间可完成不依赖答案的已授权工作，不猜测关键业务决策。
- 与用户讨论需求或方案时（包括任务模式规划），任何已有文档、规约、技能约定和项目记忆，包括本文件，都只是待核实、可质疑的材料，不因“权威”或“唯一来源”的称谓假定其全部正确，也不以旧约定直接否定新需求。代码反映当前实现，不自动证明设计合理；发现不合理、过时或冲突之处，说明事实、原约定、用户目标与修改建议及影响。质疑不等于擅自实施，实际权限、安全限制与审批仍须遵守。
- 面向用户的交流默认用户没有读过任何项目代码；涉及概念先说明含义、作用及相互关系，再解释现状、问题和取舍。路径、符号与文档引用只作证据，不能代替完整的因果说明；解释深度与问题相称，不用术语堆砌代替清晰表达。
- 只读审查不隐含修改授权；本地修改不自动授权提交、推送、合并或部署。用户要求“修复并提 PR”时，可连续完成修改、验证、提交、推送和创建 PR；未授权的外部写入或用户数据删除等破坏性操作须先完成可独立准备的工作，再就具体动作询问，并遵守实际工具权限限制。
- 用户明确指令优先于本文件和技能中的工作流建议；技能补充领域要求，不重复设置审批步骤。组件与依赖路线按下述自研决策门槛执行，技能不得绕过或弱化该门槛。若规则确实阻塞任务，引用具体文件与条款并说明原因，区分明确要求和自身推断。
- 不回滚用户或其他 agent 的未提交改动；同一文件存在相关改动时，先读懂再叠加。
- 架构、接口、协议、运行时行为和长期约定的文档与实现保持一致；旧文档不撤销用户已明确的新需求，用户限定范围外的工作仍是未授权范围。设计文档写作规则见 [设计索引](design/README.md)。
- 新增用户配置文件或配置项，以及修改配置格式、版本、字段、默认值、存放路径、作用域优先级或保存／重载方式时，必须在同一提交同步更新内置 [studio-config](code/pl-studio-runtime/assets/skills/studio-config/SKILL.md) 的对应说明与示例。按当前代码的解析、校验和实际生效行为核对；技能只保留当前支持的格式，删除失效描述，不追加历史版本流水账。架构与迁移背景留在设计文档，技能负责可直接操作的路径、格式和验证指南。
- 提 PR 或创建分支时，优先推送到用户账号 fork，并优先向 fork 源仓库的默认分支提 PR。

## 组件与依赖选型

- 实施或规划任务时，应优先复用 Rust、Flutter/Dart、目标平台提供的官方组件、标准库和项目现有抽象；官方能力不足时，再评估维护活跃、文档完整、目标平台与许可证可核验的成熟第三方组件，避免重复造轮子。成熟度不能只由下载量判断。
- 选用组件前，必须查阅其官方文档、最佳实践和 API 契约，核对版本、生命周期、错误处理、异步/并发语义、目标平台和集成边界；同时检查工作区已有依赖与可复用能力，避免引入第二套事实源。
- 不得在上层重复实现组件已有能力，也不得无理由增加包装层、兜底逻辑、shim 或兼容分支；只有承载项目领域语义或必要边界适配时才保留薄适配层，并让底层组件的错误和限制保持可见。
- 若现有官方或成熟第三方方案都不能满足需求，应先调研自研范围、成本、维护风险和兼容影响，将候选方案、来源、排除理由与取舍记录在计划或交付总结中，并向用户询问是否选择自研；在用户明确选择前，不开始自研实现。等待决定期间可继续进行不改变生产实现的只读调研。
- 本节是组件路线的特殊决策门槛。质量技能和领域 Skill 只能补充检查，不能以“无需逐项审批”、默认 fallback 或自定义平行实现绕过该门槛。

## 架构演进与数据迁移

- 修改前理解当前架构、所有权和完整调用链，优先复用已有逻辑与抽象，沿用领域命名和测试方式，避免建立平行实现或第二份事实源。
- 区分原始业务事实、可重建产品读模型和局部 UI 状态。产品投影可在原 owner/writer 中维护派生索引，但不得反向改写原事实；客户端不重复领域分组，折叠/滚动不进入业务摘要。具体时间线契约见 [时间线内容源](design/26-timeline-content.md)。
- 当前架构无法合理满足需求时，允许在任务范围及必要相邻边界进行破坏性调整。以职责清晰、事实源统一和长期可维护为优先，不为最小差异或保留旧接口牺牲架构，也不借此扩大为无关重构。
- 架构调整须同步迁移受影响调用方、协议映射、测试与文档；完成后删除旧实现、旧接口、转发别名及兼容分支，只保留最新架构与逻辑。仓库外消费者通过版本变更说明指引升级，不在项目内保留旧接口。
- anywork 仅支持 v2 会话、历史、调用统计及产品库迁入无版本号的当前 `data/` 布局；v2 前数据原样隔离，不导入、不激活。账号等非会话配置与凭据关联仍须安全迁移。旧结构只在明确迁移边界解码，正常运行只消费当前结构，不保留旧路径回退；现役外部协议适配和平台支持不属于应删除的兼容层。
- 数据库、统一 Workspace 归属与会话临时目录归档清理遵循 [存储契约](design/17-studio-storage.md)，配置与凭据关联迁移遵循 [配置契约](design/20-config.md)。后续持久化变化仍须迁移并验证，不能以备份后清空或恢复默认值代替；目录整理不授权删除用户原件或迁移备份。用户技能只读标准用户主目录 `.agents/skills/`，不创建产品私有用户技能目录。
- 破坏性代码或接口调整不授权删除用户数据，也不扩大提交、推送、发布或部署权限；相关授权统一遵循前节。

## Git 提交与 PR

- commit subject 和 PR 标题必须使用 Conventional Commit：`<type>(<scope>): <description>`。
- `type` 仅使用 `build`、`chore`、`ci`、`docs`、`feat`、`fix`、`perf`、`refactor`、`revert`、`test`。
- `scope` 可省略，但优先使用稳定范围，如 `studio`、`agent-runtime`、`release`。
- 中文描述可以使用，但必须保留英文冒号，例如 `fix(studio): 修复项目清理确认无效`。
- 用户可见缺陷优先使用 `fix`，新能力优先使用 `feat`；破坏性变更使用 `!` 或 `BREAKING CHANGE` footer。
- squash 合并前同时检查 PR 标题和实际 commit subject，确保最终提交可被 Release Please 解析。

### PR 截图证据与附件

- 使用截图作为 PR 证据时，正文中的图片应来自本次相关运行，并说明场景、平台及实际覆盖范围；可以提供同窗口尺寸的前后对照。截图不是每次修改的必备产物，不为凑截图运行无关 GUI 或测试。
- 截图必须通过 GitHub 附件等已授权渠道上传，不能只放本地路径、文字日志或 PR 评论来替代正文中的图片；不得用示意图、生成图或其他版本的截图冒充本次验证。上传前检查并遮蔽凭据、个人信息等敏感内容，必要遮蔽须说明，不能改动验证结果。
- 截图、预览文件和上传中间产物遵循下文“会话文件与交付位置”，不得放入源码、Git 提交或长期 Skill 资产；已有工具的固定产物入口保持不变。提交前检查暂存区与 PR 差异，不为隐藏截图修改仓库或全局忽略规则。

#### 使用 GitHub CLI 添加附件

`gh --version`、`gh pr create --help` 和 `gh pr edit --help` 可用于核对当前版本的 `--attach` 能力与行为，不凭旧版本经验断言 CLI 无法上传。以下示例在本会话 `artifacts` 目录执行；`OWNER/REPO`、`BASE`、`BRANCH`、`PR_NUMBER`、标题与文件名均替换为实际值。

```sh
# 创建 PR，同时上传截图；重复 --attach 可添加多张图片。
gh pr create --repo OWNER/REPO --base BASE --head BRANCH --title "fix(studio): 描述本次改动" --body-file pr-body.md --attach "./after.png#改动后"

# 给已有 PR 追加截图；不传正文参数时保留原正文。
gh pr edit PR_NUMBER --repo OWNER/REPO --attach "./after.png#改动后"

# 上传后回读实际正文，确认图片引用已替换为附件 URL。
gh pr view PR_NUMBER --repo OWNER/REPO --json body --jq .body
```

- 需要指定图片位置时，在 `pr-body.md` 中写入 `![改动后](./after.png)`，并通过 `--attach` 上传同一文件；CLI 会把对应本地引用改为上传后的附件 URL，保留正文中的替代文本。未在正文引用的附件会追加到正文末尾；`#改动后` 是附件未被正文引用时的图片替代文本，不是文件名的一部分。
- `--body-file` 内的相对图片路径优先相对于正文文件所在目录解析，再回退到命令工作目录；`--attach` 的相对文件路径相对于命令工作目录。不要把本机绝对路径或尚未上传的相对路径当作可交付图片链接。
- 更新已有 PR 的正文前，先读取最新远端正文，保留其已有修改和附件 URL，再使用 `--body-file` 提交；不要用上传前还带本地图片路径的旧正文覆盖已上传版本。
- 部分附件上传失败时，PR 仍可能已创建或更新，CLI 会输出 PR URL 并以非零状态退出。先核对该 PR 和已成功附件，再对缺失部分用 `gh pr edit --attach` 补传，不因退出码非零直接重复创建 PR。
- 若当前 CLI 不支持附件，按环境权限升级到支持版本，或在 GitHub 网页 PR 正文编辑器中拖拽、粘贴、选择图片上传并保存。额外图床、图片仓库或 Release 需要单独授权，不以提交图片到源码或伪造附件 URL 绕过限制；无法上传时如实报告阻塞。
- 上传成功后，回读 PR 正文并打开或下载实际图片，确认可访问、内容与本次截图一致，且无遗漏或重复。仅命令退出成功不足以证明证据交付完成；截图也不能替代正文中的验证命令、结果与未覆盖项。

命令行为以当前 CLI 帮助及官方手册 [gh pr create](https://cli.github.com/manual/gh_pr_create)、[gh pr edit](https://cli.github.com/manual/gh_pr_edit) 为准。

### Studio 发版决策

- 版本计算、提交分类与发布机制见 [发布与更新](design/23-release-update.md#231-版本与发布流)，本文件不重复维护政策。
- major 只能在维护者明确决定后，用最终落入 `main` 的提交正文 `Release-As: x.y.z`
  指定目标稳定版本。例如 subject 为 `chore(studio): release 7.0.0`，正文为
  `Release-As: 7.0.0`；这只是操作示例，不授权 agent 自行提交或选择大版本。
- `Release-As` 由最终提交正文消费，仅修改 PR 标题或描述不会改变发布版本。版本文件由 Release Please 管理，不手改版本文件、覆盖 tag 或在配置中长期保留 `release-as`。提交和提 PR 不包含发布授权。

## 项目目录与命令入口

### 基本目录

- 仓库 Python 脚本统一用 `python3` 运行；系统 `python` 是 Python 2。
- Rust crate 名称统一以 `pl-` 开头，例如 `pl-core`、`pl-model`、`pl-studio-bridge`。
- Flutter app 的 Dart package 名称是 `anywork`。
- Flutter 项目根目录是 `code/anywork`。
- 开发用组件预览独立位于 `code/anywork_previews`，只持有 `@Preview` 入口和合成数据，引用应用的生产组件；应用仅通过 dev dependency 在测试中复用它。
- SDK-only Dart Client 位于 `code/anywork_client`，无 Flutter/Riverpod/FRB 依赖；本地 Client 命令通过 `cargo xtask verify-client` 在正确目录执行。CI 的无 Rust 前端验证可在该 package 目录直接使用官方 Dart SDK 命令，保留锁文件、SDK-only 边界与测试发现检查。
- Client、AppGraph 与观察层的所有权和依赖边界见 [客户端与前端状态](design/25-frontend-state.md)。

### 会话文件与交付位置

- 临时脚本、中间文件和一次性探针使用最新宿主 `studio.session-files` 事实给出的本会话 `scratch/`，待交付产物使用其 `artifacts/`；路径属于当前实际 workspace，SSH 场景属于远端，不能从本地 home、进程 cwd 或旧会话推导。完整布局与保留边界见 [存储契约](design/17-studio-storage.md)。
- 正式代码、项目文档和用户明确指定的交付物仍写目标项目位置；非项目产物须报告真实路径。工程工具有明确输出入口（如 xtask 的 `target/manual-gui/`）时遵循该入口，不擅改工具的产物布局。
- 宿主内部会话数据库、归属清单、可靠资源与传输暂存不供模型手工维护；不要将 helper 资产目录、系统 Skill 安装目录或其他 Thread 的临时目录当作可写工作区。directory 的自身临时目录许可不扩大业务 `writablePaths`，也不放宽只读或 confined 边界。
- 一次性截图、日志与脚本不提交到源码或 Skill 支持目录；确需沉淀时只保留泛化知识。运行池自带忽略文件，已有用户忽略规则不覆盖；不要为隐藏运行产物改全局 Git 配置或清理未知文件。

### Flutter 与 Dart 命令

- 禁止在 Flutter 或 Dart SDK 安装目录执行本项目的 `flutter`、`dart` 命令。应用命令的工作目录是 `code/anywork`，独立组件预览命令的项目根是 `code/anywork_previews`；纯 Client 命令由 `verify-client` 切换到 `code/anywork_client`。不得在 SDK 目录执行项目命令。
- 从仓库根目录执行 Flutter/Dart 命令时，优先使用 `cargo flutter <args...>` 和 `cargo dart <args...>`；参数原样透传，包装命令会自动切换到 `code/anywork`。
- 应用命令优先使用包装；需要直接运行时，先进入 `code/anywork`。组件预览依赖准备后可在 `code/anywork_previews` 直接使用官方 Flutter CLI，参数、输入输出和热更新由 Flutter 管理；不得把 SDK 目录当作项目目录。
- CI 的 Linux 前端作业为避免引入 Cargo/FRB，可在 `code/anywork` 直接运行官方 Flutter/Dart 静态检查和无 bridge 测试，在 `code/anywork_client` 执行 SDK-only Client 检查；依赖安装使用 `--enforce-lockfile`，不绕过 Client/UI 边界或另行生成源码。该例外不放宽原生 GUI 构建入口。
- Linux CI（包括前端）统一消费同次解析、校验的项目 Docker 构建镜像。系统开发依赖在 `docker/linux/Dockerfile` 维护并由镜像 smoke 验证，消费作业不执行 `apt-get` 补装；与本次源码绑定的 helper 仍在作业内构建。
- 常用命令：

  ```powershell
  cargo flutter analyze
  cargo dart format lib test tool integration_test
  ```

### 官方 Flutter / Dart 技能与快速迭代

- 通用 Flutter / Dart 技能从用户级 `~/.agents/skills/` 发现，官方来源为 `flutter/agent-plugins` 和 `dart-lang/skills`；项目不复制或维护这些技能。缺少时读取对应官方文档，安装或更新按用户授权进行。本仓库技能只补充项目架构、构建和验收约定。
- 组件预览、布局诊断、响应式布局和测试编写分别优先使用官方 `flutter-add-widget-preview`、`flutter-fix-layout-issues`、`flutter-build-responsive-layout`、`flutter-add-widget-test`、`flutter-add-integration-test`；Dart 通用任务按已发现的 `dart-*` 技能选择。跨层所有权仍由 `flutter-frb-rust-design` 约束，测试必要性由 `test-quality` 判断。
- 上游技能中的 CLI 示例映射到本项目入口：应用命令使用 `cargo flutter` / `cargo dart`，纯 Client 使用 `verify-client`，生成使用 `generate-gui`，原生启动使用 `run-gui`，桌面测试使用 `test-project`。保留 Riverpod、typed GoRouter、Client/FRB 和既有生成模型；通用示例不要求换状态库、手改锁文件或绑定、增加依赖、开启实验语法或全仓应用自动修复。
- 人工实验统一按 `flutter-studio-build` 的[实验指南](.agents/skills/flutter-studio-build/references/experiments.md)操作。纯界面开发、局部交互和截图默认使用 `cargo xtask preview-gui --headless --no-devtools`，**不编译 Rust bridge**，不启动模型服务；可重复断言用相关 `test/ui`。只有持久化、模型调用或原生资源才选择隔离原生应用及官方 Dart MCP，不把全部层级排成必跑清单。
- `preview-gui` 只准备预览包及 scaffold 的 Pub 依赖，再透传参数和终端输入输出给官方 `widget-preview start`；发现、浏览器及热更新均由 Flutter 管理。预览包使用自己的标准 Pub 配置，不能把整个应用作为预览扫描根；不复制 UI、不手改 SDK 或缓存 manifest。依赖已准备后也可在 `code/anywork_previews` 直接使用官方 Flutter 命令；具体适配与故障恢复见构建技能。
- Dart MCP 使用官方 `dart mcp-server`，项目 roots 按当前工作区注册。MCP 的 stdio 启动直接使用实际 Dart SDK 可执行文件，不能套用会向 stdout 打印日志的 Cargo 包装；项目工作命令仍遵循上面的入口。先读取实际工具 schema，再连接 xtask 启动的应用，不用 MCP `launch_app` 绕过 bridge/helper 准备。
- Dart 界面修改复用当前载体的官方热更新并检查画面和错误；预览不因截图转为原生构建。原生 `run-gui --inspect` 支持 MCP 热重载，`--native-launch` / release 不作为热重载入口；Rust/FRB/原生变化才构建并完整重开。宿主与容器不要同时改写同一 checkout 的 Pub/生成缓存，切换前结束原运行或使用独立 checkout。

### 桌面 GUI

- GUI 构建和运行必须从仓库根目录通过 xtask（按当前 OS 选择目标平台：Windows / Linux / macOS）：

  ```powershell
  cargo xtask run-gui [--demo] [--capture] [--inspect]
  cargo xtask run-gui --release
  cargo xtask build-gui [--debug] [--demo] [--no-clean] [--check-generated]
  cargo xtask test-project --suite desktop|native [--set smoke|full]
  ```

- `build-gui` 基于已提交的 `Cargo.lock` 与 `code/anywork/pubspec.lock` 确定性构建。它允许同步缺失的远程包，但 Flutter 使用 `pub get --enforce-lockfile`，Cargo 使用 `--locked`，不会更新 lockfile 或重新解析版本；`cargo xtask`、`cargo flutter` 和 `cargo dart` 包装命令本身也使用 `--locked`。依赖升级必须手动运行对应的依赖更新命令并审查提交新的 lockfile。
- `build-gui` 默认构建 release 并收集到 `dist/anywork-release`；`--debug` 同时选择 Flutter 与 Rust bridge 的 debug 配置，只保留 Flutter 原始 build 输出，用于日常平台编译检查，不作为发布输入。RC 与稳定发布继续使用默认 release 构建。
- CI 可直接执行同次源码预编译并已核验摘要、平台/环境与编译工作区身份的 xtask，继续使用其原生构建、生成与测试子命令；缺失或身份错误必须失败，不以重新编译或旧缓存掩盖交接失败。普通本地命令仍使用上述 Cargo 入口。
- Windows 稳定发布先用 `cargo xtask build-gui` 生成 bundle，再用 `release-gui stage --version <x.y.z> --bundle <路径>` 显式打包已校验的预构建输入；`stage` 不再隐式编译。CI 下游直接执行同次构建归档且已核验身份的发布工具，不重新编译工具。仅重跑失败或指定的下游作业可复用该次 run 的构件；完整重跑与过期构件不属于断点续跑保证，见 [发布与更新](design/23-release-update.md#231-版本与发布流)。

- 不支持直接执行 `flutter build windows|linux|macos` 或 `flutter run -d windows|linux|macos`，也不新增 PowerShell GUI wrapper。
- `run-gui --release` 直接启动已有 `dist/anywork-release` 原生程序，不执行构建或依赖解析；缺失时提示先执行 `build-gui`。它与 `--demo`、`--capture`、`--inspect`、`--profile` 互斥，并沿用平台进程树管理。
- macOS 使用完整 Xcode 与 Flutter 官方 Swift Package Manager 集成，构建当前宿主架构的 `.app`；Rust bridge 由 xtask 预构建后放入 `Contents/Frameworks/`，SSH helper 放入 `Contents/Resources/data/remote-helper/`。构建收集保留 framework 符号链接，`run-gui --release` 启动 `dist/anywork-release/anywork.app/Contents/MacOS/anywork`。本地使用 ad-hoc 签名，不包含 Developer ID、公证或稳定发布授权。
- Linux 原生 GUI 需要 Clang/C++ 标准库、CMake、Ninja、pkg-config 与 GTK 3 开发文件，由项目 Docker 镜像提供。宿主原生运行时，xtask 仍须用当前 PATH 和真实最小 GTK/C++ 工程预检，缺失时透传实际命令与原始错误；不得写死编译器版本、系统库路径或注入机器专用 include/library 环境。Rust 桥以 `libpl_studio_bridge.so` 预构建并经 `ANYWORK_BRIDGE_LIBRARY` 环境变量注入 CMake，与 Windows 的 DLL 契约一致。
- `cargo xtask test-project --suite desktop` 复用 bridge/helper 构建与进程树管理，运行官方桌面 `integration_test`；与 demo、capture、profile/native-launch 和 release 模式互斥。测试用 `WidgetTester` 操作真实生产组件。`wait_events` 的隔离 provider 由 `manual-gui --preset wait-events` 持有；`conversation_read_work` 的关闭 SQLite 预置由 `--preset conversation-read-work` 持有。`test-project` 在对应环境变量未齐时调用这些 preset。
- `cargo xtask test-project --suite native` 在进程外裁判真实退出码、重开和第二实例；薄故障装配是 `tool/native_fault_main.dart`。
- 人工截图使用 Widget Previewer/成熟浏览器工具或原生官方 Dart MCP；自定义内容捕获只保留自动化及原生测量的内部职责，不作为平行人工入口。
- 原生 MCP 观察使用独立 debug Driver 入口；隔离模拟环境用 `cargo xtask manual-gui --preset gui --inspect`，复用已有 native launcher 和真实退出报告，不改变正式入口或 `integration_test` binding。Linux 无桌面时由系统 `xvfb-run` 提供显示，不需要伪终端；管道 stdin 的 `done` 请求退出后须等待并校验真实退出与后代回收，不重复录入 UI 动作。验收载体不提供 resident 热重载；确需跨层开发热重载才用普通 `run-gui --inspect`，其工具退出码不能代证产品正常退出。
- UI 自动化在 `code/anywork` 执行 `flutter test --no-pub test/ui`，不加 `-d`，不准备 Rust/bridge。
- 无显示环境的 widget 测试仍会运行依赖包的官方 native-assets hooks。当前 `cnativeapi` 在 Linux 需要 C++ 编译器、pkg-config 以及 GTK 3 / X11 / Xi 开发文件；缺少时按 hook 原始错误补齐宿主依赖，不禁用 hooks 或用额外 UI 实现代替。
- `cargo xtask manual-gui` 启动隔离的原生 Studio 和本地模拟供应商，持有环境、请求及日志供观察；场景参数是 `--preset`，截图和操作遵循统一实验指南。真实供应商观察须有具体授权，读取已有配置，不修改凭据。
  此命令仅按需编译并调用独立的 `pl-studio-acceptance`，参数由验收工具解析；普通 xtask、
  Flutter/Dart 包装命令不链接该工具及其 Studio/数据库依赖。全 workspace 检查仍覆盖验收工具。
- 本地原生验收默认使用当前受支持宿主平台，报告中明确平台与覆盖范围，不把单平台结果外推为跨平台通过；跨平台任务按实际影响说明其他平台的验证结果或缺口。
- `run-gui --demo` 不作为人工实验的默认入口，也不能证明真实 bridge、持久化或 provider 行为。纯界面使用官方预览，业务使用隔离真实产品；人工结论独立记录，默认为待评审。
- `test-project` 与 `manual-gui` 在正常完成、失败或取消后都必须等待并回收所属 Flutter、GUI 及其子进程，不得残留；Windows 使用 Job Object 管理进程树，Linux 使用项目的进程树生命周期机制；macOS 使用现有 `process-wrap` 的 Unix 进程组管理，正常退出报告若发现必须由 harness 强制回收的残留组则明确失败，不将其报告为应用已自行收束。显式阻塞隔离层并触发应用强制退出的故障场景按统一执行器契约记录后代及裁判介入，不把该阶段的裁判回收列为产品保证。
- AI 运行时观察优先通过官方 Dart/Flutter MCP / Inspector 操作 Flutter 层，重复功能验证使用 `WidgetTester` / `integration_test`。Windows、Linux 共用这些接口；Linux 没有显示服务时用 Xvfb 提供原生启动环境，Windows 原生验证仍需可运行桌面应用的会话。平台窗口、IME、托盘等边界按需使用真实键盘/指针或系统工具；不把 Flutter 层截图外推为系统行为验证。专用工具可覆盖时不使用 Computer Use。截图来源与覆盖边界见 [测试与人工验收](design/24-testing.md#2413-时间线呈现与官方集成测试)。

### GUI 生成文件

- Riverpod、Freezed、l10n 和 FRB 文件属于生成边界，只能从仓库根目录统一生成：

  ```powershell
  cargo xtask generate-gui
  ```

- 不得手工修改生成文件，也不得直接调用单个生成器。
- `cargo xtask check-gui-generated` 会重新生成并检查 canonical 输出；它不是只读命令。已授权的代码修改或生成一致性验证包含必要生成操作，但用户明确限定只读时，不能运行会改写跟踪文件的命令。
- 普通 `run-gui` 和 `build-gui` 只消费当前源码，不运行生成器或可写格式化；更新生成物使用 `cargo xtask generate-gui`，生成输入与产物保持一致。
- `check-gui-generated`、`verify-gui` 和 `build-gui --check-generated` 均包含生成检查，可以按目标选择，不是需要依次执行的清单。稳定发布与 RC 构建、预构建打包的行为见 [发布与更新](design/23-release-update.md)。
- Git 索引与普通源码统一使用 LF；PowerShell、RC 和 Inno Setup 文件使用 CRLF，`.gitattributes` 与 `.editorconfig` 必须保持一致。不得通过全局 Git 配置、构建后索引刷新或全仓 renormalize 修复行尾。

### 预置系统技能

- `pl-studio-runtime` 的上游预置技能直接存放在 `code/pl-studio-runtime/assets/skills/<name>/`：`canvas-design`、`frontend-design` 来自 anthropics/skills；Office 领域仅使用 DeepSeek Harness 的七项独立 `office` / `office-*` 技能，不混入其他文档技能来源。
- 更新时通过工具读取固定上游提交及许可证，手动拷贝所需文件，按 `SKILL.md` 和 `references/`、`templates/`、`scripts/`、`assets/` 标准布局整理；下载副本放本会话 scratch。不得新增自动同步命令、子模块、外部仓库 checkout 或构建期下载。
- 各技能基础约定独立完整，减少互相引用；支持文件位于本技能目录内。正文不写死工具函数调用、宿主物理路径或特定运行时的动态注入协议，遵循当前会话实际提供的发现与执行规则。
- 内置技能按标准资产目录与 frontmatter 动态发现和校验，不维护技能名称或数量白名单；拷贝后核对名称、描述、引用、安全边界与源文件语义，并执行适用检查。
- 源码库是 canonical 内容。每次更新须同步 `code/pl-studio-runtime/THIRD_PARTY_NOTICES.md` 中的固定 revision、来源路径、许可与本地适配说明，并保留随资源分发的版权和许可证。上游许可必须允许再分发；anthropics/skills 的 `pdf`/`docx`/`pptx`/`xlsx` 为禁止再分发的专有许可，不得预置。

## 工程边界

### 质量技能入口

通用设计、实现与测试规则由以下技能维护，本文件只规定项目约束。按任务语义选择，不以文件名或改动规模代替判断；多个边界同时涉及时组合使用，不把普通改动扩展为无关专项审计。

新增或修改内容涉及 Flutter／FRB／Rust 的跨层分工、状态与资源所有权、数据交付或页面路由时，必须先加载并使用 `flutter-frb-rust-design` 技能。

| 任务语义 | 技能 |
| --- | --- |
| Rust 实现、错误传播、重构与审查 | `rust-code-quality` |
| 公共接口、类型、错误、模块、依赖与协议 | `rust-api-design` |
| 同步、异步取消、回调与资源生命周期 | `rust-concurrency-safety` |
| unsafe、FFI、外部句柄与安全证明 | `rust-unsafe-safety` |
| 测试设计、回归、层级、必要性与去重 | `test-quality` |

质量技能以 TGOSKits `4713bfc98f` 为迁移基线，经泛化后在本仓库独立维护；运行任务时不依赖源仓库。命令、授权与项目架构以本文件为准；技能负责相应方法与证明，不复制另一套审批或门禁。

### Rust 异步接口约定

- 禁止使用 `#[async_trait]` 和 `#[allow(async_fn_in_trait)]`；仅实现 `sea_orm_migration` 的 `MigrationTrait`、`MigratorTrait`、`MigratorTraitSelf` 时允许使用其官方 `async_trait` 宏，以遵循第三方接口契约。
- 异步 trait 使用原生 RPITIT，在返回 future 上显式声明 `Send`；不通过宏隐藏生命周期或线程安全约束。

### 核心 crate

crate 职责、依赖方向与禁止依赖的唯一权威源是 [Crate 边界](design/02-crates.md)。修改前按该边界确认契约所有者；需要调整边界时遵循前文架构演进规则。

### 前端工程边界

- 线协议命名与基础类型见 [通用约定](design/05-conventions.md)，客户端契约见 [客户端与前端状态](design/25-frontend-state.md)。
- 前端测试、浏览器验证和临时 dev server 不得占用 `1420` 端口，该端口保留给用户脚本。

## 检查与观察入口

- 下列命令是可选入口，不是每次修改、提交或交付的必跑清单；本文件不规定测试目录或类型白名单，也不另设开发、审查或返修流程。可按任务目标和实际影响选择验证，通用方法使用 `test-quality` 技能，基础设施和证据含义见 [测试与人工验收](design/24-testing.md)。
- 验证报告区分实际执行、有效复用、失败和未验证；排队、运行中、零用例、采集完成或模型自述都不能冒充通过。环境或权限阻塞保留原始错误，不伪报完成。
- `code/anywork/pubspec.lock` 是必须纳入 Git 的 canonical 应用依赖快照，不得加入 ignore；
  Flutter 直接依赖升级后必须同步提交重新解析的 lockfile。
- 常用入口（`PUB_HOSTED_URL` 及镜像行为由 Flutter/Dart 自身处理，xtask 不改写已跟踪的 `pubspec.lock`）：

  ```powershell
  cargo fmt --all --check
  cargo clippy --workspace --all-targets -- -D warnings
  cargo test --locked --workspace --features pl-core/sqlite
  cargo xtask verify-client
  cargo xtask verify-gui
  cargo xtask test-project --suite desktop --set smoke
  ```

- 本地命令、MCP、LSP 与 ACP 通过 `pl-remote-helper` library 的 native Executor 创建业务进程，不要求 PATH 中存在监督 worker。SSH 使用与源码匹配的前台 `pl-remote-helper --stdio` server；桌面 xtask 将远端 server 资产作为 Flutter bundle 资源分发，不嵌入 bridge，不使用其他传输后备路径。

- 不默认启用 `--all-features`。性能与真实外部服务观察按明确目标和授权显式选择，不将费用、凭据或机器敏感采样带入普通检查；不保留专项实验 example、永久截图脚本或第二套业务运行时。
- 真实模型与 GUI 观察遵循统一实验方法，按边界选择载体；模拟通过不等于真实供应商兼容，人工结论独立记录，默认为待评审。
- CI 的触发条件与作业以 [PR Quality Gate](.github/workflows/pr-quality.yml) 为准；它描述远端实际检查，不构成本地重复执行要求。GUI 人工观察与 live 模型观察是独立入口，模拟、单平台和真实供应商结果各有覆盖边界。
- `cargo doc --workspace --all-features --no-deps` 为按需检查项，CI 不执行。

- Flutter、Dart、GUI 和生成文件检查统一使用前文定义的项目命令入口；验收时结合 widget tree、窗口截图和日志判断结果。
- `git diff --check` 可检查差异空白问题，不能代替内容、行为或权限范围的判断。
