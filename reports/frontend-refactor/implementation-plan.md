# 全链路重写计划 v5：保全后删除旧源码、按模块并行实施、架构问题即时裁决

## 1. 本次调整与当前基线

本计划按用户最新指令替代 v4 的实施节奏：**不再等待完整类型册、所有 VM 字段和全部跨层方法逐项细化后才开始编码。** 立即转为保全源码、删除明确需要重写的旧源码、按目标模块并行实施；执行者遇到不能确定的架构、公共接口或业务语义时，暂停受影响部分，由主代理判断并给出下一步指示。其他独立部分继续推进。

保留此前全部功能、安全、架构和最终交付目标；不再进行没有具体实现阻塞的泛化探索。现有 v4 合同中已经确定且与本计划不冲突的类型、字段和不变量继续作为起点；其中“整包合同未齐不得派编码”的前置条件由本计划撤销。候选报告、未核实建议和未完成合同不自动成为强制接口。

当前事实：

- 任务分支：`pure-session-thread-65e3ee582f0d4-82`。
- 最新已提交并成功推送：`c262df7e33526800ec1857dfe1042e0121c7c3ab`，13 个设计/工程合同文档；其父为 `9e00fb0ee2ab4b9ddbe3e379d545e1679d4393c6`。
- 已完成主线同步；贡献比较基线仍是 `b3f22b8f651816851852582a10a970fe25af3ae6`，源码重构输入仍是 `78a2762495772d7fe416faaf5f14876cf46597c4` 加已保全的未提交成果。文档提交没有改变该输入身份。
- 当前工作区仍有未提交的生产、测试、生成输入及协作文件改动，不回滚、不混入无关提交。
- 现有 Draft PR：https://github.com/ZR233/anywork/pull/120 。c262 对应 CI run `39749225086` 尚未确认全部终态；它只覆盖文档提交树，不是新实现验收。
- 旧备份、stash、同步工作树与 QA 证据继续保留；不重复 apply 旧 stash，不重新同步主线或启动旧实验。

## 2. 必须交付的目标

1. **Feature-First**：纯 Dart SDK 按真实领域分模块，Flutter 按功能组织；app 只负责装配、启动、导航和退出。
2. **Smart/Dumb 严格分层**：Screen/Connector 连接 VM 和平台 UI；View/Widget 只收不可变 props、UI Controller 与 typed callback，不依赖 Riverpod、Repository、Client、FRB 或 service locator。
3. **生成式 AsyncNotifier 是真正 VM**：管理编辑、校验、防抖、可见需求、pending/error/latestIntent 与交互编排，不把旧巨型 Client 包起来继续使用。
4. **Freezed 不可变值**：领域值和 ViewState 使用 Freezed；连接、Session、任务、Controller、permit、native handle、操作 ticket 等资源 owner 不值对象化。
5. **typed push 与按需读取**：Thread 五域、Timeline、产品各域按载荷、频率及生命周期分开；大文本、历史、详情和原图通过具名 typed 接口有界读取，不轮询实时状态，不以 raw JSON 拼装已知 DTO。
6. **唯一事实源**：Rust 是业务权威，各领域 Repository 是 Dart canonical 镜像唯一 writer；VM 不维护第二 reducer、模型策略或目录事实。
7. **全消费者迁移与删除**：生产、demo、fake、测试、Driver、Server、公开导出、生成输入一起迁移；删除旧 facade、兼容 alias、重复 owner、转发目录和无消费者实现。
8. **真实交付**：完整实现、统一生成、适用全门禁、原生集成验收、可复算质量/代码量对比、实现提交、任务分支推送、PR 更新及对应 CI 终态。

非目标与权限限制：不重写无关 Rust 内核/供应商协议，不做无关视觉改版，不新增自研消息总线/状态管理/codec；不推 main、不合并 PR、不发布、部署、选版本或打 tag；不删除用户数据、配置、凭据、数据库、历史或未知文件。

## 3. 先保全，再直接删除待重写源码

### 3.1 建立本次删除前快照

主代理先核对活动写入者和后台任务，保持同一文件只有一个 writer。使用当前 Thread 的 artifacts 保存：

- 当前 HEAD、分支、完整 Git 状态和已暂存/未暂存 diff；
- **本次实际删除范围内每个文件的完整内容、路径、mode 和 SHA-256**，包括未提交、未跟踪内容及此前 overlay；不能只依赖 Git HEAD 恢复未提交成果；
- 明确的删除清单、保留清单、目标任务 owner 和可追溯的快照位置。

