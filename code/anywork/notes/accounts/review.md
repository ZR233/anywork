# M23 账号／模型模块逐文件审读与交付

本轮基于父代理已批准的 Flutter 全模块审查计划执行。起始基线为 `3db5e10d03db6a13bcc44b37d37555bcaf80e2c7`，共享分支 `refactor/flutter-quality-cleanup`。业务写入限定账号目录、账号预览、账号专项测试及本目录；没有 Git 写操作，没有改 design、路由、Client/Rust、锁文件或生成物。

## 状态定义与覆盖

- 已清点：48 个生产手写 Dart 文件、7 个账号预览 Dart 文件，合计 55 个；基线合计 21,061 行。`.g.dart` / `.freezed.dart` 不计入手写审读，也未修改。
- 已审读：下列 55 个文件均已阅读全文；长文件按连续职责段读取，没有以 grep、文件名或行数代替正文审读。`AccountMenuButton` 首次审读是父集成前的实现，随后父代理已负责其共享菜单迁移。
- 已处理：下表的“已改”是本执行者修改；“保留”表示已评估职责和调用链后保留，不表示遗漏；“父集成”表示父代理拥有并发改动，本执行者没有改写。
- 已验证：`LSP` 表示首轮变更后的应用文件语义诊断为空；`待统一` 保留初审时的检查状态；后续整合分析、完整 UI 与官方预览结果统一见[总台账](../flutter-quality-audit.md)。父已回报下述四个账号专项测试文件加两项模式测试共 79 项通过；续跑时本执行者获准运行新增 ACP 目录加载的最窄单文件，1 项通过。GUI／官方预览与跨平台行为不据此宣称通过；`预览阻塞` 保留首次检查时独立包缺少 package_config 的现场记录。

## 生产文件台账

以下路径均相对于 `code/anywork/lib/src/features/settings/accounts/`。每行均已清点、已审读。

