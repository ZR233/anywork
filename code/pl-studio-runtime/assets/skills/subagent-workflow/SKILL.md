---
name: subagent-workflow
description: 当任务需要通过糊来帮 Agent Profile 使用子代理进行并行探索、独立实现或静态审查时使用。
category: agents
---

# 子代理协作

用户要求子代理、并行探索、跨 crate 分析、独立验证或按角色分工，且任务适合独立委派时使用。

主代理、机器人主代理、系统 child 与用户 child 使用同一种 Agent 定义和指令冻结模型；
`list_agent_profiles` 是该模型的 child 可配置/可派发视图，不是另一套 Agent 实现。
内置 child ID 来自本轮声明目录，不能假定闭合名单或按固定 ID 推断能力。root 定义不进入
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

例如，当前目录中可能提供 `explorer`、`executor`、`worktree_executor` 和 `reviewer`；这些名称仅是随包声明的实例，不是固定扩展接口。新增声明可增加 child 选项而无需改框架角色枚举或另维护 ID 清单。

每次派发必须提供简洁的 `taskSummary`，空白归一化后为 1–80 个 Unicode 字符，用作 GUI
子代理列表标题；`message` 包含完整任务。主代理和子代理在首次工具调用前、重要发现、阶段
切换、等待及阻塞等有意义的节点，用 1–3 句 commentary 汇报。

只发送 schema 声明的字段，不得改用 `profile_id` 或 `writable_paths`。只有 directory
Profile 接受 `writablePaths`，unrestricted 和 worktree Profile 不接受。子代理始终使用独立
上下文，`message` 必须自包含，不能依赖父会话历史。首次调用前确认 Profile、模式及
最窄目录范围。遇到类型化参数错误时修正 schema 用法，不重复原参数。刻意触发的目录边界
拒绝记为 `expected_rejection`，不得重试或通过 shell、Git、MCP 绕过。

随包内置声明的 child 身份、名称、用途、指令和 workspace mode 不可修改，可以禁用；其集合由
统一 Agent 声明的 child 视图决定。`planner` 只保留为 root 的运行/历史标识，不是可派发 Profile，
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

单个执行者交付就安排具备 review workspace mode 的独立审查 Profile，不等待整批完成。审查目标是该执行者的实际工作区：
本地 directory 改动已在当前工作空间，只有通过审查的 worktree 提交需要主代理合入。
Profile 选择、审查范围和 Git 所有权应分别明确。

派发内容、局部验证、审查、增量合入、汇报、等待及续跑遵循系统提示词的统一协作合同。
本技能提供 Profile 选择和调用示例，不另设完成协议或确认步骤。派发正文及 Turn 报告没有
应用层长度限制；只有 `taskSummary` 是简短列表标题。
