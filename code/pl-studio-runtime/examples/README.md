# 真实任务人工观察

更新器可通过 `updater_observe` 显式观察，不启动安装器：`state ARTIFACT_DIR` 在隔离 home
将设置文件设为只读并取消一次更新检查，保存 canonical 状态和文件未改写证据；
`download ARTIFACT_DIR [CANCEL_AFTER_BYTES]` 下载真实稳定 Release，可在指定进度取消。
下载前由父进程将 `LOCALAPPDATA` 设为证据目录旁的独立缓存目录；再次启动进程并使用同一
缓存，可观察恢复起点与完成校验。各次运行使用独立证据目录，取消保留非零退出状态和错误报告。
入口为 `cargo run -p pl-studio-runtime --features live-tests --example updater_observe -- ...`。
`report.json` 的 review 默认为 pending，运行完成不替代人工核对进度、文件和结果。

从仓库根目录运行，artifact 目录必须尚不存在：

```bash
cargo run -p pl-studio-runtime --features live-tests --example model_observe -- \
  openai gpt-6-astra /absolute/task.txt /absolute/new-artifacts
```

读取 anywork 用户配置中选定供应商的完整配置与系统凭据，不改写配置或会话库。
任务文件是实际待处理要求，不要求固定回答。可选参数：

- `--image FILE`：图片 bytes。
- `--image-url URL`：远程图片，保存请求期快照。
- `--image-base64 FILE`：保存完整原始 Base64 的文本文件，默认 PNG。
- `--followup TASK_FILE`：在同一模型会话中继续任务，可重复。

`events.jsonl` 保存过程，`response-N.json` 保存响应和服务端用量，
`report.json` 分开记录 execution 与 review。execution 完成不是验收通过；
review 默认 pending，由观察者阅读过程、结果和产物后另行记录结论。
缺少配置、鉴权失败、超时与事件缺口必须保留，不能静默跳过。
不会断言回答文字、工具次数、缓存命中或业务终态。

完整工具/协作任务使用 `collaboration_observe`，由操作者准备真实任务和 fixture，再显式运行。
它只收集事实和转交操作者决议，不替模型实现业务，不根据回复文字、工具次数或标记判断通过。
本 example 仅支持 Linux；非 Linux 在复制真实配置或启动业务前明确拒绝，不代表产品停止支持
Windows。Linux 人工运行前先安装同源码 helper：`cargo install --path code/pl-remote-helper --locked`。
example 默认从 PATH 启动 `pl-remote-helper`，真实检查协议版本；缺失或不匹配直接报告原生
worker 错误，绝不回退裸 Git、shell 或 process-wrap。局部隔离验证可仅为探针设置 PATH 指向
本次 `cargo build --locked -p pl-remote-helper` 的 `target/debug`，不改变用户全局安装。
以下路径必须替换为调用者本 Thread 的实际 `artifacts` 下的本次独立目录和任务文件：

```bash
ANYWORK_WORKFLOW_ARTIFACT_DIR=/absolute/current-thread/artifacts/task-case-01 \
ANYWORK_OBSERVATION_PROMPT=/absolute/task.txt \
ANYWORK_OBSERVATION_MODE=mode.task \
ANYWORK_OBSERVATION_DELEGATION_MODE=automatic \
ANYWORK_OBSERVATION_DELEGATION_PREFERENCE=balanced \
ANYWORK_OBSERVATION_SECONDS=1800 \
cargo run --locked -p pl-studio-runtime --features live-tests --example collaboration_observe
```

环境变量如下；不引入另一个通用命令行入口：

