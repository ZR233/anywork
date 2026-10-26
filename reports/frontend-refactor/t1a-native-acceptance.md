# T1.A / A2 定向原生验收：Timeline 真实 raw FRB（本轮）

## 0. 摘要与结论口径

本报告是**候选**交付：raw query/ACK/close 的**可观测链**在本轮真实 native 运行中取得候选通过证据，
**等待 fresh 复审与 root 最终验收**。本报告**不**宣称整个 Timeline 阶段已被接受，**不**宣称 a1 的
连接失败已被修复或已被定位，也**不**把任何 retryable Busy 当作"成功的 page 结果"。

本轮在**本轮自建的隔离环境**里，用官方 `cargo xtask manual-gui` 建立真实 20k 历史来源，再用官方
`pl-provider-fixture` 与一次性的 native Driver target 完成 **prime / probe-run 两阶段真实 FRB 探针**：

- `probe-prime`：用官方 `startNewThread` 在一个全新真实 Thread 上提交固定小 prompt，等到该 input
  的**真实 source Turn Completed**，并经中央退出完成应用关闭。该阶段本轮**通过**。
- `probe-run`（标签 `t1a-native-run4`）：在同一 Thread 上**只提交一次**既有 20k 固定 prompt，
  消费真实 `BridgeTimeline` 的 baseline/patch，覆盖"source Turn Completed 后仍最多 2 个已发送未 ACK
  数据帧、ACK 协议与幂等、只 ACK 前缀 1 才释放 seq3、满窗独立 query、并发/重复 close 与
  `Cancelled` 优先、dispose 一次、中央退出与进程回收"。**探针自身判据全过**（`pass: true`，
  host exit 0），但按 §8 的口径，`page` 的"完成"是在观察到应用级持久化队列 Ready 后重读得到的，
  因此这一项按可观测边界记录、留待 root 判定，不计为"合同已验收"。

本轮同时给出两个事实（详细边界见 §7、§8）：

1. **HTTP 413 的机制被本轮独立复现并定位到代码路径**：同一 Thread 若已含 20k 历史，再次提交会把
   整段历史放进请求体，超过本地 fixture 的 1 MiB 请求体上限，fixture 在剧本匹配前返回
   `413 PAYLOAD_TOO_LARGE`，`requests.json` 为空、`accepted=0`、`rejected=0`，Turn 变 Failed。
2. **source Turn Completed 之后立即读取 `page(limit:32)` 得到 typed `busy`(retryable)**，而同一时刻
   `readDetail(maxBytes:4)` 完成；在观察到**应用级**持久化队列 `Ready + pendingCommits==0`、且仍有
   2 个未 ACK 数据帧时重读同一 `page(32)`，得到 32 条真实进展。哪一步能支撑"独立查询边界"、
   哪一步不能支撑"本 Turn 已 durable"，见 §8。

## 1. 范围与责任划分

| 范围 | 归属 | 本轮结论 |
| --- | --- | --- |
| 完整 GUI displacement 矩阵（6×96 / 3×600 / burst 40 / overlap 8）、三阶段 native exit、40 页、Busy 重试、History 冻结/回 Live、人眼看图 | root（已接受，原件在其 artifacts `t1a-history-r3-heartbeat`） | 只读复用其结论，本轮不重跑、不改写、不外推为自己的证据 |
| 本轮定向 raw FRB 探针（prime + run）、来源环境建立、typed 错误/ACK/query/close/退出/回收 | 本轮（本执行者） | 见 §3–§8；**候选**，等 fresh 复审与 root 验收 |
| a1 阶段的 `connection:"failed"`（未定位原因） | root（本轮只提供证据位置，不归因、不修复） | 见 §3.3；阶段整体仍由 root 处理 |
| 全仓门禁（fmt/clippy/test/verify-client/verify-gui）、生成、Git 提交/推送/PR、最终整体验收 | root | 本轮**未执行**，也不声称 |

本轮未修改任何生产源码、生成物、合同、`design/`、`AGENTS.md`、CI、manifest/lockfile；
未 `stage`/`commit`/`push`/`reset`；未改动 root 证据原件；未改本轮四份一次性脚本与任何 artifact
（包括保留原始键名 `pageBusyBeforeDurable` / `page-at-durable`，见 §8.3）。

## 2. 现场基线、平台与入口

