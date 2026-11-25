# Shell、侧栏、会话工作区、状态与待办审读

下列逐文件检查列保留初审时的实际观察与未覆盖边界；后续统一生成、整合测试和官方预览以[总台账](../flutter-quality-audit.md)的验证表为准，不把初审“未运行”当作最终状态，也不把整套通过外推为每项平台行为已验。

基线 `3db5e10d03db6a13bcc44b37d37555bcaf80e2c7`，分支 `refactor/flutter-quality-cleanup`。按基线跟踪文件区分，M10 有 12 个手写文件，M11 有 12 个，M12 有 4 个，M18 有 8 个，M19 有 1 个。另有 4 个相关预览文件和 3 个生成文件。以下行数为审读时的范围，`session_selectors.dart` 为已包含父代理改动的 688 行，并对照基线 738 行差异。各表中的每个文件均连续读到末行。生产路径相对于 `code/anywork/lib/src/features`，预览路径相对于 `code/anywork_previews/lib/src/features`。

## M10 Shell

| 文件与审读范围 | 责任、证据与处理 | 检查和待覆盖 |
| --- | --- | --- |
| `shell/add_project_dialog.dart` 1–530 | 本地目录选择与 SSH 连接向导。先非交互探测，只有服务器提供密码认证才提示输入，并沿用现有连接编辑器及远端目录对话框。保留 `_busy`、`_picking` 与 `mounted` 边界。 | LSP 零诊断。未观察本地取消、SSH 免密与密码回退。 |
| `shell/agent_switcher_menu.dart` 1–712 | 展示目录成员并按执行身份发出停止意图。会话父索引从逐行重建改为每次构建一次，仍沿 `parentAgentId` 并防循环。共享 `StudioMenuButton` 持有触发器焦点，保留宽高约束、按钮 key、15 秒本地提示及 Client 停止命令板。 | LSP 解析到共享触发器定义。未跑嵌套成员、键盘导航、在途重试或停止与行选择互斥。 |
| `shell/agent_workspace_pane.dart` 1–770 | 按 Native/ACP 身份选择工作区，绑定 Plan、文件、待办与底栏。加载浮层与顶部错误提示改用显式布局插槽，保留测试定位 key。计数由待办组件提供。Native deferred Todo 改为订阅 `deferredTodoProvider`，现役 display lease 到位时触发读取，加载中隐藏旧内容。文件请求仍校验会话和 lease。 | LSP 零诊断。待办 provider 与 `TodoPanel` 的用例在修复图布局后待复跑。首次加载、保留历史时重连及文件面板仍待观察。 |
| `shell/recovery_issue_indicator.dart` 1–30 | 恢复诊断图标共用实现。信息级和错误级由 `impact` 决定，侧栏两种行以原 16 px 复用。 | LSP 零诊断。未观察恢复提示的悬停及并排状态色。 |
| `shell/runtime_banners.dart` 1–827 | 启动失败、恢复、队列压力及持久化诊断。清除无人读取的启动失败 Driver 写入，保留错误正文与 `retryStartup`。`_storageBlock` 只接收选中会话，删除永远走不到的其他会话摘要分支，统一插入诊断行。保留队列里的其他会话诊断和真实故障代数、保存重试与继续闸门。 | LSP 零诊断。未跑启动重试、持久化压力、恢复、显式继续或诊断身份变化。 |
| `shell/shell_view.dart` 1–521 | Riverpod 把 Client 的启动、目录、选择、工作区、恢复及持久化事实投影给各入口。删除全仓零调用的 `threadById` 和恒为真的 `ShellStorageFact.isSelected`，保留标题、数据观察、精确 Thread 选择及 typed 状态。 | LSP 零诊断。父代理已统一生成 `persistencePanelView` 对应产物。未跑目录恢复或冷会话打开。 |
| `shell/sidebar_entries.dart` 1–164 | 会话归档、删除确认与重命名。用官方 `AlertDialog`，当前路由检查避免重复关闭弹层，标题保留空值和 80 rune 校验。对话框有生产、预览和测试消费者。 | LSP 零诊断。未跑归档、取消、标题边界或输入法。 |
| `shell/studio_shell.dart` 1–376 | 顶层壳装配侧栏、页眉、启动和时间线需求。删空 `dispose`，在 part 中移除唯一 Driver 调用后删除对应导入。保留 Drawer 和宽屏侧栏之间移树的 `GlobalKey`、宽度草稿版本和 Client 保存顺序。 | LSP 零诊断，核对 shell library 没有旧引用。未跑拖动取消、并发宽度保存或 Drawer 切换。 |
| `shell/studio_shell_chrome.dart` 1–535 | 标题、成员、费用、打开工作区及输入区。打开入口由共享 `StudioMenuButton` 管理触发焦点，工作区条目与侧栏共用，保留宿主图标、资格、SSH 别名和原路径。 | LSP 解析到共享触发器与侧栏条目定义。`shell_menu_cleanup_test.dart` 已写，未运行。未观察平台启动器。 |
| `shell/studio_sidebar.dart` 1–406 | 将纯侧栏意图接至 Client、宿主能力和 typed GoRouter。Drawer 导航以代次和目标身份校验迟到完成，删除前后复核命令状态。删空的 `onQueryChanged` 以及底栏 `touchMode` 转发。 | LSP 零诊断。未跑恢复及 Drawer 竞态。 |
| `shell/studio_startup.dart` 1–91 | 启动进度与品牌。减少动效时选用同品牌 PNG，正常启动使用 WebP，启动阶段来自 AppGraph。保留资产、文案与进度语义。 | LSP 零诊断。未看实际启动或减少动效设置。 |
| `shell/thread_preparation_card.dart` 1–393 | 呈现冻结提交的准备阶段、错误与诊断。`ExpansionTile` 已持有自身打开状态，保留未知结果与明确失败的区别和恢复入口。 | LSP 零诊断。未跑准备、失败与未知结果，也未检查短窗口展开。 |

