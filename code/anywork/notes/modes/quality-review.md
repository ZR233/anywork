# M21 工作模式模块质量审读

基线 `3db5e10d03db6a13bcc44b37d37555bcaf80e2c7`，分支 `refactor/flutter-quality-cleanup`。逐行阅读下表 15 个应用手写 Dart 文件和 1 个预览文件。行号为基线范围。另核对了 Client 编辑 owner、文档转换、工作区及详情路由、现有离页测试和锁定依赖。生成文件只在确认选中值等价与生成接口时作为证据。

## 逐文件记录

应用文件均相对于 `lib/src/features/modes/`。预览文件位于独立的 `anywork_previews` 包。

| 文件及审读范围 | 证据、处理与保留理由 |
| --- | --- |
| `modes.dart` 1–10 | 路由仍消费 `ModeWorkspacePage`、`ModeDetailPage`、`confirmLeaveModeEditor`，设置页仍消费目录 tab。保留导出边界。 |
| `mode_editor_dialogs.dart` 1–651 | 新建转换窗口与详情重复构建来源和目标控件，`initialTargetId` 从无调用，重复转换分支的空 `setState` 无可见效果。复用阶段下拉框，表单内部自行管理选择反馈。移除死参数与空重建。传入结束阶段或不存在的来源时显示未选并由原校验文案提示。保留脏草稿的忙碌、保存、放弃、取消判定及各确认对话框语义。 |
| `mode_editor_support.dart` 1–136 | 新建模板建立于 Client 的领域模型。保留驱动键、最小模板和无工作流模板。窄屏 query 与选中控制器原先各解一遍 `edge:source->target`，现使用一个解析入口，保留无效值拒绝规则。 |
| `connectors/mode_editor_actions.dart` 1–218 | 连接层通过 `ModeEditorOwner.replace` 和 Client 变换提交意图，保留最大阶段数、初始阶段候选及端点检查。添加转换与重命名弹窗返回后核对 `context.mounted`，避免已销毁视图继续读 `WidgetRef`。 |
| `state/mode_workspace_view_state.dart` 1–33 | `section`、`selection`、`focus`、校验揭示状态和预演理由均为呈现信息。保留 Freezed 契约与草稿归属。 |
| `view_models/mode_workspace_controller.dart` 1–99 | `selectStage` 的两个分支均写回原 `section`。删除自赋值，复用 Freezed 选择值相等判断与统一边解析。保留切换文档的选中、校验、聚焦重置。 |
| `views/mode_catalog_tab.dart` 1–350 | 路由文件有重复 import，打开失败重复构建 SnackBar。合并入口。保留可见性门控、先解决脏草稿后打开/新建/导入及原始 JSON 文本交给 Client 校验。 |
| `views/mode_detail_page.dart` 1–164 | 构建标题和正文各解析一次选择，解析器的 `WidgetRef` 形参为空转发，文档替换参数缺类型。一次解析并复用，保留实时选择优先和路由 query 恢复，删除阶段确认后补挂载检查。子路由构造签名与返回时的清理仍供共享路由使用。 |
| `views/mode_workspace_page.dart` 1–1162 | 预演开始、重开此前传两个同样的 `reset: true` 闭包，改为单个意图。补宽屏阶段删除确认后的挂载检查。保留编辑器命令、忙碌/只读控制、画布稳定元素槽、视口、断点和窄屏路由边界。 |
| `widgets/mode_detail_sections.dart` 1–110 | `ModeDetailStageLink.icon` 无传值调用，组件直接设置原默认图标。保留标题、可替换尾部操作及只读提示。 |
| `widgets/mode_editor_fields.dart` 1–83 | 文本回流比较同时核对传入值与控制器文本，避免 Client 草稿回显重置光标或 IME。保留此条件和释放 controller。增加阶段下拉字段，使用标准 `DropdownButtonFormField` 的初始值、校验和选项。 |
| `widgets/mode_editor_panes.dart` 1–1090 | 设置初始阶段复用阶段下拉字段。预演只暴露一个启动/重开动作，两个标签及忙碌条件仍各自显示。校验列表直接消费 issue。保留 JSON 的等宽、占满空间及只读行为，保留预演 `currentState`、`terminal`、路径及最近结果，渲染继续消费 Client 快照。 |
| `widgets/mode_stage_detail_panel.dart` 1–369 | `WorkflowStateKind` 经字符串编码再解码。改用原领域 enum；保留选项、键、只读详情、锁定初始阶段开关和底部删除操作。 |
| `widgets/mode_transition_detail_panel.dart` 1–249 | 两个端点字段和新建转换重复构建。复用下拉字段且保持端点 key、来源限 atomic、目标含 final、重复端点提示和变更后恢复对应选中。 |
| `widgets/mode_workflow_canvas.dart` 1–881 | 历史补丁在同步选择前抓取全局焦点，调用 NodeFlow 的选择方法后又请求旧焦点。改为在同步内抑制画布自身的焦点请求。NodeFlowEditor 自己同步 `behavior`，删除重复推送。删除始终允许删除连线的回调、未用私有默认参数和条件已确定的样式分支。保留同步回声保护、`mounted`、controller 生命周期、合法图投影筛选、品牌色和 Material UI 依赖桥。 |
| `anywork_previews/lib/src/features/modes/previews/modes_previews.dart` 1–142 | 四个官方 `@Preview` 入口直接使用两个生产详情面板，数据合成、回调为空。更正声称会记录动作的注释，保留既有预览入口与尺寸。 |

