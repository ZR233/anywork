# 20 - Studio 持久化配置

本文是配置文件结构（schema）、账号与模型结构、提示词分层、MCP/技能/LSP 配置与凭据策略的唯一权威源；权限语义见 [04](./04-security.md)，模型层机制见 [06](./06-model.md)，设置页 UI 见 [19](./19-studio-ui.md)，智能体配置模板（Agent Profile）体系见 [12](./12-collaboration.md)。

## 20.1 配置位置与产品身份

`anywork` 使用独立的产品身份，默认仅访问 `~/.anywork` 数据根目录，操作系统凭据服务名固定为 `anywork`，产品环境变量前缀为 `ANYWORK_`。显式指定的数据根目录遵循命令行参数与环境变量优先级。

主配置文件固定为 `~/.anywork/config.toml`（Windows 下为 `%USERPROFILE%\.anywork\config.toml`）。会话、产品数据库与调试日志的数据布局由 [存储契约](./17-studio-storage.md) 统一定义。用户自定义智能体模板单独保存于 `~/.anywork/agents/*.toml`。配置结构版本号以代码常量为准。

机器人期望配置（desired config）独立保存于 `<StudioHome>/v2/bots/<bot-id>/config.toml`，拥有独立的结构版本与 `configRevision`，不在主配置文件中混入 Node、MCP 或供应商伪配置。应用密钥（App Secret）使用独立的 `bot:<bot-id>` 凭据作用域；字段定义、首次配对与在线应用边界见 [27](./27-bots.md)，物理存储布局见 [17](./17-studio-storage.md)。机器人配置可保存非敏感的所选凭据版本引用（不含凭据明文），所选引用、候选凭据材料及待确认提交的恢复由机器人所有者统一协调。

配置运行时在 Studio 启动时读取配置文件；此后普通对话与设置查询仅读取内存中的权威快照（canonical snapshot）。配置文件不存在时设置页展示内存默认配置；外部文件修改须通过显式重载命令应用。支持在线模型发现的账号在启动时各并行同步一次，运行期允许显式账号级同步；普通读取、订阅与组件重建不联网，也不设置周期自动同步。首屏使用成功缓存或内置定义，不等待网络；在线观察不写回 `config.toml`（详见 §20.5）。普通设置项即时保存；新增或编辑页维护独立草稿，经保存才写入磁盘，离开有修改的草稿须选择保存、放弃或取消。模型启用与压缩阈值为详情中的独立窄命令，不属于整账号编辑草稿（交互与错误反馈见 [19](./19-studio-ui.md)）。

### 配置版本迁移契约

