# 26 - Native 时间线、Current 与追加历史

本文是 Native 时间线呈现的唯一权威源。Current 的恢复与历史存储见 [15](./15-session-storage.md)，Schema 25 的物理结构见 [17](./17-studio-storage.md)，客户端资源归 [25](./25-frontend-state.md)，视觉规范见 [19](./19-studio-ui.md)。ACP 内容仍由其外部协议定义，不转换成这里的 Native 事件、Work 或 Single。合同声明不代表迁移、性能或跨平台验收已经完成。

## 26.1 三类事实与唯一所有者

| 数据 | 所有者 | 交付 |
| --- | --- | --- |
| 当前执行、当前正文、交互、Plan、usage 与活动摘要 | Core owner 与 Current assembler | `CurrentReader` 的有界 snapshot、watch、collection、body |
| 已接纳的不可变历史事件与正文 | schema 25 HistoryStore | `HistoryReader` 的 cut、page、event、body、change |
| 已加载窗口、展开、滚动、当前 overlay | Flutter 时间线会话 owner | 唯一 controller、generation 与 serialized apply |

Current 和 History 没有共同事务、共同切点或 ACK。Current 可先显示仍在执行的内容；后续 canonical 历史事件出现时，Flutter 以稳定 `row_key`／`entity_id` 并入同一画面。不能把两个存储的可见性描述成原子，也不能从 Current 字段推断某个历史事件一定已提交。

新的 Native 写入只产生 Current 与 schema 25 History 事实。旧 v24 wire 类型只存在于冻结迁移 schema，用于读取旧 fixture 和一次性迁移。

## 26.2 历史事件、Work 与 Single

Native 的不可变历史由 `HistoryEventHeader` 描述事件身份、序号、kind、run、attempt、entity、turn、source、call、message、group、row anchor、原始查询信息与时间。行的当前小头由 typed `HistoryRowHead` 表示：

- `Work(HistoryWorkHead)`：工作组身份、run、时间、关闭状态、成员与未完成计数、执行在场和摘要。
- `Single(HistoryEntityHead)` 与 `Member(HistoryEntityHead)`：实体身份、来源、类型、状态、时间、工具/wait、内容存在性、`HistorySingleVisibility`、观察、展示契约和按需事件/body 引用。
- `Turn`、`Source`、`Cost`、`Accounting`：执行、来源、费用与累计用量的独立查询行。

Work 与 Single 在主时间线各有一个稳定 `row_key` 和首次 anchor；成员按 `group_id` 与 member anchor 读取。`row_key` 创建后不移动，允许空洞，不以分页位置重新计算。History 中同一 row 的 head 可随真实业务事件更新，但已经接纳的旧组边界、旧成员 bytes 和历史事件本身不可变。

已经开始、首次可靠可显示与终态是不同事实。每个 run 最多有一个当前 open Work；普通工具、后台结果和迟到终态加入该组，同组同业务键的可合并行保持稳定身份。只有首次可靠可显示的独立 Single 才关闭该 Work：

- 用户输入或可信外部消息在历史接纳时形成 Single。
- 显式文件展示、独立业务回执、公开失败/取消/中断按自身类型化契约形成 Single。
- 首次公开正文或有效附件可形成 Single；空 Started、始终空内容和隐藏事实不建立可见边界。
- 来源结束、普通 Turn 成功、idle、执行 owner 关闭和冷重开不关闭 Work。

Work 关闭后，旧成员、状态、内容和摘要都不再回填。后来终态进入当前 run 的新 Work；重启建立新 run，不续写旧组。旧组没有结束事实时如实显示未知，不补造中断终态。已经可见的正文最终为空时使用 `HistorySingleVisibility::FinalEmptyAfterContent` 表达“曾有边界、终值为空”；始终不可见的空内容不创建工作壳。

工具与后台结果默认属于 Work；前台移交和后台最终结果保留各自来源身份。文件工具只有在 typed producer 明确声明独立展示时才成为 Single，客户端不按工具名、MIME 或文案重新分类。Plan/交互的公开决议由原领域事实决定显示资格，不能从正文外观猜测。

## 26.3 边界观察与不可变正文

Work 首次出现时记录真实开始；首次可靠独立可见的 Single 到来时记录边界。边界需要保存当时仍开放成员的公开状态、参数、摘要和内容前缀，而不是读取后来对象或终稿。该观察使用独立事件身份与不可变 body，以 `BoundaryObserved` 表达当时 bytes；它不是新的执行事实，也不补造不存在的 finished time 或 completion ID。

边界后旧成员的内容引用固定到该历史观察。即使后续收到权威 B3、工具成功结果、Turn 结束或失败，也不能覆盖旧组已保存的 bytes。新终态加入后续 Work。相同长度、generation、文本前缀或 MIME 都不能证明旧内容可替换。

