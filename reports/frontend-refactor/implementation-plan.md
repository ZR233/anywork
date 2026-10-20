# Rust／FRB／Dart 全链路重构与 Contract-First 实施计划

> 本文记录已批准的 v3 完整实施计划及明确的现场更新，不表示各阶段已实现。
> canonical Plan revision 6，document version 3，批准内容身份：
> `sha256:8dbea7a50d90d0cd6b6de5502a997923734e0cbd37459aaf0efa204596f56dc3`。
> 现场更新：按用户要求拉取最新主干后，实施与最终贡献比较基线改为
> `f6cb327ceb3416dca181790575711588571d3ec7`；用户另要求先建 Draft PR，后续阶段成果分别 commit/push。
> 下文保留原计划完整的目标、架构、准入、验证与交付要求；原始基线只作历史记录。

## 1. 目标、范围与交付

对当前 Dart／Flutter 及必要的 Rust／FRB 边界进行彻底重构，不以旧目录、Client API、状态归属或设计文档为不可改变的前提。目标是降低重复知识与跨层耦合，让维护者能够从功能入口清楚追踪状态、意图、事件与资源生命周期，而不是只获得一次文件搬迁。

采用用户明确要求的技术路线：

- **Feature-First** 组织功能。
- Presentation 严格区分 **Smart Screen／Connector 与 Dumb View／Widget**。
- 使用代码生成的 **AsyncNotifier 作为 ViewModel 核心**，承担真实的呈现状态与交互编排；同步纯计算仍使用派生 Provider。
- 使用 **Freezed 定义不可变领域值与 ViewState**；连接、Controller、任务和资源 owner 保持适当的可变生命周期类型。
- 实时变化通过 **Rust → FRB typed 事件推送**，按资源、作用域、频率和载荷大小分割投送；历史、详情、原图与显式查询按需读取，不轮询实时状态。
- 主代理先确定架构、接口、状态机和验收合同，再委派实施；**未确定的设计问题不得下放给执行子代理自由决定**。
- 最终提交 Conventional Commit、推送任务分支、创建 PR，交付可复算的代码量及工程质量前后证据，并等待实际 CI 终态。

保留用户能力与安全不变量，而不是保留旧实现：不丢用户数据／凭据，不改变未知结果、命令目标、保存与执行终态、脱敏及资源释放的正确含义。可以破坏旧内部 API，必须同步迁移消费者并删除旧入口，不长期保留两套状态或兼容 facade。

非目标：无关 Rust 内核重写、供应商协议重做、视觉改版、用户数据删除、发布、部署或直接合并 PR。若确需修改持久化结构，必须提供并验证迁移，不能备份后清空。

## 2. 依据、选择及纠错

### 2.1 已核实事实

原始基线 `824724165a99c30ec28e5f90e734aa6abfc64c91`，初始工作树干净；Flutter 3.47.7、Dart 3.13.5、FRB 2.13.0。最新基线见本文开头，不把主干新增代码算入重构贡献。

已对照 Flutter Architecture guide／recommendations／case study、Effective Dart、Riverpod Providers／DO-DON'T／代码生成／副作用／select／autoDispose，以及 FRB v2 的 Stream、RustAutoOpaque Ownership／Dispose、Codec、Zero-copy 文档和锁定版本源码，核实：

- 现有多层 provider／投影主要重复观察 Client，不宜在外面再套 AsyncNotifier。
- Client 同时暴露 transport、可写 store、命令、草稿和资源；canonical 与命令呈现 overlay 有混放。
- Thread／产品 topic 已有 StreamSink 推送；Timeline 正文仍由 Dart `initial/next` 泵消费。
- 高频 runtime 更新会重传聚合状态，产品集合也有整包替换。
- `StreamSink.add` 不是 Dart 消费完成 ACK；Rust mpsc 有界不等于 Dart port 在途消息有界。
- Opaque `dispose`／GC、Stream.cancel、Ref.dispose 都不能单独证明 Rust 任务已经 join。

### 2.2 选定方案

采用 **分域 Repository＋Session／资源服务＋Feature AsyncNotifier ViewModel**：

