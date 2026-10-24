# 02 - Crate 边界

本文是 crate 划分与依赖方向的唯一权威源；其他文档只链接本文，不重复定义。

## 2.1 依赖方向

```text
pl-studio-bridge / pl-studio-server → pl-studio-runtime
pl-studio-runtime → pl-core / pl-model / pl-tool / pl-protocol / pl-trace
pl-model → pl-core
pl-tool → pl-core / pl-model
pl-trace → pl-core
```

model 不依赖 tool；tool 消费 model 已解释的 account 能力与路由。core 不依赖 pl-protocol、pl-model、pl-tool、pl-trace、pl-output
或 Studio，包括测试依赖。新增概念先确认是否属于通用 Thread 编排；account、工具和产品
专属概念分别归对应适配层，不借 core 门面镜像。完整成员清单以根
Cargo.toml 为准；Flutter 应用目录本身不是 workspace 成员，其 Rust 桥接 crate 单独纳入成员。

厂商协议的 HTTP 客户端（目录发现、文件与图像生成）归 pl-model：它们与账号配置、协议
endpoint、模型目录和凭据解析同源，并由 `pl-model` 公开入口的集成测试覆盖；工具层只做参数
校验、结果编排与媒体归档，不复制第二份协议或凭据事实。

## 2.2 稳定职责

库 crate 统一使用 `pl-` 前缀；Flutter 应用的 package 名是 `anywork`。

| crate | 所有权 |
| --- | --- |
| pl-core | context/model/tool/thread 通用契约、内存 owner、当前状态 checkpoint、不可变 effect，以及产品无关的 Session 内容分页、尾部订阅与详情读取 |
| pl-model | 账号配置与厂商协议/transport、模型目录、配置值对象、路由、provider 图像 API、媒体编码、缓存、usage 与核心模型会话适配 |
| pl-provider-fixture | 独立的 loopback 模型与外部平台协议 peer、严格请求校验、场景控制与环境证据，不实现被测产品业务 |
| pl-tool | 文件、命令、SSH、Git、LSP、MCP、Skill、搜索、图像生成与图像展示、交互、笔记、todo、完成、协作与机器人会话工具 |
| pl-protocol | Studio 与外围 adapter 使用的产品 wire、DTO、错误和业务状态类型 |
| pl-trace | core effect 与调用记录的只读诊断和用量投影 |
| pl-lsp | 语言服务连接、探测和协议 |
| pl-output / pl-patch / pl-skill-core | 输出算法、patch 规则、Skill 元数据与路径规则 |
| pl-remote-helper | 复用的进程监督、流读写、capture 写入、目录能力下的物理文件发布和资源计费组件；Linux helper 只拥有物理句柄、偏移回执、未确认输出及实例租约 |
| pl-studio-runtime | TOML/SQLite 持久化及 core 时间线存储适配、产品条目投影、项目、Profile、Mode/workflow/Plan、子代理协调、机器人原生接入与会话映射、资源租约与 root/child/恢复的唯一 Thread 装配 |
| pl-studio-bridge / pl-studio-server | 同一 Studio 运行时的 FRB / HTTP 适配 |
| pl-xtask | 轻量工程命令编排；按需通过子进程调用独立验收工具，不链接 Studio 运行时、模型或数据库 |
| pl-studio-acceptance | 隔离 GUI 与产品 API 人工验收、canonical 配置构造、模拟账号/平台协调、数据库故障观察与证据采集 |
| pl-dev-support | 工程工具共享的仓库路径、命令执行及平台进程树所有权，不依赖 Studio、模型、数据库或模拟账号 |

工程工具的依赖方向为 `pl-xtask → pl-dev-support`、
`pl-studio-acceptance → pl-dev-support / pl-studio-runtime / pl-model / pl-provider-fixture`。
xtask 对验收工具只有命令调用关系，不建立 Cargo 依赖；验收工具也不反向依赖 xtask。
验收所需数据库依赖归验收工具。普通工程命令不因验收能力而编译 Studio 运行时；GUI 构建
显式构建 bridge、验收显式构建验收工具以及全 workspace 检查仍正常编译各自所需组件。
平台 fixture 不依赖被测 Studio 或其私有协议模块；它提供独立网络环境和证据，不代替
生产授权、幂等、Thread 映射或发送结果判定。宿主隔离与人工验收边界见 [24](./24-testing.md)
和 [27](./27-bots.md)。

core 不提供默认工具安装、account 配置、MCP 目录、产品 working set 或旧引擎门面。工具实例通过
不透明注册句柄向 Thread 转移所有权（见 [09](./09-tool-runtime.md)）；模型通过核心模型会话契约
传入。共用物理服务通过明确租约共享，不共享可变 Thread 工具实例。

SSH 的递归扫描、glob、候选搜索、Skill 发现、目录选择过滤与排序均归 `pl-tool` 的 host 编排。
helper 仅返回单层目录迭代页及文件事实；本地和远程命令复用 `CommandProcessManager` 与
`ManagedWorker` 的业务和物理边界，HTTP/2 由 `h2` 唯一实现，不维护平行帧 codec。

## 2.3 存储与投影

Thread 内存是活动执行状态唯一事实源；core 默认纯内存，导出当前 checkpoint、不可变 effect，
并负责 Session 对最近缓存、活动条目、待保存事实和历史查询的统一合并。core 不依赖产品协议；
core 定义按身份与顺序查询的存储能力，并提供通用 SQLite session store 与 typed Thread checkpoint/effect 查询。
Studio 负责产品条目投影、产品配置和自己的持久化状态。历史页、尾部订阅和详情统一由 Session
内容设施提供，Studio 不能另建 GUI 专用历史缓存或消息交接链；冷历史浏览不激活模型、工具或执行 owner。可丢统计由全局 calls 库独立写入。Studio 使用
通用扩展 CAS 保存业务状态并提交其模型上下文投影；GUI 只消费 canonical 产品 DTO。Account 配置
从 model、工具配置从 tool、业务协议从 protocol 导入，不借 core 镜像导出。

契约详见 [15](./15-session-storage.md) 与 [16](./16-core-contracts.md)。文档定义边界；验收结果
以实际检查记录为准。
