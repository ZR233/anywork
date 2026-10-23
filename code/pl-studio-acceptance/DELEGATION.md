# 子代理分发原生人工验收 runbook

这是 **manual-gui 显式人工观察**，不新增 Rust test、不进入自动门禁。真实生产
Runtime、Thread 工具、bridge、Client 和原生 GUI 负责准入、过滤、派发、评价和持久化；
fixture 仅模拟 loopback 外部供应商及响应 gate。`verdict.json` 始终从 `pending` 开始，
命令成功不能替代人工查看截图、canonical 状态、请求与进程证据。真实账号的有界任务由
主代理另行执行，不能从模拟或 Linux 单平台结果外推兼容性。

## 启动与资源所有权

从仓库根目录运行，每次指定一个尚不存在的证据目录：

```bash
cargo xtask manual-gui --scenario delegation-routing --output <artifacts>/routing
cargo xtask manual-gui --scenario delegation-lifecycle --output <artifacts>/lifecycle --retain-environment
cargo xtask manual-gui --scenario delegation-window --output <artifacts>/window --retain-environment
cargo xtask manual-gui --scenario delegation-enablement --output <artifacts>/enablement
cargo xtask manual-gui --scenario delegation-recovery --output <artifacts>/recovery --retain-environment
```

默认是有交互终端的原生 debug/Driver 场景。Linux SSH 没有显示时，复用已有的
`GDK_BACKEND=x11 xvfb-run -a ... script -q -e -c '<上述命令>' /dev/null` 入口；动态
端口不使用 `1420`。Xvfb 由外层 `xvfb-run` 拥有，必须等待外层命令退出后核对回收。
不能直接运行 `flutter run`，也不要使用 demo。GUI 未完成生成/编译时不要盲启动。

可选 `--delegation-driver <当前会话 scratch 中的 Dart 脚本>`。harness 通过已有纯
Dart Driver 入口运行它，依次传入：

1. 本次实测 VM Service URL；2. 合成 Git project；3. 本阶段 evidence directory；
4. 合成 environment root；5. `first` 或 `reopen`；6. fixture loopback origin。

脚本复用 `test_driver/flutter_driver_session.dart`，所有调用有界，`finally` 关闭
连接；它只能通过真实 UI 执行业务操作、通过 snapshot 观察。返回非零是失败，不吞掉
assertion。**脚本返回前不要 shutdown 应用**，harness 随后调用既有
`manual_capture.dart`，要求 `capture-stage.txt=shutdown_completed` 并等待所属 GUI
进程真正退出。无脚本时，外部 Driver 操作完后输入 `done`，其他动作码仅记录、不会替你
点击 UI。生命周期、窗口和恢复场景会在第一次 `done`/脚本返回后自动重开同一 home，第二次
`done` 才结束。EOF、取消、超时、缺主流程、provider 拒绝、Driver 非零、shutdown 或
进程退出异常都向最外层非零传播。

fixture、Flutter/DTD/GUI、Driver 都沿用 `OwnedProcess` 所属进程组的正常/失败回收。
取消优先发送本次伪终端 Ctrl-C，再等待宿主 exec 终态；不能用全局 pkill。成功关闭后
`--retain-environment` 才保留**整个环境根**并写 `retained-environment.json`，不能只复制
home 导致工作区绝对路径失效。重开仍需原 fixture 端口；结束后的 retained environment
主要用于冷目录/资料/截图，不承诺停掉的 loopback 端点还能执行模型。

账号 ID 带本次 PID 与隔离环境随机名，重开沿用原配置；A/B 都有同一个
`delegation-shared`，分别指向
`/v1/delegation-a/responses`、`/v1/delegation-b/responses`；A 另有
`delegation-other`、十个合法分页样例和四个不可选边界。第三个官方协议账号没有凭据。
模型元数据和价格未知，不借全局内置目录补齐。普通选择器不应显示已禁用、不支持文本或
未知上下文；`delegation-no-tools` 仍可能是普通文本候选，但必须被子代理候选过滤。

这些预置账号无 bearer token、无环境凭据，compatible loopback 允许无凭据连接。
**不要在此场景创建/录入真实账号或凭据**；`ANYWORK_HOME` 并不隔离系统 keyring。
如果必须通过 UI 创建账号，先复用现有 provider-usage 场景的私有 D-Bus/XDG/keyring
所有权方案，不新增生产内存凭据开关，不读写操作者 keyring。所有生产默认路由和 Mode
路由都已指向 A，不应访问官方网络。

## 工具发现的消费约定