| 路径 | 审读结论、问题与保留理由 | 已处理 | 已验证 |
| --- | --- | --- | --- |
| `accounts_views.dart` | 纯视图出口未导出 Connector／VM。保存栏移动后仍由 editor_fields 出口自然提供，不新增兼容转发。 | 保留 | 待统一 |
| `state/account_presentations.dart` | 不可变呈现、类型化 Native／ACP 分支、金额字符串和模型规格组有独立语义。后续由主代理加入类型化 Gemini 连接呈现并统一生成，最终规则见 Gemini 呈现说明。 | 保留 | 待统一 |
| `state/account_view_key_values.dart` | 类型化账号／模型身份经 JSON 编码，防止分隔符碰撞；纯 Dart 选择器服务 Driver 与预览。 | 保留 | 待统一 |
| `state/account_view_state.dart` | 路由条目、编辑器、ACP 连接修订、操作反馈分离；不能把这些身份合并成页面索引或 busy 布尔值。 | 保留 | 待统一 |
| `connectors/accounts_connector.dart` | 列表可见性、滚动、每卡订阅与类型化导航装配分明；筛选不承担卡片资源退役。 | 保留 | 待统一 |
| `connectors/account_create_connector.dart` | 创建路由入口的薄装配，稳定 entry key 不含查询提示。虽然短，承担正式路由 API，不作无依据删除。 | 保留 | 待统一 |
| `connectors/account_edit_connector.dart` | 编辑路由入口透传 focusModelId／addModel，不分配第二份草稿身份。 | 保留 | 待统一 |
| `connectors/account_editor_connector.dart` | 全文核对 session、owner、sourceRoute、leaveToken 资格及异步后复核；保留自动授权链接、一次新增模型请求、已创建账号模型保留责任。行焦点只消费最新 typed props。 | 保留 | 待统一 |
| `connectors/account_details_connector.dart` | 详情持有有限模型上下文、区域本地化与删除资格绑定；未将模型草稿锁复制成新状态。 | 保留 | 待统一 |
| `connectors/account_model_connector.dart` | 模型精确身份与 tab 的 typed route 保持单源；显式资料加载仍从已有模型所有者发起。 | 保留 | 待统一 |
| `connectors/account_actions.dart` | 删除前后检查来源路由、仓储、ownerEpoch、实际模型资源与 compactToken；对话框同意不等于任意后续操作授权。 | 保留 | 待统一 |
| `connectors/account_navigation.dart` | 只捕获已存在的草稿 owner；模板替换与路由离页共用决议 UI，实际退役时才清理。各 token 防护不能按“重复判断”删除。 | 保留 | 待统一 |
| `connectors/account_strings.dart` | 只把 l10n 文案交给纯呈现转换，不维护业务状态或校验 reducer。 | 保留 | 待统一 |
| `view_models/account_editor_ids.dart` | 编辑器实例序列与持久账号随机身份分别承担生命周期与跨配置凭据命名责任。 | 保留 | 待统一 |
| `view_models/account_editor_session_view_model.dart` | 实际 mount 资源、模板替换和离页冻结决议内聚；不按行数拆分。Native 模板转换改为共用 projectAccountTemplate。 | 已改 | LSP |
| `view_models/account_editor_view_model.dart` | 全文审读 Native／ACP 草稿、ChatGPT 登录、检测、分阶段保存和迟到结算。保留统一编辑修订和 partial-success 基线；移除无引用 acpChanged，复用模板转换。详见大 VM 判断。 | 已改 | LSP |
| `view_models/native_account_draft.dart` | raw、保存基线和已保存行身份分离；严格正整数与空凭据 preserve 语义保留。不是领域规范快照副本。 | 保留 | 待统一 |
| `view_models/account_models_view_model.dart` | 模型写入、阈值草稿、有限 readout 及 owner/revision 屏障有真实依赖；删除 fence 与不确定结果约束保留，不移出第二份模型事实源。 | 保留 | 待统一 |
| `view_models/accounts_view_model.dart` | 摘要列表、真实卡片保留与唯一账号命令 owner 内聚；删除成功需操作保存和规范缺席同时成立。未知结果保责不能与普通命令清理合并。 | 保留 | 待统一 |
| `view_models/account_card_view_model.dart` | 单卡只读投影与刷新意图；共享 projectAcpPhase 替换重复阶段 switch，status 从同一阶段派生，保留 cancelled／默认 ACP 文案及连接优先级。 | 已改 | LSP |
| `view_models/account_details_view_model.dart` | 详情、用量初始刷新和计费操作各自按真实来源身份约束；列表动作仅消费既有不可变投影。 | 保留 | 待统一 |
| `view_models/acp_account_view_model.dart` | 安装意图、认证与取消各自有 operation 身份；安装阶段覆盖连接阶段是实际业务差异，保留。连接阶段复用 projectAcpPhase。 | 已改 | LSP |
| `view_models/acp_command_notice.dart` | 认证失败与配置失败按账号、连接、操作区分；busy 去重只在同一在途上下文成立，不是通用错误吞掉。 | 保留 | 待统一 |
| `view_models/account_operation_result.dart` | 一次冻结失败不回读升级为成功；观察只等待已准入操作，不重新发送。页面销毁仅结束本地等待。 | 保留 | 待统一 |
| `view_models/account_projection.dart` | 金额精度、用量状态、ACP 安装／升级格式化仍从真实来源派生；增加共用模板映射和 ACP 连接阶段映射，删除调用方重复规则。 | 已改 | LSP |
| `views/accounts_list_view.dart` | 搜索、分类与布局只发意图；cardBuilder 保留每卡独立订阅边界，不直接查询业务。 | 保留 | 待统一 |
| `views/account_details_view.dart` | Native 与 ACP 详情按 typed content 组合；混合用量、设置、模型共用现役组件。局部折叠与页面滚动独立。 | 保留 | 待统一 |
| `views/account_model_details_view.dart` | NestedScrollView、官方 tab 几何、typed tab props 与独立存储键配合；controller 只承载动画，不作第二路由。 | 保留 | 待统一 |
| `views/native_account_editor_view.dart` | 外层降为 StatelessWidget；移除 GlobalKey Map、共享焦点节点、generation／completed 调度。稳定行 key 包含 editorId 与 editorKey，仅向行传目标字段；保存栏移到共同表单文件。 | 已改 | LSP |
| `views/acp_account_editor_view.dart` | 参数／环境列表仍保留 raw 输入与本地字段几何；不再为保存栏导入 Native 页面。删除恒 true 的 saveIsPrimary 参数。 | 已改 | LSP |
| `views/account_dialogs.dart` | 保存／放弃和删除对话框为纯意图。移除生产已无调用、仅两项预览引用的旧 AccountTemplatePickerView。现役同页选择器不受影响。 | 已改 | LSP |
| `widgets/account_editor_fields.dart` | 共用 scaffold、连接字段和保存栏内聚。模型行自己持有 ID／名称各自 FocusNode；布局后用官方 focus traversal helper；请求身份和 mounted 撤销旧回调。删生产不用的 dirty 标题参数及无消费者的次级保存分支。 | 已改 | LSP |
| `widgets/account_sections.dart` | AccountRawTextField 只持有 controller／selection／composing，raw 仍外部权威；独立 PageStorageBucket 防止输入／选择文本与折叠 bool、页面 offset 串用。 | 保留 | 待统一 |
| `widgets/account_template_selector.dart` | 使用官方 DropdownMenu 搜索、过滤与选择，受控选择拒绝后恢复显示；Gemini 目录合并属于既有产品呈现，不能随手删掉。 | 保留 | 待统一 |
| `widgets/account_gemini_connection.dart` | 指导与端点预设仍服务现役接入；存在协议文字／端点推断的结构化边界问题，须协调生成契约，见下文。 | 保留／报告 | 待统一 |
| `widgets/account_billing_control.dart` | field 与 settingsRow 是真实布局差异；官方 DropdownMenu 的文字控制器承接受控值回写，菜单动作复用账号薄组合。 | 保留 | 待统一 |
| `widgets/account_identity.dart` | 品牌资产、默认标记、布局与副标题选择策略单一生产实现；列表安全 origin 与详情可选全文有不同手势语义。 | 保留 | 待统一 |
| `widgets/account_list_item.dart` | 菜单与详情点击入口为兄弟节点，避免动作冒泡；用量、升级和身份复用现役组件。长状态的有限宽度／换行需统一预览复核，见下文。 | 保留／报告 | 待统一 |
| `widgets/account_menu_button.dart` | 首次读完原 MenuAnchor＋FocusNode 版本；按父最新通知，由父改成 StudioMenuButton 的账号样式薄组合，接口不变。本执行者未修改／格式化该文件。 | 父集成 | 父负责 |
| `widgets/account_details_header.dart` | 身份与操作栏复用、Native／ACP badge typed 分支、宽窄布局内聚。 | 保留 | 待统一 |
| `widgets/account_models_view.dart` | 目录分组、模型 ExpansionTile、窄动作及 compact 复用；实际展开状态由 ExpansibleController 读取，未另存 bool。 | 保留 | 待统一 |
| `widgets/account_compact_view.dart` | 比例与 raw 只发草稿意图，保存／恢复自动分离，显示有效值与调整事实；不在 View 计算最终阈值。 | 保留 | 待统一 |
| `widgets/account_model_specifications.dart` | 三组规格来自 VM typed facts，价格／性能保留结构化来源及缺失值，视图不解析本地化标签归类。 | 保留 | 待统一 |
| `widgets/account_model_evaluations.dart` | 分布、两种评分、未评级与过滤界面保留；有限样本窗口和排序由模型 VM 负责，View 无第二份归约。 | 保留 | 待统一 |
| `widgets/account_usage_metrics.dart` | 余额保留原始 decimal 字符串；详细布局按真实数值宽度、主次读数决定，不能与 quota grid 机械合并。移除详细布局已返回后的不可达 detailed 分支。 | 已改 | LSP |
| `widgets/account_usage_view.dart` | 计费、余额健康、查询阶段、last-good 和密度独立；状态 wrap 变体是现役展示能力，保留。 | 保留 | 待统一 |
| `widgets/acp_account_panel.dart` | 操作能力来自 VM，主／次／文档动作、登录方式、版本、用量独立组合；没有新建认证状态机。 | 保留 | 待统一 |
| `widgets/acp_upgrade_banner.dart` | 每个升级阶段表达不同事实和动作；列表 compact 与详情 embedded 复用同一 banner，已有版本、运行版本和新版本不可混为一值。 | 保留 | 待统一 |

