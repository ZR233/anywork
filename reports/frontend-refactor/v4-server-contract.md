# v4 Server HTTP／SSE运输接缝

本册固定R/A/C迁移的HTTP形式，复用现有Axum/serde/Tokio及原runtime资源owner；不新增
业务总线、认证系统、JSON codec或兼容端点。相关字段在Thread/product/read-port合同定义。
当前server路由权威注册仍为`pl-studio-server/src/routes.rs::api_router`及utoipa注解，
`/openapi.json`来自同一个router，不能维护手工第二份OpenAPI。

## 1. 安全、限流与作用域

保原loopback bind、Host为loopback/localhost、Origin存在时HTTP scheme/host/port同源
检查，允许无Origin。它不是用户/session认证，不宣称多租户隔离，也不将可猜ID当访问控制。
所有feed/read引用绑定server当前登记的原runtime/owner/incarnation，调用方不能改Thread
或project参数将旧句柄重定向。同scope ID完整保原文本，trim仅用于原判空条件。

保JSON body上限4MiB；附件multipart独立200MiB、原单文件50MiB/最多16项不改。Open/ACK/
close只接typed身份/计数，无正文业务写入，不能借上传限额放宽其默认body规则。

现有普通请求64、SSE流64两个池继续分开；新增控制请求专用64并发许可，只服务ACK/
request-close/close/retry-close，防止普通慢写占满阻断关闭。所有池try-acquire，满时typed
Overloaded，不引入等待全局长写的FIFO。它不增加native全runtime64在途详情call预算。
路由注册显式分类为normal/stream/control，不用旧path substring猜新的POST是否为stream。
stream permit从open登记前持有，actual native/pump/query工作真实结束才释放；失败未决保留。

## 2. 新feed：POST中打开并认领同一条SSE

选择一个HTTP请求完成native open与唯一listen，不增加对外open→GET的孤儿握手。

- Thread：`POST /api/v1/threads/{thread_id}/facets/<facet>/events`。
  body=`ThreadFeedOpenRequest {mode:ThreadObservationMode}`；facet恰为
  execution、metrics、context、configuration、authoring五条**固定路由**。
- Timeline：`POST /api/v1/threads/{thread_id}/timeline/events`，body为具名空请求。
  它是独立typed内容feed，不并入五facet，不恢复HTTP initial/next pull。
- Product：`POST /api/v1/products/<resource>/events`，resource按下表逐条静态注册。

| Resource | 固定segment | body完整字段 |
| --- | --- | --- |
| ProjectDirectory | project-directory | 无 |
| ThreadDirectory | thread-directory | scope:ThreadDirectoryScope |
| AgentDirectory | agent-directory | 无 |
| Configuration | configuration | 无 |
| ModelCatalog | model-catalog | 无 |
| AccountTemplates | account-templates | 无 |
| AgentProfiles | agent-profiles | 无 |
| ModeCatalog | mode-catalog | 无 |
| AccountUsage | account-usage | 无 |
| PerformanceSummaries | performance-summaries | 无 |
| PerformanceHistory | performance-history | 无 |
| SessionCosts | session-costs | rootThreadId:String |
| Recovery | recovery | 无 |
| Mcp | mcp | 无 |
| Lsp | lsp | 无 |
| Skills | skills | projectId:String |
| Persistence | persistence | 无 |
| PersistenceQueue | persistence-queue | 无 |
| Updates | updates | 无 |

每行有自己的Request/Frame/handler/OpenAPI operation；`<resource>`只是本表展开记法，
实现不是`resource:String + dynamic payload`端点。全局资源拒绝额外scope字段；ThreadDirectory
scope.query的query保原四字段，scope.thread只有threadId并保原单Thread读取准入，
Skills/SessionCosts只接受其真实scope。全部请求deny_unknown_fields。