- 仓库 HEAD `b98432fa809446d57be87a8b96379455ec8a4828`，分支 `pure-session-thread-65e3ee582f0d4-82`；
  贡献基线 `f6cb327ceb3416dca181790575711588571d3ec7`。
- 合同：`t1a-timeline-contract.md` v2（sha256 `bfdf7f6c…b012c8`）、
  `t1a2-dart-timeline-contract.md` v4（sha256 `e9cb3e4d…d8b2f8`）；协议依据 design/26、25、24。
- 平台：Linux x86_64（SSH remote helper 目标机），无桌面会话 → 隔离 Xvfb
  `-screen 0 2560x1600x24`，`GDK_BACKEND=x11`，`script -q -e`（伪终端），
  `XAUTHORITY` 使用本会话 scratch 路径 `Path.resolve()` 得到的**绝对**路径；未使用 `xhost +`，
  未占用保留端口 `1420`。
- 官方入口（未直接调用 `flutter build/run`）：
  - `cargo xtask manual-gui --scenario timeline-history --retain-environment --output <新目录>`
  - `cargo xtask run-gui --driver --profile --native-launch --native-launch-driver-target <本会话 scratch 内一次性入口> --native-exit-report <本次目录>`
  - `target/debug/pl-provider-fixture --scenario {gui|timeline-history} --bind-port <实测端口> --ready-file/--requests-file/--report-file/--status-file …`
  - `cargo dart --packages=.dart_tool/package_config.json <一次性 Driver 客户端>`
- 构建形态：profile/AOT（与官方长历史旅程一致），**不是** release 性能证据。

## 3. 阶段 A：本轮自建隔离环境（官方 `timeline-history`，**不带** displacement）

命令（省略本会话绝对路径）：

```
GDK_BACKEND=x11 xvfb-run -a -f <scratch>/<label>.xauth -e <artifacts>/<label>-xvfb.log \
  -s '-screen 0 2560x1600x24' \
  script -q -e -c 'cargo xtask manual-gui --scenario timeline-history --retain-environment --output <artifacts>/<label>' /dev/null
```

### 3.1 采用标签 `t1a-native-history-a2` 的独立通过证据（本会话 artifacts，原件不入库）

| 事实 | 实测值 |
| --- | --- |
| live 旅程 | `pass: true`，`turnCompleted: true`，`shutdown: completed` |
| live 持久化身份 | project `project-65e554b114dc7-2` / thread `thread-65e554b288afd-3`，`evidenceConsistent: true` |
| 真实来源规模 | `outputTokens: 20005`；settled 快照里 `persistenceKind: ready`、`pendingCommits: 0`（该字段是旅程自己读的展示投影，语义见 §8.2） |
| live 深页 | `pageCount: 40`，`delivered` 合计 1280（40×32），`duplicateIdentity:false`、`orderViolation:false`、`cursorStalled:false`、`growthViolations:[]`、`loadedItems:1312` |
| live 真实 Busy 与冻结 | `busyDuringFailure:true`、`failureCode:"busy"`、`bodyUnchanged:true`；冻结页 394 条 → 恢复页 426 条、`olderError:null` |
| restart 旅程 | `pass:true`、`shutdown:completed`；`restore.threadIdMatches/projectIdMatches/evidenceConsistent` 均 true；`pageCount:40`、`delivered:1280`、`identityMatches:true` |
| native exit（live / restart） | 各自 `exitCode:0`、`signal:null`、`cancelled:false`、`descendantsAtRootExit:[]`、`reclaimedDescendants:[]` |
| fixture | `completed:true`、`acceptedRequests:2`、`rejectedRequests:0`、`requiredStepsConsumed:true`；关机摘要 `consumed_steps=3/3`、`remaining_optional=true` |
| 保留环境 | `retained-environment.json` 给出 root/home/project；fixture `base_url` 为 loopback 且端口非 1420 |

### 3.2 该通过只覆盖"我的来源环境可用"

它证明本轮有一个真实 20k 历史环境可供 prime/run 使用；**不**替代 root 的位移矩阵与截图人眼判定
（`verdict.json` / `human_verdict` 仍是 `pending`），也不代表 a1 的问题被解释。

### 3.3 首轮尝试 `t1a-native-history-a1`：未定位原因的 connection failure

同一命令在 `prompt_submitted` 之后失败：

