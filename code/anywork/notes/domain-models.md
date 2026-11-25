# M04：前端模型与投影

状态：**已审读、已处理；相关 unit 已通过，UI 与最终分析见总台账**。

## 逐文件审读

以下为基线全部 10 个手写文件；Freezed 产物不手改。

| 文件（`lib/src/domain/models/` 下） | 结论 |
| --- | --- |
| agent_list_stop.dart | 保留根据执行身份、关闭状态和受理意图派生按钮的规则；不能把清理中或等待调度简化成普通停止。 |
| agent_membership.dart | 只补“子成员”的领域条件，复用 Client 的退役角色判据；历史角色可能存在于真实历史，保留。 |
| agent_workspace_view.dart | 保留现役工作区不可变呈现与 Freezed 生成边界；不同作用域的业务资源不随视图退役。 |
| composer_primary_action.dart | 保留发送／继续／停止裁决，改用 Flutter `listEquals` 替代手写恢复动作列表比较；null、有序列表的语义一致。 |
| plan_confirmation_ownership.dart | 两种计划工具名称用于辨认现役及已有历史的真实来源，不能因旧名称删掉历史语义。 |
| studio_models.dart | 保留应用模型导出入口，无新增平行类型。 |
| studio_projection_models.dart | 保留壳层、侧栏、页眉和状态栏的现役呈现切片；`fromState` 只派生，不写回领域。 |
| studio_reactive_projections.dart | 保留仍在使用的上下文、速度切片；删除四种无生产消费者的旧投影及专属比较器，见下文。 |
| studio_state.dart | 保留当前查询组合与nullable copyWith语义；删除声称“旧条目弱引用缓存”的过时注释，文件已无该缓存。 |
| timeline_commands.dart | 保留显示模式与连接阶段，二者各有独立呈现语义。 |

## F05：整条旧投影退出

根代理逐项使用 Dart LSP `findReferences`，并在应用、Client、预览及测试源码中检索：

- `StudioComposerDiagnosticsProjection`、`StudioAccountUsageProjection`、`StudioActivityProjection`
  仅在自身声明、工厂或等价比较中出现，没有生产消费者。
- `StudioComposerProjection` 只被其自身以及一个旧投影等价性自测引用。其
  `fromWorkspace` 和 `legacyWorkspace` 的语义引用均只有声明。
- 删除上述四类以及仅为它们存在的账号、模型、交互载荷、JSON深比较等帮助函数；
  未将这些私有比较器搬到新模块延续无用实现。
- 删除 `settings_account_model_origin_adapter_test.dart` 中直接构造旧投影的自测。
  同文件仍保留真实 Agent Profile 对话框随目录更新、类型过滤和路由去重等消费者验证；
  `session_selector_sync_test.dart` 继续保护现役选择器的实时更新。删除自测不减少现役路径的独立保护。

## 相邻下载接口收束

新增 `domain/timeline_file_download.dart` 承接原有纯 Dart 下载接口和启动函数类型，
从时间线的 Widget 文件中分离。FRB 实现、AppGraph、时间线两个 connector、文件 UI 测试
和工具预览直接导入领域接口；原文件只保留 `TimelineFileDownloadScope`，没有兼容导出。
接口方法、进度流、完成与停止语义未变，真实原生句柄仍归 FRB 实现持有。

## 验证状态

- 编辑前取得旧声明的语义引用；编辑后 `studio_reactive_projections.dart` LSP diagnostics为空。
- `composer_primary_action_test.dart`、`agent_list_stop_test.dart` 已随完整 unit 通过；模型来源、选择器与下载等真实 UI 回归及最终分析见[总台账](flutter-quality-audit.md)。
- 本模块无生成输入接口变化，无数据或协议迁移。