| 变量 | 契约 |
| --- | --- |
| `ANYWORK_WORKFLOW_ARTIFACT_DIR` | 必填，本 Thread artifacts 下本次独立目录。可预置 fixture、输入和 `decisions/`；`studio-home` 必须不存在，`files.jsonl` 也必须是本次新建。运行器无法获知宿主的 Thread 身份，调用者负责选择所属目录。 |
| `ANYWORK_OBSERVATION_PROMPT` | 实际任务文本文件；省略时保留原有只读双 explorer 观察提示词。Task 验证应显式给出任务。提交文本另存为 `input-prompt.txt`，清单保存其 SHA-256。 |
| `ANYWORK_OBSERVATION_MODE` | 默认 `mode.simple`，真实 Task 必须显式 `mode.task`。只支持这两个内置 Mode，其他值明确拒绝。 |
| `ANYWORK_OBSERVATION_DELEGATION_MODE` | `profile` 或 `automatic`；省略时使用真实配置默认值。仅传入创建根会话请求。 |
| `ANYWORK_OBSERVATION_DELEGATION_PREFERENCE` | `economy`、`balanced`、`fast`；省略时使用配置默认值。仅传入创建根会话请求。 |
| `ANYWORK_OBSERVATION_SECONDS` | 正整数 `1..=1800`，默认 `180`。到时记录 `timedOut` 和未完成事项，不能作为 Task 完成或验收通过。 |
| `ANYWORK_OBSERVATION_ACCOUNT` / `ANYWORK_OBSERVATION_MODEL` | 同时省略或同时设置为非空 Unicode。显式设置只覆盖新根会话的 `NewThreadModelRoute`，不会筛选账号或覆盖 child/Profile 路由。 |
| `ANYWORK_OBSERVATION_EFFORT` | 非空值，只用于显式 ACCOUNT/MODEL 根路由覆盖；覆盖路由而未设置此值时传 `None`，不猜模型的首个候选。未覆盖路由时完整继承所选真实 Mode 的 effort。 |
| `ANYWORK_OBSERVATION_WORKSPACE` | 本地模式可选，已准备好的小 fixture 目录，canonical 路径必须严格位于本次 artifact 目录内；拒绝 symlink 逃逸。只打开，不 reset、stash、提交或清理已有 fixture，允许刻意准备的脏状态。不得与 SSH workspace 同时设置。 |
| `ANYWORK_OBSERVATION_WORKSPACE_MODE` | `local`（默认）或 `worktree`。后者仅用于本地 fixture，必须有有效 HEAD，Git 元数据也须留在 artifact 内；SSH 不支持 worktree。 |
| `ANYWORK_OBSERVATION_SSH_ALIAS` / `ANYWORK_OBSERVATION_SSH_WORKSPACE` | SSH 模式必须同时设置为非空 Unicode；使用已有 SSH alias 和预先独立创建的远端 workspace path。不得与本地 `ANYWORK_OBSERVATION_WORKSPACE` 混用，且只能使用 `local` workspace mode。path 原样传给生产 `open_remote_project`，不在本机 canonicalize、读取、初始化或修改远端目录，也不修改用户 SSH 配置或凭据。 |
| `ANYWORK_OBSERVATION_HELPER_BUNDLE` | 可选，生产构建生成的 `data/remote-helper/` 资源目录；设置后用于 runtime SSH helper source。省略时使用默认 external helper（Linux 下从 PATH 查找）。 |

未给 workspace 时，在本次 artifact 下新建唯一 Git 项目，只创建最小 README 并形成初始 HEAD。
已有 fixture 不被自动提交或重写。`git/before/`、`git/after/` 保存实际 HEAD、NUL 格式状态、
未暂存与暂存差异；差异命令使用 `git diff --no-ext-diff --no-textconv --binary` 及其 `--cached`
版本，显式禁用外部 diff/textconv，同时禁用 pager、hooks 和 fsmonitor。stdout/stderr 分别流式
写入证据，receipt 保存实际退出状态、取消请求、错误及 terminal+drain 的实际耗时。Git 仍可能
启动 clean/process filter；全部 Git（包括默认仓库 init/add/commit 和 worktree rev-parse）
使用既有 `ManagedWorker` 的 exact argv 入口，唯一 owner 保留到真实 terminal control 与
supervisor exit；控制 clone 只请求 cancel，发送失败则关闭控制端，不能把受理或 EOF 当回收。
同一个 pinned wait future 与两条管道分别结算，在全部结算前持续响应原 deadline/预算/读取失败，
即使 leader 已退出，也等待 worker 监督、终止和回收剩余后代。不重建 process-wrap wait，
不丢弃 worker、wait 或 drain future 冒充回收。
receipt 的 `supervisorPid` 仅是监督者诊断身份，不能当 Git leader PID；`exitCode`/`signal`
来自业务 `ProcessTermination`，`workerError` 保留原生监督错误，`workerWaitReturned`、
`streamsFinishedBeforeWorkerWait`、`streamsSettled` 保留结算顺序。
stdout/stderr 在 worker 终态与 drain 结算后才按最终结果标记完整，
强制终止得到的 EOF 保留部分内容、标记不完整，关闭或读取失败也不能成为成功。