- Driver 报 `Streaming history did not settle: live content`；
- 保留的诊断快照（`timeline-history-live-driver.log` 第 6–38 行）为
  `threadId:"thread-65e553dbd22cc-3"`、`generation:0`、`ready:false`、`connection:"failed"`、
  `mode:"live"`、`itemCount:0`、`scroll:null`；
- 同一轮 fixture 侧正常：2 个请求全部 `accepted`、`consumed_steps=3/3`、`rejectedRequests:0`、
  自身正常退出；app 侧 native exit 为 `exitCode:0`、`signal:null`、`cancelled:false`、无后代，
  `elapsedMillis 97642`；
- `timeline-history-live.json` 只有 `phase/verdict/pid/shutdown`，说明旅程在 identity/paging 阶段
  之前就已抛出。

**这是"未定位原因的 connection failure"：本轮不作任何原因归因。** 具体地：

- 该 `connection:"failed"` 的**原因载荷没有被保留**：Driver 快照投影
  （`code/anywork/lib/src/shared/studio_driver_projection.dart` 的 `_timelineFacts`）只投影
  `connection`，不投影 `connectionError`；app 默认日志级别也没有输出该 reason；
  harness 的未脱敏运行目录是 `manual_gui.rs` 内的 `tempdir_in(&output)`，drop 即删除，
  output 里只有路径脱敏的同内容副本。因此**没有任何已保留材料可以反推原因**；
- fixture 侧正常**不能**推出连接失败的原因；a2 在**新目录/新 xauth** 下独立通过，只是另一份
  相互独立的观察，同样**不能**用于对 a1 作原因归因；
- 因此 a1 记作"未定位（unlocated）"，原因待 root 独立核证与后续诊断；阶段整体由 root 处理。
  与 root 记录的前几次尝试**在断言位置上相同**（同一条 `timeline_streaming_journey` 的
  `until('live content')`），这只是位置相同的观察，不构成原因判断。

## 4. 阶段 B：从 retained 环境读取事实（不猜）

只读 `retained-environment.json` 得到 root/home/project，只读该环境内 fixture `ready` 文件得到
实际 loopback `base_url`（含端口），据此在同端口串行重开 fixture。Thread ID 不猜：
prime 用 live 报告中的身份 `thread-65e554b288afd-3` 作为**来源 Thread**（只做一次 typed
`readThread` 冻结 projectId/mode/workspaceMode/accountId/modelId/effort）；run 使用 prime 报告
写出的新 Thread ID。未复制、未修改任何他人数据根与凭据。

## 5. 阶段 C：prime —— 在隔离环境内新建真实 Thread

接口使用（全部为既有生成接口，未手改生成物）：

- `history.readThread(threadId)`：一次 typed query，不解阅任何订阅水位，用于冻结 route/模式。
- `threads.startNewThread(request)`：`BridgeNewThreadStartEvent` 的 Progress/Succeeded/Failed；
  Succeeded 的 `receipt.inputId/threadId` 与 `thread.id` 交叉校验；流在终态前 EOF 视为
  UnknownOutcome（未重发创建）。
- 源 Turn 进度由既有 `session.source.watchLatest` 的**同步登记 + 当前值**观察驱动，不用 sleep、
  不轮询 query 证明进度；终态必须是对应 inputId 的真实 `Completed`（**source Turn 的业务终态**，
  它不证明逐 Turn 的 durable checkpoint，见 §8.2）。
- 关闭走中央 `StudioExitCoordinator.cleanupActive()`，再由 Driver 请求 `request-app-exit`
  走唯一退出通道。

结果（`t1a-native-prime3`，本会话 artifacts）：

| 事实 | 实测值 |
| --- | --- |
| 新建 Thread | `thread-65e556a3c7524-1`（真实持久化，非注入） |
| input | `native-feed-…`（本轮唯一），源 Turn `input:…:3`，source Turn Completed |
| 应用关闭 | `shutdown:"completed"`、`outcome:"clean"`、`issues:[]`、`exitRequested:true` |
| native exit | `pid` 与 GUI 一致、`exitCode:0`、`signal:null`、`cancelled:false`、后代与回收均为 `[]` |
| fixture | accepted 1、rejected 0、`remaining_optional=true`、自身 exit 0 |

另两次 prime（`t1a-native-prime`、`t1a-native-prime2`）同样 prime 成功；第一次的宿主脚本
在优雅停机竞态下读到过期的 `--status-file`（见 §9），已在宿主侧改用 fixture 自身关机摘要与
`requests.json` 作为该相位判据，探针成功标准未变。

