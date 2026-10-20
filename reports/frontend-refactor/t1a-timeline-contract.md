# T1.A — Timeline FRB push 契约（v2）

状态：root 已冻结的首项实施合同；只覆盖下述完整垂直接缝，不代表 T1／整体重构已完成。

v2 替代 v1：root 固定单个 delivery task，并按已核实 FRB 2.13 能力明确 disconnect 的取消
接线；公共方法、DTO、2／1／8 MiB 预算与业务语义不变。形成 v2 时执行者尚未修改源码。

## 1. 授权、基线与任务边界

批准计划：**Rust／FRB／Dart 全链路重构与 Contract-First 实施计划**，v3，Plan revision 6，
`sha256:8dbea7a50d90d0cd6b6de5502a997923734e0cbd37459aaf0efa204596f56dc3`。
实施／审查派发必须同时附该完整计划，不用本文件替代。

最新同步基线：`f6cb327ceb3416dca181790575711588571d3ec7`。这替代旧的 8247241、23dc4e87
作为最终贡献比较基线；后两者的历史证据只在相同输入仍未改变时复用。

前置差异：root 对 AGENTS、design/02、07、18、19、24、25、26、README 的未提交目标设计。
派发时提供这些文件和本合同的 SHA-256 身份。没有前置生产源码改动。

本任务价值：把仍由 Dart `initial/next` 拉取的 Timeline 改成真正的 typed FRB push，并在
**Dart port 之前**限制未消费数据；保留真实 reader 身份、分页／详情隔离、可靠保存与资源关闭。

T1 按真实可独立审查的接缝顺序交付：

1. **T1.A（本任务）**：Timeline bridge push、ACK、注册和关闭；Rust 内部 Session 等待不变。
2. T1.B：Thread 五域与 product 实体／窗口 feeds、必要 server 映射（另行冻结完整合同才派发）。
3. root 统一生成和新增契约测试的本地／CI 接线；T2 迁移全部 Dart ports／adapter／领域服务。

这是 T1 内的有序验收切片，不允许将新增未使用 primitive 当作全部 T1 完成；T2 仍依赖完整
T1。T1.A 本地审查不声称旧 Dart adapter 已迁移或最终 GUI 可运行。

### 必须保留的最新主干行为

- 冻结 Profile 的旧 `providerId/model` 到 `accountId/modelId` 只在既有迁移边界转换；本任务不改。
- Rust 模型层所有最终 context resolution；Dart 不恢复旧阈值计算或滑块。
- 手动压缩仍为既有一次命令，busy 拒绝、不自动重试、不伪造输入；ContextCompaction 内容照常经本 feed。
- 新会话 preparation 是一次创建命令流，观察断开不取消创建、终态前断流 UnknownOutcome；本任务
  不把它改成可重连资源 feed、不改变成功含义，也不为业务终态开背压后门。

## 2. 层次、所有权与允许变更

```text
core Session（唯一正文和保存事实）
  → runtime TimelineContentReader / TimelineTailStream（唯一产品预览转换）
  → BridgeTimeline（捕获同一 reader + tail；native 生命周期 owner）
  → StreamSink<BridgeTimelineFrame>（FRB 官方流）
  → T2 adapter / Session service（转换、归并、有界交接、ACK）
```

- 不修改 core 的 ChatTail::initial/next，也不改 HTTP Timeline 页／尾部／详情语义。
- 不新建内容 reducer、历史 cache、工具正文解析器、通用 RPC、消息总线或 codec。
- 复用现有 activity guard、CancellationToken、真实完成 Shared future 和 registry 强 owner 机制。
- producer 是本 handle 的唯一 tail 消费者；page/detail 只使用 open 时捕获的同一 reader。
- root 固定使用**一个登记的 delivery task** 同时承担读源与同步 sink 投送；不额外派生
  producer→mpsc→sink 转发任务，避免队列外再藏一份待发 payload。join 该 task 即收束这两项职责。
- 每个 handle 只允许一个 stream；不是每次订阅 Dart Stream 都新开 Rust tail。
- registry 覆盖 opening／尚未 stream／active／closing／unresolved，应用退出不能漏掉 Timeline。
- 查询／关闭不经过挂起的 tail 取帧锁；stream 的 FRB 方法应完成一次准入和任务登记后返回，
  由已登记 owner 持有 sink，不以长期借用 opaque 的方法 future 代替任务所有权。

