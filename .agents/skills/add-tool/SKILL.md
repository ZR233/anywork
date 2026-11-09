---
name: add-tool
description: Use when implementing, registering, migrating, or testing a 糊来帮 tool with pl-agent-tool and the Thread-owned RuntimeTool binding.
---

# 添加或迁移工具

通用声明与消费契约归 `pl-agent-tool`，独立工具位于 `code/tools/`，`pl-tool` 负责 Anywork 宿主适配和必要运行基础设施，Plan/workflow 等产品工具归 Studio；core 保留上下文、注册、冻结、授权与退休治理。依赖与行为见 `design/02-crates.md`、`design/09-tool-runtime.md`、`design/16-core-contracts.md`，独立作者与宿主分工见 `code/tools/README.md`，接口示例见 `code/pl-agent-tool/README.md`。

## 作者与声明

- 静态工具按身份独立 crate，自己拥有声明、校验、领域编排与结果；动态 MCP 按适配器组织，不按远端名称造包。独立工具及支持层不得传递依赖 core/model/Studio/`pl-tool`；用领域能力注入，不把 `CallContext`/`ToolOutput` 搬进接口库，也不把完整旧工具 execute 作为宿主回调。
- 普通 JSON 作者使用 `#[pl_agent_tool::tool_args]` 与 `#[pl_agent_tool::tool(name = "...")]`，或手写 `typed::TypedTool`；宏只生成参数派生与 RPITIT + Send 转发，不装箱、spawn 或赋予权限。工具可以持有业务服务，无需无关的 Debug/Clone/Serialize 约束。
- `ToolDefinition` 是名称、描述、完整 JsonSchema/Text/Grammar 输入和可选输出 schema 的唯一作者声明。静态 typed 与动态 Rust Args 共用 `typed::input_schema_for`，在绑定时生成一次；MCP 使用冻结的远端完整 schema。不在生产作者中构造 ToolSpec；`pl_model::completion::tool_definition_to_spec` 是唯一模型投影入口。
- `typed::decode_json` 解码原文并保留实际字段/索引路径、JSON source 和尾部检查。Schema 生成不执行所有 JSON Schema 约束，业务检查仍在 handler。普通 flatten/map 直接遵循 Serde；严格未知字段且复用共享业务结构时，以私有非 flatten wire + From 适配，不扫描 schema properties。
- exec 专属诊断、原始补丁、动态 MCP 和 ordinary/review finish 等特殊路径直接实现 `pl_agent_tool::Tool`，持有不可变 Definition，不增加第二套消费契约或宽泛参数兜底。

## 准备、附着与注册

1. 独立作者使用领域上下文、结果与错误；宿主静态适配后再注册。宿主中返回原生 ToolOutput/ToolError 的适配器用 `pl_tool::binding::prepare_native_tool`；普通 Serialize 输出用 `prepare_json_tool`，显式选择 context/error 映射。独立应用用 `typed::prepare_json`，无需依赖 core 或 RMCP。
2. 使用 `binding::prepare_registration` 先完成模型投影、原 opaque 声明编码和内部 ID 校验，再创建/移动服务实例。prepared adapter 的 attach 不失败，全部静态包装完成后只调用一次 `ToolHandle::new`；由 `PreparedRegistration::attach` 接管固定 `RuntimeTool`。core-only 消费方直接准备其不透明声明。
3. 所有控制、曝光、授权和调度 builder 仍在 Registration。内部 tool_id 与模型名不要求相同。消费实例的 registration 便利方法只能接收已准备材料，不能在错误路径 drop 活资源。
4. 在 StudioThreadFactory/Assembler 中显式装配 root、child 与恢复工具；每 Thread 独占实例和命令管理器，共用物理服务使用隔离租约。动态刷新保留稳定授权身份；声明、执行代次与权限身份分别处理，冻结旧调用继续持有旧租约并接受撤销检查。

## 输出、失败与控制

- native helper 原样通过 ToolOutput 和已有 ToolError，包括 observed_output；禁止再次 ToolError::new 包装已有错误。副作用后失败用 with_output 保存观测，不提交迟到控制。
- 私有后端错误在宿主边界保留原始 typed 值及显式受信访问入口；对外标准 source 链、序列化和 Debug 只含安全诊断。保留原始来源不等于把凭据或私有远端诊断沿错误链写入模型与历史。
- 普通 JSON helper 仅在 handler 成功后编码一次，同一文本构造 application/json@1 payload 与 Text context；不使用 Opaque context，也不猜测 content/message/path。编码失败保留 JsonOutputError 的阶段与 serde source，明确可能已有副作用，不重执行。
- 完整 payload 与实际 delivered_context 分别保存；预览、命令 capture 或临时路径不能冒充可靠资源。重开只读原保存材料，不按当前 Args/Output 重新解码或调用当前渲染器。
- 结束 Turn、CAS、交互、发现、等待和取消必须显式注册授权并返回类型化控制。JSON 字段、名称、schema 或 MCP annotations 都不授予权限。Note/Todo/Skill 状态从 CallContext 冻结扩展计算候选，不维护第二份可写状态。

## 生命周期与执行边界

工作区、命令、路径、文件权限、LSP、MCP、SSH 与归档由工具后端负责；文件许可不隐含 exec/Git/MCP 权限。CallContext 由宿主分配，参数不扩大能力。

Handle 不可 Clone、不实现工具 trait、不在 Drop 自动关闭。原 core owner/lease 负责停止准入、等待在途、catch execute/close future 构造与轮询、收束拒绝候选，并保留 close 失败的原实例重试；不能以强引用计数替换显式 lease 计数，不在注册锁内 await/IO/外部回调。

MCP 固定原 server/raw name/generation/turn lease，已接受请求继续等待并保存结果；close 只释放该工具租约，不 shutdown 共享 runtime。媒体先归档精确字节，失败保存收到结果与原错误，不重发调用。hosted 工具由 model 处理，无本地占位 executor。

## 验证

通过 Cargo 完整依赖闭包检查独立工具和共享支持，包括可选特性、平台、构建与测试依赖；workspace 外下游真实消费与调用，避免特性合并掩盖耦合。不能用仅迁移 schema 或新增壳包代替行为独立；原权限与生命周期证据仍在宿主边界验证。

先编译公开 API 示例再迁移相应生产路径。新库无特性、typed、typed+macros、重命名下游及必要 compile-fail 分别验证，workspace 特性合并不证明基础消费方独立。

按风险复用真实 Thread 的注册替换、冻结授权、控制、取消和关闭证明，不以 Tool::execute 直调替代。新 binding 的持久化证明应穿过 Thread、原 writer、close/join 与重开冷读，核对原字节、完整 delivery、错误、展示 marker 与不重执行；MCP 用真实本地 peer，Linux-only 零用例不算覆盖。

人工 fixture 区分 accepted 与终态，按精确任务身份等待结果，不以固定延时、放宽断言或强制生产前台化制造成功。工程入口见 AGENTS.md；真实 provider 操作仍需显式授权。
