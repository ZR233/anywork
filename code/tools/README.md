# 独立工具与宿主适配

本目录按能力家族组织 `pl-tool-<family>` crate，同家族工具放在各自模块，不为每个命令
创建独立包；动态 MCP 与资源门面同属 MCP 家族。架构边界见 [Crate 边界](../../design/02-crates.md) 和
[工具运行时](../../design/09-tool-runtime.md)。

| 目录 | Package | 范围 |
| --- | --- | --- |
| `filesystem` | `pl-tool-filesystem` | 补丁、写入、元数据、目录、删除、复制与移动 |
| `lua` | `pl-tool-lua` | Lua 编排、计算环境、并发和输出边界 |
| `command` | `pl-tool-command` | exec_command、stdin 与共用进程领域观测 |
| `git` | `pl-tool-git` | Git 系列与凭据、命令规划、结果 |
| `lsp` | `pl-tool-lsp` | 能力发现与查询 |
| `mcp` | `pl-tool-mcp` | 动态工具、资源与共用内容处理 |
| `search` | `pl-tool-search` | 搜索与抓取 |
| `media` | `pl-tool-media` | 模型读图、图像生成、用户文件展示 |
| `skill` | `pl-tool-skill` | 技能发现、读取、管理 |
| `bots` | `pl-tool-bots` | 机器人及会话读取、发送 |
| `support/media` | `pl-tool-media-support` | 跨 MCP/媒体家族共享的原字节、图像处理与归档端口，不含工具 |

## 作者契约

- 工具实现 `pl_agent_tool::Tool` 或 `typed::TypedTool`。输入、上下文、结果和错误是
  领域类型；不得依赖 `pl-tool`、`pl-core`、`pl-model`、Studio 或 FRB，包括传递依赖。
- 家族内每工具拥有唯一的参数/schema、语义校验和执行编排。成熟 SDK 和已有纯算法库继续复用，
  不复制协议、补丁匹配、图像解码、进程监督或授权机制。
- 家族专属领域类型与能力直接放在家族内；确实跨家族共享的能力才位于 `support/`。能力接口使用原生 RPITIT + Send；
  只暴露完成操作所需的事实和方法，不接收整个宿主上下文或通用“执行此工具”回调。
- 宿主负责读取配置、授权、冻结事实、持有服务和归档可靠输出；工具返回领域结果，
  由宿主适配为现有版本的 payload、模型上下文及控制效果。错误保留 source，
  副作用发生后的失败保留实际观测，禁止重执行来补偿编码或归档失败。
- 对外标准错误链可能被宿主持久化；原始后端来源仅可受信读取时，宿主需用安全诊断
  适配它，并以显式 typed 访问入口保留原始错误，不把私有 source 链暴露给历史或调试输出。

## 领域边界

| 领域 | 独立工具持有或接收 | 宿主保留 |
| --- | --- | --- |
| 文件 | 原始补丁或 typed 参数、受限文件能力、领域结果 | 路径/符号链接与写策略、调用级 grant、写锁；复用 `pl-patch` 唯一算法和 grammar |
| 命令 | 已校验输入、进程能力、原调用观测 | 同一个 Thread 进程管理器、接纳与期限、任务调度、归档/冷读/修复、停止并等待退出 |
| Git | 命令规划、结果整理、显式执行/凭据端口 | 工作树身份、授权及已解析凭据服务；不得复制凭据存储 |
| LSP | 查询参数、能力/查询端口 | 路径授权、服务器注册表与受监督进程树 |
| MCP | 完整冻结声明、原 server/raw name/generation 的租约、领域内容投影 | 配置与连接 owner、稳定授权身份、可靠媒体存储；单工具 close 仅释放自己的租约 |
| 搜索/生成 | 请求参数、已选定服务端口、冻结的必要上下文/图像限制 | 账号、凭据、hosted 选择与现有供应商 HTTP 客户端 |
| 媒体/技能/机器人 | 原字节或已授权候选事实、窄存储/文件/会话端口 | 产品资源表示、归档、技能激活效果、项目授权与产品状态 |

跨领域共享时，采用支持层拥有的类型，或由工具自身能力接口的关联类型表达宿主不透明值；
不要复制 `CallContext`、`ToolOutput`、`ResourceReference` 或全部产品 DTO。
任何取消都不自动等于物理退出；任何 accepted 都不自动等于副作用完成。

独立下游验证必须在 workspace 外解析依赖并实际调用工具，不能依赖 workspace
特性合并。依赖闭包检查与宿主集成证明缺一不可；工具声明不构成授权证明。

## 验证入口

从仓库根目录执行：

```sh
python3 .github/scripts/check_tool_boundaries.py
cargo check --locked --all-targets --manifest-path code/tools/fixtures/downstream/Cargo.toml --target-dir target/tools-downstream
cargo test --locked --manifest-path code/tools/fixtures/downstream/Cargo.toml --target-dir target/tools-downstream --test media_execution
```

依赖检查消费 Cargo 的全特性、全平台解析图，包括构建与测试依赖，并拒绝宿主依赖、
家族之间的工具包依赖及遗漏的 workspace 成员。重命名下游 fixture 独立解析所有家族，
用于证明公开接口的可消费性；它不替代各工具的行为测试和宿主的授权、归档、关闭证明。
跨工具的媒体联合行为测试也在该下游运行；家族内可直接测试多个模块，跨家族测试不得引入生产包之间的依赖。