`discover_tools` 把 query trim/lowercase 后作为**一个子串**匹配 toolId，不分词、不把空格
连接的多个名字当 OR，也没有可传入的分页/limit。生产端最多返回20个 `toolIds`。

- automatic root 使用合法共同子串 `delegation_model`，typed 读取必填 `toolIds: String[]`，
  要求结果实际含 list_delegation_models 与 get_delegation_model，且下一次请求两工具确已
  出现在声明中；空结果不能代表揭示成功，不能绕过 discover 直接发模型查询。
- child 保留初始及发现后的 root-only 声明检查，依次用四个单名字 query：spawn_agent、
  list_delegation_models、get_delegation_model、evaluate_agent。每次都必须是 typed 空数组，
  每步后四个 root-only 声明均仍缺席；非空结果（包括20条截断结果）不能证明隔离。
- 发现回执的 missing/null/非数组、空或重复 ID、超过20条均失败；原 callId/name/query
  参数必须对应，不复用旧多词查询结果。没有空 query、通配或一次截断列表的漏检捷径。
- 每个 child authored Turn 正常脚本为四次真实 discover 模型响应加一次 final 响应，共五次
  provider 请求；四个 callId 使用同 Turn 前缀及各自索引，返修输入有新的前缀，不重复调用
  身份、不提高生产 step limit。供应商 observation 仍保留各次 discover 与最终完成，原
  required final checkpoint、关闭后零新增 child 请求及 F1/F2 oracle 均不变。

有限 HTTP 消费方回放只能证明发送查询、typed 回执校验及脚本步数；不能以重放空回执
代替真实 root 的揭示或 child 权限隔离，更不能补造成功目录/历史来宣称 GUI 主流程通过。

## 列表 latest Turn 的可空投影与完整证据

Turn 标识只在所属 Thread 内解释，跨 child 的完成证据使用 `(childId, turnId)` 联合
身份；不同 child 的原始 turnId 字符串可以相同。fresh reviewer 必须真实重新 spawn，
agentId 不复用此前 reviewer 或 executor，reviewTarget 绑定原 executor，并取得该新
child 的真实 committed completed/no-pending 报告；最终评价仍核对它自己的最新 Turn 与
冻结 route。不能用跨 child 的裸 Turn 字符串不等代替上述独立性证据。同一 executor 的
续修则仍须有不同于前轮的 Turn、更高 commitSequence 和真实新输入/输出证据。

`list_agents.lastTurn` 是 Option 投影，不是完整历史索引；Open child 也可以为 null，
不能从 Open 推断该字段必有值。评价预检、原 child 续跑完成、recovery 目录核对以及关闭
负例统一使用同一项最新终态校验：

- 有值时必须是同一真实 report/evaluation 所绑定的 Turn 且 finished/completed；不同 Turn、
  running、failed、cancelled、interrupted 等明确失败，不改走历史来掩盖冲突。
- 缺失时必须真实调用既有 read_agent_session：descending/full，每页50、最多4页，核对
  target/直接父子 path/稳定分页水位/顺序，找到最新 typed normal completed Turn，且其
  opaque turnId 与真实 report 完全一致；没有页、越界、错误目标/状态都失败，不跳过。
- 关闭负例保持更强的前后独立历史查询，即使列表有合法值也照样取证。所有调用共用已有
  一个历史解码器，不为 Open/cold 再复制一套 DTO 或历史算法，不读取私有 DB。
- childId、正 committed sequence、冻结 Profile/route、noPending/noTask、直接父子关系、
  send ACK/严格增序列与新 Turn/commit、实际 provider 新输入输出证据不变；评价仍提交真实
  expectedTurnId/expectedRevision，并核对宿主最新身份/CAS 回执。列表缺字段不授权评价。

只读历史查询使用各阶段独立 callId，从当前公开水位读取，不唤醒 child 模型，也不提高
生产 step limit。截图或 provider final 本身不能代替这一 latest committed 终态证据。

历史 Item 的 state 使用生产的 kind/data 形状。私有消费 DTO 用 Serde 内部 kind tag 与
已知 variant 的显式 data 字段作薄投影：普通或未知非 Turn Item 的对象载荷可以忽略，
但它们永远不是 Turn 证据；thread/ordinal 等外层字段仍由原规则核对。
一旦 kind=turn，data/state 必须严格解码，缺失或损坏不能转成 Other 跳到较旧 Turn。
该 Turn 的 running/failed/cancelled/queued/budgetLimited 或未知非 completed 状态即使
携带对象 data，也只表示非完成，必须在最新 Turn 判定处拒绝。completed 必须有正常
completion=normal 及 completedAt>0；InteractionRequested 等不默认成 normal。
不使用 untagged 载荷失败 fallback、不手写历史 JSON 映射、不新增另一份历史解码器。

