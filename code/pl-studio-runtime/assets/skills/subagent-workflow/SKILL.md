---
name: subagent-workflow
description: 当任务需要通过糊来帮 Agent Profile 使用子代理进行并行探索、独立实现或静态审查时使用。
category: agents
---

# 子代理协作

用户要求子代理、并行探索、跨 crate 分析、独立验证或按角色分工，且任务适合独立委派时使用。

主代理、机器人主代理、系统 child 与用户 child 使用同一种 Agent 定义和指令冻结模型；
`list_agent_profiles` 是该模型的 child 可配置/可派发视图，不是另一套 Agent 实现。
内置 child ID 来自本轮代码声明表，不能假定闭合名单或按固定 ID 推断能力。root 定义不进入
该目录、Agents 设置或 spawn schema；用户 TOML 只能定义 child，不能创建 root 或注入任意 root prompt。

## 选择 Profile

尚不清楚合适的 Profile 时，先调用 `list_agent_profiles`，再将选定的稳定 `profileId` 传给
`spawn_agent`。子代理创建时冻结创建指令、provider、model、effort 和物理工作区；后续
Profile 修改只影响未来创建的子代理。禁用或不可用的 Profile 不能派发。
选择时依据当代目录中 Profile 的名称、描述、适用任务与 workspace mode，并核对实际工具 schema；
不要把探索、实现、worktree 或审查永远绑定到某个固定 ID。

首次调用就使用工具 schema 的 camelCase 字段。标准形状如下：

- 当前 catalog 中满足只读探索职责且 workspace mode 合适的 Profile：按实际 schema 提供其 `profileId`、摘要和完整任务。
- workspace mode 为 `directory` 的 Profile 可接收最窄 `writablePaths`；共享目录有真实冲突或需物理隔离时，选择相应隔离 workspace mode 的 Profile。
- 独立审查选择具备审查职责且 workspace mode 为 `review` 的 Profile，并绑定真实执行者的 `reviewTargetAgentId`。

例如，当前目录中可能提供 `explorer`、`executor`、`worktree_executor` 和 `reviewer`；这些名称仅是随包声明的实例，不是固定扩展接口。协作派发只使用本轮目录实际可用的 Profile 与工具参数，不虚构当前目录未提供的角色或参数。若用户明确授权开发新的内置声明，应由有权限的实现者按统一声明模型完成；新增声明可增加 child 选项而无需改框架角色枚举或另维护 ID 清单。

固定分发沿用 Profile 的模型路由；自动分发由主智能体按任务为现有 Profile 选择合适模型。两种方式都不改变角色、权限或验收要求，固定模型能力不足时报告而不暗改路由。

每次派发必须提供简洁的 `taskSummary`，空白归一化后为 1–80 个 Unicode 字符，用作 GUI
子代理列表标题；`message` 包含完整任务。主代理和子代理在首次工具调用前、重要发现、阶段
切换、等待及阻塞等有意义的节点，用 1–3 句 commentary 汇报。

只发送 schema 声明的字段，不得改用 `profile_id` 或 `writable_paths`。只有 directory
Profile 接受 `writablePaths`，unrestricted 和 worktree Profile 不接受。子代理始终使用独立
上下文，`message` 必须自包含，不能依赖父会话历史。首次调用前确认 Profile、模式及
最窄目录范围。遇到类型化参数错误时修正 schema 用法，不重复原参数。刻意触发的目录边界
拒绝记为 `expected_rejection`，不得重试或通过 shell、Git、MCP 绕过。

随包内置声明的 child 身份、名称、用途、指令和 workspace mode 不可在普通协作中临时修改，可以禁用；其集合由
统一 Agent 声明的 child 视图决定。只有用户明确要求并授权产品开发新增内置声明时，才在 `src/agent/catalog.rs` 添加类型化声明项，
并在 `src/agent/prompts/*.md` 添加对应提示词；提示词通过 `include_str!` 编入二进制，运行期不读取
Agent 资源目录。`planner` 只保留为 root 的运行/历史标识，不是可派发 Profile，
不能派发或禁用，也不是全局模型路由；
历史 planner 子代理仅可读取，不可续跑。用户 Profile 按每个 Profile 一个 TOML 文件加载。
按能力选择 Profile，不能假定某个工作流阶段必然对应某个 Profile。

子代理不继承主 Thread Mode 的工作流工具或运行时状态。主代理只能查询及推进宿主已注册
的图；主代理和子代理都不能编译工作流定义。

## 子代理的临时文件