普通产品 payload/metadata 使用 `anywork.chat/1`，其中旧 owner/key 引用在迁移时改写为 `HistoryEventBodyRef`。body 是 owner event 下的不可变 UUIDv4 身份，记录 ordinal、body key、role、长度、媒体类型和 SHA-256；内容按 64 KiB 分块。producer opaque 内容、工具参数/输出和边界观察保持原字节。

历史事件头不超过 16 KiB。大 wait、预览、工具内容或附件只在小头中保留摘要与引用，完整值沿所属事件正文目录按范围读取。正文缺失、越界、摘要不符或引用身份冲突都明确失败，不把损坏显示为“空”。

## 26.4 HistoryReader：固定 cut 与有界页面

History 只提供 query/page/cut/change，不保存全历史缓存或 ACK 状态。读取开始先捕获 accepted head 和 RAM pending 根，再打开新的只读事务；数据库已提交事件与尚未 flush 的 pending 在固定 cut 内合并。flush reclaim pending 后，旧查询仍持有自己的不可变根，继续读取不受影响。

主时间线页返回有界 Work/Single 行头；成员页按 `group_id` 返回 member anchors；事件页和 body 目录按精确身份、owner、范围与分页预算读取。费用、会计、Turn、来源和执行生命周期各走其 typed 查询。主列表页不 JOIN 或 COUNT 所有成员，折叠 Work 不读取成员正文，展开后才按稳定成员引用读取。

默认分页为 64 行、64 KiB，允许 1–512 行与 1 字节–1 MiB；完整响应、游标和编码字节都计入预算。候选放不下时留给下一页，单项超限明确报需求错误，不截断字段。只有索引范围真实耗尽才结束，恰好填满行数时可以返回后续空页。

查询游标固定数据库身份、历史 cut、查询范围与顺序。更换 Thread、reader、数据库或 cut 时旧游标失效，必须从新查询的首屏重建；不能把旧页的 offset、row_key 或结束标志接到新 cut。History 变化通知只表示有界窗口可能需要重读，不携带完成 ACK 或要求客户端推进历史水位。

## 26.5 CurrentReader：同一 State assembler 的唯一输出

Current 由原 State assembler 生成，`CurrentReader` 是 snapshot/watch、collection、body 与 close 的薄端口。owner、`runtimeEpoch`、`run_id` 和 revision 来自同一 owner；UI 只订阅这一 State 来源，不再接旧 ConversationStateFeed 做二次 apply。

`CurrentView` 包含当前 owner/revision、schema 18 `ThreadSnapshot` 和 `CurrentProjection`。Projection 只携带 logical status、execution presence、当前 activity/turn、真实 sources、当前 atoms、Plan/交互引用、有界 previews 和 collection refs。`CurrentAtom` 不携带历史完成身份。

大字段通过 tagged `CurrentStateField` 明确 deferred：runtime 的 `todo`、`progress`、`mcpHealth`、`workflow`、`plan` 等为 Body；`activeSkills`、`activeMcpServers`、`activeLspServers` 与 activity 的 `tools.active` 为 Collection；`thinkingSummary`、`tools.latestStarted` 等单值为 Body。字段超过 2 KiB 才 deferred，Collection 的 `count` 是完整总量，页条目可为 Inline 或 `CurrentPayloadData::Deferred`，大项不复制进 State。小头空占位不是完整值；调用方按 reference 的 owner、generation、offset 与 length 读取。generation 是 opaque namespace，冷/热公式不公开；两种来源使用同一 State shape，不维护两套 DTO。

state 元数据、usage、live usage、耗时和 controls 不等正文或 collection。Current 正文观察只随该 owner/generation 增长或替换；token 变化可以只发 body 更新，不推动历史事件或全 State 重建。当前正文终态也不必然已有 canonical 历史。

Flutter 不创建 Current Work 或历史 tail。状态栏直接投影 Current 活动、交互及保存状态；只有对应 Current 正文已有真实挂载与内容布局证据时，才由正文渲染器承接响应／压缩提示，折叠或卸载时撤销该资格。Current Atoms 保留一个有界集合页，只报告已加载数；活动工具在用户展开后读取单页，完整 `count` 与该页条目数分别表示，opaque 游标导航最多保留 16 个返回位置。集合读取不阻塞 State；后台结果在原 owner/ref 仍有效时，经时间线唯一串行更新入口应用，不能把旧行头覆盖到新的 History cut。控制器应用结果不明时退役该代次并重新 Set。