旧90路径备份不覆盖所有本次将删文件，故不能替代这次快照。快照只用于查阅和恢复，不是将未验收代码提交为备份 commit。

### 3.2 删除边界

在快照核验后，主代理按显式路径清单删除明确重写的旧手写 Dart/Flutter 源文件或目录：旧 Client/Store/Commands/facade、旧平铺领域模型、旧 Presentation/providers、旧功能呈现和需要整体重写的 FRB adapter 手写入口、旧 app 装配等。删除后允许工作区暂时不可编译。

- 根 barrel、共享模型和公共接缝也按唯一 owner 重建，不保留旧转发壳来维持中间编译。
- Rust/FRB/Server 只删除或替换本次确实需要重构的手写接缝文件/定义；**不整删 protocol/runtime crate 或无关业务实现**。保留原业务权威、存储和供应商能力，按新接缝迁移调用链。
- 保留平台工程、资源/assets、原生构建配置、未授权的配置/协作文件，以及无需重构的代码；不把“直接删除”扩大为清空仓库。
- 生成文件不手工重写；暂时失效或孤儿生成物由 root 在最终统一生成时处理。
- 测试/Driver 不因暂时无法编译或断言失败而删除功能覆盖；C 迁移对应消费者和真实回归。仅删除确已由新架构替代的旧接口专属源码。
- 执行者以已冻结快照、Git 基线和现有设计查阅旧功能，不从删后的空目录猜业务，不擅自整体恢复旧架构。

## 4. 文档与即时架构裁决

主代理先简要同步 design 中的目标架构与当前实施规则，然后开始删除与派发；不继续补完整的实施前百科式合同。

已有明确共享类型、错误分类、来源身份、预算、receipt 和 owner 规则继续沿用。需要补充的接口在实现碰到实际依赖时处理：

1. 执行者报告具体阻塞：调用双方、当前代码/合同证据、缺少的类型或时序、候选方案及影响；不自行猜测关键语义。
2. 执行者暂停该受影响范围，可以继续本任务中不依赖该决策的工作；不得通过旧 facade、dynamic、fallback 或临时兼容分支绕过。
3. 主代理统一选择接口/归属/行为，先更新必要设计或工程合同，再一次性向所有受影响执行者发送完整决定，明确替代哪些旧建议。
4. 普通私有函数、文件拆分、局部算法由执行者自行完成；只有确实改变用户目标、关键业务语义或涉及额外授权时才询问用户。
5. 不为常规接口补齐重新请求实施授权；不再以其他模块尚未完成或合同未穷举为理由阻塞整个重写。

## 5. 并行模块与所有权

按实际可用容量优先使用本地 directory executor；互斥模块依赖已确定的接口并行实现，不等待前置模块测试通过。共享文件、barrel、生成输入和装配只有一个 owner。现有输入清单作为定位依据，主代理在删除清单中同步新旧路径所有权。

| 任务 | 职责与边界 |
| --- | --- |
| R：Rust/protocol/FRB/Server | 必要 typed 分域投影、feed/query/command、流控、取消/join、来源水位、HTTP/SSE/OpenAPI及旧聚合入口删除；不重写无关内核 |
| D0：Dart 共享基础 | resources/operations、只读观察、typed 错误/身份/预算/关闭值与 port、公共根 barrel/导出；不成为新的 God facade |
| D1：Conversation/drafts | Session、五域镜像、Timeline消费与查询、草稿/附件、冻结提交、Interaction、输入保存证据、新建准备与长寿命操作 owner |
| D2：Configuration/models/modes/usage | 配置与模型真正拆域、Settings CAS/批次、账号/Profiles、用量、Mode编辑命令及各域镜像 |
| D3：Workspace/resources/updates | 唯一选择协调、目录/元数据/分页、StartupRepository、远程/资源动作、Updates镜像与任务；应用退出协调不放入 SDK |
| A：Adapter/demo/fake | FRB 到 typed port 的唯一转换及 owner 适配、生产与替身一致；不做第二 reducer、不手改生成文件 |
| U0：公共 UI | 主题、l10n、格式化、共享视觉组件、确认/状态/附件元信息；无业务 reducer |
| U1：Settings | 全部设置子域的真实 VM/Freezed state/Smart-Dumb；保存、dirty、失败、凭据和原输入约束完整保留 |
| U2：Conversation | Composer/Interaction/Timeline/Status/Context/Metrics/Todo/Plan及展示 lease；不复制正文集合或丢冻结操作 |
| U3：App/Workspace | composition、bootstrap、routing、sidebar/workspace、唯一应用退出协调，删除旧 shell/providers 和第二选择来源 |
| C：消费者/门禁源码 | 测试、Driver、diagnostics、xtask/CI、AST规则、旧SDK facade/模型目录与孤儿消费者清理；不执行测试 |

