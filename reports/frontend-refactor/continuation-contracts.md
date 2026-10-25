# 续做共享接缝决定

本文件只闭合当前真实缺口；v5 已定来源、预算、关闭与输入证据仍有效。Native、SDK、
adapter 各在自己的 owner 内实施，不因生成延期添加旧 facade 或 Noop。

## 1. 本次确认的原行为

- `AttachmentDraftRuntime::admit` 完整 batch 验证后才将 entries 发布；原失败清理忽略文件
  删除错误，必须补回真实责任。`remove` 的 `false` 表示已无 entry，不是失败。
- 原 `start_new_thread` sink 断开不取消执行，但没有客户端可加入的原任务句柄；普通
  `Failed` 不能在缺少提交阶段证据时一律映射为可重试拒绝。
- `CreatedInputExecutionSource` 接口、`ConversationDemand` 借用和
  `SubmittedInputObserver` 已存在，保留它们；不复制 receipt 或把 source 放进 Freezed。
- Clipboard stager/cleanup 继续采用原 v4 合同中的窄函数注入，复用平台临时文件能力，
  cleanup Future 必须传播真实错误。SDK 不导入 Flutter 或平台插件。

## 2. D1a 附件 ledger 的确定边界

先补独立的私有附件所有权，不等待 native binary 或新建句柄完成。复用现有
`ResourceBudget`、`ResourceKind.attachment`、`OperationId`、`DraftStamp` 与
`AttachmentMetadata`；不建立另一 budget、公共 store 或全局可变 Map。

- admission 开始前按 sources 数量保留附件额度；拿到完整真实元数据后同步转交为每个
  attachment ID 的具体 owner，再决定当前草稿是否仍采用。重复 ID、数量不符和迟到结果
  不能产生无 owner 空隙；已知 IDs 的清理必须逐项保留责任，不能只抛一个错误就遗失。
- 超量坏回复不能用一个 permit 背书任意多个已知 ID。可覆盖的额外 ID 逐个取得原预算；
  已存在却无法取得额度的 ID 作为明确的超额清理责任保留，不能声称已预算。出现这种
  责任时同步关闭本 ledger 的新增附件准入与外部 adopt，直到实际超额对象清理完成；
  原调用 join、已有引用结算、删除和关闭仍继续。报告保留超额身份/数量与 typed issue，
  不增加第二预算池，不静默突破限制，也不因 acquire 失败遗失回复剩余 ID。
- draft 引用与 operation 引用分别登记。冻结是同步动作，引用同一具体草稿/附件集合，
  不按拼接字符串偷换身份；同一 ID 的 metadata 必须一致。正文与附件双向版本关系由
  原 record 管理，ledger 不复制第二份可写草稿。
- remove/discard 仅释放当前 draft 的引用；最后一个引用释放后调用原 native remove。
  `true` 或 `false` 都表示该调用确定不再保有原 entry；异常才保留 issue、owner、permit。
- success 只释放原 operation 的冻结引用，且依据原 DraftStamp 清理仍属于它的草稿；
  新输入/新引用不受旧完成影响。拒绝释放原 frozen 引用但保草稿；Unknown 保留引用与额度。
- reservation 未取得确定结果不能当作没有 native 对象而释放。未知清理报告列出原
  operation/admission 责任；后续只能结算同一调用，不重发业务。
- seal 同步拒绝新准入；close 真正等待在途删除/迟到归属交接，显式 retry 复用原失败
  对象，不永久缓存可恢复失败 Future。不假定文件路径已删就是原读取已结束。
- CloseReport/FeedCloseIssue 按既有资源层表示，私有 cause 不泄漏到领域值/Driver。
  不能借 ledger 对外开放 publish、删除任意路径或释放别人的 permit。

此片不先发布缺失创建/提交依赖的 DraftsRepository factory；factory 在完整 command 与
context 接缝落地后组合这些真实 owner，不能为缺的方法返回 Noop/Unsupported 占位。

## 3. 后续 native 命令 owner 的约束

R2 将复用 Tokio task/结果通道与现有 `BackgroundTask` 的真实 join 机制；创建、附件各有
自己的具名 owner，不直接把不可取消业务当成可取消 feed。登记、结果查询、关闭分别
表达，不新增持久化 input 去重表。R1 通过审查后由同一 native writer 实施下面的最小接缝，
adapter 只在真实声明落盘后转换，不提前伪造 native owner。

创建成功时原 projection 的捕获与交接沿 v5 §31；原 ThreadFacetLease 可作为底层 pin，
但 cold/live 通用 opener 不获得“原创建源”的身份保证。成功 value 仍为现有
StartNewThreadResult，执行源查询失败单独保留，不改写业务成功。全局创建 gate 与原任务
终结绑定，不与 UI stream 生死绑定。

### 3.1 具名调用能力

Native 分别提供附件准入与创建的 begin/find 能力。调用方在首 await 前生成并冻结
`operationId`，begin 在副作用前登记同 runtime 的原调用 owner，重复 begin 不重放；find
只查原 identity，不创建替代命令。未找到只代表当时没有可查询 owner，不能据此证明
先前传输未到达。输入、来源与 receipt 沿原协议，不再计算一份 request digest。

SDK composition-only 能力形状：

```text
AttachmentAdmissionPort
  begin(OperationId id, AttachmentAdmissionContext context,
        List<AttachmentDraftSource> sources)->Future<AttachmentAdmissionJob>
  find(OperationId id)->Future<AttachmentAdmissionJob?>
  remove(String draftId)->Future<bool>
AttachmentAdmissionJob
  operationId:OperationId
  result()->Future<List<AttachmentMetadata>>
  requestClose()->void
  close()->Future<FeedCloseReport>
  retryClose()->Future<FeedCloseReport>

NewThreadCreationPort
  begin(OperationId id, NewThreadCreationRequest request)->Future<NewThreadCreation>
  find(OperationId id)->Future<NewThreadCreation?>
NewThreadCreationRequest {
  projectId:String,input:StudioPromptInput,mode:ThreadModeId,
  route:ModelSelection,workspaceMode:ThreadWorkspaceMode,
  delegationMode:DelegationMode,delegationPreference:DelegationPreference
}
NewThreadCreation
  operationId:OperationId
  projectId:String
  inputId:String
  progress:ReadonlyLatestValue<ThreadPreparationProgress?>
  result()->Future<StartNewThreadResult>
  executionSource()->Future<CreatedInputExecutionSource>
  requestClose()->void
  close()->Future<FeedCloseReport>
  retryClose()->Future<FeedCloseReport>
```

上述 job/source 是资源对象，不 Freezed；request 是冻结值，沿既有领域 model key/route，
不恢复旧 `NewThreadModelRoute` 别名。result 成功直接返回现有领域值；失败沿现有
`CommandDispatchFailure` 分类。native 仅在真实提交阶段证明未受理时给 Rejected；worker
未知结论、派发后无证据错误不能按错误码转换。成功后执行源读取/客户端同步失败单独
记录，不撤销成功，不伪造通用 CommitReceipt。

### 3.2 结果、资源与关闭

两类原生 owner 使用同 runtime 有界命令责任集合，共享 64 个未释放调用名额；此额度
不替代 read scope/read-call 配额，不能绕过原全局单创建 gate。只登记这两类业务及短
结果，没有任意任务插件、通用调度或新的持久化幂等库。原任务在 observer 消失后继续由
owner 真 join，结果发布必须在无接收者时也保留，不能用 `watch::send` 丢失终态。

requestClose 封新观察与源打开，不 abort 已受理命令；result 的原任务加入在 closing 中
仍有效。close 加入同任务、原 late open 和清理工作，不把拒绝/业务失败本身等同资源
清理失败；原业务错误与 close issues 都保留。成功附件 entries 交 SDK ledger 管理，不因
关闭结果观察就删除有效附件；未发布 batch 的残余路径仍由原 native job 保留并可重试。
找不到结果的 SDK reservation 不能自动释放或重发，native 退出汇总未结束责任后才 finalizer。

创建成功的 executionSource 由同一创建 owner 提供，只引用初始化时捕获的具体执行
projection；不按 ID 临时 open live/cold。source 打开的 feed 真持独立 pin，creation close
不关闭已交接 feed；未交接 pin 和打开失败归原 owner。SDK 在原证据需求需要期间保留
该具体 creation/source，不能随页面销毁或进度 stream 关闭释放。

FRB 用 opaque owner 与 typed outcome/result；HTTP 的原同步命令入口须加入同一 owner，
不能因请求断开取消已受理工作。新增可恢复查询按附件准入、创建各自具名路由暴露
begin/find/result/close/retry-close，创建进度是原 owner 的观察，不启动第二创建。
既有 Server 上传与模型准入限制不变，生产 native/Server 不能留旧无监督旁路。

### 3.3 HTTP multipart 的宿主暂存边界

R2 已核原 upload 只有在读取首个 context 字段并写完文件后，才取得包含实际临时路径的
完整 sources。这里选择宿主暂存与 native admission 分责，沿已批准 clipboard staging
边界；不向原生添加 pending-input、两阶段 reservation 或第二份 body digest。

- 原 `POST /api/v1/attachments/drafts/upload` 在 URL query 显式接收调用方 `operationId`，
  在消费 body／临时文件 IO 前登记原上传 owner。采用现操作身份非空白校验，不新增
  字符集、UUID 限制或原始值 trim；不用 HTTP header 的字符编码限制缩小操作 ID 域。
  multipart 的 context-first、file 顺序、16 文件、单文件 50MiB、总 body 200MiB、
  文件名处理及原 preflight 均保持，不增加可接纳 source 类型。
- 具名 Server 上传 owner 绑定原请求体资源和操作身份，持原 normal-request permit，
  不加 semaphore。只有完整 context／sources 冻结后才调用同 operationId 的 native
  begin；从此才占原 native 两类命令共享 64。native begin/result/close 仍是同一真实
  admission owner，不保留旧无监督旁路。
- Server 的上传、JSON admission、creation 操作身份在其具名 transport registry 中
  不得相互冒用。已登记上传 ID 的再次 upload 一律 Conflict，先于读取新 body 或创建
  文件；它表示新 HTTP 请求没有被接纳，不表示原操作被拒绝。即使 body 可能相同也不
  猜测相等，不重新暂存后比较临时路径，不将新 body 静默丢掉后返回旧成功。
- 恢复通过具名 `attachment-uploads` find/result/request-close/close/retry-close：
  请求以 typed operationId 寻找原 owner，只加入原任务。find 不存在不证明原操作拒绝。
  查询与关闭使用现 controls 名额，即使 normal/native 名额占满仍能恢复；无新的 body，
  不重算摘要、不重新 begin。具体 URL 采用可完整承载原操作字符串的 JSON 或 query。
- 上传 owner 在正常响应丢失后仍保留已知结果和清理责任；原同步 upload 返回仍加入
  这个 owner 的结果，不另启任务。原 request body 流若实际失败或被连接终止，结果按
  原任务阶段结算；未进入 native 的失败是已知未准入，进入 native 后不得按断连猜拒绝。
  不承诺恢复客户端尚未发送完的字节，也不继续读取第二份 body 来补原上传。
- 临时路径在 native 仍可能使用时不得清除。结果已知与 native 任务／文件使用真实 join
  后，宿主才清理原暂存文件；部分写入、late result、删除失败及原 native Unresolved 都
  由同一上传 owner 保留，close/retry 对原对象重试，不用 TempDir Drop 吞清理错误。
  成功 metadata 对应的 native draft entries 不因暂存文件清理或观察关闭而删除。
- requestClose 封新观察而不 abort 已登记 worker；close 真 join 暂存、native 及 cleanup。
  shutdown 封新上传，沿原绝对期限加入现有任务；若 runtime 已封原生准入，尚未提交的
  暂存任务得到真实未受理结果并清理，不能伪造 Accepted。既已登记的 native job 仍按
  原合同 join。超时保 Unresolved 及 permits，外部 issues 在 native finalizer 前汇总。

## 4. Models 来源前置与 feed 窄提取

R-Models 源码核查确认 v5 §35 尚未实现：ConfigRuntime 无全目录来源 metadata owner，
ModelsSnapshot 只有业务材料；旧 product baseline 临时构造 Ready 不可用于新 feed。
因此先由独立的 Config/source writer 兑现既定来源契约，再续跑原 feed 执行者，不生成假
sourceRevision/status ref，也不把 DTO 存在或 read scope 存在当作 feed 已可用。

该前置继续由 ConfigRuntime 原锁拥有唯一 `ObservedResource<()>` 或等价类型化 metadata；
初始化成功、真实发布和原关闭分别推进独立 checked 来源水位，不聚合账号探测。原
attach/publish 在同 guard 捕获 metadata 与业务材料。ModelsSnapshot 必须强持同次不可变
来源状态及真实 header/ref，原 current、未 ACK 与读取 scope 维持相应寿命；source 只提供
按原 origin/ref pin 的 weak 定位，旧引用过期明确失败，不重新读取 latest 填补。

最小共享能力由原 `ModelCatalogSource` 提供具名 `pin_source_status`，返回原状态材料；
具体材料类型与字段以执行者实际声明交接。不能把无定位/无寿命的 header 当作状态已可读。
Config/source 本轮不改 R1 冻结的 selection.rs 或 descriptor.rs，保留模型启用判断。