- Rust 持有业务权威；Repository 是对应领域 Dart 镜像的唯一 writer。
- Session／资源服务处理持续订阅、attempt、提交冻结、附件 ownership 与异步关闭。
- ViewModel 管理编辑、校验、可见需求、操作呈现和查询编排，不复制领域 reducer。
- Dumb Widget 只渲染 typed props 并发出意图。

排除旧 Client 外套 VM、将所有资源交给 autoDispose、仅靠末端 select 优化传输、以及自研状态管理／消息总线／codec。使用现有官方组件及成熟依赖，仅做必要的领域与边界适配。

### 2.3 进一步澄清

1. **业务终态与传输终态不同**：TurnCompleted、saved 等是有序业务数据，不能借“终帧”名义绕过顺序与投送窗口；取消控制及至多一次的传输 Failure／Closed 才不应被满窗口阻塞。
2. **传输 ACK、领域 revision、命令效果、durable 保存不同**：ACK 只释放在途额度，不推进业务版本，不证明保存。
3. **Freezed 不要求零依赖 SDK**：纯 Dart 数据包可以使用必要的纯 Dart annotation／生成工具，但不能引入 Flutter、Riverpod、FRB 或 native 句柄。
4. **不机械要求每个 VM 合并多个来源或禁止单行 intent 方法**：是否保留一层取决于其封装责任，不按行数或来源数量凑架构。
5. **跨两个 package 的分层不重复建设**：数据／领域层在纯 Dart 包，Flutter feature 不再为形式完整另建一套同构 Repository／Model。

## 3. 固定架构层级、目录与依赖方向

```text
Rust 领域 owner／Session／持久化
  → typed resource feeds／queries／commands
  → FRB adapter：生成 DTO、句柄、编码及 typed 转换
  → Dart Repository／Session services：唯一领域归并与资源生命周期
  → 生成式 AsyncNotifier：Feature ViewState 与交互编排
  → Smart Screen／Connector：观察、意图绑定、导航及平台 UI
  → Dumb View／Widget：数据、回调与局部 UI 状态
```

### 3.1 目标组织

- `anywork_client`：按 configuration、workspace、models、account_usage、conversation、drafts、modes、resources、updates 等领域组织 domain／data；runtime 下只放操作、订阅、预算、生命周期等共享机制。
- Flutter `app`：composition、bootstrap、routing、lifecycle。
- Flutter `features/workspace`、`features/conversation`、`features/settings`：各自的 presentation；再按实际子功能分组，不为对称创建空目录。
- presentation 内固定职责：`screens`／`connectors`、`view_models`、`state`、`views`／`widgets`。
- 通用视觉组件和主题归 `core/ui`；通用纯展示格式化按语义归组；FRB adapter、platform、diagnostics 分别独立，不能回到万能 shared 目录。
- 生成输出仍是独立生成边界，不混放手写 barrel 或业务默认值。

具体文件迁移表由主代理在派发前完整冻结；执行者不得自行更换 feature 名、引入第三套分层或保留旧转发目录。

### 3.2 依赖许可表

| 层 | 允许依赖 | 明确禁止 |
| --- | --- | --- |
| Dumb View／Widget | Flutter、主题／l10n、immutable props、UI-only Controller、回调 | Riverpod／Ref、Repository、Client、FRB、transport、service locator |
| Freezed ViewState | 领域值、呈现枚举与不可变集合 | Widget、BuildContext、Ref、连接／任务／native handle |
| Smart Screen／Connector | 对应 VM、View、导航／对话框／平台 UI 适配 | 直接调用 FRB、transport、可写领域 store |
| ViewModel | 领域公共接口、Freezed state、Riverpod | Widget／BuildContext、具体 FRB adapter、数据库、provider 初始化中的业务写入 |
| Repository／Session service | typed ports、领域模型、操作与资源机制 | Flutter、Riverpod、FRB 生成类型、前端 Controller |
| FRB adapter | 生成 DTO／opaque、typed port、明确转换 | 业务 fallback、UI draft、第二 reducer、持久化事实 |
| Rust 产品投影 | 真实领域 owner、Session、现有 Tokio 机制 | Widget 几何、GUI 全量历史缓存、第二业务事实源 |

