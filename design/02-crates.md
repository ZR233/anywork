# 02 - Crate 边界

本文是仓库内各 crate 职责划分与依赖方向的唯一权威源；其他文档仅通过链接引用本文，不重复定义。

## 2.1 依赖方向

```text
pl-studio-bridge / pl-studio-server / pl-studio-cli → pl-studio-runtime
pl-studio-runtime → pl-core / pl-model / pl-acp / pl-tool / pl-protocol
pl-studio-runtime → pl-studio-update / pl-studio-statistics / pl-lifecycle
pl-studio-bridge → pl-studio-update / pl-studio-statistics / pl-lifecycle
pl-studio-server / pl-studio-cli → pl-studio-update
pl-studio-cli → pl-tool
pl-studio-update → pl-remote-helper
pl-model / pl-tool / pl-studio-statistics → pl-protocol
pl-model → pl-model-runtime / pl-model-types / pl-model-wire / 厂商协议 crate / pl-model-auth
pl-model-runtime → pl-core / pl-model-types / pl-model-wire / pl-model-openai-wire
厂商协议 crate → pl-model-types / pl-model-wire（OpenAI 系另依赖 pl-model-openai-wire；pl-model-gemini 独立不依赖 pl-model-openai-wire）
厂商协议 example → pl-model-runtime (dev-dependency)
pl-studio-runtime → pl-model-auth
pl-tool → pl-core / pl-model
pl-tool → 独立工具 crate → pl-agent-tool / 最小领域支持
pl-core / pl-model / pl-tool / pl-studio-runtime → pl-agent-tool
pl-agent-tool（macros 特性）→ pl-agent-tool-macros
pl-lsp / pl-tool / pl-studio-runtime → pl-remote-helper → pl-patch
pl-trace → pl-core
```

