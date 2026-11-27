---
name: add-tool
description: Use when implementing, registering, migrating, or testing a 糊来帮 tool with pl-agent-tool and the Thread-owned RuntimeTool binding.
---

# 添加或迁移工具

通用声明与消费契约归 `pl-agent-tool`，独立工具位于 `code/tools/`，`pl-tool` 负责 Anywork 宿主适配和必要运行基础设施，Plan/workflow 等产品工具归 Studio；core 保留上下文、注册、冻结、授权与退休治理。依赖与行为见 `design/02-crates.md`、`design/09-tool-runtime.md`、`design/16-core-contracts.md`，独立作者与宿主分工见 `code/tools/README.md`，接口示例见 `code/pl-agent-tool/README.md`。

## 作者与声明

- 独立工具按能力家族组成 crate，同家族命令用模块组织，自己拥有声明、校验、领域编排与结果，不机械为每工具造包；动态 MCP 与资源门面同家族，不按远端名称造包。家族与独立支持层不得传递依赖 core/model/Studio/`pl-tool`；家族专属支持内聚，真正跨家族共享才抽取窄支持层。用领域能力注入，不把 `CallContext`/`ToolOutput` 搬进接口库，也不把完整旧工具 execute 作为宿主回调。
- 普通 JSON 作者使用 `#[pl_agent_tool::tool_args]` 与 `#[pl_agent_tool::tool(name = "...")]`，或手写 `typed::TypedTool`；宏只生成参数派生与 RPITIT + Send 转发，不装箱、spawn 或赋予权限。工具可以持有业务服务，无需无关的 Debug/Clone/Serialize 约束。
- `ToolDefinition` 是名称、描述、完整 JsonSchema/Text/Grammar 输入和可选输出 schema 的唯一作者声明。静态 typed 与动态 Rust Args 共用 `typed::input_schema_for`，在绑定时生成一次；MCP 使用冻结的远端完整 schema。不在生产作者中构造 ToolSpec；`pl_model::completion::tool_definition_to_spec` 是唯一模型投影入口。
- 可编排工具明确声明真实程序值的输出 schema，包括可检查业务失败的形状。复用 `typed::output_schema_for<R: JsonSchema>()` 按序列化方向生成，与输入的反序列化方向区分；不得用任意对象声明兜底。输出声明描述作者数据，不描述任务台账、归档或模型文字。
- `typed::decode_json` 解码原文并保留实际字段/索引路径、JSON source 和尾部检查。Schema 生成不执行所有 JSON Schema 约束，业务检查仍在 handler。普通 flatten/map 直接遵循 Serde；严格未知字段且复用共享业务结构时，以私有非 flatten wire + From 适配，不扫描 schema properties。
- exec 专属诊断、原始补丁、动态 MCP 和 ordinary/review finish 等特殊路径直接实现 `pl_agent_tool::Tool`，持有不可变 Definition，不增加第二套消费契约或宽泛参数兜底。

## 准备、附着与注册

1. 独立作者使用领域上下文、结果与错误；宿主静态适配后再注册。宿主中返回原生 ToolOutput/ToolError 的适配器用 `pl_tool::binding::prepare_native_tool`；普通 Serialize 输出用 `prepare_json_tool`，显式选择 context/error 映射。独立应用用 `typed::prepare_json`，无需依赖 core 或 RMCP。
2. 使用 `binding::prepare_registration` 先完成模型投影、原 opaque 声明编码和内部 ID 校验，再创建/移动服务实例。prepared adapter 的 attach 不失败，全部静态包装完成后只调用一次 `ToolHandle::new`；由 `PreparedRegistration::attach` 接管固定 `RuntimeTool`。core-only 消费方直接准备其不透明声明。
3. 所有控制、曝光、授权和调度 builder 仍在 Registration。内部 tool_id 与模型名不要求相同。消费实例的 registration 便利方法只能接收已准备材料，不能在错误路径 drop 活资源。
4. 在 StudioThreadFactory/Assembler 中显式装配根会话、子会话与恢复工具。每个 Thread 独占实例和命令管理器，共用物理服务使用隔离租约。Native 工具目录、执行绑定与事实通过 `InstallRuntimeBundle` 同时安装，从同一发布读取当前绑定。普通刷新复用仍有效的授权与物理租约，明确撤权后由原所有者取消并收束对应任务。
5. 可共享宿主工具进入所属能力家族的公共注册入口，由 Native/MCP 消费器准备各自投影并附着实例。新增工具不要再写一份 ACP 名称分支、参数 schema 或 execute 闭包；业务上下文只包含真实所需能力，Native 状态效果仍交原 owner。不要用假 CallContext 借执行入口，也不要在通用接口库增加产品注册表。