响应200 `text/event-stream`，`x-studio-feed-id`为原native feed_id（本次生成的有界ASCII
身份，不是任意业务ID）。一个SSE `event: frame`的data为该具体typed Frame的serde JSON。
Data的SSE id可以为deliverySequence十进制；它不提供恢复承诺。KeepAlive复用现有15s注释，
不占Data窗口、不算ACK。单Data/队列预算按该feed原合同：Timeline不能被误改成metadata
256KiB预算，五域/product遵各自已定预算。

收到Last-Event-ID直接409 typed Conflict/replayUnsupported，不再“先stale再悄悄重开”。
所有客户端须显式创建新POST流和新baseline，不自动重放旧POST或复用旧handle；浏览器
EventSource只支持GET，不作为新接口客户端。使用已有HTTP客户端的POST streaming/fetch，
不能为兼容EventSource保留旧GET/SSE别名。

native open失败在响应前为HTTP typed错误；响应已建立后，错误用本feed具体Failure控制
帧终结。Failure/Closed/ResyncRequired最多一个控制终结，业务终态仍为有序Data。满2个
未ACK窗口时，query/控制不等待该Data队列，取消可唤醒。JSON编码/发送成功不证明应用
已归并；只能显式ACK推进native窗口，TCP写入与SSE id都不是保存/命令回执。

## 3. Feed控制路由

控制payload只有共同资源能力，不含业务Frame，因此可以共享固定控制路径：

| method/path | request | response |
| --- | --- | --- |
| POST /api/v1/feeds/{feed_id}/ack | `{deliverySequence:u64}` | 204 |
| POST /api/v1/feeds/{feed_id}/request-close | 具名空请求 | 204，仅封准入/发取消 |
| POST /api/v1/feeds/{feed_id}/close | 具名空请求 | FeedCloseReport |
| POST /api/v1/feeds/{feed_id}/retry-close | 具名空请求 | FeedCloseReport |

ACK核原句柄已发送连续前缀，0/旧ACK幂等，超sent Protocol；closing Cancelled优先。
request-close不是Clean。close在途共享原工作，显式retry按CleanupRecovery沿同owner恢复，
不重开、不重发。控制路由只能获得无payload的原control能力，不能拿feedId在HTTP层自行
dispatch另一种业务内容。未知/已释放ID NotFound，不凭不存在就假造Clean。

HTTP transport在Clean之后可移除映射；幂等报告只在原handle仍存续时有效，已释放返回
NotFound与FRB dispose后不再可调用相同，不创建新的同名owner。Unresolved绝不移除映射
或释放许可；即使client已断线，server shutdown仍必须收束它或准确报告degraded。

## 4. typed read路径与父连接归属

普通产品/Thread详情由该client原feed监督其HTTP read scope。open请求完整字段为
`{feedId:String,reference:具体ReadRef}`。server必须从已登记的**原父feed**取owner_epoch/
incarnation组成ProductReadOrigin（Thread读取同样取原Thread feed的runtime_epoch/incarnation），
核kind/resource/scope与父连接相符后把origin+reference交给native。不能只凭ReadRef的
entry/revision定位，不能从当前owner补origin。父feed只能接同resource/scope的读取，
不能持Configuration句柄读别的Thread；SourceStatus、统计identity与Updates子scope同样
从该原父feed取origin。成功打开后的请求只用scope已经绑定的原身份，不再重查当前owner。

每个具体kind静态展开以下路由，kind不是任意运行期字符串分派：

- `POST /api/v1/reads/<kind>/open` → `{scopeId:String,identity:具体ReadScopeIdentity}`。
- `GET /api/v1/reads/<kind>/{scope_id}/header` → 具体ReadHeader。
- `POST /api/v1/reads/<kind>/{scope_id}/text`，body=`{fieldId:u64,offset:u64,maxBytes:Option<u32>}`。
- 该scope每个具名列表method：`POST /api/v1/reads/<kind>/{scope_id}/<method>`，
  body=`{listId:u64,offset:u64,limit:Option<u32>}`，返回该族具体ReadPage。
