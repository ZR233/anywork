# 15 - 会话状态、历史与调用记录

本文是 Native 会话当前状态、追加历史、调用诊断与冷恢复的唯一权威契约；Studio 文件布局与迁移边界见 [17](./17-studio-storage.md)，时间线展示见 [26](./26-timeline-content.md)，客户端与资源生命周期见 [25](./25-frontend-state.md)。ACP 内容继续遵循 [28](./28-acp.md) 的对端协议，不使用本文的 Native 当前态或追加历史契约。文档声明表示设计合同，不代表实现、迁移或跨平台验收已经通过。

<a id="native-current-与历史解耦的目标合同"></a>

## 15.1 Native current 与历史解耦的当前合同

Native 会话有三个用途不同的事实载体：

| 数据 | 当前权威载体 | 读取方式 |
| --- | --- | --- |
| 执行与界面持续依赖的当前态 | Core `Thread` 内存状态及同一 owner 的 Current assembler | `CurrentReader` 的有界 snapshot、watch、collection 与 body |
| 崩溃后的完整恢复对象 | 每会话独立的 `current.json` | 冷加载完整 `ThreadCurrent`，恢复为 paused |
| 已接纳的不可变历史 | schema 25 的独立追加历史库 | `HistoryReader` 的 cut、page、row、body 与 change |

