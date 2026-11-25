# 输入交互组逐文件审读表

下列逐文件检查列保留初审时的实际观察与未覆盖边界；后续统一生成、整合测试和官方预览以[总台账](../flutter-quality-audit.md)的验证表为准，不把初审“未运行”当作最终状态，也不把整套通过外推为每项平台行为已验。

下列基线手写 Dart 文件均按文件从开头连续读到结尾，再核对消费链；搜索仅用于定位消费者和删除证据，没有用扫描结果代替全文审读。生成文件只核对分类与边界，不作为手写审读数量。表中的“保留”表示已全文审读后作出的处理结论，不表示运行测试已通过。

## M13 composer：26 个手写文件

路径相对于 `lib/src/features/conversation/composer/`。

| 文件 | 职责与审读结论 | 处理或保留理由 | 真实验证 |
| --- | --- | --- | --- |
| composer.dart | 目标绑定的页面输入边界、失败提交操作 | 保留；Native/start/ACP 选择与提交失败重试由既有 owner 负责，不是死转发 | 全文与消费链核对；未运行 |
| state/composer_input_state.dart | 主动作、停止回执及超时呈现投影 | 保留；发送锁与下一版草稿、停止 accepted 与真实执行状态必须分开 | 全文与消费链核对；未运行 |
| state/composer_view_state.dart | Thread/start 投影与停止交互状态 | 保留；Freezed 输入及已有跨模块消费，routeDisplay 回退等接口由父统一收口 | 全文与消费链核对；未运行 |
| state/start_backend_view_state.dart | 创建期服务和模型目录投影 | 保留；服务可用性、加载和诊断实际被选择器消费 | 全文与消费链核对；未运行 |
| view_models/composer_actions.dart | 输入意图与官方 paste 动作捕获接口 | 保留；文本 fallback 必须保留 editor 的原调用动作及资格，不能自己模拟编辑 | 全文与消费链核对；未运行 |
| view_models/composer_attachment_intents.dart | 绑定原目标的选文件、剪贴板及拖放 | 保留；await 前后资格检查与借用文件 Future 是必要生命周期责任 | 全文与消费链核对；未运行 |
| view_models/composer_projections.dart | 从 Client 当前镜像读取 Native/start 状态 | 保留；child 基线资格、目录关闭状态与当前交互不允许由页面补造 | 全文与消费链核对；未运行 |
| view_models/composer_view_model.dart | 单一目标的意图派发、同步提交冻结及局部错误 | 保留；停止/继续失败由命令板呈现，平台失败单独显示，不能统一吞并 | 全文与消费链核对；未运行 |
| view_models/conversation_backend_view_model.dart | 目录与已打开 owner 的后端判定 | 保留；目录未到与无身份区分，ACP 已有 owner 是有效入口 | 全文与消费链核对；未运行 |
| view_models/start_backend_view_model.dart | 账号需求释放、服务选择及 Native 模型意图 | 保留；当前账号启用校验与创建锁不可删除 | 全文与消费链核对；未运行 |
| views/composer_content_view.dart | 输入外壳、路由配置、主/子交互装配 | 保留；不持业务 await，notice 是局部状态，typed route 和交互 revision 透传完整 | 全文与消费链核对；未运行 |
| views/composer_dock_view.dart | 有界宽度与底栏滚动布局 | 保留；Native 与 ACP 共用，短文件承载明确布局职责 | 全文与消费链核对；未运行 |
| views/composer_route_selectors.dart | Native 模型、推理和 service tier 配置项 | 保留；有独立不可用原因与 measureInlineWidth 契约，不合并为通用配置框架 | 全文与消费链核对；未运行 |
| views/composer_submission_body.dart | 冻结提交正文的 Markdown 与选择范围 | 保留；与状态/控件分离选择区域，禁止隐式图片加载 | 全文与消费链核对；未运行 |
| views/composer_submission_status.dart | 受理、发送、失败和结果未知的呈现 | 保留；accepted 不外推为持久化或执行完成 | 全文与消费链核对；未运行 |
| views/composer_support_views.dart | 停止失败、附件诊断、child 只读面板 | 保留；typed Recovery 全文可访问，独特失败不因文案去重丢弃 | 全文与消费链核对；未运行 |
| views/prompt_composer_view.dart | Native editor 适配与原因区去重 | 改为 listEquals 比较 actions；其余完整诊断身份与三个失败来源保留 | 定向 format；LSP 空；未运行 |
| views/start_environment_bar.dart | 起始项目搜索和环境组合 | 项目菜单改用 StudioMenuButton，删除本地 MenuController；搜索 controller 仍由该组件持有；续轮全域复核后删除纯 false 的 projectOnly 接口/分支 | 定向 format；LSP 空；未运行 |
| views/start_environment_view.dart | workspace/delegation 选择与响应式布局 | 两菜单改用 StudioMenuButton，删除私有触发器；保留约束、key、缺省覆盖与 standalone 说明 | 定向 format；LSP 空；未运行 |
| views/start_model_selector_view.dart | Native 模型与 ACP 服务的统一选择菜单 | 保留；复用 ModelRouteSelector，服务诊断和启用状态有生产消费 | 全文与消费链核对；未运行 |
| views/start_page_composer_view.dart | 创建期卡片外壳 | 保留；只接布局插槽，不持有草稿或后端事实 | 全文与消费链核对；未运行 |
| widgets/composer_attachments.dart | 附件菜单与草稿 rail | 菜单改为 Stateless + StudioMenuButton.icon，移除第二个控制器；当前菜单项同步遵守 enabled；rail 保留 | 定向 format；LSP 空；未运行 |
| widgets/composer_paste_action.dart | 捕获 EditableText 可覆盖的原始 PasteTextIntent | 保留；异步图片读完后仍使用调用时捕获的官方 action | 全文与消费链核对；未运行 |
| widgets/multiline_enter_shortcuts.dart | 局部 Shift+Enter 与官方编辑动作 | 保留；ReplaceTextIntent/UpdateSelectionIntent 维持 selection/undo，IME composing 不拦截 | 全文与消费链核对；未运行 |
| widgets/start_composer_selectors.dart | 创建期模式、模型、推理与 tier 装配 | 保留；实际配置栏消费，模式与 pending/disabled 条件明确 | 全文与消费链核对；未运行 |
| widgets/start_model_selector.dart | Riverpod 后端选择与 typed SettingsRoute 绑定 | 保留；是状态观察和 UI 的薄边界，不另持模型数据 | 全文与消费链核对；未运行 |