### 写范围与禁区

执行者只写 `code/anywork/rust/src/api/studio/` 中本任务必要的手写 Rust：

- `handlers/chat.rs` 与按职责拆出的私有 Timeline 文件；
- `types/chat.rs`、`types` 重导出（必要时新增独立 feed DTO 文件）；
- `subscription` 中 Timeline 注册／真实完成的接缝；
- `runtime.rs`、handlers/mod.rs、studio/mod.rs 的必要装配／导出。

不要顺便改 Thread／product 的生产行为，不改其它 crate、Rust 内核、server、Dart、manifest、
lockfile、文档、xtask 或生成输出。不 stage／commit／push。root 独占生成和共享接线。
目录权限可能包含更多文件，这不扩大本任务实际写授权。

## 3. 公共方法（精确合同）

```rust
pub async fn open_timeline(thread_id: String) -> Result<BridgeTimeline, BridgeError>;

impl BridgeTimeline {
    pub async fn stream(
        &self,
        sink: StreamSink<BridgeTimelineFrame>,
    ) -> Result<(), BridgeError>;

    pub async fn ack_through(&self, delivery_sequence: u64) -> Result<(), BridgeError>;

    pub async fn page(
        &self,
        before: Option<String>,
        limit: Option<u32>,
    ) -> Result<BridgeTimelinePage, BridgeError>;

    pub async fn read_detail(
        &self,
        item_id: String,
        query: BridgeTimelineDetailQuery,
    ) -> Result<BridgeTimelineDetailChunk, BridgeError>;

    // 使用 #[frb(sync)]，与既有 request_close 同步语义一致。
    pub fn request_close(&self);

    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError>;
}
```

**删除** BridgeTimeline 公开 `initial`、`next`；不留 deprecated alias、第二套拉取入口或兼容 façade。
open 仍捕获一个 reader 和一条 tail、取得首基线，等待 stream 之后通过第一个 data 移交。
page/detail 不要求 stream 已启动，也不消耗 stream 的首帧或 delivery sequence。

输入和单位：

- thread_id、item_id 与 cursor 的既有校验不放宽；ID 为 String，不用显示名识别。
- before=None 是最新页；Some token 必须是原服务端 token，空串不当成 None。
- limit=None 为 32；Some 只接纳 1..=100，不夹紧或静默改默认。
- detail max_bytes=None 为 64 KiB；Some 只接纳 4..=256 KiB；按合法 UTF-8 边界返回。
- revision、version、delivery_sequence 为 u64，不经有损 f64 计算；Dart 精度由生成器处理。
- 所有 *_at 仍是 Unix 秒 i64；已有 *_millis 为毫秒；*_bytes 为 UTF-8 字节。
- continuation=None 表示首块或读取完成（由请求／响应位置区分），不能与空串混同。

## 4. 新类型（全部字段／变体）

这些名称及可空性固定。FRB DTO 不成为新的持久化格式。

```rust
pub enum BridgeTimelineFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeTimelineEvent,
    },
    Failure { error: BridgeError },
    Closed,
}

pub enum BridgeTimelineEvent {
    Baseline { baseline: BridgeTimelineBaseline },
    Update { update: BridgeTimelineUpdate },
}

pub struct BridgeFeedCloseReport {
    pub feed_id: String,
    pub outcome: BridgeFeedCloseOutcome,
}

pub enum BridgeFeedCloseOutcome {
    Clean,
    Unresolved { issues: Vec<BridgeShutdownIssue> },
}
```

- feed_id 等于该 Timeline baseline.subscription_id，不是 Thread ID、operation ID 或 native 地址。
- issues 必须非空；Clean 不能同时携带 issues。不将 deadline 超时或 panic 变成 Clean。
- `BridgeShutdownIssue` 沿用既有完整字段：stage:String、code:String、message:String、
  retryable:bool、correlation_id:String。只用脱敏消息和真实 correlation，不传播 panic payload。
- `BridgeError` 不新增第二套分类，完整字段仍为 code:BridgeErrorCode、message:String、
  retryable:bool、correlation_id:String、details_json:Option<String>。
