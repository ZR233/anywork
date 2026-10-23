# 12 - Agent Profile 与协作编排

本文是 Profile 体系、child 派发、durable delivery、wait 语义、reviewer 门禁与返工合同的唯一
权威源；权限与工作区安全语义见 [04](./04-security.md)，通用工具运行时见
[09](./09-tool-runtime.md)，Task Mode 图与阶段见 [11](./11-thread-mode.md)。

## 12.1 边界与工作区模式

Studio 的所有会话均经 Agent 定义、指令装配与 Thread 执行边界。Agent 定义表达稳定身份、
适用的 root/child 范围、角色指令及修订；普通 root 与飞书 root 使用产品内置定义，child
从系统或用户 Profile 解析定义。已解析定义实际驱动统一指令装配，不是与旧角色字段并存的
第二套来源。Thread 仍是唯一执行 owner，渠道只适配输入输出，不建立另一套 Agent runtime。

Agent 角色与 Mode 正交：Agent 指令和 Mode 指令分别拥有独立来源。根会话可以切换执行方式，
但不能因此失去其 Agent 角色；child 没有 root Mode/workflow。模型基础指令、项目指令、
平台事实与技能仍经现有统一装配和更新边界，不能被角色定义旁路覆盖。

root-only 定义不是可派发 Profile，不进入 child catalog、动态 spawn schema 或 Agents
设置项；直接派发同样拒绝。飞书专用定义的选择来自已核实的机器人会话归属，不根据标题、
用户正文或任意 metadata 猜测。其行为契约见 [27](./27-bots.md)。

