# v4 Thread 分域 wire 合同（root 定稿中）

本文件补充 [共享合同](./v4-shared-contract.md) 和 [生命周期合同](./v4-lifecycle-contract.md)。
基线、原字段全册与 producer 证据见 [字段准入表](./t1b-thread-field-map.md)。本文件明确选择
版本、投送、大载荷路线及§9–11具体facet DTO/来源桥；尚未给出完整ports／HTTP映射的条目继续标为未完成，
不能用“实现时决定”填补，也不释放 R／D1／A 编码。

## 1. 权威与来源

`ThreadObservations` 是 Thread 产品投影的唯一 writer。源为 core snapshot/effect、原
HistoryChannel 的存储事实与最近终态，以及 Config／catalog 相容观察和 Mode 独立观察。
不新增独立业务 reducer、不从 Product 全局 sequence 推导五域水位，也不建立 GUI 正文缓存。

现有草案的 ConfigProjectionStamp／ConfigProjectionObservation／observe_projection_sources
及 Mode observe_registry 形状继续有效；所有 writer 同 canonical guard 发布来源 stamp。
运行时组合根只注入 ConfigRuntime 与 ThreadModeManager，不强持整个 StudioRuntime。

五域分别为 execution、metrics、context、configuration、authoring。源头按实际字段变化发布，
不是先构造旧 ThreadRuntimeSnapshot 再在 bridge/Dart select。metrics 变化不构造或携带
Plan、Workflow、Todo、完整 context 或 catalog。目录元数据继续只归目录 owner。

## 2. 身份与连续性（固定）

```text
ThreadFacet = Execution | Metrics | Context | Configuration | Authoring

ThreadFacetStamp {
  runtime_epoch: String,
  incarnation: u64,
  facet: ThreadFacet,
  revision: u64
}

ThreadFeedIdentity {
  feed_id: String,
  runtime_epoch: String,
  incarnation: u64,
  facet: ThreadFacet,
  mode: ThreadObservationMode
}
```

- runtime_epoch 复用当前 StudioRuntime owner_epoch；重启变化、clone不变。
- canonical Thread ID仍是String，不增加长度或格式准入。它在open参数和Session绑定中冻结，
  不反复内嵌到有界frame外壳；原业务thread_id在typed详情中完整可读。frame以全runtime唯一
  的incarnation绑定原Thread，消费方还须核对原open/Session对象，不能只按当前选择接收。
- feed_id固定由registry用`new_id("thread-feed")`生成；scope_id用`new_id("thread-read")`。
  两者及runtime_epoch仅来自本次进程生成器、不从文件/用户输入采用。按u128时间文本与u64
  序号的保守上界，三者均小于64个ASCII字节；这不是canonical Thread/Turn/模型ID的上限。
- incarnation 由唯一 observation registry 在新真实投影实例登记时分配进程内单调非零u64，
  与 assembler 的 Arc incarnation绑定；不是订阅次数、frame序号或指针地址。
- facet revision 从0开始，仅实际字段变化推进；同值重复、无关时间戳、其他facet变化不推进。
- 每个具体feed的 delivery_sequence 从1开始连续递增，baseline也占序号与ACK窗口；
  它只确认传输，不满足命令receipt、source revision、identity观察或durable。
- execution/authoring change有 `base_revision, revision`，必须接上该域上一水位；metrics/
  context/configuration的完整latest replace只要求同incarnation新revision，允许合并中间样本。
- owner重建发明确Closed(OwnerReplaced)，不将旧receiver偷偷改绑新owner。客户端只重建
  受影响facet的基线，不重放业务操作，也不无故关闭Timeline。

细化 stamp 不改变 route CAS、Settings/catalog/Mode revision 或 core commit/effect sequence；
这些来源水位作为对应数据字段分别保存，不能用 facade 全局revision代替。

## 3. 具体 feed 的统一外壳

每域定义独立 Rust enum／FRB enum／Dart Freezed union，不使用动态 JSON 或一个万能payload
discriminator。所有 frame 的共同语义为：

```text
<Facet>Frame =
  Data { delivery_sequence: u64, event: <Facet>Event }
  | ResyncRequired { identity: ThreadFeedIdentity, reason: ResyncReason }
  | Failure { identity: ThreadFeedIdentity, error: StudioFailure }
  | Closed { identity: ThreadFeedIdentity, reason: FeedClosedReason }

ResyncReason = SourceLagged | ReliableQueueFull | RevisionGap
FeedClosedReason = Requested | OwnerReplaced | RuntimeStopped

<ReliableFacet>Event =
  Baseline { identity: ThreadFeedIdentity, stamp: ThreadFacetStamp, value: <Facet>Baseline }
  | Change { stamp: ThreadFacetStamp, base_revision: u64, value: <Facet>Change }

<LatestFacet>Event =
  Baseline { identity: ThreadFeedIdentity, stamp: ThreadFacetStamp, value: <Facet>Value }
  | Replace { stamp: ThreadFacetStamp, value: <Facet>Value }
```

执行生命周期、交互决定、authoring里的真实状态改变属于可靠数据，不允许只留latest而悄然
吞掉终态。空闲/运行/失败信息均由数据事件表达，Failure只表示feed自身失败。
source投影失败不能被`.ok()`或`if let Ok`吞成None；只失败对应facet，保留其他域及last-known。

控制终态选择至多一个Failure或Closed；ResyncRequired是一种终结连续性的控制结果，发出后
停止Data并结束该feed的交付，不再紧接第二份Failure。它们不占data额度，不能被满窗口阻塞。
正常数据终态不走这条捷径，仍排在其原有序数据位置。EOF没有typed终态视为transport失败。

## 4. 流控与计量（固定）

| 域 | 未ACK Data | 待发策略 | 待发源JSON字节预算 | 单个Data源JSON预算 |
| --- | ---: | --- | ---: | ---: |
| execution | 2，含baseline | FIFO 64帧；不可latest覆盖 | 8 MiB | 256 KiB |
| authoring | 2，含baseline | FIFO 64帧；只含改变的Todo/Plan/Workflow成员 | 8 MiB | 256 KiB |
| metrics | 2，含baseline | latest 1份 | 64 KiB | 64 KiB |
| context | 2，含baseline | latest 1份 | 256 KiB | 256 KiB |
| configuration | 2，含baseline | latest 1份 | 256 KiB | 256 KiB |