## M11 侧栏

| 文件与审读范围 | 责任、证据与处理 | 检查和待覆盖 |
| --- | --- | --- |
| `shell/sidebar/sidebar_connectors.dart` 1–186 | 项目 connector 持较粗结构 owner，会话 connector 只观察该行元数据和删除命令。保留 Client 身份检查、显式重试及原错误上报。 | LSP 零诊断。未跑增量刷新或 Client 换代。 |
| `shell/sidebar/sidebar_detail_overlay.dart` 1–102 | 行详情使用 Material 富 Tooltip 与有界内容。现役语义要求不拦截行和菜单指针，`StudioHoverDetail` 支持指针移入和可点击内容，两种行为有意独立。 | LSP 零诊断。未观察长标题、图标提示和短窗口碰撞。 |
| `shell/sidebar/sidebar_directory_owner.dart` 1–283 | 管理每个项目普通和置顶目录需求，消费完整帧，切页用原 Client cursor，按精确资源 cancel/release 并上报错误。保留两种窗口身份与晚到帧检查。 | LSP 零诊断。未跑页序、换查询、退役及释放失败。 |
| `shell/sidebar/sidebar_footer.dart` 1–161 | 归档、设置、更新入口。选中外观改由整块底栏预览，原叶组件私有化。删除不参与样式的 `touchMode`，底栏行仍固定 44 px。 | LSP 零诊断。未跑更新与设置命中区。 |
| `shell/sidebar/sidebar_header.dart` 1–330 | 新会话、搜索、筛选、分段标题与分页反馈。页眉直接观察文本控制器，清空按钮独立于目录防抖立即出现或消失，空值仍省去 suffix。保留筛选语义与 44 px 触控契约。 | LSP 零诊断。`sidebar_menu_cleanup_test.dart` 已写，未运行。目录防抖由现有增量套件验证。 |
| `shell/sidebar/sidebar_menus.dart` 1–350 | 项目、会话和打开工作区子菜单。宿主应用条目收敛到 `workspaceOpenMenuItem`，项目/会话共用 `StudioMenuButton.icon` 及侧栏专用样式。保留 360 px 宽度上限、横轴约束、触发区、原外层 key、子菜单层级和禁用条件。 | LSP 确认两处调用同一共享构造器，页眉实际解析到同一条目定义。未跑子菜单、触屏、删除和工作区受阻状态。 |
| `shell/sidebar/sidebar_models.dart` 1–123 | 本地查询意图、不可变窗口数据、回调和无平台依赖的宿主能力。查询成员由 Client 提供，保留加载、已加载和分页方向。 | LSP 零诊断。未跑目录窗口查询组合。 |
| `shell/sidebar/sidebar_rows.dart` 1–474 | 项目和会话行，分别呈现生命周期状态、恢复诊断及归档动作。删除重复恢复图标实现并使用原 16 px 参数；保留身份 key 和软硬禁用差别。 | LSP 零诊断。未观察恢复说明、选中、归档、长标题、窗口缩放。 |
| `shell/sidebar/sidebar_thread_status.dart` 1–100 | 单会话 canonical 状态徽章。15 px 品牌活动圈用标准确定型 `CircularProgressIndicator` 旋转固定 270°，减少动画时静止。保留该视觉和固定槽位。 | LSP 零诊断。未观察正常与减少动效两种运行状态。 |
| `shell/sidebar/sidebar_tiles.dart` 1–162 | 单行选择、状态位置和按需操作。使用官方 `WidgetStatesController` 追踪 hover/focus，显隐保留布局和焦点资格，选中及触控时常显。保留相关状态与官方控制器。 | LSP 零诊断。未跑键盘聚焦隐藏的动作或触屏命中区。 |
| `shell/sidebar/sidebar_views.dart` 1–3 | 纯 View 与模型导出边界。生产 connector、预览和多个 widget 测试经此导入，保留。 | LSP 零诊断及文本引用。未运行外部消费者。 |
| `shell/sidebar/studio_sidebar.dart` 1–510 | 侧栏持有筛选、折叠、搜索防抖、归档和指针输入。目录项目由一次稳定分组保留两组顺序。删除无作用的独立查询广播及底栏 `touchMode` 转发。`projectStructureBuilder` 仍接收防抖后的查询和折叠项，保留定位选中项目的 `GlobalKey`、stable Thread key 和查询 demand。 | LSP 零诊断。未跑置顶排序、切换项目滚动和搜索输入撤销。 |

