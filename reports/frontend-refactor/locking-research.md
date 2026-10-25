# 锁与等待关系研究：PR #120 架构约束

## 1. 范围、版本与证据级别

用户要求自由研究锁相关模式，在架构上避免大锁、死锁。本文是只读调查与候选比较，
不是新并发框架的实施批准，也不是全仓无死锁或性能通过证明。

- 调查日期：2026-10-24（执行侧 UTC）。HEAD 为
  `0226f8060a6af8a778ac8685633707b497c8c8a2`，MERGE_HEAD 为
  `07bd17550475364419c6307ac5f1dea4ddbadcd2`；实际对象是未提交合并中的当前源码。
- `rust-toolchain.toml:2` 指定 Rust 1.99.1；本次 Rust 标准库网页也标为 1.99.1。
  未执行工具链来核验实际安装版本。
- `Cargo.toml:31` 与 `Cargo.lock:4548–4551` 均为 Tokio 1.53.3。
  本次 docs.rs 的该版本 Mutex、watch Receiver 页面无法通过检索工具取得；
  `latest` API 页面显示 1.54.1。以下将其作为官方模式/API 调研，不伪称已核验锁定版
  的全部实现。实施时仍须对照锁定版源码与后续实际门禁。
- lockfile 中有 DashMap 5.5.3、parking_lot 0.12.5；本次 Cargo.toml 文本检索未找到
  直接声明，不能把传递依赖当作业务层已选择的公共并发抽象。未发现 arc-swap 锁定项。
- 保持批准计划的 static-only：没有 build/check/test/clippy/analyze/format、生成、
  LSP diagnostics、GUI 或性能压测。调查没有新增依赖；调查确认的 L1 已另按 §4.5
  完成两文件最窄修复并获独立静态批准，仍不将其当作运行验证通过。

证据分类：**源码事实**说明现在确实发生什么；**可构造风险**必须给出等待边与前提；
**性能疑点**需要以后测量；**候选设计**尚未实现。发现持锁通知不等于已证明现实死锁。

## 2. 核心结论

优先减少共享与嵌套等待，不以“锁更少”“全部异步锁”或“全部无锁”为目标。
建议路线是：**既有领域 owner 单 writer + 不可变读快照 + 短状态提交区 + 锁外通知和
等待**。慢工作是否可以并行，取决于原事务不变量，而不是换一个 Mutex 类型。

应区分三个成本：

1. **状态锁占用**：读状态、登记工作和发布提交能否快速完成。
2. **业务串行化**：同一文件/版本的写入必须有先后关系；改成 mailbox 并不会自动消除
   这项必要串行化，也可能引入队头阻塞。
3. **执行器阻塞**：同步磁盘 I/O 或长计算是否占用 Tokio worker；移到阻塞池只解决
   执行器占用，不解决数据竞争、写入线性化或关闭责任。

## 3. 模式比较与本项目取舍