核心依赖约束如下：
- `pl-model` 不依赖 `pl-tool`；`pl-tool` 消费 `pl-model` 已解析的账号能力与模型路由。
- `pl-agent-tool` 拥有供应商无关的可执行工具声明、消费接口及作者结果容器；程序值、模型内容和可选详情分别表达，内容元素由实际领域实例化，不引入 Core、产品或存储依赖。基础特性不依赖其他 Anywork crate、RMCP、Tokio 或网络运行时；可选 `typed` 特性增加 Serde/Schemars 作者适配，可选 `macros` 特性增加薄过程宏。`pl-agent-tool-macros` 不反向依赖接口库。core 与 model 只启用基础消费契约，原生作者所在的 tool 与 Studio 显式启用作者特性。
- `pl-lifecycle` 只负责作用域、资源构造交接、取消、清理完成观察与原实例重试，不依赖业务 crate、产品协议、存储或界面；调用方仍负责领域资源的关闭顺序。同步解绑回调须快速、非阻塞，截止时刻不能中断已经开始的同步回调；可能耗时的清理使用异步资源。
- 独立工具按能力家族组成 crate，同家族工具用模块组织，拥有各自声明、参数校验、领域执行编排与结果；不机械按每个工具名称拆包。MCP 动态工具与资源门面同属 MCP 家族，不按远端目录名称创建静态包。家族及其独立支持层不得直接或传递依赖 `pl-tool`、`pl-core`、`pl-model` 或 Studio；必要的算法、SDK 与领域能力接口不属于宿主依赖。产品 DTO、注册、授权、任务交付与历史保存不进入独立工具的公开契约。
- `pl-tool` 是 Anywork 工具宿主适配及运行基础设施，不是独立工具的依赖入口。它将冻结的调用事实和受限能力传给工具，并将领域结果适配为内核输出；配置、凭据解析、工作区选择、持久化及产品事件仍归 Studio。共享支持只承载实际复用的文件、进程、媒体或服务能力，不建立通用产品上下文、第二套状态、注册表或调度器。
- `pl-core` 不依赖 `pl-protocol`、`pl-model`、`pl-tool`、`pl-trace`、`pl-output` 或 Studio 层组件（含测试依赖）。新增概念须先甄别是否属于通用的会话线程编排；账号、工具和产品专属概念分别归入对应适配层，不得通过 `pl-core` 门面镜像导出。
- 工作区完整成员清单以根目录 `Cargo.toml` 为准；Flutter 应用目录本身不是 Cargo 工作区成员，其 Rust 桥接库 `pl-studio-bridge` 单独纳入工作区。
- 厂商目录解析和独立服务客户端归属对应协议 crate。协议无关的模型绑定契约、HTTP/SSE 传输与 `WireCodec`/`WireStreamDecoder` 抽象归属 `pl-model-wire`；Chat Completions 与 Responses 编解码归属 `pl-model-openai-wire`；原生 Gemini REST（`generateContent` / `streamGenerateContent`）独立归属 `pl-model-gemini` 且不依赖 `pl-model-openai-wire`；`pl-model` 负责账号路由和选择厂商实现，`pl-model-runtime` 仅通过 `WireCodec` trait 驱动 HTTP/SSE 协议族（并保留 Responses WebSocket 专用通道），不依赖具体厂商协议 crate。协议客户端测试覆盖公开 HTTP 边界，`pl-tool` 负责参数校验、结果编排和媒体文件归档。
- 原生账号的 OAuth/OIDC、身份校验和刷新会话归属 `pl-model-auth`。OpenAI 协议通过 `pl-protocol::credential` 的凭据接口读取当前令牌，Codex 配额查询由 `pl-model-openai` 执行。Studio 装配受保护存储并持有登录操作、编辑意图绑定、配置提交及关闭责任。认证不会引入第二个模型执行器，公共状态由 `pl-studio-runtime` 向 HTTP、FRB 和 Client 发布，具体认证契约见 [20.18](./20-config.md#2018-openai-api-与-chatgpt-订阅认证)。
- ACP 是外部智能体接入协议，不属于原生模型的 HTTP 协议族。`pl-acp` 消费宿主提供的受监督字节流，负责 ACP 握手协商、认证及业务会话的类型化请求与有序更新；它不依赖 Studio、`pl-model` 或 `pl-tool`，不读取产品配置与凭据，也不直接创建操作系统进程。Studio 层负责装配进程监督器，管理接入配置、受管 Antigravity `1.x`（`>= 1.5.2, < 2.0.0`）官方服务端准备、启动资格与认证流程；固定厂商版本策略不下沉到通用 `pl-acp` 协议库，协议库仅校验宿主显式传入的期望服务端版本，并在版本不匹配时拦截后续认证与会话请求（详见 [28](./28-acp.md)）。`pl-studio-runtime` 可精确依赖同次锁定的官方 `agent-client-protocol-schema` 纯数据类型，承载 ACP 内容块、会话更新、权限及配置载荷；协议 DTO 不耦合 ACP 连接实现。HTTP 使用该官方序列化形状，FRB 与 Client 在各自边界做薄类型转换，不用 JSON 字符串或另写协议解析器替代类型契约。

## 2.2 稳定职责

Rust 库 crate 统一使用 `pl-` 前缀；Flutter 桌面应用的 Dart 包名为 `anywork`，纯 SDK 客户端包名为 `anywork_client`。

| Crate | 核心职责与所有权边界 |
| --- | --- |
| `pl-agent-tool` | 独立工具声明、拥有型且返回 Send future 的消费契约、唯一动态擦除句柄，以及可选的 typed 参数、schema 与原始错误保留适配；不持有注册表、调度、授权或资源退休状态机 |
| `pl-agent-tool-macros` | 参数派生与 typed 工具转发薄宏；复用接口库的作者适配，不生成调度、授权、任务或关闭机制 |
| `pl-lifecycle` | 弱作用域能力、父子资源归属、同步解绑、异步构造接管、关闭回执与失败原实例重试；不拥有业务数据或业务关闭顺序 |
| `pl-core` | 上下文、模型与会话线程的通用契约，Anywork 工具上下文与结果特化、注册/冻结/授权/退休治理，内存 Thread owner、完整 Current 与有界 effect window；产品 History、Work/Single 分组和 GUI 读取归 Studio |
| `pl-model` | 账号配置、有效模型目录、正式路由与协议装配 |
| `pl-model-types` | 通用消息、流事件、模型元数据和开放协议标识 |
| `pl-model-runtime` | Core 会话适配、请求执行、连接和续接、重试、取消、附件缓存与计量 |
| `pl-model-wire` | 协议无关模型绑定、HTTP/SSE 传输、`WireCodec`/`WireStreamDecoder` 与供应商错误策略契约；公共错误上下文和等待提示归一化，具体业务码归各厂商协议 crate |
| `pl-model-openai-wire` | OpenAI Chat Completions 与 Responses 线协议编解码与共享请求构建 |
| `pl-model-gemini` | 原生 Gemini REST（`streamGenerateContent`、Vertex AI API Key 与 Gemini API）独立编解码与模型目录 |
| `code/model-protocols/` 中的其他厂商 crate | 目录解释、内置模型声明与服务实现，OpenAI 系派生协议组合 `pl-model-openai-wire` |
| `pl-model-auth` | 模型账号认证协议、身份值对象与凭据刷新会话；存储由宿主注入，不拥有产品登录操作、配置提交或模型执行 |
| `pl-acp` | 外部智能体的 ACP 协商、认证与业务会话协议，类型化请求、有序更新及错误定义；不持有产品业务状态或操作系统进程 |
| `pl-provider-fixture` | 独立的本地环回（loopback）模拟模型与外部平台协议对端（peer）、严格请求校验、场景控制与环境证据采集；不实现被测产品业务逻辑 |
| 独立工具家族 crate | 文件、命令、Git、LSP、MCP、搜索、媒体与文件展示、技能、机器人各自聚合相关工具，以模块保存各工具的声明、校验、领域编排、结果与错误；通过 `pl-agent-tool` 被独立宿主消费，跨家族只共享必要的窄领域支持 |
| `pl-tool` | Anywork 工具宿主适配、统一执行器的工作区/工具策略、容器窄后端与共享服务所有权、内核结果及控制映射；保留用户交互、笔记、待办、轮次完成、任务治理和多智能体等宿主控制工具 |
| `pl-protocol` | 多个同级 crate 直接同时依赖的最小跨层基础原语：统一错误与供应商失败分类（`PureError`/`Result`/`ProviderFailure*`/`RetryDisposition`/`StateError`）、稳定标签枚举契约（`LabeledEnum`）、跨层身份标识（`SessionId`/`AgentId`/`ThreadId`）、首包观测来源（`FirstOutputSource`）以及 `pl-tool` 与 Studio 同时直接依赖的协作工作区/派发路由原语；单归属 crate 或细分领域协议直接归属对应 owner crate 与领域子模块 |
| `pl-trace` | 核心效果与调用记录的只读诊断及用量投影 |
| `pl-lsp` | 语言服务器连接、二进制探测与协议通信；通过 `pl-remote-helper` 复用原生进程树所有权与异步管道驱动 |
| `pl-output` / `pl-patch` / `pl-skill-core` | 终端输出截断算法、补丁（patch）解析规则、技能元数据解析与路径规范化规则 |
| `pl-remote-helper` | 统一执行机器、受管进程、目标文件与 HTTP 字节接口；本地执行与 Linux 前台服务共用原生所有者。私有执行协议不依赖产品 DTO，不持有工作区、Thread 或跨连接恢复状态 |
| `pl-studio-mcp` | 传输无关的 Host MCP 服务、工具消费投影与领域调用端口、本地 IPC 契约及客户端，以及宿主原生 stdio 服务程序；不依赖 Studio runtime、Flutter/FRB、`pl-core`、`pl-model` 或 `pl-tool`，不拥有产品存储、成员目录或业务调度。Studio 实现该端口并持有原实例 IPC 服务 |
| `pl-studio-update` | 稳定更新清单与来源校验、可信下载、安装缓存锁、长度/摘要/签名流式验证、只读安装包租约和安装器交接；不依赖 Studio runtime、模型、工具、配置或数据库，不持有产品更新状态机，也不决定应用退出 |
| `pl-studio-statistics` | 模型性能快照与分页契约、同源不可变统计材料的发布、读取信用及关闭生命周期；不依赖 Studio runtime、模型、工具或数据库，不聚合计费事实，也不读取调用库。Runtime 原统计所有者串行提交单调版本并发布材料 |
| `pl-studio-runtime` | Studio 传输无关产品协议、会话目录与成员定义（`SessionDirectoryRow`、`AgentDefinitionSnapshot`、`AgentBinding`）、TOML/SQLite 持久化与完成历史存储适配、产品完成事实及真实来源生命周期、唯一 Native 读取分类与活动快照、项目管理、智能体预设、工作模式（`mode`）/工作流（`workflow_tool`）/计划（`plan_tool`）状态机、子智能体协调、机器人接入与会话映射，以及会话作用域内的成员资源所有权、Native 统一装配和关闭（见 [14](./14-runtime-host.md)）。公开签名引用的下层类型由本 crate 重导出，供上层适配器直接使用。 |
| `pl-studio-bridge` / `pl-studio-server` | 同一 Studio 运行时的 FRB 桌面桥接适配与本地 HTTP 服务端适配 |
| `pl-studio-cli` | `anywk` 非交互式生产宿主；命令参数、输入预检、原生任务终态观察与退出编排，不拥有第二套智能体循环，见 [29](./29-cli-harbor.md) |
| `pl-xtask` | 轻量工程命令编排（含 `test-project` 桌面/原生套件）；仅在执行验收命令时按需通过子进程调用独立验收工具，自身不链接 Studio 运行时、模型层或数据库 |
| `pl-studio-acceptance` | 隔离的 GUI 与产品 API 人工验收工具（`manual-gui --preset`）、规范配置构造、模拟账号与模拟平台协调、数据库故障注入观察与验收证据采集 |
| `pl-dev-support` | 工程工具共享的仓库路径解析、命令执行、同次 CI 构件身份校验与平台进程树生命周期管理；不依赖 Studio、模型层、数据库或模拟服务 |

Native 完成记录的读取分类由 Runtime 唯一确定，Core 只比较不透明 hint 并在原发布边界分配 seq/run；原 writer 保存不可变记录和两个段索引，不持久化展示组。Flutter 原 controller 按明确呈现类别与 run.start_seq 唯一组合代表卡，SDK 不组合，Widget 不重写分类；段详情沿 Run 独立读取。完整所有权与读取契约见 [26](./26-timeline-content.md)，存储迁移见 [17](./17-studio-storage.md)。

### 共享类型与实现类型

类型按领域所有者和实际消费边界归属，不以 `pub`、可序列化或包含“协议”字样作为进入 `pl-protocol` 的依据。只有多个无直接隶属关系的 crate 同时直接依赖的基础原语才进入 `pl-protocol`；若某定义仅由单一根 crate 直接拥有或生产，再经其公开接口交付给下游消费者（如 `pl-studio-bridge`、`pl-studio-server`、`pl-studio-cli`），则直接定义在该拥有者 crate 的对应细分领域模块中，并在拥有者公开签名边界按需重导出，避免下游额外依赖 `pl-protocol`。仅供单个适配层使用的传输请求体（如纯 HTTP 路由查询/命令封装）、内部事件、分页游标布局和控制协议直接留在该适配层或拥有者 crate 维护；同一 package 的库、二进制及测试共享的定义也留在该 package。产品对外只传递不透明游标时，编解码和游标内部结构归分页服务所有者。

共享关系包括公共字段、枚举载荷、函数签名和序列化结构的传递使用。HTTP、FRB 等产品适配边界发布的契约及其成员，不因只有一个直接构造者而视为私有实现；迁移成员必须与父契约和依赖方向一起核对。

同一领域含义和序列化契约只维护一份定义，消费者直接使用所有者的类型，不通过 JSON 往返转换在重复定义之间搬运数据。独立工具拥有其输入与结果契约，宿主只添加路由、授权和配置等必要适配；不同业务含义、生命周期或历史迁移责任的相似结构保持各自边界，不为减少结构体数量强行合并。

### 工程与测试工具边界

工程工具间的依赖方向固定为：
- `pl-xtask → pl-dev-support`
- `pl-studio-acceptance → pl-dev-support / pl-studio-runtime / pl-model / pl-tool / pl-provider-fixture`

`pl-xtask` 与 `pl-studio-acceptance` 仅通过命令行子进程调用交互，不建立 Cargo 编译期依赖。验收所需的数据库依赖归属 `pl-studio-acceptance`，日常工程命令不会触发 Studio 运行时编译；GUI 构建、人工验收与全工作区检查各自按需编译目标组件。模拟平台服务 `pl-provider-fixture` 独立于被测 Studio 及其私有协议模块，仅提供受控网络环境与请求证据，不代替被测产品执行授权校验、幂等去重、线程映射或发送结果判定（详见 [24](./24-testing.md) 与 [27](./27-bots.md)）。

### 内核与远程工具职责切分

`pl-core` 不内置默认工具安装、账号配置、MCP 目录、产品工作集或旧版引擎门面。工具实例通过不透明注册句柄向线程转移所有权（见 [09](./09-tool-runtime.md)），模型实例通过核心模型会话契约注入；底层共享的物理服务通过显式租约复用，不同线程之间不共享可变工具实例。

SSH 远程开发场景中，技能发现与目录选择的过滤、排序由宿主侧 `pl-tool` 编排；文件接口增量交付单层目录项，同一目标内的递归复制在执行侧完成。模型自主文件搜索与读取遵循 [工具运行时](./09-tool-runtime.md#97-文件发现与读取归属命令工具) 的显式命令契约。本地与远程业务统一消费 `Executor / Command / Child`，产品 `CommandProcessManager` 保存任务、标准输入及有限预览，分别观察根退出与输出捕获完成；不恢复未知输出或重放命令。HTTP/2 通信统一使用 `h2` 组件。

## 2.3 存储与投影

活动线程的内存状态是执行期的唯一事实源：
- **`pl-core` 存储契约**：默认纯内存运行，提供完整 Current、可替换状态快照与有界 effect window。effect window 保存尚未交给产品 History 的 original observation cut；它不分配产品 event seq、不拥有 Work/Single 分组或 GUI 历史缓存。通用 SQLite/ColdStore 的独立 checkpoint/effect 契约仍可存在，但不作为 Native Current/History 的共同写链。
- **Studio 产品层投影与持久化**：Current assembler 拥有当前业务投影和有界正文/集合引用；History classifier 把可靠 effect 转成 schema 25 事件与不可变 body。Current writer 周期保存完整 `current.json`，带 original observation cut 的 effect 交给独立 HistoryChannel；二者不共同提交。Cold read 不激活模型、工具或执行 owner；展示合同见 [26](./26-timeline-content.md)。
- **统计与跨层类型导入**：可丢弃的调用统计由全局 `calls.sqlite` 独立写入。Studio 通过通用的扩展 CAS 接口保存业务状态并提交模型上下文投影，桌面界面仅消费规范的产品 DTO。账号模型契约、工具契约与 Studio 产品协议分别从 `pl-model`、`pl-tool` 与 `pl-studio-runtime` 导入；跨同级 crate 的共享基础原语归 `pl-protocol`，不经由 `pl-core` 镜像中转。


存储与内核契约详见 [15](./15-session-storage.md) 与 [16](./16-core-contracts.md)。

项目技能、会话临时目录、命令捕获归档和 Git 工作树分别由各自领域适配同一个具体执行器。`SshWorkspaceBinding` 只携带冻结端点事实与公共工作区执行绑定，不持有多套物理 owner。工作树的 Git 算法、common-dir/backlink 归属校验和未知副作用分类仍归 Studio；确认的 Git 元数据位于 checkout 外时，在同一执行器上打开独立的受限读取视图。

Lua 编排家族 `pl-tool-lua` 独立持有解释器、输入、计算环境、并发协调和有界输出。`pl-tool` 将其窄工具调用端口绑定到 Thread 的嵌套调用能力；core 只治理父子任务、冻结授权和可靠交付，不依赖 Lua 或解释工具声明。