## 6. 阶段 D：raw `probe-run`（标签 `t1a-native-run4`）

命令与 prime 相同，仅把 fixture 场景切到 `timeline-history`、并用 prime 产出的 Thread ID：
`<host> <retained-output> t1a-native-run4 probe-run thread-65e556a3c7524-1`。

### 6.1 断言 → 证据（严格区分四类事实）

本文四类事实分别写作：**(a) source Turn Completed**（业务终态）、**(b) query 的 busy/completed**
（单次读取的返回）、**(c) 应用级持久化队列 `Ready + pendingCommits==0`**（`graph.client.persistence`
这个应用级 store 的状态）、**(d) 逐 Thread/Turn 的 durable checkpoint**（本报告**没有任何证据**能
单独证明它，见 §8.2）。

| 合同要求 | 证据（`t1a-native-run4` 的 driver/host 报告） |
| --- | --- |
| 真实 `BridgeTimeline`（非 fake/demo/合成 D1），原 feed 强 owner，一次 stream | 真实 RustLib 生成句柄 `openTimeline` + 单次 `stream()`；`feedId: "timeline-tail-…-2"` 全程唯一 |
| data 连续且从 1 开始，baseline 占额度 | `frames`：seq1 `baseline`、seq2 `patch`、seq3 `patch`；探针在 `_frame` 内对任何非连续序号、第二个 baseline、feedId 变更、未取消先 Failure/Closed 直接抛错 |
| baseline 1 不 ACK；源进展来自现有 Session 观察 | baseline 从未作为 ACK 前缀（直到窗口满后才 ACK 前缀 1）；`ackThrough(3)`/`ackThrough(0)` 之后都有"发送数仍为 2"的显式断言；源 Turn 进度只经 `watchLatest` 观察 |
| 真实 20k input 对应 **(a) source Turn Completed** 时仍最多 2 个已发送未 ACK 数据帧 | `noAckDataFramesAtSourceCompletion: 2`；这是**断言点上的计数**——若产品在 ACK 之前提前发送第 3 帧，紧随其后的 `_sequence != 2` 断言会失败 |
| 业务终态不得冒充 durable（口径隔离） | 探针里的 `businessTerminalIsNotDurableClaim: true` 是**写入报告的常量规则标记**（表达"业务终态不得冒充 durable"这条约定），**不是独立测量**；本轮没有测量 (d) |
| 满窗 `page(limit:32)` 的独立查询边界 | 两段证据：① (b) `source Completed` 后**首次**读取 → 原始键 `page-busy-before-durable` = typed `busy`(retryable)；② 观察到 (c) 之后、仍 2 未 ACK 时**重读** → 原始键 `page-at-durable` = `completed`，`pageItemsWhileFull: 32`、`latestQueryDiffersFromInitialBaseline:true`。键名是原始标签，实际语义见 §8.3 |
| 稳定小基线 saved terminal item 的 `detail(maxBytes:4)` 完成、UTF-8 ≤ 4 | `detail-while-full: completed`、`detailBytesWhileFull: 4`，且 `chunk.itemId` 与基线 detail 目标一致；该读取与 page 首次读取同批（`Future.wait`）完成 |
| 两个 query 错误在 await 前一起登记；query 不改 feed 水位 | 两个 query 在同一 `Future.wait` 中先各自登记（`_capture`）再等待；query 前后发送数与 feed 身份未变 |
| ACK 3（尚只 sent 2）必须 typed `protocol` 且不释放额度 | `ackThrough(3)` 只接受 `BridgeErrorCode.protocol`；随后 `ackThrough(0)` 与"发送数仍为 2"断言通过 |
| ACK 0 幂等；旧 ACK 1 幂等 | `ackThrough(0)` 无错误且不释放；前缀 ACK 1 之后重复 ACK 1 无错误、未额外释放 |
| 只 ACK 前缀 1 使被挡住的第 3 帧送达，仍保留 2 未 ACK（2/3） | ACK 1 后 `_until(sequence == 3)` 成功（说明 seq3 在此之前未被发送）；`ackedPrefixAtClose:1`、`sentAtClose:3`、`unacknowledgedAtClose:2` |
| 满窗 `requestClose` 立即封准入；并发两次 close、stream cancel、再重复 close 都真 join/Clean/同 feedId；之后才 dispose 一次 | `concurrentAndRepeatedNativeCloseClean: true`（两份并发 close + stream.cancel + 第三次重复 close，全部同一 `feedId` 且 `Clean`）；`disposed: true`（仅一次） |
| 关闭后非法 ACK/page 仍 `Cancelled` 优先 | `cancelledWinsAfterClose: true`：`ackThrough(4)` 与 `page(limit:0)` 均得到 typed `cancelled`，未被 invalid_argument/protocol 抢先 |
| App exit 经 `StudioExitCoordinator`；PID 匹配、exit0、signal null、cancelled false、无后代 | driver `shutdown:"completed"`/`clean`/`issues:[]`、`exitRequested:true`；`native-exit`：`pid` 与 GUI 一致、`exitCode:0`、`signal:null`、`cancelled:false`、`descendantsAtRootExit:[]`、`reclaimedDescendants:[]`（真实耗时 28.9 s） |
| 20k 固定 prompt 只提交一次 | fixture `acceptedRequests:1`、`rejected:0`、`consumed_steps 2/3`、`remaining_optional:true`、自身 exit 0；prime 与 run 是两条独立命令、不同 inputId、不同输出目录 |
| 只记录小身份/序号/种类/错误/计量 | 报告只含 Thread ID、inputId、feedId、序号/种类、typed 错误码与字节数；不含正文、历史或 wire 载荷 |

