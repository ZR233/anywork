# M09 Driver 诊断四文件审读

下列逐文件检查列保留初审时的实际观察与未覆盖边界；后续统一生成、整合测试和官方预览以[总台账](../flutter-quality-audit.md)的验证表为准，不把初审“未运行”当作最终状态，也不把整套通过外推为每项平台行为已验。

基线 `3db5e10d03db6a13bcc44b37d37555bcaf80e2c7`，分支 `refactor/flutter-quality-cleanup`。
本轮只改 `lib/src/shared/` 下 `studio_driver_keys.dart`、`studio_driver_key_values.dart`、
`studio_driver_projection.dart`、`studio_driver_state.dart` 与本笔记；未触碰 capture、tool、
domain 模型、其他 shared 组件与邻居改动，无 Git 写操作。历史清理范围由父批准，
不含新增接口或新功能。

## 方法

- 四个文件逐段全文阅读（不是按搜索命中或行数推断）。
- 消费者判据三层：①全库 `StudioDriverKeys.` / `StudioDriverKeyValues.` 引用计数；
  ②同一字面量（含插值模板）以**引号锚定**的正则检索全库文本，避免
  `account-template` 误命中 `account-template-selector`、`account-row-` 误命中
  `account-row-upgrade:` 这类同前缀他键；③Dart LSP `findReferences`、
  `documentSymbol`、`diagnostics`。
- 用 HEAD 内容另建基线副本跑同一套判据：失效集合与当时工作树完全一致，
  说明失效来自历史迁移，不是邻居在途编辑造成的假象。
- 文档单独核对：`code/pl-studio-acceptance/DELEGATION.md` 与 `notes/**` 点名的身份
  先保留不删，经父裁定后再统一处理（见下）。

## 最终形态

| 文件 | 行数（基线→现） | 声明数（基线→现） | 本轮删除 |
| --- | --- | --- | --- |
| `studio_driver_keys.dart` | 947 → 647 | 368 → 259 | 109 条声明 |
| `studio_driver_key_values.dart` | 202 → 97 | 117 → 60 | 57 条键值 |
| `studio_driver_projection.dart` | 995 → 820 | — | 1 个旧端点 + 4 个专属 helper |
| `studio_driver_state.dart` | 1751 → 1723 | — | 2 个只写不读字段、1 个聚合读函数、1 个启动失败写入链 |

合计 +4 / −612 行。两个键值文件现在没有任何“零消费者”声明（全库扫描复算为 0），
反向核查 1083 处引用、0 悬空。

## 逐文件台账

### studio_driver_key_values.dart（202 → 97 行，117 → 60 个声明）

- 职责：共享 Driver 自动化键值的字符串来源；账号等功能模块还维护自己的现役身份。只依赖 Dart（`dart:convert`、
  `package:anywork_client/models.dart`），不引入 Flutter，纯 Dart 宿主脚本可复用。
- 入口与消费者：65 处 `StudioDriverKeyValues.` 引用，集中在 3 个文件——
  `studio_driver_keys.dart`（Flutter 侧 `ValueKey` 构造）、
  `tool/profile_timeline_probe.dart:904`（`threadRow`）、
  `features/shell/thread_preparation_card.dart:339`（`threadPreparationStage`）。
- 删除：57 条零消费者键值（17 组，见台账）。相关旧键中的引用随声明退出，
  `models.dart`／`dart:convert` 及 `jsonEncode` 仍被现役键值使用，因此没有 import 失效。
- 保留：`timelineScrollable` 等经 keys 转发的键值（每条保留的转发目标都存在）。

### studio_driver_keys.dart（947 → 647 行，368 → 259 个声明）

- 职责：把 key values 包成 `ValueKey<String>`；少量只在 Flutter 侧登记的键
  （`studio-*`、`thread-*`、`ssh-*`）自带字面量；动态身份统一用 `jsonEncode([...])`
  或 `$id` 插值，保证测试与组件指向同一节点。
- 入口与消费者：1022 处 `StudioDriverKeys.` 引用，119 个 Dart 文件
  （`lib` 68、`test` 45、`integration_test` 6），生产侧挂在真实组件上。
- 删除：109 条零消费者声明（与 key values 同步）。
- 注释同步：`conversationActivity` 的说明去掉已删除的“展开详情”；
  `toolImageEntryId` 的说明改为 thumbnail/dialog，不再提已删除的 toggle。

### studio_driver_projection.dart（995 → 820 行）

- 职责：一次同步读取 Client 现役镜像装配 `StudioDriverFacts`；`bindStudioDriver`
  只登记查询闭包，不创建账号、观察、草稿、Session、ChatView 或订阅。
- 入口与消费者：`bindStudioDriver`（1 处）与 `queryStudioDriverFacts`（3 处）只被
  `test/unit/bots_adapter_test.dart`、`test/unit/frb_adapter/bots_frb_adapter_test.dart`、
  `test/ui/app_route_draft_test.dart` 使用。