## 1. delegation-routing：固定与三个短偏好

在同一环境用附件旁设置菜单创建 **四个不同 root**，创建后不可切换策略：

| root 策略 | 输入框提交的完整 marker |
| --- | --- |
| 固定 Profile | `[[delegation:routing:fixed]]` |
| 自动 / 经济 | `[[delegation:routing:economy]]` |
| 自动 / 平衡 | `[[delegation:routing:balanced]]` |
| 自动 / 快速 | `[[delegation:routing:fast]]` |

主模型保持 A/shared。固定 root 的 explorer 必须使用已配置 A/other/high，不接受 root 路由
冒充 Profile 路由。自动 root 从真实 `discover_tools`、有界模型查询、详情的结果选取
A/shared、A/other/low、B/shared，逐一真实 spawn→终态报告→绑定真实 child 的独立审查→
最终评价→close（固定模式也实际调用评价工具）；不是从
fixture 的期望清单重新实现候选路由器。第一个自动 child 使用 `obsolete_route` 角色，
其旧固定路由刻意禁用，证明角色资格与选择模型分离。它仍受原 Profile 工作区权限约束。

检查并保存：省略 limit 且有后续页时首屏必须恰好 5 条（本场景有超过 10 个合格样例），
后续尾页只要求不超过 5 条；显式 max 10 另行断言。另核对生产游标稳定分页、0/11 limit 真实拒绝、未知 task category
适配标签不做硬排除、disabled/no-text/unknown-context/no-tools 和缺 credentials 的详情
`available=false` 与 reason、撤下型号 NotFound；未知价格/计费/未采样速度不冒充免费、
套餐或零延迟。每个 root 实际请求仅有自己当前那段短偏好，固定没有偏好；不注入完整
目录描述/评价评论。偏好只影响提示词，本脚本不声称真实模型一定按某种偏好选中特定型号。

**截图**：默认模式/偏好，草稿跟随/覆盖及有效值，冻结 Thread 策略，子代理菜单中 A/other
与 A/B 同名型号的账号区别，长名/窄窗口、状态不挤出。全局修改后旧 root 保持原值，
草稿覆盖不污染默认；这些 UI/canonical 行为由 Driver 独立断言，fixture 不冒充证明。

## 2. delegation-lifecycle：完整交付、审查、返修、最终评价

`first`：创建自动/平衡 root，提交 `[[delegation:lifecycle]]`。真实工具依次：

1. 从生产查询选 A/shared 执行者、B/shared 审查模型；执行者 directory 仅写 `work`。
2. executor 真实初次交付，root 解析 spawn 的 agentId 与终态报告的非空 childId/turnId、
   正 committed sequence、completed 状态及无运行任务/待处理交互/权限。`turn.inputId`
   是可空的 chat input 身份，消息触发 Turn 可为 null；`messages` 是结果可见身份的投影，
   可为空，不是完整 inbox 消费清单。有 inputId 时检查其有效性，有 messages 项时逐项
   检查 id/sourceId/sequence/consumed；不解析 opaque Turn/message ID 的内部格式。
3. 新建 `reviewer-initial`，以真实 `reviewTargetAgentId` 绑定原 executor，独立报告要求
   返修。它的本次审查任务完整交付后，最终评价为新记录 revision 1 并真实 close；不再续跑。
4. `send_message` 给原 executor，核对真实 target、有效 messageId 及严格推进的交付
   sequence。不能要求报告 `messages` 包含该 messageId，也不能拿 chat inputId 与它
   比较。fixture 记录 child provider 请求实际收到的本次新输入：场景 intent、真实 target、
   输入 SHA-256 及对应 final 响应；新终态必须同 child、commitSequence 严格推进、Turn 与
   前轮不同，并与真实 list_agents 的 latest completed Turn、冻结 route、无 pending 状态
   一致。随后
   **重新 spawn** `reviewer-repair`，在 fresh context 中以真实 review target 绑定同一个
   executor、独立冻结角色及模型。它的 agentId 与首轮 reviewer 不同，报告的联合身份
   `(childId, turnId)` 不复用首轮；原始 Turn 字符串允许相同。首次修复经
   该新 reviewer 批准后，才最终评价 executor 为 revision 1；新 reviewer 自己的最终评价
   是另一条 revision 1 记录，随后真实 close。原 executor 续跑始终保持 child/frozen route。
