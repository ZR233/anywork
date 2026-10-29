# 糊来帮 Agent 协作规范

本文件是本仓库面向 Codex、Claude 和其他 AI agent 的唯一项目级协作规范。与用户交流、计划、总结和 PR 描述默认使用中文。命令、路径、代码标识符和正式技术名称保留原文；通用质量方法通过下文技能入口按需读取。

## 协作与变更原则

- 将“帮我”“修复”“实现”等明确行动请求视为执行授权；在用户指定范围内连续完成必要的读取、修改、相关文档同步、验证和失败修复，不在步骤之间反复询问是否继续。已有授权持续有效，常规实现选择按现有约定自行处理。
- 先从会话、代码和文档核实缺失信息；只有无法推断且会改变业务语义、交付目标或授权范围的信息才询问。明确指出缺什么及影响，等待期间可完成不依赖答案的已授权工作，不猜测关键业务决策。
- 只读审查不隐含修改授权；本地修改不自动授权提交、推送、合并或部署。用户要求“修复并提 PR”时，可连续完成修改、验证、提交、推送和创建 PR；未授权的外部写入或用户数据删除等破坏性操作须先完成可独立准备的工作，再就具体动作询问，并遵守实际工具权限限制。
- 用户明确指令优先于本文件和技能中的工作流建议；技能补充领域要求，不重复设置审批步骤。组件与依赖路线按下述自研决策门槛执行，技能不得绕过或弱化该门槛。若规则确实阻塞任务，引用具体文件与条款并说明原因，区分明确要求和自身推断。
- 不回滚用户或其他 agent 的未提交改动；同一文件存在相关改动时，先读懂再叠加。
- 涉及架构、接口、协议、运行时行为或长期约定时，在已有授权范围内先同步对应设计，再修改实现并核对一致性，不因旧文档与已明确的新需求冲突重复索要授权。仅调整协作规则或技能时直接维护相应文件；用户限定范围外的工作列为缺口。设计文档写作规则见 [设计索引](design/README.md)。
- 提 PR 或创建分支时，优先推送到用户账号 fork，并优先向 fork 源仓库的默认分支提 PR。

## 组件与依赖选型

- 实施或规划任务时，应优先复用 Rust、Flutter/Dart、目标平台提供的官方组件、标准库和项目现有抽象；官方能力不足时，再评估维护活跃、文档完整、目标平台与许可证可核验的成熟第三方组件，避免重复造轮子。成熟度不能只由下载量判断。
- 选用组件前，必须查阅其官方文档、最佳实践和 API 契约，核对版本、生命周期、错误处理、异步/并发语义、目标平台和集成边界；同时检查工作区已有依赖与可复用能力，避免引入第二套事实源。
- 不得在上层重复实现组件已有能力，也不得无理由增加包装层、兜底逻辑、shim 或兼容分支；只有承载项目领域语义或必要边界适配时才保留薄适配层，并让底层组件的错误和限制保持可见。
- 若现有官方或成熟第三方方案都不能满足需求，应先调研自研范围、成本、维护风险和兼容影响，将候选方案、来源、排除理由与取舍记录在计划或交付总结中，并向用户询问是否选择自研；在用户明确选择前，不开始自研实现。等待决定期间可继续进行不改变生产实现的只读调研。
- 本节是组件路线的特殊决策门槛。质量技能和领域 Skill 只能补充检查，不能以“无需逐项审批”、默认 fallback 或自定义平行实现绕过该门槛。

## 架构演进与数据迁移