来源前置落盘后，允许 R-Models 在 models 内从 Templates 的私有窗口窄提取共用交付结构，
仅复用两未 ACK、一个 pending、sent/acked、claim 与原材料持有规则，不改 Templates 的
公共签名、预算或行为；变化范围重新静态审查。不新增通用消息总线/调度器。Catalog delta
使用上个已发送材料与当前原发布材料的成员 refs，不能假设现有 source 已提供并不存在的
previous/delta 方法，也不能按 poll 时的 latest 重建被合并掉的成员身份历史。

## 5. D2a 审查后的精确详情与导航裁决

### 5.1 复用原配对凭证，不拼独立 targets

`DelegationModelReadTarget` 改为 `sources: ConfigurationRoleReadTarget` 与
`model: AccountModelKey`；删除原两个独立 configuration/catalog 字段，不加旧构造或别名。
该 sources 是已经冻结的 Rust 配对凭证，包含原 `reference`、`configuration`、`catalog`
与 `ConfigProjectionStamp`；名称沿既有公共类型保留，不复制另一种 pair，也不让
roleRoute 代转模型详情或扩大到 ModeCatalog。

native 的后续 `openDelegationModelRead` 必须在原 Configuration 配对材料中核验全部
sources 身份及 settings/modelCatalog 双水位，再持原配置与目录材料。凭证匹配但材料
已过期仍失败；不得仅回显请求或从 latest 填补账号名/计费。SDK 检查凭证结构内部的
origin/ref/真实水位一致性、scope 对原 catalog 的身份与完整回显；native 不存在的证明
不能由 Dart 自签发。公开 UI 只消费 ConfigurationHeader 真实发布的 roleRead 凭证。

guide、performance、评价计数与最近窗口在该次原生详情 scope 捕获后不可变；只保证原
配置/模型捕获相容，不伪造性能/评价与配置的全局事务。精确 reader 保留最近评价最多10、
资料来源最多6的既有业务边界；实际原生 scope 未完成仍是明确后继依赖。

### 5.2 选择守卫同时核意图与原位置

`selectAgentThread` 的任何异步阶段均捕获原 selection 的 project/root/binding。每次
await 后及最终发布前，除了原 selectionGeneration，还要核当前 selection 仍属于该
原位置；目录/Thread移除触发的内部 fallback 即使未增加用户意图 generation，也使旧
Agent读取失去发布资格。不得依赖跨域事件原子到达。

成功与失败采用同一身份守卫：重新验证原 membership 的 origin/reference、成员实际
存在和原 root/project 归属，再发布当前错误或选择。过时成功/错误只结算原操作为
Superseded，不覆盖 fallback 或新选择；当前有效读取错误仍保持可见。

## 6. 创建证据源的真实 Execution 前置

R2 核查确认当前 ThreadFacetSources 只有 Metrics；Execution 的 protocol/FRB 类型不等于
真实 projection/feed，InteractionIndex 的声明也未被原观察 owner 实例化。因此由原
native writer 先完成独立的 R-E 单元，再做 R2 的创建句柄与原源捕获。不能用普通 live/cold、
Metrics 身份、空 InteractionIndex 或永久 Unavailable 代替尚未实现的 Execution。

R-E 在原 Thread observation/LiveOwner 发布边界维护真实 Execution projection，复用原
ThreadFacetLease、原 incarnation 与共享 read scopes/read calls；不创建另一执行 Thread、
第二观察 worker 或正文副本。基线/变更字段以现有 thread_facets/execution 与 v4 Thread
wire 合同为准，材料引用必须可由原 immutable pin 读取；来源未知不能填假 Idle/空集合。

同一单元闭合 Execution 所需的 Turn、InteractionIndex/Interaction、Activity、Storage 等
既定具名读取及原来源绑定，再提供实际两未 ACK 的 runtime、FRB 和 HTTP feed。Execution
遵守 v4 wire §4 的可靠 FIFO64/8MiB、单 Data256KiB，不采用 Metrics 的 latest 覆盖。
运输仅借出一个待发槽，仍计入同一可靠待发帧数/字节责任，不能在 FIFO 外叠第二队列。
原源按实际顺序保全 Turn 终态、Interaction 决定与 terminal facts；lag、队列溢出或 gap
显式 ResyncRequired 后停止 Data，满窗不阻塞 ACK/query/取消/唯一控制终态。
Turn 完整历史沿已有公开历史能力有界查询，不能以 active/recent 摘要替代；其它 facet 的
未实现能力单列后继，不为当前单元制造空 ref。

对后续创建 owner 发布的借用必须接收具体原 observation/projection 身份，成功初始化时
取得而不是事后按 ID 查 current。该能力只 pin 已有源，不 ensure/激活；打开 feed 取得
独立原源 pin，保相同 epoch/incarnation，close 真 join。R-E 发布实际类型/函数后，R2 再
把它交给 CreatedInputExecutionSource。R-E 不顺带实现尚未交付的其它产品域或命令任务。

## 7. Binary 描述符失败与关闭身份分离

A1 审查确认完整 identity 的 u64→Dart int 转换失败时，下层已按 raw scopeId 验证 Clean，
SDK 原 wrapper 却重抛旧 identity error，造成 permit 永久未释放。修正只涉及二进制读取
的窄接缝，不放宽 query 校验、不改通用 PinnedReadOwner 或伪造元数据。

`AttachmentBinaryRead` 增加稳定的 `scopeId:String` getter，值只能来自同一 native handle
的原 identity.scopeId；即使其余 descriptor 不能转换，该值仍可用于关闭，成功关闭后也
可读取保存值。查询同时核 typed identity 的 scopeId 与该值一致。scopeId 缺失/非法时不
从 close report 倒推；adapter 保留 handle，显式关闭重试可向原 handle 重取 raw identity。

SDK wrapper 真正调用 close/retryClose 后，以这个独立原标识核 report.feedId；不能因
此前完整 descriptor 的查询错误拒绝一个身份匹配的真实 Clean。若关闭期间 adapter 才
恢复 raw identity，可以使用它保存的同句柄标识完成核验；不是把 report 值当期望值。
raw 身份仍不可得则继续 Unresolved，不能提前 dispose。A1 的 query failure 继续向调用方
传播原错误，SDK 原读取 scope 的失败记录与已完成清理分开。

D1 仅改 binary port/读取 owner，A1 仅改对应 adapter；已审 D1b 五文件与 ledger 不变。
后继 C 增加/复用公共 Drafts 读取行为中的不可表示 incarnation→读取失败→真实关闭释放，
以及 raw identity 读取暂时失败→同 handle retryClose 恢复的证明。

## 8. Start 专用原配置／目录读取

root 已核旧 HEAD 的 `ModelRouteQueries.modeRoute`、`overlayStartSessionRoute`、
`StartSessionDraftOwner.setModelIntent/_freezeRoute`，以及原生 `RuntimeConfig.mode_model_route`。
本节闭合 v5 §23/28 留下的未决项，不在 Dart 搬回旧 resolver，不将 mode 填入 roleId。

### 8.1 来源与公共形状

Configuration 的原配对凭证 `ConfigurationRoleReadTarget` 可证明同次配置／目录材料；
复用凭证，不复用 roleRoute 方法。增加独立具名 Start read scope，归 Configuration：

```text
StartRouteIntent {mode:ThreadModeId,model:AccountModelKey?,effort:String?}
StartRouteQuery = resolve{intent:StartRouteIntent}
  | selectModel{intent:StartRouteIntent,selected:AccountModelKey}
StartRouteRead = ready{sources:ConfigurationRoleReadTarget,
  query:StartRouteQuery,intent:StartRouteIntent,route:ModelSelection,
  defaults:DelegationSettings}
  | unavailable{sources:ConfigurationRoleReadTarget,
    query:StartRouteQuery,intent:StartRouteIntent,desired:ModelSelection?,
    defaults:DelegationSettings,error:StudioFailure}
ConfigurationRepository.readStartRoute(
  {required ConfigurationRoleReadTarget sources,required StartRouteQuery query})
  ->Future<StartRouteRead>
ConfigurationPort.openStartRead(ConfigurationRoleReadTarget sources)
  ->Future<ConfigurationStartReadConnection>
ConfigurationStartReadConnection
  header()->Future<ConfigurationRoleReadTarget>
  resolve(StartRouteQuery query)->Future<StartRouteRead>
  requestClose()->void
  close()/retryClose()->Future<FeedCloseReport>
```

值归 Configuration domain，不含 opaque、Future 或正文；资源连接不 Freezed。native
按 sources.reference 定位原 pair 并核全部 target/stamp，query/结果完整回显，过期明确
失败。scope 复用原 Configuration 的 8/64 与真实关闭；不会顺便读取 latest ModeCatalog、
保存配置、probe 网络或初始化 Thread。默认分发设置来自同一原配置材料，不跨读 latest。

### 8.2 精确保留的路由/编辑规则

- base 为配置中该 mode 的 route，否则 mode.simple；不使用首个模型替代缺失 base。
- resolve 使用原 intent：完整显式 model 优先，否则 base model；非空 effort intent
  优先，否则仅在最终 model 与 base 相同时继承 base effort；剩余空 effort 取该原模型
  canonical 默认。非空 effort 不被此查询自动“修正”，严格创建校验仍归原 native。
- selectModel 是无副作用的本地编辑建议：previous model intent 非空时，比较它与 selected；
  否则比较 base model。真实换模型时复用原 Models effort 建议（candidate=null），返回
  规范化后的 effort intent，无建议/空值则清掉该 mode 的 effort intent；未换模型保留
  原 effort。返回的 intent.model 始终是 selected，不自动写任何配置。
- 模型不存在/禁用、完整 route 不可得返回 unavailable，保留真实 desired 与原编辑意图，
  不虚构 first、enabled 或 Idle。来源失效、协议错误、读取故障则真实失败，不与已知
  unavailable 混淆。字符串空值及未 trim 的原始 effort 语义不扩大，不新增候选类型限制。
- 不需要 ModeCatalog 配对：原规则只读 mode 标识/配置路由/Models。实际 mode 创建准入
  继续在原命令边界检查，与原行为一致，不能声称查询冻结了 Mode 定义事务。

### 8.3 Drafts 物化与同步提交

StartDraft 增加显式 `prepareRoute()->Future<void>`，其具名只读路由准备状态由同一 draft
owner 持有。初始读取和失败重试由可见需求/明确用户动作调用，不在 getter/build 中开源，
不轮询。setMode/model/effort 编辑使原准备结果同步失效；显式 model 选择使用 selectModel
请求，随后只在原编辑意图仍最新时采纳返回的规范化 intent。手动 effort 后到时不能被
较早 model 建议覆盖。来源变化使结果过时，但不清 raw 编辑或把 defaults 复制为覆盖。

准备状态必须保原完整 sources/query/intent 和最后已知结果身份，区分尚未读取、读取中、
已知不可用与读取失败。可并入 StartDraftState 的具名 Freezed 状态，不复用 creation 的
preparation 进度，不另建全局 resolver/store。具体私有去重按原 key，不永久缓存失败。

submit 首 await 前只消费当前 sources 与 mode/本地 route intent 相容的 ready 结果，
同步冻结 route、overrides 对同一 defaults 的解析及其余原提交字段。尚未物化或已过时
不能先排异步 resolver 再补“冻结”结果；保草稿并返回明确未受理。之后配置变化不能改写
已发送的完整 route，原 native 仍做真实受理检查。此新增公开动作及状态由 D2/D1/A/U/C
同一轮迁移；本节不声称 Configuration 的 native 配对 producer 已经实现。

## 9. Configuration 原生单元与共享文件所有权

Configuration 是 Start、账号编辑、角色查询与精确模型详情的实际前置。下一原生单元
先完整实现 Configuration（Profiles 独立来源仍另行迁移），消费已经批准的 Models
capture/status，不复制模型策略或另一全量 Settings facade。

- 原 ConfigRuntime 同一提交锁内捕获不含密钥的 Configuration 材料、集合成员身份、
  原来源 metadata 与相容的 Models 引用；同 ID 删除重建必须新 entry，不能靠 watch
  消费时的 latest 重建。复用 S1 的原发布/锁外通知与有界 pin 模式，业务/来源/投影水位
  各自独立，不改 S1 Models 来源的已定语义。
- 角色/Start/模型资料查询共同消费同一个 Rust-issued 配对材料凭证，但每类 query
  保持具名接口与权限；pair 持原两份不可变材料，只有 current、未 ACK 或实际 scope
  承担强引用，不引入无界 pair 历史。任一捕获失败真实报告，不发布伪相容 pair。
- Source/frame/read 字段以现 SDK Configuration header、reads、pages 与 commands 的
  已冻结 typed 声明为闭包，包括 enabled/billing/disabledModels/delegation 与凭据存在性；
  只开放无密钥字段。嵌套列表、长文本仍按原 typed scope 分页/UTF-8 读取，不 raw JSON。
- 可靠性、8 个 product scope、64 个 read calls、2 未 ACK 与材料 pin/close 沿已有机制。
  可把已提取的 delivery window 窄开放到 runtime 内部供 Configuration 复用，不复制
  第三套窗口，也不改 Templates/Models 行为；该可见性增量纳入本单元复审。