跨 feature 只消费公共能力，不导入其他 feature 的 ViewModel、私有 state 或具体实现。组合根可以装配多个领域，但不得成为新的 God facade。

## 4. 状态、所有权与生命周期合同

| 状态／资源 | 唯一 owner | 其他层的权利 | 结束条件 |
| --- | --- | --- | --- |
| 业务事实与可靠历史 | Rust 领域 owner／Session | typed 读取／命令 | 领域关闭与既有可靠保存规则 |
| Dart canonical 镜像 | 对应 Repository reducer | 只读观察 | Repository/runtime 关闭 |
| operation 身份、未知结果、receipt、观察水位 | 操作注册与领域写入边界 | VM 观察并决定呈现 | 真实结果／join，不随 Widget 消失 |
| 会话连接、attempt、待返回 open、订阅与查询 | Session／资源服务 | VM 借用能力 | 显式目标切换／关闭／退出，真实 ACK 后释放 |
| 长寿命 composer 草稿、冻结提交与附件 ledger | 领域草稿／附件服务 | VM 发编辑／提交／放弃意图 | 明确转移或放弃，不因 Settings 往返清理 |
| 页面编辑原始输入、校验、防抖、操作呈现 | 对应 Feature VM／编辑会话 | View 渲染与回调 | 明确编辑会话结束；已受理任务仍由领域层 join |
| 模式编辑 JSON／graph／撤销重做呈现 | 单一模式编辑 VM／编辑会话 | 两种 View 观察同一状态 | dirty guard 处理完成后结束，不双份编辑状态 |
| Timeline 已加载 Message 与 UI 控制器 | 展示 coordinator／lease | View 借用 UI-only binding | 子树卸载确认后销毁；不停止 Session／writer |
| 焦点、composing、动画、局部展开和滚动几何 | Widget／UI Controller | 不反写 canonical | 本地 UI dispose |
| 页面导航 | go_router | Smart 发导航意图 | 路由生命周期 |
| 当前工作区业务目标 | Workspace session coordinator | route／Screen 读取或发 activate 意图 | 显式目标变更，不保留第二可写 selection provider |

### 4.1 共同规则

- 首次 await 前冻结 ID、目标、revision、draft stamp、operation ID；后续完成不按新的“当前选择”重定向。
- Repository 的观察登记与当前值读取是同一同步步骤，不能先读 snapshot、await 后再 listen。
- last-known＋同步错误与“从无可渲染数据”的初始失败分开；局部保存或重连不把整页切成空白 loading。
- 编辑 VM 不能因 canonical 更新整体重建并清空 dirty draft；同目标更新只按已定义的 merge 规则推进基线。
- 每次 await 后核对 mounted／retired、目标与 generation；旧成功、失败、finally 只结算自己。
- UnknownOutcome 不自动重放；Rejected、观察失败、效果生效与 durable 各自保留。
- VM dispose 取消自己的观察／计时器，不自动关闭跨路由 Session 或清附件；应用级关闭显式 seal、cancel、join，最后再 dispose provider container／opaque。
- `keepAlive`、family key、编辑会话保留和预算必须在每个 VM 的合同中指定，不交执行者猜测，也不以 keepAlive 掩盖资源泄漏。

## 5. 已选定的接口形式与设计模式

本节是采用的接口基线；P0 中由主代理补齐所有字段／变体／签名、验证消费者，并冻结为有版本的完整契约。以下不是让执行者自由补全的模板：**缺失项未由主代理补齐前，不启动对应实施任务**。

### 5.1 FRB feed 形式

采用具体的 typed opaque feed，而不是万能 JSON 流或泛型 RPC：

```rust
pub async fn open_thread_feed(
    thread_id: String,
    facet: BridgeThreadFacet,
) -> Result<BridgeThreadFeed, BridgeError>;

impl BridgeThreadFeed {
    pub async fn stream(
        &self,
        sink: StreamSink<BridgeThreadFrame>,
    ) -> Result<(), BridgeError>;

    pub async fn ack_through(&self, delivery_sequence: u64)
        -> Result<(), BridgeError>;

    pub fn request_close(&self);
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError>;
}
```

