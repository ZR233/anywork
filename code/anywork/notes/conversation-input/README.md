# 会话输入与交互维护笔记

本目录记录 composer、interactions、ACP 输入交互组的职责、审读结论和验证边界。逐文件记录见 [审读表](review.md)。这里保留可复用的维护知识，不存命令日志、截图、临时脚本或文件摘要。

## 所有权与维护边界

- Native 草稿、附件、提交及命令事实由 SDK-only Client 持有。Composer ViewModel 只观察原 owner 并派发目标绑定的意图；不能把 Future 完成、命令 accepted、历史可见与持久化成功合并成一种成功状态。
- `ConversationComposer` 统一持有编辑器控制器、焦点、选择与 composing。目标 identity 变化时换编辑器；同一目标的菜单和状态更新不得重新挂载编辑器。异步粘贴、文件选择及拖放继续检查原目标资格，拖放必须返回完整 Future 以覆盖借用文件的有效期。
- 当前交互与子任务交互观察沿用 Client 的 Current/History、基线资格及操作观察资源；ViewModel 的同步门只防重入，不替代命令事实。child 的计划确认仍是诊断，不变成 host 可代答的问题。
- ACP 属于外部协议。`legacyMode` 是仍在使用的 ACP `modes` 适配；`configOptions != null` 即使是空数组，也不能退回 `modes`。保留对端顺序、权限 option ID、会话 owner 身份、窗口缺口及外部历史 unknown 结果，不补造 Native 的 ACK、历史或恢复保证。
- 页面退出释放本地呈现资源；业务 membership 与在途命令由原 owner 承担。不要为“减少状态”删除 cancel/join、代际检查、草稿保存或失败出口。

## 本组清理结果

1. 附件入口、起始项目搜索、工作区模式和委派菜单复用 `StudioMenuButton`。组件持有唯一稳定焦点；调用方只提供内容与动作。项目搜索和委派保留 `crossAxisUnconstrained: false`、原高度/宽度限制、onOpen 清空搜索及语义 key。ACP 配置栏已有的共享菜单迁移保留。
2. 问题多选改用官方 `CheckboxListTile`，删除唯一消费者已迁移的 `DockOptionRow` 与手绘 `_OptionMark`。整行点击、键盘操作、checked 和 disabled 语义由官方控件统一处理；多选答案及自由文本仍归 `UserInputView` 的局部草稿管理。
3. 回退问题输入框遵循已有 `UserInputView.enabled`，失去决议资格后禁用编辑，恢复资格后保留草稿。提交边界再次检查 enabled。只向本组内部 `FallbackQuestionDock` 透传已有资格，没有增加页面或 Client 呈现输入。
4. Recovery 诊断的 actions 有序相等比较复用 Flutter `listEquals`，其余身份、范围、影响和 detail 比较保留。普通失败不按文案去重。
5. ACP 状态详情复用既有 `mapAcpCapabilities`，连接状态复用同文件停止原因翻译。计划面板用 `.select` 只观察 plan，避免消息正文流触发步骤重映射。
6. 斜杠菜单保留滚动控制器及按位置管理的行 key，只有命令数量变化时增删 key；高亮变化不再销毁全部行的局部焦点状态。输入层现有 IME、Enter/Tab、Escape 与线程身份处理保留。
7. 删除全域无 true 消费者的 `StartEnvironmentBarView.projectOnly` 参数/分支，以及无构造消费者的 `InteractionDockKind.plan` 枚举值与图标分支；其他调用方无需迁移。
8. ACP 权限决议在本 ViewModel 用独立动作 token 绑定当前请求对象，成功与失败共用 mounted、动作 token、会话 owner 和当前请求资格检查。请求切换清理旧呈现状态；旧 Future 仍正常收束，但不能清除新操作的 submitting 或覆盖新错误。不改变 Client 或 ACP 协议。

官方 API 契约核对来自当前 Flutter SDK 的 `foundation/collections.dart`、`material/menu_anchor.dart` 和 `material/checkbox_list_tile.dart`。`listEquals` 按元素有序比较；`MenuAnchor.childFocusNode` 用于键盘返回触发器，横向约束参数控制自然宽度；`CheckboxListTile` 整行切换并合并语义，禁用使用空 onChanged。

## 验证与交接

