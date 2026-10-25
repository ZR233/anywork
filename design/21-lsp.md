# 21 - LSP 运行时与语义查询

## 21.1 目标与边界

`anywork` 的语言服务器协议（LSP）运行时为智能体提供代码语义查询能力，并向 Flutter 界面展示当前项目的最新已知（last-known）语言服务器状态。LSP 运行时仅驻留于本地宿主进程，不通过 MCP 暴露。语言服务器定义为数据驱动的目录（catalog）：内置目录收录已知语言服务器（当前内置 `rust-analyzer`），用户可在配置文件中声明自定义语言服务器（配置结构见 [20](./20-config.md) §20.13）。新增语言支持只需添加目录条目、驱动（driver）实现或用户配置，无需修改 `pl-core`，代码中亦不存在硬编码语言名称字面量或按语言分支的条件判断。

## 21.2 模块职责划分

`pl-lsp` 按职责边界组织为六个稳定的公开子域：
- **`catalog`**：语言服务器定义、用户配置合并、工作区匹配规则与内置条目。
- **`driver`**：环境探测、组件修复（repair）、启动命令解析与服务器专项初始化。
- **`host`**：工作区文件系统、进程宿主边界与本地子进程树托管。
- **`client`**：单语言服务器连接及其配置、文档同步、诊断收集、消息分发、JSON-RPC 通信、连接状态、传输层与 URI 转换边界。
- **`query`**：语义查询请求、源码位置、诊断信息与查询结果等纯领域契约。
- **`runtime`**：类型化错误、状态快照、能力集合与唯一注册表所有者（registry owner）。

模块依赖方向由 `query`/`runtime` 纯契约及 `catalog`/`driver`/`host` 边界指向 `client`，再由 `runtime` 统一组装；`client` 不反向依赖注册表编排逻辑，内部实现子模块保持私有。

## 21.3 服务器目录（Catalog）与驱动（Driver）

语言服务器定义为纯数据结构（序列化采用 `camelCase`），声明以下属性：
- 服务器标识（`serverId`）、展示名称（`displayName`）与支持的语言标识列表（`languageIds`）。
- 工作区检测规则：相对工作区根目录的文件名或单段通配符（glob），空列表表示始终匹配。
- 启动命令模板：可执行文件名与参数列表，当前占位符仅支持 `{workspaceRoot}`。
- 能力集合：支持的 `lsp_query` 操作子集，用于能力报告与查询路由校验。

重复的 `serverId` 或 `languageId` 冲突在配置解析阶段直接以类型化错误失败返回（fail-loud）。当同一 `languageId` 被多个语言服务器声明且同时匹配当前工作区时，路由层以类型化歧义错误拒绝请求并列出候选服务器，不按注册顺序或名称猜测；零匹配时返回列出当前可用语言的未知语言错误。未显式指定 `languageId` 的文件路径路由遵循相同原则：文件扩展名零匹配返回不可用（`unavailable`），唯一匹配路由至对应服务器，多个服务器声明同一扩展名时返回类型化路径歧义错误。

驱动层（`driver`）是语言服务器生命周期的唯一适配边界：环境探测（返回类型化就绪或缺失原因）、组件修复、进程启动参数解析与服务器特殊初始化（如 `rust-analyzer` 的客户端文件监控配置）由具体驱动实现提供；连接管理、底层传输与 JSON-RPC 请求转发则由通用 `client` 层统一实现。目录支持运行期开放扩展（内置定义、用户配置与宿主自定义共存），驱动采用原生异步特征（RPITIT，返回 `Send` Future，不使用 `#[async_trait]`）。`rust-analyzer` 的 `rustup` 探测、`missingServerComponent` 判定与 `rustup component add` 自动修复逻辑完全封装在 `rust-analyzer` 驱动内部；用户声明的自定义服务器绑定通用命令驱动（执行 `<command> --version` 探测，无组件修复语义）。注册表与路由层不包含任何特定语言的专项逻辑。