定义身份、修订与指令来源随已有 instruction snapshot 冻结；正常运行只消费当前结构。
旧结构只在版本迁移边界依据已保存的 root/child、Mode 和 Profile 身份解释，保留原正文，
不使用当前定义重写历史或替换已冻结指令。新建会话采用新定义，恢复不重新选择角色；
迁移不能证明归属时明确失败并保留数据。具体持久化约定见 [20](./20-config.md#206-提示词配置)。

Studio 的 child Agent 使用与 root 相同的 Thread/Turn/Tool 框架。创建时冻结最终模型路由与
Profile 工作区模式；路由由固定 Profile 或自动选模决定（见 12.7）。父 Agent 负责拆分工作、
避免冲突、审查成果，并用普通 Git 显式整合 worktree child 的 commit，不存在自动 merge
或 delivery gate。

根会话拥有会话级工作区模式 `ThreadWorkspaceMode`：`local`（默认）使用 Project 根目录，
`worktree` 从 Project 的 Git 仓库 `HEAD` 派生独立 checkout 并在其中工作。它是 Thread 的
canonical 产品事实，在创建会话时确定，之后不随配置或运行状态变化。它与 Profile 的 workspace
mode 是两条语义轴：会话模式决定工作区在哪里，Profile 模式决定 child 相对会话工作区的隔离
方式。根会话 worktree 的创建、绑定、恢复与清理见 12.5。

会话对外只有一个 canonical 工作区地址 `workspace_path`，与 `workspace_mode` 同层、在创建
会话时写定、之后只读：`local` 会话的地址是 canonical Project 目录，`worktree` 会话的地址
是该会话的工作树路径。`workspace_mode` 只是地址的类型标记；侧栏、会话顶栏与 GUI 状态不按
模式分别取路径，也不自行推导或拼接工作树布局。子线程继承所属根会话的地址与模式。地址与
durable lease 的职责边界见 12.5，产品投影见 [18](./18-studio-state.md) §18.2，持久化与迁移
见 [17](./17-studio-storage.md) §17.1。

child Profile 的工作区有四种模式，其中的 root 指该 child 所属根会话的工作区根：

- `unrestricted`：Profile 不增加额外项目隔离，root 就是会话工作区根（根会话为 `worktree`
  时即在该 worktree 内）；项目内外仍遵循会话 Permission Mode。
- `directory`：root 仍是会话工作区根；`writablePaths` 只限制 Pure 内置文件 mutation 工具在
  其中的业务文件写入，另有本 Thread 的 scratch/artifacts 许可（见 [04](./04-security.md)）。
  它不是 OS 沙箱，shell、Git 与 MCP 可以绕过，工具描述、child 固定上下文和
  GUI 必须共同提示该边界。
- `worktree`：root 是独立 Git worktree，boundary 为 Confined，worktree 内全可写；base 仍是
  Project 仓库的 `HEAD`，不是父会话 worktree；主工作区未提交内容不复制过去，成果不会自动
  合并。
- `review`：root、boundary 与 worktree 事实在 spawn 时采用被审代理的冻结工作区收据——被审者
  为 worktree child 时即 Confined 于该 worktree，为共享会话 checkout 的 child 时即会话工作区
  根及对应边界。review child 不创建、不拥有任何 worktree lease，也不继承被审者的
  `writablePaths`；“只审查、不修改代码”由 Profile 提示词承担。

根会话使用 `worktree` 时，共享会话 checkout 的 unrestricted/directory child 同样继承
该会话的 Confined 路径边界；directory 再叠加目录写策略。review child 的边界来自被审代理
收据而非该继承规则的重新推导；被审者为共享会话 checkout 的 child 时，两者结果一致。创建、
冷恢复与工具刷新必须保持同一边界，不能因 Profile 不独立创建 worktree 而恢复 host-permitted
访问。

## 12.2 用户 Profile 与系统预设

用户 Profile 位于 Studio home 的 `agents/` 目录，默认路径是
`~/.anywork/agents/<agent-id>.toml`。目录只扫描第一层普通 `.toml` 文件，文件名 stem 是稳定
id，不递归读取临时、隐藏或备份文件。单个文件完整表达一个 Agent：

```toml
schema_version = 1
enabled = true
display_name = "Rust 执行者"
description = "实现和重构 Rust 模块"
suitable_tasks = ["Rust 实现", "测试修复"]
workspace_mode = "directory"
system_instructions = """
遵循项目规范完成实现，并验证相关测试。
"""

[model]
account = "deepseek"
model = "deepseek-flash"
effort = "high"
```

用户 Profile 可选择四种模式，`review` 与系统 reviewer 语义一致（spawn 必须提供
`reviewTargetAgentId`）。旧文件缺少 `workspace_mode` 时按 `directory` 解释，下一次保存
写回 canonical 字段。文件分别解析、校验和原子保存；无效文件保留原字节、从有效目录排除，
并以脱敏 warning 暴露。合法但 account_id/model_id 当前不可解析的 Profile 保留在 Settings 中并
标记 unavailable。

主智能体（Main agent）是 root，负责理解需求、制定计划、协调子代理、整合与验证结果。
`planner` 只保留为 root 的身份标识；root 的模型 selector 属于各自 Thread，并以当前 Mode 的
保存值作为新建或切换默认值。主智能体不是可派发 Profile，也不在 Agents 设置页提供独立配置。
Studio 注册四个系统子代理 Profile：`explorer` 固定为 unrestricted，`reviewer` 固定为
review，`executor` 固定为 directory，`worktree_executor` 固定为 worktree。系统 id、名称、用途、指令
和模式不可编辑；Agents 设置页可以配置其启用状态、account_id/model_id 和模型声明的 effort。
`planner` 是保留标识，用户 Profile 不可占用；目录查询和 spawn 均不接受它。
历史 planner child 保留身份、消息和执行记录，仅供查看；恢复或续跑在资源创建前拒绝，
界面显示“该子代理角色已停用”。历史订阅直接重放日志并发布只读快照，不装配运行资源；
后续等待随订阅取消而释放。该限制仅针对 child，不影响使用同一路由的 root。

每个 child 创建时冻结 Profile id、正文与工作区分配快照，保存最终选择的 account、model、effort、
分发模式与偏好及配置 revision；自动模式不保存被覆盖的固定路由作为执行事实。后续 Profile 更新只影响未来 child；已有 child 在 account 配置刷新时仅用
当前 endpoint、凭据与模型目录重新解析已冻结 selector，不改写 selector、创建指令或物理工作区，
也不在每轮回读 SQLite。产品在准备初始
外部资源时接收同一冻结 Profile 快照，不能从父 Agent 配置或非类型化 metadata 猜测权限和
系统指令。本文保留的是公共功能语义而不是固定 Rust 签名：任何实现 PL host 的产品都必须能
在外部资源产生副作用之前取得"本次 spawn 已冻结的完整 Profile"，用于按同一 account、
model、effort、system instructions 和 workspace mode 创建容器、远端会话或审计收据；后续
可以重命名请求类型或拆分生命周期阶段，但不得删除这项能力，也不得把重新解析 Profile 的
责任推回产品层。

Plan 属于各自的 Thread，不随 Profile 或 workspace assignment 复制到 child，也不
存在 lineage 共享句柄。child 始终使用独立上下文，不继承父 Thread 的对话记录、附件、资源引用或
厂商私有历史；`spawn_agent` 不接受历史继承选项。root 必须把 child 所需的已批准基线写入
`spawn_agent.message`；
child 不装配 `plan_*` 工具；方案与问题通过 Turn 报告交给 root。配置冻结与 Plan session
隔离是两条独立边界。`spawn_agent.message` 和 root 后续通过 `send_message` 发送的补充输入
都在 child Timeline 中显示为 `parentAgent` 文本消息，并由 Studio 标记为"主智能体 / Main
agent"；`send_message` 对运行中 child 请求打断并在清理后携带新内容自动继续，对空闲 child 启动执行。
它复用用户 prompt 的 owner 控制入口，`interrupt_agent` 则仅停止，不自动续跑。消息收据只表示受理。它们对 account 仍是普通 user role，不得改变上下文隔离、Plan 隔离、预算刷新或
parent→direct-child 授权语义。

## 12.3 spawn 与目录写策略

`spawn_agent` 必须提供 `taskSummary` 与完整、自包含的 `message`。child 的初始上下文只由冻结
Profile 的系统指令、产品初始事实和该消息构成，不读取父模型请求历史。概要由调用者用简短语句描述本次
任务，折叠空白后必须非空且不超过 80 个 Unicode 字符；缺失或非法概要在分配资源前拒绝，
不截断。Studio 通过类型化创建请求接收概要，作为 child 的初始 canonical Thread title
保存和发布。后续消息、进度与完成汇报不覆盖该标题；显式重命名沿用 Thread title 合同。
既有 child 保留保存的标题，不根据历史任务正文补写概要。

root 与所有 child 共用可见进展合同：非平凡任务首次工具调用前、重要发现、阶段切换、
等待和阻塞时输出 1–3 句 commentary，说明已确认进展和下一步。长任务持续提供有信息量
的更新，不为每批工具机械重复播报；隐藏推理和最终答复不替代执行期间的可见进展。

`spawn_agent` 接收可选 `writablePaths`。只有 directory Profile 接受该字段：省略表示整个工作区
可写，空数组表示业务目录只读（不撤销本 Thread 的 scratch/artifacts 许可）；条目是该 child
实际工作区相对目录前缀。runtime 拒绝绝对路径、
`..`、非法分隔
以及解析后越界或经过不安全 symlink 的路径，规范化和去重后冻结。其他模式传入该字段直接
返回参数错误，避免形成虚假隔离预期。

`spawn_agent` 接收可选 `reviewTargetAgentId`。只有 review Profile 接受该字段且必须提供：值是
被审子代理的 Pure agentId（执行者 spawn 回执中的 `agentId`），必须是调用者（root）的直接
child、属于同一根会话且拥有工作区收据。宿主冻结被审者的工作区收据作为 reviewer 的工作区，
不由模型提供路径；被审者的 worktree lease 不发生归属转移。worktree 被审者的 lease 已清理或
物理工作树缺失时拒绝 spawn。其他模式传入该字段、review 模式缺失该字段或目标不合法都直接
返回参数错误。

canonical Project 路径只标识项目，不充当 directory 写入的路径基准：本地与 SSH 的目标和
可写目录均以实际 workspace root 判定；本地使用文件工具的安全路径解析统一 Windows
路径表示及最近存在父目录，不要求被授权的新目录已存在。目录外写入仍拒绝，Project 主
checkout 和其他会话/child checkout 不因此成为可写目录。

模型可见的 `spawn_agent` schema 必须从本轮启用的 Profile 快照动态生成对象联合（oneOf），
而不是在一个公共对象上暴露所有模式字段。每个分支以 `profileId` 常量绑定一个 Profile：
directory 分支声明可选 `writablePaths`，unrestricted 与 worktree 分支不声明该字段；所有分支
都使用 `additionalProperties:false`。review 分支必须声明并要求 `reviewTargetAgentId`，其他
分支不声明该字段；各分支保留相同的任务概要、完整消息及既有 metadata 语义，不扩大或
收紧公共参数的有效输入。schema 同时给出 profileId → workspace mode 映射，供模型
在首次调用前完成选择。用户 Profile 按冻结的 workspace_mode 进入相同分支。运行时保留独立
硬拒绝，防止绕过 schema 的非法请求；explorer 的只读与 reviewer 的只审查是角色行为合同，
不能用 `writablePaths:[]` 模拟，也不由工具层裁剪 reviewer 的命令能力。schema 约束用于降低
模型首次调用错误，执行路径仍按 Profile 快照
重做同一语义校验，不能把 schema 当作安全边界。

Studio 从已发布的同一代 Profile 快照及会话冻结的分发模式形成派发声明和目录查询工具；
固定模式只保留固定路由可执行的 Profile，自动模式保留启用且结构有效的角色，不因其
固定路由不可用而排除。自动模式每个分支必填非 null 的 `modelSelection`，固定模式不声明
该字段；其类型与真实派发请求一致，不经 metadata 隐式覆盖。目录查询使用与声明完全
相同的角色集合；自动候选模型仍由 12.7 的独立查询和实时准入负责，不复制模型目录。
查询使用该轮冻结的目录，而不是在执行中另取可能不同代的清单。配置或 Profile 目录变化通过现有工具
刷新边界更新后续请求，Mode 切换与冷激活也采用当前快照。已经开始的模型请求保留原声明，
已创建 child 保留原冻结 Profile、路由和工作区；执行时仍独立核对当前准入权限与启用状态。
声明变化遵循工具内容身份与 deferred reveal 的既有失效规则，不另设目录缓存或执行器。
该模式下无可用 child Profile 时不注册 `spawn_agent`，保留可解释的目录查询；恢复可用 Profile
后由同一刷新边界重新注册。不得回退到无约束的通用派发 schema，也不把 root-only 定义
作为空目录的默认候选。目录读取或声明构造错误按工具目录失败传播，不伪造空目录成功。

spawn receipt 返回模式、实际 root、canonical 可写目录；worktree 模式额外返回 branch 与
base commit；review 模式返回被审 agentId 与采用的目标工作区事实。Local 与 SSH backend 的所有 Pure 内置文件 mutation（apply patch、
write/delete/copy/move、项目 Skill 写入）都调用同一中央路径策略；该策略不因会话使用
full-access 而关闭。读取不受 `writablePaths` 限制，项目外路径仍只由 Permission Mode 决定。
当前版本该模式固定为 `full-access`（见 [04](./04-security.md)）。

协作查询（包括 `list_agents`）只读取宿主授权范围内的快照，允许与普通读取工具出现在同一
模型批次；该批次不承诺跨工具的联合事务快照。创建、发送消息、打断和关闭代理会改变协调
状态，仍必须单独调用，不能与查询或其他工具混批。

## 12.4 Task 编排合同

### 任务消息与依赖

Task root 先建立依赖图、文件所有权与验证边界。跨目录检索、历史核验和相互独立的事实收集
优先拆成多个 `explorer` 并行执行；主智能体综合事实、比较方案并决定计划。探索 child 默认使用
fresh context，父消息必须自包含，explorer 返回 `file:line`、符号名、必要原文和不确定项；
root 负责综合结论和亲自维护 `design/**`，child 不替代 root 编译或转换 workflow。

实现 child 的任务消息必须完整声明：任务目的与用户价值、设计基线与前置事实、拥有的
文件/模块和不变量、禁止修改范围、按顺序执行的探索/实现/测试/提交步骤、可检查的完成与
失败条件、最终 diff/commit/测试/风险证据，以及 workspace、`writablePaths`、Git 与 cleanup
合同。root 应先按依赖边排序：无依赖且写集合互斥的任务并行，有真实语义依赖的任务保持
顺序；只有极少操作的微任务、重复目标、需要共享未稳定上下文或真实前后依赖的工作不得为
增加 agent 数量而拆分。

- 单个边界清晰的实现，或多个写集合完全互斥的并行实现，使用 `executor`；并行时为每个
  child 传入最窄且互不重叠的 `writablePaths`，禁止 child 借 shell、Git 或 MCP 越界修改、
  stage、commit 或 reset。
- 会触及共同接口、manifest、lockfile、生成文件或高风险 Git 状态的任务使用
  `worktree_executor`。每个 child 在独立 worktree 提交，经局部审查通过后由 root 串行合入当前工作空间；worktree 不能
  替代真实前后依赖的顺序执行。对于任务要求创建的新文件，child 必须先用文件工具创建并以
  只读工具确认精确路径和内容，之后才能执行引用该路径的 `git add` 或 `git commit`，不得用
  试探性暂存验证文件是否存在。状态检查、文件创建、内容确认、测试、暂存、提交和提交复核
  是独立步骤，不得用 `&&`、`||`、`;` 或 pipeline 拼成一个 exec，保证任一步失败都保留准确的
  首次调用责任和可重试边界。

平凡单文件任务保留所有阶段、Plan 批准和独立 reviewer；计划目标不超过八行，不机械展开
DAG 或验证表，无独立探索价值时不派 explorer。root 可以承担协调成本高于工作量的写入；无
文档或整合变更的阶段复用已有事实简短说明；阶段切换仍按新鲜查询和 Solo mutation 执行。

### ready frontier 调度

planning 开始和每个 child 交付后，root 都执行一次成本感知的并行化分析：从需求、仓库边界
和验证目标识别可交付节点；仅当多个实质交付存在依赖时，为合格节点记录前置依赖、读写
范围、适用 Profile、交付证据与 root-only 标记，形成任务 DAG。依赖已满足、边界清楚、可
独立验收且预计能缩短关键路径或显著增加独立证据的节点构成 ready frontier；root 按容量
派发就绪任务，等待期间继续处理未委托工作，不得重复 child 的任务。每收到一个执行者的
本轮终态报告，root 即核对证据、安排局部审查并更新依赖；满足依赖的
后续任务立即释放，不等待整批完成。容量不足时将就绪审查排队，不用整批屏障代替容量调度。
调度不使用固定 agent 数量。

### Turn 报告与收据

主代理统一承担用户澄清和 Plan 确认。child 不装配 plan_* 或 request_user_input；权限审批仍由
运行时处理。父消息提供已批准基线，child 遇到问题时结束本轮汇报，由父代理决定续跑。

finish_turn({message}) 提交完整非空正文并结束 Turn；自然 final 同样结束本轮，不需要再调用
工具或重复汇报。派发、续跑和汇报正文不设应用层长度上限；模型容量和存储背压仍按各自合同
处理，不能静默截断。正文说明目标、事实、架构、接口形状、错误语义、依赖步骤、复杂流程
伪代码、所有权和验收。契约明确、局部自主，事实和建议必须区分。

TurnState 是唯一执行终态；报告由对应终态水位的已提交历史投影，不拥有独立状态机、revision、
registry 或就绪 marker。报告包含 child 身份、Turn/input 身份、触发及本轮消费消息的身份与序号、终态序号、实际停止原因、完整
正文、未完成后台任务和交互，以及本轮实际权限审批记录（含已完成审批）。正常结束不等于任务完成，父代理结合目标和证据判断。
强制停止没有模型总结时由运行时报告实际原因及本轮已提交可见输出，不追加模型请求、不借用
旧轮总结、不转发隐藏 reasoning。步数耗尽保留现场，由父代理决定继续，不自动续跑。

spawn/send 收据仅表示消息受理。父代理绑定真实 agentId 和本轮 input/Turn 身份，不能把旧轮
报告用作新任务交付。消息序号和 effect 序号属于不同域。
Turn 标识只在其所属 Thread 内解释，跨 child 的完成证据使用 `(agentId, turnId)` 联合
身份；不同 child 可以保存相同的 Turn 字符串。独立复审由新 child 的真实创建、review
target 与该 child 的终态共同证明，不能靠不同 child 的裸 Turn 字符串是否相等推断。

### 通知、等待与恢复

终态提交后，完整报告以稳定 child/终态 commit 消息身份写入父 Thread inbox，重试幂等；固定终态水位
禁止混入后续 Turn 输出。wait 只等待就绪，消息通过下一模型请求进入上下文，不再另外查询提交
或返回重复报告。空 taskIds 等待子代理等 Thread 消息，工具 taskIds 仅引用工具任务，不能传入
agentId 或裸 callId。指定任务时仍可被新消息提前唤醒，`sleep` 回执也是普通工具任务；统一就绪、
截止点与取消语义见 [14](./14-runtime-host.md) §14.4–14.5。正常超时不机械轮询。

显式恢复时核对已保存 child 终态与父 inbox 并补齐缺失通知；历史查询不激活模型。Turn 结束
不关闭 Thread、不取消跨 Turn 后台任务、不清理 worktree。read_agent_session 保留为诊断与
历史查询，不是正常交付必经步骤。旧进度与通知仅在迁移边界转换，保留原始内容、身份和顺序，
不得把 readyForCompletion 推断成成功执行。

### 独立审查与增量合入

working 内各实现任务独立推进编码、局部验证、静态审查和修复。root 收到单个执行者的本轮
完成证据后即派 fresh-context reviewer，不等待其他执行者；原执行者在该轮审查期间暂停修改
被审范围，其他互斥范围可继续工作。执行者只做自身改动范围的格式检查、静态检查、单元测试
和必要定向回归，不运行全仓格式化、全量测试或最终集成门禁。无法定向执行的检查交 root；
若目标项目强制每次提交前全量验证，派 directory executor，由 root 统一验证后按授权提交，
不能让 worktree executor 跳过项目规则。

每次审查消息包含当前已批准的完整实施计划及已确认调整、该任务范围与验收要求、执行者
身份、基线 commit、差异摘要和局部验证证据。reviewer 通过 spawn 的 `reviewTargetAgentId`
绑定被审执行者，宿主把被审者的工作区收据冻结为 reviewer 工作区；reviewer 直接在该工作区
内读取文件、运行只读 Git 命令并执行必要的验证命令（含构建与测试），但不修改源代码、Git
状态或外部状态——这是 Profile 提示词合同，不是工具层裁剪。未完成的其他独立任务不算
当前任务遗漏，但影响本任务正确性的真实依赖必须明确。缺少完整计划或必要源码证据时补齐
后才能批准。计划明确留给 root 的最终验收尚未执行，不单独阻塞局部静态审查。

审查结论绑定 worktree commit 或 directory 差异及文件内容身份。reviewer 在被审执行者的
实际工作区内审查，不限定为 root 工作区；被审工作区缺失或已清理时 spawn 与冷激活显式
失败，由 root 重派新 reviewer 或先恢复现场，不能凭摘要批准。报告明确批准或阻塞问题并附
证据，不得同时批准又要求先补齐审查必要证据。
root 消费对应 reviewer 本轮终态报告，不解析字符串 marker，不另读 submission。

- directory 成果已在当前工作空间。审查通过、局部验证和前置条件满足后标记该任务完成，
  不执行 cherry-pick、merge 或模拟合入，也不顺带提交其他未完成或未审查的本地改动。
- worktree 成果审查通过且依赖满足后，root 即用普通 Git 将已批准提交合入当前工作空间，
  不等待其他执行者。主工作区 Git 操作串行；合入成功后才标记任务完成并释放依赖。
- 冲突解决、后续修改或依赖变化影响已审范围时，补充该范围的验证和 fresh-context 复审；
  无关变化不使全部审查失效。不得丢弃其他所有者的改动或借冲突处理扩大为无关重构。

代码 finding 由 root 发回原执行者；修复后先局部复审，再按工作区类型完成或合入。设计问题
由 root 在继续相关编码前同步文档；需要调整计划时遵循既有确认流程，不用修改计划掩盖偏离。
各任务循环互不阻塞，所有执行者及 worktree 保留至最终验收通过，不能把增量合入当作 cleanup。

全部本地任务完成、全部工作树任务完成并合入后，integrating 核对交付完整性和审查版本；
没有 worktree 就不制造合入操作。reviewing 由 root 对照完整计划进行跨任务静态审查、适用的
全量检查、集成与功能验收，逐项对应要求、实现和实际证据。不强制再派全量 reviewer，局部
审查批准也不能代替整体验收。最终验收发现代码问题时回 working，由原执行者局部修复、复审，
worktree 修复再次合入，directory 修复直接留在当前工作空间；设计问题回 editing_documents。
仅环境故障则处理环境并重跑受阻检查，不机械触发代码返工。所有必要验收通过后关闭子代理，
清理已接受的 worktree 并核对资源回收，再进入 completed；失败或取消保留未交付现场。

合适 child 不可用或失败时，root 先等待容量并收窄重派一次；仍失败才允许最小实现兜底，并
在交付中记录 `ROOT_IMPLEMENTATION_FALLBACK`、原因和直接修改范围。参数错误按实际 schema
修正后再调用，不能重复相同错误；刻意验证目录边界的拒绝记为 expected rejection，不能绕过。
上述职责是 Mode/Profile 提示词合同，不新增运行时子任务状态机或工具能力裁剪。

### 原执行者返工与验证证据

root 保存任务读写范围与原执行者 `agentId` 的映射，交付后保持执行者 idle、可续跑，不提前
关闭或清理 worktree。代码 finding 必须先用 `send_message` 续跑原执行者，附 finding、当前
整合基线、修复范围和验证记录；只有执行者不可用或原权限无法覆盖修复时才重派，并记录具体
原因。设计 finding 仍由 root 修订。worktree 返工前由 root 协调核对最新 canonical 基线，仅在依赖或冲突需要时同步；只采纳
本轮新增修复提交，不重复整合旧提交。每次续跑都重新建立 pending 集合，使用本轮消息之后的
终态报告；旧轮次完成状态与旧交付不能证明返工完成。修复后创建 fresh-context reviewer，
局部批准后本地任务直接完成，worktree 新增提交由 root 合入；最终验收通过后才关闭执行者、清理 worktree；
停止或失败保留未交付现场并报告原因。

执行者、reviewer 的本轮报告包含验证记录：实际执行者、完整命令、
工作目录、代码基线（commit 加相关未提交 diff 或文件内容身份）、覆盖范围、环境、结果和
工具/日志证据。明确区分本次实际执行、引用已有证据、尚未验证；没有执行测试也必须说明
原因，阅读测试代码不算执行测试。root 向后续 child 传递已确认的记录，并在最终交付逐项
汇总。执行身份以成功 spawn 回执中的 Pure agentId 为准；child 无法确认时报告角色/范围，
由 root 绑定 ID，不使用环境变量、进程或外层宿主 ID。相同命令、相关代码范围与环境未变且
已有成功证据时复用；修改或依赖变化、冲突、失败诊断、覆盖缺口与强制门禁要求重跑时，报告
具体原因。执行者只做局部验证，root 承担最终整合验证与项目强制门禁；reviewer 可执行只读
检查与必要验证命令，但不修改代码，补测试仍由执行者完成。验证记录使用报告正文，不新增生产协议、持久化字段或
GUI 接口。复用会话增加上下文及 account prompt cache 复用机会，缓存命中只按上游实际
usage 报告，不承诺固定收益。阶段完成标准消费可复用的验证记录，只补缺失或失效的检查，
不为阶段切换机械重复全量测试。

用户要求的验证未完成时不得宣称 completed；同一基础设施故障确认后不派 child 试探同一
物理能力。以上均是提示词约束，不新增运行时完成硬门禁。

## 12.5 worktree 生命周期

本地和 SSH 后端都以创建时解析的 `HEAD` 执行 `git worktree add -b`，禁用 hooks 和
credential helper，最长 120 秒。两者都以本次解析出的仓库根作为 worktree backend 根：远端
项目的 workspace handle 根、Git 工作目录与相对路径基准都取自该仓库根，而不是配置的 Project
目录，因此 Project 目录是仓库子目录时同样成立；远端 Git 与目录操作仍由本地编排，经远端进程
面与文件面在远端执行，helper 内不实现 Git/worktree。创建路径与恢复、preview 和清理共用该
约定。lease 记录归属：child 智能体使用
`<repo>/.anywork/worktrees/<root-thread-id>/<child-id>` 与 Pure-owned `pure-agent-*` 分支；
根会话自身工作区使用 `<repo>/.anywork/worktrees/<root-thread-id>/session` 与 Pure-owned
`pure-session-*` 分支。review child 复用被审者的物理工作区但不拥有 lease：归属、清理与
重建仍由被审执行者的 child 身份决定。身份校验按归属校验期望 leaf 与期望分支，仍拒绝任何非
Pure 分支。非 Git 项目或无 HEAD 时类型化失败。

远端后端的 `git worktree add`/`remove` 路径参数、workspace 打开参数与 lease 记录使用同一
POSIX 形式：客户端宿主形态（含 Windows 路径分隔符）不得跨端，否则物理 worktree 会落在与
lease 记录不一致的位置。远端绝对路径的唯一规范化边界是
`pl-tool::remote::normalize_remote_absolute_path`：它把反斜杠转换为 `/`、折叠重复分隔符与
`.`，并拒绝空值、相对路径和 `..`；Studio、worktree backend 与恢复代码不得维护第二套路径
解释（跨端路径约定见 [22](./22-ssh-remote.md) §22.3）。

根会话 worktree 对本地与 SSH 项目都可用，并在创建会话的命令内建立：先按 `HEAD` 解析仓库与
base、记录含 `ssh_alias` 的 `prepared` lease，再创建物理 worktree，随后转为 `active`，然后
发布含 `workspaceMode` 的 Thread 目录事实，最后激活 owner 并把该路径绑定为会话工作区根。
远端会话的工作区根与 canonical Project 目录分离，工具层按会话工作区根打开远端 workspace
handle。任一阶段失败都让命令失败、不发布 Thread，并按 `NoSideEffects | MayHaveCreated`
收束；已创建资源保留现场，不用 `--force` 绕过 Git 锁或注册身份。崩溃可能留下已落库 lease
而没有 Thread 记录，启动对账把这类 lease 作为诊断保留。

根会话激活只按 Thread 的 `workspaceMode` 与 durable lease 解析工作区：`local` 使用 Project
根目录；`worktree` 必须存在 identity 匹配的 `active` lease，缺失、身份不符或已经清理都返回
类型化失败并发布带 revision、branch/base/head 与 path 的 Recovery，不静默回落到主工作区。
归档清理该会话树在 worktree 模式下拥有的物理工作树：会话自身 lease 与树内 child lease 都按
`cleanupRequested → discard → cleaned` 收束，Pure-owned 分支一并删除，身份校验规则不变；
任一步失败回落 `preserved` 并发布 Recovery，归档本身仍完成，不静默留下既不确定又无处处置
的资源。归档因此是破坏性动作：工作树中未提交的改动与未整合的提交一并删除，确认入口见
[concepts/project-sidebar.md](./concepts/project-sidebar.md)。

非归档的关闭路径不删除会话自身 worktree；child worktree 仍按关闭路径的 disposition 处置。

归档不改变 Thread 身份：恢复把 `archived` 翻转回去，并在原路径重建已清理的工作树——会话自身
与树内 child 各按同一归属重新派生路径并准备 lease——使会话地址在归档与恢复之间保持稳定。
运行期不再存在「Thread 已归档后仍长期持有 worktree」的状态，只在清理失败时保留 `preserved`
现场。

恢复必须让 worktree 会话重新落到可用状态，不能只翻转归档标记后留下无法激活的会话：已清理或
缺失的 lease 在原路径重建；归档清理失败留下的 `preserved` 现场在身份匹配且物理工作树仍然
存在时重新绑定为 `active`（并退掉对应的 Recovery 条目），否则同样在原路径重建；两条路都失败
时返回类型化失败并保留现场。恢复完成后该会话的 lease 必须是 `active`，否则恢复本身失败。

Recovery 的 worktree preview 与显式清理只作用于不再由活动 owner 使用的资源：保留
（`preserved`）的 lease、没有已注册 Thread 的孤儿 lease、归档清理失败而保留的现场，以及
身份或物理资源缺失、不匹配的现场。健康 `active`（以及创建中的 `prepared`）lease 不进入清理
入口，也不显示为待清理项；显式清理命令必须在服务端复核同一前置条件，陈旧 GUI 卡片不能删除
在用 worktree。创建会话失败当场收束为 `preserved` 的会话 worktree 必须立即发布带归属、状态、
revision 与 preview 的 Recovery 条目，不依赖下次启动审计才可见；该条目覆盖同一 Thread 的旧
诊断，不留下来源已保留却无处清理的资源。

「创建中」与「崩溃遗留」以进程内显式标记区分：标记存续期间该 lease 既不发布也不可清理（即使
owner Thread 记录尚未发布）；进程重启后标记消失，遗留 lease 按需要人工处置的资源处理。所有
运行期把会话 worktree 收束为 `preserved` 的路径，包括创建阶段的失败收束与身份不符收束，都
必须在返回错误前完成发布。

`studio_objects` 保存版本化 lease：归属类型、owner Thread id、
`prepared | active | preserved | cleanupRequested | cleaned`，以及 repo、path、branch、base
与 revision。spawn 或创建会话的任一阶段失败都按
`NoSideEffects | MayHaveCreated` 分类补偿 Thread、热资源、worktree 与 branch。启动恢复按
durable lease 对账，本地与远端 lease 同样处理：远端 lease 的预览与显式清理在连接可用时经
远端 backend，SSH 离线时保留现场并给出诊断。除 lease 外，启动期只对本地项目额外扫描文件
系统中的未注册 Pure-owned worktree，不为远端项目打开 SSH 连接，远端资源完全由 durable
lease 覆盖。资源部分缺失或身份不匹配时保留现场并发布 Recovery issue，不盲删目录或非 Pure
分支。

`close_agent` 对 worktree child 接受 `workspaceDisposition = preserve | cleanup`，默认
preserve。review child 不持有物理工作区，关闭时不触发任何 worktree 处置；其冷激活要求被审
目标仍可解析且（worktree 被审者）lease 非 cleaned、物理工作树存在，否则类型化失败并由
root 重派新 reviewer，不代为重建被审者工作树。关闭工具等待子孙 Thread、订阅与所选宿主资源处置完成，成功结果包含目标及
`lifecycle.kind = closed`；成功回执同时报告实际 workspaceDisposition。它不通过目录事件报告
完成；父 inbox 的 core Closed 通知可能早于物理资源清理，不能代替 `close_agent` 成功回执与
路径/分支复核。若工具执行仍是 pending task acknowledgement，须等待该任务的最终结果。清理
失败保留关闭状态、所选 disposition 与可恢复错误，显式重试不能使已取消的会话重新执行。
显式关闭同样支持目录中已保存但未驻留的 child：按持久父子身份授权，并与同目标的评价、
激活和续跑排序；不得通过提交新输入来激活后再关闭。关闭只恢复完成关闭与资源处置所需的
事实，不调用模型，不依赖当前模型启用或凭据状态；成功必须确认真实关闭及所选资源处置，
不能仅以目录存在或未驻留推定已关闭。
显式关闭意图与宿主资源退出必须分离：正常应用退出、服务关停或资源回收不表示用户或
父代理禁止该 child 再次执行。Core `ThreadLifecycle::Closed` 描述当次 owner 已关闭，
不能单独作为跨进程拒绝恢复的依据。Studio 在既有版本化 Thread 扩展中持久保存显式
关闭意图，轻量目录只投影同一事实；不得从归档可见性、工作区 lease 或模型可用性猜测。
显式关闭先在同 child 的操作边界封闭准入并可靠保存该意图，再收束执行与资源；保存
失败不得发布关闭成功，提交后的资源清理失败不撤销意图，原 owner 保留重试责任。
对已持久封口的 child，续跑与执行激活明确拒绝；只读历史、已提交评价收据及关闭重试
仍可使用。正常退出后未显式关闭的 child 可由新的显式输入恢复，沿用冻结 Profile、
模型、现场和上下文，并重新校验当前准入，不因恢复改选模型。旧记录无法证明显式关闭
意图时保留原恢复行为，不把历史 `Closed` 伪造为显式关闭；迁移见 [17](./17-studio-storage.md)。
关闭不自动 commit、merge、cherry-pick 或修改主分支；父 Agent 应先审查 child commit、用
普通 Git 显式整合，最终审查与验证通过后再请求 cleanup。已经 preserved 的 lease，不论归属
child 智能体还是根会话，都在 Agents/Recovery 中显示 revision、branch、base/head、dirty 与
changed-files 预览，并提供显式清理；两种归属共用同一清理入口，按归属标识区分。物理
worktree 清理尊重 Git 锁与注册身份拒绝：注销失败且目录仍存在时，不继续
绕过 Git 删除目录或分支；保留现场并返回实际错误，显式解除原因后可重试。Windows 本地 Git
命令必须按进程传入 `-c core.longpaths=true`，覆盖 worktree 创建、状态、注销、分支清理
及普通 Git tool 操作；不修改用户全局 Git 配置。该设置只解决 Git 的长路径处理，不改变
归属校验、注册状态或失败后的现场保留规则。

## 12.6 GUI

Agents 是 canonical Agent 配置中心，不保留重复 Roles 设置页。系统卡片显示固定模式徽标、
启用开关、account_id/model_id/effort 控件，用户编辑器额外显示三模式选择。所有设置 mutation
携带 `expectedSettingsRevision`，成功后以返回的完整 canonical settings snapshot 原子刷新
UI（设置页整体契约见 [19](./19-studio-ui.md)）。

显式 send_message 可按已保存的直接父子身份激活未显式关闭的 cold child，沿用原 agentId、现场和上下文；
list_agents 同时投影热、冷历史成员。恢复观察可补写缺失 inbox，但历史观察不唤醒模型；
新的终态才主动唤醒父代理，显式输入/续跑负责消费恢复的待处理消息。已保存消息身份及消费水位
去重，不因报告投影升级重送旧通知。保留 worktree 的恢复提示不阻断根任务续跑。

根任务接受显式新输入时，对未加载子代理的保存 checkpoint 与历史做只读终态对账，补齐父 inbox；
无需打开子代理工作区或调用模型。仅打开历史页面不触发这一步或恢复执行。

## 12.7 分发模式、模型查询与最终评价

根会话创建时确定 `delegationMode = profile | automatic` 与
`delegationPreference = economy | balanced | fast`，与 Thread Mode、工作区模式独立。
缺省为固定 Profile、平衡；全局默认只影响未来会话。解析后的会话选择持久化且创建后只读，
压缩、恢复和工具刷新不重新继承全局默认。child 保存本次派发来源，但不获得派生、选模或
评价工具。主代理模型本身不受此选择影响。

分发模式/偏好由版本化 `studio.delegation` Thread 扩展保存，root 创建时冻结，child
只复制本次派发来源；child 的最终模型仍由冻结 Profile 绑定唯一拥有，不在分发扩展中
再保存可独立修改的路由。目录摘要与回执从这些事实派生。GUI、HTTP、机器人及其他
创建入口都在首次受理前形成同一选择，缺少显式覆盖的新会话才读取全局默认。

固定模式使用 Profile 配置的路由，`spawn_agent` 不接受模型覆盖；自动模式要求
`modelSelection`，包含 `accountId`、`modelId` 与可选 `effort`。启用 Profile 在自动模式中
只提供角色指令与工作区契约，不因其固定路由不可用而消失。宿主在任何外部资源分配前
从同一配置快照校验 Profile、所选路由及模型启用状态，并将最终选择写入冻结快照。
schema 与执行路径遵守同一模式，不能用 metadata 传递路由或权限；目录/审查模式参数
仍按 12.3 校验。spawn 回执包含最终模型身份，续跑沿用该身份，不按偏好自动换模。

自动选模候选依次经过账号有效目录、[06](./06-model.md) 的文本类型资格、模型启用、
路由可用性及工具/任务能力筛选。没有候选时明确失败，不回落固定模式或借用其他账号。
查询可用性只证明本地准入，不能保证远端健康、订阅有效或额度充足，不发送推理探针。
派发仍复核最新资格，已撤销成员不能由陈旧查询授权。

偏好只通过主代理的一段短预设提示词表达，不是硬编码排序器：经济在满足质量前提下
优先整项任务的预计边际成本并考虑返修，平衡综合适配、质量、成本与耗时，快速优先整体
交付时间并考虑首字延迟、吞吐和返修风险。三者都不得牺牲权限或验收；未知价格不等于
免费，订阅不等于可无限用，最高吞吐不等于最快完成。只注入选中的模板，不注入全量
模型目录或评论；固定模式不注入偏好模板。

### 查询与上下文预算

- `list_delegation_models` 只返回合格且开启的候选，支持硬能力、任务类别、账号、计费
  类别和最低上下文筛选。默认 5 条、最多 10 条，按稳定身份分页；游标绑定查询条件及
  目录水位，变化时明确失效。任务适配标签是参考，不把未评测模型伪装为能力不支持。
- `get_delegation_model` 查询单个精确账号模型，提供资料、来源、可用性及最近 10 条
  本地评价。不可用详情不授权派发，已撤下目录成员不从系统目录补回。
- 列表只投影短简介、能力、价格/计费、速度样本及评价摘要；不带完整参数 wire 或评论。
  简介最多 240 个 Unicode 字符，资料来源最多 6 项；详情不展开网页正文。
  硬过滤及保存输入校验不依赖模型自觉控制长度，不静默截断评价提交。
- 目录、价格、性能与评价分别消费已有领域事实，不维护第二份模型注册表；查询不联网、
  不推进设置 revision、不扫描会话正文。评论和网络资料均为非指令参考材料。
- 主代理先筛选再按需查看少量详情，数据未变化时复用结果；工具按需发现，GUI 展示
  信息不额外注入模型上下文。

### 最终任务评价

`evaluate_agent` 仅允许主代理评价自己的直接 child。输入包含 `target`、
`expectedTurnId`、`expectedRevision`、任务类别、最终结果及评价；账号、模型、effort、
Profile、分发模式和偏好由宿主从冻结事实取得，不接受调用者任意指定被评模型。
预期 Turn 必须为最新已提交终态，且没有运行任务、未消费输入或待处理交互/权限。
逻辑任务完成由主代理按证据判断，Turn 结束本身不表示完成。
热快照和轻量目录中的 Turn 集合可能已按保留边界退休，缺少 `lastTurn` 不等于从未
提交终态。评价以现有可靠会话历史及其持久化水位证明最新已提交 Turn，同时从当前
owner 或冷检查点核对活动、待处理工作与冻结身份；不能把历史中的某个较旧终态当成
当前最新状态，也不为评价激活模型、扫描会话正文或建立第二份终态索引。

对同一 child 的评价、续跑准入与关闭封口有确定的串行顺序：评价获准后，新的续跑和
关闭等待其写入结论；续跑先获准时，评价不得使用前一轮的空闲快照；关闭已封口则拒绝
新的评价写入，已提交幂等查询仍可返回原收据。该顺序属于现有协作 owner 的操作边界，
不新增逻辑任务完成状态。冷 child 可从已保存检查点只读验证，但不能只凭目录状态判定
终态，也不为评价启动模型或执行工具；实际写入前仍须与同 child 的激活/续跑裁决一致。
冷评价不是恢复或迁移入口：只读访问现有 canonical 检查点和可靠历史，不创建历史库、
导入旧检查点或完成遗留清理；共享历史句柄仍被其他观察者持有时，也不得降低只读访问
模式。缺少 canonical 数据或需要迁移时明确拒绝，迁移留在既有打开或显式继续边界；
损坏及未知格式保留原始错误和现场，不借评价自动修复。

共用主代理提示词要求在完整交付、审查和全部返修结束后，关闭前评价一次；失败或外部
环境阻塞同样可以如实收尾，不能为得到评价而制造成功。结果为 `passed`、`failed` 或
`notRated`；可评分结果包含质量与指令遵循两个 1–5 分项，`notRated` 不携带分数、不
参与均分。评论非空且最多 300 个 Unicode 字符，描述验收依据、优缺点及必要返修情况，
不复制源码、凭据或整段报告。Turn 数不自动解释为返修次数。

每个 child 只有一条有效评价，首次 `expectedRevision = 0`，更新携带已有 revision。
同一终态同一内容重复提交返回原收据，不增加样本或改变排序；确有后续返修时可绑定
新的最终 Turn 更新原记录。陈旧 Turn、内容冲突或 revision 冲突明确拒绝，不重放副作用。
记录只在事务持久化成功后发布；取消等待不假定写入回滚，重试按同一身份收敛。
真实写任务始终由协作 owner 持有并负责等待结束；完成任务应及时回收，不依赖下一次评价
或关闭根会话才释放。关闭准入的临时状态只覆盖尚在收束的操作，跨进程封口消费上述
Studio 显式关闭意图；Core 生命周期仍只负责 owner 的真实运行与关闭，不另建随历史
child 数量永久增长的内存关闭目录或逻辑任务完成状态机。
存储与恢复见 [17](./17-studio-storage.md)。

评价按 `(accountId, modelId)` 跨会话查询，最近 10 条按更新时间与稳定身份排序；摘要
只统计此窗口并给出有效样本数与结果分布。无法判断、未知及小样本不冒充能力结论。
外部评价不与本地评分混算，不因经济/快速偏好降低验收标准，不上传公网。