- 范围内 Rust 配置命令保持真实 CAS/OperationId/失败分类，并返回原提交捕获的资源
  target，不把 latest 取回的 target 冒充该命令来源。旧原业务持久化与权限语义不改。

新的 runtime、protocol、FRB、Server Configuration 模块由同一 writer 实施。与 R-E
重叠的根 runtime/lib/builder/shutdown、根 bridge products/module、Server router/exit
注册由 root 串行接入；执行者交准确初始化与退出挂接形状，不并行编辑这些共享入口。
局部模块审查不代替 root 的实际注册和最终消费者验收。

### 9.1 审查修复：配置命令调用资源与回执材料交接

首轮审查确认纯 `Future<ConfigurationCommandReply>` 不能承接原提交材料的寿命：SDK
在 port 返回后才同步 Configuration／Models targets。改用具名调用资源，保留纯回执
类型，不把句柄放入 Freezed。八个 configuration mutation（不含 Profiles/reload）改为
返回 `Future<ConfigurationCommandCall>`，并提供只查原调用的 find：

```text
ConfigurationPort.findConfigurationCommand(OperationId operationId)
  -> Future<ConfigurationCommandCall?>
ConfigurationCommandCall
  callId:String
  operationId:OperationId
  result()->Future<ConfigurationCommandReply>
  requestClose()->void
  close()/retryClose()->Future<FeedCloseReport>
```

`result` 的已知拒绝／未知／已提交未观察仍沿现 `CommandDispatchFailure`，不按普通
error code 猜阶段。callId 是原生／运输 owner 签发的独立资源身份，close report 的
feedId 使用 callId，不使用可跨 CAS attempt 保持的 OperationId。回执 OperationId
仍必须等于原写入身份；两个时钟、target 和业务失败语义不变。

begin 的明确 Rejected 只表示该次准入没有创建 call；已登记调用的业务拒绝通过
`call.result()` 返回并承担真实关闭责任。adapter 只将明确的原生准入错误或对应 HTTP
结构化拒绝响应归入前者；丢回复、网络异常和句柄/result API 错误不据普通错误码改称
业务拒绝。无 call 的准入拒绝不制造 Noop call，也不 find 后关闭冲突请求的原 owner。

- 原 Rust commit evidence 将同次 `ConfigurationSnapshot`／pair（连同 Models material
  与 ModelsSnapshot/status）强持交给原调用 owner。typed wire result 仅序列化值；
  call owner 在明确关闭前保 pin，不以 task 已完成、watch 已读或一次 reply 构造结束
  释放。不能改成 source 的无界强历史或事后 current 查询。
- SDK 原 `ConfigurationWriteJob` 在 await begin 前登记调用责任，接回原 handle 后取得
  result，再同步两个原 target。只有当前业务结果已得到相应观察，才安排调用清理；
  未确认的原查询、late open、同步失败及 cleanup issue 都保留原 owner。结果获取、
  canonical 同步与 cleanup 各自结算，cleanup 失败不撤销已提交事实。
- 已知 Rejected 的 CAS 重试先真实关闭上一 call，再重新捕获本次 CAS 请求；OperationId
  不变、新 callId 不同。旧 cleanup 未解决时停止自动重试，不能在同 ID 下换 owner。
  Unknown 或已提交未观察不重新 begin；丢失 begin 回复只可 find／加入原结果，find
  为 null 仍保未知，不按缺失证明未派发。关闭应用时也只加入原工作，不重放业务。
- adapter 返回 call 后由 SDK 持有；不得在 `result()` 返回前等待 SDK 消费 target，
  也不得用 finally 在返回回执时提前 close。不能为未实现生产接缝制造 Noop call。
  reuse 原 ResourceLifetime/操作额度；不把调用当 read scope 重复收费或加 semaphore。
- 整体退出封闭普通读取/源后，迟到结果可能是已提交但未观察；这不是允许假 observed、
  重放业务或重新开放全局 reads 的理由。继续按原退出图加入执行与清理，保留各自真实
  结果，未解决问题进入 Degraded。SDK 单域关闭与 native 整体退出分别验证；仅调整
  Dart lifetime 不证明能越过 native 的准入 fence，不额外引入未批准的消费 lease。
- HTTP 与 FRB 都在原任务注册边界按 OperationId 和完整冻结请求查重；同请求加入原
  owner，不消耗新 normal permit，不启动第二 worker。只有新调用取得原额度并原子
  登记；并发首发不能变成非原子预查。opaque 丢失不能自动遗弃仍需 find 的结果。
  FRB 的索引属于该真实 bridge/runtime，而非全局静态缓存；监督复用原 BridgeTaskRegistry。
- 结果／关闭按 callId 定位，find 按 OperationId；旧 callId 不会指向新 attempt。
  `requestClose` 封新观察而不取消已受理 CAS，真实 result/worker 与清理 join 后才
  释放对应资源；Unresolved 留原 call/issue/permit，可重试。
  FRB/HTTP 的 result 查询须与同一关闭 fence 原子登记；只封后来的准入不能代替等待
  已接纳 waiter。close/retryClose 真正加入 producer 和这些查询完成/取消后才释放
  evidence/permit。等待关闭者自身被取消也不能丢掉原 owner 的收束责任，不增池或期限。
- 单次公开 `retryCleanup` 对同一 call 只有一次 native `retryClose` 尝试。写 lane 与
  lifetime 对同一责任的收束应合并本次尝试，而非在一次失败返回后立即再次重试；同时
  仍要执行本轮其它独立 read/feed owner 的真实清理，不能为了去重跳过它们。
- 身份加入保证限定在原调用仍留存期间。客户端不得在 clean-close 后复用旧 ID 提交
  另一意图；known-Rejected 的同意图 CAS retry 是已定义的例外。close 是资源生命周期
  行为，不是允许重放的业务证明。系统不承诺固定内存、任意 String ID 下的无限期
  全 runtime 去重，不增加永久 tombstone 或持久去重表，不以 LRU 淘汰伪造该承诺。

上述澄清取代首轮 handoff 中将 clean-close 后状态丢失等同“允许安全重放”的不完整
表述；Unknown 不自动重发、保留原操作及真实提交证据的既有业务要求不变。Profiles
与 reload 的原 source capture 前置仍独立，不为本次八类 mutation 加假 Profiles target。

## 10. Profiles 原来源与具名读取前置

本单元先补独立 Profiles source/feed/read，不把未完成的 Profile 命令或 reload 包装为
Noop call。SDK 现有 `AgentProfilesFrame`、header、entries/entity/lookup、profiles、
diagnostics、text 与 source-status 的声明是接口闭包；系统与用户 Profile 的完整值、
nullable effort、原文、排序和诊断均保留，不为传输收紧 ID 或正文。

- 事实源仍是 `AgentProfilesResource` 的原扫描缓存；在初始化与原 `adopt_scan` 采用
  边界捕获不可变材料、集合/成员身份、来源 metadata。订阅先登记再返回当前值，通知
  锁外发出；不能由后续 watch latest 拼成员历史。同 ID 在已采用结果中消失后再出现
  必须新 entry，普通内容更新保 entry；无内容变化不伪造业务 revision，所有新水位
  检查溢出而不复用最后水位。
- 原扫描诊断属于被采用材料：不存在目录仍是合法空用户目录；目录/文件读取、解析及
  校验问题保原诊断及其已能证明的结果，不额外推导 provider 探测状态。初始化成功采用
  原材料才发布 Ready，关闭发布 Stopped；投影捕获失败与预算/运输错误独立显式报告，
  不把捕获失败当正常空集合，不因有逐文件诊断丢弃原诊断文本或重新扫描。
- Source、profiles business revision、projection stamp、collection/entity revision
  各自表达自己的变化。source status 只读同次捕获的 metadata，不借 Configuration
  或 Models 的状态冒充 Profiles；公开 `openSourceStatus` 按真实来源路由，不能仅按
  entry 字符串猜域。所有 origin/ref 都由原生签发和核验。
- 复用现有 product 的 8 scopes/64 read calls、`DeliveryWindow` 的两未 ACK/一 latest、
  field table、最终 JSON 256KiB 与分页/UTF-8 文本规则。只 current、未 ACK、实际 scope
  和真实命令调用持原材料；历史定位不强留。每类真实 open/query/stream 都有原 owner
  和 late-open/close/retry join，不新建 semaphore、通用框架或第二份可写 Profiles。
- ConfigRuntime 的原命令/reload 结果须能携带同次 Profiles 捕获证据，为后继三 target
  消费提供原材料，而非事后读 current。先提供该证据不等于已完成公开命令调用资源；
  后继再统一定义并接通保存用户 Profile、系统 enabled 和 reload 的结果消费/关闭链。
  reload 不伪造不存在的 CommitReceipt，显式 reload 的外部目录扫描也不声称文件系统事务。

实施写范围沿当前 Configuration 原生 writer 的既有目录：config 内 Profiles capture、
runtime/configuration 内独立 Profiles 模块、protocol/products、bridge/products、
Server/configuration；Profiles 保独立 source/origin，不因模块归组混成 Configuration
事实。runtime/lib/builder/shutdown、BridgeRuntime、Server 根注册仍由 root 串行接入，
R2 被审期间不改其共享根文件。Dart、tests、生成、产品其它领域不在该前置单元内。

root 接入时将 Configuration／Profiles 的 `finish_close` 放在原统一 finalizer 已满足
Clean 前置的分支，不仅依据 `close_detail_reads` 的局部成功。原 hooks 对 reads/scopes
Clean 的要求仍必要，但外部 HTTP/FRB 未收束 issue 同样必须阻止材料最终释放；不新增
finalizer、期限或成功状态，也不因此改动既有 Models/Templates 的独立实现。

## 11. Thread Authoring 原投影与读取

R2 完成后的原 native writer 下一单元只补 Authoring，不同时扩大为 Context／Thread
Configuration。三者不同于产品 Configuration／Profiles，不能因为同名误认已有 producer。

- 复用原 `ThreadObservations`／`LiveOwner`、原 ThreadHandle、冷 checkpoint 与 read
  group。基线取该次捕获，后继从原 committed ThreadWrite 的扩展变更和 checkpoint
  投影；不按字符串 ID 重新查 current owner，不从 watch 合并后推可靠变更。
- canonical 键为 `pl.tool.todo`、`studio.plan`、`studio.workflow`，沿各自版本化
  decoder；缺失即 None，移除明确 Replace(None)。Plan／Workflow 的领域 revision、
  Todo 的原 extension revision、facet revision 和 delivery sequence 分开。只有原
  delivery/payload 身份可证明时才提供 Todo callId；读失败不默认空成功。
- Authoring 采用可靠 FIFO64、源队列 8MiB、最终单 Data 256KiB、两未 ACK（含 baseline）；
  唯一队列不在 FRB/HTTP 再堆一份。lag/full/gap 发一次 ResyncRequired 后停 Data，
  ACK/close 控制不被满窗堵塞。仅实际发送才暴露对应引用，旧 origin 不借未发送的新材料。
- 公共闭包是既有 AuthoringFrame/briefs、SDK `openThreadAuthoring` 与 Todo/Workflow/
  PlanDocument 具名 reads；原文、列表与 nullable 值保持。复用 Thread 共享 8 scopes、
  ReadCalls64、现 FieldTable/page/text 最终 JSON 预算。scope pin 原不可变材料，Plan
  document 核原 version/hash；不能按最新 Mode 或后继文档拼旧 ref，不扩展写权限。
- 快照中的冻结 Mode 元数据只有在 Mode ID、graph revision 与 graph hash 都匹配原
  Workflow run 绑定时才可用于展示。同 ID 的图更新可能保留旧 run，不能仅以同快照或
  state ID 相同就用新图标题/名称填旧 run；不匹配时保留原 run 信息，不查 latest 或重编译。
  若外部来源更新确实影响既有
  Workflow 投影，沿原 retained 来源通知捕获真实变化，不重传无关 Plan 正文或唤醒
  Metrics。progress 只暴露协议当前真实能力，不把工具活动猜成新增 progress writer。
- feed/read/transport 的关闭沿原 source/lease/ThreadReadGroup、BridgeTaskRegistry
  和 HTTP typed controls，加入真实 producer/sink/query/late-open；Unresolved 保原
  owner/issue/permit。source 关闭不是关闭 Thread，也不影响已经独立交接的其它域。

本单元包含 native capture/feed/reads、FRB 与 HTTP 的真实领域能力和必要 operation
声明；Dart adapter 后继消费，不为其它 facet 方法塞 Unsupported。产品 Configuration/
Models/Profiles、Drafts jobs、SDK、生成和测试不在本单元。root 正修改的 11 个根挂接
文件保持单 writer，由本单元交准确模块/初始化/路由/退出 hooks 后串行接入。

## 12. Profile 命令与 reload 调用资源

§10 来源/读取前置批准后，补齐剩余三个配置意图。保持现有 Repository 业务动作与
Profile 资格、内容、CAS、凭据和 reload 行为；只替换 port 的资源交接。已完成的八类
ConfigurationCommandCall 不改成带可空字段的全域回执，也不为代码复用伪造 reload receipt。