## M14 interactions：16 个手写文件

路径相对于 `lib/src/features/conversation/interactions/`。

| 文件 | 职责与审读结论 | 处理或保留理由 | 真实验证 |
| --- | --- | --- | --- |
| connectors/child_interaction_connector.dart | 主会话的 child 决议卡片及 topic 重试 | 保留；计划确认被同判据排除，真实 sync 失败单独显示，不挂载刷新 | 全文与消费链核对；未运行 |
| connectors/hosted_child_interaction_connector.dart | 绑定原 child 请求及 revision 的提交 | 保留；结果归 SDK 命令观察，不建立第二结果通道 | 全文与消费链核对；未运行 |
| connectors/plan_confirmation_connector.dart | 计划事实、资格与本地反馈组件绑定 | 保留；不把计划文档塞入输入视图，修订和批准走同一 owner | 全文与消费链核对；未运行 |
| connectors/tool_approval_connector.dart | 工具批准原因草稿和请求身份门 | 保留；payload/host/child 身份变化清草稿，旧闭包不可混用新请求原因 | 全文与消费链核对；未运行 |
| connectors/user_input_connector.dart | 问题资格、命令状态和请求 key | 保留；线程/交互 key、revision 及 host 决议身份均透传 | 全文与消费链核对；未运行 |
| state/interaction_payload.dart | 载荷呈现快照与 active priority 判定 | 保留；Unknown 是真实协议载荷边界，不能当作兼容死分支删除 | 全文与消费链核对；未运行 |
| view_models/interaction_command_view_model.dart | 共享命令投影、同步门、child 操作观察 | 保留；receipt 与 observed 都齐才给保存提示，生命周期 token 不替代 SDK 所有权 | 全文与消费链核对；未运行 |
| view_models/plan_confirmation_view_model.dart | 当前计划资格与失败/accepted 状态 | 保留；重新核对 thread/revision/question，失败仍可编辑重试 | 全文与消费链核对；未运行 |
| views/child_interaction_view.dart | 来源、revision、等待和失败卡片 | 保留；pending/accepted 的说明不同，blocked 接口后续可由父按公共边界收口 | 全文与消费链核对；未运行 |
| views/fallback_question_dock.dart | 未结构化问题及答案入口 | 透传既有 enabled 禁用 TextField，草稿 controller 保持由 UserInputView 所有 | 定向 format；LSP 空；禁用/恢复回归通过 |
| views/plan_confirmation_view.dart | 本地计划反馈草稿与自适应动作布局 | 保留；平台 send 与局部换行、同请求反馈生命周期已有独立测试 | 全文与消费链核对；未运行 |
| views/tool_approval_view.dart | 批准/拒绝及参数、原因呈现 | 保留；输入和按钮共同使用既有 enabled，不重复做命令校验 | 全文与消费链核对；未运行 |
| views/user_input_view.dart | 多题索引、多选、自由文本与请求语义更新 | 修复 fallback 禁用透传，提交再次检查 enabled；完整问题语义变化才清草稿，密文标记和空答案规则保留 | 定向 format；LSP 空；多选/键盘和草稿回归 2/2 通过 |
| widgets/interaction_widgets.dart | 公用 dock、操作布局与信息块 | 删除失去唯一消费者的 DockOptionRow 和恒返回同色的 switch；续轮全域复核后删除无构造消费者的 plan enum/图标分支 | 定向 format；LSP 空；未运行 |
| widgets/question_progress.dart | 多题进度与跳转 | 保留；属于局部导航和回答统计，不进入业务摘要 | 全文与消费链核对；未运行 |
| widgets/question_step.dart | 当前问题选项及文本输入 | 用 CheckboxListTile 替代手绘勾选与 IgnorePointer/Opacity；保留 first-option key、secret、文本与多选语义 | 定向 format；LSP 空；最终合并 checked、Space 切换及答案回归通过 |