每个 child（包括执行审查职责的 Profile）使用自己最新 `studio.session-files` 事实中的 `scratch/`、`artifacts/` 和命令
输出目录，不从父代理或被审者的 Thread ID、home 路径和临时文件目录推导。共享 checkout 不
等于共享会话临时目录；跨代理交付须给出必要的产物路径和归属，不要求对方写入父会话 scratch。
directory 的业务 `writablePaths` 与本 Thread 的 scratch/artifacts 许可分开；只读角色、工作区
边界和禁区仍然有效，不能借临时目录许可扩大实现范围。不要把内部数据库、helper 共享资产、
安装的 Skill 或可靠资源目录当作临时工作区。

## 派发时机与工作区

`spawn_agent` 用于边界明确的异步任务。子代理始终使用独立上下文；独立探索可并行派发，由主代理
综合证据；需要检查实例时使用 `list_agents`，没有独立工作时使用 `wait`。真实依赖保持顺序，
所有权重叠的修改不并行。Task 的 `editing_documents` 阶段仅由主代理写入 `design/**`。

是否安排局部 review、何时审查、何时集成以及采用串行、并行、混合或批量方式，由主智能体按用户目标、真实依赖、写冲突、风险与效率决定；不要求每个执行者或 worktree 完成后都自动审查/集成。directory 改动已在当前共享工作区，不制造合入。用户授权范围内的集成、生成、全量验证或交付可明确委派给合适的现有执行者；普通编码任务不自行执行 Git。设计中标为待接入的 worktree 准入、清理目标不能当作已实现事实。

Task 模式根智能体仅负责澄清、只读探索委派、综合事实、维护架构/接口/数据结构约定、依赖与所有权、调度、裁决及验收判断；不得亲自编码或执行任何命令（包括只读 shell、Git 状态、版本及工具链探测），小任务也不例外。可直接读取文件和使用只读查询工具；需要命令取证时委派给合适的现有 Profile。所有业务实施均交由现有执行者，小任务可集中给一个执行者，工作量只影响组织方式。计划或派发可描述接口契约、签名和关键伪代码，但不得代写完整、可直接采用的业务实现或测试代码；实现由执行者编写。具体伪代码与实现步骤写入计划或派发消息，不沉入长期设计文档。Task 的最终整体代码审查和适用检查/功能验收由独立 reviewer 实际执行，根综合证据裁决。Profile 选择、审查范围和 Git 所有权分别明确，reviewer 不修改业务源码、Git 或真实用户配置；隔离验收交互属于允许的审查操作，但不得修改未经授权的外部系统；修改跟踪生成文件的操作交执行者，reviewer 核证。

执行者若发现路线、设计、接口、数据结构、业务语义、依赖、验收、工作区现场或 review 意见与实现有任何冲突、歧义或不确定，立即停止本轮实施、安全收束在途操作、保留现场并报告：原要求、事实与证据、冲突、影响、改动/在途状态及需决定事项。可另列建议、理由、收益风险和待验证假设，但不能先试做或把建议当裁定；等主智能体明确续跑后才继续。

Review 必须绑定实际目标与版本；派发时提供完整适用计划及调整、范围、执行者身份、基线/版本和验证证据。`reviewFeedback: toExecutor` 只能指向同父、同 root、同 project 的绑定执行者，授权在创建时冻结。reviewer 只给指定范围结论，可执行明确委派的只读命令、构建/测试和隔离验收，不写业务或 Git、不改真实用户配置或未经授权的外部系统；隔离验收交互属于允许的审查操作。只有 reviewer 可用 `finish_turn({message, review})` 提交 `approved | needsChanges | inconclusive`，摘要非空且不超过 512 个 Unicode 字符，`reviewedVersion` 非空且不超过 2048 个 Unicode 字符并标明真实版本身份；完整依据留在 `message`。自然 final、旧版本、缺字段、异常或未收束不能批准。reviewer 不直接给兄弟发 `send_message`；只有派发时明确授予 `reviewFeedback: toExecutor` 且宿主确认有效 `needsChanges` 才会回送。目标忙碌、新任务、关闭或结果不确定时不打断、不猜测，由宿主报告父代理。回送不表示修复完成，建议不等于裁决。父报告含紧凑结论、摘要、版本、身份和回执，完整审查按需读取；返修后是否复审由主智能体按受影响范围决定。

子代理轮次仅结束执行，不意味着交付被接受、资源已关闭或现场可清理；Task 根智能体按实际依赖等待未交付报告，无独立工作时使用 `wait`，超时不代表完成。所有实际交付、适用 review 与返修结束后、关闭前按整体证据对直接 child 评价一次；未安排局部 review 不构成遗漏，证据不足用无分数 `notRated`。

派发内容、局部验证、审查、增量合入、汇报、等待及续跑遵循系统提示词的统一协作合同。
本技能提供 Profile 选择和调用示例，不另设完成协议或确认步骤。派发正文及 Turn 报告没有
应用层长度限制；只有 `taskSummary` 是简短列表标题。