5. executor 同终态同内容重试必须返回同一记录、revision 和原时间；相同 Turn 内容冲突
   真实拒绝。reviewer 从不通过 send/“清上下文”冒充 fresh-context 复审。
6. 故意增加一个确实新的后续要求：原 executor 的真实 completion 请求在外部 gate
   已到达并保持未完成后，root 评价旧终态必须拒绝。不是点击+sleep 猜测 running。
   这个 running 阶段先被生产 idle 准入校验拒绝，要求真实错误含完整的具体内层原因
   `child still has running work, pending input, interaction or permission`；不要求此时已进入
   latest-Turn 比较，也不接受任意错误或 JSON 成功回执。只有消费该拒绝后 fixture 才释放
   供应商响应。root 收到同 executor 的新 committed 终态且无 pending 后，再分别验证
   旧 Turn 的 `latest committed terminal Turn` 拒绝和旧 revision 的 `revision conflict`
   拒绝；这两个后续步骤不能用 running 阶段的原因替代。
   后续交付再 **spawn 第三个真实 reviewer `reviewer-late`** 独立验收；其 agentId 与前两位
   都不同，报告的 `(childId, turnId)` 联合身份不复用前两位，原始 Turn 字符串可相同，
   reviewTarget 仍绑定原 executor。只有 executor 的原评价更新到 revision 2；第三位
   reviewer 是新任务、新记录 revision 1。B/shared 详情此时必须有三位不同 reviewer 的
   三条 revision 1 记录，而非一位 reviewer 的 revision 2。第一阶段保留 executor 与第三位
   reviewer 供专门冷关闭，前两位已真实关闭，因此最多同时 2 个 Open child。

root 显示 `delegation lifecycle complete` 后，另建一个自动 root 提交
`[[delegation:foreign]]`；它只使用 fixture **从真实最终收据观察到**的 child/Turn 身份，
真实 `evaluate_agent` 必须拒绝非直接父 root。不伪造 childId，不使用父 Turn，不通过
HTTP 创建 CallContext。child 请求还核对自身根本没有 spawn/list/get/evaluate 声明。

记住原 lifecycle root 的真实 ID，第一阶段截图并 `done`。`reopen` 自动用同一 home 重启：
打开**原 root**，提交 `[[delegation:cold]]`。冷列表/评价详情读取保存的冻结事实，验证
原 executor revision 2 与三位 reviewer 各 revision 1 的内容、时间不变，并确认前两位仍
Closed。此时只 close 保留的 executor 与第三位 reviewer，取得真实 Closed/preserve 回执；
最终四个真实 child 都须 Closed 且保留冻结模型。之后对 Closed executor 再 send 必须拒绝，
不是先关闭全树后又用 send 激活。成功 close 会移除已关闭 owner，因此这里也经过真实
activation 拒绝链，而非假定存在一个热 owner 的 `closed` 错误。关闭负例使用合法的 sample
供应商输入，按下面的联合证据校验；若生产错误执行，供应商会正常回答并留下请求。
第二阶段 child completion
计数必须与第一阶段相同（正常 root completion 不计为 child 调用）。结束时再次 `done`。

Driver 的外部 marker 不变：第一阶段原 root `[[delegation:lifecycle]]`、另一 root
`[[delegation:foreign]]`；第二阶段选回原 root `[[delegation:cold]]`。provider state 的
`lifecycle_complete` observation 收据现在是 `executor`（revision 2）、`reviewers` 数组
（按首轮/修复后/新增要求后三位排列，各 revision 1），不再有单个 `reviewer` 更新到
revision 2 的字段。`reviewReports` 提供三组真实 agentId/turnId/commitSequence 与相同的
reviewTargetAgentId；`closedBeforeReopen` 是前两位，`pendingColdClose` 是 executor 与
第三位。`cold_close_complete` 收据的 `closedChildren` 必须含这四个真实 ID，评价内容与
时间不变；UI 智能体列表的冻结模型还须与上述实际收据逐项核对。

返修关联不依赖可缺失的报告消息元数据：send 文本携带的是 fixture 自有 intent 标签，
不是宿主 messageId 或权限。provider observation 的可选 `continuation` 保存实际收到的
`targetAgentId` / `intent` / `inputSha256` / 对应 `output`；只有同冻结 route 的实际 child
请求因该输入生成 final 响应才记录该证据。父侧仍独立核对真实 send 收据与最新终态，
不从标签推导 Turn ID，不伪造 Runtime 消费身份，也不以供应商到达替代 committed 完成。

