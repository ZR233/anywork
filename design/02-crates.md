# 02 - Crate 边界

本文是仓库内各 crate 职责划分与依赖方向的唯一权威源；其他文档仅通过链接引用本文，不重复定义。

## 2.1 依赖方向

```text
pl-studio-bridge / pl-studio-server → pl-studio-runtime
pl-studio-runtime → pl-core / pl-model / pl-acp / pl-tool / pl-protocol / pl-trace
pl-model → pl-core
pl-tool → pl-core / pl-model
pl-trace → pl-core
```

核心依赖约束如下：
- `pl-model` 不依赖 `pl-tool`；`pl-tool` 消费 `pl-model` 已解析的账号能力与模型路由。
- `pl-core` 不依赖 `pl-protocol`、`pl-model`、`pl-tool`、`pl-trace`、`pl-output` 或 Studio 层组件（含测试依赖）。新增概念须先甄别是否属于通用的会话线程编排；账号、工具和产品专属概念分别归入对应适配层，不得通过 `pl-core` 门面镜像导出。
- 工作区完整成员清单以根目录 `Cargo.toml` 为准；Flutter 应用目录本身不是 Cargo 工作区成员，其 Rust 桥接库 `pl-studio-bridge` 单独纳入工作区。
- 厂商协议的 HTTP 客户端（模型目录发现、文件上传与图像生成）归属 `pl-model`，与账号配置、协议端点、模型目录及凭据解析保持同源，并由 `pl-model` 公开 API 的集成测试覆盖；`pl-tool` 仅负责参数校验、结果编排与媒体文件归档，不维护第二套协议或凭据逻辑。
- ACP 是外部智能体接入协议，不属于原生模型的 HTTP 协议族。`pl-acp` 消费宿主提供的受监督字节流，负责 ACP 握手协商、认证请求与类型化结果解析；它不依赖 Studio、`pl-model` 或 `pl-tool`，不读取产品配置与凭据，也不直接创建操作系统进程。Studio 层负责装配进程监督器，管理接入配置、固定 1.4.1 版本的官方服务端准备、启动资格与认证流程；固定厂商版本策略不下沉到通用 `pl-acp` 协议库，协议库仅校验宿主显式传入的期望服务端版本，并在版本不匹配时拦截后续认证与会话请求（详见 [28](./28-acp.md)）。

## 2.2 稳定职责

Rust 库 crate 统一使用 `pl-` 前缀；Flutter 桌面应用的 Dart 包名为 `anywork`，纯 SDK 客户端包名为 `anywork_client`。

| Crate | 核心职责与所有权边界 |
| --- | --- |
| `pl-core` | 上下文、模型、工具与会话线程的通用契约，内存线程所有者、当前状态检查点、不可变效果（effect），以及与产品无关的 `Session` 内容分页、尾部订阅与详情读取 |
| `pl-model` | 账号配置、厂商协议与传输层、模型目录、配置值对象、路由解析、厂商图像 API、媒体编码、提示缓存、用量计量及核心模型会话适配 |
| `pl-acp` | 外部智能体的 ACP 协商与认证协议、类型化请求结果及错误定义；不持有产品业务状态或操作系统进程 |
| `pl-provider-fixture` | 独立的本地环回（loopback）模拟模型与外部平台协议对端（peer）、严格请求校验、场景控制与环境证据采集；不实现被测产品业务逻辑 |
| `pl-tool` | 文件读写、命令执行、SSH、Git、LSP、MCP、技能、网络搜索、图像生成与展示、用户交互、笔记、待办（todo）、轮次完成、多智能体协作与机器人会话工具 |
| `pl-protocol` | Studio 与外围适配器共用的产品线协议（wire）、DTO、错误信封与业务状态类型 |
| `pl-trace` | 核心效果与调用记录的只读诊断及用量投影 |
| `pl-lsp` | 语言服务器连接、二进制探测与协议通信 |
| `pl-output` / `pl-patch` / `pl-skill-core` | 终端输出截断算法、补丁（patch）解析规则、技能元数据解析与路径规范化规则 |
| `pl-remote-helper` | 跨端复用的进程监督、流式读写、输出捕获写入与资源计费组件；Linux 远端辅助进程仅持有物理句柄、偏移量回执、未确认输出及实例租约 |
| `pl-studio-runtime` | TOML/SQLite 持久化与核心时间线存储适配、产品条目投影、项目管理、智能体预设、工作模式/工作流/计划状态机、子智能体协调、外部机器人原生接入与会话映射、资源租约，以及根会话/子会话/冷恢复的统一线程装配 |
| `pl-studio-bridge` / `pl-studio-server` | 同一 Studio 运行时的 FRB 桌面桥接适配与本地 HTTP 服务端适配 |
| `pl-xtask` | 轻量工程命令编排；仅在执行验收命令时按需通过子进程调用独立验收工具，自身不链接 Studio 运行时、模型层或数据库 |
| `pl-studio-acceptance` | 隔离的 GUI 与产品 API 人工验收工具、规范配置构造、模拟账号与模拟平台协调、数据库故障注入观察与验收证据采集 |
| `pl-dev-support` | 工程工具共享的仓库路径解析、命令执行与平台进程树生命周期管理；不依赖 Studio、模型层、数据库或模拟服务 |