## 预览文件台账

以下路径相对于 `code/anywork_previews/lib/src/features/settings/accounts/previews/`，均已清点、已全文审读。

| 路径 | 审读结论、问题与保留理由 | 已处理 | 已验证 |
| --- | --- | --- | --- |
| `account_preview_fixtures.dart` | 合成数据保留 Native／ACP 同名 ID、金额精度、多币种、登录及升级状态。conceptDetails 是同生产组件的不同上下文窗口输入，没有第二套 UI；宽窄维度仍有价值。 | 保留 | 待统一 |
| `account_template_preview_fixtures.dart` | 模板静态输入工厂、未知用量能力与 Gemini 数据独立；模板事实不被别的供应商能力默认值替代。 | 保留 | 待统一 |
| `account_list_preview_data.dart` | 预览静态行数据与生产列表成员模型隔离，不往生产 VM 塞预览行。 | 保留 | 待统一 |
| `account_preview_host.dart` | 本地记录动作、主题和本地化不创建 Client；表单场景只编辑合成 props。场景身份、locale 与文字缩放控制官方预览重建。 | 保留 | 待统一 |
| `account_template_previews.dart` | 各模板调用共同 host 和生产组件；ChatGPT、Gemini 和 ACP 的独有展示维度保留。 | 保留 | 待统一 |
| `account_component_previews.dart` | 组件／整页含阈值、tab、菜单、状态长文案、手动行焦点的现役预览；删除只在 preview 出现的 scaffold dirty 输入及过时场景名。 | 已改 | 预览阻塞 |
| `accounts_previews.dart` | 删除旧独立模板选择页的两项预览；修正已失真的“save secondary”名称，保留同页生产编辑入口与真实状态组合。 | 已改 | 预览阻塞 |