## 3. delegation-window：有界窗口、Unicode、幂等之外的持久化

自动 root 提交 `[[delegation:window]]`。脚本顺序创建/终态/评价/关闭，A/shared 11 个
真实被评 child、B/shared 1 个，总共 12 个；每个先经一个真实独立 reviewer 验收，再
评价并关闭双方。reviewer 使用 A/other，因此不污染 A/B shared 的评价窗口。不扩大
生产并发 limits、不插 SQLite（12 个被评 shared 样本加 12 个 reviewer，共 24 个真实
child，最多同时 2 个 Open child）。覆盖：

- 300 Unicode 字符含首尾空白原样保存；301 多字节字符（含空白）拒绝；纯空白拒绝。
- `notRated` 携分拒绝；`failed` 缺第二项分数拒绝；合法 notRated 不带分、不参与均值。
- 从真实已提交评价收据得到期望集合，详情严格比较 A 最近 10 条更新时间/稳定身份降序、
  原始内容、revision、时间和均值；B 同 modelId 独立窗口，不混账号、不把调用数当任务数。

第一阶段 `done` 后在 `reopen` 打开原 root，提交 `[[delegation:window-reopen]]`，不再
创建 child；读取恢复的真实工具历史和产品评价详情，完整比较同样 12 条收据的有界投影，
并核对第二阶段没有新增 child completion。此阶段新 root 查询不能替代“重开原 root”。

## 4. delegation-enablement：即时保存、真实在途 gate 与新准入

两个自动 root，A/shared 为在途 root、A/other 为观察 root；不能在一个运行中的 root 改
冻结路由。账号启用开关使用真实 GUI（必要时滚动定位），不是直接写 config/数据库。

1. A/other 观察 root 先提交 `[[delegation:before-disable]]`，保留真实分页游标；从真实全局
   候选选出 B/shared，再用该实际账号查询其候选和详情，记录它原本确实合格、descriptor
   enabled=true、available=true。后续只从原 root 的真实工具历史恢复这份身份与证据，
   不从 fixture 清单或 A 的账号字符串推造 B。随后 A/shared root 提交
   `[[delegation:inflight]]`。轮询本次 fixture
   `GET <fixtureOrigin>/delegation/state`，等 `inflightArrived=true`，表明确有 completion
   请求到达，不能用 sleep 推断。
2. 账号 A/shared 开关关闭即保存，无额外“保存”。取 canonical revision、enabled、pending、
   error，打开/返回再读；暂不释放供应商。A/other 观察 root 提交
   `[[delegation:inspect-disabled]]`，旧目录水位游标必须真实拒绝，新的 query 必须排除
   A/shared，详情 false/reason。
3. UI 关闭 B/shared，A/other root 提交 `[[delegation:no-candidates]]`：B 的真实过滤查询
   为空，原 B/shared 的详情仍存在、descriptor enabled=false、available=false，且完整
   unavailableReason 为当前生产的 `configuration error: role executor uses disabled model
   <accountId>.<modelId>`。详情、空候选与禁用前证据必须绑定同一实际账号/型号。
   使用该原候选的合法 route/effort、原 explorer 角色和供应商能正常处理的 sample 输入
   尝试派发；错误只接受真实外层精确文本 `child configuration resolution failed`，不能
   单凭它或任意错误证明禁用，也不能接受 Spawn/Sent/其他 JSON 成功回执。
   派发前后分别真实 list_agents，完整身份/父子集合不变、无新增或残留 child；B/shared
   真实 provider 请求和所有 child 请求计数均不增加，不能 fallback 到其他模型。
   目录与计数基线在真正发起该 spawn 时录入同 callId 的 observation receipt，回放只能
   读取原基线，不能重取较大计数。结果还须精确关联 callId/name/完整 arguments。
   若生产错误派发，fixture 不检查 disabled 自行拒绝，而正常回答 sample 并记录请求，
   再由上述目录/请求 oracle 硬失败；场景最终观察也不允许任何 child provider 请求。
4. 记录即时 canonical 禁用后，发送本次 fixture 的外部环境动作：

   ```bash
   curl --fail-with-body -X POST '<fixtureOrigin>/delegation/release' \
     -H 'content-type: application/json' --data '{"gate":"inflight"}'
   ```

   gate 未到达提前 release 返回 409。原调用应正常完成；用真实 Thread/Turn canonical
   Completed、截图和 gate 记录证明“禁用未取消在途调用”。