## 21.4 注册表所有者与命令查询分离（CQS）

注册表（registry）是语言服务器进程、连接、处理器、诊断信息、活动状态与状态快照的唯一所有者，对外提供六组边界原语：

```text
reconcileWorkspaceMembership(project)
probeLspServer(scope)
repairLspServer(serverId)
resetLsp(scope)
readLspState()
shutdownLsp()
```

其中 `scope` 可指定单个服务器、单个工作区或全部（`All`）：
- **工作区成员协调（`reconcileWorkspaceMembership`）**：仅规范化工作区根路径、按目录检测规则静态判定各服务器适用性（检测未命中的条目保留为 `Disabled` 成员供界面展示原因）、增删服务器定义并清理过期客户端；严禁在此步骤执行 `--version`、`rustup`、网络请求或启动语言服务器进程。
- **状态只读查询（`readLspState`）**：仅克隆所有者已发布的不可变快照。
- **环境探测（`probeLspServer`）**：执行驱动的环境探测（如运行 `rust-analyzer --version`）。当检测到缺失 `rustup` 组件时，驱动发布类型化的 `missingServerComponent` 错误（附带组件标签与修复说明），不自动执行安装。
- **组件修复（`repairLspServer`）**：仅接受处于 `missingServerComponent` 状态的服务器，委托对应驱动执行修复（如运行 `rustup component add rust-analyzer`），修复成功后自动重新执行环境探测；其他不可用状态一律拒绝修复请求。
- **按需启动与重置（`resetLsp`）**：语义查询（`lsp_query`）可按需启动已确认 `Available` 的语言服务器客户端，但不重新执行环境探测；启动失败时必须回写注册表可用性及错误状态，并发布 `LspStateChanged` 事件。`resetLsp` 对目标客户端执行 LSP `shutdown`/`exit` 握手，清空诊断、活动状态与消息处理器；若重置前服务器已启动则立即重启，若未启动则回到 `Available/Unstarted` 状态，不关闭注册表本身。
- **终态关停（`shutdownLsp`）**：进入不可恢复的终止状态，拒绝后续一切成员协调、探测、修复、重置与启动请求，仅允许读取已停止的最终快照。

## 21.5 并发控制、路径语义与进程生命周期

文件路径与文件 URI 严格遵循文件所属宿主声明的路径语义：远端 POSIX 路径的编码、解码、初始化、文档同步请求与诊断投影不得套用本地 Windows 路径规则，统一由共享地址组件负责转义，严禁手动拼接 URI 字符串。所有语言服务器进程确认退出后才释放所属宿主引用；关闭失败时保留原对象与关闭责任。远端宿主身份绑定存活的工作区租约实例：复用同一租约时保持宿主身份不变，新建连接或重新打开工作区时生成新身份，不将可复用的工作区编号当作宿主代次。

成员协调、环境探测、组件修复、重置与关停通过注册表生命周期锁串行化；在状态锁临界区内不等待环境探测、`rustup` 安装、客户端初始化或子进程退出。异步操作在启动时捕获操作 ID、期望修订号与配置指纹，过期结果不得覆盖较新状态。移除工作区或服务器时，先从内存状态中原子移出所有者，再在生命周期锁外等待子进程关闭。

所有探测、修复与语言服务器子进程统一经由 `pl-remote-helper` 的后台进程工厂启动（见 [05](./05-conventions.md) §5.5）：Windows 下隐藏控制台窗口并将进程树纳入作业对象（Job Object）；Unix 下使用独立进程组。关闭客户端时先执行标准 LSP `shutdown`/`exit` 握手，再等待完整子进程树退出，超时后强制终止并回收；`Drop` 实现仅作为最后兜底。

## 21.6 状态快照模型

