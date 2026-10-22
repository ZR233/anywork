# T1.B Thread 五域实施合同草案（未达到编码准入）

本文件记录 root 正在冻结的实际接口与时序决定，不是让执行者自行完成的模板。
完整批准计划为 `implementation-plan.md`（Plan revision 9／v4 approved）；现场事实完整清单见
`t1b-thread-field-map.md`。本草案不能单独派发实施；§6 中任一关键空白未补齐前不释放 T1.B。
已经冻结的架构见 `design/18-studio-state.md` §18.2.2；生成与 Git 继续由 root 独占。
v4补充的当前版本、读取scope和外部回应CAS决定以
[Thread wire合同](./v4-thread-wire-contract.md)为准，关闭与候选身份以
[生命周期合同](./v4-lifecycle-contract.md)为准；本旧草案的准入清单仍须随整包定稿收口。

## 1. 边界与版本域

Thread 唯一实时产品投影发布 execution、metrics、context、configuration、authoring 五域；
authoring 内 Plan／Workflow／Todo 各自变化只带自身字段。Timeline 正文继续独立，不进入五域。
core 自己的 `ThreadSnapshot` 是输入事实，不在公开产品聚合 DTO 删除范围内。

以下身份必须分别存在，不能用单一 revision 替代：

| 身份／水位 | 唯一含义 |
| --- | --- |
| runtime owner epoch | 当前运行时实例，和 bootstrap／已有命令 stamp 的作用域相同 |
| Thread observation incarnation | 同 ID Thread 当前这一次实际投影实例；不能使用 receiver 重连次数冒充 |
| facet revision | 该实例、该域的已发布事实变化；无关字段或时间戳变化不推进 |
| feed ID | 本次消费者句柄；错误、ACK、close 和查询 owner 绑定它 |
| delivery sequence | 同 feed 从1起的连续已发送 data 序号，含 baseline；仅释放传输额度 |
| core commit/effect sequence | 权威执行提交来源；不是上述 facet 或 delivery 水位 |
| model route revision | route extension 的业务 CAS；当前 catalog 可用性变化不提升它 |
| Settings／catalog／Mode revision | 三个来源自己的修订；Settings/catalog 相容读不包含 Mode 事务 |
| live observation sequence | 原 `(turn_id, attempt_id)` 内样本序号，可有损合并，不作可靠域连续性 |
| history/writer ticket | 原 incarnation 的可靠保存等待；不由 ACK、业务 Completed 或全局Ready替代 |

旧 Feed 不能自动跟随同 ID 新实例；新实例须先有新基线，旧结果只结算旧 owner。
Assembler 现有 `Arc<()> incarnation` 是进程内身份依据，不直接序列化其地址或把它说成公开 epoch。
跨域不承诺原子事务，调用者不能拿另一个域或独立 query 的水位修补缺口。

## 2. 来源观察接口（root 选定形状，已补提交点／closing边界）

这些是 runtime crate 内部能力，不是新 FRB 接口；不在模型 crate／GUI 建同构服务。
完整类型使用现有 `ConfigRuntimeSnapshot`、`ModelCatalogRuntimeSnapshot`、
`ThreadModeRegistrySnapshot`，保持原 canonical 配置与凭据 owner。

```rust
pub(crate) struct ConfigProjectionStamp {
    pub settings_revision: u64,
    pub model_catalog_revision: u64,
    pub closing: bool,
}

pub(crate) struct ConfigProjectionObservation {
    pub settings: ConfigRuntimeSnapshot,
    pub catalog: ModelCatalogRuntimeSnapshot,
    pub closing: bool,
    pub changes: tokio::sync::watch::Receiver<ConfigProjectionStamp>,
}

impl ConfigRuntime {
    pub(crate) fn observe_projection_sources(
        &self,
    ) -> ConfigRuntimeResult<ConfigProjectionObservation>;
}

impl ThreadModeManager {
    pub(crate) fn observe_registry(
        &self,
    ) -> (
        std::sync::Arc<ThreadModeRegistrySnapshot>,
        tokio::sync::watch::Receiver<u64>,
    );
}
```

`ConfigProjectionStamp` 是小型不可变值，只含上述两个 u64 和单向closing，不含配置内容、凭据、
账户列表、时间或秘密摘要；它允许 `Clone + Copy + PartialEq + Eq + Debug`，无需 serde/FRB。
`ConfigProjectionObservation` 是一次登记的返回值，不是另一套长期镜像或Freezed值；三个基线
字段和changes在同一canonical read guard内取得。closing不能只放在后续通知而让首次登记猜测。
观察方法不新增磁盘／网络／刷新／CAS／激活；错误仅沿现有配置读取的 typed 失败传播。
没有读到值不能默认为空配置。关闭准入由 runtime／Thread owner 封闭，观察 receiver 本身不获得
写权限或解除关闭状态，不因 receiver 被 drop 而关闭配置、Mode 或正在执行的 Turn。

### 2.1 必须证明的登记／提交时序