5. 原 A/shared root 提交 `[[delegation:disabled-next]]`，观察真实准入失败与原始错误，
   provider 状态没有新请求。若这个 marker 到达 fixture，整个场景强制失败。
6. 开关重新启用 A/shared 后提交 `[[delegation:enabled-again]]`，新调用才成功，最后 `done`。

CAS 冲突/快速开关必须由 UI canonical 观察或允许的真实 settings typed CAS 操作产生，
不能仅以 fixture 请求计数宣称 CAS 通过。全局默认重开、Settings 与草稿 pending/error 的
细粒度断言由 Client/adapter 契约及最终 GUI Driver 证据共同承担。

## 5. delegation-recovery：正常退出后同 child 续修与显式关闭对照

此独立场景验证 [12](../../design/12-collaboration.md) 的关闭意图区分，不修改原 lifecycle
的三位 fresh reviewer / executor revision 2 / 冷关闭无 child 请求 oracle，也不修改 window
最近 10 条与 routing 分页。Core `Closed` 只表示上一个 owner 已关闭；不能仅从冷列表的
该值推断 child 被持久禁止恢复。只有真实 `close_agent` 成功收据证明本场景的显式关闭。
生产恢复修复经独立审查后才由 root 运行本场景，静态检查和 fixture 回放不算 GUI 通过。

### first：完整交付后保留 executor，显式关闭 reviewer

新建自动/平衡 root、主模型 A/shared，提交 **`[[delegation:recovery]]`**：

1. 通过真实 discover/query 选择 A/shared 的 directory executor（仅 `work`）与 B/shared
   reviewer；记录真实 spawn、completed/no-pending 报告，reviewTargetAgentId 绑定 executor。
2. fresh reviewer 完整独立审查通过后，两者各创建自己的最终评价 revision 1；再真实
   `close_agent` reviewer，取得 Closed/preserve 收据，executor **不显式关闭**。
3. `recovery_first_complete.receipt` 保存 `rootAgentId`、`executor` / `reviewer` 两份事实：
   `agentId/profileId/model/messageSequence/turnId/commitSequence/evaluation`，以及
   `reviewerClose` 的真实 target/lifecycle/workspaceDisposition。executor 此时必须 Open、
   reviewer 必须 Closed，无 pending，所有模型/父子/最新 Turn 与真实目录一致。
4. root 显示 `delegation recovery first complete` 后保存截图、canonical 状态与真实 root ID，
   输入第一次 `done`（或 first Driver 正常返回）。harness 正常 shutdown，等待
   `capture-stage.txt=shutdown_completed`、GUI 真 exit 0 和所属进程回收，再同 home/同 fixture
   端口启动 reopen。不能先向 executor 发送新输入，也不能在 first 偷跑 reopen marker。

### reopen：原 root 恢复同 executor，独立复审后更新原评价

打开 **同一个原 root**，不是另建 root，提交 **`[[delegation:recovery-resume]]`**：

1. 从恢复的真实工具历史读取 first 的两份 spawn/评价和 reviewer close 收据；恢复的报告
   必须匹配原 child/Turn。先真实 list_agents / detail 核对冻结模型、直接父子、原评价内容及
   revision/时间，不能只用 fixture 内存当产品持久化证明。executor 冷目录可以显示上个 owner
   的 Closed，不以此拒绝续修；已显式关闭 reviewer 必须保持 Closed。
2. 对该 reviewer 发送新输入，要求 **真实 send_message 工具错误**，不是成功 ACK。
   当前真实冷关闭失败的模型可见外层是精确文本
   `Agent service failed: Thread activation failed`，并不含 `closed` 或 `not open`；不从
   该文本单独推断内部原因。有效合成输入 marker 为 `[[delegation:child:recovery-closed-probe]]`；如果
   生产错误地执行它，fixture 会正常回应并记录该 child 请求，不会自行拒绝来伪造负例。
   `recovery_explicit_close_rejected` checkpoint 只能在消费真实工具拒绝后出现。
3. 给原 executor 发送一个明确的新小型续修要求。真实 send 回执 target 相同、messageId 有效、
   sequence 严格大于 first 的 spawn.messageSequence。复用 continued_report：child provider
   实际收到本次输入，正文 SHA-256/intent/output 匹配，且新请求仍有原初次任务和交付上下文；
   同 ID/冻结 route 的新 committed Turn 必须与前次不同，list_agents latest completed 一致。