预算按包含identity/stamp/tag的最终产品serde JSON字节计量，不把它当FRB wire或RSS。
文本和无界列表采用下一节typed读取，所以不能靠截断合法事实满足帧预算。不可缩的结构
超过单帧预算时明确Overloaded；任何原业务合法的大文本／集合都必须有可达读取路径，
不能把正常大payload一律变成永久Overloaded。该要求必须在具体DTO册中逐字段证明。

可靠FIFO溢出显式ResyncRequired，不覆盖队头／业务终态，不重发命令；重建只该facet。
不保留旧subscriber的512帧／16ms聚合泵后再叠另一队列。runtime来源使用现有Tokio
watch/broadcast/Notify与owner登记，bridge交付窗口仅有一个明确的排队责任；不得层层
新增mpsc来掩盖消费背压。

ACK0／旧ACK幂等；超过sent为Protocol。只允许同具体句柄连续处理前缀，转换／归并／必要
消费交接失败不ACK。query不排在等待下一事件或容量的锁后，满窗口仍能page/detail/close。
资源关闭遵循 [生命周期合同](./v4-lifecycle-contract.md) 的正常close与显式retryClose。

## 5. 大载荷：typed按需读取而非raw JSON封包

### 5.1 路线决定

Interaction问题、选项、终态回答／理由，TurnFailure/rollover文本，storage last_error，
动态工具列表、任意来源文本都不能借旧DTO没有cap而塞入有界feed。采用固定typed资源的
**不可变读取scope＋typed列表页＋UTF-8文本块**：

- scope绑定具体projection incarnation和事实revision；不改绑同ID新对象。
- 不新增持久化数据库、通用文档DOM、自研codec或历史镜像；读取既有canonical投影／history。
  仅拥有scope和原immutable源引用，不能复制整个历史或预序列化全部字段缓存。
- query只按身份读取，不激活模型/工具、不flush writer、不重算业务策略。
- 列表页和text chunk由Rust按实际schema产生；Dart消费typed DTO，不解析拼接的运行时JSON。
  唯一保留JSON文本的是原本就opaque的tool arguments字段，不用于解析业务discriminator。
- 开scope时要求的revision已过期或无法取得该版本为Superseded，scope关闭为Cancelled，
  事实确实不存在为NotFound。成功取得的scope固定不可变版本，普通source变化不打断该
  版本的page/text读取；不返回同名新对象，不把缺少来源当空值，不重发回应。

固定pin语义如下，取代早期草案“source每变化就让已开scope失效”的不完整表述：

1. scope创建在原projection的登记边界核对incarnation/revision并取得immutable typed源。
   已构造的typed源用Arc共享；冷checkpoint/terminal receipt只在原owner读取边界做必要
   解码/投影，再由scope拥有不可变源。不宣称当前Interaction已经全部零拷贝Arc-backed。
2. 字段索引只持typed discriminator/列表索引，与Arc源分开，禁止自引用或unsafe指针。
   最后实际scope/query完成后释放源，不保留永久全局body cache；256KiB是单次传输预算，
   不是完整源对象或RSS上界，不能隐去必要的源解码成本。
3. 普通revision变化后，既有scope继续读原版本；header始终标原source_revision。VM每次
   返回都核对原query/binding身份，不把旧结果写入新state。读完旧scope不赋予过期回应权限。
4. incarnation替换、scope/runtime关闭时同步封新query并取消；原owner等待已登记query
   真正退出后才释放其源/permit。相同Thread ID的新incarnation不能接管旧scope。
5. terminal冷读使用既有durable identity/receipt事实，不把checkpoint遗漏当NotFound；
   pending以resident actor为准。读取不创建model/tool/continuation，不推进保存水位。

### 5.2 读取预算与标量

scope同时受资源permit计费；每Thread最多8个详情scope，app/bridge合计最多64个在途详情调用。
每页默认32项、允许1..100；每次返回产品JSON最多256KiB。文本块默认64KiB，允许4B..256KiB，
游标为UTF-8字节边界；合法4字节字符必须能前进，拒绝非法offset，不静默clamp。
payload bytes单独标明，不把query封套字节和文本字段bytes混为一个计量。
`max_bytes`是文本UTF-8内容的上限而非必须返回量；还要按实际serde转义与封套开销缩短到
JSON预算可容纳的完整字符前缀，next_offset按实际原UTF-8字节推进。不得用字符数或未经
JSON转义的字节数证明完整响应在预算内。页limit同理是最大项数，可以因预算早停但必须前进。

所有现有无界String在新的详情DTO中使用以下固定typed表示；它是字段读取协议，不是通用
序列化值树。数字／bool／enum／nullable语义不变：

```text
ReadText = Inline { text: String }
         | Deferred { field_id: u64, utf8_bytes: u64 }
TextChunk { field_id: u64, offset: u64, text: String, next_offset: Option<u64> }

ReadScopeIdentity {
  scope_id: String,
  runtime_epoch: String,
  incarnation: u64,
  source_revision: u64
}
```

scope同样绑定原open目标和registry incarnation，不把可能任意长的已有Thread ID复制进每个
256KiB响应外壳。所有实际业务身份字段仍经ReadText完整返回；不删除或迁移改名旧目录条目。

Inline最多4096 UTF-8 bytes；更大文本使用Deferred，不截正文。field_id由scope内typed源
访问表分配；该表只记录“哪个已知字段＋列表索引”，不保存第二份字符串或动态JSON树。
读取调用必须携带原scope；不同scope的相同field_id不可混用。非文本字段不得借此转成字符串。
Option<String>映为Option<ReadText>，None与Inline("")严格不同。
4096是Inline上限，不是强制内联条件；同一header/元素内小文本累积或JSON转义使预算超限时，
继续将确定字段提升为Deferred，直至结构能容纳。已知固定标量结构本身不能被截断或漏字段。

列表分页返回 `{scope, offset:u64, total:u64, items:Vec<具体类型>, next_offset:Option<u64>}`。
页内元素自身的任意长文本均已变为ReadText，因此不能因一个合法长题干/选项永远无法前进。
嵌套列表由各自typed方法读取，不返回递归Value／Map；每个列表的字段、索引与方法在下节固定。

### 5.3 Interaction 完整读取面

具体`InteractionReadScope`仅允许以下方法（native snake_case，Dart camelCase）：

```text
header() -> InteractionReadHeader
questions(offset:u64, limit:u32) -> QuestionPage
options(question_index:u64, offset:u64, limit:u32) -> OptionPage
answer_entries(offset:u64, limit:u32) -> AnswerEntryPage
answer_values(entry_index:u64, offset:u64, limit:u32) -> AnswerValuePage
text(field_id:u64, offset:u64, max_bytes:u32) -> TextChunk
request_close() -> ()
close() -> FeedCloseReport
retry_close() -> FeedCloseReport
```