| 模式 | 合适场景 | 限制与项目取舍 |
| --- | --- | --- |
| 短同步 Mutex | 小型状态、配额准入、句柄登记；没有 await 和慢工作 | Tokio 官方并不要求异步代码一律用异步锁。保留简单同步边界，避免持锁调用未知代码。[S1] |
| 异步 Mutex | 资源本身确需跨 await 排他使用 | 等锁时让出执行器不等于无死锁。需证明被等待者不再依赖本锁；公平队列也不消除队头阻塞。[S3] |
| RwLock | 多读少写且读临界区确实短 | std 的优先级依赖 OS；Tokio 为公平/偏写。不能持读锁等待写锁，再借第二读锁“递归读取”。[S4][S5] |
| 专属任务/单 writer | 有序命令、独占连接、需异步 I/O 的资源 | 优先复用 Thread 等现有 owner。消息队列有界，责任在入队前登记；不得建立第二事实源。长工作、控制消息和关闭也要避免相互等待。[S2] |
| 不可变快照 | 读者需在处理期间使用同一版数据 | 短锁取得 `Arc` 后在锁外处理，不能分别加载两个版本再宣称配对一致。旧快照仍受原 pin/配额/释放责任约束。现有 Mode snapshot 可直接复用。[S10] |
| 先准备、后校验提交 | 与共享状态无关的解析/校验/编码成本较大 | 锁外结果带原版本，提交前重核 revision、closing 与资源身份。CAS 只裁决内存并不保护已经发生的外部文件覆盖；回滚也必须有原写入所有权。 |
| 提交与通知分阶段 | 发布 watch、回调、cancel/wake 可能跨 owner | 先完整提交，再释放所有相关业务锁，最后通知。不是仅释放最内层锁。延迟通知不得回退保留水位；无 receiver 时仍保结果。[S6][S7][S11] |
| 固定锁序/领域分区 | 多对象事务，或已证实互不相关的资源 | 所有路径（含清理/析构）遵循同一偏序；分区键须覆盖真实共享文件。不能按 UI 产品页机械拆锁；跨域 reload 仍有配对提交语义。[S9][S11] |
| 分片并发容器 | 真正独立 key 的高竞争读写 | 先证明无跨 key 原子要求。DashMap guard 仍持锁，文档明确提示持引用调用若干方法会死锁；不能整表替换后便宣称安全。[S12] |
| ArcSwap/RCU 类读路径 | 测量确认快照读锁仍为热点 | ArcSwap 是候选而非当前选型。需另核版本、许可、平台与回收成本；当前标准库 `Arc` 快照尚未证明不足，不新增依赖。[S10] |
| seqlock/手写原子状态机 | 特殊小数据、可重试读取且有严格内存/调度证明 | 不用于当前含 Arc、容器、I/O 的业务聚合。内核 seqcount 有 writer 串行化、指针与抢占限制，不能直接搬进异步用户态。[S13] |
| try_lock/超时 | 显式忙碌反馈或限制等待时间 | 失败不能变成正常空数据；循环抢锁可能活锁/饥饿。超时不是取消或 join，不能拿它作为死锁修复或 Clean 依据。[S8] |

这是项目取舍，不是承诺每种模式都引入。Rust 所有权、标准库与已有 Tokio 原语优先；
只有已验证不足才继续第三方选型。没有理由创建通用锁管理器、通用 actor 总线或自研 RCU。

## 4. root 已亲核的 Config/Mode 事实

### 4.1 已有可复用的好边界

- `code/pl-studio-runtime/src/mode/manager.rs:270–279`：`replace_source` 在获取
  manager 写锁前调用 `prepare_batch`。该准备相对 manager 自身锁已在锁外，不能误报
  为全部编译都在 manager 写锁内；但调用者仍可能持有更外层锁。
- 同文件 `:257–264`：`observe_registry` 在同一读锁下取得 immutable snapshot 和
  watch 订阅，避免分开“先读后订阅”漏过变更。`:335–341` 的 `snapshot` 仅取 Arc。
- `config/runtime/mod.rs:298–305`：Configuration 已有同锁快照/水位/订阅。
  `:317–337` 的 `notify_projection` 明确要求 state 与 command guards 均释放后调用，
  并拒绝迟到回退的 settings/catalog/closing 水位。这是可复用的领域边界，不需新总线。
- 同文件 `:342–356` 的 `if_usage_query_current` 是显式受限的私有同步提交回调，
  用于校验与采用的同一边界，禁止 await/I/O/重入。不能把这种受控事务函数与任意
  外部 listener 一概等同；保留时仍需逐调用点验证该前置条件。

### 4.2 外层串行区确实覆盖慢工作

`config/runtime/mode_definitions.rs:89–173` 的保存路径在 `command_lock` 下进行
版本/closing 校验、文档验证、原缓存复制、JSON 编码、读原文件、创建目录、原子写、
manager 替换、必要恢复以及文档缓存采用。删除 `:175–230` 与 reload `:232–269`
也持有该锁执行文件操作/扫描或发布。这是结构事实，不是已测得的耗时数字。

`mode/manager.rs:442–475` 在调用者持 manager 写锁期间重建/排序 snapshot，并调用
`watch::Sender::send_replace`。因此 Mode 保存的嵌套方向包含：

```text
Config command_lock
  -> Mode manager state.write
     -> watch 值写入 / 通知
```