4. **重新 spawn** fresh reviewer，绑定原 executor，agentId 不复用已关闭 reviewer，
   该新 child 的报告按真实 `(childId, turnId)` 联合身份区分；不同 child 的原始 Turn
   字符串可以相同，不假定 opaque Turn 字符串全局唯一。
   新 reviewer 独立审查新增范围通过后，executor 更新原评价为 revision 2（createdAt 不变），
   新 reviewer 自己创建 revision 1。旧 reviewer 评价完整原样保留。
5. 真实 close 新 reviewer 与 executor，取得两份 Closed/preserve 收据。最终目录三 child 都
   Closed、模型不变、无 pending；最多同时两个 Open child，不提高产品并发上限。
   `recovery_complete.receipt` 保存 `rootAgentId/executor/initialReviewer/reviewer` 三份最终
   child 事实、`continuation` 真实 send 收据、`closedSend` 的 callId/tool/target/toolError/
   前后目录状态/请求计数，以及
   `closeReceipts` 三份真实 close 收据。此时第二次 `done` 才结束；不需要第三次重启。

### 外部证据与完整成功判定

- 四个 child final checkpoint 必须恰好各一次：`recovery_child_initial`、
  `recovery_child_review_initial`、`recovery_child_repair`、`recovery_child_review_resumed`。
  供应商只模拟外部结果，实际 route 仍核对 endpoint/model/effort 和工具回执，不靠 /models。
- `observation.inputTargetAgentId` 是 send 文本中 fixture 关联标签的真实目标，仅用于将
  **该 child** 的 provider 请求（含 discover 与 final）分组，不是权限或生产身份推断。
  已显式关闭 reviewer 的新输入目标计数在拒绝前后必须都是 0；root 正常 completion 不计入。
  `observation.continuation` 仍只在实际 final 响应时记录。
- recovery 和 lifecycle 的关闭负例共用严格消费边界：已消费同一直接父子、冻结 route 的真实
  Closed/preserve close 收据，且真实 get_delegation_model 仍确认原账号/型号 available，排除
  本场景意外修改账号/凭据/启用状态后造成的准入前置失败；send 的精确 callId/name 与原
  target/message 参数一致；输出不是
  typed Sent 或其他 JSON 成功/ACK，并且**恰好**匹配上述已核实的外层错误。前后都真实
  list_agents，目标仍 Closed、同 parent/route、无 pending inputs/tasks、latest completed Turn
  等于原最终 Turn。Open/cold list 的 lastTurn 都可为 null，不能伪造或要求该摘要加载历史；
  最新终态另经真实 read_agent_session（descending/full，每页50、最多4页）核对，前后各自
  从新水位读取、仅在同目标历史中找到最新正常 completed Turn 才通过，不解析 opaque item ID。
  recovery 的冷目录核对同样用该只读历史证据补足缺失的 Turn，而不激活 child。
  该目标新输入 provider 请求（含 discover）计数在实际派发前冻结基线，
  拒绝后不增加（recovery 的前后基线均为 0；lifecycle 不增加 first 的已有返修请求）。
  `closedSend.before/after` 保存 target/parentAgentId/model/turnId/lifecycle/pendingInputs/
  runningTasks；原 send 派发 observation 也保存同 callId 的 before/计数，不能在结果回放时
  重新取得较大基线掩盖一个误执行请求。
  只缺任一证据都失败，不接受其他含 closed 的文本、未知错误、错误 target、缺账号或未授权
  前置失败。授权/直接父子检查发生在 activation 前；已持久显式关闭的恢复检查发生在
  凭据/模型绑定前。外层仍不暴露完整 source，故这里只证明受控已关闭目标拒执行及无新工作，
  不把这一文本当作任意环境故障的类型化根因证明。
- harness 在 first 真实退出后保存阶段观察，校验 first 完成且 reopen 未提前执行；reopen 后
  必须读到同 root/同 executor、一个新的 reviewer、executor revision 2 / reviewers 各 revision 1，
  并确认关闭目标没有新增请求。原 lifecycle/window 的第二阶段 child 请求总数不增规则仍保留，
  不套用于本场景的合法恢复调用。
- outer fixture 同时要求两个主完成 checkpoint、真实关闭拒绝 checkpoint 和上述四个实际 final，
  拒绝请求、缺阶段、空旅程、只启动就 done、Driver 非零、shutdown/进程退出失败全部向外非零。
  observation/receipt 不能替代真实 GUI shutdown、同 home 重开、截图与产品 canonical 证据。
- 精确锁内 send/close/restore 交错仍是 unproved；不加生产 testhook、不以 sleep 竞赛作证明，
  不改私有库或构造 CallContext。迁移/保存故障由生产 owner 的允许专项验证承担。