header全部字段：

| 字段 | 类型／完整语义 |
| --- | --- |
| scope | ReadScopeIdentity；原scope不能随页面refresh换身份 |
| interaction_id | ReadText，原身份完整可达 |
| thread_id / turn_id | ReadText，原业务归属，不用当前选择回填 |
| item_id / tool_id / agent_path | Option<ReadText>，原scope optional成员 |
| revision | u64，原Interaction revision，不是delivery序号 |
| purpose | General或PlanConfirmation{expected_revision:u64, operation_id:ReadText, argument_hash:ReadText, plan_hash:ReadText} |
| continuation | Option<Continuation>，Resolution或Question{question_id:ReadText}，另含presentation Visible/Hidden |
| created_at / updated_at | i64 Unix秒 |
| content | UserInput{question_count:u64}或ToolApproval{ name:ReadText, arguments:ReadText, working_directory:Option<ReadText>, parent_agent_id:Option<ReadText> } |
| state | Pending{operation_id:ReadText}；UserInputResolved{operation_id:ReadText,resolved_at:i64,answer_entry_count:u64}；ApprovalResolved{operation_id:ReadText,resolved_at:i64,decision:Approved/Denied,reason:Option<ReadText>}；Cancelled{operation_id:ReadText,cancelled_at:i64,reason:ReadText}；Expired{operation_id:ReadText,expired_at:i64} |

各页items的完整类型：

- Question：`index:u64, id:ReadText, header:ReadText, question:ReadText, is_other:bool,
  is_secret:bool, options_count:Option<u64>`。None与Some(0)保留，不把未加载options当None。
- Option：`index:u64, label:ReadText, description:ReadText`，顺序不变。
- AnswerEntry：`index:u64, question_id:ReadText, answer_count:u64`。源HashMap在scope创建时按
  原question ID稳定排序索引，仅索引引用，不复制answer全文；保留不匹配题目的历史key。
- AnswerValue：`index:u64, value:ReadText`，原数组顺序不变。

UserInput/ToolApproval不相容的页方法为InvalidArgument；超范围offset为InvalidArgument，
offset==total返回空页/next=None。scope/header/typed字段完整解码前不创建输入控件；isSecret
先于对应输入控件到达，不能先按普通输入显示再补遮蔽。

UI用明确分页/全文读取表达未加载内容；不能把截断预览当完整审批参数。原合法空questions
保留显式empty结构及现有自由回答能力：非空trim后的fallback文本以`questionId="answer"`
和单元素answers提交；不擅自收紧为“空题集不可回应”。空题集展示从typed header已知字段
产生，不靠解析raw JSON重新猜业务类型。完整审批参数及所需问题正文以有界文本块
可达；读取失败显式阻止对应提交，已输入答案留在原interaction/revision的草稿。
具体“已读完哪些块后可提交”的VM状态与动作准入仍需在U2合同一并定稿，不交执行者决定。

### 5.4 回应 CAS（固定接口方向）

外部respond必须新增 `expected_interaction_revision:u64`；保留 `operation_id`、
`interaction_id` 和现有typed resolution完整字段。Runtime在取得canonical当前Interaction后
按下列terminal／Pending顺序核对UI冻结revision，再将相同revision传入内部CAS；不能先对
所有状态一律要求current相等，也不能读取当前revision后替代UI条件。

驻留和durable路径采用同一顺序：

1. 已Resolved且typed resolution相同，先核expected是terminal revision或其可证前置revision
   （当前Pending→Resolved为一次递增，用checked_add核对）；满足时只读返回NoChange。
   不ensure执行owner、不重新授权或发continuation。
2. 不同terminal决定为Conflict；相同决定但revision不属上述关系为StaleRevision。
   Cancelled/Expired没有可匹配resolution，不能当相同决定成功。
3. 只有Pending才要求current.revision恰等于UI expected；相同expected逐层传入assembler
   permission/user-input/plan-confirmation及core CAS，不能内层又回填current。
4. 幂等成功不额外要求外部operation_id与持久记录相同。当前外部ID仅用于命令回执相关，
   内部保存的是`resolve:<wire_id>`或producer身份；不能伪称已有外部operation去重记录。
   保留非空ID准入，NoChange回执关联本次请求ID，不把原terminal归因于这个新ID。
5. 事实不能证明revision/决定关系时明确失败；冷durable与驻留采用同一校验，只有真实
   durable读取才标durable，不因幂等命中自动给内存事实标durable。

完整reply仍含typed interaction事实与receipt，receipt
观察目标须与execution同incarnation和原interaction身份匹配；ACK不是回应生效或durable。
UnknownOutcome不自动重发，旧完成只结算原草稿。FRB、server、Dart、demo/fake全部一起迁移。
此项是新增契约，不描述为旧API已有expectedRevision。

## 6. 五域字段的确定归属

本表固定完整业务字段去向，具体DTO及typed详情引用已在§9–11定义；未完成的公共ports和
跨transport迁移仍不允许executor自行决定。

| 域 | 必须交付的完整事实与原子分组 |
| --- | --- |
| execution | active Turn、最近terminal Turn全部typed state；Interaction生命周期及完整可读请求/决定；活动identity/kind/summary/工具数与完整列表；storage typed fault/generation/accepted-durable/execution/pressure/resume/canResume及原last_error详情 |
| metrics | 原Turn/attempt/observation_sequence/state与成对completion_tokens/response_millis；最近有效authoritative样本原Turn；取消/失败撤回live，不把分子分母跨代次拼接 |
| context | ThreadRuntimeUsage全部已存在计量/cache/cost/unknown字段；最近请求冻结model/窗口/阈值；当前策略单独来源stamp；live context只含原sample身份和latest_context_tokens，不搭metrics重发 |
| configuration | canonical route account/model/effort/revision、availability/reason；相容Settings/catalog水位与Mode水位；active skills真实来源；未实现MCP/LSP/health明确unsupported，不报健康空列表 |
| authoring | Todo完整字段与可证明call_id；Plan phase/revision/document identity及按文档身份交付markdown；Workflow当前run全部字段与Mode删除/名称提示；无来源progress明确unsupported |