**可构造风险，尚非已发生死锁证明**：如果接收方持有 watch 的 `Ref` 再调用需要
manager 锁的接口，就可能形成 `manager -> watch` 与 `watch -> manager` 的反向等待。
如果通知中的 waker 同步重入 command owner，也会撞到仍持有的外层锁。
必须继续核真实消费者与 waker 路径，不能仅根据示意图宣称已有线上死锁。

### 4.3 两个不能采用的“快速修复”

1. **只将通知挪到 `replace_source` 尾部**：即使释放 manager 锁，调用它的 Config
   command guard 仍活着，跨 owner 重入边没有全部消失。续做合同 §20 因而只是
   两层锁外分阶段通知候选。用户随后同意推荐路线，该部分已按续做合同 §20 开始实施，
   不据此宣称文件事务的大锁问题也已解决。
2. **先释放命令锁，再写最终文件，失败恢复旧字节**：A 读旧版、B 提交新版、A 失败
   恢复旧字节，会覆盖 B 已提交内容。原子 rename 只保证单次替换，不提供业务 CAS。
   必须先确定同一资源写入所有权、原版本与回滚责任，不能靠第二次内存比较补救。

### 4.4 Config/Mode 独立盘点补充

Config 原作者完成只读调查（`message:22:1438` / commitSequence `1692`）；root 核验
报告 SHA-256 `f06bff6a6d06682c6d7b018d6f77002e71f5eac88139dcae9004fe823b8efc44`，
并亲读核心锁表、事务链、候选与不确定项。原始报告在该执行者会话 artifacts 的
`config-mode-lock-transaction-audit.md`，不作为项目运行产物提交。

- command lock 确实横跨 Settings/凭据、Profile、Mode 定义、目录 probe begin/finish
  与关闭；Mode definition read、Config+Profiles 相容解析也使用它。普通 Config read
  与 pinned 材料详情并非全部受它阻塞，不应笼统称为“所有读取的一把大锁”。
- **新增已证缩锁点**：`config/runtime/catalog.rs:100–160` 保持 state 读 guard 时，
  在 Updated 分支调用 `next_observation_order`。root 亲核该函数
  `config/model_catalog.rs:36–52` 包含 `sequence.json` 的读和原子写；网络调用不在
  这个锁内。可先研究释放 state guard、仍保 command 排他责任，不必立即拆整个 writer。
- Mode 定义 JSON 是潜在可独立的文件域；`mode_model_routes` 则属于与账号、role
  和凭据联合校验的同一 `config.toml`，不是独立资源。不能以“都是 Mode 设置”为由
  一起拆开；Config+Profiles 相容读取也不能用分别读取两个 current 取代。
- 已有 ModelCatalogTasks、ReadCalls/Scopes、Bridge/HTTP command owner 分别监督
  自己的工作，但没有覆盖所有 Config/Mode/direct 入口的文件写入责任。复用监督
  不等于已经具备可放开全局写锁的 reservation/事务能力。
- `design/20-config.md:650–653` 明确说目录观察属于另一 lane 且不阻塞配置 command，
  当前目录网络等待已在锁外，但采用阶段仍共用 command lock 并做文件 I/O。
  **这是文档与实现差异，不在本研究里悄悄弱化为“仅联网不阻塞”。** 后继实现先按
  现有设计目标评估；若确需收窄这个承诺，应另行向用户确认，不直接以代码覆盖设计。
- 普通 task wake 未必同步执行接收方业务；当前尚未定位新 Mode observation 的生产
  消费点。仍维持“通知反向边是条件性风险、未证明现役死锁”的结论。

### 4.5 Thread/运输调查：已闭合的等待环与其他分级发现

Native 原作者完成独立只读调查（`message:25:3186` / commitSequence `3364`），报告
`thread-transport-lock-study.md` 的 SHA-256 为
`49bb1f7f4f2e8774d60970eb6851a8e186e6e1bca508df6aa7af21852373a5fa`；同一会话
artifacts 的 `thread-transport-lock-study-sources.json` 记录六十个来源文件身份。
以下位置绑定研究时、L1 修复前的内容。root 已亲读关键等待链，不仅接受摘要结论。

**L1：源码可证明的循环等待，优先修复；未运行复现。**

- `studio/runtime/thread_execution.rs:197–202`、`thread_metrics.rs:100–108`：
  工厂经原 ReadCalls 同步登记 opening，worker 再无条件等待 lifecycle 锁。