## 输出、失败与控制

- 作者提供 `ToolResult<C>`：`data` 是程序值，`content` 是模型内容，`details` 只存确有诊断、界面或保存用途的附加材料。Core `ToolOutput` 承载这个结果和独立可信控制。`ToolData::Absent`、JSON null、空数组、空对象和字符串分别保留；看起来像 JSON 的字符串仍是字符串。Lua 直接读取和修改普通值，输出由脚本的 print/return 选择，不反解正文或替换成原呈现。
- native helper 原样通过 ToolOutput 和已有 ToolError，包括 observed_output；禁止再次 ToolError::new 包装已有错误。已执行且有可检查业务结果的失败用 `ToolError::operation`，调用无法完成用 Invocation 类别并在有观测时使用 `with_output`。子任务真实失败与 Lua 能否处理返回值分别记录，不 downcast 某一种命令错误，不提交迟到控制。
- 嵌套调用消费 owner 提交后的 `ToolCompletion`，先判断真实终态，再读取可选 output 和原 typed error。取消／中断仍是错误，活跃父脚本可以从 `err.output` 读取部分数据；父脚本自己取消仍需退出并收束。没有完成事实的准入／提交故障不伪装成作者结果。
- 外部 MCP 的程序值只来自 `structuredContent`。无输出 schema 的成功回执缺结构值时，Lua 返回 nil；已声明 schema 的成功回执缺值时明确失败。`isError=true` 保持调用失败，`pcall` 的 `err.output` 只在有已观察结构值时提供；不能把协议 content record 冒充程序值。同步生产 SDK 与工具说明，不保留旧回执 fallback 教学。
- 私有后端错误在宿主边界保留原始 typed 值及显式受信访问入口；对外标准 source 链、序列化和 Debug 只含安全诊断。保留原始来源不等于把凭据或私有远端诊断沿错误链写入模型与历史。
- 普通 JSON helper 从业务返回值生成 JSON data 与默认 Text，复用共用呈现，不创建旧 `application/json@1` 结果信封，也不猜测 content/message/path。编码失败保留 JsonOutputError 的阶段与 serde source，明确可能已有副作用，不重执行。
- 完整作者结果与实际 delivered_context 保留各自含义，等价内容可共享不可变材料。状态发布不能覆盖已保存的完成结果；有界缓存裁剪后通过原保存 owner 回读。预览、命令 capture 或临时路径不能冒充可靠资源，完整命令捕获由 `details.command` 接入资源保留。重开只读原保存材料，不调用当前渲染器。
- 图片通过显式 `ContextContent::Media` 交付，先依据已提交终态确认允许交付；取消、中断及调用失败的媒体保留在原件，不自动进入父脚本结果。普通 Resource 仅在脚本输出明确选择其 ID 时交付，不凭 MIME 自动展示；领域 Opaque 不猜媒体。需要专用产品呈现时，将明确详情交给所属 artifact，例如 `fileDisplay`。详情不自动进入模型上下文，不再把专用 JSON 回执编码成 Opaque 结果信封。
- 普通模型调用消费 content，Hosted 调用消费 data，必须依据实际 caller，不能用工具的 Hosted 资格替代。同一声明允许两类 caller 时一起验证；Responses 的 output_schema 仅约束字符串中的 JSON，普通内容可使用官方内容数组，不能靠放宽 schema 或解析正文规避协议边界。具体映射遵循 `design/06`。
- 结束 Turn、CAS、交互、发现、等待和取消必须显式注册授权并返回类型化控制。JSON 字段、名称、schema 或 MCP annotations 都不授予权限。Note/Todo/Skill 状态从 CallContext 冻结扩展计算候选，不维护第二份可写状态。