未跟踪内容范围由 `git ls-files --others --exclude-standard -z` 界定，不含 Git 忽略项。
按 NUL 分割原始路径字节，`untracked.jsonl` 的 `pathHex` 保留非 UTF-8、空白和换行等路径身份，
`contentFile` 指向逐文件流式复制的内容；实际 bytes/hash 仍由 `files.jsonl` 记录。
只采 workspace 内普通文件，拒绝 symlink、特殊文件、越界路径，以及 `.git`、`.anywork`、
`studio-home` 运行时目录；缺失、类型不支持、采集中变化和读取错误都记录并使取证不完整。
每次 before/after 最多 10000 个未跟踪文件、单路径最多 64 KiB，内容共用既有证据预算。
运行器不改全局 Git 配置或 hook。后续模型工具操作仍按真实任务和运行时权限执行。
SSH workspace 沿生产 SSH project 与 helper 路径执行；manifest 的 `workspaceLocation` 记录
`kind=ssh`、alias 和原始远端 path，`project.json` 保存生产 runtime 返回的实际 project。
SSH 不在本机读取或初始化远端 Git，也不生成 `git/before/` 或 `git/after/`；manifest 的
`unfinished` 明确记录远端业务 Git 快照未采集、需人工核对远端产物。因此真实 workflow
终态仍照常保存，但 `evidenceComplete` 为 false，不能把这次 SSH 采集报告为证据完整。

运行器读取 `ConfigStore::default_app()` 指向的用户配置，仅接受 schema 23 至当前版本且无 inline
account `bearer_token` 的原始 TOML bytes。它不会 dump hydrated 配置或读出 secret 供证据打印，
只复制配置原文和 `agents/` 首层普通 `*.toml`；拒绝用户 agents 目录/条目的 symlink。
不复制原 home 的历史、数据库、Mode 或其他资源，不改写 routes、effort、账号 enable/billing、
MCP、LSP 或 skills 配置。隔离副本由正常启动流程迁移；发生重置立即拒绝提交任务。
所引用的外部资源不可用时保留真实错误，运行器不会扩复制用户目录或私自改配置。
真实系统凭据只由生产运行时按原账号关联使用。
显式根路由覆盖在 manifest 中标记 `rootRouteOverride=true`，不能当作主要真实配置验收证据。

需要人工决议时，stdout 只提示真实 interaction ID 和 `pending/` 快照路径；快照包含真实
scope、revision、交互内容和 canonical Plan 正文。操作者先阅读，再在本次 artifact 的固定
`decisions/` 目录提交一条普通 `*.json`。建议先写非 `.json` 临时文件，写完后原子改名发布，
避免运行器读取半个文件。每个文件最多 128 KiB，一次运行最多 256 条。

最小计划批准文件如下；ID 和 revision 必须替换为当前快照实际值：

```json
{
  "operationId": "operator-approve-001",
  "interactionId": "<真实 interaction ID>",
  "expectedRevision": 3,
  "resolution": {
    "kind": "userInput",
    "data": {
      "answers": {
        "plan_confirmation": {"answers": ["Approve"]}
      }
    }
  }
}
```

要求修订时，答案改为 `{"answers":["Revise","请补充实际需要的修订意见"]}`。
`expectedRevision` 是 **interaction.revision**，不是计划 revision。外层拒绝未知字段；
`resolution` 使用生产 `InteractionResolution` 类型，不从模型文本生成。
运行器通过 `resolve_interaction(operationId, rootId, expectedRevision, interactionId, resolution)`
提交一次，保存 exact 输入 bytes/hash 和 API 实际 receipt 或错误，不删除输入、不修改数据库。
每个文件名只处理一次，修改已处理文件不重发；遇 stale 应重新阅读快照，并用新的文件名和
operation ID 明确决定，运行器不取最新 revision 自动重试，也不会因超时自动批准。
每次决议准入前核对场景截止时间和中断；若一条 resolve 已准入，就保留所有权并保存它的实际
receipt/错误，返回后立即重核停止，不再提交同批剩余文件。
不增加文件停止指令，使用 Ctrl+C 或观察截止时间。