Timeline 与产品资源采用同样的**生命周期纪律**，但使用各自具体 feed／frame／query 类型，不为形式统一建巨型 trait 或万能 enum handler。Timeline 页／详情绑定同一 reader 身份，不能被同 ID 的另一次 runtime 替换，也不与事件等待共用阻塞锁。

`BridgeThreadFacet` 按 execution、metrics、context、configuration、plan/workflow 等内聚资源分组。facet 内的 PlanChanged／WorkflowChanged 等 typed 变化只携带变化字段，不因共用一个 feed 重传无关大字段。

### 5.2 Repository 读写形式

共同接口纪律，不创建万能 Repository 基类：

- `snapshot`：同步只读当前领域状态。
- `observe(listener)`：同步返回登记时的初始值和仅拥有自身观察的 lease；不暴露 publish/setState，不在返回前重入 listener。
- 领域写动作：接受 typed intent，立即登记 operation／冻结目标，返回只读 operation ticket；ticket 暴露身份、状态观察与 typed 最终结果，不向 UI 暴露 reducer、permit 或重放按钮。
- 显式 query：typed 请求与结果，携带目标／revision／cursor；由领域层登记、去重、取消与 join。
- Repository／资源服务 close：幂等、真实异步收束，返回 typed 未解决资源报告。

分域方法面固定职责：

| 能力 | 输入／输出形状 | 不得上移或混入的责任 |
| --- | --- | --- |
| ConfigurationRepository | SettingsEdit → operation ticket／scoped commit；配置 observation | CAS、canonical merge 与配置版本不能由 View 猜测 |
| ModelCatalogRepository | account/model key、typed filter／cursor → 候选／详情；catalog observation | 不以显示名作 key，不在 GUI 另算资格或默认路由 |
| AccountUsageRepository | account ID＋usageQueryRevision → 去重 query／额度 observation | old query 不清新 pending；失败不因 rebuild 自动循环 |
| WorkspaceRepository／Session coordinator | canonical 目录查询／变更；WorkspaceTarget → activation outcome | 分开目录事实与当前目标；不再保留双 selection 镜像 |
| Conversation／Session services | Thread ID → scoped state／content observations；页／详情 query | attempt、订阅基线、取消／join 与预算归此层 |
| Draft／Attachment services | typed edit／admission／freeze／submit／abandon → stamp／operation | 不用 View dispose 清理冻结 ownership，不接受目录／URL 冒充本地文件 |
| ModeRepository | 定义／校验／预演／保存／删除的 typed 请求与结果 | 不维护第二份页面 JSON／graph 编辑状态 |
| Resources／Updates | 明确资源 ID／意图 → observation／operation | 不通过通用 String command、反射或 raw map 分派 |

所有方法的完整参数类型、nullable、允许输入、错误及取消语义必须在派发契约中逐项列出，不以此表代替真实签名。

### 5.3 ViewModel 与 Widget 形式

- `@riverpod class …ViewModel extends _$…ViewModel`；异步页面的 `build` 返回 `FutureOr<…ViewState>`，family 只用稳定、值相等的身份 key，不用 Widget、Controller 或大型 mutable 对象作 key。
- build 可以登记只读观察／必要读取，不能提交写操作、自动重放命令或依靠 Widget 调 init 才正确。
- 主页面、编辑会话与交互动作方法名称表达领域意图；view callback 连接这些方法，不穿透 `vm.client.store.transport`。
- Freezed ViewState 的业务字段引用 typed 领域值；操作呈现按 operation／target 区分，不能为一次保存把整页状态替换成 AsyncLoading。
- Smart 用 `ref.watch/select` 观察，用 `ref.listen` 或动作的 typed 结果处理导航／提示；ViewModel 不拿 BuildContext。
- Dumb 构造函数只接受 `ViewState`／明确数据、UI-only Controller 和 typed callbacks。Timeline binding 不含 Repository 或业务 handle，不将第二份完整 Message 列表放进 ViewState。

固定主 VM 责任包括 Workspace、Accounts／AccountEditor、Usage、ModeEditor、Composer、Interaction、Timeline、Status、ResourceManagement、Update。可以按真实独立状态进一步拆分，但必须由主代理先更新接口表，执行者不能自行拆出新层。