## M17 ACP：36 个手写文件

路径相对于 `lib/src/features/conversation/acp/`。

| 文件 | 职责与审读结论 | 处理或保留理由 | 真实验证 |
| --- | --- | --- | --- |
| acp_views.dart | 纯 ACP 呈现组件导出 | 保留；预览和跨组件测试有实际导入，非旧接口别名 | 全文与消费链核对；未运行 |
| connectors/acp_composer_connector.dart | 原线程的文件、剪贴板与模式绑定 | 保留；picker 捕获原 draft owner，paste generation 和拖放完整 Future 均有必要 | 全文与消费链核对；未运行 |
| connectors/acp_configuration_connector.dart | 配置状态及忙碌原因绑定 | 保留；配置失败及运行/中断资格是协议特有条件 | 全文与消费链核对；未运行 |
| connectors/acp_external_history_connector.dart | 外部历史 dialog 生命周期与首次读取 | 保留；打开结果未知由 ViewModel 承担，不做成功回读 | 全文与消费链核对；未运行 |
| connectors/acp_permission_connector.dart | 权限请求呈现与 answer/cancel | 保留；传原 permissionId 与 optionId，不投射为 Native 二选一 | 全文与消费链核对；未运行 |
| connectors/acp_plan_card_connector.dart | 步骤投影与面板 key | 保留；空态隐藏有实际装配调用 | 全文与消费链核对；未运行 |
| connectors/acp_start_composer_connector.dart | 创建准备、服务/模式选择、接受配置 | 保留；post-frame 校验 workspace 身份，needsConfiguration 不能退化为盲重试 | 全文与消费链核对；未运行 |
| connectors/acp_status_bar_connector.dart | 独立 readout 订阅和侧栏按钮 | 保留；开销较高的详情只在弹层挂载，未按文件长度拆分 | 全文与消费链核对；未运行 |
| connectors/acp_timeline_connector.dart | 行呈现、图片读取与资源侧栏 | 保留；URI 与外部链接有真实薄适配，FileReadingScope 绑定 thread 身份 | 全文与消费链核对；未运行 |
| connectors/acp_workspace_connector.dart | ACP workspace、侧栏和 child 只读资格 | 保留；复用共享壳，本地展开/宽度状态不进入业务事实 | 全文与消费链核对；未运行 |
| state/acp_timeline_row.dart | 既定过程分组、活动工具与思考摘要 | 保留；ACP 有界内容投影，未套用 Native WorkRange 协议 | 全文与消费链核对；未运行 |
| state/acp_view_state.dart | 不可变呈现类型与语义 key | 已处理：父删除无生产构造的 sessionInfo 呈现输入并统一生成；真实外部协议适配保留 | 联合测试中 usage 替代场景及 sessionInfo 输入过滤通过 |
| view_models/acp_composer_view_model.dart | 草稿准入、附件、interrupt run 与命令 | 保留；interrupt 受理与 activeRun 结束分开，原 owner 错误责任不能丢 | 全文与消费链核对；未运行 |
| view_models/acp_configuration_view_model.dart | 官方配置/模式到控件映射 | 保留；空 options 不回退、顺序和 grouped choices 真实有效，legacy 是外部协议适配 | 全文与消费链核对；未运行 |
| view_models/acp_content_view_model.dart | 内容、工具、diff、JSON 与图片映射 | 保留；ACP typed JSON 的 BigInt 及有界 Myers diff 适配不是可直接删掉的普通 JSON 包装 | 全文与消费链核对；未运行 |
| view_models/acp_external_history_view_model.dart | 列举、分页、owner 核对与 unknown 打开 | 保留；unknown keepAlive 防重复外部创建，不能当缓存冗余删掉 | 全文与消费链核对；未运行 |
| view_models/acp_permission_view_model.dart | 权限队列投影和提交失败 | 续轮修复成功/失败的当前动作 token、owner、请求对象和 mounted 资格；旧完成不清除新提交态或覆盖错误 | 定向 format；LSP 空；真实 VM/owner/port 身份回归 6/6 通过 |
| view_models/acp_plan_card_view_model.dart | plan 计数与优先级投影 | 改为只 select plan，与原注释承诺一致；避免正文流导致步骤重映射 | 定向 format；LSP 续轮复查空；未运行 |
| view_models/acp_session_view_model.dart | Client owner 借用与共享观察 | 保留；Ref 不关闭业务 membership，缺目录行不能推断 root | 全文与消费链核对；未运行 |
| view_models/acp_start_composer_view_model.dart | 创建草稿、准备状态及失败投影 | 保留；从 startDraft 原事实派生，不创建第二准备状态机 | 全文与消费链核对；未运行 |
| view_models/acp_status_bar_view_model.dart | 状态、context/cost/throughput/detail | 复用 mapAcpCapabilities 删除重复数组；保留 snapshotConfig 与 raw stop reason 的真实保留快照 | 定向 format；LSP 空；未运行 |
| view_models/acp_timeline_view_model.dart | 能力/header 与有界过程行映射 | 保留；能力映射成为现有复用点，latest usage/commands 与消息边界不改变 | 全文与消费链核对；未运行 |
| views/acp_conversation_composer_view.dart | ACP 准入、slash 键盘与共享编辑器 | 保留；Column 常驻保住 editor identity/composing，slash 是编辑器局部补全而非失焦普通菜单 | 全文与消费链核对；未运行 |
| views/acp_conversation_content_view.dart | Flyer 行身份、欢迎/缺口提示和消息呈现 | 已处理：父删除 sessionInfo 死呈现分支；保留现役内容、历史缺口与 Flyer 身份 | 父修复生成 shader 资产竞争后复跑过程组 25/25 通过 |
| views/acp_external_history_dialog.dart | 搜索、分页与 unknown 行保护 | 保留；本地搜索不改变外部事实，未知结果不显示重试动作 | 全文与消费链核对；未运行 |
| views/acp_start_composer_view.dart | 创建输入与准备诊断 | 保留；共用 ConversationComposer，准备失败和配置确认入口有生产消费 | 全文与消费链核对；未运行 |
| views/acp_status_bar_view.dart | 独立状态读数及详情布局 | 停止原因统一复用 _stopReasonText；保留 BigInt 溢出安全、未知容量与 retained 区分 | 定向 format；LSP 空；未运行 |
| views/acp_workspace_view.dart | 统一 workspace 壳和底部 dock 适配 | 保留；布局插槽有明确作用，不另持业务状态 | 全文与消费链核对；未运行 |
| widgets/acp_configuration_bar.dart | 对端配置控件及 overflow 分类 | 保留父已有 StudioMenuButton 迁移；官方 grouped submenu 与 boolean 控件保留，未覆盖父差异 | 全文与消费链核对；未运行 |
| widgets/acp_content_block_view.dart | Markdown/资源/图片/音频块呈现 | 保留；无隐式资源读取，外部打开由调用方提供；fallback 图像面向纯组件消费者 | 全文与消费链核对；未运行 |
| widgets/acp_message_actions.dart | 本地复制反馈和长消息折叠测量 | 保留；timer dispose 与 post-frame mounted 防护存在，动态内容高度需测量 | 全文与消费链核对；未运行 |
| widgets/acp_permission_dock.dart | 保留对端选项顺序的 dock | 保留；复用 InteractionDockShell 和补丁视图，tone 不改变 option 身份 | 全文与消费链核对；未运行 |
| widgets/acp_plan_card.dart | 步骤进度、优先级和完整文本 | 保留；局部滚动与完成态有独立产品意义 | 全文与消费链核对；未运行 |
| widgets/acp_slash_command_menu.dart | 领先 token 匹配、稳定排序、菜单滚动 | 保留局部 scroll/key 生命周期；改为增删行 key，避免高亮变化全部换 key | 定向 format；LSP 空；未运行 |
| widgets/acp_timeline_process_group_view.dart | ACP 过程组标题和共享折叠壳 | 保留；工具/思考/压缩各有真实协议意义，复用 Native 呈现组件但不复用其历史协议 | 全文与消费链核对；未运行 |
| widgets/acp_tool_card.dart | ACP 附加载荷作用域与共享工具行 | 保留；是必要协议适配，不是可删除的无语义转发 | 全文与消费链核对；未运行 |