- `studio/runtime/read_calls.rs:50–58,69–96,104–112`：返回 future 前任务已登记；
  close 封口并真 join 原任务，封口本身不解除 lifecycle 等待。
- `studio/runtime/lifecycle/transitions.rs:13–16` 与 `lifecycle/shutdown.rs:902–907,
  1335–1342`：strict shutdown 持 lifecycle guard，使用无界预算收束 detailReads。

```text
opening O 已登记但尚未 poll
  ↓
shutdown B 先取得 lifecycle L
  B 持 L → ReadCalls.close → 等 O 完成
  O 开始执行 → 等 B 持有的 L
```

这不依赖假设外部回调违反契约；单线程调度中先调用工厂、不 yield，紧接着 await
strict shutdown 即可安排该顺序。bounded exit 的超时只能截断外层等待，不能从架构
上消除此循环。

已有 `thread_authoring.rs:51–58` 提供复用方式：尚未开始 I/O 的排队准入同时观察
同一 shutdown latch；关闭已提交优先返回原 typed Cancelled，取得 guard 后仍重核。
root 已先同步 design18 与续做合同 §21，再交原作者只修 Execution/Metrics 两入口。
不取消 whole opening，不 abort 已开始 I/O，不改 ReadCalls/permit/join 或原关闭期限。
**两文件修复现已获 fresh 静态批准并精确暂存，运行验证仍延期。** 总差异 12 行新增、
2 行删除，仅在 lifecycle 排队等待中加入原 latch-first select；guard 后原关闭重核保留。
root 核 before/index/after 及其余索引不变，审查后内容为：

- Execution：`aa6bcf985b69da0a70550eb65c008b8ae7420420b7d2a4c587a24f1abecb6988`。
- Metrics：`1a6db1cba4b91e3e261a4bab8b0b164d8461f0720685c147f7ba79c7bb642ddb`。

静态审查覆盖首次 poll 前关闭、排队时关闭、latch/lock 同时 ready、取锁后重核，以及
已进入 I/O 后不被 select 取消；没有新增取消源、测试 hook 或通用准入包装。

**R3：stage wrapper 监督缺口，另行设计，不夹入 L1。**

root 亲核 `lifecycle/shutdown.rs:763–803::run_stage_owned`：先创建局部 JoinHandle，
bounded 超时或 Skipped 分支返回时没有持久槽保留该 handle，因此 wrapper 会脱离 join；
借 `&mut` 做 timeout 仅保护等待期间，不能补上返回后的所有权。原业务 ReadCalls/
scope owner 仍可能保留自己的责任，退出也已 Degraded，不能外推为提前释放或假 Clean。
下一步区分纯汇总等待（可能不需额外 spawn）与必须继续执行的关闭工作（应由原 shutdown
owner 保留 completion），再补迟到结果/失败与显式接续；不新增全局任务框架。

**其余结论保持边界：**

- Thread actor/驻留投影、不可变 snapshot 与原 scopes/ReadCalls 是可复用的唯一 owner，
  不应拆成每 feed 一个 reducer 或第二资源池。
- 当前 Models/Thread HTTP 的 body 没有反向 await 包含自身的 close。peer 不 poll/
  不 Drop 导致真实关闭等待，是未收束责任，不应以提前 EOF/释放来“修死锁”。
- actual-send 与 exposure/sent-prefix 共用门具有原子性意义；其同步、不得重入的
  契约不能被“所有 callback 都搬锁外”机械破坏。普通失效通知/cancel/可能跨域的
  最后引用析构则仍应逐边评估锁外化。
- 索引锁内 cancel、Metrics 锁内 watch 通知属于条件性重入风险；尚未证明现役
  Tokio/Hyper waker 反向获取业务锁。部分 Drop 有跨域锁边，但未找到对应逆边。
- lifecycle 异步锁跨存储、cold checkpoint、baseline ready 的队头阻塞，及 projection/
  window 锁内复制、排序、JSON 字节计量属于性能/隔离疑点。256KiB 最终帧预算不证明
  构造成本恒定；本次没有性能数据，不宣称换锁或无锁方案必然更快。