## 6. FRB 实时、分割投送与流控合同

### 6.1 投送分类

| 数据 | 方式 |
| --- | --- |
| Turn／Interaction／可操作故障 | 有序基线＋typed 变化，不静默丢弃关键事实 |
| throughput／实时 token | 独立小型 latest-value 样本，只带必要身份／样本序号／计数 |
| context／累计 usage／费用 | 独立投影，按事实变化推送，unknown 与 zero 分开 |
| route／workflow／plan／todo／活动／服务 | 按变化原因分域，plan 正文只在其版本变化时交付 |
| Timeline 正文、字段变化、saved／terminal | FRB typed push；删除 Dart `next()` 泵，复用 Rust Session 的事件等待能力 |
| 目录／账号／catalog／额度／配置集合 | scoped baseline／typed upsert-remove 或有界窗口，摘要与历史分离 |
| 完整输出／原图／长文本／非首屏历史 | 按身份、revision、cursor 分页／分块 query，推送引用或版本变化 |

小而低频的对象可整体替换，不机械给每个标量开流，不发明万能 JSON patch。

### 6.2 版本、一致性与消费确认

- resource key、owner epoch、feed revision、订阅身份明确；可靠增量的 base→next 只能连接同一域。
- 先登记 receiver 再取基线，按同域水位去重覆盖帧；分页快照不得假装完整集合。
- latest 样本可以跳过中间样本，但不能将有损样本序号当可靠控制 revision。
- 不能证明连续时显式 ResyncRequired／Lagged，只重建受影响域的新基线，保留 last-known 与错误，不重放业务操作。
- delivery sequence 在单个 feed 内从首个 data frame 开始单调递增；基线也消耗额度。`ack_through` 确认已连续处理的前缀，重复旧确认幂等，确认尚未发送的序号明确拒绝。
- ACK 绑定具体 opaque feed，不释放另一个订阅／attempt 的额度；转换或归并失败时关闭／重同步，不先 ACK 再假装处理成功。
- 初始实现采用小型固定在途窗口，**每 feed 最多 2 个未确认 data frame**；latest 待发送值只保留 1 份。可靠待发送队列同时受帧数和领域载荷字节预算约束，具体每类预算由主代理在 feed 合同中冻结。
- 大载荷依现有 Timeline 页／详情预算及新增分域读取合同交付，不以 silent truncate、无界队列或后台自动全文加载规避预算。
- 在途上限是消息／载荷边界，不冒充整个进程 RSS 或精确 FRB wire bytes。

### 6.3 状态机与关闭

统一生命周期：`opening → active → closing → closed`；未确认释放保留 unresolved owner，不把超时等同 closed。

- 每 feed 只允许一次 stream 消费者；重复打开明确报错。
- 控制取消优先于等额度，业务终态仍按有序数据处理；传输 Failure／Closed 至多一次，不能因消费者停止 ACK 而阻塞 join。
- `request_close` 同步封闭准入并发取消；`close` 等待 producer、sink 和所有登记调用真实结束，再释放句柄。
- Stream.cancel 后 adapter 仍负责显式 request-close／join／dispose；GC 仅兜底。
- page／detail 不等待挂起的事件接收锁；关闭后迟到成功按原 attempt 收束，不进入新 UI。
- 错误转换进入 typed Failure，不能仅日志 warn 后跳过。取消、协议缺口、资源不足和内部错误不折叠成正常 EOF。

使用官方 StreamSink、Tokio bounded channel／Semaphore／CancellationToken 与现有真实完成登记；消费额度仅是必要 FRB 边界适配，不扩展为重放日志、通用 RPC 或新消息框架。codec 沿用生成器支持的路线，不凭直觉切换或宣称 zero-copy。

## 7. Contract-First 子代理实施规则（硬门槛）

### 7.1 主代理必须先交付的设计包

每项实施前，主代理形成有版本和内容身份的契约包，并核对以下项目全部完整：