## M12 会话工作区

| 文件与审读范围 | 责任、证据与处理 | 检查和待覆盖 |
| --- | --- | --- |
| `conversation/workspace/conversation_sidebar_panel.dart` 1–382 | 共用顶栏、页签、文件关闭与状态栏开关。删除没有读取者的 `isOverlay`，窄窗浮层仍由布局壳计算，Plan 预览和测试构造由父代理同步。 | LSP 零诊断。未跑单页签、文件关闭和窄窗布局。 |
| `conversation/workspace/conversation_sidebar_state.dart` 1–173 | 按会话记住面板身份和宽屏模式。待确认 Plan 仅对新身份自动打开，文件关闭回到仍可用的页签。保留局部状态及同步 reconcile。 | LSP 零诊断。未跑同身份重复观察、撤销和文件返回。 |
| `conversation/workspace/conversation_workspace.dart` 1–3 | Native、ACP、预览和测试的共用布局导出。保留活跃入口。 | LSP 零诊断与消费者文本核对。未运行跨包消费者。 |
| `conversation/workspace/conversation_workspace_shell.dart` 1–603 | 管理并排、全宽、窄窗浮层、底栏和 `MultiSplitView`。原 `overlays` 根据测试 key 选 `Positioned.fill`，迁移唯一实参消费者到 `readingBanner` / `readingOverlay` 两个有明确位置的插槽。保留堆叠顺序、移树 key 和分隔条交互。 | LSP 零诊断，全仓搜索无旧实参。未跑分栏动画、Overlay 关闭、Plan footer 和保留时间线焦点。 |
| `conversation/workspace/deferred_runtime_fields.dart` 1–73（本批新增） | 观察 Client 当前字段与时间线 display generation。Todo 和工作流共用读取规则，按现役 lease 借用 `CurrentReadScope`，待办观察独立，状态栏与图共用一个工作流观察。关闭异常经过同一资格检查。 | LSP 零诊断，语义查询定位 `openCurrentScope` 和两处工作流消费者。真实 Client 路径的 widget 用例待复跑。 |

## M18 状态