1. Config observer 在 `RuntimeState` read guard 内登记 receiver 并克隆两份相容 snapshot，
   同步返回；任何 writer 的 canonical 更新与来源 revision 对发布在同一 write guard 中完成。
2. Mode observer 同样在 registry read guard 内登记并克隆当前 Arc snapshot；Mode 的真实提交
   在 registry write guard 内安装快照并发布其 revision。不要经 Product 总线再克隆一份registry。
3. receiver 的登记初值被 Tokio 视为 seen；Thread 投影必须先消费同步返回的初值，再等待 changed。
   不持 `watch::Ref` 跨 await，也不能拿着它反向取得 Config／Mode 的锁。
4. 通知可能合并中间来源修订；worker 在唤醒后从 canonical owner 重读当前值，以来源 revision
   去重。只有投影字段实际改变才推进对应 facet revision。中间来源修订不作为可回放执行事件。
5. producer 使用 `send_replace` 保留无 receiver 时的最新水位；普通 `send` 失败后丢值的语义
   不适用于该来源。没有接收者不是错误，不新增重试队列或无界pending。
6. 声称“同锁发布”的检查覆盖下表全部提交点。初始stamp与canonical初值相同。关闭时同步
   发布closing，worker读到后解除这一路等待（避免关闭watch立即ready形成忙循环），仍继续
   Thread终态和存储收束；不把关闭来源当清空配置或强制结束整个worker。

组件依据：项目锁定 Tokio1.53.3，已按实际 Cargo package 源码核对 watch 的初值、subscribe、
borrow_and_update、send_replace 与借用生命周期。不是自研总线／codec，也不增加依赖。

### 2.2 全部提交点及关闭决定

| 真实路径 | 新来源发布的固定责任 |
| --- | --- |
| `ConfigRuntime::initialize` | 初始化Settings/catalog revision与closing=false；没有receiver也保留初始stamp |
| `save_user_agent_profile` | 与现有Settings snapshot替换同guard发布；在任何Profile文件写之前核closing，关闭后拒绝，不把Profiles scan当Settings通知 |
| `update_with_effective`（含replace/update调用方） | desired/observations/settings/catalog原子安装后、drop state之前发布同一stamp；前置校验/磁盘保存错误不伪造新stamp |
| `reload_from_disk` | 在读盘/扫描等新工作前核closing；最终Settings/catalog一起安装的write guard内发布，不靠后续产品投影成功与否 |
| `publish_catalog_locked` | 所有probe开始/查询构造失败/probe完成共用提交点在更新catalog后发布；effective config可能变而Settings revision不变，以catalog revision反映 |
| `close_model_catalogs` | 保留原取消probes；实际目录值改变才推进catalog revision/updated_at；无论是否有目录变化均一次发布closing=true，同一guard完成；重复关闭无新事实 |
| `ThreadModeManager::publish` | 安装registry/catalog immutable快照后、释放manager guard前发布新revision；不依赖调用者是否随后发Product event |

Config写入口的关闭拒绝沿已有配置owner关闭错误语义，不新增消息文本解析分支。当前
save_profile与reload缺少该guard，属于必须随来源生命周期补齐的实际缺口。目录close仅新来源
失效通知，不在关闭时额外排队执行模型更新；旧model-refresh/shutdown生命周期不被绕开。
Config/Mode之间没有嵌套锁。owner state锁→watch内部锁为固定方向；接收者不能反持watch借用。
Mode成功replace当前会提升来源revision，即使内容相同；本任务不改变该现有来源语义，但Thread
只在对应投影实际变化时提升facet revision。未知source的remove保持no-op。

### 2.3 Thread 注入与消费义务

`ObservationServices` 目前只有 recovery/store/events/performance/threads/writer；新来源能力
必须由 composition root 显式注入，不把 ProductEventBus 当成配置读取器。只读引用不能让
Thread worker 反向持有整个 `StudioRuntime` 并形成 task／runtime cycle。
新增字段固定为 `config:ConfigRuntime`、`modes:ThreadModeManager`；组合根位置为
`runtime/lifecycle/builder.rs` 构造 `ObservationServices` 的现有struct literal。
两者允许强clone：Config/Mode没有反持ThreadObservations的边，不能为形式增加Weak服务定位。
现有assembler callback继续使用原Weak<Shared>，不要改成强引用形成环。
每个实际已驻留worker在run初始化登记两来源，receiver由该worker唯一持有；终止时drop自身
观察并join worker。`LiveOwner`不再另存第二份Config/Mode、receiver或长期baseline缓存。
确切facet失败与finish/join接线仍须随§6完整owner合同定稿，不能将旧drain的Drop abort当成
新feed已真实join的证明。

来源变化只刷新同一驻留 Thread 实例的当前策略，不 ensure 冷 owner，不重新提交 deferred model
update，不改当前请求冻结绑定，不重开 Timeline。来源读取失败保留 last-known＋错误；关闭
要取消来源等待并真实 join。既有执行／交互可靠 effect 通道继续驱动其权威事实。