### 6.2 失败即报错的证据（不是放宽）

- `_until` 的所有等待都有 90 s 上限，超时抛 `TimeoutException`；观察失败原样上抛。
- `_frame` 对 Failure 帧直接抛出 typed 错误；`Closed` 在未 `requestClose` 前出现视为错误。
- 本轮确实按此机制失败过两次（§9），报告保留原始 typed 错误，没有改成成功。

## 7. find #1：413 的真实机制（本轮独立复现）

- 现象：`t1a-native-run2` 在同一 Thread（前一轮已生成 20k 内容）上再次提交固定 prompt 时，
  Turn 变为 `FailedStudioTurnState: HTTP 413 … provider returned an unstructured error response`。
- fixture 侧：`fixture_status=failed`、`accepted=0`、`rejected=0`、`consumed_steps=0/3`，
  `requests.json` 为空，stdout 报 `fixture stress stream incomplete: emitted 0/20000 data events`。
- 代码定位（只读）：`code/pl-provider-fixture/src/lib.rs` 的 HTTP handler 先用
  `axum::body::to_bytes(request.into_body(), 1024 * 1024)` 读体，超限直接返回
  `StatusCode::PAYLOAD_TOO_LARGE`，**在 `match_step` 之前**；因此请求既不计入 accepted 也不计入
  rejected，剧本一步都没消费。
- 结论：413 不是 ACK/query 通过，也不是 fixture 剧本或成功标准过多；它是"把整段 20k 旧历史装进
  请求体"触发的 body 上限。因此每轮真实 20k 提交都必须落在**只含小段真实内容的全新 Thread** 上
  ——本轮 prime→run 的设计正是如此，且 root 已确定的修正方向被真实运行证实。
- 该复现本身是 fixture 请求体上限导致的真实失败；它**不**说明 Timeline 侧已通过，也不构成
  a1 connection failure 的解释。

## 8. find #2：满窗 query 的独立边界与"durable"口径

### 8.1 已确认的合同语义（root 确认，本轮只记录，不修改）

- 满窗时 query **不应等待事件接收锁**；native-v2 明确**不修改 reader 公共语义**；
- design/26 允许在读取连续性／checkpoint 栅栏不足时返回 **retryable Busy**；
- 因此不需要强制制造 Busy，也不得把 Busy 当作"成功的页"。

### 8.2 四类事实的口径（本报告不越界）

| 说法 | 本轮能支持 | 本轮不能支持 |
| --- | --- | --- |
| (a) source Turn Completed | 探针观察到的对应 inputId 终态为 `CompletedStudioTurnState`（§5、§6） | 不能推出 (d) |
| (b) query busy/completed | 每次读取的 typed 返回：首次 `busy`(retryable)、重读 `completed` 且 32 条（§6.1） | 不能据此判断该 Turn 的持久化水位 |
| (c) 应用级持久化队列 `Ready + pendingCommits==0` | 探针脚本的 `durable` 判定读的是 `graph.client.persistence`（应用级 persistence store）的 `stateLoaded && ReadyPersistenceState.pendingCommits == 0` | **这是应用级队列事实，不是逐 Thread/Turn 的 durable checkpoint**，因此不能声称"该 Turn 已全部 durable" |
| (d) 逐 Thread/Turn durable checkpoint | 无 | 本轮**没有**任何独立证据；不得由 (a)(b)(c) 组合推出 |