```text
ConfigurationPort.saveProfile(SaveProfileRequest) -> Future<ProfileCommandCall>
ConfigurationPort.setSystemProfileEnabled(SetSystemProfileEnabledRequest)
  -> Future<ProfileCommandCall>
ConfigurationPort.findProfileCommand(OperationId) -> Future<ProfileCommandCall?>
ConfigurationReloadRequest { operationId:OperationId, expectedRevision:int }
ConfigurationPort.reload(ConfigurationReloadRequest) -> Future<ConfigurationReloadCall>
ConfigurationPort.findConfigurationReload(OperationId)
  -> Future<ConfigurationReloadCall?>
ProfileCommandCall / ConfigurationReloadCall
  callId:String, operationId:OperationId
  result() -> Future<ProfileCommandReply / ConfigurationReloadResult>
  requestClose(), close()/retryClose() -> Future<FeedCloseReport>
```

- 三种调用种类沿原 Configuration registry 的封闭 typed request/result 分支和窄 wrapper
  组织；不新增 BridgeRuntime registry 字段、任务池或 semaphore。OperationId 对完整
  kind+冻结 request 原子 join/conflict，跨种类不能冒用，同请求满 normal pool 仍可加入。
  callId 唯一标识一次 attempt，结果/controls 只作用于原 call；typed result 入口核种类，
  不把错误种类的回执强转。find 只恢复原 live call，缺失不证明未提交。HTTP/FRB 的具体
  具名入口保持同一闭包，运输不另造业务状态机。
- Profile 正常结果是已有 `ProfileCommandReply` 的真实 receipt 与三个原 target。
  已知保存后材料曝光或 followup 失败保 receipt／原 capture，以 CommittedButUnobserved
  表达，不撤销保存；若已能确认文件写入成功、却尚不能构造真实回执，则另用 typed
  `ConfirmedWithoutUsableReceipt`（原 operationId 与错误），不伪造配置 revision/receipt。
  reload 正常结果仍只有三个 target；原采用已确定但没有可用结果时
  以独立 typed `AdoptedButUnobserved`（带原 operationId 与错误）交付，SDK 映射现有
  confirmedWithoutUsableReceipt 失败状态；正常的“本来无 receipt”不是错误。
- 原子 Profile 文件 writer 不变：原字段/路由验证、TOML 编码与写前准备在原提交边界
  分期；一旦调用可能替换目标的 atomic writer，其普通错误保守归 Unknown，不猜 rename
  或目录同步是否已发生，不重放或回滚目标文件。写入成功而后续 state/capture 失败同样
  不倒退为 Rejected。系统 enabled 复用现 typed settings mutation 阶段，另保系统角色
  限制；reload 的采用点由原 state 替换证明，采用前已知校验/CAS失败才是 Rejected。
- 原结果 owner 强持原 Configuration／Models 配对和 Profiles snapshot/capture failure。
  从这份 evidence 暴露原三个 target，不在 followup 后读 current；捕获失败不能补一份
  latest 或假 Profiles target。已有来源关闭时如实未观察，不复活普通 reads。
- SDK 在首次 begin await 前保存完整 typed request 与原调用责任；Profile 的 receipt
  及三个 target、reload 的三个 target 都实际同步后，才完成相应 observed 并清调用。
  reload 继续用原 SDK operation 关联，不制造原生 CommitReceipt。明确 stale CAS 拒绝
  仍沿原有限同意图重试，先 Clean 旧 call，再新 request revision/new callId；reload
  无 receipt 不意味着可以绕过这条清理边界。Unknown/采用后未观察不自动重发。
- 接回 handle、result operationId、targets 和 close report 逐项核验；begin 明确
  Rejected 仅未建 call，已登记业务拒绝从 result 取得并清理。只复用原 job/owner 的
  私有共有机制，不扩大公开 God facade。资源关闭、单次显式 retry、整体退出的真实
  Unresolved/Degraded 语义沿 §9.1；未知结果与资源清理结论分别保存。

实现仍由原 Configuration native writer 与 SDK D2 在互斥目录完成；D2 先完成当前
重复 cleanup retry 修复并静态复审，再迁这三个 port。C 与生产 adapter 随稳定接口
顺序迁移。root 共享根文件保持单 writer，新字段或改变整体退出图不是本单元默认授权。

## 13. Models 精确详情的原资格材料前置

§5.1 的配对 pin 已由原 `ConfigurationSource.pin_pair` 实现；Models runtime 子模块可
直接使用它，不因父模块字段私有而另加转发 wrapper。配对中的 ConfigurationValue 和
ModelsValue 是无密钥投影，原 ModelsSnapshot 也不是完整 ConfigRuntimeSnapshot；因此
不能把 `hasBearerToken` 或展示 descriptor 当作旧 execution admission 的等价证明。

- 沿原 ConfigRuntime 的 Models 捕获边界，以该次有效配置及原有效模型成员执行既有
  delegation model admission。与旧查询共用同一具名判定，保持原默认 effort、连接
  override、启用、文本类型、协议凭据和工具能力规则；不在 Dart 或新 scope 重写策略。
- 只保存按原 account/model 绑定的最小资格结果和既有不可用原因，不保存 token、
  完整配置快照、已解析 endpoint/route、任务或新 registry。普通资格拒绝仍是成员
  `available=false` 的事实，不令整个 Models 来源失败，不隐去该成员。
- 资格材料随原不可变 Models material/pair 保活，参与既有业务/账号材料相等性与版本
  推进。即使展示 DTO 没变，资格变化也不能复用旧 material；同 ID 删除重建仍取得新
  entry。来源状态、水位、锁顺序和 weak 历史定位的既有责任不变。
- 精确详情从原 pair 读取该资格、账号名、计费及原 descriptor。guide 使用原配对的
  catalog 身份和原有效成员，保持 Bundled/非 Manual 的旧条件与最多六来源；不得
  latest 补齐。性能和最近最多十条评价仍在本次 scope 打开期间独立捕获，不伪造全局
  事务或以任意后来的 summary 替换原窗口。
- 本前置只补原材料，不等于详情 scope、protocol/FRB/HTTP 或生产 Dart adapter 已
  实现。后继继续复用原 Models 的 8 scopes、全 runtime 64 read calls、具名字段/
  分页及预算；打开在首次等待前登记，关闭真实 join，不增加平行池或通用读取框架。

原资格判定的共享提取由 root 串行维护；Models 捕获扩展与在途 Configuration/Profile
writer 的文件所有权分开后再派发。不得因运行期共享同一来源就让两个 writer 同改根文件。

## 14. Models 精确详情的具名读取闭包

资格材料前置批准后，沿 §5.1 的原配对提供
`StudioRuntime::open_delegation_model_read(DelegationModelReadTarget)` 与独立
`models::StudioDelegationModelRead`。target 的 `sources` 复用
`ConfigurationRoleReadTarget`，`model` 复用现有 account/model key；不增加第二种配对
凭证，也不以旧聚合 detail API 为 fallback。scope identity 属于原 catalog origin/ref，
并完整回显已核验的 target；回显本身不能替代原 pair pin。

- protocol 的 `products::read::delegation_models` 对齐现有 SDK 的
  DelegationModelReadHeader、ModelSelectionGuideRead、ModelSelectionSourceRead、
  ModelSelectionMeasurementRead、AgentEvaluationRead 及两种专用分页值。复用既有
  ModelDescriptorRead、ReadText、TypedListRef、性能/评价摘要和枚举，不复制新计费/
  评价类型或把长 comment/guide/标识文本塞入无界 header。
- 读取提供稳定 identity/target、header，现有 Models 的 text/strings/type support/
  exclusions/connection modes/input capabilities/input sources/modalities/price tiers，
  以及 selection sources/evaluations 两个具名分页。字段和列表 ID 只属于本 scope；
  默认页/文本块及上限、最终 JSON 预算沿既有 Models 契约，不扩大输入或静默截断正文。
- opening 在原 ReadCalls 登记后才进入异步取材；先 pin/验证完整 pair，再从该材料
  选原 account/model，捕获一次 guide/performance/evaluation。评价摘要只从同一
  最近窗口计算，保既有排序与最多十条，不另查后来 summary；性能未知语义不改。
- 新 scope 与 catalog/source-status 共用原 ModelCatalog 的八个 scope 配额及 runtime
  ReadCalls64；requestClose 同步封口，close/retryClose 真正 join 原查询/打开，失败
  保原 owner/material/issue，不重开相同 ID 的 current。Templates 与既有 catalog
  读取的语义、预算和选择建议不因复用而改变。

root 先维护共享 DTO 与必要模块声明，原 R-Models 只负责 runtime/models 内实现；FRB、
HTTP 与生产 Dart adapter 随该实际接口稳定后衔接，各根文件继续单 writer。未接完运输
或尚未统一生成不由一个局部读取实现的完成声明替代。

## 15. SDK 操作的额外显式观察门槛

三目标回归确认：Profile 的真实 receipt 只有 Settings/Profiles stamps，普通配置
命令的 receipt 只有 Settings stamp；Models 仍是 reply 中必须同步的原 target。
不能为此篡改 receipt、补签 stamp、延迟保留真实提交证据或在 UI 另造 ticket 遮罩。

```dart
OperationWriter<T> begin<T>({
  required String target,
  DraftStamp? draft,
  bool requireIdentityObservation = false,
});
```

- 此参数是原 SDK operation 登记时不可变的附加要求，在发布初始操作前冻结；不是
  改写 `CommitReceipt.requiresIdentityObservation`。有 receipt 时，须同时覆盖其
  原 targets，并在任一身份观察要求存在时取得真实 `identityObserved()` 证据。
- 复用原 writer 的身份观察信号，不新增公开 writer 方法、状态值字段、第二 registry
  或另一份 ticket。默认 false 保持其它领域原行为；native receipt 自己的要求仍有效。
  无 receipt 的状态仍只由真实身份观察推进，不因默认 false 而自动 observed。
- Configuration 的共用 begin opt-in true，覆盖八类配置、两个 Profile 意图及 reload。
  原两/三 targets 全部同步且原 call 标记已同步后，正常首次结算或原结果恢复才可发布
  identityObserved，再 accepted/acknowledged；错误、部分同步与普通 feed 覆盖不能发布。
- 已提交但观察失败时立即保原 receipt/已确认阶段，公开 observed 和 pendingOperation
  责任仍等待完整证据。恢复只加入原 call，成功后可推进 state，但不改写已交付的首次
  Unknown/SyncFailed 结果或诊断。CAS 被拒绝的 attempt 不发布证据，原 operation 的
  要求跨同意图重试保持，不新增每 attempt 状态机。
- 若某操作同时有原生身份 predicate 和 owner 附加义务，发出同一信号前必须全部满足；
  本修复不改变 Drafts/Conversation 的原生输入身份、effect 或 durable 证明。

共享 Operations 接口/判定由 root 单 writer 先接入，D2 只在原 Configuration 成功结算
边界 opt-in/发布证据；两部分联合复审。测试保持原 receipt，并分别证明 pre-covered 与
late-covered stamps 不绕过门槛、正常无 receipt 及原默认行为不变；所有执行仍统一延期。

## 16. Drafts 原输入的 pre-ACK Turn 证据

源码调查确认 `SubmittedInputObserver.considerTurn` 没有生产调用，现有 TurnBrief 不含
inputId；公开 `Session.openTurn` 受 UI demand 限制，不能供 UI 已退出或仅创建 source
存在的提交观察使用。原 `ThreadMirrors.applyExecution` 已有可 await 的 ACK 前交接，
此次扩展原提交 lease 与该交接，不另造 bus、observer registry 或镜像缓存。

原 `SubmissionExecutionLease` 增加以下 composition-only 能力，保留现有 ready/execution/
release；不扩大普通 Session 的公开 UI 准入：

```dart
void bindExecutionTurns({
  required Future<void> Function(
    SubmissionExecutionLease original,
    ThreadFacetStamp origin,
    List<TurnBrief> turns,
  ) consume,
  required void Function(StudioFailure failure) onFailure,
});
Future<TurnReadScope> openTurn(
  TurnReadRef reference, {required ThreadFacetStamp origin});
void requestCloseTurnReads();
Future<CloseReport> closeTurnReads({DateTime? deadline, bool retry = false});
```

- 一个 lease 只绑定一个消费者；消费者及其失败通道在首次交接前同步就位。保留原
  `_evidence` 集合和原具体 owner，旧 epoch/incarnation/attempt 不借新 owner 继续取证。
- 每个 Execution delivery 先冻结本次 active/recent 引用，去重最多两条，不把 await 后
  的 latest 读作本帧。空列表也交接来源身份。沿原 mirror handoff 等待本次有界处理后
  才 ACK，不等待 future Turn、ticket 或该帧 handoff 之后的 ready。
- `openTurn` 只接受原 lease 当前交接中的 origin/ref；复用原 TurnScopeOwner 的身份
  校验与具名读取。scope 在调用 adapter 前进入原 SessionReads 同一 map/八 scope 限额，
  使用可区分的 UI/submission 归属，不增加第二池、隐藏 UI lease 或通用读取绕行。