- 修改前理解当前架构、所有权和完整调用链，优先复用已有逻辑与抽象，沿用领域命名和测试方式，避免建立平行实现或第二份事实源。
- 当前架构无法合理满足需求时，允许在任务范围及必要相邻边界进行破坏性调整。以职责清晰、事实源统一和长期可维护为优先，不为最小差异或保留旧接口牺牲架构，也不借此扩大为无关重构。
- 架构调整须同步迁移受影响调用方、协议映射、测试与文档；完成后删除旧实现、旧接口、转发别名及兼容分支，只保留最新架构与逻辑。仓库外消费者通过版本变更说明指引升级，不在项目内保留旧接口。
- anywork 本次大版本不迁移旧会话、历史、调用统计及产品库：旧目录原样隔离，新会话写入独立 v2 数据根；供应商等非会话配置与凭据关联仍须安全迁移。其他需要迁移的用户数据只在明确迁移边界解码，正常运行只消费当前结构；现役外部协议适配和平台支持不属于应删除的兼容层。
- 数据库与会话边界遵循 [存储契约](design/17-studio-storage.md)，配置与凭据关联迁移遵循 [配置契约](design/20-config.md)。本版本 v2 内后续持久化结构变化仍须迁移并验证，不能以备份后清空或恢复默认值代替迁移；断代不授权删除旧目录。
- 破坏性代码或接口调整不授权删除用户数据，也不扩大提交、推送、发布或部署权限；相关授权统一遵循前节。

## Git 提交与 PR

- commit subject 和 PR 标题必须使用 Conventional Commit：`<type>(<scope>): <description>`。
- `type` 仅使用 `build`、`chore`、`ci`、`docs`、`feat`、`fix`、`perf`、`refactor`、`revert`、`test`。
- `scope` 可省略，但优先使用稳定范围，如 `studio`、`agent-runtime`、`release`。
- 中文描述可以使用，但必须保留英文冒号，例如 `fix(studio): 修复项目清理确认无效`。
- 用户可见缺陷优先使用 `fix`，新能力优先使用 `feat`；破坏性变更使用 `!` 或 `BREAKING CHANGE` footer。
- squash 合并前同时检查 PR 标题和实际 commit subject，确保最终提交可被 Release Please 解析。

### PR 截图证据与附件

- 涉及界面设计或功能修改的 PR，正文必须嵌入与本次改动直接相关的真实截图证据，并说明截图来源、场景、平台及实际覆盖范围。界面变更使用实际运行截图，按需提供同窗口尺寸的前后对照；纯文档变更不要求截图，也不为凑截图运行无关产品 GUI 或全量测试。
- 截图必须通过 GitHub 附件等已授权渠道上传，不能只放本地路径、文字日志或 PR 评论来替代正文中的图片；不得用示意图、生成图或其他版本的截图冒充本次验证。上传前检查并遮蔽凭据、个人信息等敏感内容，必要遮蔽须说明，不能改动验证结果。
- 截图、预览文件和上传中间产物遵循下文“会话文件与交付位置”，不得放入源码、Git 提交或长期 Skill 资产；已有工具的固定产物入口保持不变。提交前检查暂存区与 PR 差异，不为隐藏截图修改仓库或全局忽略规则。

#### 使用 GitHub CLI 添加附件

先运行 `gh --version`、`gh pr create --help` 和 `gh pr edit --help`，核对当前版本的 `--attach` 能力与行为，不凭旧版本经验断言 CLI 无法上传。以下示例在本会话 `artifacts` 目录执行；`OWNER/REPO`、`BASE`、`BRANCH`、`PR_NUMBER`、标题与文件名均替换为实际值。

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