- 顶层entries body为`{offset:u64,limit:Option<u32>}`；ThreadDirectory唯一改为
  `{cursor:Option<String>,limit:Option<u32>}`，不保offset重载。
- 顶层entity body=`{reference:ProductEntityRef}`；具名lookup body仅该业务key字段，返回
  `Option<ProductEntityRef>`。方法清单及key字段来自产品read ports §4，不加动态where条件。

产品root kind与§2十九个segment相同；scalar无entries/entity路由。额外具名kind为
product-source-status、performance-summary-identity、performance-effort-identity、
performance-sample-identity、update-summary、update-operation、update-error、update-details。
SourceStatus只接受原父resource的status ref，不跨scope变成全域诊断出口。

Thread额外kind为thread-turn、thread-interaction、thread-interaction-index、thread-activity、
thread-storage、thread-metrics-identity、thread-context、thread-configuration、thread-todo、
thread-workflow、thread-plan-document。具体header/问题/选项/answers/tools/Wait/text方法与
字段按Thread合同§5及§10逐条注册，不额外公开JSON路径。Plan文档读绑定原version/hash。

read控制共用：`POST /api/v1/read-scopes/{scope_id}/request-close|close|retry-close`，空请求，
request-close返回204，另两项返回FeedCloseReport（其中identity字段按原scope标识）。
parent feed的requestClose同时封子scope准入并取消其真实查询；不允许feed已关闭而仅靠
client保存的scopeId继续读同ID新owner。HTTP open尚未交付响应也先登记父归属；响应丢失
时关闭父流仍可回收所有已受理子scope，不依赖client知道每个scopeId。

原scope成功pin后，普通source推进不使读到一半的文档失效；父连接/原owner关闭才Cancelled。
scope过期且原版不可得Superseded，wrong type/offset InvalidArgument，损坏Storage/Protocol。
页/块预算、UTF-8边界、scope8/runtime64call/readModel计费沿公共合同，不在Server另扩大一套。

## 5. Server自身监督与断连

原sender.closed只能证明HTTP body接收端不再取帧，原无监督tokio::spawn不能证明join。
R将server运输任务接入与native资源owner一致的明确登记/完成能力，复用Tokio JoinHandle/
现有owned completion，不新增通用任务调度器。AppState只持运输资源索引和任务责任，
不是另一canonical业务store；native source/projection仍只一份。

首await前取得stream许可/登记opening；请求取消发生在open期间也保该工作，open晚到即
requestClose并join，不发布给新请求。进入pump前登记其真实completion；每条失败/early
return都经过统一关闭责任，不能因send_json失败return而绕过native close。

SSE断连、server shutdown或显式request-close均同步封该feed及子scope准入，发native取消，
然后supervisor等待native producer/sink、server pump与已受理query真实终态。发送者返回
Ok不证明peer收到帧，pump结束也不证明native清理成功。Clean只按所有实际owner结果判定，
不是靠Drop、GC、socket EOF或超时。TCP缓冲中的已编码字节不是canonical source；不宣称
Clean证明远端已处理这些字节，client必须拒绝关闭后迟到应用。

server信号首先封HTTP准入/广播取消，在runtime finalizer前join运输资源并汇总全部typed
issues，再调用Rust shutdown。不能先让runtime报告Clean才补server失败，也不能忽略
server JoinHandle panic。保原二次退出信号的强制退出语义；强退不是Clean证据。

## 6. 命令结果与HTTP错误

所有既有业务mutation保具名独立路由，request保原输入校验/CAS并按最新合同增加明确字段。
成功/拒绝/未知/已提交但观察失败的响应使用该具体ReplyOutcome，五变体沿失败合同。
200返回returned；known rejected按其StudioError映射4xx/5xx；unknownOutcome为503；
committedButUnobserved/confirmedWithoutReceipt为500但保真实receipt或成功确认。
客户端必须读typed outcome，不凭status/retryable重发。