Plan writer检查的是**trim后UTF-8正文<=64KiB**，存储仍保留原始两端空白；完整持久Plan状态
另有128KiB JSON上限。不得把前一个条件冒充原markdown字段硬64KiB。Plan文档按身份单独读，
直接typed返回原markdown/version/content_hash；其document是经过原状态校验的128KiB JSON
状态的子值，加有界scope封套可满足256KiB读取预算，不为对称再造raw JSON分片。
metadata变化但文档identity未变不重读正文。content_hash的`sha256:`+64小写hex形式有实际
writer及恢复校验证据，不因其它字段也叫hash而类推上限。
Todo/Workflow事件只带自己的改变，metrics不触发它们的投影。冻结workflow graph不能因Mode
registry同名新定义而换绑。Todo的call_id不可证明时用显式nullable来源，不伪造冷恢复稳定ID；
具体公共新字段类型见§9.6及§10。

上述外壳调整基于现有v2目录`CatalogStore::decode`仅校验非空/关联一致、不校验ID长度的
事实；不是提高预算或拒绝已有合法数据。新runtime生成ID与已持久化业务ID必须分开证明。

## 7. 尚待 root 补齐，不释放编码

- [x] execution/Turn/activity/storage DTO、typed列表页及failure/rollover字段；§9–11，仍需实现验证。
- [x] context当前策略与冻结绑定、独立样本身份/版本及schema预算依据；§9.3–9.4，非实测证明。
- [x] configuration/authoring DTO、Plan文档复用和Todo可证明身份；§9.5–10。
- [x] live/cold/retired、incarnation替换、读取与drain/join；§8、§11及生命周期合同。
- [ ] runtime/FRB/Dart所有open/read/command签名、receipt映射及server URL/SSE/OpenAPI删除替代。
- [ ] Interaction完整读取/回应准入已有编辑接缝§1；其它详情UI、全query交错及跨层验收矩阵仍待齐全。

以上都完成且纳入全范围所有权表之后，才能作为R/D1/A/U2的编码合同。

## 8. live／cold与投影结束的固定决定

### 8.1 打开与冷读

新增具名 `ThreadObservationMode={live,cold}`，不用多个布尔参数猜副作用。各域的open请求
统一携带 `threadId:String, mode:ThreadObservationMode`，返回该具体域opaque/feed连接；
不是一次订阅整个旧聚合再在末端分流。

- live模式保留原非retired订阅的准入语义：在原runtime lifecycle／assembler边界取得residency
  pin，必要时ensure已有Thread执行owner，所有并发open复用同一实际assembler incarnation。
  不发用户输入，不因打开五个域建立五个执行owner或重复deferred model update。
- `parent_thread_id.is_some() && role == "planner"` 的retired分支强制cold，不把所有child都
  当retired。Dart session按真实目录身份选择，Rust仍重复验证准入，不能信任UI传入的mode。
- cold模式与一次性各域read不创建model/tool/continuation，不ensure执行owner。需要初始化
  既有库schema时走现有存储迁移边界，明确这是schema准备，不冒充完全无文件副作用；
  不能写入新的用户会话事实或用默认checkpoint替代失败。
- cold投影从canonical checkpoint、可靠usage/persistence来源和有界最近terminal事实构建。
  没有checkpoint／来源读取失败明确失败，不发健康空域。cold feed交付基线后保留到取消，
  不以正常EOF驱动无限重连，不为此启动执行owner或额外的冷Thread配置监听worker。
  cold结果标明快照来源，不宣称它是持续更新的活动执行观察；驻留live实例的无token策略
  刷新义务不变。需要当前全局模型/Mode资料时观察其原领域，不从冷快照回填历史请求绑定。
- 一个Thread的读取投影由唯一observation registry管理。冷投影被真实live实例替换时分配
  新incarnation，旧feeds明确OwnerReplaced、旧query scopes Cancelled；不得改变旧句柄归属。
  新reader必须等新基线，保留旧last-known仅作显示，不用它证明新owner已ready。

每个facet单独ready/失败/重同步；configuration冲突恢复不重开Timeline或不相关域。关闭一个
feed只释放它的listener/residency借用，不关闭core Session、Turn、writer或仍被其他用途需要的
投影worker。关闭原Session服务才统一收束它拥有的连接和query，不能交给Widget dispose。

### 8.2 唯一投影worker与drain

Observation的task及其completion由registry entry唯一拥有；注册时绑定assembler的原Arc
incarnation并分配公开u64 incarnation。查询／close先取原entry的强引用，之后不按同ID重新
查找替换对象。现有Drop abort仅可作放弃/进程收尾防护，不是正常drain完成证明。

Assembler关闭顺序保持 `prepare_close → core close → observation drain → published resources`。
drain必须实际执行：

1. 在原entry冻结应观察的core commit，并等待applied/initialized；失败明确返回，不假报完成。
2. 等待**原HistoryChannel的handoff ticket** durable，再flush调用时冻结的writer admitted
   ticket；不能用新incarnation checkpoint绝对序号等旧channel，不等待之后无限新增工作。
3. canonical close事实已被投影／可靠交接后，封闭该entry的新feed/query准入，通知现有feed
   与scope关闭，停止Config/Mode来源等待，向worker发停止请求并await其真实completion。
4. worker不能在自身任务中await自己的drain/close；不得持registry/Config/Mode/watch借用跨
   await，也不能先remove entry靠Drop abort再称join完成。
5. 仅全部真实收束成功且registry token仍相同才移除entry。失败保留entry/typed issues和未
   保存事实；不可恢复worker失败不得重启producer重放effect假装清理。其他独立资源仍并行
   收束，应用最终报告非Clean，不能以全局清空map释放未确认资源。

Runtime总退出仍先封准入、并行close_all／准备排空；各Thread drain与全局finish必须共享原
entry的完成事实，避免重复消耗JoinHandle。全部成功后才统一finish观察与持久化flush；
失败保留报告并遵循首次退出期限，不通过重新开始deadline掩盖等待环。

## 9. 有界五域 Data 的具体字段

本节取代§6“具体DTO待细化”的部分。所有非时间计数为u64，明确写u32/u16者除外；
Option与0分别保留。Rust字段snake_case，Dart camelCase；表中的类型/变体必须全部生成
为typed DTO，不用String表示已知enum，不从Debug文本构造协议。

### 9.1 引用与不变量