- Failure 后只能 Closed；每种控制帧至多一次。正常结束只 Closed；主动关闭在 sink 已失效时
  控制帧可以无法投递，真实 close 报告与 registry 状态仍须可读，不能用控制帧投递成败证明 join。

### 完整复用、不改变的 payload

以下为 `types/chat.rs` 的已核实 v1 接口；嵌套 canonical `BridgeThreadItem` 和错误类型按该
commit 的完整定义复用，不修改任何字段、变体、默认值、脱敏或历史表示。

| 类型 | 全字段／变体 |
| --- | --- |
| BridgeTimelineLifecycle | Streaming、Terminal |
| BridgeTimelinePriority | Immediate、Coalesced |
| BridgeTimelineResyncReason | Lagging、Unavailable |
| BridgeTimelineRecoveryNotice | Retry、Result |
| BridgeTimelineItemSource | Content；ModelRecovery{attempt_id:String, notice:BridgeTimelineRecoveryNotice} |
| BridgeContentField | Text；ThinkingSummary{chunk_index:u32}；ThinkingContent{chunk_index:u32}；ToolArguments；ToolResult；ToolOutputArtifacts；ToolUserInput{question_index:u32,part:BridgeThreadUserInputFieldPart}；RawPayload{payload_index:u32} |
| BridgeThreadUserInputFieldPart | Header；Question；Answer{answer_index:u32}；OptionLabel{option_index:u32}；OptionDescription{option_index:u32} |
| BridgeTimelineDetailRef | field:BridgeContentField、revision:u64、total_bytes:u64、preview_bytes:u64 |
| BridgeTimelineItem | item:BridgeThreadItem、source:BridgeTimelineItemSource、saved:bool、lifecycle:BridgeTimelineLifecycle、omitted_bytes:u64、details:Vec<BridgeTimelineDetailRef> |
| BridgeTimelinePage | items:Vec<BridgeTimelineItem>、before:Option<String>、has_older:bool |
| BridgeTimelineBaseline | subscription_id:String、version:u64、items:Vec<BridgeTimelineItem>、before:Option<String>、has_older:bool |
| BridgeTimelineFieldChange | Unchanged；Append{text:String}；Replace{text:String}；Remove |
| BridgeTimelineFieldUpdate | field:BridgeContentField、change:BridgeTimelineFieldChange、total_bytes:u64、preview_bytes:u64 |
| BridgeTimelineChange | Add{item:Box<BridgeTimelineItem>}；UpdateItem{item_id:String,expected_revision:u64,revision:u64,omitted_bytes:u64,saved:bool,lifecycle:BridgeTimelineLifecycle,item_shell:Option<Box<BridgeThreadItem>>,fields:Vec<BridgeTimelineFieldUpdate>}；Remove{item_id:String} |
| BridgeTimelineUpdate | Patch{subscription_id:String,from:u64,to:u64,changes:Vec<BridgeTimelineChange>,priority:BridgeTimelinePriority}；Resync{subscription_id:String,reason:BridgeTimelineResyncReason,baseline:BridgeTimelineBaseline} |
| BridgeTimelineDetailQuery | field:BridgeContentField、revision:u64、continuation:Option<String>、max_bytes:Option<u32> |
| BridgeTimelineDetailChunk | item_id:String、field:BridgeContentField、revision:u64、text:String、total_bytes:u64、continuation:Option<String> |

空 items 仍是有效基线／页；has_older 来自真实存在性检查，不能从条数或 omitted_bytes 猜测。
UpdateItem 的 item_shell=None 表示静态壳不变，不表示移除条目。saved 与 Terminal、正文 revision
独立；同 revision 的 saved 更新合法。Resync 同连接保持 subscription_id，真正重开才换身份。

源类型定义定位：`code/anywork/rust/src/api/studio/types/chat.rs`，本基线 SHA-256
`1d58cd3271357811e95b03b18b3e3c7bede50a2ef563ce2f85d66f38fdada75f`。
`BridgeThreadItem` 完整闭合定义位于同基线 `types/thread_stream/item/` 及其已存在依赖；本任务只
机械搬运现有转换结果，不重新定义其模型。若必须改变这些嵌套类型，先报告 root，不能自行补设计。