## 既有预览：6 个文件

路径相对于 `../anywork_previews/lib/src/features/conversation/`。这些文件同样逐个全文读完。

| 文件 | 职责与结论 | 处理或保留理由 | 真实验证 |
| --- | --- | --- | --- |
| composer/previews/composer_previews.dart | Native 输入、创建、动作矩阵及冻结正文 | 保留；只持合成编辑数据，引用生产组件，宽窄/字号/发送状态各有观察价值 | 全文与消费链核对；未运行 |
| acp/previews/acp_configuration_previews.dart | ACP 创建/运行配置、权限、步骤及历史 | 保留；真实生产组件消费，对端配置 fixture 有合成来源说明 | 全文与消费链核对；未运行 |
| acp/previews/agy_configuration_fixture.dart | 分组模型、强度与 boolean 合成配置 | 保留；被配置预览消费，不读取用户配置 | 全文与消费链核对；未运行 |
| acp/previews/acp_process_group_previews.dart | 运行、失败、长内容和完整会话过程矩阵 | 保留；同时被 acp_process_group_test 复用，非死预览 | 全文与消费链核对；未运行 |
| acp/previews/acp_status_bar_previews.dart | 状态详情、unknown 与超限工况 | 保留；与生产详情同实现，BigInt/retained 状态各有独立观察价值 | 全文与消费链核对；未运行 |
| acp/previews/acp_ux_polish_previews.dart | diff、slash、长消息、权限和外部搜索 | 保留；仍消费生产 workspace、content、permission 与 composer | 全文与消费链核对；未运行 |