请求解析、Host/Origin、body/并发准入在dispatch前明确拒绝，mutation路由输出对应
rejected的相同序列化形状；不能让Axum默认纯文本错误绕过typed契约。query/控制错误是
StudioFailure完整code/message/retryable/correlation/details；新Superseded映409，
Cancelled/StaleRevision/Conflict仍各有独立code。保x-correlation-id，秘密不进诊断。

必须同步的具体请求变化：

- RemoveAccountModelRequest增加原operationId，不用Rust固定拼接替代。
- AccountUsage check增加expectedUsageQueryRevision，联网前验证原账号查询身份。
- Interaction resolution增加expectedInteractionRevision，逐层原样CAS，不用current覆盖。
- SubmitPromptReceipt增加native requestDigest；仍保原inputId/route revision CAS，不额外
  发明operationId持久去重表。new-thread结果中的同一receipt同步。
- Thread model-route保expectedModelRouteRevision与expectedSettingsRevision双CAS、
  modeDefaultSaved/warning和真实receipt，旧runtime/settings聚合替换为本域typed引用。
- Settings batch是Dart独立子操作编排，不新增伪原子HTTP batch或父receipt。

## 7. 删除与保留清单

删除旧GET /api/v1/state、/api/v1/state/product、/api/v1/events/product；删除旧Thread
聚合GET /api/v1/threads/{thread_id}及GET /api/v1/threads/{thread_id}/events；删除旧
Settings聚合GET /api/v1/settings、account-catalog、各runtime资源全量read与旧product topic
入口，改为对应具名feed/read。旧GET timeline/events改POST，不留兼容转发。

具名Settings、Mode authoring/validate/schema/preview、prompt/interrupt/interaction、项目与
Thread目录mutation、资源retry/reset/probe/repair/discover/search、附件read/admit/remove
及server update.check能力保留并更新typed DTO/outcome。不得顺带删原动作或新增desktop
prepare/install/shutdown endpoint；Server没有这种桌面退出控制能力。

**Turn历史单列保护**：旧GET /api/v1/threads/{thread_id}/turns读完整持久Turn历史，
不能被Execution的active_turn/recent_terminal_turn两项替代。其独立typed历史scope/分页
仍须保完整Turn、窗口内ThreadItem、ThreadContextDisposition及大Turn内继续cursor。
当前历史source是原只读history DB，缺失为空、不建库/迁移/激活；顺序last_ordinal降序，
原query默认50/clamp1..200、原页2MiB来源预算及DB/Thread/watermark绑定游标均记录为迁移
输入事实。新typed输出的精确字段/正文ref与预算适配未定稿前，不授权删除该历史能力。

所有新路由/请求/响应/错误/枚举在同router utoipa::path/ToSchema登记，不用body=Object/
String掩盖业务schema。SSE response的媒介虽是text/event-stream，文档必须给具体Frame
schema与ACK/close协议，不能只声称任意字符串流。删除的旧组件无消费者后一起删，不保
deprecated alias。基于OpenAPI的消费者升级说明由C同步最终迁移报告。

## 8. 仍需闭合

- [ ] Turn历史独立typed DTO/读取scope完整接缝，不能丢原历史窗口。
- [ ] 原StudioStateSnapshot.runtime的纯查询替代与server read生命周期；不能因删除聚合
      /state而丢runtime state/recovery/activeTurns，也不能为此启动另一runtime或暗加20th业务feed。
- [ ] 全部具名mutation/path/Request/ReplyOutcome逐项映射表、附件及新建进度运输。
- [ ] 各ReadKind具体typed methods与OpenAPI最终注册/删除及测试消费者矩阵。

本册尚不是整包放行。无编译/测试/生成/GUI；准确组件版本和实际取消行为仍在最终验证取得
证据。现项目锁定Axum0.8.9/Tokio1.53.3，复用现有Sse/ReceiverStream/mpsc/CancellationToken；
不以参考过的其它版本官方API文档冒充本版本已运行验证。
