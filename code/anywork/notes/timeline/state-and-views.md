# 时间线逐文件审读：状态、资源连接与视图

与 `review.md` 共用审读范围。下列全部初始文件均已逐行完整阅读；表内“保留”表示审查后有明确职责，没有为减少行数强行替换。表内路径前缀为 `code/anywork/lib/src/features/conversation/timeline/`。

## 运行字段

`code/anywork/lib/src/features/timeline/view_models/thread_runtime_fields.dart` 按 Thread 读取 Client 内联当前值或同名延迟字段，通过独立的 `AsyncValue` 交付待办与 workflow run。工作流观察比较包含图查询所需身份，引用 Client 原 run。延迟引用保留时间线 ViewModel generation 观察，沿原 owner 的发布检查同一 generation 中后到的 Current reader。每次读取在提交前核对 owner、lease、reader 和字段引用。退订同步 retire，读取路径在 `finally` 等待 `close()`。运行字段测试与证据见[壳层交付记录](../shell/review.md#pr596-后续分层验证)。

## 状态模型（18）

| 文件 | 判断 / 处理 |
| --- | --- |
| state/chat_item_presentation.dart | 已读 payload 解码、History/Current 身份、未知/损坏单行降级、public input、复制资格。forUnit 对冻结坏记录保留已有 malformed 原文/诊断，不把它替换成不可用占位；真正不可用观察仍走原占位。observationUnavailable 的读取资格语义保持不变。 |
| state/chat_payload_reading.dart | 已读严格字段校验、工具状态/参数/附件及 wait 投影。使用 registry 策略而非工具名分叉，保留。 |
| state/content_reference_identity.dart | 已读 Current/History 引用完整身份和 window 适配，保留，不把 generation 当可解释业务时钟。 |
| state/lsp_presentation.dart | 已读所有类型、预览截断恢复、location/hover/symbol/call/diagnostic/capabilities/status 解析。保留真实 wire 文本解析与 raw fallback；删除无人调用 timelineLspQueryOperation 及失去用途的 import。 |
| state/patch_presentation.dart | 已读 freeform/input 信封、文件操作、移动、chunk、EOF 和不支持格式拒绝。是请求展示解析而非重新求差异，保留。 |
| state/timeline_current_projection.dart | 已读按 run 与终态资格向开放组叠加 Current；冻结/完成历史不覆盖。保留。 |
| state/timeline_display_diagnostics.dart | 已读 Group/Children/Member/window 同步只读诊断与实际 layout 事实，不开查询。保留。 |
| state/timeline_display_models.dart | 已读固定 cut 的 block/member 引用、不可变行比较、正文来源和有界 Current snapshot。删除只有声明的 presentationVersion 常量；保留生命周期比较和 immutable block 保护。 |
| state/timeline_display_unit.dart | 已读展开意图、body 可见 token、generation 退役与成员 close。三条退役分支分别服务 replace/retire/折叠，不能因相似而丢掉准入差异。保留。 |
| state/timeline_file_presentation.dart | 已读 pl.tool.files 回执、唯一 opaque artifact、版本 1/2 支持、deferred/networkImage/ready/failed 分支。外部回执版本支持不等于历史业务兼容投影，保留。 |
| state/timeline_history_item_content.dart | 已读原始 History 单行预读、正文引用 key 与逐 body 错误。保留首帧 handoff 和原 scope 资格。 |
| state/timeline_history_projection.dart | 已读 boundary/WorkRange 构造、leading/tail 时间、event metadata 与状态转换。保留后端索引和固定 cut，不以 Flutter 猜测区间。显式检查自身消费的 int/bool/String 字段，类型损坏仅使该行进入 malformed 诊断；各字段独立按类型读取，保留有效 capturedAt、实体/事件身份和真实观察可用性，不将坏字段扩大为整页失败，也不伪造 available=true。坏 metadata 不得借 finalEmptyAfterContent 隐藏诊断。不捕获真实读取或资源异常，不改变公共数据契约。 |
| state/timeline_image_resources.dart | 已读引用计数、按 attachment 共享尝试、retire/release 与 retry 资格。保留；虚拟列表卸载不是清空共享图片的理由。 |
| state/timeline_outcome_presentation.dart | 已读 failure/budget/cancellation 纯投影、可见 provider 分类、重试秒数与 duration。保留，避免根据显示字符串改变真实失败语义。 |
| state/timeline_ui_controllers.dart | 已读借用 UI 控制器窄接口，保留。 |
| state/timeline_view_state.dart | 已读 Freezed 呈现元数据，未修改生成输入。保留。 |
| state/tool_presentation.dart | 已读单项工具呈现值与 outcome，保留，不缓存另一份历史顺序。 |
| state/work_group_event_folder.dart | 已读按 call/entity/event 分桶、缺失调用反查、first seq 稳定位置、最新状态与分阶段正文合并。保留完整折叠语义。 |

## ViewModel 与成员读取（基线 5，新增 1）

| 文件 | 判断 / 处理 |
| --- | --- |
| view_models/conversation_current_owner.dart | 已读 bounded windows、scope retire/join、订阅取消、分页及 cleanup retry。保留原 reader 资格和关闭证据；未用通用 dispose 掩盖失败。 |
| view_models/display_member_controller.dart | 已读完整组结果、Current overlay、结构与逐行通知、disclosure 所有权、分页一致性和串行关闭。保留；record equality 与主列表 equality 保护对象不同，未机械合并。 |
| view_models/plan_document_view_model.dart | 已读业务引用身份、会话/展示 owner 同步、有界读取、请求代次、retry/copy。保留错误与旧请求隔离。 |
| view_models/timeline_message_controller.dart | 已读唯一 Flyer mutation、serial admission、冻结边界保护、stable row reconcile、trim 与退役。LSP 确认 replaceBlocks 只有测试消费者，已删除旧局部替换接口/实现，测试改用生产 reconcileBlocks 的完整窗口，保留 prepend 与终态更新排队行为断言。 |
| view_models/timeline_view_model.dart | 已读跨线程 matching 和只读 source 观察，保留 AppGraph owner。 |
| view_models/history_work_range_members.dart（新增） | 从 presentation owner 提取完整 DisplayMembers 实现，按已有接口独立承担固定 cut 的 work range 遍历、去重、call backfill 和 batch。无额外 reader owner 或事实源；关闭只停止成员需求，scope 仍由调用者拥有。资源关闭类型显式来自 lifecycle。 |

## 连接层（14）

| 文件 | 判断 / 处理 |
| --- | --- |
| connectors/completion_run_connector.dart | 已读稳定展开租约与成员诊断登记；Widget 不接管业务关闭。保留。 |
| connectors/file_reading_panel.dart | 已读选中文件 identity、异步尝试隔离、Markdown 安全链接和 scroll reset。保留，与 Plan 的 PageStorage 需求不同，不直接合并两个阅读表面。 |
| connectors/interaction_details_connector.dart | 已读集合分页、1 MiB 结构预算、64 KiB 连续窗口、secret 隐藏、只读 question/approval 视图和取消。保留独立只读资格，不能影响 actionable dock。 |
| connectors/plan_detail_connector.dart | 已读 Native 引用资格与 ACP markdown 窄适配，两者共享纯视图。保留外部协议差异。 |
| connectors/timeline_canonical_payload_connector.dart | 已读首帧预读 handoff、history identity、延迟正文 scope 和 public input 的稳定挂载。保留，不让 metadata 替换已公开正文的读取 owner。 |
| connectors/timeline_children_connector.dart | 已读独立 History reader、固定 cut、最多 16 个窗口描述符、Set/reconcile、retry、late opener 回收和 controller mutation 计数。保留，无理由合并成 Main reader。 |
| connectors/timeline_connector.dart | 已读显示租约借用、草稿提交观察、下载 owner、原附件资格、retry/live/history 动作与纯视图装配。删除无消费者 pendingPlanInteractionId 参数传递，保留实际 Plan summary。 |
| connectors/timeline_deferred_file_connector.dart | 已读保存路径选择、transfer 观察、暂停/停止、finished 与 stop 并发、身份退役。保留原 transfer 生命周期，不加第二下载状态源。 |
| connectors/timeline_file_download.dart | 已读下载能力接口和注入作用域，保留既有平台端口。 |
| connectors/timeline_media_connector.dart | 已读共享 thumbnail 原件、descriptor 释放、artifact receipt 连续读取、附件 ledger、save/reveal、HTTPS remote image 策略。保留真实资源所有权，不与原生 IO 合并。 |
| connectors/timeline_member_atom.dart | 已读 Current body/disclosure、scope 资格、reasoning summary、工具与正文呈现、layout witness。删除只初始化/赋 null、从未有错误写入的 _observationError 字段及不可达分支。已知冻结载荷损坏交 ChatItemView 呈现字段诊断与 raw；不让旧边界占位提前遮蔽诊断，也不改变 _unavailable 对正文读取的禁用。真实 error 仍来自原 body owner。 |
| connectors/timeline_owned_body_connector.dart | 已读 History read / Current watch、body generation、取消 join、窗口导航、onRead 的完整 prefix 资格与 witness。保留读取分工。 |
| connectors/timeline_read_demand_viewport.dart | 已读真实 viewport 预算与 post-frame owner 检查。保留，不新增分页 owner。 |
| connectors/work_group_member_list.dart | 已读结构/逐行观察、retry、封口期间 placeholder 和公共成员装配。历史/实时已经复用，保留。 |

## 实时状态（6）

| 文件 | 判断 / 处理 |
| --- | --- |
| live_status/live_status_bar.dart | 已读唯一挂载入口、details、response、开放组 host 与成员 subtree 缓存。保留原 Current 和展示资格；不同 UI 需求不复制业务状态。 |
| live_status/live_status_header_spec.dart | 已读活动/工作组/重连/attention 视觉派生、减少动画、摘要 Markdown 与 meta。与 machine 重复的 storage 分类改用 LiveStorageSeverity.fromStorage。其余 header 差异保留。 |
| live_status/live_status_machine.dart | 已读交互遮蔽、response/compaction 实际布局接管、主阶段优先级、attention 去重与 Current work 成员筛选。storage 分类改为共享 enum 方法；未改变优先级和隐藏资格。 |
| live_status/live_status_state.dart | 已读全部不可变输入/阶段/attention/gate 与 equality/hash。新增 fromStorage 单一分类：resumeReady > fault > pressure > resumeRequired > paused，null 沿用原 header 的 fault。 |
| live_status/live_status_surface_view.dart | 已读主阶段 dispatch、attention 和 fixed/live 视口布局。保留纯表面与生产/预览共享。 |
| live_status/live_status_view_model.dart | 已读 Client/session/lease 的单一事实观察与真实诊断对象借用。保留，不加第二归约器。 |

## 视图（5）与边界导出（1）

| 文件 | 判断 / 处理 |
| --- | --- |
| views/markdown_document_body.dart | 已读 width-following padding 和文档 theme，保留。 |
| views/plan_detail_view.dart | 已读局部 scroll、PageStorage、status badge；保留与布局重挂载相关的阅读位置。 |
| views/plan_document_theme.dart | 已读既有 Markdown theme 上的标题字号，保留。 |
| views/plan_receipt_view.dart | 已读只读历史 Plan、独立 disclosure、文档宽度，保留。 |
| views/timeline_view.dart | 已读真实视口补页、layout barrier、LatestScrollViewport、Flyer builders、submissions 和 retained-layer 可见性观察。删除无消费者 pendingPlanInteractionId；其余保持唯一 owner 与 UI 只定位的边界。 |
| timeline_views.dart | 已读纯呈现导出边界，保留无 Connector/Client/Provider/AppGraph 的入口。 |

## 组件（27 个基线文件）

| 文件 | 判断 / 处理 |
| --- | --- |
| widgets/chat_item_view.dart | 全文 1107 行已读。公共输入、敏感 question body 过滤、原始 envelope 降级、tool 参数与 declared body、错误结果、正文/复制和实际布局证据紧密关联，保留结构。冻结记录已有 malformed 诊断时展示可展开原文和字段诊断，避免被观察不可用占位遮蔽；普通 unavailable 语义与敏感字段过滤保持原边界。 |
| widgets/completion_run_view.dart | 已读单个 Work header、时钟、live/history 几何和 shell。保留既有公共参数，本轮不扩大跨 feature API 清理。 |
| widgets/content_layout_witness.dart | 已读 RenderParagraph UTF-16 selection、真实 clip 可见区、composition callback、首次 layout 时间与 unmount。保留真实证据，不能用“存在 atom”替代。 |
| widgets/conversation_activity_bar.dart | 已读共同表面、status header 与 response bounded body；保留。 |
| widgets/conversation_activity_viewport.dart | 已读 footer 剩余高度与本地 scroll 所有权，保留。 |
| widgets/conversation_current_views.dart | 已读被接纳文本和范围导航纯视图，保留。 |
| widgets/plan_summary_card.dart | 已读文档入口语义与窄窗 badge 布局，保留，不混入决策动作。 |
| widgets/timeline_activity_clock.dart | 已读 package:duration 进位、本地时钟、TickerMode、未知/倒序时间，保留。 |
| widgets/timeline_activity_row.dart | 已读行几何、meta 宽度测量、语义、shared cat ticker、各动画、官方 ExpansionTile disclosure 与 rail。保留官方交互，不加 focus/overlay 镜像。 |
| widgets/timeline_activity_section.dart | 已读 header 自然高度、bounded body、选择暂停与 LatestScrollViewport，保留。 |
| widgets/timeline_attachments_view.dart | 已读文件网格、MenuController、来源动作、下载进度、图片错误自然高度。保留原能力注入和官方菜单。 |
| widgets/timeline_children_view.dart | 已读原 Chat controller 的 shrink-wrap 列表、分页 controls 与稳定 id 查找，保留。 |
| widgets/timeline_compacting_zip_icon.dart | 已读纯 painter、四段连续相位与 repaint，保留，未把矢量绘制当重复业务。 |
| widgets/timeline_content_range_view.dart | 已读初值 handoff、read intent/qualification、bounded text、copy/next 与 frameBody。保留，不累计全文。 |
| widgets/timeline_display_unit_view.dart | 已读稳定 expansion 身份、post-frame 重建、同步撤销读取资格，保留。 |
| widgets/timeline_image_view.dart | 已读图片 bytes 拷贝、MemoryImage、重试、缩略图/原图官方 Dialog，保留。 |
| widgets/timeline_lsp_tool_view.dart | 全文 1528 行已读。已按查询结果、服务器能力/状态、共同视觉拆为同一 Dart library 的两个 part；入口仅 dispatch 和共同外观，不新增导出或 owner。能力与状态共用 _LspServerHeader，状态 badge 各自保留。 |
| widgets/timeline_markdown.dart | 已读 syntax candidate、safe link/source tag、媒体与标准 code/table builder。保留原文，不二次解析/修复 Markdown。 |
| widgets/timeline_outcome_card.dart | 全文 984 行已读。错误卡、budget 指标、notice、分类标签/技术详情和复制计时同属结果呈现，保留结构；复制消息 1500ms 与复制路径 1600ms 语义不同，不强行统一。 |
| widgets/timeline_patch_diff_view.dart | 已读文件/chunk/行着色与选择、stat badge、路径复制。已复用 TimelineCopyPathButton，移除独立 timer/clipboard 实现。 |
| widgets/timeline_plain_text.dart | 已读标准 Flutter Text 薄适配与稳定 key，保留。 |
| widgets/timeline_reasoning_view.dart | 已读单行 summary、正文存在才展开、无动作 Markdown 与状态/耗时 fallback，保留。 |
| widgets/timeline_resting_cat.dart | 已读身体/尾巴分层 painter、关键帧与尾部插值，保留。 |
| widgets/timeline_wait_blocks.dart | 已读 wait 来源、规则、懒诊断、状态与时长。删除无生产消费者的 TimelineWaitPanel；预览直接使用既有解码工具 presentation，终态测试直接装配 TimelineToolItemView。保留 TimelineWaitDetails 及原 adapter 路径，保护等待终态的原 task 身份、展开和诊断文本复制。 |
| widgets/timeline_wait_indicator.dart | 全文 152 行已读。文本搜索及 LSP 均确认只有自身声明/State 引用，无任何生产/测试/预览消费者，已删除。 |
| widgets/timeline_work_group_shell.dart | 已读 ExpansibleController、PageStorage、减少动画与 rail，保留 Native/ACP 共用官方交互。 |
| widgets/timeline_writing_indicator.dart | 已读纸/笔分层绘制与局部重绘，保留。 |

新增组件：`widgets/timeline_lsp_query_view.dart` 与 `widgets/timeline_lsp_servers_view.dart` 是既有库的 part，无新公开接口；`widgets/timeline_copy_path_button.dart` 承担 ACP location 与 patch file path 已有的同一复制反馈，分别保留 2px/3px padding。

初始组件为 27 个，包含已删除的 timeline_wait_indicator.dart。完整路径和逐文件状态另见 review-ledger.tsv；阅读完成来自逐文件全文审读记录。

## 损坏 metadata 的行级边界

timeline_history_projection_test.dart 使用坏字段后紧接正常正文的两行输入，分别覆盖 contentPresent、startedAt、finishedAt、entityId、sourceOrder、capturedAt、turnId。坏行保留原 payload 和诊断字段名，正常行保留原文与实体身份；合法 metadata 的身份、顺序和时间不变，缺少稳定事件身份仍抛 ConversationContinuityError。显式类型检查放在纯投影边界，避免将显示损坏扩大为整页失败，也避免把读取/资源错误降级成普通内容。

timeline_history_metadata_diagnostic_test.dart 补足真实消费链：对 boundary_observed 和 legacy_observed，分别从 forUnit → ChatItemView 与 TimelineMemberAtom 入口装配生产组件，展开并核对字段诊断及原始 JSON，确认后续正常行仍呈现。另有两入口的真实 unavailable 反例，保持旧边界不可用占位。冻结记录保留实体/事件身份、有效 capturedAt=6000 和 available=false；呈现诊断不授予正文读取资格。用例采用 metadata 生产投影和真实视图，不能仅用 forRecord 中间值断言替代。