有界Data不内嵌无界业务String/集合。以下是**具体类型**，不是一个kind+JSON的万能ref：
`TurnReadRef`、`InteractionReadRef`、`InteractionIndexRef`、`ActivityReadRef`、`StorageReadRef`、
`ContextReadRef`、`ConfigurationReadRef`、`TodoReadRef`、`WorkflowReadRef`。
它们各自完整字段为`entry:u64, revision:u64`。entry是本投影incarnation内的typed读取索引，
非canonical业务ID，不能当Thread/Turn/interaction ID传给命令；实际String身份在详情中原样返回。

索引只指向原owner已拥有的typed事实，不能保存第二份全文或可写领域值。相同实体持续更新
保持entry、推进事实revision；删除后同业务ID重建必须分配新entry。不同ref类型不可混用。
打开scope同时核原Thread绑定、runtime_epoch、incarnation、entry和revision；若原版本已不可
取得返回Superseded，而不是改读最新。同一scope成功打开后保持§5的immutable pin语义。
entry分配不得回绕复用；达到计数上界明确Overloaded，不假装另一旧对象。

`MetricsIdentityRef {entry:u64}`另作具体类型；它指向不可变的Turn/attempt字符串身份，
**不随每个token样本更新revision**。故读取身份不会因高频计量不停Superseded。
它不携带计量值，也不形成第二份计量owner；实际计量始终由metrics Data完整replace。

只有已交付Data中出现的读取索引可供该Session借用；scope/引用的开放不扩大原资源可见性。
旧引用的过期不授权重新激活执行者、重发命令或从当前选择找同名实体。

### 9.2 execution

```text
TurnBrief {
  reference:TurnReadRef, revision:u64, updated_at:i64, state:TurnBriefState
}
TurnBriefState =
  Queued {queued_at:i64}
  | Running {started_at:i64, phase:TurnPhase}
  | Completed {started_at:Option<i64>,completed_at:i64,completion:TurnCompletion}
  | Cancelled {started_at:Option<i64>,requested_at:i64,completed_at:i64,
               cause:TurnCancellationKind}
  | Failed {started_at:Option<i64>,completed_at:i64,category:TurnFailureCategory,
            provider_kind:Option<ProviderFailureKind>,http_status:Option<u16>,retry:RetryDisposition}
  | BudgetLimited {started_at:Option<i64>,completed_at:i64,limit:BudgetLimitSnapshot,
                   rollover:TurnRolloverKind}
TurnPhase = Preparing|Thinking|Responding|Planning|RunningTool|Persisting
TurnCompletion = Normal|InteractionRequested
TurnCancellationKind = Unspecified|UserRequested|RuntimeShutdown|AgentClosed|Interrupted|Recovery|Coalesced
TurnFailureCategory = Provider|ProviderCapacity|Tool|Validation|Protocol|Internal
ProviderFailureKind = Authentication|Authorization|Capacity|Configuration|Transport|Protocol|Unknown
RetryDisposition = Retryable{retry_after_ms:Option<u64>} | Permanent
BudgetLimitSnapshot {kind:BudgetLimitKind,usage:BudgetUsage}
BudgetLimitKind = ModelStep|ToolCall|Wait|WallClock|AgentCount|AgentDepth|Finalization
BudgetUsage {model_steps:u32,tool_calls:u32,wait_calls:u32,elapsed_ms:u64}
TurnRolloverKind = NotAttempted|Succeeded|Failed

InteractionBrief {
  reference:InteractionReadRef, revision:u64, kind:UserInput|ToolApproval,
  status:Pending|Resolved|Cancelled|Expired, created_at:i64, updated_at:i64
}
InteractionIndexHeader {reference:InteractionIndexRef,total:u64,pending:u64}
InteractionDelta {
  base_index_revision:u64,index:InteractionIndexHeader,
  upserted:Vec<InteractionBrief>, removed_entries:Vec<u64>,terminal_facts:Vec<InteractionBrief>
}

ActivityBrief {
  reference:ActivityReadRef, revision:u64, kind:ThreadActivityKind,
  tool_count:u32, background_count:u32, active_count:u64, has_latest_started:bool
}
ThreadActivityKind = Preparing|WaitingApi|Thinking|Responding|Planning|RunningTool|
  AwaitingApproval|AwaitingInput|Stopping

StorageBrief {
  reference:StorageReadRef, fault:Option<HistoryFault>, fault_generation:u64,
  accepted_sequence:Option<u64>,durable_sequence:Option<u64>,
  execution:ThreadStorageExecution,pressure_paused:bool,resume_required:bool,
  can_resume:bool,has_last_error:bool
}
HistoryFault = QueueFull|WriteFailed|WriterUnavailable|NoProgress|CheckpointFailed|BlobFailed
ThreadStorageExecution = Running|Pausing|Paused
ThreadStatus = Idle|Queued|Running|WaitingTool|WaitingInteraction|Cancelling|Closing|Closed|Faulted

ExecutionBaseline {
  status:ThreadStatus,
  active_turn:Option<TurnBrief>,recent_terminal_turn:Option<TurnBrief>,
  interactions:InteractionIndexHeader,activity:Option<ActivityBrief>,storage:Option<StorageBrief>
}
ExecutionChange {
  status:Option<ThreadStatus>,
  turns:Option<TurnsReplacement>, interactions:Option<InteractionDelta>,
  activity:ActivityReplacement,storage:StorageReplacement
}
TurnsReplacement {active_turn:Option<TurnBrief>,recent_terminal_turn:Option<TurnBrief>}
ActivityReplacement = Unchanged | Replace{value:Option<ActivityBrief>}
StorageReplacement = Unchanged | Replace{value:Option<StorageBrief>}
```

一个core提交引起的Turn/interaction/storage相容变化在同一ExecutionChange交付，不将其拆为
可见半事务。InteractionDelta最多100个upsert+remove+terminal索引；超出不截断或丢终态，发
ResyncRequired并让新基线的完整typed index页可达。该限制是单Data编码预算，不缩小合法
interaction数。基线的index是当前canonical投影所含Interaction集合，不宣称全历史；旧终态
完整内容仍从原durable identity/receipt读。临时活动详情过期明确Superseded。

status是该执行owner的真实准入状态；目录中的同名status是侧栏目录投影，不能拿较迟的目录
刷新决定发送、停止、切模型或closing准入。标题/项目/路径/归档等目录元数据仍不进本域。

执行错误的code/message、Coalesced目标、rollover错误、activity全部文本/工具/Wait和storage
last_error均由具体scope读取；不是删除它们，也不把摘要当原文。`has_*`只表达已知字段存在，
不表达详情已经加载。活动summary现有512字符预览规则继续保留，但不能外推ID/name/list上限。