- header 核原 Thread/ref revision，inputId 为 inline 时精确比较；deferred 时先核长度，
  再按原 text 分块协议精确比较必要 UTF-8 字节，提前不匹配可停止，不读取无关错误正文，
  不伪造完整 ConversationTurn。原 ID 不 trim、normalize 或缩字符域。
- 原 Thread/source/input 全匹配才推进 identityObserved；typed queued 不推进 effective，
  running 与 startedAt 非空的 terminal 可推进 effective。durable 的原 history 三要素
  完全不变，Wrong-input/仅 ThreadStatus.Queued/任意 saved 都不能补证或自动重发 Unknown。
- Composer 在业务 dispatch 前绑定；Start 在 retain 原创建 source 后、首 baseline 交接
  前绑定，不能先 await ready。允许在空 baseline 交接时初始化原 observer，不能循环
  等待同一 ready。已确认创建后观察失败仍保原结果与独立同步错误。
  若已有 execution attempt/baseline，只有其绑定的 source 与本次 CreatedInputExecutionSource
  同一对象才可复用；普通 feed、另一 source 或仅相同 Thread/incarnation 不能完成 ready。
  不相同时必须沿原创建 source 建立其自己的 attempt，并由该 baseline handoff 完成 ready。
- close 先封该 lease 的 Turn reads；observer join 本次交接/late-open/query 与原 history
  查询，scope 真 Clean 后才撤销相应责任。failed close 保原 owner/report，可显式 retry。
  只 join 本 lease 读取，不 await Session.close；consumer 不 await 会包含自身的关闭
  future。截止时间只截止等待，不丢后台责任、不新开 source 或重放命令。
  observer 失败构造交回的清理 owner 也须由 Draft work 实际 join 并记录 CloseReport，
  包括 value 已知的 Start；后台 join 自行完成不能替代 work 的 evidenceDone/释放结算。
  原 onFailure 通知或同步取消/释放阶段抛错须保留可显式 retry 的原责任，成功阶段
  不重做，失败阶段不被 attempted/notified 标记永久封死。重试成功清对应恢复项，
  不抹原 cause/首次业务结果，不把真实 terminal join issue 一起清掉；普通 close
  不暗中无限重试，重入期间也不得重复释放同一步骤。

本轮只消费真实收到的 typed Turn 证据。原生 Core 尚无 queued Turn，Pending input 不能
塞进 durable history 查询，也不虚构 Turn/ref/time；SDK queued 契约回归不是 native
Pending 端到端证明。本轮不改 native/schema，也不宣称新增了这项能力。

实现切片为 Conversation 的 demand/session owner/feeds/reads 与 Drafts 的 submitted-input
observer/submission work，尽量保持六文件；如必要相邻共享签名超出此范围须先报告。
后继公开 factory 回归应保 wrong-input、queued/running、durable=false 的独特断言，补
无 UI、created-source-only、首 baseline pre-ACK、deferred inputId、关闭中的 late open/
query、错误/重试与原八 scope 共享上限；不复制私有观察算法作替身，不在静态期运行。

## 17. Models 原能力的 FRB／HTTP 运输闭包

§13/14 的原资格、pair pin 与精确详情 runtime/protocol 已局部静态批准；本切片只补
既有 Catalog feed/read、source-status read 和 exact detail 的运输，不重写业务材料。
SourceStatus 必须使用原 ref+origin，SDK 的 Materialized.current 不代表读取 native
latest 的授权。精确详情 target 在 native 校验原 pair 后取得，不以请求 echo 代证。

### 17.1 FRB 具名能力

- `open_model_catalog_source_status_read(reference, origin)` 返回
  `BridgeModelCatalogSourceStatusReadConnection`，提供 identity/request_close、
  header/text/close/retry_close，复用已有来源状态 union 与 ReadText。
- `open_delegation_model_read(BridgeDelegationModelReadTarget)` 返回
  `BridgeDelegationModelReadConnection`，提供 identity/target/request_close，以及
  header、原 Models 九类字段读取、selection_sources/evaluations、close/retry_close。
  八个新 Bridge 纯值 DTO 与 §14 protocol 一一对应；复用现有 descriptor、pair、
  性能/评价摘要与枚举，不复活旧 whole detail/guide 长文本接口。
- 复用原 ModelsRead/open_read/BridgeTaskRegistry 和 TypedFeedTask，trait 实现放
  新叶，不增加 runtime registry 或 BridgeRuntime 字段。Catalog **具名 read 连接**
  （`products/read/catalog.rs`）的 retry_close 必须转发原 read owner 的 retry_close，
  而不是再次普通 close；本条不把 Catalog feed 与 Catalog read 混为一个 owner。

Catalog feed 的 retry-close 重新等待原 TypedFeedTask 的同一 producer completion，
不重启流或重发终态。当前该 feed 没有独立的 native RetryClose 清理操作：发送/join
失败均保为 Terminal，不能因再次等待清掉；等待方取消后可再次 join，只有原 producer
真实完成且无 issue 才退役注册并释放 sink/feed。这与具名 read 的显式 cleanup retry
是不同责任，不能互相替代或据此声称可恢复任意 transport 故障。

### 17.2 独立 HTTP read 与生命周期

新增 Models 具名 HTTP transport 集合，仅登记 CatalogFeed/CatalogRead/SourceStatusRead/
DelegationRead 的打开、native handle、查询与 body 消费责任、保留的能力身份、issue
及原 stream permit。不引入第二 native 池、业务镜像、ACK window、通用 transport 框架
或永久 tombstone；实际资源终结后按原生命周期退出索引，不承诺无限身份保留。

- reads 独立按原 origin/ref 或完整 target 打开，不能强绑父活 feed；feed close 不
  关闭已交接 read。Catalog 与 Delegation 同可为 Value，仍须保真实 read kind，
  错域 query/control 返回 typed InvalidArgument，未知 handle 返回 typed NotFound。
- opening 在首次 await 前登记，丢失回复/late-open 仍归原 owner；requestClose
  先封准入，不 abort 原 native opening 伪造 join。close/retry 加入原打开/查询，
  descriptor 或转换失败仍保 native 清理能力与原 scope identity。
- body 直接消费原 native send_pending，等待原 changed/cancelled 和 transport 的
  ACK 唤醒；不增加第二 pending publication 队列。ACK 仅转原连续前缀，需显式唤醒
  body，不能假设源更新通知会在 ACK 后触发。control 至多一次且不受 Data 窗口阻挡。
- 最后 control handoff 不算 body EOF/Drop；消费者与原 producer/open 真 join 后
  才释放 pin/stream permit。真实 join/sink issue 保留，显式 retry 用原 native 新
  cleanup 报告替换可恢复项，失败 Future 不永久缓存、不按错误文本重分类。
- close report 的 feed_id 必须来自原 feed_id 或 scope_id，不能回填预期身份；
  Last-Event-ID 明确拒绝。原请求、ID 字符域及正文不 trim/缩限或静默截断。

### 17.3 路由与预算

以下具名路由均为 POST，typed body/OpenAPI 由同一实际 router 和 protocol 生成。

| 路径 | 能力 / operationId |
| --- | --- |
| `/api/v1/products/model-catalog/events` | SSE / `modelCatalog.events` |
| `/api/v1/model-catalog-feeds/{feed_id}/ack` | `modelCatalog.ack` |
| 同 feed `/request-close`、`/close`、`/retry-close` | `modelCatalog.requestClose/close/retryClose` |
| `/api/v1/reads/model-catalog/open` | ref+origin / `modelCatalog.read.open` |
| `/api/v1/reads/model-catalog-source-status/open` | ref+origin / `modelCatalog.sourceStatus.open` |
| `/api/v1/reads/delegation-model/open` | 完整 target / `delegationModel.read.open` |
| `/api/v1/models-reads/{scope_id}/request-close`、`/close`、`/retry-close` | `models.read.requestClose/close/retryClose` |

统一 `/api/v1/models-reads/{scope_id}/` 下的 21 类 query：

- Catalog-only：`catalog-header`、`entries`、`entity`、`lookup-account`、`accounts`、
  `models`、`effort-after-model-selection`、`first-text-model`；operationId 为
  `modelCatalog.read.header` 或 `modelCatalog.read.<camelMethod>`。
- Catalog/Delegation 共用：`text`、`strings`、`type-support`、`type-exclusions`、
  `connection-modes`、`input-capabilities`、`input-sources`、`modalities`、
  `price-tiers`，operationId 为 `models.read.<camelMethod>`；text 也支持 SourceStatus。
- SourceStatus-only：`source-header` / `modelCatalog.sourceStatus.header`。
- Delegation-only：`delegation-header`、`selection-sources`、`evaluations`，分别为
  `delegationModel.read.header/selectionSources/evaluations`。

共 32 路由，精确分类 1 Stream / 7 Control / 24 Normal，复用 Server 原三池各 64。
三类 reads 仍共原 ModelCatalog 八 scope 和 runtime ReadCalls64；两种额度不混同。
页默认 32、limit 1..100、最终 JSON 256KiB；文本默认 65536、4..262144 字节和原
UTF-8 边界不变。guide 最多六来源、评价原 SQL LIMIT 10 保持；分页不证明整个原
Catalog/Config 材料或 capture 内存已有固定源侧总字节上限，不作此虚假承诺。

### 17.4 单 writer 与实施边界

native 执行者只写新 FRB read/convert 叶、Catalog retry 必要一行、Server `models/**`，
以及 protocol 三叶中现缺的十三个 ToSchema derive（feed/model_catalog.rs 五种、
read/models.rs 五种、read/model_pages.rs 三种），不改变字段/serde/业务语义。
不写 runtime 已批准 Models 实现、共享 pages/primitives、SDK/tests/generated。

root 串行维护 `StudioOperation` 的实际 32 个操作、Bridge read/mod 与 convert/mod
声明，以及 Server lib 的模块/运输集合初始化/精确请求分类、routes merge 与 exit
seal/join。同一绝对 deadline 及最终 issue 汇总不变，不新加 finalizer/期限，不改
Config/Profiles 最终 Clean 后才释放来源材料的约定。含在审 Profile 改动的共享根
必须等其范围批准后才叠加；新叶可依冻结接口先实施，根 hooks 单独审查。

## 18. Configuration 生产 adapter 与产品机械资源复用

native Configuration56/Profiles35/Profile-reload24 与 SDK Configuration 调用/观察门槛
均已局部静态批准后，提供唯一 `FrbConfigurationPort implements ConfigurationPort`。
其构造无打开来源、reload、probe 等副作用；完整覆盖现有二十一入口，而非只补 opener。

- 两个真实 Configuration/Profiles feed 使用已有纯 converters、实际 listen 才 claim、
  ACK 只转已消费前缀。ConfigurationHeader 必须映射原 nullable roleRead，不能用
  null 替代已签发 pair；失败不转换为空集合或正常 EOF。
- 五类 scope 覆盖 Configuration value、Profiles value、Role、Start、source status
  的全部具名 query 和 controls。统一 status native opener 已按完整 origin 分派原
  Configuration/Profiles 来源，Dart 不猜 entry/ID、不建立来源表或双 opener fallback。
- Value scope 绑定原 value ref；Role/Start 绑定 pair.reference 与 configuration.origin，
  不是 configuration value ref。catalog.origin 与其 ref 独立保留；source-status
  绑定 SourceStatus version。全部双水位、closing 与 typed query/result 完整往返。
- Start 只映射原 Resolve/SelectModel 和 Ready/Unavailable；保 mode.simple 退回条件、
  显式模型/effort overlay、同模型继承与空 effort 默认规则，不首模型替换或在 Dart
  重新计算资格。Profile 可空 effort 与用户正文按原输入传输，不增加 trim/默认值。

原 products 的 ModelsReadOwner/ModelsNativeOpening 是现有机械 owner，不另复制一套
Configuration opening。将其收敛为单一 ProductReadOwner/ProductNativeOpening：
前者接收明确 ProductReadOrigin + ProductReadVersion 和具名 native callbacks，后者
仍使用原 AdapterResourceOwner 的登记。完整迁移原 Catalog/Templates read 与 Templates
feed 消费者，删除旧类/路径/转发别名；原 Models/Template diagnostic 标识和消息不变。
共享 owner 不持业务模型、额外预算或独立 registry，也不增加通用框架。

- raw scopeId 在完整 scope 转换前独立保存；descriptor/header/query 失败仍可沿原
  opaque 真正关闭并核 report.feedId。scope identity 一旦核定不能换源、entry、版本
  或 incarnation；late open 归原 owner，封口后不得交接给新的 owner。
- 原页/字段/text helper 保各域的 offset/limit/UTF-8/最终预算，不把 scope Value
  假设带入 SourceStatus。原 Catalog/Templates 的相邻迁移随本单元复审。
- Configuration/Profiles 八态来源转换继续只有一份。FRB 2.13 desktop 的 i64 为
  PlatformInt64/int，进入既有 BigInt 精确检查前做无损类型适配，保负数/可空与溢出
  诊断，不改 shared exact helper 签名、不用 dynamic 多版本兜底或静默截断。生成符号
  仍以真实 Rust 输入与锁定生成器为依据，统一生成后核 canonical，不手改生成文件。