D0/U0优先发布最小公共形状；其他模块可以同时实施已确定部分。基础接缝未存在时不通过兼容壳绕开，由 root 协调具体依赖。只有真实交付依赖才建立等待关系，不为形式扩展 DAG。

每份派发包含本完整计划、该任务目标与验收、源码快照/基线、允许目录与禁区、已确定接口/owner/时序、关键安全要求、消费者责任、静态验证限制及架构阻塞上报方式。执行者不修改 design、共享邻居文件、Git 索引或提交。

## 6. 必须贯穿实现的安全和业务不变量

### 6.1 状态、编辑与操作

- 首次 await 前冻结目标 Thread/Project、具体 Session/incarnation、operation、revision、draft stamp、路由和附件归属；迟到结果只结算原操作。
- 同步登记观察并取得当前值，避免 snapshot→await→listen 丢首帧。
- canonical 更新不清 dirty raw；未知不伪造 Idle/Disabled/空集合，last-known 保留原来源身份。
- Accepted、Observed、Effective、Durable 独立；ACK/业务 Completed 不证明 durable。
- UnknownOutcome 保留冻结输入和附件，不自动重发，不因 Widget/Provider dispose 丢失。
- 输入 durable 必须匹配真实 history 输入身份、原生 requestDigest 与 accepted sequence；不能用任一 Turn.saved 或 Dart 伪造 receipt 证明。
- Profiles、Settings、Mode binding、route、目录各用实际来源水位，不借全局序号或不相干 core commit sequence 证明收敛。
- 同目标冲突写串行；停止、详情和分页不排无关长写 FIFO。多字段保存是独立真实子操作，不伪装原子事务。
- 凭据 Preserve/Replace/Clear、hasBearerToken、敏感回答、原输入字符集/空值/数值范围严格保留；Freezed 不使 secret 可以进入日志/Driver。

### 6.2 流控与资源

- typed feed 最多2个未 ACK Data，baseline占额度；latest待发仅1份，可靠队列遵守已定帧数/源字节预算。
- ACK针对具体句柄已连续处理的前缀；超sent拒绝，转换/归并/必要展示交接失败不ACK。
- 缺口显式ResyncRequired/Lagged，只恢复受影响域，不重放业务命令；终态有序交付，取消控制不被满窗口阻塞。
- requestClose同步封准入；close等待open、producer、sink、query、consumer、stream cancel等真实完成后才释放permit/dispose。
- Unresolved保留owner、handle、全部typed issues和真实恢复能力；awaitCompletion/retryClose/terminal分开，不永久缓存可恢复旧Future，不用Drop/GC/超时假join。
- 所有fake/demo遵守实际listen认领、typed Conflict及closing Cancelled优先，不在events getter认领。
- Timeline具体候选/consumer/mount/Session身份全部受监督，不只比较threadId，不漏收束后续consumer。

### 6.3 功能与数据保全

- 完整Turn历史不能被active/recent摘要替代；历史2MiB普通页预算有超大首项例外，游标水位不是跨页数据库事务快照，不能虚构保证。
- 目录保原查询、排序、pin、父子关系、search的Project依赖和keyset语义；当前窗口缺项不等于实体不存在，total不冒充全库数量。
- 原图/大字节不进Freezed ViewState；typed按需读取保原draft/Thread资源权限和模型/上传准入。
- 新建进度断流不等于取消创建；只在实际能力存在时承诺取消，退出必须真实join已受理工作。
- 更新检查/下载/校验/安装包lease与应用退出分责；本地启用条件不伪造canonical状态；Server不凭桌面能力新增安装/退出端点。
- ApplicationExitCoordinator仅归U3；首次30秒绝对退出期限不续期，外部issues先于唯一native finalizer，Clean与installer结果分开，Degraded不安装。
- 遵守v2数据根隔离和现役v2迁移规则；不删除旧数据，不用清库/恢复默认解决迁移。