1. **完整最新批准计划**及本任务对应验收项，不仅发标题或链接。
2. **现场基线**：实际 commit；已有未提交前置改动的文件内容／diff 身份；依赖任务与已批准调整。
3. **架构位置**：唯一职责、调用／数据流、允许依赖、禁止依赖、所用设计模式及不使用的替代模式。
4. **精确接口清单**：Rust／FRB／Dart 类型、全部字段与变体、数值单位／宽度、null／unknown／empty 语义、方法签名、provider 名／family key、Widget 构造参数和 callback 结果。
5. **状态与所有权**：每份状态唯一 writer、谁创建／借用／取消／join／释放，生命周期及跨路由保留规则。
6. **时序／并发合同**：首次 await 前冻结什么；代次检查；去重／CAS／retry；同步观察登记；背压、窗口、预算及关闭竞争。
7. **错误矩阵**：输入拒绝、冲突、未知结果、观察失败、lag、取消、EOF、超限的 typed 结果及调用方动作；禁止的 fallback。
8. **生产者—消费者迁移表**：本任务提供／消费哪些接口；哪些调用方必须迁移；哪些旧类型／路径／方法必须删除。
9. **路径与 Git 权限**：最窄写目录和明确文件所有权、禁区、共享／生成文件 owner；不 stage/commit、不改其他任务。
10. **依赖有序步骤与关键伪代码**：正常路径、失败／取消路径和回滚点，复杂流或编辑状态机不能只写“按最佳实践实现”。
11. **验收矩阵**：每项要求对应已有／新增用例、定向命令、预期结果、已有证据及留给 root 的最终验收。
12. **变更边界**：必须遵守的合同、仅供参考的局部建议、尚待核实但不影响接口的假设分别标注。

**门槛：字段、方法、状态归属、错误语义或跨任务依赖有关键空白时，任务不进入实施。**主代理先调查和定稿，必要时只派只读探索，不以执行者“自行合理发挥”补设计。设计包与代码不一致时先修正契约或实现，不把矛盾留给集成阶段。

架构文档保存稳定职责／协议／接口形状；工程迁移清单保存具体路径、任务归属、基线及验收映射，避免把实现流水塞进设计文档或维护两份相互冲突的权威事实。

### 7.2 执行者可以与不可以决定的事项

可以：在合同内选择私有函数、局部控制流、清晰的内部命名、注释和不改变语义的数据结构；发现更好实现可说明理由。

不可以自行决定：公共／共享接口、层依赖、状态 owner、业务默认值、允许输入、转换规则、错误分类、重试／并发／流控策略、预算、provider 保活策略、生成边界、新依赖或迁移范围。不得为了让测试通过放宽业务输入、吞错误、保留兼容别名或新增平行缓存。

遇到上述问题，停止受影响范围，报告**证据、冲突、影响消费者、建议及需要 root 的决定**；不先写临时 shim。其他互斥任务可继续。

### 7.3 设计变更和返工流程

- 主代理判定是局部实现问题、契约内调整，还是目标／范围／关键决策变化。
- 契约内问题由原执行者修复；跨接口调整先由主代理更新设计包并标明新版本、替代旧要求和受影响消费者。
- 真正改变已批准目标／范围／关键决策时，按 Plan 流程确认；普通实现修正不反复请求同一授权。
- 用完整续跑消息通知原执行者，不只发“修一下”；旧输入或旧报告不能证明新版本已完成。
- 不同执行者不得同时编辑共享协议／生成输入／同一接口的两端，除非已有明确互斥所有权与冻结合同。

### 7.4 独立审查与接受条件

每份执行完成报告到达后立即安排 fresh-context reviewer，提供完整批准计划、契约包版本、执行者／基线／实际 diff 身份、验证证据及本轮范围。

审查不只看编译：逐项核对需求—接口—实现—测试矩阵、层依赖、失败／取消路径、旧实现删除、字段与业务语义，明确批准或阻塞。范围冻结后才能审查；返工交原执行者，再创建新 reviewer 复审。

局部静态批准不等于 root 的跨层验收。交付报告必须有实际命令与结果、文件／内容身份、偏差、未覆盖项和未结束任务；受理回执或“本轮停止”不当作任务完成。

## 8. 实施 DAG、所有权与生成协调

### P0：root 设计／基线／接口冻结