## 焦点与草稿保护的完整调用链

`AccountEditConnector` 透传 typed route query → `AccountEditorEntryConnector` 持有实际 route entry 的 session → `AccountEditorConnector` 对当前 session／editor／owner／ModalRoute 复核 → 已准入的 addModel query 由 VM 只消费一次；普通定位按模型 ID 找到稳定 editorKey → `NativeAccountEditorView` 仅传目标行字段 → `AccountManualModelEditor` 的本地焦点节点。

外层现在没有每行 GlobalKey 注册表，没有共享 FocusNode 在不同输入框之间转移，也没有 `_focusGeneration`、`_scheduledGeneration`、`_focusCompleted`。行的 `(editorId, editorKey)` key 保留同一草稿的输入控制器、selection／composing 和焦点几何，真实编辑器替换则重建局部字段。各字段本身仍使用原 manualField 选择器，没有改变 Driver 定位契约。

仍保留一次布局后回调：行必须已经附着、完成布局，官方 helper 才能从节点上下文访问滚动区域。回调捕获本行请求身份；字段目标变化或取消会替换该身份，行销毁通过 mounted 拒绝，避免旧请求抢焦点。原始字段、业务草稿、模型 ID 校验和保存资格仍归 VM／原 Client owner。普通 raw／观察刷新不会重发焦点请求；原 route callback 的资格检查未删。

采用已安装 Flutter 官方 `FocusTraversalPolicy.defaultTraversalRequestFocusCallback`，它直接执行 requestFocus 和 Scrollable.ensureVisible；保留 `.15` 对齐及零时长。核对的是当前 SDK 源码 `packages/flutter/lib/src/widgets/focus_traversal.dart:202` 的正式 API 契约，以及 `EditableText` 失焦时清理 composing 的官方行为；不新增焦点框架、自动重试或 overlay。官方参考：https://api.flutter.dev/flutter/widgets/FocusTraversalPolicy/defaultTraversalRequestFocusCallback.html 。

## 最小必要复用与大 VM 判断