| 文件与审读范围 | 责任、证据与处理 | 检查和待覆盖 |
| --- | --- | --- |
| `status/context_usage_readout.dart` 1–533 | 上下文、费用、缓存和压缩详情。阈值辅助函数无外部调用，转为私有并删除始终缺省的 marker 参数。保留未知值、百分比边界、多币种和模型全名手动提示，沿用父代理的标准进度环。 | LSP 零诊断。未跑 14 状态旧套件或查看紧凑详情。 |
| `status/session_selectors.dart` 1–688 | 模式、模型、强度与服务档位。父代理已迁移共享触发器，保留其改动、真正 `SubmenuButton`、锁定解释及快照模式文案。 | LSP 零诊断。本批未跑四类菜单或布局测量。 |
| `status/started_items_panel.dart` 1–526 | 能力菜单以及 Skill/MCP/LSP 观察呈现。复用 `StudioMenuButton.icon` 并保留原样式和按键，菜单内 Builder 仍通过官方 `maybeIsOpenOf` 表达观察需求。挂载、收束及重连逻辑沿原链路。 | LSP 解析到共享触发器定义。未跑能力菜单打开时租借 LSP、关闭取消观察或异步重连。 |
| `status/started_items_state.dart` 1–54 | Freezed 的能力、观察状态及动作反馈值。保留 MCP、LSP 的同步状态和活动差别，生成输入保持原样。 | LSP 零诊断。未跑错误、分页和重试的投影组合。 |
| `status/status_bar_item.dart` 1–185 | 状态栏通用按钮、读数和速度格式。保留图标模式、读屏与显式用户激活语义，以及带交互和短提示两类读数。 | LSP 零诊断。未跑读屏、键盘激活或读数省略。 |
| `status/status_view.dart` 1–658 | 状态及能力 ViewModel。删除无分支 switch 和 `_publishCommands` 单纯转发，保留集合页、同一 owner 的命令保活、资源观察、retire/close 和原值解析。 | LSP 零诊断。父代理已统一生成 `StartedItemsViewModel` 对应产物。未跑 deferred 集合、重连与关闭。 |
| `status/thread_status_bar.dart` 1–456 | 独立呈现上下文、Throughput、能力和工作流，窄窗允许整条横向滚动。原 `WorkflowStatusReadout` 只转发给 `WorkflowStatusPill`，原位替换并沿用 run/state key。工作流与 Native 图共用当前 run 读取，加载隐藏旧读数。 | LSP 零诊断。deferred run 用例在修复图布局后待复跑。未跑窄窗键盘和吞吐量增量。 |
| `status/workflow_graph_panel.dart` 1–843 | 运行态工作流图、缩放、快照及 Native/ACP 取值。删除画布无效 hash 缓存与无人读取的 `isInitial`，保留模式变更时 fit。节点底行给长 ID 分配徽章之后的剩余宽度。Native 和缺少 canonical 图的 ACP 使用同一套按请求身份加载、报错和重试的逻辑。保留 `vyuh_node_flow` 主题桥。 | LSP 零诊断。widget 用例覆盖正文代次、Native 图 RPC 乱序及 ACP 切线程，修复后待执行。回边和缩放仍待验证。 |

## M19 待办

| 文件与审读范围 | 责任、证据与处理 | 检查和待覆盖 |
| --- | --- | --- |
| `todo/todo_panel.dart` 1–105 | 用后端待办呈现进度及行状态。计数徽章移入待办组件，与进度条复用 `completedCount`，保留非空才绘制进度、全部完成配色以及未知状态原文。 | LSP 零诊断。未跑未开始、完成、未知、空列表及长文本视觉。 |

## 预览与生成边界

| 文件与审读范围 | 责任、证据与处理 | 检查和待覆盖 |
| --- | --- | --- |
| `shell/previews/sidebar_preview_fixtures.dart` 1–114 | 合成目录、状态、SSH 和本地应用资格。仍为整栏及孤立行/菜单预览提供数据，保留。 | LSP 零诊断。未启动 Previewer。 |
| `shell/previews/sidebar_previews.dart` 1–334 | 使用生产侧栏及组件。归档样本按当前归档开关投影，局部页眉筛选可真正切换，菜单画布留出弹层空间，整块底栏展示选中态后删除重复的按钮预览。随生产移除无作用的查询日志回调。 | LSP 零诊断，旧回调实参已随范围外测试迁移。未看桌面、触屏、大字号或菜单弹层。 |
| `status/previews/thread_status_bar_previews.dart` 1–162 | 状态栏宽/窄/深色样本，实际能力菜单，`thread_status_bar_test.dart` 也使用。原工作流转发 widget 改为生产 `WorkflowStatusPill`，保留可注入 Plan 回调。 | LSP 零诊断。未运行该预览或复用它的 widget 测试。 |
| `conversation/workspace/previews/unified_sidebar_previews.dart` 1–855 | 九种工作区布局。部分交互回调是空实现，状态展示是合成值。该文件为只读范围，已回读父代理迁移后的 `WorkflowStatusPill` 和 Native `TodoCountBadge` 调用。 | 审读时 LSP 零诊断。未跑 Native、ACP 及窄宽 Previewer。 |