## 5. 投送、ACK 与精确预算

| 项目 | 固定值／语义 |
| --- | --- |
| 未确认 data | 每 handle 最多 2 个；baseline 计入 |
| sequence | 首 data 为 1，每次成功投送 data 加 1；不能回绕，溢出为 Protocol 并收束 |
| 未投送 pending | 最多 1 个 data，不能在 producer 局部变量之外再藏一份等待槽 |
| 单 data／pending 载荷 | 最多 8 MiB，共享产品结果的标准 JSON 编码字节计数 |
| 控制帧 | Failure、Closed 不占 data 额度，各至多 1；不进入满 data 队列后面永久等待 |
| core 页／预览／详情 | 原有 32/100 条、2 MiB 页、256 KiB 单条、8 MiB 连续性副本、64/256 KiB 详情不变 |
| 合帧 | 仅 core 原有一次合帧，transport 不另定时／合并／丢中间正文 |
| ACK 超时 | 不新增自动超时或重连；无 ACK 只停送数据，显式取消必须可收束 |

字节计数是领域载荷准入，不是 FRB wire bytes、RSS、Dart heap 或 core 驻留计量。使用既有
标准序列化能力向计数器输出即可，不建立第二正文字符串／Vec<u8> 副本、自研编码器或新增
wire 计量字段。计数对象是原产品 TimelineTailBaseline 或 TimelineTailUpdate 的标准 JSON，
不包含 FRB data 封套；序列化失败是 Protocol（retryable=false）。不为满足传输 cap 重裁剪
产品页或改变 core 的预算算法。超限以 Overloaded
Failure 结束当前 feed；原 Session／Turn／writer 不停止，last-known 可继续显示并显式重试。

生产者不能在额度满时持续从 tail 抽取并保留未交付 frames。可有最多一个已取得的待发结果，
其余变化留在 core 的有界连续性机制内；恢复读取后由 core 返回连续 Patch 或真实 Resync。

ACK 仅作用于当前 opaque：

- active 时 ack(0)、ack(n<=已确认) 成功幂等。
- 已确认 < n <= 已发送时，一次释放所有 seq<=n 的在途票据，唤醒容量等待。
- n>已发送为 Protocol，不改变额度／水位；调用方随后 request_close+close 并保留协议错误。
- closing/closed 时 ACK、stream、page、detail 均 Cancelled 优先；close 可重复调用。
- ACK 不确认业务保存、operation 观察、执行终态或有效性；不能释放另一个 handle 的额度。

## 6. 生命周期、时序与失败路径

### 准入与关闭

同一短临界区决定 closing、单消费者准入、活动调用计数和发送／确认水位；不持该锁 await。
request_close 先原子封准入，再触发 CancellationToken，容量和源等待都监听它。

```text
open:
  获取 active bridge（尚无子资源）
  创建 provisional Timeline owner，绑定原 runtime / thread / cancellation
  在 registry 的 shutdown 准入检查下登记（先于 reader/tail 的第一次 await）
  登记 open 调用 guard
  带取消打开同一 reader、tail；取得一次 baseline；把结果安装到原 owner
  成功只向调用方移交 handle；失败/取消清理自己，未解决 owner 不从 registry 消失

stream:
  closing 优先拒绝；在短锁内认领唯一 consumer，先登记 owner task 再返回
  唯一 delivery task 独占 tail 与 sink，先发 baseline，再依序取 runtime.next
  每个 pending 完成计数/转换；错误 -> 唯一 Failure -> Closed，不用日志后跳过
  等待 data 额度和 source 时同时观察 cancel；sink.add 失败立即 cancel
  在一次非 await 的发送线性化步骤内同步 sink.add 与 sent 水位
  同步 sink.add 成功后才能让 ACK 看见该序号，不能暴露已预留未发送的序号
  sink.add 失败 -> cancel；所有 owner 结束并发布真实 completion

close:
  request_close
  等待已登记 open/query/delivery task 真实结束（不是等 data ACK）
  释放 baseline、tail continuity、captured reader 和未投送 payload
  汇总 retained completion：Clean 才可摘除强 registry owner；失败为 Unresolved
  并发/重复 close 读取同一结果；close Future 被外部放弃不遗失后台资源所有权
```