`manifest.json` 区分 `taskCompletedObserved`、`taskStopped`、`timedOut`、`interrupted`、`evidenceIncomplete`、
`budgetExceeded`、初始化/采集/存储/API 错误及 simple 全树空闲观察；记录主错误、清理错误、未完成事项、
root/child 身份、实际 route/delegation、时间、水位来源及 SHA-256。
Task 候选完成必须来自当前完整 `agentDirectory`、各会话快照、最新持久化 Turn、
无 active Turn/activity/execution/pending interaction，以及工作流 `Terminal` 且
`current_state_id=completed`；`current_run=None` 不是完成，历史 failed Turn 留给观察者判断，允许 root 返修。
清单的 `rootWorkflow` 与 `rootWorkflowSnapshotRevision` 保留最后实际观察的工作流及其快照提交修订号，
与采集的 `termination` 分开：工作流已 completed 但采集欠证据时如实列出欠项，超时不抹掉该工作流事实。
候选全树空闲后，通过既有 `synchronize_thread_observation` 逐成员同步产品投影和历史移交水位，
重新读取 Ready 完整目录、各 Thread 快照和公开最新 Turn 历史，再复核目录没有变化。
根会话和任何未关闭成员仍必须有健康、无故障/压力暂停/恢复闸门且 durable 已追平 accepted 的真实存储水位。
仅同树非 root、目录 Closed 且 settled、无 execution/canStop/awaitingScheduling/budget pause，
快照也为 Closed、无 active Turn/activity/pending interaction、runtime 存在且无 execution 的 child，
允许在 `storage=None` 时另取 `closedHistory` 证明：公开 `list_thread_turns(id, None, 1)`
成功通过既有持久 checkpoint/history fence 栅栏且返回非空、身份匹配的最新终态 Turn。
这记录为 `historyCheckpointValidated`，不编造 fence 数值，原缺失 storage 仍保留 None；已有 storage
故障或水位未追平不能被历史证明遮蔽。空历史/非终态仍阻塞，Busy 明确列为 pending 并受场景截止限制，
损坏、身份或其他 API 错误直接保留失败。snapshot revision 不是 history fence，也不是 notification revision。
同步前后重复该成员采样，快照、持久证明及实际 Turn id/revision/state 必须稳定，成员变化同样重新观察；
simple 空闲结束也复用这套确认。截止时间和 Ctrl+C 同样适用于同步及历史读取等待。
`completion-observed.json` 保留目录、逐成员 `live` 真实水位或 `closedHistory` 证明，以及同步前后
快照和终态 anchor，并明确 `atomicSnapshot=false`：
这些逐 Thread 同步和重复采样不是跨全树的原子事务。

公开快照的权威 activity 投影覆盖 Turn 已结束后仍为 Running 的后台工具任务；成功读取的
`activity=None` 因而证明该快照水位没有 Running 工具。不能只看目录 Idle，也不能把事件流
缺口当作零任务。收束导出另检查完整 timeline 的 typed 工具状态，未终态工具的真实
item/call/task 身份及状态保存在逐页 `.nonterminal.json`，读取错误和具体未完成项留在清单中。
取消、失败和中断仍是终态事实，不代表任务验收通过。

root 必须无 continuation；仍 open 或待调度的 child continuation 也阻塞结束。对当前 canonical
directory 已为 Closed、且无 active/activity/execution/pending interaction、最新 Turn 已终态、
满足上述持久性证据的退役 child，允许保留历史 continuation，并完整记录为 `retiredOwedWork`。
这不表示其子任务成功，也不证明 workspace 或其他物理资源已全部回收；实际 close 工具结果、
`shutdown_runtime` 响应和进程证据分别保留供审查。
`taskCompletedObserved` 仅表示 canonical 完成已被观察；`evidenceComplete` 还要求导出完整、
无具体未知/错误且 runtime 正常关闭。历史失败、退役欠账、关闭产物与审核结果仍由人工判断。
simple 的空闲终态只代表该观察结束，不能证明任务成功。任何不完整采集返回非零状态，
即使正常收集结束也必须由人工/reviewer 根据完整证据独立验收。

场景时长只解析一次，在异步准备前建立同一个绝对 deadline，覆盖准备 Git、运行前取证、初始化和实际观察；
小量 rev-parse 输出也最多读取 64 KiB，完整原文仍受 Evidence 总预算约束。每次新观察、
决议准入和 simple/Task 完成声明前后都重核 deadline/中断。只读观察等待允许按该边界取消；
可能准备资源或产生副作用的 initialize/open/create/subscribe/resolve 已准入后等待真实返回，
拿到返回值的 owner 再决定停止，不丢弃责任。`scenarioElapsedMillis`、`admittedOperations`
分别记录场景耗时和已准入操作耗时及返回时停止状态。