### 工程与测试工具边界

工程工具间的依赖方向固定为：
- `pl-xtask → pl-dev-support`
- `pl-studio-acceptance → pl-dev-support / pl-studio-runtime / pl-model / pl-provider-fixture`

`pl-xtask` 与 `pl-studio-acceptance` 仅通过命令行子进程调用交互，不建立 Cargo 编译期依赖。验收所需的数据库依赖归属 `pl-studio-acceptance`，日常工程命令不会触发 Studio 运行时编译；GUI 构建、人工验收与全工作区检查各自按需编译目标组件。模拟平台服务 `pl-provider-fixture` 独立于被测 Studio 及其私有协议模块，仅提供受控网络环境与请求证据，不代替被测产品执行授权校验、幂等去重、线程映射或发送结果判定（详见 [24](./24-testing.md) 与 [27](./27-bots.md)）。

### 内核与远程工具职责切分

`pl-core` 不内置默认工具安装、账号配置、MCP 目录、产品工作集或旧版引擎门面。工具实例通过不透明注册句柄向线程转移所有权（见 [09](./09-tool-runtime.md)），模型实例通过核心模型会话契约注入；底层共享的物理服务通过显式租约复用，不同线程之间不共享可变工具实例。

SSH 远程开发场景中，技能发现、递归复制所需的目录遍历，以及目录选择过滤与排序由宿主侧 `pl-tool` 统一编排；远端 `pl-remote-helper` 仅返回单层目录分页与文件元数据事实。模型自主文件搜索遵循 [工具运行时](./09-tool-runtime.md#97-文件读取缓存与工作区纪元epoch) 的显式命令契约。本地与远程命令执行复用 `CommandProcessManager` 与 `ManagedWorker` 的生命周期边界；HTTP/2 通信统一使用 `h2` 组件，不自行维护平行的帧编解码器。

## 2.3 存储与投影

活动线程的内存状态是执行期的唯一事实源：
- **`pl-core` 存储契约**：默认纯内存运行，负责导出当前检查点与不可变效果，并通过 `Session` 统一合并最近内存缓存、活动条目、待落盘事实与历史分页查询。`pl-core` 不依赖产品协议，仅定义按身份与顺序查询的抽象存储接口，同时提供通用的 SQLite 会话存储实现及类型化的检查点/效果查询能力。
- **Studio 产品层投影与持久化**：负责将核心事实投影为产品条目，并管理产品配置与扩展业务状态。历史分页、尾部订阅和字段详情统一由 `Session` 内容设施提供，Studio 不另建 GUI 专用历史缓存或消息交接链；浏览冷历史不会激活模型会话、工具实例或线程执行所有者。
- **统计与跨层类型导入**：可丢弃的调用统计由全局 `calls.sqlite` 独立写入。Studio 通过通用的扩展 CAS 接口保存业务状态并提交模型上下文投影，桌面界面仅消费规范的产品 DTO。账号配置、工具配置与业务协议分别从 `pl-model`、`pl-tool` 与 `pl-protocol` 直接导入，不经由 `pl-core` 镜像中转。

存储与内核契约详见 [15](./15-session-storage.md) 与 [16](./16-core-contracts.md)。
