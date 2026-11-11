# 02 - Crate 边界

本文是仓库内各 crate 职责划分与依赖方向的唯一权威源；其他文档仅通过链接引用本文，不重复定义。

## 2.1 依赖方向

```text
pl-studio-bridge / pl-studio-server → pl-studio-runtime
pl-studio-runtime → pl-core / pl-model / pl-acp / pl-tool / pl-protocol / pl-trace
pl-model → pl-core
pl-tool → pl-core / pl-model
pl-tool → 独立工具 crate → pl-agent-tool / 最小领域支持
pl-core / pl-model / pl-tool / pl-studio-runtime → pl-agent-tool
pl-agent-tool（macros 特性）→ pl-agent-tool-macros
pl-lsp → pl-remote-helper
pl-trace → pl-core
```

核心依赖约束如下：
- `pl-model` 不依赖 `pl-tool`；`pl-tool` 消费 `pl-model` 已解析的账号能力与模型路由。
- `pl-agent-tool` 拥有供应商无关的可执行工具声明与消费接口，基础特性不依赖其他 Anywork crate、RMCP、Tokio 或网络运行时；可选 `typed` 特性增加 Serde/Schemars 作者适配，可选 `macros` 特性增加薄过程宏。`pl-agent-tool-macros` 不反向依赖接口库。core 与 model 只启用基础消费契约，原生作者所在的 tool 与 Studio 显式启用作者特性。
- 独立工具按能力家族组成 crate，同家族工具用模块组织，拥有各自声明、参数校验、领域执行编排与结果；不机械按每个工具名称拆包。MCP 动态工具与资源门面同属 MCP 家族，不按远端目录名称创建静态包。家族及其独立支持层不得直接或传递依赖 `pl-tool`、`pl-core`、`pl-model` 或 Studio；必要的算法、SDK 与领域能力接口不属于宿主依赖。产品 DTO、注册、授权、任务交付与历史保存不进入独立工具的公开契约。
- `pl-tool` 是 Anywork 工具宿主适配及运行基础设施，不是独立工具的依赖入口。它将冻结的调用事实和受限能力传给工具，并将领域结果适配为内核输出；配置、凭据解析、工作区选择、持久化及产品事件仍归 Studio。共享支持只承载实际复用的文件、进程、媒体或服务能力，不建立通用产品上下文、第二套状态、注册表或调度器。
- `pl-core` 不依赖 `pl-protocol`、`pl-model`、`pl-tool`、`pl-trace`、`pl-output` 或 Studio 层组件（含测试依赖）。新增概念须先甄别是否属于通用的会话线程编排；账号、工具和产品专属概念分别归入对应适配层，不得通过 `pl-core` 门面镜像导出。
- 工作区完整成员清单以根目录 `Cargo.toml` 为准；Flutter 应用目录本身不是 Cargo 工作区成员，其 Rust 桥接库 `pl-studio-bridge` 单独纳入工作区。
- 厂商协议的 HTTP 客户端（模型目录发现、文件上传与图像生成）归属 `pl-model`，与账号配置、协议端点、模型目录及凭据解析保持同源，并由 `pl-model` 公开 API 的集成测试覆盖；`pl-tool` 仅负责参数校验、结果编排与媒体文件归档，不维护第二套协议或凭据逻辑。
- 原生账号的 OAuth/OIDC 协议、身份校验与请求凭据刷新归属 `pl-model`；Studio 装配受保护存储并持有登录操作、编辑意图绑定、配置提交及关闭责任。认证不会引入第二个模型执行器，公共状态继续通过 `pl-protocol` 向 HTTP、FRB 和 Client 发布，具体认证契约见 [20.18](./20-config.md#2018-openai-api-与-chatgpt-订阅认证)。
- ACP 是外部智能体接入协议，不属于原生模型的 HTTP 协议族。`pl-acp` 消费宿主提供的受监督字节流，负责 ACP 握手协商、认证及业务会话的类型化请求与有序更新；它不依赖 Studio、`pl-model` 或 `pl-tool`，不读取产品配置与凭据，也不直接创建操作系统进程。Studio 层负责装配进程监督器，管理接入配置、固定 1.4.5 版本的官方服务端准备、启动资格与认证流程；固定厂商版本策略不下沉到通用 `pl-acp` 协议库，协议库仅校验宿主显式传入的期望服务端版本，并在版本不匹配时拦截后续认证与会话请求（详见 [28](./28-acp.md)）。`pl-protocol` 可精确依赖同次锁定的官方 `agent-client-protocol-schema` 纯数据类型，承载 ACP 内容块、会话更新、权限及配置载荷；不依赖 ACP 连接或驱动实现。HTTP 使用该官方序列化形状，FRB 与 Client 在各自边界做薄类型转换，不用 JSON 字符串或另写协议解析器替代类型契约。

## 2.2 稳定职责

Rust 库 crate 统一使用 `pl-` 前缀；Flutter 桌面应用的 Dart 包名为 `anywork`，纯 SDK 客户端包名为 `anywork_client`。

| Crate | 核心职责与所有权边界 |
| --- | --- |
| `pl-agent-tool` | 独立工具声明、拥有型且返回 Send future 的消费契约、唯一动态擦除句柄，以及可选的 typed 参数、schema 与原始错误保留适配；不持有注册表、调度、授权或资源退休状态机 |
| `pl-agent-tool-macros` | 参数派生与 typed 工具转发薄宏；复用接口库的作者适配，不生成调度、授权、任务或关闭机制 |
| `pl-core` | 上下文、模型与会话线程的通用契约，Anywork 工具上下文与结果特化、注册/冻结/授权/退休治理，内存线程所有者、当前状态检查点、不可变效果（effect），以及产品无关的 `Session` 原子完成集合、发布顺序、pending、统一分页与冻结详情读取 |
| `pl-model` | 账号配置、厂商协议与传输层、模型目录、配置值对象、路由解析、厂商图像 API、媒体编码、提示缓存、用量计量及核心模型会话适配 |
| `pl-acp` | 外部智能体的 ACP 协商、认证与业务会话协议，类型化请求、有序更新及错误定义；不持有产品业务状态或操作系统进程 |
| `pl-provider-fixture` | 独立的本地环回（loopback）模拟模型与外部平台协议对端（peer）、严格请求校验、场景控制与环境证据采集；不实现被测产品业务逻辑 |
| 独立工具家族 crate | 文件、命令、Git、LSP、MCP、搜索、媒体与文件展示、技能、机器人各自聚合相关工具，以模块保存各工具的声明、校验、领域编排、结果与错误；通过 `pl-agent-tool` 被独立宿主消费，跨家族只共享必要的窄领域支持 |
| `pl-tool` | Anywork 工具宿主适配、受限本地/SSH/容器后端与共享服务所有权、内核结果及控制映射；保留用户交互、笔记、待办、轮次完成、任务治理和多智能体等宿主控制工具 |
| `pl-protocol` | 多个 crate 或产品适配边界实际共享的产品线协议（wire）、DTO、错误信封与业务状态类型；`session` 模块定义 `SessionId`/`SessionDescriptor`/目录行 `SessionDirectoryRow`，`agent` 模块定义 `AgentId`/`AgentDescriptor`/`AgentDefinitionSnapshot` 与封闭后端绑定 `AgentBinding`（`Native`/`Acp`） |
| `pl-trace` | 核心效果与调用记录的只读诊断及用量投影 |
| `pl-lsp` | 语言服务器连接、二进制探测与协议通信；通过 `pl-remote-helper` 复用原生进程树所有权与异步管道驱动 |
| `pl-output` / `pl-patch` / `pl-skill-core` | 终端输出截断算法、补丁（patch）解析规则、技能元数据解析与路径规范化规则 |
| `pl-remote-helper` | 跨端复用的进程监督、流式读写、输出捕获写入与资源计费组件；Linux 远端辅助进程仅持有物理句柄、偏移量回执、未确认输出及实例租约 |
| `pl-studio-runtime` | TOML/SQLite 持久化与完成历史存储适配、产品完成事实及真实来源生命周期、唯一 Native 读取分类与活动快照、项目管理、智能体预设、工作模式/工作流/计划状态机、子智能体协调、机器人接入与会话映射，以及会话作用域内的成员资源所有权、Native 统一装配和关闭（见 [14](./14-runtime-host.md)） |
| `pl-studio-bridge` / `pl-studio-server` | 同一 Studio 运行时的 FRB 桌面桥接适配与本地 HTTP 服务端适配 |
| `pl-xtask` | 轻量工程命令编排（含 `test-project` 桌面/原生套件）；仅在执行验收命令时按需通过子进程调用独立验收工具，自身不链接 Studio 运行时、模型层或数据库 |
| `pl-studio-acceptance` | 隔离的 GUI 与产品 API 人工验收工具（`manual-gui --preset`）、规范配置构造、模拟账号与模拟平台协调、数据库故障注入观察与验收证据采集 |
| `pl-dev-support` | 工程工具共享的仓库路径解析、命令执行与平台进程树生命周期管理；不依赖 Studio、模型层、数据库或模拟服务 |

Native 完成记录的读取分类由 Runtime 唯一确定，Core 只比较不透明 hint 并在原发布边界分配 seq/run；原 writer 保存不可变记录和两个段索引，不持久化展示组。Flutter 原 controller 按明确呈现类别与 run.start_seq 唯一组合代表卡，SDK 不组合，Widget 不重写分类；段详情沿 Run 独立读取。完整所有权与读取契约见 [26](./26-timeline-content.md)，存储迁移见 [17](./17-studio-storage.md)。

### 共享类型与实现类型

类型按领域所有者和实际消费边界归属，不以 `pub`、可序列化或包含“协议”字样作为进入 `pl-protocol` 的依据。仅供一个业务 crate 使用的请求、内部事件、分页游标布局和控制协议由该 crate 维护；同一 package 的库、二进制及测试共享的定义也留在该 package。产品对外只传递不透明游标时，编解码和游标内部结构归分页服务所有者。

共享关系包括公共字段、枚举载荷、函数签名和序列化结构的传递使用。HTTP、FRB 等产品适配边界发布的契约及其成员，不因只有一个直接构造者而视为私有实现；迁移成员必须与父契约和依赖方向一起核对。

同一领域含义和序列化契约只维护一份定义，消费者直接使用所有者的类型，不通过 JSON 往返转换在重复定义之间搬运数据。独立工具拥有其输入与结果契约，宿主只添加路由、授权和配置等必要适配；不同业务含义、生命周期或历史迁移责任的相似结构保持各自边界，不为减少结构体数量强行合并。

### 工程与测试工具边界

工程工具间的依赖方向固定为：
- `pl-xtask → pl-dev-support`
- `pl-studio-acceptance → pl-dev-support / pl-studio-runtime / pl-model / pl-provider-fixture`

`pl-xtask` 与 `pl-studio-acceptance` 仅通过命令行子进程调用交互，不建立 Cargo 编译期依赖。验收所需的数据库依赖归属 `pl-studio-acceptance`，日常工程命令不会触发 Studio 运行时编译；GUI 构建、人工验收与全工作区检查各自按需编译目标组件。模拟平台服务 `pl-provider-fixture` 独立于被测 Studio 及其私有协议模块，仅提供受控网络环境与请求证据，不代替被测产品执行授权校验、幂等去重、线程映射或发送结果判定（详见 [24](./24-testing.md) 与 [27](./27-bots.md)）。

### 内核与远程工具职责切分

`pl-core` 不内置默认工具安装、账号配置、MCP 目录、产品工作集或旧版引擎门面。工具实例通过不透明注册句柄向线程转移所有权（见 [09](./09-tool-runtime.md)），模型实例通过核心模型会话契约注入；底层共享的物理服务通过显式租约复用，不同线程之间不共享可变工具实例。

SSH 远程开发场景中，技能发现、递归复制所需的目录遍历，以及目录选择过滤与排序由宿主侧 `pl-tool` 统一编排；远端 `pl-remote-helper` 仅返回单层目录分页与文件元数据事实。模型自主文件搜索与读取遵循 [工具运行时](./09-tool-runtime.md#97-文件发现与读取归属命令工具) 的显式命令契约。本地与远程命令执行复用 `CommandProcessManager` 与 `ManagedWorker` 的生命周期边界；HTTP/2 通信统一使用 `h2` 组件，不自行维护平行的帧编解码器。

## 2.3 存储与投影

活动线程的内存状态是执行期的唯一事实源：
- **`pl-core` 存储契约**：默认纯内存运行，导出检查点与不可变效果；`Session` 统一读取尚未提交的不可变完成项与持久历史，完成时分配发布序号，提交后回收 pending。它不拥有活动预览、产品封口语义或展示分组，也不依赖产品协议；通用 SQLite 会话存储及检查点/效果查询保持独立职责。
- **Studio 产品层投影与持久化**：拥有业务完成语义、可变执行事实与实时活动，一次准备完成项后原子发布，并将同一批次交既有 writer 与 checkpoint 同事务保存。历史统一读模型与实时事件见 [26](./26-timeline-content.md)，不另建 GUI 历史缓存；冷读不激活模型、工具或执行所有者。
- **统计与跨层类型导入**：可丢弃的调用统计由全局 `calls.sqlite` 独立写入。Studio 通过通用的扩展 CAS 接口保存业务状态并提交模型上下文投影，桌面界面仅消费规范的产品 DTO。账号配置、工具配置与业务协议分别从 `pl-model`、`pl-tool` 与 `pl-protocol` 直接导入，不经由 `pl-core` 镜像中转。

存储与内核契约详见 [15](./15-session-storage.md) 与 [16](./16-core-contracts.md)。