普通 current 捕获、保存、读取和恢复不等待、查询或校验历史；历史接纳也不读取或确认 `current.json`。两者没有共同事务、提交水位、恢复栅栏或历史回放修补关系，可以分别加载、分别失败。一次性的 schema 24 升级顺序只归 [17.21](./17-studio-storage.md#1721-独立当前状态与追加历史的升级边界)，不能推广成日常写路径。

`ThreadSnapshot` 使用 schema 18；Current 与 History 的公开协议版本各为 1，磁盘 Current schema 与 History schema 分别按自身版本校验。客户端收到不支持的 schema 或协议版本时必须明确拒绝，不保留旧客户端的双读、兼容分支或隐藏降级。

#### 可恢复对象与身份

`current.json` 是完整的 `ThreadCurrent`，包含会话身份、保存者运行代次、快照 revision、保存时间、完整逻辑状态以及至多一个当前模型调用。正文、context、opaque 载荷、待交付结果、已接纳工具观察和模型已合并流按当前格式内联；持久附件沿用原资源身份、长度、摘要与媒体类型并逐项校验。连接、凭据、锁、取消令牌与活执行句柄从不持久化。

运行代次 `runtime_epoch` 在一个 owner 生命周期内是规范 UUIDv4，跨 Turn 与 idle 不变；新 owner、新 execution 和新 attempt 使用新的 UUIDv4。历史 `run_id` 引用产生事实的原运行代次。工具与 provider 身份保留原始来源，旧回调、一次性许可和旧控制请求不因加载 current 获得新 owner 的执行资格。正文资源 ID 在正常写入中使用 UUIDv4；只有显式 legacy import 可以根据冻结旧身份生成确定 ID。

逻辑状态保留生命周期、当前执行、continuation、完整 context、private context、输入与 inbox、任务与局部顺序、工具交付、交互与权限、业务扩展、工具声明、累计用量和当前模型调用的真实阶段。历史身份、历史提交顺序、展示分组、输出增量链和持久化等待不属于 current。

#### 捕获、保存与关闭

Current writer 订阅 Core owner 的小型 dirty 变化，每 2 秒检查是否需要保存；每 Thread 最多一个捕获、编码和写入整体在途。保存期间出现的新变化继续保留 dirty，不维护完整快照队列，也不为每个 token 写盘。捕获等待有固定上限，取消、owner 换代或迟到结果按原代次丢弃；等待捕获不持业务状态锁，也不重新发送模型请求。

持久化诊断中的 `current` 只读取该 Current writer 的 runtime epoch、dirty／in-flight、实际保存回执、最近成功写入／捕获时间与快照年龄；未登记 owner 或尚未成功保存的字段保持未知。History 的 admitted／durable 水位独立提供，不能证明 Current 已保存，也不能与 Current 修订相比较。

定向诊断的 `current_capture_ms` 覆盖完整的一致性捕获，另计 producer 捕获请求与换 attempt 后的重抓，失败也记录结果。`current_encode_ms` 只计完整 JSON 编码，`current_json_bytes` 是实际编码长度；`current_save_ms` 从捕获完成至真实文件写入返回，包含校验、编码与 flush，不包含等待下一次周期保存。Current 使用直接覆盖，flush 只确认 Tokio 文件操作完成，不承诺原子替换或断电持久性。`current_snapshot_age_ms` 表示最近成功保存所含状态的年龄，不以写入完成时刻重新起算；页面诊断继续随观察时间计算年龄。首次 load 单独记录 `current_load_ms`，迁移与资源校验须按实际覆盖说明，不与纯 JSON 解码混算。

自动保存失败保留 dirty 和类型化错误，固定间隔后重试；显式 flush 只尝试一次。捕获完成后在锁外编码完整 JSON，并直接覆盖 `current.json`。新建文件在 Unix 使用仅所有者可读写的权限；覆盖写入中断可能留下空文件或不完整 JSON，因此保存成功只表示写入接口返回，不承诺父目录同步或断电后仍保留。资源校验失败不得开始替换文件。

附件缓存以资源根、身份、摘要、长度和媒体类型限定；首次加载验证全部必需资源，周期保存只验证当前 owner 尚未验证的新引用。外部删除或损坏在后续加载、读取或保存验证时明确失败，不承诺每轮保存主动重读全部附件。

关闭先停止新工作、取消并等待在途捕获，再由原执行生命周期收束生产者。生产者必须在累积器销毁前交出最后完整观察；Core 保留已接纳结果后执行一次最终 flush 并等待 current writer。取不到最终观察或写入失败必须报告，不能以历史 flush 成功替代 current 保存成功。

最终观察已取得而文件写入失败时，原 writer 保留完整观察、错误和路径租约；后续明确关闭可重试保存该观察，不再次捕获或启动生产者。重试仍由 writer 持有并 join，取消等待者不会分离写入任务。最终观察本身缺失或资源退出失败时保留原失败，不用新的空 owner 修复；显式永久删除只收束并释放原责任，不补写待删除文件。

#### 冷加载、暂停与继续

冷加载只读取并验证完整 `current.json` 及其所需资源，恢复逻辑事实并进入 paused；不启动模型、工具、进程或对外投递，也不从历史猜测正文、终态或最近执行。旧模型流和工具观察只作为上次运行的暂停事实展示，不表示仍在执行，不拼接为新流。

继续执行属于 Core 与 Continue 控制契约；嵌套执行循环、Continue 控制 DTO 及资源安装分别由其所属边界维护，本文不定义平行控制 DTO。普通新会话即使暂未配置模型，也创建 fresh Current owner，不把空对象当作冷恢复。恢复后的明确输入、继续或队列恢复请求由现有 owner 输入驱动调用同一个 Current 本地对账与普通 Turn 准备流程；被动读取、消息通知或重复回执不获得新的执行授权。恢复得到的新请求只能通过普通准备流程建立新 owner、execution、attempt 和累积器，完整历史不能修补 current，旧 partial stream 不进入新上下文。累计用量以最后一次有效 current 为基线，不从全部历史追补。

<a id="独立追加历史"></a>

## 15.2 独立追加历史

每个 Native Thread 只有一个 schema 25 History writer。`history_store_meta` 保存数据库、Thread 与 schema 身份；`history_events`、`history_bodies`、`history_body_chunks` 是唯一业务表，均由数据库触发器禁止更新和删除。当前 wire 只使用 `HistoryEventHeader`、类型化 `HistoryRowHead` 与 `HistoryEventBodyRef`。旧 v24 wire 只允许出现在冻结迁移 schema。

普通输入与 Continue 的原受理身份、请求摘要、路由版本及后续状态写入独立的 `InputAccepted`／`InputConsumed`／`InputDiscarded` 事件；它们不建立 UI 行，不复制用户正文。受理元数据由原 effect 冻结，正文 ID 在运行期冻结时生成，writer 重试沿用原候选。重复请求按输入身份索引读取一个固定的已提交历史切面，只有原事实可证明的回执才可重放；不会为了重放激活会话、访问工作区、认领继续点或清除后来发出的 Stop。RAM 接纳尚未落盘时只报告可重试的等待，不能冒充保存成功。

事件身份 `event_id` 是幂等键；canonical 完成事件在迁移时直接使用旧 `draft.item_id`，正常新事件也沿用原业务身份，不另建永久映射。`seq` 由唯一 History writer 在接纳批次时分配，同一业务批次全部取得序号后才公开完整批次，不发布中间切点。事件头最多 16 KiB，保存 typed 小头和查询索引；大正文写入不可变 body，body 身份在正常写入中为 UUIDv4，legacy import 除外。

`HistoryEntityHead` 是 Single 与 member 的小型 metadata，记录实体、run、attempt、来源、kind、delivery、状态、真实时间、工具身份、wait、内容存在性、`HistorySingleVisibility`、观察、展示契约和按需引用。canonical payload 是 `anywork.chat/1` 的不可变正文，普通产品 payload/metadata 中的旧引用在迁移时改写为新 `HistoryEventBodyRef`，producer opaque 字节保持不变。 `single_visibility` 是行投影资格，不属于 producer 原始业务事实；导出保留冻结 metadata，只在一致性校验时排除该展示字段，其他事实字段必须完全一致。

历史同时支持 Work、Single、Member、Turn、Source、Cost 与 Accounting 行头。Work 和 Single 在主时间线使用稳定 `row_key` 与首次 anchor；成员按 `group_id` 和成员 anchor 读取。工作尾组只在首次可靠可显示的独立 Single 到来时关闭，来源结束、Turn 成功、idle、owner 关闭和冷重开均不关闭。旧组始终按当时观察到的历史 bytes 读取，后来的 B3、终稿或其他来源终态不能替换它；后续终态进入当前 run 的新组，重启也不续写旧组。

正文按 64 KiB 固定块保存，读取一次最多 64 KiB 且最多访问两个相邻块。主列表和正文目录默认每页 64 行、64 KiB，允许 1–512 行、1 字节–1 MiB，预算包含完整响应与游标；候选放不进预算时留给下一页，单项超限明确失败，不截断。时间头统一为 UTC 毫秒；canonical payload 保持原协议单位和字节。

History writer 先在数据库事务外固定 RAM pending 根，再开始 SQLite 事务；接纳事实和数据库提交是不同阶段。查询先捕获 accepted head 与 pending 根，再开新的只读快照，合并数据库与尚未 flush 的不可变事实。flush 成功后才 reclaim 对应 pending；在途查询持有旧根，回收不破坏其读取。失败保留原事件与写入错误，重试复用同一身份和字节；内容冲突明确失败。History 在同 effect 的原始 producer cut 上冻结边界，不能读取更新的 Current 正文。模型终态先把最后真实 progress 交给 History 再释放 receiver；工具中断或取消的 partial 作为原 canonical 正文保留，不冒充成功终稿。历史不保存全会话缓存。

`history_pending_events/bytes` 只统计已接纳、尚未 SQLite COMMIT 的事实；`history_retained_events/bytes` 统计仍占 RAM 配额的材料，包含已提交但在途查询仍借用的旧根。提交后前者可为零而后者仍非零，不能将两者混作未落盘欠账。`history_sql_read`／`history_sql_write` 在实际成功执行的事件／正文 SELECT／INSERT 后计数，事务回滚仍须单列，不能把语句成功当成 COMMIT。`timeline_examined_anchors` 计一次查询实际解析的候选锚点，`timeline_returned_bytes` 计完整响应（含 cut／游标，group 使用成员响应形状）；两者受该请求预算约束。`history_body_bytes_read` 计 SQLite 实际装入的完整 chunk 字节或 pending 实际复制的范围，`history_body_returned_bytes` 单列返回范围，不能用较小的返回值冒充底层读取量；列表小头不计入正文。日志按原 Thread 身份关联，默认关闭，不参与业务裁决或引入前端 ACK。

提交、失败、压力和关闭沿用原 HistoryChannel 责任：容量不足返回类型化背压，调用方保留原事实；写入失败保留 pending；关闭先封闭接纳、取消并等待读取，再 flush 剩余事实并释放 writer lease。关闭一个 `HistoryReader` 只关闭该读取资格，不关闭共享 HistoryStore 或其他读者。 CLI/bot 等等待终态的消费者在同一 History cut 上查询 Turn，读取其不可变 `turn_detail`，未命中时等待该 History reader 的 change；不依靠 Current 的最后一次通知，不比较两域 revision。 非交互 CLI 还独立观察 Current 的真实待回答状态，以 `WaitingForInteraction` 结束本次观察并报告 `blockedOnInput`，保留真实待回答观察，已退休的 active Turn 不补造；不能将这项控制结果伪造成历史完成。Turn 分页只由持有资格的 HistoryReader 提供，不保留另开 reader 的独立 `/turns` 快捷接口。

投影交给 History 的 `PreparedEffect` 使用 `retained_resources` 表达本 effect 的真实交付与 repair 资源；`turn_id` 可以为空，只有能由原任务证明时才填写。该计划不复制 `latestTask`，也不创建 `history_tool_tasks`。资源身份、摘要和引用冲突使事件接纳失败，不能先发布完成 head 再补资源。

Native 完成工具的 canonical 原件同时保留 `native.tool-task.v1` 正文，记录该 effect 中真实的 `TaskRecord` 与完整 `ToolDelivery`，包括原始 opaque 载荷及结果状态。`get_tool_task` 在原可靠队列尚未 flush 时读取同一在途事实，交接后按工具身份读取 History 原件；不依赖已经消费结果的 Current，也不从展示摘要拼造原始载荷。该正文复用 History 的身份、预算、分块、读者和关闭机制，不另建任务表或结果缓存。既有历史中未保存的原始字节保持不可用，不重执行工具补造。

Native 通过 `ThreadHandle::attach_history(HistorySinkHandle)` 安装独立 History 端口，不附加 legacy checkpoint store。
Core 交付 `HistoryExport { effect, original ThreadSnapshot observation cut, output_claim }`，不创建 checkpoint；
原可靠预算、类型化压力和执行安全点继续约束接纳，输出预留随同一原件转移。Native 单观察者投影后交给原 History writer。
Core Current 的累计用量同步复用该原件的 `PreparedAccounting` 提取，不等待历史提交，JSON 保留已知累计证据。
Current 捕获、保存和物理关闭不等待 History fence；历史失败保留原件并报告自己的故障，不能确认或清除 Current 保存责任。

## 15.3 CurrentReader

`CurrentReader` 是本 State assembler 的唯一薄观察端口，提供 snapshot、watch、collection page、body read、body watch 和 close。metadata watch、内容 watch 与 owner、`runtimeEpoch`、`run_id` 来自同一 owner 和同一 state cut；没有第二个 State reducer、旧 `ConversationStateFeed` 二次 apply、历史 tail 拼接或 GUI ACK。

`CurrentView` 由 owner/revision、schema 18 `ThreadSnapshot` 和 `CurrentProjection` 组成。当前正文、collection、Plan 与交互只使用 `CurrentContentRef` 或 `CurrentCollectionRef`，不出现旧完成项或历史 body 引用。`CurrentAtom` 只描述当前业务来源和执行事实，不携带 completion ID 或 completion sequence，也不能据此推断历史中已经存在 canonical 原件。

State 中可能增长或超过小头预算的值使用 tagged `CurrentStateField`：

- `Body { field, reference: CurrentContentRef, byteLength }`：用于 `todo`、`progress`、`mcpHealth`、`workflow`、`plan`、`thinkingSummary`、`tools.latestStarted` 等单值。
- `Collection { field, reference: CurrentCollectionRef, count }`：用于 `activeSkills`、`activeMcpServers`、`activeLspServers` 与 `tools.active`。`count` 是完整集合总量，不是页长度。

State 字段序列化不超过 2 KiB 时保持内联，超过阈值才 deferred。集合页条目为 `CurrentPayloadData::Inline` 或 `CurrentPayloadData::Deferred { reference, byteLength }`；大条目不复制进 State。内联占位不是完整值，读取方不能猜测空值。generation 是 opaque 身份，调用方不推导 live/cold 命名公式，也不跨 namespace 比较。

热 owner 的 Current Body/Collection 来自原 ThreadLiveFeed 的 StateResources 共享索引，多个引用共享同一不可变内容；冷 owner 从完整 JSON 的同一 State shape 重建引用。State assembler 不读成第二份常驻大 State，磁盘 `current.json` 不是发送给 Flutter 的小 DTO，UI 也不会为了 metadata 或 usage 预读整个正文。

runtime usage、live usage、时机、工具与后台计数、todo/progress、controls 等轻量指标可先由 State 交付；正文、collection 和 deferred field 的读取失败不阻塞这些可用指标。当前模型输出 token 只更新其正文 owner，不触发历史 SQL。

当前流出现 lag、resync 或 owner 更换时返回小型 Reset 基线，不 replay 历史。collection cursor 固定 `owner_id + collection + revision`；owner 或版本失效返回 stale reference，并从最新 projection 重新开页。正文引用固定 owner、domain、entity、key 与 generation；replace、owner 换代或旧引用失效不得把新内容接到旧 offset 后。

关闭 CurrentReader 先同步封闭准入并取消自己拥有的 metadata/body watch 和 page 读取，再 join 调用方已准入操作；不等待或关闭 HistoryReader。正在等待绑定的读取也必须被关闭唤醒。调用方先取消、底层 reader 后关闭等交错必须共同收束，不能遗留父 reader 或未 join 的子任务。

watch 的读取与关闭使用共享引用，接收队列与原 join handle 由 watch 内部同步。等待下一帧不能持有阻止同步取消的 FRB 独占借用；取消关闭等待者仍保留原 join handle，后续关闭继续等待同一个生产者。

## 15.4 传输与客户端边界

HTTP 和 FRB 都分别开放 History 与 Current 句柄，沿用同一组 typed DTO 和版本检查，不生成另一套当前缓存、历史水位或事件归约器。History 是纯 query/page/cut/change 能力；Current 是 snapshot/watch/collection/body 能力。二者由调用方显式 close，不通过业务消息完成资源释放。

SDK 把 History page 机械交给 Flutter 时间线所有者，把 Current State 机械交给会话状态唯一写入口。Flutter 现有 controller 只持有唯一已加载历史窗口，并以稳定 `row_key`／`entity_id` 叠加一个 Current owner；older 查询只返回页面并走显式 apply，不触发隐藏 apply、不推进 Current 资格。具体页面与生命周期合同见 [25](./25-frontend-state.md) 和 [26](./26-timeline-content.md)。

发送回显只是原 Composer 的临时呈现。规范输入由 Current 出现并被同一时间线消费者应用后按 `input_id` 结算显示，不伪造历史事件、完成序号或保存成功；命令成功和下一 Turn 启动都不是等待回显的条件。

## 15.5 通用 Core 存储与诊断

Core 的通用 SQLite 后端仍可独立使用既有 effect、checkpoint 与 durable pressure 契约；这些内部机制只属于该通用存储的调用方，不定义 Native Studio 的 `current.json` 或 schema 25 history 关系。本文不声称 Core 嵌套执行循环、Continue 控制 DTO 或所有调用方已经统一重写；相关边界按其所属合同处理。

模型与工具调用诊断继续使用版本化 JSONL 与可重建的 `calls.sqlite` 索引，不参与当前态恢复或历史正文。诊断写入失败只形成诊断缺口，不阻塞 Current 或 History 的可靠事实；会话累计用量来自 current 中的绝对摘要，不从已过期日志回填。

## 15.6 关闭与冷失败

应用关闭分别等待 Current writer、History writer、History readers、Current readers 和调用诊断 owner 的真实结束。Session 的关闭存储责任直接等待独立 Current writer，不依赖产品观察任务恰好先消费最终快照；其后再等待 History writer。仅为报告接收而创建的临时 owner 也必须保存交付标记的最终清理并 join 自己的 Current writer，再释放原登记；History 退出不能代替该责任。显式永久删除也必须 join 原 Current writer、捕获和订阅，但不要求先修复或成功保存即将删除的数据；普通关闭与归档仍必须报告原保存失败。Current 保存失败保留 dirty 与错误；History flush 失败保留 pending 与错误；History reader 关闭失败保留原读取 owner。任何一方成功都不能掩盖另一方未收束。

未知结构版本、身份冲突、损坏资源或缺失必要迁移路径一律 fail-closed 并保留原文件/数据库。历史正文局部损坏明确返回读取错误，不把缺块解释为空内容。只有明确隔离的 v2 前数据可以保持不导入、不激活；正常路径不打开迁移备份、旧 schema 24 表或旧 client fallback。

History 导出发布与 Current 快照发布不构成同一可见点。历史页读取及可靠交付后的释放，只在该物理 owner 的共享导出窗口内校验已发布／已释放边界；不读取可能迟到的 Current snapshot.commit_sequence，也不等待 Current 保存。超过窗口自身已发布范围仍须拒绝，重复释放已交付范围保持幂等。