审批后 root 先更新 design/02、07、18、19、24、25、26 的受影响契约、设计索引及 AGENTS 中过时的 Client／provider／生成／测试约定。建立完整领域—feed—Repository—VM—Screen 矩阵、生命周期图、接口签名与旧入口删除清单。

完成每项契约包的前置核对再派任务，补齐各 feed 预算、各 VM family／生命周期及所有现有动作的准确签名，不留给执行者决定。建立统一代码指标及相同合成场景基线。

### T1：Rust／FRB 实时契约

一个执行者拥有共享 protocol／runtime／bridge 的新 feed、分域投影、Timeline push、消费额度与取消／join，以及必要 server 映射；不与其他协议修改并行。只做相关 Rust 格式、静态检查和定向契约验证。root 管理跨语言生成。

现场执行切片：先 T1.A Timeline 真正垂直接缝，再 T1.B Thread／产品 feeds；各自完整冻结合同、局部验证／独立审查，不将未使用 primitive 当作全部 T1 完成，不并行修改共享范围。T2 仍依赖完整 T1。

### T2：Dart Repository／资源层／adapter

依赖 T1 的接口固定。一个明确 owner 完成 Client 解体、分域 Repository／session services、Freezed 领域模型、typed ports、FRB adapter、操作呈现分离、bootstrap／demo／fakes 和测试调用方迁移。共享纯选择、跨 feature 能力与公共导出在此冻结，不为旧 Client 包转发壳。

root 负责共享 UI 及 app 注入合同，先提供确认对话框、附件元信息、状态展示等跨任务组件的确定 props／回调，再释放使用它们的任务。

### T3／T4：Settings 与 Conversation

依赖 T2 和公共 UI／入口合同就绪后，按最窄互斥 feature 目录并行：

- Settings：账号／额度／模型、Agents、模式编辑、SSH、资源、一般设置和统计的 VM／Freezed State／Smart-Dumb 迁移。
- Conversation：composer、交互、timeline、status、todo，移除手写巨型 part，共用新分域 push；展示 coordinator 与唯一 Message 集合保持明确所有权。

跨 feature 测试、共享接口、app 装配归 root；执行者不互改目录。保留 feature 公共入口的冻结构造，不到集成时才协商参数。

### T5：Workspace／应用装配／清除旧架构

依赖新功能入口稳定，完成 shell／sidebar／workspace／启动／恢复／更新、导航与退出协调。删除旧全局聚合模型、多余 provider、旧 facade／ports／路径／别名及第二选择／附件镜像，统一 diagnostics 和共享 UI。

### 生成与版本管理

- 优先使用本地 directory executor，成果直接在当前 workspace，不制造虚假合入。
- 各执行者仅写自己的手写范围、不 stage/commit、不做全量门禁。
- root 独占 manifest／lockfile 变更协调、跨层接口和全局生成；统一 xtask 入口生成纯 Dart 模型、FRB、Riverpod、Freezed 与 l10n。
- 全局生成前协调输入稳定窗口；有未完成且会破坏生成的输入时不运行，不让执行者各跑全局生成相互覆盖。
- 生成 diff 与手写 diff 分开审查，孤儿输出由统一入口清理，不手改生成文件。
- 各任务审查／修复独立推进，依赖成立即释放后续任务，不为填满容量拆分真实依赖。

## 9. 验证与完成标准

### 9.1 定向自动化与架构门禁

复用现有公开行为测试，迁移至新公共入口，不锁定旧私有实现。必要覆盖：

- 同步观察登记／基线竞争、同域缺口、旧 epoch／attempt、实体删除与 A→B→A。
- 速度独立投送且不通知 plan／workflow／catalog；正文 append／replace／remove、saved／terminal 正确。
- 慢消费者在途上限、重复／越界 ACK、满窗口取消、晚到 open、重复 close、转换失败与真实 join。
- dirty draft 不被 canonical 更新覆盖、首次 await 前冻结、旧 finally 不改新目标、UnknownOutcome 不自动重放。
- 两实例隔离、Settings 往返保留会话与草稿，无关变化不触发消费者重建。
- 新 AST 依赖规则及反例 fixture：Dumb／State、VM、数据包与 FRB adapter 的边界真正可拒绝。