补充两条必要的谨慎：

1. run3 的即时 `busy` **也可能只是读取连续性/栅栏不足**（design/26 允许），因此**不能单独推断**
   "该 Turn 未 durable"；本轮只把它记为"source Completed 后首次读取返回 typed retryable Busy"。
2. 命中 (c) 只是"应用级队列已 Ready 且无待提交"，与 (d) 仍不是同一命题。

### 8.3 原始 artifact 键名与实际语义（不改名，避免身份漂移）

| 原始键（run4 报告，未改名） | 实际语义 | 不能支持的语义 |
| --- | --- | --- |
| `pageBusyBeforeDurable` | source Turn Completed 后**首次**读取 `page(32)` 得到 typed `busy`(retryable) | 不是"证明此前未 durable" |
| `page-at-durable`（`_queries` 内键） | 观察到 (c) 之后、仍 2 未 ACK 时的**重读**，结果为 `completed` | 不是"逐 Turn durable 水位" |
| `pageCompletedWhileWindowFull` | 重读在"未 ACK 发送数仍为 2"的断言点完成 | 不是 Rust 内部队列/预算结论（见 §10） |
| `businessTerminalIsNotDurableClaim: true` | 探针写入的常量规则标记（表达约定） | 不是测量事实 |

### 8.4 本轮据此得到的边界结论

- `run3`：source Completed 后**首次** page 读取 = typed retryable `busy`，同批 `readDetail(4B)` 已完成；
- `run4`：在同一 feed、仍 2 未 ACK、**未发送任何 ACK 释放**的前提下，观察到 (c) 后重读同一
  `page(32)` 得到 32 条真实进展（最新项与初始 baseline 不同）；
- 这两份证据合起来可以支撑"**满窗 query 与事件投送窗口相互独立、ACK 不是读取前提**"的可观测边界，
  但它们**不**把 `busy` 变成成功页，也**不**证明 (d)；
- 该边界是否足以满足冻结判据的措辞，仍由 root 亲读 page/durable 合同后判定；本轮不声称该项已完成
  合同验收，也不修改生产/预算/公共 API/Plan。

## 9. 失败、偏差与工具侧发现（全部保留原件）

| 轮次 | 命令 | 结果 | 说明 |
| --- | --- | --- | --- |
| `t1a-native-history-a1` | 官方 `timeline-history`（retain） | 失败（原因未定位） | Driver `live content` 未 settle，timeline `connection:"failed"`、`generation:0`、`itemCount:0`；fixture 正常（2 accepted、3/3、rejected 0）；无 `connectionError`/reason 载荷保留，见 §3.3 |
| `t1a-native-history-a2` | 同上（新目录/新 xauth） | **通过（独立观察）** | 本轮来源环境（§3.1）；不能反推 a1 原因 |
| `t1a-native-prime` | probe-prime | 探针通过、**宿主判据失败** | 优雅停机时 fixture `--status-file` 仍是启动快照（watcher 200 ms 轮询在 stop 时被取消）：判据改为 fixture 自身关机摘要 + `requests.json` |
| `t1a-native-run` | probe-run（旧探针构建） | 失败 | source Turn Completed、2 帧后 `page`/`detail` 之一抛 `BridgeError`，旧构建未记录 code |
| `t1a-native-run2` | probe-run（同一 Thread 重跑） | 失败 | **413**，即 §7 的真实复现 |
| `t1a-native-prime2` | probe-prime | **通过** | 新 Thread `thread-65e5560a9efcc-1` |
| `t1a-native-run3` | probe-run（补 typed 证据后） | 失败 | 首次 `page` → typed `busy`；同批 `detail` 完成（§8.4 前半） |
| `t1a-native-prime3` | probe-prime | **通过** | 新 Thread `thread-65e556a3c7524-1` |
| `t1a-native-run4` | probe-run | 探针判据全过（**候选**） | 全断言链（§6），page 口径见 §8 |