配置版本演进须满足以下迁移契约（会话与产品数据的隔离与演进见 [17.7](./17-studio-storage.md#177-大版本隔离与配置迁移)，不得将会话大版本隔离作为重置用户配置的理由）：

- **启动期跨版本识别与保全**：启动时在发布产品状态前识别配置版本，沿明确的版本转换链将历史配置与用户智能体模板升级为当前结构，完整保留用户选择、账号身份与凭据关联。
- **备份、校验与原子替换**：转换前先备份原始字节且不覆盖已有备份，转换后执行完整声明校验，并通过原子文件替换或可恢复步骤提交。涉及多个配置文件、数据库关联或系统凭据时由 Studio 统一协调，严禁发布新旧结构混合的权威快照。
- **默认值与失败边界**：新增字段仅能使用对应版本迁移明确规定的默认值；旧字段在迁移边界完成转换，不以重建整份默认配置、猜测模型路由或运行期双轨兼容分支代替迁移。正常读写仅消费当前结构。未知未来版本、语法解析失败、旧 DTO 不匹配或迁移后的无效引用均按 `Migration` 停止加载，保留原文件与未决操作，不触发全局备份或默认重建；缺失或无效的程序迁移链属于 `Internal` 故障。系统凭据库或底层 I/O 故障保持 `Environment` 并停止启动。不改变 [17.2](./17-studio-storage.md#172-启动与按需激活) 对无关数据库损坏的既有恢复策略。错误链保留原始 source，诊断提供文件、文档族、源/目标版本与失败阶段，不回显配置原文或敏感凭据。
- **可恢复性与重载约束**：迁移中断后重启可安全接续同一操作（操作日志仅记录身份、版本、步骤与摘要校验，不记录密钥）；运行期显式重载仅接受当前有效结构，失败时保留既有权威快照，不在查询或重载路径中隐式执行版本迁移。

配置版本转换继续使用 TOML/Serde 与系统凭据服务：类型转换仅承担配置领域语义，多文件和凭据关联的联合提交继续遵循上述可恢复操作契约。SQLite 的结构与数据迁移统一由 SeaORM 官方迁移系统管理（见 [17.11](./17-studio-storage.md#1711-上下文来源与版本升级)），不将配置文件迁入数据库，也不以 SQL 事务代替跨文件、系统凭据的恢复协议。

历史配置版本迁移链摘要如下：
- **版本 `18 → 19 → 20`**：`18 → 19` 从 `disabled_system_agents` 移除 `planner` 并保留五条模型路由；`19 → 20` 将旧 `planner` 路由复制为 `mode.simple` 与 `mode.task` 的默认路由，从 `models.routes` 中删除 `planner`，并保留四个系统子智能体路由、账号及凭据关联。
- **版本 `20 → 21`**：将 `models.providers.<id>.capabilities.web_search.standalone = "deep_seek_anthropic_messages"` 改写为 `"deep_seek_tools_api"`，并按版本默认值补齐 `[deepseek_web_search]` 的 `fetch_enabled`。
- **版本 `21 → 22 → 23`**：`21 → 22` 将旧模型声明中的 `slug` 转换为 `model_id`；`22 → 23` 将模型接入领域的 `Provider/Preset` 统一迁移为 `Account/AccountTemplate`（`models.providers` 转为 `models.accounts`，账号 `preset` 转为 `template`、`adapter` 转为 `protocol`，角色、工作模式与用户智能体模板中的 `provider`/`model` 转为 `account_id`/`model_id`）。
- **版本 `24 → 25`**：保留或补齐 ACP 账号集合，显式移除旧版 ACP 的自定义 `program`/`args` 字段，同时保留模型禁用集合（`disabled_models`）、计费类别覆盖（`billing_kind`）与子智能体分发默认设置（`[delegation]`）。
- **版本 `25 → 26`**：退役账号 `pricing_mode`，计费意图统一由 `billing_kind` 表达；保留既有类别覆盖、参考价格、账号身份与凭据，不将旧的关闭估算状态推断为用户声明不计费，也不回写历史账单。
- **版本 `26 → 27`**：将各账号旧 `disabled_models` 成员转换为 `model_enabled_overrides` 中值为 `false` 的条目，移除旧字段；未明确禁用的模型保持自动，不批量写入 `true`。转换保持账号身份、凭据关联、路由及其余覆盖不变，并沿用启动期备份、原子提交与中断恢复边界；正常读写仅消费新映射。

所有设置变更命令（Settings command）均须携带 `expectedSettingsRevision`，成功后返回新的 `SettingsConfigSnapshot`；当模型目录发生变化时一并返回 `ModelCatalogSnapshot`，并分别发布 `SettingsConfigStateChanged` 与 `ModelCatalogStateChanged` 事件。直接响应结构 `SettingsStateResponse` 仅用于在单次调用中同时带回配置与目录两份独立资源，消费端仍按各自修订号幂等合并；CAS 冲突或校验失败时保留当前权威状态。

### 20.1.1 设置变更的资源边界

模型接入协议统一使用 `accounts`、`accountId`、`modelId` 与 `templateId`；模板目录使用 `templates`，与账号实例目录分离。账号配置中的 `template` 为可选模板引用，`protocol` 为明确的厂商协议适配器。账号编辑通过稳定 `id` 定位同一资源，不提供重命名账号 ID 的路径。模型选择、工作模式或角色路由以及会话路由统一使用 `(accountId, modelId)`；`defaultModelId` 与 `suggestedModelId` 仅作为目录或新建路由的展示投影，不构成账号运行时的第二份模型选择。

写入接口按最小业务资源划分，不将整个 `StudioSettings` 快照作为补丁提交：标量设置、列表设置、单个 MCP 字段、单个工作模式的模型或推理强度、单个智能体角色的模型或推理强度各自使用独立的类型化变更命令（typed mutation），请求仅携带目标标识与新值，其余字段由配置所有者从最新权威状态解析。

账号创建与编辑均由配置所有者联合校验端点、凭据、声明和覆盖。创建提交完整初值；已有账号编辑提交实际变更的类型化字段意图，保持未编辑字段，不允许 CAS 重试重发旧整卡覆盖并发模型配置。未修改、显式设置与清除覆盖有不同表示；创建或编辑时凭据留空均采用 `Preserve`，不能将未输入凭据解释为删除系统凭据的 `Clear` 意图，账号 ID 不可重命名。模型启用、计费类别、连接方式与压缩阈值分别使用窄命令，仅修改目标账号或模型；阈值接受精确正整数，恢复自动只删除该覆盖。配置事务及凭据提交仍复用现有原子资源边界。已有会话路由更新同时核对能力和活动状态，不与账号编辑混为同一操作。

所有账号模板共用相同的配置提交边界：凭据与期望配置落盘、权威状态发布后立即返回，不阻塞等待 MCP 连接、在线模型发现或额度网络查询。

账号 HTTP 写入契约区分创建和编辑：`POST /api/v1/accounts` 仅创建新稳定 ID，已有 ID 必须通过 `PATCH /api/v1/accounts` 提交字段意图；退役旧 `PUT /api/v1/settings/account` 整卡 upsert，不保留转发别名。文本及模型声明字段使用保持、设置与恢复默认三态，省略表示保持，显式 `null` 不替代清除意图；恢复默认需存在适用默认值，否则拒绝。连接与阈值分别通过 `PUT /api/v1/accounts/model-connection` 和 `PUT /api/v1/accounts/model-auto-compact` 提交设置或清除覆盖意图。`POST /api/v1/accounts/sync-models` 只返回同步受理身份，最终结果从独立目录来源观察。外部消费者须升级请求与响应类型，不将创建、编辑或同步受理混为同一个保存操作。

### 主配置与 Profile 的类型迁移和恢复

文件级 schema 规则统一见 [17.11](./17-studio-storage.md#现役-toml-文档的独立格式迁移)。主配置保持整数版本 27，完整支持 18–27 的连续类型链；用户 Profile 各自新增整数 `schema_version=1`，不再依赖主配置版本判断。主配置已经是当前版本时，后来导入的无版本 Profile 仍须在启动/显式导入边界独立升级。普通查询与订阅只读取已发布快照，不执行迁移写回。

Profile 的专属无版本 DTO 分别接收 `provider` / `account_id` 与 `model` / `model_id`：单旧键、单新键、同值双键或能确定唯一完整身份的混合可导入；冲突、缺身份、类型错误及未知结构均拒绝。已有根版本绝不回退无版本导入。格式升级保留 `enabled=false` 等用户选择；主配置 26→27 仅将原禁用模型转换为 `model_enabled_overrides=false`，不为其他模型补造显式 true。

联合引用校验针对真正待提交的迁移候选。已经是当前格式且不需要替换的 Profile 只验证版本、结构与字段；若其账号或模型已由正常设置操作删除，继续沿用 Profile 目录的不可用诊断和可编辑状态，不将该资源的路由不可用升级为整个应用启动失败。禁用 Profile 同样保留这一行为；待导入或升级的候选仍须在提交前通过联合引用校验。

跨资源提交继续由现有配置/凭据协调器负责，不由迁移库拥有第二份运行时状态。先持有实例锁并完成 pending journal 的原操作：旧目标 23–27 的候选字节、摘要和 operation 身份不能改为最新候选；需要验证当前视图时只在内存转换，原操作完成后才准备下一次升级。历史 journal 解码固定在恢复边界。

主配置和每个 Profile 分别产生候选并联合校验账号/模型引用，再完成所需 keyring 写入及持久回读，交原协调器提交与发布。主配置实际源版本、内联 token 与旧凭据关联的迁移意图从已验证原件保留，不能在当前 DTO 删除旧字段后反向推断；新候选及新日志不新增明文凭据，受保护历史原件沿用原策略。新操作可仅包含 Profile，不把无变化的 main 加入替换列表；每个资源按自身文档族、源/目标版本和摘要判断，不用 main 的全局版本代替 Profile 版本。替换后的同步故障按真实日志/磁盘状态收敛，确认前不发布候选快照。

## 20.2 配置职责划分

### ACP 接入配置与模型阈值覆盖

账号设置以 `Native` 与 `Acp` 类型化分支汇集两类接入。Studio 独立持有 `acp.accounts`，每个稳定 ID 仅保存名称与接入类型，不使用空 `base_url` 或空模型目录伪装成原生账号。Antigravity 仅运行产品固定 `1.4.1` 版本的受管安装，启动程序与参数由安装与认证边界生成，不属于用户配置字段；ACP 账号不进入原生默认账号或模型路由候选列表。Google 凭据由官方程序管理，不经由原生 API 密钥凭据接口，也不复制到 `anywork` 的 TOML、数据库或系统凭据库（详见 [28](./28-acp.md)）。

每个原生账号的模型目录独立保存按 `model_id` 索引的自动压缩阈值覆盖值（正整数词元数），内置（`bundled`）、附加（`additional`）与显式（`explicit`）模型共用同一解析规则。缺省值表示使用解析后的模型默认阈值（目录预设值或安全输入容量推导值）；恢复默认操作仅删除对应模型的覆盖项，显式设置的数值若与非空默认值相等亦自动归一化为缺省（最终上下文解析规则见 [06](./06-model.md)）。

账号详情的阈值输入与比例预设仅建立呈现草稿，点击「保存」才提交该模型的设置意图；「恢复自动」显式清除覆盖。配置所有者继续接受精确正整数并沿现有模型策略解析最终有效值，界面不另建安全上限算法或把所有模板默认值固定成同一比例。有效值与保存意图因安全策略不同须明确展示，不能静默改写用户输入；该交互不改变配置格式、命令身份或既有 CAS 顺序。

模块职责边界如下：
- **`pl-model`**：拥有产品无关的模型配置值对象，包括角色路由配置（`account_id`、`model_id`、`effort` 的校验与解析）、账号配置与模型路由配置，负责将路由解析为运行时端点与唯一选中的不可变模型信息，不执行文件 I/O 或路径定位。
- **`pl-studio-runtime`**：拥有 Studio 配置结构与启动期版本迁移、配置文件路径、TOML 解析、原子保存与默认值、系统指令、技能、MCP、运行时声明、`disabled_system_agents`、UI 配置、智能体模板文件的逐文件解析与原子保存，以及会话首轮固定系统指令快照的生成。配置所有者在同一发布边界区分磁盘期望配置与非持久化在线模型目录覆盖层（overlay）；保存操作仅序列化磁盘期望配置，绝不将在线发现的模型写入 `additional_models` 或转存为自定义模型。

`[ui]` 配置段仅保留 `follow_active_turn`（默认 `true`）与 `compact_timeline`（默认 `false`）；视觉主题不属于持久化配置项。

### 20.2.1 模型启用、计费类别与分发默认设置

- **模型启用覆盖（`model_enabled_overrides`）**：保存精确 `model_id` 到布尔值的映射，缺省为空；条目为明确开启或关闭，缺项表示按 [06](./06-model.md) 的目录规则自动解析。线上未列出的内置项仍在配置列表展示，用户可显式开启；来源变化或重启不清除已保存意图。模型启用状态切换复用独立类型化变更命令（携带 `operationId`、`expectedSettingsRevision`、`accountId`、`modelId` 与 `enabled`），只更新指定成员的覆盖，提交后同时推进设置水位与目录资格水位。模型配置快照以 `modelEnabledOverrides` 发布期望配置，目录快照发布已解析的 `enabled`；两者不是两份独立启用设置。禁用导致既有路由不可用时仅标记路由 `unavailable`，不自动篡改用户已选路由。
- **账号计费类别（`billing_kind`）**：可选值为 `metered | subscription | noCharge | unknown`，作为账号计费意图的唯一持久化事实源。省略时按明确模板与权威端点地址自动推导生效类别，无法匹配时为 `unknown`；显式配置值优先且不被端点地址修改静默覆盖，自动推导结果亦不回写为显式配置。权威设置快照同时投影生效值 `billingKind`（用于展示与筛选）与可空覆盖值 `billingKindOverride`（表达用户显式意图）。账号页的「不计费」开关即该类别的布尔投影：开启时写入显式 `noCharge`，关闭时清除覆盖并恢复自动推导。
- **子智能体分发默认设置（`[delegation]`）**：保存 `mode = profile | automatic`（默认 `profile`）与 `preference = economy | balanced | fast`（默认 `balanced`）。两个字段各自使用独立的类型化设置命令，仅改变未来新建会话的默认值；已建会话在创建准入时冻结解析后的非空枚举，后续不再回读全局默认设置（见 [12](./12-collaboration.md) §12.7）。

## 20.3 根路由与系统 Profile

配置文件不设全局 `active_account`。根智能体的期望路由归属各自会话；主配置通过 `mode_model_routes` 保存各工作模式的新建与切换默认选择器。`mode.simple` 与 `mode.task` 必须存在并独立保存 `account_id`、`model_id` 与 `effort`；合法的自定义工作模式 ID 在尚无独立条目时继承 `mode.simple`，首次显式选择后形成独立条目。修改工作模式默认路由不会反向改写其他已存在的会话。

账号页「设为默认」只更新 `mode.simple` 的保存意图，不改其他模式或 `models.routes` 中的显式角色覆盖。未配置专属路由的系统子智能体仍整体继承当前 `mode.simple`，因此其有效 Profile 投影及未来新建实例可采用新的默认选择；已有 Thread／child 的冻结选择保持原样，不将继承值回写为显式覆盖。验收须分别比较保存意图与有效投影，不能要求缺省继承的有效值永久不变。

`models.routes` 仅保存系统子智能体配置模板的显式路由覆盖；用户自定义智能体模板的路由直接保存在各自的 `~/.anywork/agents/*.toml` 文件中。现有内置系统子智能体的配置键如下表所示（实际集合由统一智能体声明的子智能体视图决定）：

| 配置键 | 中文角色名 | 核心用途 |
| --- | --- | --- |
| `explorer` | 探索者 | 代码现状、文档、网络资源与上下文的只读探索 |
| `executor` | 执行者 | 实施明确任务；按授权承担代码、验证、集成、生成及交付操作 |
| `worktree_executor` | Worktree 执行者 | 在独立 Git 工作树中实施修改与验证 |
| `reviewer` | 审查者 | 独立代码审查、检查与隔离环境中的产品操作验收，不修业务源码 |

共用系统提示词约定：主智能体在只读调研及任务（Task）模式的规划阶段可按需委派 `explorer` 子智能体（无需等待实施计划批准），无依赖的多个独立问题可按可用容量并行探索，存在真实依赖的步骤保持串行。委派时须提供自包含的背景、问题、范围、检索线索、来源要求与完成标准；`explorer` 返回结论、可追溯证据与不确定项，交由主智能体综合判断，以减少原始检索材料对主会话上下文的占用。

Task 的实施策略为可选建议，职责与停工裁决统一见 [12](./12-collaboration.md)。执行与验收复用上述预设，不增加专门操作角色或配置：固定分发沿用执行者、审查者各自路由；自动分发按具体任务选择合适模型，不能因模型具备某能力而扩大角色权限。缺所需能力时明确报告，不静默覆盖固定路由。

所有内置智能体均由编译进二进制的声明表与 `include_str!` 内嵌提示词提供，不生成或修改用户目录文件（共同定义与可配置范围见 [12](./12-collaboration.md)）。系统子智能体的身份、用途、系统指令与工作区模式只读且不可删除，可通过主配置 `disabled_system_agents` 禁用。当某个系统子智能体未配置专属路由覆盖时，整体继承 `mode.simple` 的 `account_id`、`model_id` 与 `effort`；显式覆盖优先，且覆盖失效时不静默回退。每个模型绑定包含 `account_id`、`model_id` 与可选的 `effort` 字符串（必须匹配目标模型 `parameters` 中 `name = "effort"` 声明的合法候选值；若模型未声明该参数则必须省略 `effort`）。

## 20.4 TOML 配置示例

本地 `config.toml` 字段统一采用 `snake_case` 命名（与 API 传输层的 `camelCase` 区分），精简示例如下：

```toml
# schema_version 使用当前程序生成的值，版本号以配置代码常量为准。

disabled_system_agents = []

[runtime]
# 字段保留；当前版本执行路径固定为 full-access，该值不影响实际执行（见 04-security.md）。
permission_mode = "request-approval"
active_skills = ["rust", "git", "doc"]
active_mcp_servers = ["github", "filesystem"]

[instructions]
base_override = ""
developer = ""
user = ""
project_doc_max_bytes = 65536

[mcp.servers.filesystem]
enabled = true
transport = "stdio"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "D:/workspace"]
env = {}

[skills]
enabled = true
auto_learn = true
project_dir = ".agents/skills"
user_dir = "~/.anywork/skills"

[mode_model_routes."mode.simple"]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"

[mode_model_routes."mode.task"]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"

[models.routes.explorer]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"

[models.accounts.deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com"
# API 密钥由操作系统凭据库保存，TOML 中不出现明文凭据。
tool_wire_policy = "function_fallback"
template = "deepseek"
protocol = "deep_seek"

[models.accounts.deepseek.catalog]
source = "bundled"
catalog = "deepseek"
```

## 20.5 账号与模型目录

### 只读账号与模板元数据

账号摘要通过可空 `displayEndpoint` 发布安全端点，仅由 Runtime 的 Native 摘要投影从权威配置解析为 URL origin（协议、主机和非默认端口）。摘要不得包含用户信息、路径、查询或片段；无效地址、不透明 origin 或无主机地址返回空值，ACP 固定为空，不回退原始字符串。该字段只供显示，不作为可保存连接地址；原配置与编辑命令保持原有语义。HTTP 协议、FRB DTO、Client 领域值及呈现层保持同一可空契约，列表不得逐行读取详情或自行解析原地址。

Native 模板描述符由 `pl-model` 目录所有者发布 `defaultBillingKind: BillingKind` 与 `supportsModelDiscovery: bool`：前者复用模板账号的权威有效计费推导并保留 `unknown`，后者取自模板引用目录的发现能力。它们是必需的当前协议字段，不用客户端默认值或品牌判断掩盖映射遗漏。字段参与整个目录的修订计算；目录传输 schema 从 `18` 升为 `19`，仓库内生产与测试消费者同步升级，外部消费者须采用新描述符。目录仅有进程内缓存，这些只读投影不增加持久化账号字段、不改变配置 schema，也无需用户数据迁移。

模板描述符另包含可空 `supportsUsageQuery`：空值表示该目录发布者未提供运行时查询能力，不等同于不支持。`pl-model` 的静态目录不拥有 Studio 用量查询处理器，因此发布空值；Studio Runtime 在同一目录读取入口补齐每个 Native 模板的明确支持值，HTTP 与 FRB 共用这一最终快照，不增加客户端第二份目录或额外读取。该支持值与账号摘要的查询能力、实际查询分派来自 Runtime 同一类型化策略，保留既有模板身份归一化及配置失败语义，不从品牌、发现能力或凭据状态推断。支持表示存在查询处理器，不保证凭据有效、查询成功或套餐额度充足。

Runtime 发布的目录修订同时覆盖完整的能力补齐后快照与 `pl-model` 基础修订，后者继续覆盖目录 DTO 之外的传输 profile 修订。修订为不透明标识，消费者仅比较身份，不依赖长度或哈希格式；不得沿用不覆盖运行时能力的基础修订，也不新增持久化目录缓存。

`models.accounts` 支持保存多个账号实例，同一账号模板可重复创建多个实例（唯一性仅约束映射表键名）。每个账号实例持久化以下内容：
- **协议与模板身份**：明确的厂商协议适配选择 `protocol`、可选的 `template` 模板身份（完全自定义账号可不保存 `template`）。
- **实例连接字段**：显示名称 `name`、服务端点 `base_url`、环境变量引用 `bearer_token_env`、自定义请求头 `http_headers`、工具协议策略 `tool_wire_policy` 与补丁工具类型 `apply_patch_tool_type`。`apply_patch_tool_type = "freeform"` 表示该实例允许把内置补丁工具下发为 freeform（custom）工具；缺省值或非原生 custom 线协议时使用函数回退声明（形态与判定条件见 [09](./09-tool-runtime.md) §9.8）。
- **模型目录（`catalog`）**：分为 `Bundled { catalog, additional_models, connection_overrides }` 或 `Explicit { models, connection_overrides }`。
- **端点服务能力（`capabilities`）**：分为 `TemplateDefaults`（判别值为 `capabilities.source = "template_defaults"`，默认继承权威模板声明的服务能力）或显式声明的服务能力（自定义账号默认无附加服务能力）。

账号声明的保存资格与模型的路由可用性分开校验。Native 账号允许在尚未配置任何模型时保存，空 `Explicit` 目录本身不构成声明错误；保存、启动及重载保留这个空目录，不补造模型、在线发现能力或默认路由。名称、端点、协议、模板、凭据和覆盖仍遵循既有校验，已有路由与模型引用的完整性约束不因允许空目录而放宽。没有可用模型的账号不能设为默认，也不能解析为可执行路由；创建后设默认仍是创建确认后的独立操作，失败保留已创建身份，用户补齐模型后仅重试剩余意图。

路由解析根据当前路由选中的模型绑定与连接覆盖（`connection_overrides`）确定传输协议（`Responses` 或 `Chat`）与连接方式（`HTTP` 或 `WS`），再结合账号的厂商协议适配、端点地址、凭据与服务能力组装为运行时路由；合法传输组合矩阵为 `Responses + WS/HTTP` 与 `Chat + HTTP`。

账号端点服务能力与单模型能力严格区分：账号服务能力表征服务端点是否支持 Responses 托管工具（hosted tools）、托管或独立联网搜索（携带 `OpenAIResponses` 或 `DeepSeekResponses` 方言）以及图像生成（携带 `Images` 方言与生图模型前缀）；模型能力则表征当前模型自身是否支持原生搜索、函数调用或多模态输入。官方 OpenAI 端点默认开启 Responses 托管工具，若用户覆盖为自定义 `base_url` 则默认关闭；xAI 权威端点默认继承 `prompt_cache_key` 缓存方言，若覆盖为非权威 `base_url` 则由 `TemplateDefaults` 自动撤销该缓存方言。

内置目录模型与用户自定义或附加模型共用统一的数据结构（含 `model_id`、`display_name`、`description`、`context_window`、`max_context_window`、`auto_compact_token_limit`、`default_temperature`、`max_output_tokens`、`pricing`、`parameters`、`binding`、`capabilities`、`truncation_policy` 与 `base_instructions`）。其中 `capabilities` 为结构化输入能力矩阵（见 [06](./06-model.md)），显式声明支持的模态、来源与体积限制；未知模型默认为纯文本（`text-only`），非视觉模型在任何附件 I/O 与凭据读取前即拒绝图片输入。同账号下显式配置的同 ID 模型定义优先于绑定的内置定义，同 ID 在线明确字段优先于本地补全；不同账号之间的同名模型严禁交叉借用能力、参数或价格。

展示名称优先级是上述字段规则的例外：已有手动模型的 `display_name` 优先于在线名称；没有手动名称时优先采用明确的非空白在线名称，缺失时才使用内置名称及原始 ID，具体规则由 [06](./06-model.md#67-模型目录启用资格与远程压缩) 统一定义。账号编辑页已支持手动模型的显示名称，不另设内置或在线模型的独立改名开关。

### 在线模型观察与目录来源管理

启动与显式账号级同步共用同一发现、完整候选校验及原子缓存发布契约。同账号、同查询身份的重复请求合并到同一在途操作；不同账号独立推进。请求冻结账号与配置代次，配置、有效凭据变化或账号删除使旧结果失去发布资格，查询身份不得泄漏凭据或其摘要。网络请求不持有全局配置锁，成功缓存原子替换后才发布独立的 `modelCatalogRevision`；失败只更新该账号检查时间与类型化错误，保留最近有效目录及手动模型、启用覆盖、连接和压缩覆盖。目录变化不自动更换已选路由，不改变进行中请求的冻结配置。

目录来源保留 `default`、`cached`、`online`，并区分同步中、最近检查、最后成功及错误；模型条目来源仍为 `online`、`bundled`、`manual`。无发现能力明确返回不支持，不伪造成功。删除手动模型的独立命令携带 `operationId`、期望设置修订号、账号与模型身份，仅允许 `manual`，清理该模型所属覆盖但不改写历史或账单。

运行时持有所有同步操作与退役代次，关闭先封闭准入并取消网络，再真实等待活动任务及原子提交；调用方不再等待、关闭超时或取消信号均不解除汇合责任。观察与页面销毁不能终止业务任务。配置、凭据关联与目录缓存不因界面重构重置；持久化变化必须在迁移边界显式保全，遵循 [17](./17-studio-storage.md)。

## 20.6 提示词配置

`[instructions]` 配置段保存与供应商无关的用户可配置提示词来源（缺失整段或单字段时采用默认值）：

- `base_override`：完整替换当前模型的 `base_instructions`，仅用于需要完全接管系统提示词的高级场景。
- `developer`：追加受信任规则，适用于本地运行约束、协作偏好与稳定行为准则（实际发送角色由模型协议分发契约决定）。
- `user`：追加至用户上下文（user context）层，适用于用户背景、项目背景与非强制偏好。
- `project_doc_max_bytes`：`AGENTS.md` 等项目文档的总读取字节上限，默认 `65536`（设为 `0` 表示禁用项目文档注入）。
- `project_doc_fallback_filenames`：除 `AGENTS.override.md`、`AGENTS.md`、`Agents.md` 外额外尝试读取的项目文档文件名列表。

运行时在会话首轮固定基础提示词、受信任规则、用户上下文块与项目文档来源路径；已有会话后续不随全局配置或磁盘文档变化而自动改变提示词，新创建的会话才采用最新配置。基础提示词优先级依次为：显式 `base_override` → 模型声明的 `base_instructions` → 产品内置基础提示词。系统提示词按“基础指令 → 智能体角色指令（`Agent`） → 工作模式指令（`Mode`） → 自动分发偏好 → 平台环境 → 配置规则 → 技能目录与其他约束”的固定顺序组装，并在会话初始化、工作模式切换、请求准备与上下文压缩恢复中复用同一套组装规则（缓存与协议角色映射见 [06](./06-model.md)）。

指令快照同时持久化共同智能体定义身份、适用范围、来源与修订号，以及独立的 `Agent`、`Mode` 与自动分发偏好指令来源（职责边界见 [12](./12-collaboration.md)）。切换工作模式仅更新 `Mode` 来源，模型重绑定仅更新模型基础指令来源；会话恢复、上下文压缩与工具刷新不会根据当前配置目录重建已冻结的 `Agent` 角色指令或分发偏好。宿主运行事实（如平台信息、工作区绑定与 `studio.session-files` 临时目录路径）不属于冻结提示词，在每次安全边界由实际宿主服务动态提供并在压缩后保留最新值。

## 20.7 运行态声明

`[runtime]` 配置段保存本地 Studio 运行态展示所需的可选声明：`permission_mode`、`active_skills` 与 `active_mcp_servers`。其中 `permission_mode` 字段虽保留配置兼容，但当前版本执行路径固定为 `full-access`（见 [04](./04-security.md)），修改该字段不改变实际执行权限。`active_skills` 与 `active_mcp_servers` 仅声明启动预选项，不作为运行期真实可用性来源：MCP 服务的用户启用意图以 `[mcp.servers.<id>].enabled` 为准，真实连接健康度由进程内注册表探测；当前会话的已激活技能（`activeSkills`）由持久化的会话级激活扩展派生（见 [10](./10-skills.md) §10.6）。

## 20.8 MCP 配置

用户自定义 MCP 服务保存在 `[mcp.servers.<server_id>]` 表中。`server_id` 必须非空且仅包含 ASCII 字母、数字、`_` 与 `-`（因其参与构成模型可见的工具名），且不得占用内置保留 ID。Studio 运行时还会合成一组内置 MCP 服务，其界面开关状态保存在 `[mcp.builtin_servers.<server_id>]` 中。每个 MCP 服务须配置 `enabled`（默认 `true`）与传输方式 `transport`（`stdio` 或 `streamableHttp`）：`stdio` 服务须配置 `command`、`args`、`env` 及可选 `cwd`；`streamableHttp` 服务须配置 `url`、`headers` 及可选 `bearer_token_env_var`。

启动后由 MCP 运行时所有者监听权威配置变化并在后台增量协调（reconcile）已启用且凭据完整的服务，维护配置指纹、工具命名规范化（格式为 `mcp__{server_id}__{tool_name}`，最长 64 字符，超长或冲突时追加稳定哈希后缀）、健康状态与代次（generation）原子替换（轮次租约契约见 [09](./09-tool-runtime.md)）。

内置智谱 Coding Plan MCP 服务固定包含 `zhipu_search`、`zhipu_reader`、`zhipu_zread`（均为官方端点的 `Streamable HTTP` 传输）与 `zhipu_vision`（经 `npm` 启动的 `stdio` 传输）。这组内置服务仅复用 `template = "zhipu-coding-plan"` 账号实例的有效 Bearer 令牌（存在多个实例时按账号 ID 稳定排序选取首个具备有效凭据的实例）；无可用令牌时标记为缺少凭据且不发起连接，检测到有效令牌时未显式禁用的内置服务自动启用并进入后台探测。

## 20.9 技能（Skills）配置

`[skills]` 配置段控制本地技能系统：

- `enabled`：是否启用技能目录扫描、提示词注入、工具注册与用户 `/name` 斜杠指令，默认 `true`。
- `auto_learn`：是否在主会话轮次结束后启动后台审查智能体自动沉淀项目技能，默认 `true`。
- `project_dir`：项目级技能目录（相对工作区根目录解析），默认 `.agents/skills`。
- `user_dir`：用户级只读技能目录，默认 `~/.anywork/skills`。
- `system.enabled`：是否启用内置系统技能，默认 `true`。
- `external_dirs`：额外只读技能目录列表，默认空列表。
- `disabled`：禁用的技能名称列表，默认空列表。
- `auto_learn_min_tool_calls`：触发自学习审查所需的最少工具调用次数，默认 `5`。

目录优先级、前置元数据（frontmatter）格式、工具契约与自学习语义见 [10](./10-skills.md)。系统内置的 `studio-config` 技能是面向智能体的 `anywork` 配置指南；任何涉及配置文件路径、结构版本、配置段字段及默认值、凭据解析优先级或保存重载语义的变更，均须在同一提交中同步更新该技能文档。

## 20.10 配置草稿与保存前校验

设置页基于账号配置领域提供的静态权威账号模板目录构造独立编辑草稿；模板不写入通用 `SettingsStore`，共享选模消费模型领域的只读目录，不借用账号编辑整卡（分域边界见 [25.14](./25-frontend-state.md#2514-账号分域与可预览呈现)）。设置项写入磁盘前必须在前端与 Studio 服务端双重完成完整校验，校验失败时仅在界面展示错误而不落盘：
- 账号键名（account key）非空且唯一；模板引用必须存在；自定义账号必须显式指定传输协议（`protocol`）。
- 传输模式组合必须合法：`Responses + WebSocket/HTTP` 与 `ChatCompletions + HTTP` 合法，`ChatCompletions + WebSocket` 在发起任何网络请求前直接拒绝。
- 除允许免鉴权的本地服务外，API 密钥不得为空。
- 没有被路由引用的 Native 账号可保存空模型目录；空目录不提供可选模型，设默认或执行路由仍须解析到真实可用的模型。允许空目录不豁免其他声明、覆盖或引用校验。
- 每个角色路由引用的模型必须存在于对应账号的有效模型集合中，同一账号下的 `model_id` 不得重复；角色引用的默认模型若用于生成角色推理强度，必须声明 `effort` 参数且包含至少一个候选值。

## 20.11 凭据安全策略

账号的 API 令牌保存在操作系统凭据库中（服务名固定为 `anywork`，账户键名为 `account:{account_id}`），`config.toml` 中严禁保存明文令牌、凭据引用或可逆密文。账号配置可同时保存 `bearer_token_env` 环境变量名；运行时按“操作系统凭据库优先，其次读取非空环境变量值（空白值与缺失环境变量均视为无凭据）”的顺序解析。

设置页编辑凭据遵循 `Preserve`（保留原凭据）、`Replace`（提交配置前写入系统凭据库并回读验证）与 `Clear`（删除系统凭据）三态语义。凭据操作与 TOML 原子替换构成同一个失败关闭（fail-closed）提交流程：若凭据写入或回读阶段失败，严禁覆盖配置文件。版本迁移需将旧命名空间 `provider:<id>` 复制至 `account:<id>` 时，必须在持久化凭据服务成功写入并回读验证后才提交新配置引用（不得以进程内临时内存租约的回读代替持久化校验）。机器人模块沿用同一系统凭据服务，按 `bot:<bot-id>` 保存版本化受保护材料（见 [27.2](./27-bots.md#272-管理配置与凭据)）。MCP `stdio` 服务的 `env` 字典按配置原样传给子进程；`Streamable HTTP` 服务的 `bearer_token_env_var` 仅保存环境变量名，由运行时从当前进程环境读取并构造 `Authorization` 请求头。

## 20.12 联网搜索配置与凭据门控

Studio 维护两段相互独立的顶层联网搜索配置：
- **`[web_search]`（OpenAI 搜索）**：`mode` 取值为 `disabled | cached | indexed | live`（默认 `cached`），`context_size`、`allowed_domains` 与近似地理位置均可省略。
- **`[deepseek_web_search]`（DeepSeek 搜索与抓取）**：仅包含 `enabled`（联网搜索）与 `fetch_enabled`（网页抓取）两个布尔开关，默认均为 `true`。

两路搜索并非互斥单选：`StudioWebSearchSettings` 与 `StudioDeepSeekWebSearchSettings` 分别暴露各自的 `configured`、`effective`、`availability` 与 `account_id`（其中 `effective = configured && availability == available`）。权威 DeepSeek 模板默认声明 `DeepSeekToolsApi` 独立服务能力；若实例覆盖了非官方 `base_url`，则 `TemplateDefaults` 自动撤销该方言及缓存方言（而 OpenAI 模板覆盖 `base_url` 时仍保留 `/alpha/search` 独立搜索能力）。

设置页运行独立的服务规划器（service planner），仅根据账号服务能力与凭据完整性解析各搜索后端的可用性（`disabled`、`missingCredential` 或 `accountUnsupported`），不依赖当前会话或角色路由：OpenAI 独立搜索优先选用所属账号目录中的 `gpt-6-sol`（不存在时取首个有效模型），DeepSeek 独立搜索直接调用原生工具接口而无需绑定模型。实际会话轮次执行时，再根据当前对话模型是否支持函数调用（function calling）决定是否为本轮注册对应的独立搜索工具；OpenAI 独立搜索、DeepSeek 原生搜索与托管搜索互不抢占（多后端仲裁规则见 [06](./06-model.md)）。

## 20.13 LSP 自定义服务器配置

用户在 `[lsp.servers.<server_id>]` 表中声明自定义语言服务器：每个条目必须配置 `command` 与非空 `language_ids`，可选配置 `args`、`detection`（工作区检测文件名或单段通配符，缺省为始终匹配）、`extensions`（文件扩展名列表）、`display_name` 与 `operations`（支持的 `lsp_query` 操作子集，缺省支持全部操作）。示例如下：

```toml
[lsp.servers.purelang]
command = "purelang-lsp"
args = ["--stdio"]
language_ids = ["purelang"]
detection = ["pure.toml"]
extensions = [".purelang"]
```

该配置段与 `pl-lsp` 内置目录合并；若 `server_id` 或 `language_ids` 与内置或其他自定义服务器冲突，配置校验直接返回类型化错误并保留原配置。自定义服务器绑定通用命令驱动（通过 `<command> --version` 探测环境，无自动修复语义，运行与路由契约见 [21](./21-lsp.md)）。

## 20.14 独立设置变更命令

配置变更按最小业务资源拆分为独立的类型化命令（typed command）：账号实例编辑、默认账号切换、账号删除、单个工作模式路由的模型或推理强度、单个智能体角色的模型或推理强度、系统指令字段、技能字段、单个 MCP 服务、通用设置字段、OpenAI 搜索字段以及 DeepSeek 搜索与抓取两个独立开关。所有命令均携带 `expectedSettingsRevision` 并由同一运行时命令锁执行 CAS 校验；桥接层与本地回环 HTTP 统一通过 `PUT /api/v1/settings/field`（承载 `SettingsFieldUpdate`）与对应资源端点处理，单字段更新请求严禁顺带覆写同页其他未修改字段的旧副本。启动期在线模型目录观察属于独立的命令通道与修订水位（仅推进 `modelCatalogRevision`），不阻塞设置变更命令。

## 20.15 模型标识迁移与账号隔离目录

配置结构版本 `22` 将模型对象中的 `slug` 统一迁移为 `model_id`，完整保留标识值、账号与凭据关联、连接方式覆盖及压缩阈值覆盖；旧字段仅在版本迁移边界解码。账号隔离目录以 [06](./06-model.md) 为准，工作模式不再限制可选模型集合。已知版本迁移若发生失败，将以独立的 `Migration` 错误沿启动链路传播并保留原文件供用户修正，绝不转入持久化数据损坏的自动重置流程。

## 20.16 自定义工作模式存储

自定义工作模式保存在数据根目录的 `modes/` 子目录下，每个 `<mode-id>.json` 文件保存一份完整的工作模式文档（执行字段与状态图约束见 [11](./11-thread-mode.md)，画布布局元数据独立于执行定义）。系统提供 JSON Schema 与显式校验命令；JSON 格式仅用于配置创作与落盘，运行时与传输层统一使用类型化 DTO。

配置所有者在启动、保存、删除与显式重载时访问该目录，日常查询仅读取已发布的不可变快照。保存与删除采用目录修订号 CAS、同一串行命令通道与原子文件替换，内置工作模式 ID 受写保护。显式重载会先完整读取并校验所有文件，任一文件损坏均保留上一份有效目录而不静默跳过坏文件。自定义工作模式上限为 **128 个**，单个 JSON 文件上限为 **256 KiB**，画布布局最多包含 **32 个节点**（节点坐标必须为有限浮点数且绝对值不超过 `1,000,000`）。启动时若检测到损坏的工作模式文件，将阻止启动并保留原文件，不触发产品数据库自动重置。

## 20.17 图像生成配置边界

图像生成能力不属于用户手工配置项，而是由目录声明的协议端点服务能力（`Images` 方言、生图模型前缀与首选模型）、当前在线模型目录观察以及账号凭据可用性共同决定（运行语义见 [06](./06-model.md) §6.13）。当前版本不提供独立的生图开关、模型选择器、尺寸或质量偏好设置或专用代理服务器地址，配置文件中也不保存第二份生图模型名单。覆盖了自定义 `base_url` 的账号继续沿用目录声明（将 `Images` 路径追加至该 `base_url` 前缀），并复用同一账号的系统凭据或环境变量令牌；凭据缺失时仅使生图工具不予注册，不产生报错弹窗，也不影响该账号下对话模型与其他工具的正常使用。