## Driver 对接（唯一 key 源与只读观察）

宿主脚本读取 `code/anywork/lib/src/shared/studio_driver_key_values.dart`，不要自行拼接
账号/模型 key 或添加业务 Driver command。使用 `FlutterDriverSession.rawTap`，不使用
屏幕坐标；菜单是否已打开先观察，不重放有副作用的提交。

- `sessionSettings` → `draftDelegationMode` / `draftDelegationPreference` → 对应
  `delegationModeOption('draft', null|mode)` / `delegationPreferenceOption(...)`。
  null 为分别跟随默认，固定模式不可操作偏好但保留草稿值。
- 全局 `defaultDelegationMode` / `defaultDelegationPreference` 与 `'default'` options；
  工作区使用菜单中的 `sessionWorkspaceMode`，不新增 composer Profile 选择器。
- `modelEnabled(accountId, modelId)` / `modelDetails(accountId, modelId)` 的身份由
  KeyValues 内的 `jsonEncode([accountId,modelId])` 唯一构造。详情只显式打开/关闭/
  reload，不让快照为了采样自动查全目录。
- `accountBillingKind` / `billingKindOption(null|unknown|metered|subscription)` 区分清除
  override 与显式 unknown；不能拿关闭价格统计当 subscription。
- 现有 `agentSwitcher` / `agentRow` 与 `agentModel(threadId)` 查看真实冻结路由。

`snapshot.delegation` 只读域：defaults、settingsRevision/catalogRevision、
accountModels（canonical enabled 与 pendingEnabled/error 分离）、drafts（两个 override
与 effective 值）、threads（创建时冻结 mode/preference）、agents（冻结模型）、仅已打开
的 modelDetails/evaluations。不要把点击成功或本地 pending 值当 canonical 成功。

正常操作通过 Client 产生独立业务 operationId。若确需额外真实 typed HTTP/Runtime
CAS 核验，`SetAccountModelEnabledRequest`、`SetAccountBillingKindRequest`、
`RemoveAccountModelRequest` 的必填 `operationId` 必须独立生成；同意图在明确 CAS
拒绝后的重试保留 ID，回执必须原样匹配，不能伪关联固定描述 ID。此 fixture 不绕过
Client 提供上述写命令。

## 证据、失败归因与明确缺口

每阶段 `provider-observations.json` / 总 `provider-observations.json` 保存严格 completion
请求证据：`ordinal`、`endpointAlias`、实际 `model`、`marker`、`note`、`accepted`、实际
`tools`、当前 `preferenceTemplates`、选中 `expectedAccountId`、实际 `actualEffort` 与关键真实收据。不会记录
Authorization、完整系统提示词或操作者正文。最终 fixture 原请求在环境中仅属合成样例；
分享只用脱敏 evidence。`requests.json` 保留 strict 诊断，fixture.log 保留原始拒绝原因。

`delegation-result.json` 分别写 journey 与 fixture 停止状态，默认人类 verdict pending。
场景要求的主流程未执行会让 fixture CLI 非零，包括“只启动、只看 UI、直接 done”。
`capture-stage.txt=shutdown_completed`、GUI 真 exit、fixture stop/report、外层 exec 终态
都要核对；失败也要查看所属 PID 树，不能拿 kill 信号已发送冒充回收完成。

**不声称已确定证明**：锁内 evaluate/send/close/cold-activate 精确线性化、spawn prepare
与 archive、新 root 与 archive、取消评价 waiter 后事务提交、cleanup/commit 受控故障。
这些尚无已核实的公共可控 gate，不能并发点击+sleep 假装确定；不加生产 testhook，不复制
私有算法。若需新增公共边界或受控 FS/存储故障，先由主代理决定范围与契约。

实现复用与官方契约：Axum 0.8.9 `Router::route/with_state` 和现有
`axum::serve(...).with_graceful_shutdown`；Tokio-util 0.7.20 `CancellationToken::cancelled`
是 cancel-safe，取消前/后订阅都能观察 gate 状态；Serde typed/adjacently-tagged enum
解析真实 TurnState，不以 marker 当终态。参考：

- <https://docs.rs/axum/0.8.9/axum/struct.Router.html>
- <https://docs.rs/tokio-util/0.7.20/tokio_util/sync/struct.CancellationToken.html>
- <https://serde.rs/enum-representations.html>

本模块不引入新依赖、router 框架、评价 store、model 目录或过滤器。