- 删除：旧诊断端点 `studioDriverTopicDiagnostics`（读取 topic 引用计数、各域同步计数
  与 revision）及其专属 `_connectionCounts`、`_projectionRevisions`、`_SyncCounts`、
  `_maxRevision`。全库文本检索 0 引用，LSP `findReferences` 只返回声明自身；
  没有任何装配点或读取消费者，属旧端点残留。
- 保留：`studioDriverStampJson`、`studioDriverSummariesJson`、`studioDriverResourceJson`
  等 converter 仍被 `snapshotJson` 的实际字段消费。

### studio_driver_state.dart（1751 → 1723 行）

- 职责：①只读事实 DTO（时间线展示代次/条目、ACP 准备、bots、整体 Facts）；
  ②`snapshotJson` 的 JSON 投影；③退出诊断的发布/读取；④现场滚动几何。
- 入口与消费者：
  - 生产侧使用发布半边：`app/studio_host_lifecycle.dart`（报告、阶段、
    `markExitRequested`、native 期限预算）、`app/studio_shutdown.dart`（阶段）。
  - 读取半边 `snapshotJson` 仍消费 `_nativeExitJson`、`_shutdownReportJson`、
    `_shutdownPhasesJson`（现役 native 退出证据链），并由上述 3 个测试文件驱动。
- 删除：①`accountTemplates` 字段（构造参数/初始化/声明）——只写不读，快照的模板事实
  来自 `accountSummaries.templates`，是重复事实源；②`settingsReady` 字段——全库无读取者
  且不进 JSON；③`exitDiagnosticsJson` 聚合读函数——全库零调用，其内容
  （nativeExit/shutdownReport/shutdownPhases）已由 `snapshotJson` 提供，只剩
  `startup` 切片无消费者；④随之失效的 `_startupJson`、
  `_startupFailureCode`/`_startupFailureCorrelationId` 两个静态字段与
  `publishStartupFailure` 写入方法。
- 说明：本批删除后，全库不再有 `publishStartupFailure` 的调用点——
  唯一写入者 `features/shell/runtime_banners.dart`（M10）已在同批清理中移除；
  该文件还包含持久化面板整理，生产退出诊断写入链保留。
- 保留：native 退出的三个私有 JSON helper、`publishShutdownProgress`、
  `publishShutdownReport`、`publishNativeExitBudget`、`markExitRequested`、
  `shutdownProgress`、`snapshotJson`、`readFacts`、`bindSnapshotQuery`。

## 删除台账（109 键 + 57 键值，17 组）

每组均已确认零引用、零字面量命中、基线 HEAD 同样零命中；抽查项 LSP 只返回声明自身。

| 组 | 数量（keys/values） | 失效原因 |
| --- | --- | --- |
| 模型详情对话框 `modelDetailDialog/Close/Reload/Evaluations` | 4 / 4 | 模型详情改由 accounts 模块自持身份挂载 |
| 时间线全文查看器 `timelineNewOutput`、`timelineDetail*` | 8 / 8 | 已被 `design/26` 的 `timelineContent*` 窗口键取代 |
| 项目路径手输 `projectPathDialog/Input/Submit` | 3 / 0 | 添加项目已走系统/SSH 目录选择 |
| MCP 全量重置确认 `mcpResetAllConfirm` | 1 / 0 | 现役只有 `mcpResetAll` 入口 |
| 添加项目来源/连接 `addProjectSourceLocal/Remote`、`addProjectConnect` | 3 / 0 | 对话框只保留 `addProjectContinue` 等现役键 |
| 账号编辑器旧共享身份 `accountEditor*`、`accountTemplate`、`accountBaseUrl*`、`accountApiKey`、`accountManualModelDelete*`、`customModel*` | 11 / 1 | accounts 模块改用 `AccountViewKeyValues`（`accounts-editor-field:` 等） |
| 统一添加账号模板选择器 `accountTemplatePicker/Option/List` | 3 / 3 | `AccountTemplatePickerView` 已删除，现役模板身份由 `AccountViewKeyValues.template` 承担 |
| ACP 账号与准备面板 `acpAccount*`、`acpInstall*` | 32 / 32 | ACP 面板动作改用 `AccountViewKeyValues.acpAction`；`acp-install-cancel` 字面量只作 SDK correlationId |
| 账号行/连接方式/压缩限制 `accountRow`、`accountConnectionMode*`、`accountModelConnectionMode*`、`accountModelAutoCompact*` | 7 / 0 | 同上，accounts 模块自持行与连接身份 |
| 计费与模型身份 `modelEnabled`、`modelDetails`、`accountBillingKind`、`billingKindOption`、`accountNoCharge` | 5 / 4 | 父裁定：`DELEGATION.md` 是已退役账号控件的陈旧说明，现役入口是 `AccountViewKeyValues`／`AccountBillingControl`；不给新 UI 回挂旧 key |
| 时间线 Current 集合 `currentCompletedItems`、`currentCollection*` | 5 / 5 | Current 列表不再挂这些旧键 |
| 条目块/回滚/技能激活 `timelineRolledBack`、`timelineBlock`、`timelineSkillActivation` | 3 / 0 | 对应呈现已删除或换身份 |
| 超大条目正文回源 `timelineItemBodyNotice/Load/Retry` | 3 / 0 | 页面不再提供回源入口（只剩同名 l10n 文案） |
| 历史附件 `historyAttachment` | 1 / 0 | 附件统一走 `attachmentDraft*`/`attachmentModality` |
| 活动摘要与问答回执详情 `timelineActivitySummary`、`timelineUserInputDetails/Question/Answer` | 4 / 0 | 只保留折叠头部 `timelineUserInput` |
| 图片条目 `viewImageToggle`、`toolImageGallery`、`imageCard*`、`markdownImage*` | 8 / 0 | 现役图片呈现用 `viewImageThumbnail`／`viewImageDialog`／`timelineImage*` |
| 计划回执回复 `timelinePlanReceiptReply`、bots 事实块 `botsStartTime/EndTime/Project/Fact*`、活动条详情 `conversationActivityDetails` | 8 / 0 | 各自入口已不存在，同组 `timelinePlanReceipt`／bots row／`conversationActivity` 保留 |