生成关系已核对。`shell_view.g.dart` 对应 `shell_view.dart` 的 `persistencePanelView`，`status_view.g.dart` 对应 `status_view.dart` 的 `StartedItemsViewModel`。父代理统一执行 `cargo xtask generate-gui`，退出 0。`started_items_state.freezed.dart` 对应未修改的 `started_items_state.dart`。追加的 deferred 读取使用手写 provider，无生成输入改动。

## 验证与跨界交接

- `cargo dart format` 只处理本批 20 个已修改或新增的 Dart 文件，两次退出均为 0。`git diff --check` 对负责的生产和预览路径返回 0。原生 Dart LSP 对 37 个生产文件、4 个预览和两份新测试均返回 `No diagnostics.`。页眉与能力菜单的语义定义查询解析到 `StudioMenuButton`，页眉工作区行解析到 `workspaceOpenMenuItem`。一次并发引用查询返回 `LSP request timed out: textDocument/references`，从全仓搜索补核 `threadById` 与 `ShellStorageFact` 的消费者。
- `threadById` 在全仓的基线消费者为零，`ShellStorageFact` 的唯一构造位于 `persistencePanelView`，`compactLimitOf` 原引用均在同文件，`overlays:` 原唯一实参在 `AgentWorkspacePane`，`SidebarFooterButton` 去掉原独立预览后只在底栏内部使用。`StudioDriverKeys` 仍定位原按钮和菜单项。
- 收束轮的 12 个 Dart 文件通过 `cargo dart format --output=none --set-exit-if-changed` 与 LSP 诊断，按本轮路径检查 `git diff --check`。两个侧栏菜单解析到 `StudioMenuButton.icon`，智能体菜单解析到 `StudioMenuButton`。三处均用 `crossAxisUnconstrained: false`。项目和会话的旧 driver key 仍在触发按钮外层，智能体旧 key 仍在按钮。已确认 `material_ui` 1.11.0 的 M3 将旧 `BoxConstraints.tightFor` 转为同样的最小与最大尺寸，空 tooltip 保留智能体菜单原样呈现。
- 收束轮范围内已移除 `onQueryChanged`、底栏 `touchMode`、`ConversationSidebarPresentation.isOverlay` 和 `WorkflowStatusReadout`。已回读父代理在增量侧栏测试、Plan 测试和时间线 Plan 预览中的构造迁移。全仓 Dart 调用中已无旧回调实参、工作区 `isOverlay` 实参或 `WorkflowStatusReadout`。`agent_list_layout_test.dart` 的关闭操作由父代理同步为 Escape。
- 启动失败旧 Driver 写入已从 `runtime_banners.dart` 删除，核对 `studio_shell.dart` 所有 part 后删除 Driver 导入。Driver 执行者负责对应存储字段链。实际 native 退出发布和 `snapshotJson` 归原所有者。
- 父代理已从中英 ARB 删除与 `runtime_banners.dart` 旧分支对应的三对 `OtherSession` 文案，生成产物随父代理统一生成更新。
- 菜单用例从生产 `SessionHeader` 和 `SidebarHeader` 进入，覆盖 Escape、焦点返回、键盘重开、禁用项、URL 交付及输入与清空按钮。

## 延迟正文读取与工作流图