既有 reader 的调用取消仍复用 runtime/数据库原有机制，不另派无人管理的 query task。
close 没有新的独立 deadline：应用级唯一 deadline 在 registry shutdown 编排收集 unresolved；
外部等待超时不释放 permit、不把仍运行任务标为完成。绝不 abort 后未 join 就报告 Clean。

正常源 EOF：已经取得的 data 按顺序送完才 Closed；无下游 ACK 时允许停等，request_close 仍
立即打断。主动关闭可放弃尚未发送的 observation，但不能发送伪造 saved／Terminal。

FRB 2.13 的 StreamSink 没有公开的 closed Future。不能伪造该能力、轮询 port 或用定时 ping
检测 disconnect。sink.add 的发送失败触发本 owner 取消；Dart Stream.cancel 必须由 T2 adapter
在 finally 显式 request_close→close→dispose，即使两额度已满也如此。全窗口且没有新 send 时，
Rust 的可观察关闭信号就是上述显式取消／应用 shutdown，不把裸 Stream.cancel 或 GC 当成 native
ACK。这是既有显式 owner 合同的接线，不新增轮询、重放或隐式关闭假设。

### 错误矩阵

| 事实 | typed 结果 | 消费者动作／禁止事项 |
| --- | --- | --- |
| 非法 ID／页范围／cursor／详情参数 | 沿用 InvalidArgument／NotFound／StaleRevision 等原分类 | 展示输入／版本问题，不夹紧或自动拼全文 |
| 第二次 stream | Conflict（retryable=false） | 关闭错误绑定；不能开第二个 sink 继续 |
| closing 后调用 | Cancelled（retryable=false） | 只结算原 attempt；不作为正常 EOF |
| ack 超 sent／sequence 溢出 | Protocol（retryable=false） | 关闭并报告；不释放额度，不重放业务 |
| source/conversion 失败 | 原 typed Failure，随后 Closed | 保留 last-known；由领域服务显式重建受影响 feed |
| payload >8 MiB | Overloaded（retryable=true） | 结束本 feed，显式资源错误；不截断决定或身份 |
| core Resync | 正常、有额度的 Update::Resync | 按既有 Live/History 规则采用基线；不是 transport Failure |
| sink 失效／观察取消 | 取消本 feed，真实 join | 不停止 Thread／writer，不关闭别的观察 |
| delivery task panic 或未证实完成 | CloseReport::Unresolved，稳定 issue code 与 correlation | 保留 owner／permit；不能第二次 close 变 Clean |

新增的 Timeline completion issue 固定使用 stage=`subscriptions`，唯一 delivery task panic 的
code=`producerTaskFailed`（该任务是 native feed producer，也拥有 sink）；不为产生
sinkTaskFailed 人为增加第二任务。既有其它订阅的 sinkTaskFailed 不变。沿用现有 registry
deadline 的既有分类，不新增动态拼接 code 或从 message 推断类别。

只使用既有 BridgeErrorCode 的 19 个分类，不新增字符串分类分支。没有自动 retry/backoff、
新的默认值、额外队列、keepAlive 或公开可写诊断。

## 7. 生产者—消费者迁移／删除清单

| 接缝 | 本任务 | 后续责任 |
| --- | --- | --- |
| core Session ChatTail | 不改；内部 initial/next 保留 | 既有公开 API 测试复用 |
| runtime TimelineContentReader/TailStream | 不改公共语义，机械复用 | server 继续消费同一内部等待 |
| FRB BridgeTimeline | stream/ACK/close report，删除公开 initial/next | root 统一 generate-gui |
| BridgeTaskRegistry／应用 shutdown | 纳入 Timeline opening/query/task/reader 的真实关闭 | root 最终退出／native 验收 |
| FRB 生成文件 | 执行者不写 | root 在输入冻结后统一生成并检查 |
| Dart StudioTimelineConnection／FrbTimelineConnection | 不在本切片保留 shim | T2 改 typed events/ack，删除 pull API |
| Dart StudioTimelineChannel／Session services | 不在本切片新增第二 pump | T2 await 消费／有界交接后 ACK，保留 attempt/关闭算法 |
| demo／fakes／领域及 adapter tests | 不把 fake 记 native 通过 | T2 同步迁移当前真实消费者 |

