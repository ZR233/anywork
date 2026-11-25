# M05 / M15 / M16：timeline 预览逐文件审读

范围为 `code/anywork_previews/lib/src/features/conversation/timeline/` 的全部 10 个手写 Dart 文件。以下均已全文阅读；清点和引用查询仅用于核对覆盖与消费者，不替代阅读。预览使用合成不可变数据并装配生产组件，不建立 Client、读取 owner 或第二份业务状态。

| 文件（相对上述目录） | 审读判断与处理 |
| --- | --- |
| previews/model_request_wait_preview.dart | 已读完整组件。使用生产等待呈现构造模型请求场景，未发现独立业务实现，保留。 |
| previews/tool_detail_preview_fixtures.dart | 已读完整工具合成数据和契约分派。不同工具的参数、结果、附件与错误样例承载实际适配差异，保留，不按形似 JSON 机械合并。 |
| previews/tool_detail_previews.dart | 已读完整 Preview 入口、host、工具展开和工作组装配。场景复用真实 ToolItemView 等组件，包含失败、超时、窄窗、大字、深色、长结果与滚动；保留契约覆盖，不删成只剩成功样例。 |
| previews/expanded_work_timeline_previews.dart | 已读完整 History、live、放大字号、折叠入口。live 场景名称已准确标为主时间线 live 模型；保留模型 location，不宣称真实 footer 覆盖。 |
| previews/expanded_work_timeline_fixture.dart | 已读完整合成行、控件、滚动控制器和扩展成员。History/live 模型均由 TimelineView 主行装配 Work。已纠正 bottomSliver 注释，滚动测试名称明确 TimelineView 模型，保留首/中/尾成员可达、追加、异步高度和上滚阅读意图断言。受限 LiveStatus 工作区另由现有 surface 测试保护，不新建平行夹具。 |
| previews/timeline_component_previews.dart | 已读完整复制动作、命令、间距、父代理、媒体、结果等组件入口与 host。复用生产 TimelineView / ChatItemView / outcome、attachment 等组件，保留各自用户可见差异。等待预览直接使用 DecodedToolCard.value 与 TimelineToolItemView，删除旧包装入口并迁移现有挂载测试。 |
| previews/plan_detail_previews.dart | 已读完整计划文档、收据与窄屏入口，使用生产视图与主题，保留；不混入真实交互审批能力。 |
| previews/conversation_live_status_previews.dart | 已读完整活动阶段、attention、工作组、动画与尺寸/字号场景。使用真实状态表面，不复制状态机；保留场景和视觉组合。 |
| previews/timeline_lsp_previews.dart | 已读完整查询、悬停、引用、能力、状态、窄窗大字场景。删除所谓 declared window 的无效 ContentRef 夹具：其实际呈现始终来自内联 bodies，renderer 未读取 atom 引用；改用既有 _lspToolItem 构造 _statusItem 和共同 _lspCard，删除旧构造与无用导入。此预览只声明覆盖内联结果，不冒充 owner 限定的延迟正文测试。 |
| previews/timeline_preview_fixtures.dart | 已读完整公共合成数据、消息和工作区间构造。LSP 确认 TimelinePreviewRunEntry.atom 无读取者，删除该字段与 runEntry 中虚假的 DeferredPayload/ChatAtom 构造，保留 id、order、memberCount 到 WorkDisplayBlock 的投影；删除只有声明的 contentReference。其余真实场景数据保留。 |

## 场景与证据的边界

expanded_work_timeline_scroll_test.dart 的六个 TimelineView 模型用例验证主列表滚动，不替代 footer 的布局证据。live_status_surface_view_test.dart 中 `open work keeps the latest thinking summary above scrolling members` 使用生产 LiveStatusSurfaceView：在 170px 高、360px 宽、1.6 倍字号的受限表面展开 12 个成员，滚动到末项后断言标题坐标不变、标题仍可命中，折叠后末项消失。这是实时状态工作区内部滚动与固定标题的证据，不外推为原生宿主或完整会话 footer 集成验证。

timeline_component_preview_test.dart 的公共组件挂载用例使用预览的生产组件入口；wait_presentation_integration_test.dart 验证等待终态时保留身份、展开和 Flutter SelectableText 的诊断复制。其他预览的全文审读与静态诊断不能替代实际画面观察，LSP 大字窄窗的视觉效果仍由相应官方预览或 widget 场景验证。