- `AccountEditorFooter` 从 Native 页面移动到共同 `account_editor_fields.dart`，Native／ACP 继续使用同一组件；删除从 ACP 到 Native 页面的 import 和没有消费者的 saveIsPrimary=false 分支，生产仍是原 FilledButton。
- `projectAccountTemplate` 共用 Native 目录的类型化呈现转换，供 session 目录和具体编辑器使用；没有共享各自草稿或观察责任。
- `projectAcpPhase` 共用连接状态先于认证状态的映射，供卡片和详情使用。安装准备覆盖仍留在 ACP owner；卡片取消与默认 ACP 文案仍按原语义选择。
- editor VM 很长，但其 dirty、revision、保存基线、部分成功和未知结果资格由同一编辑器控制。将 Native／ACP 保存拆成独立 provider 会改变原子资格边界，不能为了行数机械拆分。本轮抽出已有重复的纯转换并删无引用转发，没有引入“万能编辑器”或第二 owner。
- models VM 的 compact、readout 与目录依赖同一修订／资源身份；accounts VM 的卡片 lease 与操作 owner 也各有真实生命周期。共有操作结算已经在 `account_operation_result.dart`，不再加平行抽象。

## 测试变更与推荐最小集

新增 `code/anywork/test/ui/account_manual_model_focus_test.dart`，通过生产 NativeAccountEditorView 的真实字段检查：

1. 目标行进入视区；行重排及无关观察刷新保持 raw、selection、活动 composing；路由式目标切换后可在不同字段间聚焦，已离焦的 composing 遵循 Flutter 正常清理。
2. 目标行尚不存在时不误焦，出现后定位；用户手动选择别的输入框后，同一定位提示及 raw 刷新不抢焦点；删除目标行后保留行可继续输入。
3. 真实 editorId 替换即使复用同名行键，也不复用旧编辑器的局部输入控制器；卸载后不留失效回调异常。

扩展现有 `test/unit/account_cards_view_model_test.dart` 的认证观察用例，检查 cancelled／unchecked／retrying + cancelled 的真实卡片阶段和文案，保护共用映射的优先级；没有写源码文本断言或只验证 fake 自己。

父代理统一运行时，建议从仓库根使用既有应用包装入口（不要与其他验证并发改写缓存）：

```sh
cargo flutter test --no-pub test/ui/account_manual_model_focus_test.dart test/ui/accounts_typed_route_contract_test.dart
cargo flutter test --no-pub test/unit/account_cards_view_model_test.dart test/unit/accounts_view_models_test.dart
```

第一条保护焦点、路由查询不换草稿、迟到 add 提示和真实离页决议；第二条保护模板转换、ACP 阶段、草稿保存和资源资格。父计划中的完整 unit／UI、analyze、官方 preview 仍由统一验证执行者选择和运行，本执行者未执行这些命令。菜单集成另建议复核既有账号菜单预览、billing dropdown 和取消返回焦点。

## 实际检查结果与限制

- 在 `code/anywork` 使用当前官方 `dart format`，仅列出本轮 14 个 Dart 文件（10 生产＋2 测试＋2 预览）；首次结果 `Formatted 14 files (6 changed) in 0.51 seconds`，退出码 0。之后只对测试中的一行断言按官方失焦语义修正，交付前再次格式化该文件，结果 `Formatted 1 file (0 changed) in 0.02 seconds`，退出码 0。
- 原生 Dart LSP：`.anywork/lsp/dart.toml`，SSH 工作区、现有 Flutter bundled Dart，ready；未重新配置／pub get。对实际 AccountManualModelEditor 符号、TextField 定义和废弃 API 引用完成语义查询。注意 findReferences 的应用分析上下文不涵盖未解析的独立预览包；删除旧 Picker 另用全 code 范围非生成 Dart 调用检索确认只有两项预览消费者。
- 格式化后 10 个生产修改文件及 2 个账号测试文件分别查询 LSP diagnostics，均为 `No diagnostics`。修正过一次 Stateless 化后跨行残余的 widget 引用，并重新查询为空。最终测试断言修正后也再次查询为空；对实际 helper 调用执行 goToDefinition，落到当前 SDK `focus_traversal.dart:205:15`，确认使用官方声明。
- 两个预览修改文件的 LSP 验证被准备条件阻塞：`code/anywork_previews/.dart_tool/package_config.json` 实际不存在；报 `Target of URI doesn't exist`，涉及 `package:flutter/widget_previews.dart`、`package:material_ui/material_ui.dart`、`package:anywork/...`，后续 undefined 类型诊断为其级联。没有为了消除错误改源码 import 或伪造 package_config。需父在统一窗口准备独立预览包依赖后重新验证。
- 范围内 `git diff --check` 退出码 0。首轮本执行者只做格式／LSP／只读检查；父后续回报四个账号测试文件加两项模式测试共 79 项通过。续跑的最窄单文件结果见下一节。没有执行 pub、生成、整 analyze 或 GUI，没有外推跨平台原生行为。