T1.A 到 T2 之间跨语言编译不完整是明确的依赖窗口，不是可交付兼容架构；最终不得遗留旧
initial/next adapter／ports 或未使用的新 feed。

## 8. 有序实施与定向验证

1. 阅读本基线的 chat handler、runtime reader、DTO、subscription completion／shutdown。
2. 增加上述新 DTO，保持既有 payload 不变；实现唯一 stream 准入与 ACK 状态转换。
3. 将捕获的 reader/tail 及 open/query/task 归入 registry 可真实 join 的具体 Timeline owner。
4. 用 typed sink 推送替代公开 initial/next；删除旧入口、更新 Rust 重导出和注释。
5. 输入稳定后向 root 汇报“需要统一生成”，暂停本范围修改；这不是完成报告。root 生成后
   通过同一执行者续跑消息确认新基线，再运行局部检查／测试和修复。
6. 完整报告绑定实际 diff／文件身份、命令、结果与未覆盖项；随后范围冻结交 fresh reviewer。

测试应复用真实生命周期路径，不只自测无消费者的 counter。可在 private 生产发送接缝注入
收集／失败 sink 来确定性交错，但不得新增测试专用 public API、伪造真实 FFI 或新依赖。
真实 StreamSink/native 仍由 root 手工验收，局部测试不冒充该层。

| 要求 | 局部证明（测试名统一包含 timeline_feed） | root 最终证明 |
| --- | --- | --- |
| baseline 有序、两额度 | baseline + 两次变化，第三个 data 在无 ACK 时不可交付；ACK 后继续 | 实际 FRB 慢消费诊断 |
| ACK 正确 | 0／旧 ACK 幂等、跨前缀释放、超 sent 不改状态、两个 handle 隔离 | Dart merge→ACK 行为 |
| 无缺帧与 Resync | 复用现有 Session 基线/变化证明，新增 handler push 次序断言，不重写 core 算法 | native 首屏／流式／分页 |
| 业务终态不绕额度 | full window 下 saved／Terminal 保持待交付；ACK 后有序出现 | 完成／保存事实与诊断 |
| 无 ACK 仍能关闭 | full window、sink 失败、未启动 stream、挂起 source／query 下 request_close→join | 退出、切 Thread、进程回收 |
| 真完成与重复关闭 | 同时 close 不能早于 guard 释放；失败 retained、重复结果一致 | 应用 deadline unresolved |
| 参数和 budget | 原页/详情范围不变；8 MiB cap 边界、无静默丢失／截断 | 同场景载荷与高水位证据 |
| 旧入口删除 | Rust 引用与公共导出不存在 BridgeTimeline.initial/next | T2 后 Dart AST／旧路径清理 |

执行者局部命令（从根目录，生成后）：

```bash
# rustfmt 只作用于本次手写改动文件；不得 cargo fmt --all 或全仓可写格式化。
# 用实际改动路径执行 rustfmt --edition 2024 --check <files...>
cargo check -p pl-studio-bridge --lib
cargo clippy -p pl-studio-bridge --lib -- -D warnings
cargo test -p pl-studio-bridge --lib timeline_feed
```

若基线的 edition 或 formatter 规则与命令示例不同，以 manifest／rust-toolchain 实际声明为准，
先报告并使用同一已声明值，不能为了通过局部检查改项目工具链。
root 负责把新增 bridge 契约入口纳入正式本地／CI，然后执行全量门禁、统一生成检查和 native
GUI。没有 root 最终验收时只能批准本切片，不能声明整个重构完成。

## 9. 变更控制

**必须遵守**：所有公共字段／方法、owner、关闭含义、2/1/8 MiB、错误矩阵、旧入口删除和无自动
重试。若不能用现有机制满足，停下给出证据／受影响消费者，先由 root 更新合同。

**局部实现建议**：沿用已存在的 Shared completion 与短锁 guard；可以拆私有模块、调整不改变
公共语义的数据结构。不得将建议理解为要复制一套相同 registry 或自研组件框架。

**非关键待核实**：private helper 的最终名字和模块拆分；RustFmt 所需实际文件清单。这些不改变
上述接口、预算或验收。没有授权执行者自行决定的关键设计空白。