工具侧（非产品）发现：fixture 的 `--status-file` watcher 每 200 ms 轮询、优雅停机会取消它，
因此该文件在停机瞬间可能仍保留上一次轮询的快照（本轮 prime 首次就遇到 `total:0` 而实际 accepted 1）。
正式 harness 在 timeline-history 场景下实测能读到最终计数（本轮 A 阶段亦然），故该竞态未影响正式判定；
但宿主编排更稳妥的做法是使用 fixture 退出时打印的关机摘要或 `--requests-file` 作为最终计数，
本轮宿主脚本已改为如此（并在 status 文件有数据时继续强制 `rejected==0`、`remaining_optional==true`）。

本轮探针脚本的两次有据修改（均不改变输入、预算与成功判据，只是错误收束/证据增强）：
①补 typed 错误码并分别登记两个 query；②把 `page` 的完成观测点从"source Completed 后立即读取"改为
"观察到应用级持久化队列 Ready 后重读"（脚本内部键名沿用旧原始标签，未为改名制造身份漂移）。
脚本在每次成功运行前后保持 format 0 diff、`dart analyze` 0 issue、Python AST 通过。

## 10. 未覆盖与不外推

- 不覆盖位移矩阵、GUI 视觉/截图人眼判定、窄窗口与 1920×1200 正常窗口的观感结论：这些是 root
  已接受的原件；本轮 `verdict.json`/`human_verdict` 仍为 `pending`，本轮不给出人眼判定。
- 不覆盖 `Close` 的非 Clean（`Unresolved`）分支：本轮真实 close 全部 `Clean`，未用替身制造异常，
  也未把 Unresolved 分支说成已验证。
- 不覆盖 Windows、真实供应商、发布/release 形态、跨机器；只证明本机 Linux + 本地模拟供应商 +
  profile/AOT build 的行为。
- **本轮 raw FFI 探针只证明可观测事实**：在断言点上"已发送且未 ACK 的数据帧为 2"、越界 ACK 被
  typed 拒绝、只 ACK 前缀 1 后被挡住的 seq3 才送达。它**不能**证明 Rust 侧 `latest` 待发槽
  "最多 1 份"、也**不能**证明内部 8 MiB 载荷预算、FRB wire bytes 或进程 RSS。
- 若本报告之外引用"`latest` pending 槽 1 份""源标准 JSON 8 MiB 预算"等预算结论，其证据是
  **已批准的 native 源码与 16 项契约测试**（root 既有证据），**不是**本轮 FFI 探针；本轮不新增
  任何未核的原始测量数据。
- 不给出任何性能百分比：本轮没有与同条件基线做可比的端到端测量；28.9 s 只是单次真实 native
  运行耗时，不是性能结论。
- 未执行全仓门禁（fmt/clippy/test/verify-client/verify-gui）、未生成、未提交：按派发范围留给 root。

## 11. 复算入口（不含本机绝对路径）

```bash
# A. 本轮隔离环境（无 displacement；Linux SSH 无桌面）
GDK_BACKEND=x11 xvfb-run -a -f <scratch>/<label>.xauth -e <artifacts>/<label>-xvfb.log \
  -s '-screen 0 2560x1600x24' \
  script -q -e -c 'cargo xtask manual-gui --scenario timeline-history --retain-environment --output <artifacts>/<label>' /dev/null

# C. prime（同端口重开 gui fixture 由宿主脚本完成）
xvfb-run -a -f <scratch>/prime.xauth -s '-screen 0 2560x1600x24' \
  python3 <scratch>/run_timeline_raw_probe.py <artifacts>/<A 标签> <prime 输出> probe-prime

# D. run（使用 prime 报告写出的新 Thread ID；20k prompt 只提交一次）
xvfb-run -a -f <scratch>/run.xauth -s '-screen 0 2560x1600x24' \
  python3 <scratch>/run_timeline_raw_probe.py <artifacts>/<A 标签> <run 输出> probe-run <新 Thread ID>
#    注：D 的 page 完成观测点在"应用级 persistence store Ready + pendingCommits==0"之后重读，
#    窗口仍为 2 未 ACK；该 store 不是逐 Turn durable checkpoint（§8.2）。

# 定向静态检查（一次性入口在本会话 scratch）
cargo dart format --output=none --set-exit-if-changed <scratch>/timeline_raw_feed_probe_main.dart \
  <scratch>/timeline_raw_feed_probe_client.dart
cargo dart analyze <scratch>/timeline_raw_feed_probe_main.dart <scratch>/timeline_raw_feed_probe_client.dart
```