## ACP 模板加载的真实路径核验

`AcpAccountViewModel._loadTemplates` 调用的是实际 `AcpServiceImpl.loadTemplates`，后者在 `code/anywork_client/lib/src/acp/data/acp_service_impl.dart:124` 交给 `_starts.run`。实际符号语义定位到 `code/anywork_client/lib/src/studio/commands/command_lane.dart:21`：正常路径使用 `Future.sync(operation).whenComplete(...)`，关闭 lane 时返回 `Future.error`。因此即使底层目录端口同步 throw，错误也经 Future 交回，VM 的 await 会先让 `_templateLoadFuture = task` 完成赋值，再执行 catch／finally。本次没有证据支持原先怀疑的生产 late 初始化缺陷，没有为防御生产不可达路径改写原方法。

新增 `test/unit/account_acp_template_loading_test.dart` 使用现有 SDK `AccountsTestRuntime` 装配真实 AccountDomainResources、AcpServiceImpl、CommandLane 和账号 VM；仅外部目录端口第一次同步抛出 StudioFailure，第二次由可控 Future 返回合法模板。用实际 auth／install 观察就绪通知消除环境准备竞态，检查原错误文案、重试动作、空目录、两次重试共用一个真实查询、成功目录、文档链接及无未收束资源。没有替换 AcpService 为同步抛错的假实现。

实际运行 `cargo flutter test --no-pub test/unit/account_acp_template_loading_test.dart`，最终结果 `+1: All tests passed!`，退出码 0。测试准备期间的构造／导入错误和基线观察未就绪导致的断言失败已修正，它们不计作生产缺陷复现或先红后绿证据。新增文件已按官方格式化，移除未用 import 后再次格式化为 0 changed，LSP 为 `No diagnostics`；没有重跑父已经完成的广泛测试。

## 交给父代理的跨界／后续事项

1. 父已实现 `lib/src/shared/widgets/studio_menu_button.dart` 的 `StudioMenuButton`（text／icon），并负责把 AccountMenuButton 改为账号样式薄组合；其对外接口保持。本执行者没有改该文件或共享组件。菜单回焦／outside tap 消费由父验证。PR #596 后续分层将共享组件迁入受检查的 `shared/widgets/`，账号包装只保留标签、图标和按钮样式。
2. 删除旧 Picker 后，`shared/studio_driver_keys.dart` 与 `shared/studio_driver_key_values.dart` 中仍有 `accountTemplatePicker` 选择器常量，全 code 检索未见现役挂载点。Driver 组已删除这些无消费者常量，没有新增兼容挂载。
3. Gemini 文本／端点推断已只读追到 NativeAccountDraft、Client details／template 字段及 FRB adapter。具体的权威来源、无模板与缺失模板区别、最小 typed 指导值、能力 badge 的产品决定，以及生产／fixture／生成输入变更清单见 [Gemini 呈现决定](gemini-presentation.md)。随后由主代理完成类型化呈现、投影及生成输入迁移，实际修后测试和官方预览结果以该文档为准。
4. `account_list_item.dart` 宽布局状态区的 singleLine／非 flex 曾被列为静态风险。官方既有长英文状态场景在 960px、1.0× 与 1.3× 下均完整显示 “Preparing managed connection”，主代理已核对两张真实图，无溢出或不可读；该候选未复现，不据静态结构改写生产布局，也不外推任意字符串／窗口组合。
5. `_loadTemplates` 同步 throw 怀疑已按真实实现核验并用真实领域装配单测收束：错误被 CommandLane 转为 Future，未复现 late 初始化缺陷；生产方法保持稳定，详见上节。
6. 父确认删除的旧 Composer／Diagnostics／Usage／Activity 投影不改变现役账号 VM；本模块没有借清理改写这些共享边界。

本页保留模块审读与处理依据；最新跨模块验证和整体接受状态见总台账。