三个 typed call wrapper 各自保真实 callId/operationId、result 与同步 requestClose /
close/retryClose。只在该 begin API 的 native 明确无-call admission Result-Err 下映射
Rejected；transport/codec/lost reply 和 find 错误不按 code 猜拒绝。登记后业务拒绝来自
原 call.result，仍需关闭；同 ID 冲突不借 find 关闭别人的 owner。

result 在原 AdapterResourceOwner 登记实际工作并保到 typed outcome/返回值转换完成，
不使用普通 query 的关闭后 ensureOpen 覆盖已确定 committed/adopted 结果。requestClose
后不新开 result RPC，先前已接纳工作仍真实 join。Profile 五类、reload 四类和原八配置
outcome 穷尽映射；正常 reload 无 receipt，AdoptedButUnobserved 保确认无可用回执语义。
原 call handle 已核定操作身份后，Committed/CommittedButUnobserved/Returned 等已确认
outcome 中的回执或嵌套 OperationId 校验失败，仍保已确认阶段，转为确认但回执不可用
的 typed failure；不能经普通协议错误降回 Unknown。只有身份有效的真实 receipt 才能
继续保留为 committedButUnobserved；Rejected/Unknown 分支不得反过来推导成功。
真实 receipt/targets/OperationId 原样核验，不补 Models stamp、观察信号或新 ticket。
不在 result finally 提前关闭材料，SDK 全 targets 同步/观察责任仍按 §9.1/12/15；
CAS、Unknown find/join、单次显式 retry 的既有规则不变。

单 writer 为 A1：新 `products/configuration/**`、configuration_converters 的 roleRead/
时间适配、source_converters 的 desktop 时间适配、原产品 read/open helper 的上述迁移
及全部直接消费者。只写其实际 products 权限内，不写 shared、Conversation、SDK、
native、生成或 app。root 后继直接装配 FrbConfigurationPort 并复用本 App 的 budget/
operations/真实 Models target receiver；不新增 SDK barrel 或恢复旧 studio_api facade。

## 19. HTTP 详情归属的用户确认

用户在说明“停止实时更新是否应中断已打开详情”的区别后，明确选择方案二：
Thread五域与Models详情独立管理。该确认解除原design18 §18.2.4/v4 Server父feed通则
与现Thread/Models实现之间的冲突；原完整Plan仍有效，不改变交付目标或静态验证节奏。

- Thread五域的具名详情及相关统计identity读取、ModelCatalog/source-status/精确
  Delegation模型详情，使用显式原origin/ref或完整target，由native校验pin原版本。
  不强制活feed前置，不从current/新feed补旧身份；父feed停止、断连或重开不撤销
  已交接独立scope。Context/ThreadConfiguration后继沿同一Thread归属。
- 调用方仍负责显式close；宿主原运输owner始终登记打开中、未交接和未收束责任，
  应用退出沿原期限统一封准入、真正join。Unresolved保原句柄/issue/permit及显式
  retry，不以未知scopeId、丢回复、GC或超时假Clean；未关闭仍占原有限额度。
- 其他产品，包括Configuration、Profiles、AccountTemplates，维持已实现的父feed
  监督，不因共享Dart机械owner或端口组合而一并迁移。依领域只留一种公开契约，
  不加父/独立双入口或兼容转发来回避归属。
- 所有原身份、版本、权限与预算限制不变；这不是停止AI执行、撤回已受理命令或
  退出免清理的选项。Unknown仍不得自动重放，不增新registry、池或业务事实源。

root先同步design18与v4 Server本节相关条款，再继续Thread两域实施；已有Thread与
Models局部批准保留其原内容身份，最终集成验收仍须核具体路由、断连/显式close与退出。

## 20. Mode registry 原提交的锁外通知前置

用户完成锁研究后明确要求按推荐架构继续 PR。本节采用为分阶段改造的第一项实施合同，
不是全面拆锁或新框架授权；它解决已知通知边界，不把移出通知等同于已解决广域锁。

当前 Mode manager 的 publish 在 state.write 内 send_replace，Config 的 Mode 保存/
删除/reload 还持外层 command_lock。只把 send 移到 manager 方法尾不足以解除外层锁。
复用原 watch 和不可变快照，增加 crate 内的具名分阶段能力，不新建队列、manager 或
通知框架，不携带第二份 Mode 定义。

```rust
pub(crate) struct ModeRegistryPublication { /* private retained revision notification */ }
impl ModeRegistryPublication {
    pub(crate) fn notify(self);
}
impl ThreadModeManager {
    pub(crate) fn replace_source_deferred(
        &self,
        source: ThreadModeSource,
        registrations: impl IntoIterator<Item = ThreadModeDefinition>,
    ) -> Result<(Arc<ThreadModeRegistrySnapshot>, ModeRegistryPublication), ThreadModeManagerError>;
    pub(crate) fn remove_source_deferred(
        &self,
        source_id: &ThreadModeSourceId,
    ) -> (Arc<ThreadModeRegistrySnapshot>, Option<ModeRegistryPublication>);
}
```

- publication 为非 Clone 的一次责任，只持原 watch sender 和已提交 revision；不通过
  Drop 隐式通知，避免返回/异常时仍持外层锁。通知即使暂无 receiver 也保值，迟到较小
  revision 不覆盖较新水位；保持原 revision 生成策略及同 revision 失效通知语义。
- 既有公开 replace_source/remove_source 保原签名和业务语义，调用同一提交逻辑，
  在自己的 manager guard 释放后通知。它们仍服务 builtin/其他直接调用者，不是
  兼容旧实现的别名；Config 使用 deferred 能力穿过其真实外层提交边界。
- Config Mode 保存、删除、reload 先保原文件/验证/回滚/CAS/缓存采用顺序，取得
  同次 snapshot 与 publication；释放 command_lock 和相关 state/document guards
  后再 notify。不得为了锁外通知提前通知半提交文档缓存，或吞掉已提交后的通知责任。
  内部发布接缝将同次 `Arc<ThreadModeRegistrySnapshot>` 与可选 publication 一起返回；
  command outcome 从该 snapshot 取 catalog，不在解锁后用 latest 替代本次结果。
  未改变及未知 source 删除不造新通知，失败路径仍透传原错误/恢复失败。
- 启动初始化也消费原 publication，不漏 retained 基线；未成功的准备/编译不发布。
  不更改 Mode 的输入、ID、128 项/文档字节上限、graph revision、业务 receipt 或路径。
- root 独占 mode/manager.rs 与 mode/mod.rs 的窄能力；原 Configuration writer 只写
  config/runtime/mode_definitions.rs 及必要同目录消费者。两部分联合静态审查，root
  核身份后再登记，不并写 Thread observation 或已批准 Profile/Models 单元。

后继 Thread owner 仍通过原 observe_registry 的同锁 baseline+receiver 注册消费，
本前置不新增 Thread facet、不宣称 Mode 删除提示或完整两域来源闭包已经完成。

## 21. Thread opening 排队准入与关闭等待环

锁研究发现 Execution/Metrics 的 opening 在原 ReadCalls 同步登记后，无条件等待
runtime lifecycle 锁；strict shutdown 持该锁并 join ReadCalls，形成可实现的等待环。
这是源码已闭合的缺陷，不是运行复现结果。Authoring 已有正确的原 shutdown latch
参与排队准入模式，本切片只把同一契约补齐到两个遗漏入口。

- 范围仅 `studio/runtime/thread_execution.rs::open_thread_execution` 与
  `thread_metrics.rs::open_thread_metrics` 的准入等待。仍使用原 ReadCalls 登记/额度/
  completion；排队阶段同时观察原单向 shutdown latch，关闭已提交时优先返回原
  typed Cancelled。获得 lifecycle guard 后保留原 shutdown 重核。
- 只取消未进入 I/O 的准入等待；已取得准入的完整 opening、cold checkpoint、activation、
  baseline handoff 与真实 join 不变。不能把 whole opening 放入取消 select、abort
  原 task、丢 JoinHandle、提前归还 permit 或删除 ReadCalls 登记。
- 不新建锁/队列/registry/取消源/错误类型，不改变 Thread ID、Live/Cold、权限、
  source/ref/epoch/incarnation 或 HTTP 独立 scope 合同。Authoring 仅作为复用参照，
  本次不修改；未来 Context/ThreadConfiguration 遵守同一准入契约。
- 原作者窄修后 fresh 静态复审；保持 static-only。后续真实验证须控制“已登记但
  opening 未执行、strict shutdown 先取得 lifecycle”的顺序，核 opening Cancelled、
  关闭真实收束及后继 open 被拒；timeout 只是失败看门狗，不是成功判据。
- 本修复不声称解决全局 lifecycle 长 I/O 的队头阻塞、Mode 锁内通知或 shutdown
  stage wrapper 超时脱离监督的问题；这些在锁研究报告中分别保留。

## 22. 推荐锁架构的分阶段采用

用户明确同意研究报告的推荐方向：优先沿既有领域 owner 单 writer、不可变读快照、短状态
提交区、锁外通知/等待调整，不新增通用 actor 总线、事务调度框架、RCU 或第二事实源。
L1 已批准；本轮先实施 §20 与下述最窄 state 锁缩小，并独立冻结 shutdown 阶段监督合同。

- `ConfigRuntime::finish_model_catalog_probe` 的全局 observation sequence 操作不再
  持有 Config state guard。仍由原 command 串行边界保护 generation/identity/closing
  校验、sequence 全序、整表合并、文件采用和发布；先在同一 state 捕获必要 owned 输入，
  释放 state 后才访问 sequence 文件，最终在原 owner 采用。不放开文件事务排他责任。
- 保 Updated/NotModified/error 的原身份检查、CacheWrite/Protocol 分类、checkedAt、
  失败保旧 cache、跨账号整表合并与原 receipt/source 水位；不改变输入或新增后台任务。
  此小切片不宣称目录文件采用已完全脱离 Settings command lane。
- 广域 command 与 lifecycle 锁的后继按真实资源划分。Mode 定义 JSON 与同一
  `config.toml` 内的 mode route 是不同责任；账号/凭据/route 联合事务不可按页面拆锁。
  慢 I/O 的原受管工作、准入、版本重核与关闭 drain 必须先明确，不能 unlock 后写入，
  再用失败回滚覆盖后继。design20 的目录独立 lane 目标保留，不偷偷弱化。
- shutdown stage 超时后的 completion 归现有关闭协调器；纯等待与必须继续的副作用
  先逐阶段区分。不得仅靠局部 JoinHandle 的借用 timeout 假定返回后仍有人负责 join，
  也不以 abort/Drop/提前 EOF/permit 释放解决等待。具体槽位、重试及阶段错误合同另行
  冻结后实施，原首次绝对 deadline、Degraded、finalizer 顺序不变。
- Mode manager/mod 由 root 写；Config 原作者只写 mode_definitions 与 catalog 两叶，
  合并为四文件联合静态审查。R3 由原 native 作者先做最窄阶段闭包调查，不并写此四文件。
  全部仍 static-only，真实取消交错、持久化与性能证据留统一验收，不虚报优化收益。

## 23. Models Dart 生产 port 闭包

原 Models native/FRB/HTTP 与 §18 产品机械 owner 已静态批准；此次将已有能力接入 SDK
现役 `ModelsPort`，不新增业务 mutation 或 UI 策略。无构造副作用的生产 port 完整提供：
openModelCatalog、openAccountTemplates、openModelCatalogRead、openAccountTemplatesRead、
openSourceStatus、openDelegationModelRead 六入口。

- Catalog feed 复用原 typed native feed 与 AdapterFeedConnection；连续 ACK 前完成
  转换/交接，保持原 2 未 ACK/1 latest/control、typed failure、requestClose/close/
  retryClose 与真正 join。不得用旧 topic 轮询、聚合 facade 或伪 feed 代替。
- 三类 Models reads 以原 ref+origin 或完整 Delegation target 独立打开，不借当前活 feed。
  source-status 使用自己的版本种类；exact detail 保完整 pair/config/catalog/account/
  model 身份，native 校验/回显不等于省略 adapter 核对，不从 latest 补材料。
- 复用现 ProductReadOwner/ProductNativeOpening 与现 Models 字段页/文本转换；完整
  实现 SDK 所有具名方法与 close/retry。raw identity 先保存，转换失败仍交回原 native
  清理；共享诊断标识、旧 Templates 行为与原 scope/call 预算不变，不新 owner/池。
- Models DTO 的 desktop i64 与现 exact 检查无损适配，价格/时间/计数保 nullable、币种、
  单位、finite 与数值边界，不强转截断或默认为零。typed union 穷尽映射，不写 raw JSON
  fallback，不手改生成文件，不重算模型资格、自动选择或最终评价。
- 生产组合入口收敛为完整 port；删除旧三个临时叶工厂及其旧导出/调用，迁移可见消费者。
  先核实际引用；若引用位于作者目录权限外，交 root 串行接线，不能留转发 alias。
- 原 A1 在 products 目录实施，SDK/native/shared/generated/app/test/文档为只读；只能
  按本合同修改 Models 叶与必要已有 Models converter/factory，§18 Configuration 代码
  默认保护。需要改变其已审共享 owner 行为时先报告，不把物理目录权限当重构许可。

### 23.1 精确详情的独立关闭身份