LSP 状态快照采用可观察资源（`ObservedResource`）语义：`Loading` 与 `Failed` 不携带可用载荷，`Refreshing` 与 `Degraded` 保留最近一次已知健康状态（last-known health），`Stale` 表示期望成员集合已发生变更。每个语言服务器条目记录稳定的 `id`、`displayName`、扩展名与 `languageIds`，并以穷尽的状态联合体表达 `Checking`、`Available`、`Unavailable` 与 `Disabled` 四种状态。命令缺失（`missingCommand`）与组件缺失（`missingServerComponent`）作为 `Unavailable` 分支内部的类型化错误码表达，不额外设立平行的布尔或字符串字段。

仅 `Available` 分支携带检查时间戳、诊断计数以及 `Idle | Busy | Indexing` 活动状态联合体（其中 `title`、`message` 与 `percentage` 仅存在于 `Busy` 与 `Indexing` 状态）；`Unavailable` 分支携带检查时间戳与类型化错误；`Checking` 与 `Disabled` 分支仅携带说明信息。运行时快照中的活跃语言服务器计数仅统计处于 `Available` 状态的服务器。

## 21.7 智能体工具接入与界面投影

当目标工作区存在处于 `Available` 状态的语言服务器时，系统以能力接缝（capability seam）模式向智能体工具集原子注册两个常规即时（eager）工具：`lsp_capabilities` 与 `lsp_query`（不注册按语言命名的 `lsp_query_{language_id}`，也不使用延迟加载命名空间）。两个工具在构造时直接捕获同一个注册表、工作区与路径解析器实例：
- **`lsp_capabilities`**：根据“服务器目录 × 工作区检测 × 运行态”动态产出当前工作区可用的语言服务器、`languageId`、支持的操作列表与就绪状态。
- **`lsp_query`**：接收 `languageId`、`operation`（支持 `definition`、`references`、`hover`、`documentSymbol`、`workspaceSymbol`、`implementation`、`callHierarchy`、`diagnostics`）与查询参数，在运行期按目录路由至对应语言服务器；超出该服务器声明能力集的操作由路由层直接拒绝。

父智能体与子智能体可共用同一个注册表所有者，但必须在各自工具集中独立注册工具接缝；单个智能体的工具更新不得改变另一智能体已冻结的工具计划。输入路径先经工作区受限（workspace-only）的绝对路径解析；源码行列位置对外采用基于 `1` 的行号与字符偏移（1-based line/character），内部自动转换为 LSP 标准基于 `0` 的 UTF-16 偏移。

执行语义查询前，运行时向语言服务器发送 `textDocument/didOpen` 或 `textDocument/didChange` 同步文档内容；文件系统后端在构造时捕获注册表引用，在文件写入、移动或删除后通知已启动的语言服务器客户端并发送文件变更通知（watched-files notification）。Windows 扩展长度路径（verbatim path）在生成文件 URI 前自动转回常规盘符或 UNC 路径。遇到 `ContentModified` 或服务器启动初期的空结果时仅做有界重试，不伪造 `didChange` 通知。

会话运行时快照中的 `activeLspServers` 表示当前轮次实际冻结的语言服务器集合；产品级完整状态仅通过 `readLspState` 查询与 `LspStateChanged` 事件流交付。页面刷新、聚合快照读取、轮次创建与工具查询均不得隐式触发环境探测（probe）或组件修复（repair）。Flutter 的 LSP 设置页直接投影产品级密封状态（sealed state）：进入页面与点击刷新调用 `readLspState`；项目探测、组件修复（仅在 `Unavailable` 且错误码为 `lspComponentMissing` 时可用）以及工作区或服务器重置分别调用各自的类型化命令。服务器活动进度（`Idle`/`Busy`/`Indexing` 及百分比）随同一快照与事件流实时投影至设置页列表行与聊天主状态栏。

## 21.8 非目标

本模块不实现插件市场 LSP 推荐界面、终端输出展示或 IDE 虚拟文档 URI；除用户在配置文件中显式声明的自定义语言服务器外，不自动下载或安装任何语言服务器。`rust-analyzer` 的 `rustup` 组件安装必须由用户点击修复按钮显式触发 `repairLspServer` 命令执行。