### 9.3 metrics

```text
MetricsValue {
  live:Option<LiveTurnMetrics>, authoritative:Option<AuthoritativeTurnMetrics>
}
LiveTurnMetrics {
  identity:MetricsIdentityRef, completion_tokens:Option<u64>,response_millis:Option<u64>,
  state:Live|Authoritative, observation_sequence:u64
}
AuthoritativeTurnMetrics {
  identity:MetricsIdentityRef,completion_tokens:u64,response_millis:u64
}
```

authoritative identity的attempt可空，因为累计Turn值不冒充最后单次请求样本。identity页返回
原turn_id和真实可选attempt_id。live的identity必须有真实attempt，不合成空串。分子/分母来自
相同来源快照，失败/停止撤回原live而非拼接旧值。latest_context_tokens不出现在metrics，
其own sample身份与数值在context；互不因无关更新推进revision。

LiveContext不携带metrics的observation_sequence；只在identity/latest_context_tokens/state
实际改变时发布。来源序号可由唯一projection私有核对以拒绝乱序源，wire连续性由context自身
facet revision保障。详情ref只在其实际承载字段变化时更新，不因另一个域的计数变化失效。

### 9.4 context

```text
ContextValue {
  usage:Option<ContextUsage>,live_context:Option<LiveContext>,
  current_policy:Option<CurrentContextPolicy>, details:ContextReadRef
}
ContextUsage {
  has_incomplete_usage:bool,context_window:Option<u64>,max_context_window:Option<u64>,
  auto_compact_limit:Option<u64>,latest_context_tokens:u64,prompt_tokens:u64,
  completion_tokens:u64,cached_prompt_tokens:u64,cache_write_tokens:u64,reasoning_tokens:u64,
  inference_count:u64,total_tokens:u64,cache_usage:CacheUsageSummary,
  estimated_cost_count:u64,estimated_cache_saving_count:u64,has_unpriced_usage:bool,
  prompt_generation:Option<u64>,prefix_changed_reason:Option<PromptPrefixChangedReason>,
  updated_at:i64
}
CacheUsageSummary {input_tokens:u64,cache_read_tokens:u64,hit_rate:Option<f64>,has_incomplete_usage:bool}
LiveContext {identity:MetricsIdentityRef,latest_context_tokens:Option<u64>,
             state:Live|Authoritative}
CurrentContextPolicy {
  sources:ConfigProjectionStamp,mode_revision:u64,route_revision:u64,
  context_window:Option<u64>,max_context_window:Option<u64>,input_token_limit:Option<u64>,
  auto_compact_limit:Option<u64>,unavailable:Option<ModelContextUnavailable>,
  adjustment:Option<ModelContextAdjustment>
}
```

ConfigProjectionStamp保持settings_revision/model_catalog_revision/closing；ModelContextUnavailable
与ModelContextAdjustment使用模型层的原typed enum/全部字段（`pl-protocol/src/account_catalog.rs`），
前者为WindowUnknown|InvalidParameters|InputBudgetExhausted，后者为SafetyLimit，均无载荷；
不在Dart重算。`PromptPrefixChangedReason`完整变体为Initial、PromptScopeChanged、AccountChanged、
ModelChanged、BaseInstructionsChanged、GlobalInstructionsChanged、ModeRoleChanged、SkillCatalogChanged、
WorkspaceInstructionsChanged、RequestPropertiesChanged、FixedPrefixChanged、ToolSchemaChanged、
ContextCompacted、ContextAppended、ContextRecovered。当前无来源的三个prompt派生字段保留None；
prompt_cache_policy原可空字符串在Context header，而非伪造一个策略enum。

最近请求model_id在Context header完整保留，不由current_policy回填；当前account/model/effort
和模型名称等全部来自同一Configuration版本的typed header。成本和节省是两个独立有序
typed列表，每项currency:ReadText/amount:f64，不换汇、不把无计价当0、不丢未知币种。

### 9.5 configuration

```text
ConfigurationValue {
  details:ConfigurationReadRef,sources:ConfigProjectionStamp,mode_revision:u64,
  model_route:Option<ModelRouteBrief>,active_skill_count:u64,
  active_mcp:ThreadCapabilitySupport,active_lsp:ThreadCapabilitySupport,
  mcp_health:ThreadCapabilitySupport
}
ModelRouteBrief {revision:u64,available:bool,has_unavailable_reason:bool}
ThreadCapabilitySupport = Unsupported
```

Unsupported明确表示当前Thread投影未提供该能力，不等同产品MCP/LSP领域也不支持或无服务器。
以后接入实测来源必须显式演进schema，不在当前实现临时添“健康空列表”。本域不携带完整
Settings、catalog或Mode文档；相容来源revision与route CAS各自独立。header保留原route的
account/model/effort/reason；active_skills的实际名称由typed页返回。cold来源由baseline identity
的mode=cold表达，不把冻结快照宣称持续观察当前配置。

### 9.6 authoring

```text
AuthoringBaseline {
  todo:Option<TodoBrief>,plan:Option<PlanBrief>,workflow:Option<WorkflowBrief>,
  progress:ThreadCapabilitySupport
}
TodoBrief {reference:TodoReadRef,item_count:u64,has_call_id:bool}
PlanBrief {revision:u64,state:Drafting|AwaitingConfirmation|RevisionRequested|Approved,
           document:Option<PlanDocumentRef>,updated_at:i64}
PlanDocumentRef {version:u64,content_hash:String}
WorkflowBrief {reference:WorkflowReadRef,revision:u64,has_current_run:bool,
               lifecycle:Option<Active|Terminal>,mode_deleted:Option<bool>}
AuthoringChange {todo:TodoReplacement,plan:PlanReplacement,workflow:WorkflowReplacement}
TodoReplacement = Unchanged | Replace{value:Option<TodoBrief>}
PlanReplacement = Unchanged | Replace{value:Option<PlanBrief>}
WorkflowReplacement = Unchanged | Replace{value:Option<WorkflowBrief>}
```

三个Replacement在同一个源提交的Change内原子归并；无关成员保持Unchanged。progress当前
Unsupported，不能虚构百分比。PlanDocumentRef仅在文档改变时变；同一version/hash的正文
在当前阅读owner内复用，Plan状态变化不重复传markdown。无可证明来源的Todo call_id映None，
不延续旧空串冒充稳定身份。Workflow只交当前runtime run；本次不扩展成完整图/归档/历史API。

## 10. 具体详情读取面