- 新 Context/ThreadConfiguration 应在无 facet/registry guard 时取得 Config/Mode
  owned 基线与订阅；结束 watch Ref 借用后才跨 owner/await，再在短 facet gate 核原
  Thread/incarnation 与来源水位发布。该约束已写入 design18，不冻结未决业务来源语义。

## 5. 推荐架构与必须保留的约束

用户已明确按推荐方向继续 PR。先按续做合同 §20/22 实施 Mode 分阶段通知与 sequence
I/O 缩 state 锁；更广的领域写入拆分与 shutdown 阶段监督仍先冻结具体所有权和错误
合同，不因采纳方向而跳过这些证明。Models 完整生产 port 与公开回归/装配盘点独立推进。

第一阶段四文件已完成并获独立静态批准：Mode 通知越过 manager 与 Config 外层命令
guard，结果保同次 snapshot；catalog sequence I/O 前释放 state guard，但保 command
事务责任。root 已核身份并精确暂存。此结果不证明全局写入隔离目标已完成，运行验证
仍延期；未把后继 observation 消费者尚未接入当作本切片新增代码缺陷。

### 5.1 优先级

1. **先修 L1，再消除反向调用与等待边**：业务锁内不做未知回调或等待；失效通知、
   取消与资源析构按实际重入边缩锁，保受控 actual-send 的原子契约。处理
   watch 值时立即复制必要标量/Arc，释放 Ref 后才跨 owner 或 await。
2. **再减小准备阶段**：锁外完成与共享状态无关的解析/编码；按实际错误优先级和
   CAS 语义设计提交接口，不因提前验证改变原拒绝类别。
3. **再处理持锁 I/O**：若现有 owner 可监督完整写入任务，先在同一准入边界登记原
   命令，受管任务持有必要写入责任至文件与内存采用结算。等待者取消不撤销已受理写入。
   这是候选责任划分，不能只把现有闭包塞进 `spawn_blocking` 就认为实现完成。
4. **最后才考虑拆领域写入队列/替换快照容器**：先证明跨域 reload、catalog pair、
   Profiles 与 Mode 的交错不会撕裂事实；必要时保留真实事务协调，禁止第二 writer。

### 5.2 读、提交、通知分离，但不拆散事务

建议的责任顺序是锁外准备、准入与原版本校验、受管写入、原 owner 原子采用、锁外通知。
这不是允许在文件写入期间随意释放所有排他责任：同资源写入顺序与恢复授权必须始终
属于原 owner。可并行的只是已证实独立的准备或资源，不能绕开已有配对版本与 receipt。

通知若延迟到后继提交之后才执行，应只作为重新读取 canonical 状态的提示，不回灌
旧快照；保留原 revision/同 revision 失效语义、无接收者保值、原 close/closing 单调性。
不增加独立发布队列、镜像或历史事件总线。

### 5.3 关闭也纳入等待图

目标依赖为：原 owner 封准入并保留在途登记，锁外通知取消，锁外等待真实终态，确认
所有责任结束后释放。不得让 producer 等 consumer 的 ACK，同时 consumer 等包含
自身的 close；不得持有 registry 锁 join 还需访问 registry 的 worker。

`spawn_blocking` 开始执行后不能靠 abort 强制停止；`JoinHandle` Drop 会脱离任务而非
等待。等待 deadline 到期只能返回原 Unresolved/诊断并保留原 join 责任，不能报 Clean。
这些要求复用现有监督和配额，不新增第二注册表。[S8][S14]

## 6. 后续验证目标（此阶段未执行）

- L1 以真实公开 opening 与 strict shutdown 控制“登记先于 worker poll”的顺序，
  核 Cancelled、真实关闭与后继准入拒绝；不以复制坏算法或仅未超时代证。验证安排
  在项目允许的既有验收入口，不借本研究给其他 Rust crate 新增无门禁测试。
- 用真实公开行为构造通知重入、先订阅/后发布及发布早于订阅的交错；证明既无漏失效，
  又无旧 revision 回退。受控内部提交函数另核不会越过其禁止 I/O/重入契约。