- 自动版本计算统一递增 minor，`fix:` 也不自动递增 patch；`!` / `BREAKING CHANGE:`
  不自动递增 major，但必须保留真实的破坏性变更标记和发行说明。发布契约见
  [发布与更新](design/23-release-update.md#231-版本与发布流)。
- 普通 `docs:` / `chore:` 不进入发行说明，仅含这些提交的批次不触发 Release PR；
  真实破坏性变更说明和显式 `Release-As` 人工版本决定不受普通分类隐藏影响。
- major 只能在维护者明确决定后，用最终落入 `main` 的提交正文 `Release-As: x.y.z`
  指定目标稳定版本。例如 subject 为 `chore(studio): release 7.0.0`，正文为
  `Release-As: 7.0.0`；这只是操作示例，不授权 agent 自行提交或选择大版本。
- 使用 squash 合并时确认最终 commit body 保留 `Release-As`；仅修改 PR 标题或描述不够。
  等待 Release Please 同步生成版本文件和 CHANGELOG 后，再审查并合并 Release PR；不直接
  手改版本文件或 tag，也不在配置中长期保留 `release-as`。现有构建、签名和故障恢复流程不变。

## 项目目录与命令入口

### 基本目录

- 仓库 Python 脚本统一用 `python3` 运行；系统 `python` 是 Python 2。
- Rust crate 名称统一以 `pl-` 开头，例如 `pl-core`、`pl-model`、`pl-studio-bridge`。
- Flutter app 的 Dart package 名称是 `anywork`。
- Flutter 项目根目录是 `code/anywork`。
- SDK-only Dart Client 位于 `code/anywork_client`，无 Flutter/Riverpod/FRB 依赖；Client 命令通过 `cargo xtask verify-client` 在正确目录执行。
- 每个 `AppGraph` 拥有独立 Client 与资源。`presentation/providers` 只适配只读观察；其销毁只能取消自己的观察和预算 permit，不能关闭 Session/ChatView、清草稿或清附件。业务意图直接调用 Client action；`features/**` 不导入 FRB、transport 或 Client 私有实现。

### 会话文件与交付位置

- 临时脚本、中间文件和一次性探针使用最新宿主 `studio.session-files` 事实给出的本会话 `scratch/`，待交付产物使用其 `artifacts/`；路径属于当前实际 workspace，SSH 场景属于远端，不能从本地 home、进程 cwd 或旧会话推导。完整布局与保留边界见 [存储契约](design/17-studio-storage.md)。
- 正式代码、项目文档和用户明确指定的交付物仍写目标项目位置；非项目产物须报告真实路径。工程工具有明确输出入口（如 xtask 的 `target/manual-gui/`）时遵循该入口，不擅改工具的产物布局。
- 宿主内部会话数据库、归属清单、可靠资源与传输暂存不供模型手工维护；不要将 helper 资产目录、系统 Skill 安装目录或其他 Thread 的临时目录当作可写工作区。directory 的自身临时目录许可不扩大业务 `writablePaths`，也不放宽只读或 confined 边界。
- 一次性截图、日志与脚本不提交到源码或 Skill 支持目录；确需沉淀时只保留泛化知识。运行池自带忽略文件，已有用户忽略规则不覆盖；不要为隐藏运行产物改全局 Git 配置或清理未知文件。

### Flutter 与 Dart 命令

- 禁止在 Flutter 或 Dart SDK 安装目录执行本项目的 `flutter`、`dart` 命令。Flutter app 命令的工作目录必须是 `code/anywork`；纯 Client 命令由 `verify-client` 切换到 `code/anywork_client`。不得在 SDK 目录执行项目命令。
- 从仓库根目录执行 Flutter/Dart 命令时，优先使用 `cargo flutter <args...>` 和 `cargo dart <args...>`；参数原样透传，包装命令会自动切换到 `code/anywork`。
- 只有包装命令无法满足需求时，才可直接运行 `flutter` 或 `dart`，且必须先把工作目录切换到 `code/anywork`；不得把 SDK 目录当作项目目录。
- 常用命令：

  ```powershell
  cargo flutter analyze
  cargo flutter analyze
  cargo dart format lib test_driver
  ```

### 桌面 GUI

- GUI 构建和运行必须从仓库根目录通过 xtask（按当前 OS 选择目标平台：Windows / Linux）：

  ```powershell
  cargo xtask run-gui [--demo] [--driver]
  cargo xtask run-gui --release
  cargo xtask build-gui [--demo] [--no-clean] [--check-generated]
  ```

- `build-gui` 基于已提交的 `Cargo.lock` 与 `code/anywork/pubspec.lock` 确定性构建。它允许同步缺失的远程包，但 Flutter 使用 `pub get --enforce-lockfile`，Cargo 使用 `--locked`，不会更新 lockfile 或重新解析版本；`cargo xtask`、`cargo flutter` 和 `cargo dart` 包装命令本身也使用 `--locked`。依赖升级必须手动运行对应的依赖更新命令并审查提交新的 lockfile。
- Windows 稳定发布先用 `cargo xtask build-gui` 生成 bundle，再用 `release-gui stage --version <x.y.z> --bundle <路径>` 显式打包已校验的预构建输入；`stage` 不再隐式编译。CI 下游直接执行同次构建归档且已核验身份的发布工具，不重新编译工具。仅重跑失败或指定的下游作业可复用该次 run 的构件；完整重跑与过期构件不属于断点续跑保证，见 [发布与更新](design/23-release-update.md#231-版本与发布流)。

- 不支持直接执行 `flutter build windows|linux` 或 `flutter run -d windows|linux`，也不新增 PowerShell GUI wrapper。
- `run-gui --release` 直接启动已有 `dist/anywork-release` 原生程序，不执行构建或依赖解析；缺失时提示先执行 `build-gui`。它与 `--demo`、`--driver`、`--profile` 互斥，并沿用平台进程树管理。
- Linux 原生 GUI 需要 Clang/C++ 标准库、CMake、Ninja、pkg-config 与 GTK 3 开发文件；Debian/Ubuntu 示例为 `sudo apt-get install -y clang cmake ninja-build pkg-config build-essential libgtk-3-dev`。xtask 必须用当前 PATH 和真实最小 GTK/C++ 工程预检，缺失时透传实际命令与原始错误；不得写死编译器版本、系统库路径或注入机器专用 include/library 环境。Rust 桥以 `libpl_studio_bridge.so` 预构建并经 `ANYWORK_BRIDGE_LIBRARY` 环境变量注入 CMake，与 Windows 的 DLL 契约一致。
- `cargo xtask run-gui --driver` 使用 `test_driver/driver_main.dart` 启用 Flutter Driver extension，供 Dart MCP 的 `flutter_driver_command` 操作 GUI；xtask 不负责启动实验性的 `dart mcp-server`。
- `cargo xtask manual-gui` 启动隔离的原生 Studio 和本地模拟供应商，记录截图、快照、请求与日志供人工判定；真实供应商人工验收仍用 `cargo xtask run-gui --driver` 直接读取用户已有配置，不修改其凭据。
  此命令仅按需编译并调用独立的 `pl-studio-acceptance`，参数由验收工具解析；普通 xtask、
  Flutter/Dart 包装命令不链接该工具及其 Studio/数据库依赖。全 workspace 检查仍覆盖验收工具。
- 本地原生验收默认使用当前受支持宿主平台，报告中明确平台与覆盖范围，不把单平台结果外推为跨平台通过；跨平台任务按实际影响说明其他平台的验证结果或缺口。
- GUI 人工验收使用 `cargo xtask manual-gui`；`cargo xtask run-gui --demo` 仍可供独立的界面预览，不能证明真实 bridge、持久化或 provider 行为。
- Driver 命令在正常完成、失败或取消后都必须等待并回收所属 Flutter、DTD、GUI 及其子进程，不得残留；Windows 使用 Job Object 管理进程树，Linux 使用项目的进程树生命周期机制。
- 调试和验收 Flutter GUI 时，Flutter Driver 能覆盖的交互必须使用 Flutter Driver，不使用 Computer Use。只有 Driver 无法覆盖且确有必要时，才可使用 Computer Use，以减少对用户鼠标、键盘、窗口焦点和桌面状态的影响。

### GUI 生成文件

- Riverpod、Freezed、l10n 和 FRB 文件属于生成边界，只能从仓库根目录统一生成：

  ```powershell
  cargo xtask generate-gui
  ```

- 不得手工修改生成文件，也不得直接调用单个生成器。
- 修改生成输入后运行 `cargo xtask check-gui-generated` 检查 canonical 输出，并分开审查生成 diff 与手写 diff。已授权的代码修改或生成一致性验证包含这些命令所需的生成操作，不为常规生成另行确认；用户明确限定只读时，不运行会改写跟踪文件的命令，报告未验证项。
- 普通 `run-gui` 和 `build-gui` 只消费当前源码，不运行生成器或可写格式化；修改生成输入后必须先显式运行 `cargo xtask generate-gui`。
- `check-gui-generated`、`verify-gui` 和 `build-gui --check-generated` 会重新生成并检查 canonical 输出，适用于提交前及 PR 质量门禁。稳定发布的编译阶段与 RC 构建直接消费已提交的生成文件，后置 `release-gui stage` 只打包预构建 bundle，不重复质量门禁；批准发布前须确认前序验证完成（见 [发布与更新](design/23-release-update.md)）。
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

| 任务语义 | 技能 |
| --- | --- |
| Rust 实现、错误传播、重构与审查 | [rust-code-quality](.agents/skills/rust-code-quality/SKILL.md) |
| 公共接口、类型、错误、模块、依赖与协议 | [rust-api-design](.agents/skills/rust-api-design/SKILL.md) |
| 同步、异步取消、回调与资源生命周期 | [rust-concurrency-safety](.agents/skills/rust-concurrency-safety/SKILL.md) |
| unsafe、FFI、外部句柄与安全证明 | [rust-unsafe-safety](.agents/skills/rust-unsafe-safety/SKILL.md) |
| 测试设计、回归、层级、必要性与去重 | [test-quality](.agents/skills/test-quality/SKILL.md) |

质量技能以 TGOSKits `4713bfc98f` 为迁移基线，经泛化后在本仓库独立维护；运行任务时不依赖源仓库。命令、授权与项目架构以本文件为准；技能负责相应方法与证明，不复制另一套审批或门禁。

### Rust 异步接口约定

- 禁止使用 `#[async_trait]` 和 `#[allow(async_fn_in_trait)]`；仅实现 `sea_orm_migration` 的 `MigrationTrait`、`MigratorTrait`、`MigratorTraitSelf` 时允许使用其官方 `async_trait` 宏，以遵循第三方接口契约。
- 异步 trait 使用原生 RPITIT，在返回 future 上显式声明 `Send`；不通过宏隐藏生命周期或线程安全约束。

### 核心 crate

crate 职责、依赖方向与禁止依赖的唯一权威源是 [Crate 边界](design/02-crates.md)。修改前按该边界确认契约所有者；需要调整边界时遵循前文架构演进规则。

### Flutter、Bridge 与 wire

- Dart reducer 和 projection 优先消费 typed DTO/union，不新增 raw JSON 运行期兼容入口。
- Settings/GUI 状态更新必须以 bridge 返回的 canonical snapshot 或事件流为准，不能只修改本地 draft。
- 序列化类型统一使用 `#[serde(rename_all = "camelCase")]`；Rust 字段保持 `snake_case`。
- ID 使用 `String`，内部按需解析 UUID；时间戳使用 Unix 秒 `i64`，字段命名为 `*_at`。
- 结构化协议变更必须同步 Rust protocol、FRB DTO、Dart domain model、reducer/projection 和设计文档。
- 前端测试、浏览器验证和临时 dev server 不得占用 `1420` 端口，该端口保留给用户脚本。

## 测试、检查与交付

- 验证按实际影响选择。纯文档、技能或协作规则修改（包括提交前）只检查内容、引用、规则一致性及适用格式，不运行 Rust、Flutter、GUI 或 live 全量验收；若同时改变构建／生成输入、运行配置或测试执行语义，则按这些实际影响验证。代码修改先运行定向检查，跨 crate、协议、构建或依赖变更扩展到相关消费者；提交前执行下述代码门禁，生成输入、GUI 行为与 live 验收另遵守对应要求。
- 适用检查通过且需求已满足后直接交付；只有新修改、失败或尚未解决的具体风险才扩展或重复验证。只读分析以结论与出处为完成条件；修改任务以范围内修改完成、适用验证通过和差异可审查为完成条件；提 PR 任务还须交付 PR 链接及实际 CI 状态，排队或运行中不算通过。环境或权限阻塞时报告已完成项、原始失败和剩余工作，不声称全部完成。
- Rust 常规自动化用例位于 `pl-patch/tests/`、`pl-model/tests/` 与 `pl-core/tests/`，只通过被测 crate 的公开 API 验证完整能力；`pl-patch` 仅限补丁语义一致性专项（与 Codex `apply-patch` 语义对齐，有意差异须显式断言），见 [测试设计](design/24-testing.md)。纯 Dart Client 的公开行为测试位于 `code/anywork_client/test/`，Riverpod/路由适配契约测试位于 `code/anywork/test/client/` 并纳入 `verify-client` 门禁。`pl-studio-runtime` 允许历史保存与数据迁移专项故障注入，以及 `tests/` 中通过公开 API、真实临时 Git/SQLite 验证工作树和归档生命周期的专项集成测试；不为测试扩展生产公共接口。除上述专项外其他 Rust crate 不新增测试；除上述 Client 适配契约外，Flutter widget/integration 与发布脚本测试仍不进入门禁。上述 Rust 测试通过本地模拟供应商或脚本化模型运行；`pl-core` 不依赖 `pl-model`。上游预置技能自带的测试源码保持原样，但不进入本项目门禁。测试设计与失败传播遵循 [test-quality](.agents/skills/test-quality/SKILL.md)，具体边界见 [测试设计](design/24-testing.md)。
- `code/anywork/pubspec.lock` 是必须纳入 Git 的 canonical 应用依赖快照，不得加入 ignore；
  Flutter 直接依赖升级后必须同步提交重新解析的 lockfile。
- 代码、构建、依赖或生成输入变更提交前，在本地执行与 CI 一致的检查清单（纯说明性变更按本节首条豁免；只需保证当前环境通过；
  `PUB_HOSTED_URL` 及其镜像行为由 Flutter/Dart 自身处理，xtask 不改写已跟踪的
  `pubspec.lock`）：

  ```powershell
  cargo fmt --all --check
  cargo clippy --workspace --all-targets -- -D warnings
  cargo test -p pl-patch
  cargo test -p pl-model
  cargo test -p pl-core --features sqlite
  cargo test -p pl-studio-runtime
  cargo xtask verify-client
  cargo xtask verify-gui
  ```

- Linux 上运行使用外部 helper 模式的 Studio/Server 人工验收前，先执行
  `cargo install --path code/pl-remote-helper --locked`，确保同一生产进程 worker 位于 PATH。
  桌面 xtask 构建将 worker 作为 Flutter bundle 资源分发，不嵌入 bridge；两种宿主均不使用裸 shell 后备路径。

- 不默认启用 `--all-features`：`live-tests` 等 feature 依赖外部服务与有效
  API key，需要时以 `cargo run -p pl-studio-runtime --features live-tests --example model_observe -- <provider> <model> <task-file> <artifact-dir>` 等显式
  opt-in 执行，CI 与本地默认检查都不包含。
- 真实模型和 GUI 任务使用人工观察入口；本地模拟验收记录执行结果和证据，不把模拟通过等同于真实供应商兼容。人工结论独立记录，默认为待评审。
- CI（PR Quality Gate）运行 `pl-patch` 补丁语义专项、两库的确定性公开 API 集成测试与 Studio 历史保存、迁移及工作树/归档专项测试，并保留格式、静态分析、编译和 GUI 生成一致性检查，另执行 Conventional PR 标题、工作流静态检查及发布配置检查；GUI 人工验收与 live 模型观察不在 CI 中运行。GUI 行为改动交付前运行 `cargo xtask manual-gui`，核对截图、快照、日志和进程回收。
- `cargo doc --workspace --all-features --no-deps` 为按需检查项，CI 不执行。

- Flutter、Dart、GUI 和生成文件检查统一使用前文定义的项目命令入口；验收时结合 widget tree、窗口截图和日志判断结果。
- 交付前运行 `git diff --check`，确认无意外生成文件、无范围外改动，并在总结中列出实际执行的测试、未执行项及原因。