## 生命周期与执行边界

Host MCP 暴露工作区工具时，复用普通会话的独立作者、冻结工作区/执行端口和必要任务基础，
不要在 MCP handler 中重写命令、文件或 Git 算法，也不要构造 Native Thread/Turn 来借工具。
目录及执行绑定同源，非 JSON 输入只在传输边界做原文适配。受理后的任务、进程、捕获与归档
必须由真实成员 owner 持有并参与关闭；MCP 断开只结束观察，不等于业务取消或退出。
本机 ACP cwd 与 SSH 业务路径分开，具体契约见 `design/28`，不把提示词或工具前缀当作沙箱。

MCP 输入投影使用统一策略而非工具名特例：JSON 保留完整 schema，必要封装以及 Text/Grammar
使用声明的 `input` 载体；保留 `$defs`、`$ref` 的原根作用域和严格未知字段检查。先完成静态
适配，再做唯一句柄擦除；声明准备失败不能消耗活实例。结果保留原业务失败及已观测输出，
不公开私有错误链，不因传输、编码或归档失败重执行工具。

Host MCP 同时投影作者 content 与 data。只在存在 data 时提供 `structuredContent`，用明确的对象载体 `{"result": data}`；输出 schema 描述相同载体并保留作者 schema 的独立引用根。普通 Native 协议读取 content，Hosted 程序调用读取 data 与配套 schema；历史缺值走明确缺值分支，不解析文字补造。任何返回字段都不能代替真实错误状态或授权。

工作区、命令、路径、文件权限、LSP、MCP、SSH 与归档由工具后端负责；文件许可不隐含 exec/Git/MCP 权限。CallContext 由宿主分配，参数不扩大能力。

Handle 不可 Clone、不实现工具 trait、不在 Drop 自动关闭。原 core owner/lease 负责停止准入、等待在途、catch execute/close future 构造与轮询、收束拒绝候选，并保留 close 失败的原实例重试；不能以强引用计数替换显式 lease 计数，不在注册锁内 await/IO/外部回调。

MCP 固定原 server/raw name/generation/turn lease，已接受请求继续等待并保存结果；close 只释放该工具租约，不 shutdown 共享 runtime。媒体先归档精确字节，失败保存收到结果与原错误，不重发调用。hosted 工具由 model 处理，无本地占位 executor。

## 验证

通过 Cargo 完整依赖闭包检查独立工具和共享支持，包括可选特性、平台、构建与测试依赖；workspace 外下游真实消费与调用，避免特性合并掩盖耦合。不能用仅迁移 schema 或新增壳包代替行为独立；原权限与生命周期证据仍在宿主边界验证。

先编译公开 API 示例再迁移相应生产路径。新库无特性、typed、typed+macros、重命名下游及必要 compile-fail 分别验证，workspace 特性合并不证明基础消费方独立。

按风险复用真实 Thread 的注册替换、冻结授权、控制、取消和关闭证明，不以 Tool::execute 直调替代。新 binding 的持久化证明应穿过 Thread、原 writer、close/join 与重开冷读，核对原字节、完整 delivery、错误、展示 marker 与不重执行；MCP 用真实本地 peer，Linux-only 零用例不算覆盖。

跨语言回执验证使用生产序列化的实际结构，核对 data 的缺失/null、content 的媒体类别和 details 的产品字段。合法领域 Opaque 的 content 仍是 UTF-8 字符串，不能在客户端夹具中擅自替换成对象；旧工具结果信封仅由正式迁移解释。分别手写两端看似一致的对象夹具不能证明互通。

覆盖非零结果、调用失败前输出、并行输入顺序、后台受理与完成、stdin 接纳与实际消费，以及小预算下的恢复身份。跨 exec、缓存淘汰及关闭重开后按同一任务读原件，独立核对原字节和业务操作只发生一次；不能重跑原业务命令制造恢复证据。普通短结果不携带空诊断或内部保存包装，截断与捕获失败必须保留事实和恢复入口。

人工 fixture 区分 accepted 与终态，按精确任务身份等待结果，不把后台操作强制前台化来绕过交付语义。工程入口见 AGENTS.md；真实 provider 操作仍需显式授权。