Current watch 发生 lag、resync 或 owner 更换时返回小型 Reset，并重新捕获完整小 State；不 replay 历史。collection cursor 固定 owner 和 revision，版本变化返回 stale；body reference 固定 owner 与 generation，replace 后旧引用失效。旧 owner 的迟到 body、collection 和 watch 结果不能写入新 owner。

关闭 CurrentReader 时先同步撤销本 reader 的 metadata/body watch 与 page 读取准入，再唤醒并 join 所有已准入操作及子 watch。调用方取消与父 reader 关闭并发时也必须共同收束，不等待或关闭 HistoryStore。

## 26.6 业务引用由 State 交付

Plan 与交互的当前读引用由同一 State 发布者交付。`CurrentPlanHead` 包含 revision、phase 和可选 document body ref；`CurrentCollectionRef` 绑定 owner、collection 与 revision。引用只有在原业务资源已经可读时才发布，token、正文读取、保存进度和 UI apply 不推动其 revision。

`plan = None` 表示当前没有计划；计划存在但没有文档时 document 为 `None`。interactions collection 未建立时引用为 `None`；已经建立的空集合可拥有有效引用，不能把读取失败吞成空集合。

Plan、交互详情和文件内容通过引用自己的 owner/generation 读取；资源换代只退役对应详情窗口。Current State 不复制完整业务列表，也不把 collection 页拼回 State。旧的 `content.current`、完成批次 current 或展示 tail 不能作为业务引用来源。

## 26.7 正文、成员与附件

Current 正文按 `CurrentContentRef` 的有界窗口读取；History 正文按 `HistoryEventBodyRef` 的有界范围读取。两者都保留 offset、返回 bytes、可用长度和真实 sealed 资格，不能用一个所有者的窗口扩展另一个所有者。

折叠 Work 只读取 Work head；展开后才请求该组的 member page，并按实际可见行读取详情。成员 head 的 `detail_event_id`、`input_manifest_event_id` 与 `body_manifest_event_id` 是导航元数据，不等于正文已加载。稳定性来自 entity/member/row identity，不来自当前 tool 名、URL、Markdown 外观或 MIME。

历史 metadata 单次读取沿用 64 KiB 小头预算。业务卡片需要完整 envelope 时，按精确 event、content role 和 range 分块读取后解码；超预算、截断、身份冲突或解码失败明确呈现，不自动扩大预算、累计无限正文或把原始 JSON 冒充业务卡。

附件和媒体继续使用会话 `resources/` 的可靠引用、长度、摘要和媒体类型。工具捕获已截断的事实在 bytes 中保持截断来源，UI 不能把显示摘要当完整输出。历史读取不重新执行工具、访问原工作区文件或重新生成附件。

Markdown、代码、补丁和工具 renderer 消费类型化内容与明确角色。未知契约、opaque 内容和不支持的结构按原字节/诊断边界呈现；客户端不依据文本猜测权限、完成状态或外部发送资格。搜索、选择复制、安全链接和媒体限制沿用现有组件。

## 26.8 Flutter 唯一窗口与串行 apply

Flutter 的现有 timeline controller 是应用内唯一已加载历史窗口。它只保存有界 rows、成员页和展开状态；不是 Rust HistoryStore 的镜像，也不为每个 scope 建立第二 reducer。Current overlay 只保存一个当前 run 的 State 与当前正文观察。

画面键使用稳定 `row_key`／`entity_id`。主列表“最新 head”可对已加载窗口中的同一 row 做受控 replace；older query 是纯页查询，只能通过明确 apply 入口一次 Prepend，不能隐藏 apply、推进 Current owner 或复写其他 scopes。新增 anchor 通过范围页或新首屏发现，不能为了刷新一个 head 拉回全部历史。

实时模式只接纳最新一页及其 cut，在 Flyer 中按稳定 row key 更新、追加和移除到该有界页面，并在组件成功后同时提交该页的 older 游标。进入历史浏览后，整个已加载历史窗口固定原 cut；后台变化只提示存在新输出，older 仍使用该 cut 的 opaque 游标，不裁掉正在浏览的行。历史行与成员在此模式中只读 History，不叠加当前 run 后来的正文。回到实时位置通过原 reader 读取新的最新页并建立新的展示资格；保留同 row 的展开意图，旧正文与查询资格退休。提交消息不等待这次查询或绘制。

Work 的成员引用和组关闭等 metadata 必须来自该行接纳的同一 cut；不能把 H1 的成员引用与 H2 的组边界拼在一起。成员与原件详情按 opaque 游标读取有界页，窗口只保留有限导航描述符；EOF 只表示该页范围耗尽，不证明组已关闭。

所有历史 apply 串行执行：前一个 controller 操作完成后才启动下一次 UI 应用。generation 覆盖换 Thread、换 reader、页面销毁和显示接管；旧 query 成功、失败或 finally 不能写入新 generation。普通绘制、动画或滚动不进业务 apply 队列，也不构成 ACK。