## 7. 实施期只静态审查，不编译测试

全部手写实现、消费者迁移和旧入口清除完成前，root、executor、reviewer均不得运行：

- cargo build/check/test/clippy、Flutter/Dart analyze/test；
- 格式化、代码生成、GUI/fixture/live、性能探针、验证性示例构建；
- 会隐式构建或生成的验证入口。

允许读取、rg/符号定位、源码及测试源码编辑、静态diff/接口核对、hash/链接/空白检查及受控Git操作。删旧源码后临时不可编译是预期状态，不能为中间绿色恢复旧API、删断言或增加fallback。

每收到执行者完成报告立即安排fresh reviewer，亲读实际文件和内容身份，只审该任务逻辑、接口、所有权、失败路径、功能保全与迁移覆盖。未执行最终检查不单独阻塞局部静态批准；真实缺陷和遗漏必须阻塞。问题交原执行者修复，再新reviewer复审。

本地directory成果原地生效；如确需worktree，审查通过后串行整合，不能夹带未审改动。执行者及现场保留到最终验收通过。

## 8. 全部手写完成后的统一验收

进入条件：各模块完成、消费者全迁、旧入口全删、当前版本局部静态审查通过、全部worktree成果整合。root亲自做跨任务审查，逐项对照目标、最新决定、设计与diff。

随后从仓库根统一执行 `cargo xtask generate-gui`，检查canonical生成及孤儿清理；不手改FRB/Freezed/Riverpod/l10n生成内容。

适用最终门禁：

- `cargo fmt --all --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test -p pl-model`
- `cargo test -p pl-core --features sqlite`
- `cargo test -p pl-studio-runtime`
- standalone core无数据库/SQLite两个profile，必要bridge契约检查及Server编译
- `cargo xtask verify-client`
- `cargo xtask verify-gui`
- 新AST边界规则与反例fixture
- `git diff --check`

最终代码问题交原执行者局部修复、复审，再补受影响验证；不机械重跑输入未变的有效证据。所有失败、零测试、超时、权限/环境问题保留真实记录，不冒充通过。

原生验收使用官方xtask、真实bridge、隔离模拟供应商及Flutter Driver；Linux SSH用私有Xvfb和绝对XAUTHORITY，受控回收进程树。覆盖设置保存/失败/dirty、发送停止互动、UnknownOutcome/冻结附件、五域独立更新、Timeline历史/长正文/图片/冻结与回Live、满窗ACK/query/resync、切Thread/冷恢复、真实取消join、保存失败、退出与更新、正常/窄窗口截图。旧初始连接失败纳入实际typed错误取证，不以旧绿色解释根因。

Linux实测、Windows CI、真实供应商和人工截图评审边界分开报告。模拟通过不冒充真实厂商或用户人工批准。

## 9. SSH与外部操作规则

SSH失败后等待10秒，再只读核原task、文件/写入结果与所属进程；状态未知的写入不重放，原任务活跃则继续等待。只读检查确认旧进程结束后才可重新观察。不得nohup/detach、全局pkill、杀用户桌面或占用1420。

已推送的进度提交保留；新的实现代码在完整重写和最终验收前不作为可交付阶段推送。用户数据、旧stash、备份及未交付现场不清理。

## 10. 最终对比、提交、PR与完成标准

使用同一源码统计脚本，对冻结main b3与最终实现版本复算：手写Dart/限定Rust/测试/Driver/生成代码分别列文件数、LOC/非空行、增删比例；最大文件/library、严格>500行数量、手写part、平铺密度、重复实现、旧接口删除、真实Repository/VM/Freezed/Smart-Dumb覆盖分别说明。搬家、生成替代和真正去重不混算；无可比测量不报性能提升百分比，不把源JSON预算当wire/RSS。

完成后提交Conventional Commit，必要破坏性变更如实用`!`/BREAKING CHANGE并给迁移说明；推送任务分支、更新现有Draft PR，等待**对应实现commit**的CI全部终态。进度文档CI不替代该步骤。

最终验收通过后按归属关闭代理、确认资源回收；失败保留可恢复现场。最终一次性交付PR、commit、贡献基线、可复算质量对比、实际验证/CI与平台覆盖；未解决功能缺陷、遗漏消费者、未知资源清理或缺少门禁不能标记完成。