## 保留项与理由

1. `snapshotJson` 与 `readFacts`／`bindSnapshotQuery`：读端虽有生产消费者偏差，
   但确有 3 个测试直接驱动（`bots_adapter_test`、`bots_frb_adapter_test`、
   `app_route_draft_test`），属现役测试契约，不扩张删除整个 Driver 读端。
2. native 退出证据链（`publishShutdownProgress`/`publishShutdownReport`/
   `publishNativeExitBudget`/`markExitRequested` + `_nativeExitJson`/
   `_shutdownReportJson`/`_shutdownPhasesJson`）：生产在写、`snapshotJson` 在读。
3. `threadComposer`：驱动文件内无读取，但 `test/ui/app_route_draft_test.dart:519`
   读取 `facts.threadComposer.draft`。
4. `studioDriverStampJson`／`studioDriverSummariesJson`／`studioDriverResourceJson`：
   `snapshotJson` 的实际字段来源。

## 跨界核对与收束

1. `DELEGATION.md` 的旧账号控件说明已由父迁移到真实 `AccountViewKeyValues.modelEnabled/modelDetails`
   及 `AccountBillingControl` 菜单／下拉框；退出旧 `account-no-charge` 身份。
2. `features/shell/studio_shell.dart` 的 Driver import 原先被同库 part 中的启动失败 writer 使用，
   不能只看主文件判定无用。writer 退出后已同步删除 import；正式分析在整合阶段核实。
3. Driver 读端（`snapshotJson`／`queryStudioDriverFacts`／`bindStudioDriver`）在 `lib/`
   没有生产装配点，只有测试调用；生产只写诊断、不读诊断。这解释了死键长期无人发现。
4. `tool/profile_timeline_probe.dart` 直接依赖 `studio_driver_key_values.dart` 的纯 Dart
   边界，本轮删除未破坏该边界（只用到 `threadRow`）。

## 实际验证

- 反向引用核查：259 个 keys 声明、60 个 values 声明、1083 处引用、0 悬空。
- 失效复算：两个键值文件剩余“零引用且零字面量”声明 = 0 条。
- LSP：两批改动后四文件 `diagnostics` 均为 0 条；`findReferences` 抽查——
  `studioDriverTopicDiagnostics`=1（仅声明）、`exitDiagnosticsJson`=1（仅声明）、
  `keys.modelEnabled`=1（仅声明，已删）、`values.modelEnabled`=2（声明+已被删的转发）、
  `viewImageThumbnail`=6 处/5 文件（现役）、`accountNoCharge`=1（已删）。
- `cargo dart format`（仅这 4 个文件）：第一批 2 changed，第二批 0 changed，
  `--set-exit-if-changed` exit 0。
- `git diff --check` 无空白告警；改动规模 4 文件 +4 / −612 行。
- 未运行 `cargo flutter analyze`、任何测试、GUI 或生成检查。

## 整合验证与覆盖边界

- `notes/shared-components.md` 的 M09 表和退出证据保留理由已由父同步。
- 下列为初审建议的影响范围，现已纳入完整 unit/UI 执行；MCP 用例首次旧 finder 失败后的定向复验见总台账，其余不重复运行：
  - `cargo flutter analyze`：确认全应用无残留引用与 lint（原 part 库导入疑问已核实，无生产缺陷）。
  - `cargo flutter test --no-pub test/unit/bots_adapter_test.dart test/unit/frb_adapter/bots_frb_adapter_test.dart test/ui/app_route_draft_test.dart`：
    直接覆盖 `queryStudioDriverFacts`＋`snapshotJson`（含删除的 `accountTemplates`／
    `settingsReady` 与保留的退出证据链）。
  - `cargo flutter test --no-pub test/ui/startup_error_route_test.dart`：
    覆盖父已移除 writer 的启动致命失败路径。
  - `cargo flutter test --no-pub test/ui/mcp_scoped_catalog_and_thread_status_test.dart test/ui/timeline_image_card_presentation_test.dart test/ui/context_usage_readout_test.dart test/ui/statistics_effort_breakdown_adapter_test.dart`：
    覆盖删键相邻区域的现役身份（`mcpResetAll`、图片呈现、上下文读数、统计）。