新增 `interactions/previews/interaction_previews.dart` 使用官方 @Preview 调用生产 UserInputView，补齐此前没有独立目录预览的结构化/回退问题交互。新增 `test/ui/interaction_cleanup_test.dart` 保护 checked 语义、键盘多选和禁用草稿。两者已通读自身完整输出并做定向静态核对；运行状态见维护笔记与交付报告。

续轮新增 `test/ui/acp_cleanup_test.dart`，使用真实权限 ViewModel、生产 Client owner 和既有可控端口，覆盖 A 迟到成功/失败与 B 提交/失败的交错，以及销毁后完成，实际运行 6/6 通过。父修复两个生成 shader 资产的竞争后遗留并复跑过程组 25/25 通过；本组修正交互测试从合并节点读取有效 SemanticsData，并复用 testWidgets 默认语义生命周期，最窄单文件命令 exit 0、2/2 通过。当前有效结果为 6+25+2=33 个场景通过，来自分次运行；没有重复声称同一次三文件全绿，没有降低选中语义或键盘断言。原始日志位置由交付报告提供，不把日志放入源码。

## 生成边界

基线含 composer 4 个生成文件（两个 state `.freezed.dart`、composer/start_backend 两个 `.g.dart`），interactions 1 个 `interaction_command_view_model.g.dart`，ACP 11 个（`acp_view_state.freezed.dart` 和 10 个 ViewModel `.g.dart`）。合计 16 个，不计入 78 个手写文件的全文审读数量。父代理已统一生成并报告 exit 0；本组未执行生成或手改生成文件。

## 删除消费证据与未扩张范围

- 删除前 `DockOptionRow` 的生产引用只有 `question_step.dart`，没有测试或预览直接消费者；迁移为 CheckboxListTile 后删除声明。`_OptionMark` 仅被该私有选项行消费，随迁移删除。
- `_EnvironmentTrigger` 只有同文件 workspace/delegation 两个菜单使用，两处均迁移到共享菜单；附件和项目选择器的 MenuController 只供本菜单开关，迁移后移除。
- `_mapCapabilities` 只被本文件 session detail 消费，现用既有 `mapAcpCapabilities`；`_badgeBackgroundFor` 所有分支都是相同 primary 色，直接用同一主题值。
- 续轮再次全域搜索确认 projectOnly 仅有其声明、固定 false 传参与条件，plan enum 仅有枚举值和图标匹配分支；删除这两处本组已授权接口，无目录外调用方迁移。没有删除生产文件或既有预览文件，没有修改 Rust、Client、typed route、范围外共享接口、生成物、锁文件或设计文档。目录外两个包含 interactions 的预览文件是 workspace/unified_sidebar 与 timeline/plan_detail，无需迁移。