场景停止后不再提交业务决定。末端事件确认与最终证据导出（包括 after Git 取证）共享独立的
**绝对 30 秒总预算**，不按页、Thread 或文件重置；读取超时后记录具体未完成项，停止新增导出。
随后仍真实 join writer，并调用、等待 `shutdown_runtime`，保存实际关闭响应；不 abort/丢弃
句柄宣称回收。`cleanupElapsedMillis`、`cleanupBudgetExpired`、每个事件 writer 的
`joinElapsedMillis` 和 `shutdownElapsedMillis` 分开保留实际时间。场景上限及取证清理预算
不是强制杀进程时限，已准入副作用收束、真实 join/shutdown 可能超过它们。订阅丢弃只停止
观察，关闭 runtime 只是清理，不能用来反证任务已完成。

每个 Thread 的事件区间从实际消费的首个 snapshot 开始，以最终公开 Turn 查询取得的精确
`{turnId, turnRevision, terminalState}` 为语义末端。writer 连续消费且实际观察对应终态 Turn
通知后才确认；最多保留 1024 个终态锚点，已消费的精确匹配可复用。manifest 的 `events`
分别保留首帧 canonical revision、消费末端 subscription epoch/revision、目标和匹配帧水位。
两个 revision 域不能比较；终态可能是 live 或 retained 重放，公开 API 无法区分，清单如实
标注，不宣称覆盖到候选快照全部 canonical commits 或关闭前全部通知。最终快照、持久 Turn
及完整 timeline 仍独立导出。无首帧、gap/lag、提前 EOF、无可用终态锚点、缓存超限或清理预算
内未确认，都使区间 unknown/incomplete 并影响 `evidenceComplete`。收到 stop、recv None 或
写文件正常结束本身都不代表完整。
若 EOF 发生在已消费的目标锚点之后，可复用该精确匹配来确认此前的区间；清单保留
`streamEnded=true`。EOF 前没有匹配锚点时不能成立，也不在 EOF 后假造新通知。

证据包括 `root-thread.json`、`directory/`、`samples/`、`pending/`、`decision-inputs/`、
`decision-receipts/`、每个 Thread 的 `events.jsonl` / `snapshot.json`、逐页 Turn 与 timeline，
以及逐字段详情正文。Turn 页最多 200 rows / 2 MiB，timeline 每页最多 100 条并按 opaque `before`
读到 `hasOlder=false`；详情绑定 field/revision，用 64 KiB continuation chunks 流式写入，
不把 preview 当全文、不把整段历史累积为 Vec，也不把 opaque ID 直接当路径。
`files.jsonl` 是 manifest 引用的文件索引，保存身份到索引文件名的映射、实际 bytes/hash 和完整性；
`inputs/` 保存不变的原始配置/Profile 副本，`studio-home/` 索引项以 `mutableAfterCapture=true`
明确标为初始化时的取证，之后由正常启动迁移管理，不把初始 hash 冒充迁移后的当前内容。
timeline 页与详情引用保留 saved/lifecycle/revision，manifest 的 `threadExports` 保存逐 Thread
快照 revision、真实存储水位、最新 Turn、页数、详情字段数及导出完整性。清单另保存二进制 SHA-256，以及本构建
嵌入的关键 system/Task/角色提示词和协作 Skill 来源 SHA-256，不依赖运行后 checkout 的内容。

采集限制为总证据 256 MiB（为失败清单预留 1 MiB）、最多 64 个 Thread 和 10000 条 timeline
条目。采集器写入严格计量；Studio 自有数据库、fixture、provider 原始输出由每 500ms 的真实磁盘
采样计量，API 调用期间和采样之间的运行时写入可能超过阈值，发现后停止采集并正常回收。
不能把这一采样阈值理解为文件系统配额。达到预算保留不完整和真实错误，不静默截断为完整。
`studio-home`、原始配置、事件、工具完整参数/结果及供应商敏感原文都是私有证据，**不能直接
作为公开 PR 附件**；分享前须在后续独立副本中检查和脱敏，保留原始验证事实。

GUI 真实任务通过 `cargo xtask run-gui --driver` 启动，由观察者使用 Flutter Driver
提交任务、查看流、截图和产物，并人工记录结论。自动 Rust 测试仅保留在
`pl-core` 和 `pl-model` 两库；此处不再承诺配置迁移、恢复或
GUI 场景的自动断言；隔离模拟入口使用 `cargo xtask manual-gui`。

执行侧会话目录与 Git 池 ignore 可用 `session_layout_observe` 观察，不读取用户供应商配置：

```bash
cargo run -p pl-studio-runtime --example session_layout_observe -- /absolute/new-artifacts
```

可选 SSH 观察复用已授权的隔离 helper 环境变量（`PURE_SSH_TEST_SERVER` 等），不改用户 `~/.ssh/config`。