controller 调用异常时，无法证明列表未被部分修改，因此终止当前 generation，并以新 HistoryReader 的 Set 重建；不盲重放 Prepend。重建成功前保留旧画面，成功后一次替换；失败显示真实错误，不删除草稿、Current 状态或无关会话。

同组 Current 行与历史 row 以业务身份合并，不依赖到达顺序。Current 可显示执行资格和最新正文；canonical 历史出现后仍保留同一 row/entity 身份。旧组只读历史自身 bytes，不用后来 Current 内容替换。若两个存储短暂不一致，保留最后已见真实状态和等待说明，不伪造成功终态。

关闭显示 owner 先撤销新需求，再取消自己拥有的 History/Current reader 与 body watches 并等待 join。一个 scope 失效不关闭共享 HistoryStore、其他页面或业务会话；迟到 Future 只能结算原 generation。

## 26.9 实时状态与展示组件

状态栏从唯一 Current State 和当前显示窗口派生，直接消费 usage、live usage、activity、tools、todo/progress 和错误。`execution_present` 不等于正在执行，完整运行资格仍来自真实 sources、activity 和原 owner 状态。无 active turn 的有效后台活动仍可显示。

实时活动概览来自 Current Projection；主列表的 Work 和稳定行始终来自 HistoryReader。活动正文可随 Current 更新，历史 Work 的成员和显示身份按自身 cut 保持稳定。实时正文 renderer 与历史成员 renderer 使用同一内容组件，但各自持有独立读取 owner；不靠 Flutter 推断组边界。

折叠 Work 默认一行，呈现真实图标、单行摘要与经过时间；展开后才显示成员。隐藏或折叠撤销该视图自己的正文/媒体读取，不停止业务执行。封存历史行使用真实 finished/start 时间；未知时间不推算。实时计时只是 UI 派生值，不写 Current 或 History。

保存失败、停止、审批、存储错误和冷恢复限制必须保持可见，不能被普通活动摘要合并隐藏。来源结束、Turn 成功或页面关闭不创建展示边界；停止请求和模型自述也不成为历史终态。
网页搜索与抓取的 `tool.result` 是工具实际交付的有界文本预览。内联与窗口详情均按文本保留来源、换行、截断及部分失败提示，不将页面正文解析为结构化回执；完整机器载荷中的不透明状态与原始响应不因展示需要自动公开。其他工具仍按各自明确声明的正文编码解码。

已声明公开 Body 的 Input 在 canonical metadata 恢复之前即可沿原内容窗口呈现；metadata 读取只补足附件等已公开元数据，不是正文准入条件。恢复等待、64 KiB 预算限制、解码失败或身份错误均不得遮蔽这份独立且合法的正文；metadata 的限制或错误单独明确呈现，不回显原信封。恢复成功后仍只有一份正文组件和原正文读取 owner，沿同一 item/ref/generation 保持读取资格，不重复显示或再读同一窗口；附件按原成功身份核对后才取得读取资格。没有公开声明的 Input 仍沿原 canonical 限制，不能把其他域当正文绕过。读取资格判定在原呈现模型内复用，不在包装器与 Widget 各复制一套放宽规则。

发送回显由原 Composer 持有。Current 中同一 `input_id` 的规范输入被时间线消费者应用后，临时回显结算为正式呈现；未出现时保留发送状态或真实失败。它不产生历史事件、不按正文去重、不扫描旧历史，也不因命令成功提前清除。

## 26.10 当前快照格式与旧数据边界

Current JSON schema 为 1，Current 协议为 1，ThreadSnapshot schema 为 18；History schema 与协议分别为 25 和 1。正常 reader 只接受当前版本。schema 24 的完成/展示 wire 类型仅存在于冻结迁移 schema，供旧 fixture 和一次性迁移读取，正常代码与测试不能依赖它们作为现役 wire。

schema 24 到 25 的备份、current 准备、一个 SQLite Immediate 事务和回滚规则只由 [17.21](./17-studio-storage.md#1721-独立当前状态与追加历史的升级边界) 定义。迁移保留旧 canonical 身份、真实可见边界、未知值、费用与附件，不把旧水位、旧展示序号或队列顺序伪装成新事件。

正常路径不打开 v24 备份、旧完成 reader、旧 current checkpoint 或旧展示表。迁移失败保留完整旧库与已准备的 current，重试不重复追加；完成后 Current 或 History 单方损坏只影响自身，`history.sqlite` 的旧副本不能重建 Current。

计划、交互、正在执行的工具和旧 partial stream 只按 Current 的 paused 事实呈现。历史不补齐 current，冷打开也不激活模型、工具、进程或外部投递。