1. **字段先到、读取资格后到。** `AgentWorkspacePane` 的 `_DeferredTodoPanel` 之前在取得 lease 前就记下字段。`timelineSessionOwnerProvider` 只提供 AppGraph 的 owner，lease 发布时 owner 身份不变，同一字段可一直无人读取。两个 Native 工作流入口也缺少对 lease 发布的观察。`TimelineSessionOwner.lease` 借出同 Thread 的未退休 display，应用新 display 后由 `_publishState` 发布其 generation。新 provider 订阅 Client 字段和该 generation，lease 或 reader 尚未建立时等待下一次状态变化。
2. **旧正文完成和正常退役。** `TimelineDisplayLease.openCurrentScope` 登记原 query scope。Client 的 `CurrentReadScope._run` 在等待前后检查资格，正常退役会把晚到的成功或错误变为 `StaleConversationScope`。现在失去订阅时 retire scope，等待读取完成后 close，并在发布前核对 provider、现役 lease、原 reader 和完整字段身份。读取和 `scope.close()` 同在外层 `try/catch` 内，失去资格后的读或关闭异常被吸收，当前的读、关闭或解码异常由 `FutureProvider` 保存在 `AsyncError`，Native 图沿现有错误和重试入口呈现。Client 继续校验实际字节窗口。
3. **当前 run 与图请求对应。** 原 Native connector 可能在字段换代时继续使用旧解码 run，也可能把缓存的旧图交给新 run。图查询按 Thread、modeId、graphRevision、graphHash 标识，当前 UI 只观察当前请求键，加载中隐藏上一份图。Client 图 RPC 仍按 Thread ID 读取，响应返回 modeId、节点和边，缺少 graphRevision 与 graphHash，因此只能隔离本地请求代次。
4. **ACP 切线程的 fallback。** `AgentWorkspacePane` 在已有 ACP backend 时可用同一个 `AcpWorkspaceConnector` 切线程。后者按 Thread 保留侧栏选择，`ConversationRightSidebar` 的面板 key 只含页签 kind。两边的工作流面板均可直接呈现时，原未按 Thread 键定的 connector 可复用 State。原 `didUpdateWidget` 沿用旧 `_epoch` 与 `_loadingFallback`，会阻止新请求并允许旧响应落入新线程。现在 ACP 首先呈现 Client 已观察到的 canonical 图，只有已知工作流缺图时订阅同一个按请求身份区分的 RPC provider。

deferred widget 用例通过真实 AppGraph、Client 通知和 `CurrentReadScope` 注入字段头及正文窗口。先让字段头到达，再发布视口需求，检查 Todo 与状态栏可见，以及状态栏和图共享一次工作流正文读取。随后阻塞旧正文、推进新字段并让旧读取失败，检查图面板已消费最新 run、没有出现旧错误或未处理异常。测试以真实关闭报告检查资源收束。此用例注入的是读取失败，`scope.close()` 抛错分支通过代码链核对。整块 `AgentWorkspacePane` 布局仍待验证。

父代理的联合测试为 64 通过、3 失败。本批唯一失败是 deferred 用例在 `takeException()` 读到 `RenderFlex` 向右溢出 1.5 px。Demo 图 `editing_documents` 节点宽 220 px，水平内边距和边框共占 26 px，底行可用 194 px。17 字符的 M3 `labelSmall` 在测试字体下需要 195.5 px，ID 原为 `Row` 的无界非 flex 子节点，省略号无法生效。现在 ID 在剩余宽度内单行省略并对齐行尾。

独立图 RPC 回归从同一 Thread 的两份有效 run 推进生产 connector，只在 transport 端暂挂响应。断言新请求启动时旧请求仍未完成，新图加载前没有沿用旧图，先返回的新图实际呈现 `editing_documents` 活跃节点，晚到旧响应无法替换它。该用例使用原测试视口。

ACP 切线程回归通过真实 Client 的两个 ACP 会话和受控观察帧，先检查 canonical 图直接呈现且零 RPC。保持 connector 在同一个 element 中切线程，令旧线程 fallback 仍在途、新线程缺图，检查新请求可先完成且旧响应无法覆盖新线程的图。

前一轮六个 Dart 文件通过 `cargo dart format --output=none --set-exit-if-changed`，Dart LSP 均为零诊断。此次改动的三个 Dart 文件格式复检退出 0、改动数为 0，Dart LSP 均为零诊断。父代理统一安排共享 checkout 的 Flutter 测试窗口，此次修复后尚未运行 `shell_menu_cleanup_test.dart`。完整 analyze、GUI 和依赖准备均未由本执行者执行。

后续可按场景选择现有 `acp_header_workspace_test.dart`、`thread_status_bar_test.dart`、`sidebar_thread_destructive_action_test.dart`、`agent_list_stop_button_test.dart`、`unified_conversation_workspace_test.dart` 与 `workflow_graph_and_mode_selector_test.dart`。视觉场景包括 300 px 侧栏与大字号、浅深色能力菜单、会话菜单层级、工作区并排与全宽、窄窗浮层及待确认 Plan footer。

## 整合补充

统一生成已完成三对失效 OtherSession 文案的删除。最新 deferred Todo/workflow 与 Native/ACP 图请求隔离共 12 项定向通过，官方窄状态栏、侧栏及工作流分栏图已核对；RPC 响应没有图 revision/hash，保护的是本地请求代次，不声明后端版本验证。完整 UI 初轮 580 通过、2 失败来自其他两处旧 finder，两个失败场景已过滤复验通过，最终分析见总台账；不把表内初审未跑项当作最终阻塞。