除PlanDocumentScope无需text外，全部scope拥有header/text/request_close/close/retry_close，
关闭沿生命周期合同；列表方法
采用§5.2的offset/limit和typed page。每个header都含scope:ReadScopeIdentity，文本字段采用
ReadText，数字/enum/可空性保真。下表列出各scope全部额外方法和header字段，不能由executor
以万能Map替代。读取无需另订阅一个Thread聚合流。

| scope | header除scope外的字段 | 额外typed方法 |
| --- | --- | --- |
| TurnReadScope | input_id:Option<ReadText>,id:ReadText,thread_id:ReadText,revision:u64,updated_at:i64,state:TurnReadState | 无列表；text读该Turn已登记具体文本字段 |
| InteractionIndexScope | total:u64,pending:u64 | entries(offset,limit)→InteractionBriefPage |
| InteractionReadScope | §5.3全部字段，保持purpose/continuation/terminal值 | §5.3 questions/options/answer_entries/answer_values |
| ActivityReadScope | thread_id,identity,turn_id:ReadText; revision:u64; input_id,attempt_id:Option<ReadText>; kind:ThreadActivityKind; summary:ReadText; summary_truncated:bool; count/background:u32;active_count:u64;latest_started:Option<ActivityToolReadItem> | tools(offset,limit)→ActivityToolPage；wait_targets(tool_index,offset,limit)→WaitTargetPage；latest_wait_targets(offset,limit)→WaitTargetPage |
| StorageReadScope | 原StorageBrief全部非reference字段，last_error:Option<ReadText>，不重复has_last_error | 无列表 |
| MetricsIdentityScope | turn_id:ReadText,attempt_id:Option<ReadText> | 无列表；source_revision固定该不可变身份版本，不用实时counter sequence |
| ContextReadScope | frozen_model_id:Option<ReadText>,prompt_cache_policy:Option<ReadText>,estimated_cost_count:u64,estimated_cache_saving_count:u64 | costs(offset,limit)→CostPage；cache_savings(offset,limit)→CostPage |
| ConfigurationReadScope | route:Option<ModelRouteReadValue>,active_skill_count:u64 | active_skills(offset,limit)→SkillNamePage |
| TodoReadScope | call_id,agent_id,path,parent_path,explanation:Option<ReadText>,item_count:u64 | items(offset,limit)→TodoItemPage |
| WorkflowReadScope | revision:u64,current_run:Option<WorkflowRunReadValue> | 无列表，不暗加graph/history |
| PlanDocumentScope | version:u64,content_hash:String | document()→PlanDocumentValue{scope,version,content_hash,markdown:String} |

`TurnReadState`与原完整TurnState逐变体/字段同构，所有String替换ReadText；不是只有
TurnBriefState。特别保留Failed的code:Option<ReadText>/message:ReadText、Cancelled
Coalesced的target_turn_id:ReadText、BudgetLimited的rollover Failed{error:ReadText}。
其余嵌套enum/计数/时间字段与§9.2完整定义相同，无默认补值。

`ActivityToolReadItem`全部字段：`call_id:ReadText,task_id:Option<ReadText>,name:ReadText,
summary:ReadText,arguments:CommandLine|Opaque|Streaming|Unavailable,
state:Running|AwaitingApproval|Cancelling|Finished,ordinal:Option<u64>,started_at:Option<i64>,
wait:Option<WaitReadValue>`。工具页额外保留其`index:u64`，原列表顺序不变。
WaitReadValue：`intent:Events{target_count:u64,timeout_ms:u64}|Timer{duration_ms:u64},
state:Waiting|Ready|TimedOut|Elapsed|Cancelled|Failed|Interrupted,messages_ready:Option<bool>`。
WaitTarget：`index:u64,task_id:ReadText,tool_name:Option<ReadText>,summary:Option<ReadText>,
summary_truncated:bool,status:Option<Running|Succeeded|Failed|Cancelled|Interrupted>`。
latest_started不冒用active列表索引，故有独立latest_wait_targets方法；没有对应wait或Timer
上调用targets为InvalidArgument，不当空列表。activity detail的完整正文/结果仍由原typed
activity内容读取接口承载，此scope只替代原状态域无界元数据，不把状态摘要当详情正文。

`CostReadItem {index:u64,currency:ReadText,amount:f64}`；`SkillNameReadItem {index:u64,name:ReadText}`；
`TodoReadItem {index:u64,step:ReadText,status:Pending|InProgress|Completed}`。恢复数据仍须保留
原协议可表达值，不以当前tool writer的数量/字符限制拒绝历史读取。
`ModelRouteReadValue {account_id:ReadText,model_id:ReadText,effort:Option<ReadText>,revision:u64,
available:bool,unavailable_reason:Option<ReadText>}`。
`WorkflowRunReadValue {lineage_id:ReadText,run_id:ReadText,mode_id:ReadText,graph_revision:u64,
graph_hash:ReadText,lifecycle:Active|Terminal,current_state_id:ReadText,started_at:i64,updated_at:i64,
current_state_title:ReadText,mode_display_name:ReadText,mode_deleted:bool}`。

### 10.1 逐字段预算结论

- 五域Data除已验证的Plan content_hash和本进程identity外，不含任意业务String/无界列表；
  字段数固定，Interaction单delta索引总数<=100。不是用无证据ID cap代替schema设计。
- 列表元素中的每个String均为ReadText；嵌套列表独立分页。4096 Inline上限加实际JSON
  计量/必要Deferred可保证单元素前进；页limit不是最小返回量，不能截断整条合法元素。
- Turn失败/rollover、storage错误、工具ID/name/Wait、币种、route/effort/理由、Todo/Workflow
  全文字段均有明确typed读取方法；metrics无需长字符串也能持续合并/撤回同一sample。
- Plan document使用已校验持久状态128KiB JSON子值，保原空白和hash；scope封套有界且
  总计仍核256KiB。不能只凭trim后64KiB证明返回预算。
- 每次serialize按实际完整Data/page计算，不把源引用内存、FRB编码字节、临时解码或Dart
  全文呈现占用隐藏在这些数字后。索引/源引用的生命周期和pending queue仍须真实收束。

本节完成五域Data和元数据详情DTO的形状；完整runtime/FRB/Dart ports、receipt、HTTP/SSE
迁移、原activity内容读取及错误值边界仍须下一合同统一列齐，不能据此提前派发R。

## 11. ReadRef来源桥、索引连续性与Interaction观察

### 11.1 引用登记不是持久化ID