## 12. 证据清单与内容身份

原件只在本 Thread 的 `scratch`/`artifacts`（未入库；不含提交正文、截图、VM URL 或日志正文）。
scratch 一次性脚本（本轮最终版本，本轮返工**未改动**）：

| 文件 | sha256 |
| --- | --- |
| `run_timeline_acceptance.py` | `dd3f87be6d8b7ae4ed1266d4f6b851fa2fb942c26dcd591dc8a512789c23d514` |
| `run_timeline_raw_probe.py` | `31c70bf1b1bc59078ad1b04d9b2f4324b6dd20faa6bc48e9d73a7dc4fc65d2f7` |
| `timeline_raw_feed_probe_main.dart` | `6273395ebf951baeacf86488b3f38b47096e11dd4f618dc2b0209cc71449386d` |
| `timeline_raw_feed_probe_client.dart` | `3d76c2f5f576e6b6f791aeea799f2395d7785ad4b2c57739d5903a2df8ffe6f1` |

关键证据 JSON（本会话 artifacts，按标签相对引用）：

| 标签/文件 | sha256 |
| --- | --- |
| `t1a-native-history-a1/timeline-history-live-driver.log`（a1 诊断快照） | `aae3b1287d891bf0f5ea9afe9ba4994357e7f8ea66fa308c838bfe138f06f226` |
| `t1a-native-history-a1/timeline-history-live-exit.json` | `a9388226f540a03b1e863c08d014c23757c41113c6d8ce6131c55960b1bb4df5` |
| `t1a-native-history-a1/timeline-history-live-native-exit.json` | `9fcf41a8ea7f91384cec1f28e38163206a03d92002aeaa4bfd97c38966e1622b` |
| `t1a-native-history-a1/fixture-status.json` | `b1da5eb04acf30636e5eed7df30ba82450896229fd3b35888a453b3e441c7bad`（与 a2 同名文件同 sha：内容即归一化的 accepted 2 / rejected 0 / completed true / requiredStepsConsumed true） |
| `t1a-native-history-a2/timeline-history-live.json` | `17b220db0085ddc107ee6e37dd0334bebf033ece5b82b8741dd3f29125669e84` |
| `t1a-native-history-a2/timeline-history-restart.json` | `ac08eced48396a7915744e34d0be34be94b09d8935bfc6c832d2162ca937c1b4` |
| `t1a-native-history-a2/timeline-history-live-native-exit.json` | `007ecd5057e53f2915c7632b6fd4a9f3329a89cac01cfa0f045dc97f5e6e7249` |
| `t1a-native-history-a2/timeline-history-restart-native-exit.json` | `ff5cc8036a72c455d770fe00bdf6692b98e4c113ba2d6ba2871dd51b2f176ea4` |
| `t1a-native-history-a2/retained-environment.json` | `ed2587cf3bd807f65cd9f5b329abc9ba86a7c3cad89076b84d2775d9a3fb4f26` |
| `t1a-native-prime3/host-report.json` | `d56d9d0779110fb9763948e61555def7d127d06e00ffbd6228e2e2c30760b940` |
| `t1a-native-run3/driver/raw-feed-report.json`（首次读取 busy 证据） | `0f925e9d1b415d680a5f5fbcd5b1cc63035ce8a827387f3b7bd3bdbf4f142a83` |
| `t1a-native-run3/host-report.json` | `13472f6d4b181ef8ed91db25a1239d70f9b55a445f992b8260b956818332d1de` |
| `t1a-native-run2/host-report.json`（413 证据） | `bbd80f6ef8b5c98dc4350a125e28a994ea6e1a38eab566617b764c3bb76df695` |
| `t1a-native-run4/host-report.json`（本轮候选通过） | `44f5972a237ad2ab3b45bb6eb86706c2e58089d4767445f0406d9d71f3357b3e` |
| `t1a-native-run4/driver/raw-feed-report.json` | `8faa8c4bb556b8ae0b7f647d50ba969abd0aa0fbbec5359315311c52bc6f79ae` |
| `t1a-native-run4/native-exit.json` | `5e70c234fba880e3f40ab96f24c0fd17bbc693b5312060bf0d5718872ff11df5` |