- 同版本并发保存只允许原 CAS 结果；后继成功提交不能被旧失败恢复覆盖。
- 慢文件操作期间，独立快照读取与必要的关闭封口保持可推进；最终关闭仍真等写入。
- 在 opening、query、回调和 close 等待边分别取消调用者，再以原 owner 接续收束。
- 满 Data 窗口不挡 control/cancel；UI consumer 不等待包含自身的关闭链。
- 将争用等待、持锁时间、阻塞任务排队、快照复制成本分别测量，报告分位数和工作负载；
  不以锁数量、代码行数或一次“没超时”代替性能与安全证据。

测试入口与允许层级仍遵守 AGENTS/design24；不为研究新增生产测试 hook 或扩公共 API。
当前不新增测试框架，不运行 Loom/压力测试；只有存在明确模型边界与收益时再评估。

## 7. 官方与维护方资料

以下网页于调查日经配置的网页工具读取。Rust/Tokio 是 API 契约来源；PostgreSQL/Linux
仅提供可迁移原则，不把数据库死锁检测、内核抢占规则或 RCU 实现冒充本项目能力。
第三方文档只作候选初筛，未完成引入所需的平台/许可/版本选型。

| 编号 | 来源与本次用途 |
| --- | --- |
| S1 | [Tokio — Shared state](https://tokio.rs/tokio/tutorial/shared-state)：短同步锁与异步共享的选择。教程不是项目锁定版本证明。 |
| S2 | [Tokio — Channels](https://tokio.rs/tokio/tutorial/channels)：专属任务持有资源、消息传递及 channel 类型。 |
| S3 | [Tokio Mutex](https://docs.rs/tokio/latest/tokio/sync/struct.Mutex.html)：异步排他与 FIFO 契约；本次 latest 为 1.54.1。 |
| S4 | [std RwLock](https://doc.rust-lang.org/std/sync/struct.RwLock.html)：1.99.1，OS 相关优先级与重入读风险。 |
| S5 | [Tokio RwLock](https://docs.rs/tokio/latest/tokio/sync/struct.RwLock.html)：1.54.1，公平/偏写队列。 |
| S6 | [Tokio watch Receiver](https://docs.rs/tokio/latest/tokio/sync/watch/struct.Receiver.html)：1.54.1，Ref 实际持读锁，长借用可阻塞 producer。 |
| S7 | [Tokio watch Sender](https://docs.rs/tokio/latest/tokio/sync/watch/struct.Sender.html)：1.54.1，send 与保留更新方法的无 receiver 语义。 |
| S8 | [Tokio JoinHandle](https://docs.rs/tokio/latest/tokio/task/struct.JoinHandle.html)：1.54.1，Drop 与借用等待取消安全。 |
| S9 | [PostgreSQL 15 — Explicit Locking §13.3.4](https://www.postgresql.org/docs/15/explicit-locking.html)：一致取锁顺序和避免长事务等待；本项目不因此获得数据库死锁检测。 |
| S10 | [ArcSwap 维护方文档](https://docs.rs/arc-swap/latest/arc_swap/)：读多写少的快照替换、回收与限制；网页另说明 1.9 内存顺序修复，不在此预先推荐版本。 |
| S11 | [Linux — Unreliable Guide To Locking](https://docs.kernel.org/kernel-hacking/locking.html)：锁封装、持锁外部回调风险，以及不能为避死锁而破坏原子性。 |
| S12 | [DashMap API](https://docs.rs/dashmap/latest/dashmap/struct.DashMap.html)：带锁引用与多种方法的 deadlock 前提；latest 不作为项目 5.5.3 的逐项验证。 |
| S13 | [Linux — Sequence counters and sequential locks](https://docs.kernel.org/locking/seqlock.html)：writer 串行化、抢占及指针限制。 |
| S14 | [Tokio spawn_blocking](https://docs.rs/tokio/latest/tokio/task/fn.spawn_blocking.html)：阻塞隔离、开始后不可 abort，以及超时不终止工作。 |
| S15 | [std Mutex](https://doc.rust-lang.org/std/sync/struct.Mutex.html)：1.99.1，poisoning 是失败信号而非自动恢复事务不变量。 |

poison 恢复亦需逐 owner 论证：仅调用 `PoisonError::into_inner` 不会自动修复半提交，
也不能在此把全部恢复策略机械替换为 panic。当前仅记录该审查义务，不改既有错误合同。