只在真实契约 owner 边界增加必要确定性测试，按本次设计同步测试约定；不为测试扩公共 API、不以 fake 代替 native FFI、不增加无关测试专项，也不削弱断言／静默跳过制造绿色。

### 9.2 root 全量与集成门禁

全部任务局部审查通过后，root 亲自对照完整计划、设计包、源码 diff、消费者与删除清单，执行：

- `cargo fmt --all --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test -p pl-model`
- `cargo test -p pl-core --features sqlite`
- `cargo test -p pl-studio-runtime`
- `cargo xtask verify-client`
- `cargo xtask verify-gui`
- CI 的 standalone core 两种 feature profile 检查，以及相关 bridge／server 编译与新增必要契约入口
- `git diff --check`

使用 `cargo xtask generate-gui`／canonical 检查的统一生成边界，不直接调用单个生成器；两包依赖快照审查后锁定。有效证据可复用，不机械重复全量验证。

审批时基线记录：Flutter analyze 零问题；此前 verify-client 总命令在 adapter 阶段因总超时终止，不能当完整门禁通过。现场已补充完成 `23dc4e87` 的完整 verify-client（adapter 194 tests）与 analyze；`f6cb327c` 未改变 Dart 输入，可复用为基线证据，不证明改动后的最终版本。

新增 bridge feed library 契约入口由 root 纳入本地／CI；其测试不能替代下述实际 StreamSink 与 Dart port 验收。

### 9.3 原生 GUI／传输验收

Linux SSH 使用隔离 Xvfb、`cargo xtask manual-gui`、Flutter Driver 与真实 bridge／本地模拟供应商，检查：

- 设置主要子域的保存、失败／重试、切 tab／返回、模型／模式选择与编辑 guard。
- 发送／停止／交互、指标／上下文独立更新、计划／工作流变化。
- Timeline 首屏、流式、历史分页、回实时、长正文／附件／问答和计划回执。
- 慢消费者、分域重同步、切 Thread、退出及订阅／进程回收。
- 正常／窄窗口截图、快照、日志与交互边界。

实际打开截图判断，不把 demo、成功启动、fake 或 exit 0 当完整原生验收。Linux、Windows CI／实测及真实供应商覆盖分别报告，不互相外推。

## 10. 工程质量前后证据与 PR

从同一基线与最终版本以相同规则复算，提交工程报告与复算命令：

1. 手写生产 Dart／Rust、测试、生成代码分开统计文件数、LOC／非空行、增删净值及百分比，生成量增加不冒充维护成本减少。
2. 最大手写文件／library、>500 行文件数、手写 part 数、平铺目录密度与旧 API／无消费者清理。
3. Thread 树选择、附件格式／图标／元信息、确认／状态展示等重复实现份数与真实消费者；区分搬家、生成替代和去重。
4. Repository／AsyncNotifier／Freezed／Smart-Dumb 的实际覆盖、依赖违规、静态分析与契约／原生验证结果。
5. 相同合成工作负载的分域事件、无关字段投送、在途／队列高水位、重同步与关闭。业务载荷／诊断编码字节不冒充 FRB wire bytes；没有同条件测量不声称性能提升百分比。
6. 契约—实现—验收完成矩阵、真实缺口与迁移说明。

原始日志、VM 地址、原始截图及未脱敏快照存忽略目录，不提交敏感或一次性材料。

已核实 GitHub 登录 ZR233，remote 实际为 `ZR233/anywork`、默认 main、非 fork。用户最新要求提前建立 Draft PR、按阶段 commit/push；不降低局部审查与实际验证要求，不夹带未完成／未审实现。公开 Dart／FRB／共享事件协议破坏性变化使用真实 `!`／BREAKING CHANGE 和升级说明，不推 main、不合并、不发布。

最终交付：PR 链接、commit、质量对比表、实际本地／GUI 证据和 CI 终态。局部批准不等于整体完成，排队／运行中 CI 不算通过。最终验收成功后再关闭执行者并确认资源回收；受阻则保留未交付现场并明确剩余事项。

本计划完整替代前版，尤其将“主代理先确定接口再派发”提升为实施准入、变更控制和独立审查的共同硬门槛。