## 画布焦点证据

- `git blame` 将 `previousFocus.requestFocus()` 追到 `70b0137b5` 初版编辑器。Flutter 的焦点请求等到微任务才提交。当同一帧已请求另一个输入框时，`primaryFocus` 仍指向旧输入框。旧补丁重新请求该旧输入框会覆盖更新的请求。官方 SDK 的 `focus_manager.dart` 546–555、1169–1195 可核对 setter、焦点提交及 `_markedForFocus`。 [Flutter `FocusNode.canRequestFocus`](https://api.flutter.dev/flutter/widgets/FocusNode/canRequestFocus.html) · [Flutter `FocusNode.requestFocus`](https://api.flutter.dev/flutter/widgets/FocusNode/requestFocus.html)
- 应用锁文件、现有包配置及缓存清单均指向 `vyuh_node_flow` `0.32.0`。`node_api.dart` 744–833 的 `selectNode`、`selectNodes` 以及 `connection_api.dart` 475–510 的 `selectConnection` 均只有 `toggle` 参数，而且同步触发 `canvasFocusNode.requestFocus()`。实际通过 SSH 读取相同版本的 pub.dev 文档并复核本地源码。 [选节点](https://pub.dev/documentation/vyuh_node_flow/0.32.0/vyuh_node_flow/NodeApi/selectNode.html) · [批量选节点](https://pub.dev/documentation/vyuh_node_flow/0.32.0/vyuh_node_flow/NodeApi/selectNodes.html) · [选连线](https://pub.dev/documentation/vyuh_node_flow/0.32.0/vyuh_node_flow/ConnectionApi/selectConnection.html)
- `GraphApi.selectSpecificNodes` 可无焦点地重置节点选中集合，但只写节点选中，单独切换时不会清除连线选中。连接 API 有选中全部连线或单条选中，没有等价的无焦点按 ID 批量接口。继续调用组件自身选中入口以保留节点与连线的互斥行为。 [按 ID 选择节点](https://pub.dev/documentation/vyuh_node_flow/0.32.0/vyuh_node_flow/GraphApi/selectSpecificNodes.html) · [连接 API](https://pub.dev/documentation/vyuh_node_flow/0.32.0/vyuh_node_flow/ConnectionApi.html)
- 使用 controller 已持有的公开 `canvasFocusNode`。仅当画布未持有焦点且能请求焦点时，同步期间临时将 `canRequestFocus` 设为 `false`，在 `finally` 恢复。已经获得焦点的画布继续接收键盘操作。业务选中回调抑制与焦点拦截分属两个条件，前者保护上游状态免受投影回声影响。 [画布焦点节点](https://pub.dev/documentation/vyuh_node_flow/0.32.0/vyuh_node_flow/NodeFlowController/canvasFocusNode.html)

## 验证与剩余事项

- 已对改动 Dart 文件使用 Dart 3.14.0 格式化并检查范围内 Git 差异。现有 native `dart` LSP 为 ready。定义查询确认 `selectNode`、`selectConnection` 和 `canvasFocusNode` 解析到 0.32.0 缓存源码，`canRequestFocus` 解析到 Flutter SDK。引用查询确认阶段下拉字段被三个编辑入口复用。
- 对 15 个应用手写文件和两个新增测试查询文件级诊断，均返回 `No diagnostics`。初审时独立预览包尚无自己的 `.dart_tool/package_config.json`，LSP 曾返回 44 项导入无法解析的诊断。该历史环境问题已随依赖准备消除，最终预览包官方 `flutter analyze --no-pub` 为 `No issues`，实际预览也已完成；不再属于当前阻塞。
- 稳定窗口可在 `code/anywork` 使用 `flutter test --no-pub test/ui/mode_workflow_canvas_test.dart test/ui/mode_editor_test.dart`。两个新测试文件已在账号/模式六文件联合运行中通过（总计 79 项，exit 0），统一生成已完成。画布用例预期程序选择节点和图重载后选择连线均成功，不发用户选择回调，输入焦点维持或按本帧较新的请求切换，实际点击后画布取回焦点。表单用例预期结束阶段不能作为来源，修正后可选结束阶段为目标并提交去除首尾空格的条件。
- `test/ui/accounts_typed_route_contract_test.dart` 860–897 已间接覆盖脏模式草稿离开设置时的取消和放弃。此处为初审记录；后续账号／模式联合 79 项已通过，两次统一生成均成功，`ModeWorkspaceController` 的 Riverpod 产物已同步。最终分析和预览结果见总台账。
- 详情窄屏的 route 查询恢复、宽屏嵌入和共享路由守卫仍走原路径。工作区按 `document.definition.id` 判断挂载时是否打开与重置呈现状态，路由守卫使用 `openedModeId`。两种身份在 JSON 改名时可以不同，若调整挂载和路由语义需在共享路由验收中处理。异步弹窗补足销毁检查后，跨草稿代次的身份核对仍归后续共同边界验证。