## 3. 五域字段归属与原子分组

| 域 | 必须保留的事实 | 不允许的投送 |
| --- | --- | --- |
| execution | active Turn、最近终态Turn、interaction生命周期／可操作请求引用、activity身份与摘要、typed storage故障／恢复资格及水位 | 不带正文副本；不将错误投影失败吞为absence；不把可靠决定覆盖成latest样本 |
| metrics | 原Turn/attempt、completion tokens/response millis成对事实（含首字等待）、原live sample sequence与状态 | 不夹context窗口／Plan／Workflow／catalog；不猜activeTurn补速度身份 |
| context | 累计usage/cache/各币种费用、最近请求冻结模型与窗口、当前策略（单独来源身份）、live context读数 | 不拿现在catalog回填请求当时revision/窗口；unknown不变0；不重复策略计算 |
| configuration | canonical route/CAS revision、当前可用性、Mode目录关联、实际active skills及已证资源来源 | 无来源的MCP/LSP/progress占位不能声称已测空集合；当前可用性不修改已冻结route |
| authoring | Todo、Plan metadata/文档身份、Workflow当前run、真实progress | Todo或速度变化不重发Plan正文；Mode变更不改正在运行的冻结graph |

Turn 保留 typed state：queued/running/completed/cancelled/failed/budgetLimited 的所有真实变体，
包括 cancellation cause、budget rollover及 provider typed失败，不能换成平行status/message。
但 TurnFailure.message、rollover.error 也是未限长文本；不能只给 Interaction 做大载荷设计而
忽略它们。activity.tools.active 与 wait/tool摘要同样需要完整预算核对，不能假称标量小对象。

## 4. 大载荷与读取的必须条件

- Plan 正文已有64KiB上限；可在文档身份变化／新域基线时有界交付，不为接口对称另造无价值分块。
- UserInput／approval／取消理由等字段没有统一cap。新的传输预算不是缩小合法业务输入范围的
  授权；不得静默截短并仍允许用户批准／提交，也不得以永久不可读替代迁移能力。
- 引用＋typed查询如果采用，必须冻结同owner／interaction revision，完整问题、选项、
  isOther/isSecret、purpose/continuation及terminal payload均不能丢；已知schema不能改成raw
  JSON兼容入口。只有原tool arguments本来是opaque JSON，可继续作为该字段的文本读取。
- 查询不能排在事件等待锁后；close封准入并取消／join全部登记查询。旧revision/旧owner返回
  明确Superseded／Cancelled，不拿新的同ID对象替换旧查询结果。
- 初始首屏动作准入、完整payload可达性、输入草稿保留／提交冻结、错误重试与unknown outcome
  都必须随读取协议一并冻结；不能把这些关键决定留给执行者。
- storage原始last_error、Turn失败文本与长动态列表也按真实来源处理，不能从日志构造业务事实。

## 5. 命令和非订阅消费者迁移边界

`ThreadSnapshot`／`ThreadRuntimeSnapshot` 除订阅外，还被history.read_thread、server HTTP/SSE／
OpenAPI、model-route reply、demo/fake和Dart adapter消费，完整删除表要覆盖这些真实入口。
没有公开旧聚合别名；core内部同名执行快照仍保留。

`ThreadModelRouteCommandReply` 迁移不得丢 receipt、canonical settings、mode_default_saved、
warning；query／reply不修复feed水位。冲突先canonical Settings再目标configuration新baseline，
不重开Timeline。请求原 `operation_id/expected_model_route_revision/expected_settings_revision/
account_id/model_id/effort` 六字段共同语义不变。
响应交互当前FRB没有UI expected_revision；新完整detail/read合同若需要该字段，必须在同一任务
同步服务端权威CAS与所有调用方，不能描述成“现有已支持”。UnknownOutcome不得自动重放。
`compact_thread` 仍没有native receipt，不伪造OperationId/durable证明。

## 6. 编码准入尚未完成的精确清单

- [x] Config／Mode全部来源writer、内部观察API、closing与最窄composition注入形状。
- [ ] Thread投影来源等待与facet错误/finish/join完整接线（不能只复用旧Drop abort结论）。
- [ ] Thread live/cold/retired observation owner、epoch生成和重建、所有停止/失败结果。
- [ ] 五域完整具体DTO与嵌套复用类型内容身份、baseline/change/base→next/null/unknown规则。
- [ ] 可靠／latest的帧数与源载荷字节预算、满窗取消、超限/lag/resync/关闭优先矩阵。
- [ ] Interaction及其它无界字段的typed完整读取、动作准入、查询生命周期与预算。
- [ ] runtime／protocol／FRB／server／Dart/receipt全部方法签名、删除矩阵与所有权路径。
- [ ] 每一项行为的局部公开回归、原生证据以及root最终集成门禁。

以上勾选完成且root核准后才改名为可派发合同；本草案不能作为未使用primitive或旧Client外壳
的实施授权，也不代表T1.B、T2或整个重构完成。