实际完成：首批仅对自己改动的 13 个应用/测试 Dart 文件和 1 个预览文件运行定向 `dart format`；续轮对权限 ViewModel、项目环境栏、交互公用组件及新 ACP 回归共 4 个文件定向格式化，通过。对改动 Dart 文件逐个请求 native Dart LSP 诊断；首批计划投影的导入问题已修复，曾出现的 `riverpod_syntax_error` 在续轮复查时消失。续轮三个生产文件、新 ACP 回归及计划投影的最新诊断均为空，当前没有已观察到的插件残留；这不替代父代理最终全量静态检查。范围内 `git diff --check` 通过。

父代理统一生成完成后，指定联合命令首次运行出现着色器资产竞争后遗留。父仅清理两个生成的 shader 资产并由官方测试重建，复跑后过程分组 25/25 通过。交互场景剩余失败来自测试读取合并语义的方式：finder 已返回 `MergeSemantics` 节点，但直接读取 `SemanticsNode.flagsCollection` 只得到节点自身标记；改为 `getSemanticsData().flagsCollection`，才能断言包含子 Checkbox 的最终 checked 状态。保留原选中和键盘断言，并增加 Space 后 Alpha 未选中、Beta 仍选中的语义断言。另删除重复申请的 `SemanticsHandle`，由当前 SDK 默认启用语义的 `testWidgets` 负责完整生命周期。

最终本组在独占测试窗口运行 `cargo flutter test --no-pub test/ui/interaction_cleanup_test.dart`，exit 0，2/2 通过，无 shader 异常。当前有效证据为权限身份 6/6、过程分组 25/25、交互 2/2，合计 33 个场景通过，来自已完成的分次运行，未声称同一次三文件全绿。生产控件、渲染器、backend、theme 和 splash 均未为通过测试而修改。本组没有运行 GUI、完整 analyze、生成器或依赖准备。

- 权限身份回归：联合运行中 6/6 通过。使用真实 `AcpPermissionViewModel`、`AcpComponentHarness` 的生产 Client owner 及既有可控外部端口，以正式轮次完成帧清空 A 队列后交付 B；通过两个独立边界 Future 控制回执顺序。A 的迟到成功/失败各自在 B 提交中、B 已失败、ViewModel 已销毁时完成；实际验证 B submitting/错误归属、原 permission ID 透传及销毁后无通知/异常。没有取得修前运行证据，不称为完整红绿对照。
- 交互回归：最窄单文件运行 2/2 通过，证明多选答案、合并后的 checked 语义、Space 切换及回退草稿禁用/恢复。
- 修前失败判据：回退场景应在 disabled 输入框断言失败；旧手绘选项应在最终合并语义的 checked 断言失败。当前两个场景均有修后通过证据，未执行生产修前版本的对照。测试本身的语义读取和 handle 生命周期错误均由真实失败定位后修正，没有降低断言。
- 菜单迁移回归：`cargo flutter test --no-pub test/ui/conversation_composer_test.dart test/ui/session_selector_sync_test.dart test/ui/acp_configuration_components_test.dart`。核对项目搜索打开重置、选项禁用、菜单键盘返回与编辑器草稿/焦点，以及窄窗配置收纳。
- ACP 局部状态回归：`cargo flutter test --no-pub test/ui/acp_ux_interactions_test.dart test/ui/acp_usage_metrics_test.dart`。核对 slash 高亮/选择/滚动、线程切换、IME 以及 plan 的正文流隔离。
- 官方预览入口仍是 `cargo xtask preview-gui --headless --no-devtools`。新增 `输入交互` 组提供多选、窄窗大字、回退草稿禁用/恢复；既有 Composer 与 ACP 预览覆盖附件、配置、过程组、状态详情和外部历史 unknown。预览场景本轮未启动，不能记录视觉通过。

本组未修改现有跨范围测试或预览。父代理已完成统一 `cargo xtask generate-gui`，报告 exit 0；本组仅消费生成结果，没有执行生成或手改生成文件。

## 父代理统一生成边界

- `AcpUpdatePresentation.sessionInfo` 已处理：父代理已删除 Freezed 输入、死视图分支及两语言无消费者文案并统一生成。过程分组测试改用现役 usage 更新，保留“过程 · 1 项活动”断言；该场景及真实 sessionInfo 输入过滤场景在本次联合测试中通过。外部 sessionInfo 协议映射为 superseded 的生产行为继续保留。
- 权限身份修复仅更改手写 ViewModel 内部状态和函数体，没有改变生成类型形状或公开 provider 签名。交付后本组停止修改生成输入，由父代理统一生成并安排回归执行。