生产接线确认 SDK `ModelsDetails` 在 close 后读取完整 identity，而实际 adapter 的该
查询受 closing 闩及 descriptor 转换约束，会将已完成的关闭误判为失败。沿已有 Binary
raw-close 原则，`DelegationModelReadConnection` 增加 `String get scopeId`：只来自原
native handle，首次有效取得后稳定，Clean/dispose 后仍可读；初次不可得时只允许从
同一原 handle 恢复，不能取新 scope 或用 report.feedId 补签。

SDK 先执行原 close/retry，再用独立 scopeId 拒绝空 ID／错报告，不因完整 descriptor
失败跳过清理。identity/target 的查询准入和原 pair 校验不变。root 只改 SDK port 与
ModelsDetails 两文件；A1 只补新 exact 叶的 raw getter，复用原机械 owner 不变，十二
路径联合静态审查。现全 code 手写 Dart 检索只有该新叶为具体实现者；后继替身同样须
遵守此合同，不因尚未补全的测试消费者保留旧接口。

## 24. Shutdown 原阶段监督与最终成功许可

R3 只读调查已核 13 个 stage_branch、3 个直接工作与3个服务 join，共19个稳定阶段；
另有 Store 关闭的同类局部 JoinHandle 缺口。按用户已采纳的架构路线冻结以下合同，
不新增通用任务框架、第二 coordinator、公开 DTO/进度 variant 或额外资源池。

1. **唯一归属**：原16个工作任务、三服务 job 与条件 Store completion 归原 ShutdownRun。
   原 service_stops 所有权迁入而非复制。闭合私有阶段身份对应原 label/order；DAG、
   各自时间限制、SSH 依赖观察结束后回收、MCP/LSP 真 Done 后才 stopped 全保留。
2. **登记和执行**：在短 owner 边界安装可重新 join 的 job 后才让 factory/业务首次
   执行；可用现 Tokio 一次启动 gate，不新调度器。Running 共享原 job，成功不重跑；
   timeout/Skipped 只作用于观察，不取消业务、不遗失 handle。已许可的阶段即使预算
   耗尽仍受管启动，Store 则必须先通过原 can_close 与当前退出许可。
3. **重试资格**：三服务保 once-only；后台 watcher/probe/title 的已结束 join/panic
   失败不能通过重启或空表成功清除。detailReads 仅原 scope 的 RetryClose 且无 terminal
   call failure 可继续；toolRefresh 仅原 RejectedTools 清理部分可恢复，原后台 join
   失败保留；bots 依据原 typed retryable；agentFramework 只依据原保留 entry/command
   的明确恢复信息；persistence 只允许原 drain/flush 恢复，writer shutdown 终态错误
   不靠再次调用洗掉。Store 与其它无恢复证据的失败保原结果，未知不猜 retryable。
   重试只对调用入场时已确认 eligible failure 冻结一次资格，Running 后来首次失败
   本轮先返回失败，下一次显式调用再决定，不自动循环。
4. **错误保全**：原业务 anyhow cause 与 JoinError 无损保留；title join 结果不能丢弃，
   catalog stop 的 close 失败与各 probe 失败均汇总，不能 close?? 遮住其它结果；writer/
   observer 不先转 String。只补这些相关 helper 的 typed 失败接缝，不重写底层 owner。
   当前所有未解决 issues 与原首个 cause 保留，已恢复旧 attempt 仅为诊断，不永久播种
   为新 collector 的阻塞；不为此建立无限 attempt 历史或按错误文本判断恢复资格。
5. **调用者取消**：strict 保 caller-driven，已受理阶段持久保留，未调度后继由显式
   retry/exit 接续。复用原 Shared completion 可在后续 join 归档迟到结果；不要求
   无观察者时新增 eager supervisor，不谎称 Shared 自己会主动 poll。应用退出仍为
   原 owned run，不因等待方离开停止编排。
6. **统一成功前置**：首个 exit 原子冻结 D0 与首份 external issues。strict 的 Store
   准入及 FinishShutdown 前检查已提交的 D0/issues，退出已经先提交时不绕过其前置。
   最终许可/状态提交与 exit 准入同一 coordinator 边界；不得持其锁做 I/O、通知或
   释放文件锁。先已提交 Clean 的情况不追溯撤销，但后到输入不能造第二 finalizer。
   Store 已开始必须继续真实 join；D0 过期或已有外部 issue 时不迟到发 Stopped/释锁。
7. **保原恢复语义**：成功阶段不重跑后，不再借成功 agentFramework 的偶然副作用
   重试 writer。需要恢复时沿原 retry_persistence/指定 history recovery 的明确能力，
   不在关闭内自动清指定 fault generation，不扩大三服务 stop 的底层重试合同。

原 native 作者独占 shutdown 主体及必要 title/catalog/framework helper；root 串行
改 runtime/mod 与 lifecycle/builder 的旧 service_stops 装配。transitions 保现 strict
guard 归属，不为此增加第二 runner。若现 typed 错误不足以证明某条恢复资格，先补
允许范围内的窄阶段错误，不得 generic Err 一律重试；无法无损闭合则报告具体缺口，
不默改业务或扩大到 pl-core/pl-tool/pl-lsp。原 ReadCalls/scopes 与已审 L1/Mode/Config/
Models运输算法不改；源文件组织可在同 shutdown 域内按实际职责拆分，不能新建公共框架。

静态交错必须覆盖登记后先关闭、timeout后重等、成功不重跑、显式重试资格冻结、三服务
once-only、Skipped仍启动、SSH依赖、Store在途时exit提交、strict先入场后exit超时以及
旧失败不假清；全部真实运行与故障验证仍延期，不新增被项目禁止的 Rust tests/hooks。

### 24.1 原存储恢复事实（G1）

原 coordinator 的 drain 不再从公开聚合 snapshot 的单条 error/latest metrics 推断
资格。原 incarnation 登记携带 Preparing / Running / Stopped 状态，准备阶段取消也
必须完成原 detach；只有真正交给原 worker 的登记才为 Running。遗留错误行不代表
仍有可运行任务，不以 released_dirty 是否为空替代生命周期。
Preparing 仍是未完成的接管责任：它在同次 canonical 读取中阻止 drain 成功或缓存
失败恢复资格，直至原准备完成或取消。不能在旧 released_dirty 行退役、新 writer
首次报告原队列之间，将尚未报告欠账的 Preparing 行当作健康零队列。

drain 在原状态锁的一次读取中捕获全部失败 incarnation 的原身份、欠账、typed metrics、
error 与 released_dirty。诊断本来已是 String 的来源如实保留，不声称恢复丢失的底层
source；新错误不再将其合成一条字符串作恢复协议。只有全部失败都来自 Running 原
writer、具有 typed history fault 且没有 released_dirty 时，才能把该失败归为原显式
history 恢复后可重观测；缺失事实、准备/终止、watch 关闭都不授资格。读取与等待先
订阅，读取原登记后再等变化，不以派生 watch 的陈旧值伪报 drain 成功。

同一 HistoryChannel 的具名恢复能力核对原 channel 身份及原 Running writer，不借
threadId 查到的新 channel 或公开 latest 行替代；观察 barrier 仍先核原固定 ticket，
已达到 ticket 不受后来故障反向否定。此能力仅是“可向原 owner 请求恢复”，不是自动
执行 retry、保证恢复成功或允许重建 writer；R3 不清 fault_generation，不新开队列。

claim/detach 原队列交接、pending/watermark/预算算法保持不变。现实现唯一生产 update
来自原 channel 的 effects/metrics，replacement 在同 channel step fence 下读取 durable
checkpoint 并接管；因此“released_dirty 永久不能被后继清除”的旧注释过强，改为未有
真实接管前必须保留。不能将这一澄清外推为任意新 incarnation 健康即可清旧义务。
root 负责这条窄 storage 接缝；原 R3 作者消费 typed 错误，G2 观察/Resource 的具体
分类另行闭合，不以本段代称 G2 已完成。

### 24.2 原关闭 producer 的类型化失败与剩余责任（G2）

1. 采用 producer-specific 私有错误及实际 close phase 的原身份封装。Thread entry 用
   原 incarnation/ThreadHandle/cleanup gate，unpublished 用原 factory/gate；后者可在
   Thread entry 移除后仍负清理责任。operation 文本、泛 Resource/Storage 及“有 entry”
   都不是恢复依据。原公开/wire 形状不扩张，不新建通用 capability 或 close 框架。
2. Observation 分开保存原 progress cause、原真实 BackgroundTask completion 及全部
   scope issues；投影 panic 即使 task 正常返回也属终态，outer panic/无 final state
   不能重启 worker。原仍等待 retry 的 worker 只从其实际 retry 点接续。每个已捕获的
   history handoff/write-behind ticket 跨显式尝试保持；成功步骤不重放，汇总独立结果
   不无限等待仍在 retry 点的失败 worker，也不把未尝试步骤写成假失败。
3. WriteBehind 的 flush/shutdown 在原 owner 保留 typed phase、原 owner/task 身份、
   原 through ticket 与原 PureError/JoinError/RecvError。原已 String 化的旧来源如实
   保留，不伪称恢复更早 cause。当前失败与公共 health 的同次来源必须相容，不由新
   registry 或错误文本反推；已恢复旧故障不永久阻塞新结果。
4. 只有原 Running supervisor、同队列仍负原目标且未进入停止接管时，Blocked 才有
   关闭阶段的重新观察资格。NotRunning/Stopping/已结束/watch closed 不给新的关闭
   尝试；其真实 join 责任仍在。保留原 retry_persistence 的显式恢复能力，但必须先
   核原任务真实终态及停止/队列身份，不从空槽或 is_finished 推可重启，不并行启动
   第二 supervisor。内层 worker 的原恢复、FIFO、批次、退避、水位算法保持。
   原失败接续使用同域 `reobserve_original_flush(&WriteBehindFlushFailure)`，先核 owner，
   再按原 ticket 已达优先规则结算；否则在原 lifecycle 边界重核原 task/stop/欠账资格并
   保住该任务，锁外复用固定目标等待。`can_reobserve_original_flush` 仅是纯查询，
   不能与一次新的 `flush_through` 拼成原任务接续。资格失效保原失败，不等待新槽，
   不追加业务恢复、任务或注册表。
5. 协作 AgentOperations 的原 Jobs/Shared 保所有实际 job/root join 失败、driver 失败
   及剩余未 join 身份；结果观察不 take 掉唯一诊断，driver 失败不重启。仍存活的原
   JoinSet 只继续真实 join；业务结果继续由原调用结算，不把任意业务 Err 当 join 失败。
   正常准入路径若需要保原一次错误交付，使用同一失败记录的已交付事实，不删除关闭
   必须保留的终态。成功/终态不会因后续空表而改成成功，也不创建无限 attempt 历史。
6. 允许混合失败的 remaining-original-close 接续：原 FrameworkShutdownFailure 与
   ShutdownRun failed result 保存剩余原责任，入场仅为已有可推进 leaf 冻结一次资格。
   新 attempt 不调用已成功/终态 leaf，继续保所有未修复 terminal facts；剩余清理完成
   后不再授重复资格，终态仍阻 Clean。不增加另一个 strict runner/coordinator。
7. Worktree 关闭按真实 validation/record/preview/discard 阶段及原 lease/policy 判断；
   记录冲突、身份错误不授泛 retry。discard 与记录同时失败保两份原因；已确认完成
   的物理步骤不因后续记录失败而重做。不得解析 Git stderr 猜 absent、绕 Git lock
   强删或重建 workspace。本次不扩具体 backend 的 branch-absence 协议，也不混入
   saved-child 显式业务的其它双失败修复；这些相邻边界单列，不能声称已闭合其幂等性。

实施按真实依赖分片：先闭合 WriteBehind 与 AgentOperations 原失败来源及直接调用方，
独立静态审查后再接 observation/resource 身份与阶段接续，最后补 R3 collector/资格。
root 保共享根/文档/索引单 writer；各切片仅在明确 allowlist 内改动，static-only 不变。

G2b2 的 ThreadCloseFailure 只承载关闭阶段、原身份和 producer 原失败，仍通过原
ThreadAssemblyError::Resource.source 传递，不扩公开 enum/wire。资格查询是纯读取；
实际接续在原 operation/cleanup 边界重核并只推进原剩余阶段，不能把纯查询与按 ID 的
fresh close 拼接。原 ObservationCloseFailure 直接接续原 request，原 RejectedTools
保同实例未完成项及未尝试责任；普通 Tool/Storage 字样不构成恢复证据。工厂关闭阶段
保原 lease/policy 与已完成物理步骤，不因记录失败再 discard；不改变创建/恢复算法。
共享 thread_assembler.rs 的接入由 root 应用精确补丁，原 close_all DAG 保持；G2c
再统一消费这些类型和 continuation，未消费的后继不以 allow 或兼容 shim 掩盖。
跨 assembler 的新失败仅使用 crate-private canonical 路径：
`crate::studio::RejectedToolsCloseFailure` 与
`crate::studio::thread_factory::FactoryCloseFailure`。root 在实现完整后应用必要的
runtime、studio、thread_factory 根精确导出，与 assembler hook 联合审查；不提前
接入尚不存在的类型、不扩大模块公开性，也不以通用动态 capability 代替原 producer。

