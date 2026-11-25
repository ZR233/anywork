# Statistics 设置页清理审查

## 范围与结论

审查 `lib/src/features/settings/statistics/` 11 个手写 Dart 文件及 `code/anywork_previews/lib/src/features/settings/statistics/previews/` 2 个预览文件。生成文件 `statistics_view_model.g.dart` 按仓库规则不手改。没有发现可安全移除的旧接口、重复统计事实源或无消费者夹具，因此统计实现和预览 fixture 均保留；没有改变查询、筛选、刷新、分页、模型身份或指标展示语义，也无需 Rust/Client 重构。

## 逐文件清单

| 文件 | 职责与证据 | 处理结论 |
| --- | --- | --- |
| `connectors/statistics_connector.dart` | 将 shell `visible` 传给 `statisticsViewModelProvider.notifier.setVisible`，并把 ViewModel 回调连到 view。 | 保留；这是页面可见性与 SDK-only repository demand lease 的明确所有权边界，含 post-frame mounted 检查。 |
| `state/statistics_filter_options.dart` | 从只读 history/summaries 构造模型、effort、service tier 选项，输出不可修改列表。 | 保留；LSP references 确认由 history widgets 和 statistics view 消费，且汇总数据需进入模型筛选。 |
| `state/statistics_view_state.dart` | 把 repository state、筛选值与已筛历史作为不可变展示状态。 | 保留；属于 UI 投影而非重复写入 Client/产品事实。 |
| `statistics.dart` | statistics feature 的公开导出。 | 保留；当前 feature 入口仍被设置路由/调用方依赖。 |
| `view_models/statistics_repository_provider.dart` | 暴露 Client statistics repository 的 Riverpod provider。 | 保留；Provider 是 UI 与 SDK-only Client repository 的现有接线点。 |
| `view_models/statistics_view_model.dart` | 维护局部筛选、基于权威 ready snapshot 对账筛选有效性，并复用同身份 materialization 派生筛选结果。 | 保留；其 owner epoch/feed/revision/identity 检查保护 owner 切换、部分失败和大列表复用语义，不能简化为直接重查或客户端重算查询。 |
| `views/statistics_view.dart` | 根据状态显示 summary、筛选控件、compact/wide history 和空/失败提示；使用 material identity 减少大列表值比较。 | 保留；这是生产视图和展示状态消费者。 |
| `widgets/statistics_formatters.dart` | 本地化缺失指标、时间、速度、模型身份及 service tier 标签。 | 保留；统计指标缺失与身份状态是用户可见契约。 |
| `widgets/statistics_history_widgets.dart` | history 筛选 header、effort/tier/mismatch 控件及 compact/wide 原子事件行。 | 保留；过滤项直接来自 Client materials，原始记录与 mismatch 信号仍需显示。 |
| `widgets/statistics_status_widgets.dart` | repository 打开/失败、数据缺口及空状态呈现。 | 保留；明确区分正常空、读取失败和数据缺口。 |
| `widgets/statistics_summary_widgets.dart` | 汇总卡片、效率指标和 effort/service-tier breakdown。 | 保留；依据 `StatisticsSummary` 展示独立聚合读模型，不在 Flutter 重新汇总业务数据。 |
| `previews/statistics_preview_fixtures.dart` | 构造同账户/模型/effort 下不同 requested service tier 的合成 immutable snapshot。 | 保留；预览场景让 tier 对比可见且不访问真实服务或产品数据。 |
| `previews/statistics_previews.dart` | 用上述 fixture 渲染生产 `StatisticsView` 预览。 | 保留；只组装合成数据与生产组件，不复制生产 UI。 |

## 调用关系与验证

- Dart LSP 对 `StatisticsFilterOptions` 的 references 指向其定义、history widgets 与 statistics view，合计 7 处/3 文件；确认它不是孤立类型。
- Dart LSP 对 `statistics_view.dart` 返回 `No diagnostics.`；对通用 workspace `Settings`/`Statistics` 搜索得到的大结果仅用于定位，未将符号计数作为审读证据。
- 统计文件没有源码改动，因此无需执行格式化。本次没有执行测试。若父代理安排最窄回归，可运行 `cargo flutter test --no-pub test/ui/statistics_effort_breakdown_adapter_test.dart`；此用例覆盖适配器和统计 UI 的现有行为，但不等于完整数据库/Client 集成验证。
- 主要未覆盖项：本次没有运行任何测试，也没有执行真实数据库或原生 UI；统计查询与产品库读模型边界仅通过只读代码/LSP 调用链审查，未运行集成验证。