registry在发布对应Data前登记读取定位；不能等第一个query到来后从当前选择猜原source。
每条定位固定`原entry owner、typed ref种类、canonical业务身份、事实revision、来源种类`。
Interaction额外保存由原投影已知的`wire interaction ID、local ID、interaction/permission来源`；
wire ID使用原`interaction_key::encode/decode`，durable键使用唯一
`thread_projection::order::receipt_id(kind,local_id)`，不复制另一套字符串格式。

固定来源选择如下：

- 当前Turn、Interaction、Activity、Storage、Context、Configuration、Todo、Workflow：在
  实际projection发布边界取其不可变typed来源。所需原source若还按值持有，可做一次必要
  投影并交Arc共享；不是每个scope复制全文。查询不会重新求当前策略或创建执行owner。
- 冷projection的Turn来自原`newest_terminal_turn`，Interaction先读已验证checkpoint，终态
  缺失再按已知durable identity取实际receipt；投影/解码失败不得`.ok()`成空值。
- 活动的短暂中间版本若已不被当前projection、在途交付或scope持有，返回Superseded。
  不保证所有过去Activity版本永久可读，不从后来的同名task补造旧内容。
- MetricsIdentity定位不可变turn/attempt组合；只是sample身份索引，不保第二份计量快照。
- PlanDocument定位实际version/hash并持原有效文档源；同identity可共享，不另建全历史正文库。

登记只保当前projection需要的索引、可靠队列/未ACK交付所需的来源、已打开scope和已登记命令
身份观察的必要定位。ACK后不再有这些owner引用的历史定位可释放；之后旧ref明确Superseded，
不为使任何旧ref永远成功而积累全局map/全文缓存。原历史仍通过已有历史身份入口可达。
pending operation需要的定位归该操作permit并受64预算；详情scope继续受8/Thread与调用64上限。

scope的opening在首await前登记。若需要异步冷读，先捕获上述定位与原owner，读回后核owner
未关闭及确切revision/kind/业务身份，再安装immutable源；不跨await持registry/配置锁。
source可以从resident转成durable，只要证明是**同一身份、同一revision的同一事实**；不允许
以latest替代expected。owner替换期间读到正确旧字节也不能发布给新incarnation。

### 11.2 exact-revision receipt读取（复用原表，不迁移数据）

现有`HistoryStore::latest_fact_receipt`只取最新记录，不能证明旧ref的exact revision。
原`history_fact_receipts`已经以`(item_id,revision)`为主键，writer核相同键的digest一致；
不需要新表或复制receipt账本。本次由R在原HistoryStore边界增加crate内能力：

```text
fact_receipt_at(item_id:&str, revision:u64) -> Future<Result<Option<FactReceipt>>>
```

读取原表的精确键，复用原schema/read-only连接准入；检查实际kind及解码后的record revision/
local ID。不得读latest后把它的revision改成请求值。查询失败传播typed Storage/Protocol边界，
不存在原requested版本时按下列规则区分：

- ref确实登记过而该版本已不可取得：Superseded；
- 调用者指定从未存在的业务身份，且resident/checkpoint/对应durable事实均不存在：NotFound；
- 数据来源打开/解码/关联校验失败：实际Storage/Protocol，不降为NotFound；
- 原scope或owner关闭：Cancelled优先，仍join已受理read。

这里只新增读取原事实的必要查询，不改变持久化布局、不把普通读取变成schema迁移。既有
显式activation的schema准备仍走原边界；原terminal/no-change决定的latest查询与本exact读取
分开，不能为新API修改旧数据或清空不符合预期的条目。

### 11.3 index页与delta

- InteractionIndexRef.entry代表这个incarnation的集合，reference.revision仅随成员/成员brief
  变化推进；不是execution所有字段共用的revision。header total/pending及所有page都来自
  这一个不可变index源，entries按InteractionReadRef.entry升序，固定scope内不得移动顺序。
- page的条目ref.entry与delta.upserted.reference.entry/removed_entries/terminal_facts.entry
  是同一索引域；brief.revision等于该ref.revision，不能分别取不同source快照。
- delta.base_index_revision必须接上前一index水位；index.reference.revision是应用后水位。
  当前集合成员更新走upsert；真正离开当前集合走remove。需要可靠交付但本提交后已不在
  当前集合的终态走terminal_facts，同时允许其entry出现在remove；仍在集合的终态只走
  upsert，不在terminal_facts重复。remove本身**不是**已回应/已批准/已取消的证明。
- terminal_facts只含Resolved/Cancelled/Expired，并来自原core effect里的实际终态，不从
  “pending集合没有它”推断。首基线只表示当前集合；过去终态用真实receipt判定，不伪造补发。
- D1拿到baseline即可归并execution状态；索引材料可按需分页，未读完不能标complete。打开
  index scope后产生的delta仍按连续序归并；旧page只补原revision材料，不能覆盖同entry的
  新brief或复活已remove成员。需要合并的元数据仅记录本次查询以来的entry新水位/tombstone，
  受可靠队列同样64帧/8MiB上限；超出即放弃该索引读取，重建当前index scope，不无限缓存。
- index重读不能重开Timeline或重放回应。空页/total不匹配/同scope重复entry/错误next_offset
  为Protocol，不靠跳过该页填平缺口。冷index没有后续变化，仍保持到明确取消。

### 11.4 回应receipt的身份观察

Rust原receipt目标继续是`interaction:<wire_id>`、runtime owner_epoch和真实interaction revision，
requires_identity_observation=true；这与facet revision/index revision/delivery sequence均不同。
runtime/durable的回应reply必须给出与该receipt目标相符的typed交互身份/终态；不能只有
“execution水位前进”而没有可判定的交互结果。

D1在发送前登记原Session/incarnation、InteractionReadRef.entry、完整wire ID、预期revision、
typed resolution的观察条件。只有相同业务ID/来源、原owner和预期终态的真实typed事实，或
原命令返回的同身份canonical结果，才能满足它；terminal_facts可满足身份观察，remove/ACK/
无关interaction不能满足。必要正文比较通过对应scope或已冻结输入与native成功receipt完成，
不能只比较kind=Resolved。变更另一个interaction或同ID新incarnation不结算旧操作。

已知命令成功但观察失败仍为syncFailed；未知结果不因“当前没有pending”改判成功。发现相同
业务决定不等于证明外部operation ID是那次提交者，不能伪造外部ID的持久去重事实；后续可
明确展示匹配的canonical结果，不能自动重发来取得新receipt。Durable只采信原保存事实。