## 27. main 新增业务的迁移边界

当前未解决入口分成两类，处理方式不同。业务已在新分层完整体现的旧 facade 直接随
原删除决定消解，不再保留转发；承载 main 真实新能力、且新分层尚无对应实现的入口，
必须先把能力迁移到新 owner，再删除旧入口。

需要迁移的能力及 owner：

- Bots：新 SDK 产品域（Repository、typed product topic 载荷、命令与读取）＋原生
  适配＋App 生成式 VM 与设置分页＋演示与 Driver 只读投影。设置界面不直接调用 FRB。
- 委托设置：Configuration 的委托默认值读取与写入原归属 Configuration；App 的委托
  展示与 composer 会话菜单消费同一读值，不在 View 内复制默认值。
- 目录与选择：Agent 目录查询与导航意图归 Workspace；composer／shell 只调用已发布
  选择动作，不自行生成 selection generation 或 root 推导。
- 读取与更新：单 Thread 元数据读取归 Workspace；更新动作的外部链接启动属平台边界。

迁移顺序为先 SDK 值／动作，再原生适配，再 App 消费者，最后删除旧入口；任何一步都
不为让旧调用点暂时可用而新增兼容别名、动态 capability 或第二份状态。删除后的新
实现须通过适用门禁与真实 GUI 验收，不能以旧 facade 仍存在作为完成条件。

### 24.3 协作准入登记与评价目标等待

root 关闭在原封口后，先与原 AgentOperations admission 登记边界同步，再检查和等待
该 root 的原任务；已通过准入但尚未登记的任务不能漏过。短准入屏障不跨业务或长 join，
不新增任务、锁、registry 或 driver。取消观察不丢弃原任务责任。

核对该边界时发现既有评价先等目标 permit、后判直接父子关系：无效 self-target 可与
持 root permit 的关闭形成相互等待。评价须在原受管 job 内、等待目标 permit 前，从
原 canonical 目录核实直接 child 关系；不只特判 self 而留下 foreign root 的同类路径。
该只读核验不取得目标 permit、不启动/迁移 Thread、不写目录；其错误走原业务结果。
取得原目标 permit 后仍核当前目录、caller、关闭状态、终态及 revision，串行保护覆盖
原 flush/历史读取/SQL 提交。合法冷 child 及已提交相同评价的幂等返回不变。

此修复不扩大评价输入或授权，不改 protocol 校验、主线分发策略及原关闭 DAG，也不以
取消 job、提前释放 root permit 或绕过真 join 消除等待。与 G2a 原任务身份联合复审，
其余 G2b/c 仍为后继；上述交错是源码证据，运行验收仍延期。

## 25. 既有 Thread 模型／effort 切换不自动重发

root 已核 main 和 PR 的 design18 都禁止自动重试 route 写入，但 main 旧客户端实际
在 staleRevision/conflict 后刷新两个 owner 并最多重试两次。用户现明确选择按设计
不自动重发；迁移不保留旧 retryRevisionConflict 路径，也不把它扩成新的自动 CAS 重试。

- 一次意图冻结原 Session、operationId、目标模型／effort 及两个业务 expected revisions。
  冲突返回调用方并保留原路由；重新观察后由用户明确发起新意图，不自动换版本重发。
- 普通 error code 不证明尚未提交。原 Thread extension 已提交而后继材料、Mode 默认
  保存或运输失败时，保原真实提交事实与 warning；不能降为 Rejected 或按冲突重放。
- Rust 仍唯一决定模型 enabled/Text/effort/连接/上下文资格及 NextTurn 生效点；客户端
  不按可选 effort 第一项补默认，不绕过 bot 托管或 child 冻结路由限制。
- 此决定只适用于已有 Thread 的模型／effort 联合写；Configuration 的其他命令重试、
  Rust 原保存 Mode 默认值的内部有界重试、Stop 的精确原 Turn 取消合同保持不变。

此段只冻结已确认的重试语义；route 的新生产命令结果保活、typed 提交分期与原目标
观察接口仍待原 owner 闭合，不代表新 command port 或 Thread Configuration producer
已经实现。未知结果不自动重发的原合同继续适用。

### 25.1 bot 归属的窄读取迁移

native Configuration read/protocol/FRB 已保留原 `bot_id`。SDK 的 ModelRouteReadValue
补 `required ReadText? botId`，已物化 ThreadModelRoute 补 `required String? botId`；
nullable 表示该原详情确实无托管身份，不设默认值掩盖漏传。手写 converter 仅从原
FRB read DTO 转换，configurationHeaderTexts 在同 scope 文本物化中包含该字段。
不扩大 feed brief、不新建 bot 状态源、不裁剪或改写 ID、不从当前 bot 列表推断。

本切片只闭合字段与读取材料传递；新 Thread Configuration producer、完整路由命令、
Bots Repository 及托管导航仍是独立后继。没有可用详情时保 Unknown，不能借新增
nullable 字段默认开放编辑；也不新增 bot 会话的本地 Stop 禁令。

## 26. 具体 Session 的 Stop 动作

原权威入口保持 interrupt_prompt(operationId, threadId, expectedTurnId)。本切片不修改
native 受理语义，不新增 source CAS、command registry 或泛 commandcall 框架；SDK
绑定只能证明本地原 Session，不能冒称 native 已校验不存在的 incarnation 参数。

公开动作只增加 `ConversationSession.stopTurn({required ThreadFacetStamp origin,
required TurnReadRef target}) -> OperationTicket<Unit>`。Conversation factory 必传原
ConversationCommandPort；port 增 interruptTurn(threadId, turnId, operationId)，返回
真实 threadId/turnId/interrupted/CommitReceipt 的纯值，不返回旧 aggregate snapshot。

- 同步冻结 Session 对象、原 Execution source、active target、OperationId，登记工作
  与原 evidence demand，再读当前值；origin 必须 Execution/Ready/同 incarnation，
  target 必须该原 source 已交付的 active queued/running Turn。过时/关闭/外来目标
  在派发前明确拒绝；不创造 NoChange receipt。
- 通过原独立 Turn read scope 有界物化 header.id/header.threadId，核原 scope、目标及
  Thread，保任意合法原字符串；读失败或派发前原目标已终止则不发命令。source 的
  同一 entry 可跨 revision 表示同 Turn，不能因为正常进度更新就改选另一目标；更不能
  把不同 incarnation 的相同 entry 当同身份。首次冻结的 read ref 不替换为 latest。
- 原观察先于派发，允许原终态证据早于 reply 缓存；原 native receipt 验证 OperationId、
  threadId、turnId 与 requiresIdentityObservation 后才确认 Accepted。原同 source 的
  后继权威帧证明目标不再 busy 时才 Observed/Effective，不赋 Durable。断流/控制/
  owner 替换本身不构成证明；来源恢复后仍须有原身份相容的真实权威材料。
- 未派发的本地失败为 Rejected；已派发的普通异常一律不凭 code/文案猜拒绝，缺真实
  提交证据时 Unknown，绝不自动重发。明确成功却 receipt 不可用、或有 receipt 而
  后续观察失败，沿既有 confirmed/committed-but-unobserved 语义保事实，不降 Unknown。
- Stop 不排在 route/archive/create 的长写 FIFO 后；工作、opening、read 与 evidence
  归该具体 Session/Repository，借原 SessionReads/8 scopes、原预算和原 Execution
  demand，不造平行 registry、不对外复用提交专用 lease 冒新业务契约。
- 页面离开不改目标；关闭同步封 Stop 准入，已派发调用真实结束后才归还其责任。
  原 evidence 不能在 Repository 关闭后无限悬挂：不可再证明时如实 evidenceFailed，
  保原受理/Unknown 结果，再取消观察并真实关闭读句柄。清理失败保原 handle/issues/
  permit，显式 retry 只重试清理，不重发停止命令；成功步骤不重复。

本片先做 SDK action/owner/port，生产 adapter、公开回归与 UI/Driver 为依赖后继。
不把已有 DTO 当作已接线，也不因其他端口未迁完加 Noop 或旧 facade 兼容入口。

生产薄适配直接调用已有 FRB interrupt_turn；调用未返回时的普通异常统一保 Unknown，
不从 bridge code 猜未派发。真实成功 reply 的转换失败保原成功材料、cause/stack：有
可用且相符的原 receipt 时为 committed-but-unobserved，其余为 confirmed-without-
usable-receipt，不降 Unknown。成功转换只传纯值，由 SDK 校验目标/receipt 并结算；
适配层不观察 Turn、不重试业务、不拥有新的 Session/句柄/预算或原始回执全局缓存。

### 26.1 Stop 的页面能力与独立呈现

root 已核 main 的 composer_dock：运行中的 child 有 Stop-only 按钮，交互面板有独立
Stop；退休 planner 仅只读提示。新 UI 必须保留这些入口，而非套用 canCompose 或为
Stop 开放 child 输入。正常 composer 保“无输入时 Stop、有输入时 Send and continue”，
Escape 使用同一 Stop 资格；send/platform pending 不成为 Stop 禁令，不重做视觉布局。

领域呈现归 Conversation VM 的独立 Stop 通道，不放入 Composer/Drafts 的单一操作
observer、pending/error 或发送意图。Smart 页面持自身挂载／可见代次，原 VM、Session、
实际注册的 Execution source 及 epoch/incarnation 构成该动作的运行期能力；纯 ViewState
只留原 origin/target、operation/result/error 等值。点击只从原 source 的当前 Ready 帧
冻结同 entry queued/running Turn 的完整 ref，随后由 SDK 冻结，不在任何 await 后换目标。
绑定失效与目标不再 busy 分开：后者不能撤掉仍需显示原 Observed/Effective 的观察。

原观察登记和 UI 发布可同步重入。新意图在调用 SDK 前同步占位，返回的 ticket、观察
句柄及迟到结果只归原页面／来源／意图；旧 callback/finally 不得修改新呈现或发送状态。
不要为 UI 新建操作 registry、业务队列或 Session owner。取消 UI 观察失败保原 handle
与错误，不借新注册或业务重发掩盖；结果观察错误不改写原提交阶段。
本地观察取消与 native 清理分责：当前 SDK 的实际订阅取消先撤监听及 permit，再同步
发布可用额度通知；通知可重入，listener 异常交原 zone，不冒充 native 关闭错误。
VM 卸载先冻结原句柄并封页面资格，独立尝试全部观察取消、metadata 封口与关闭；
前项意外异常不跳过后项，全部尝试后保 stage/cause/stack 诊断并观察原 close Future。
metadata 未完句柄、issue 与预算仍由原 Workspace owner 接续及汇入应用关闭，不保活
旧展示 VM 等 native 清理。诊断出口不等于 ExitCoordinator.externalIssues，也不证明
异常句柄已回收；本片不新增非标准 UI 订阅的转交／恢复注册表。

现 App Router 用嵌套 Settings MaterialPage，可覆盖仍 mounted 的 Workspace。使用
Flutter 原 ModalRoute 的 current 通知及真实挂载/卸载证明页面资格，不把 mounted、
TextField.enabled 或 TickerMode 当唯一证明，不新建导航 owner。官方 ModalRoute.of /
isCurrentOf 明确依赖 isCurrent 改变而重建；实际版本及焦点行为仍待统一验收。
暂时遮盖可保原纯状态/原 ticket 身份供同一运行期上下文回到可见时重新观察，但先
核 exact source，不能恢复已退休 callback。VM 完整销毁后只消费新的 canonical 来源；
没有原能力不推测恢复旧 operation，也不为此永久 keepAlive 或新增 SDK 查询。
完整 VM 销毁也结束它对 result 的等待；SDK 原票据继续结算，迟到错误仍被消费。
只保留标准 Future 竞争所需的纯结果等待，不让原票据的未完成 continuation 强持
已卸载 VM、页面或 Session/source。UI 等待结束不表示 native 已结束或取消成功。

ACK 只发布原 receipt，ticket.result 可能仍等 Observed；Observed 结算可先于 Effective。
UI 因此持续采原 ticket.state，不把任一 Future 结束当全部完成。Unknown 后若当前原
来源仍有可停止目标，新的明确用户点击产生新 OperationId；这不是自动 retry，不重用
或重判旧结果。当前意图的准入/native/Accepted 未观察阶段防重复，清理只归 SDK。

定向只读核对已确认最小接线可行：Conversation VM 捕获原 Stop 动作，Smart Screen
持永久可退休的页面 token；生命周期入口仅同步退休／预约安全事件，不在 build 内写
Provider 状态或注册、取消观察。事件再按原 token 收束／恢复观察并发布纯值，旧事件
不能操作新页 handle。Unknown 判定先于通用 isPending，避免将新明确意图永久封禁。
原 SessionFacetObserver 只补实际 source 捕获、失效通知与注册返回归属核验，不改变
其它领域读取政策。Composer VM／State 保持不变；Composer Connector／View 仅传
纯 Stop 状态与 callback，child／interaction 共用同一 Conversation Stop-only 控件。

现有 U-General 执行者仅有 settings/general 写权限，不因此授权其修改 Conversation。
UI 实现和回归尚未交付；生成、测试和真实 Driver 继续遵守整体阶段门槛。
