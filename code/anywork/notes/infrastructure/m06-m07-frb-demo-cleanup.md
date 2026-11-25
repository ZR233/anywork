# M06/M07 审读与清理记录：infrastructure/frb 与 infrastructure/demo

基线 `3db5e10d03db6a13bcc44b37d37555bcaf80e2c7`，分支 `refactor/flutter-quality-cleanup`。
本文件记录 M06（`lib/src/infrastructure/frb`，初审 22 个手写文件，后续新增 2 个共享纯转换模块）与 M07（`lib/src/infrastructure/demo`，8 个手写文件）的实际审读、处理与保留理由。
“已审读”表示逐行读完整个文件，不是目录统计或关键字搜索；“已处理”表示审读后在本轮实施了模块内改动。

## 约束

- FRB adapter 只做类型化映射、机械转发与真实句柄收束，不造业务状态或第二事实源。
- demo 继续作为显式模拟，不增加真实服务依赖。
- Client SDK-only、现有 Current/History/ownership 契约不变；共享纯转换只属于手写 FRB adapter，不改后端或 Client。
- 本执行者不运行完整 analyze、UI/GUI、native 构建、生成或 Git 写操作；根执行者统一生成完成后，仅运行约定的两个文件联合单测。最终整体验收由根执行者承担。

## 实施结果概览

- 初轮改动 15 个文件（frb 9 个、demo 6 个）；后续 plan/workflow 收束见下文，初轮行数统计不代表最终共享工作区差异。
- 删除的符号（库内私有）：`_studioFailureCode`、`_string`、`_frbInt`、`_frbNullableInt`、`_modelCatalogStateFromFrb` 内的 `convert` 闭包、`catalogModels` 中间变量、`_FrbRawHistoryReader/_FrbRawCurrentReader` 各一份 `_checkOpen/_guardedCall`、`_DemoReadSource.pageCurrent/fit/_read/_accepted/_closed/_closing/requestClose/close/h0/itemH0`、顶层 `_demoItem(...)`、`_demoAutoCompactLimit`、`DemoStudioTransport._demoDirectoryPage/_ownedHistoryReaders/_joinDemoConversations`、`_demoSnapshot` 中的 `deepseek` 中间变量。
- 文件规模变化：`studio_demo_conversation.dart` 1105 → 907，`studio_demo_api.dart` 7937 → 7900，`studio_thread_stream.dart` 797 → 751，`studio_timeline.dart` 487 → 459，`studio_api.dart` 168 → 136。

## 逐文件审读清单

状态：已审读（读完、无需改）/ 已处理（读完并实施）。行数为基线行数。

### M06 infrastructure/frb（初审 22 个，新增 2 个共享模块）

| 文件 | 初审行数 | 状态 | 笔记 |
| --- | ---: | --- | --- |
| frb_runtime_owner.dart | 553 | 已审读 | 进程初始化/退出 owner，one-shot 闩、失败 memo 设计完整。`_runBeginRuntimeExit` 的 `remainingMs` 是 Rust 全局退出期限预算，Dart 的 `bound`（≤2s）只等待早期封闭确认；两种合同均保留，见最终核查。 |
| statistics/frb_statistics_feed.dart | 405 | 已审读 | 句柄收束正确（`requestClose` 幂等、`close` 可重试、未确认不丢 handle、`dispose` 仅在确认后）；`StatisticsPage` 头部三处重复属协议字段一致。保留。 |
| studio_account_catalog_converters.dart | 589 | 已处理 | 2 处 `_frbNullableInt(...)` 改为 `?.toInt()`。`accountCatalogFromFrb/accountModelFromCatalog` 公开且被外部复用，不动。 |
| studio_acp_business_mapper.dart | 1026 | 已处理 | plan/workflow 的三份转换迁至 `studio_workflow_converters.dart`，直接导入共享函数；沿用 Native 精确性拒绝规则，删除原函数及只服务旧映射的 `mode_editor/thread_stream` 导入。`models` 导入仍有 delegation 消费者，保留。 |
| studio_acp_business_port.dart | 258 | 已审读 | 机械转发 + 句柄观察；`_acpBusinessCall` 只对已派发的 `PanicException/AnyhowException` 包成 `AcpCommandOutcomeUnknown`，有注释且正确。保留。 |
| studio_acp_converters.dart | 613 | 已处理 | 22 处 `_frbInt/_frbNullableInt` 改为 `.toInt()/?.toInt()`；其中 `nextResetAt == null ? null : nextResetAt!.toInt()` 触发 `prefer_null_aware_operators`，已改为 `?.toInt()`。 |
| studio_api_contract.dart | 2539 | 已处理 | `_checkOpen/_guardedCall` 上提到 `_FrbRawResource`（两个 reader 的逐字重复删除）。`_FrbRawPortProxy/_FrbRawPull/_FrbRawEvent` 单一所有者设计清晰，保留。workflow graph 读取直接调用共享 mapper，不再经 ACP mapper。 |
| studio_api.dart | 168 | 已处理 | 删除 `_string/_frbInt/_frbNullableInt`；`_permissionMode(Object?)` 收紧为 `_permissionMode(String)`（生成 `permissionMode` 为非空 `String`）。时间 helper 迁至纯模块，当前库导入共享数值及 workflow 映射，供全部 part 真实调用。 |
| studio_bots_converters.dart | 397 | 已审读 | `BotPlatform.feishuChina` 为唯一平台硬编码（生成 DTO 无 platform 字段），现状约束。保留。 |
| studio_bridge_api.dart | 46 | 已审读 | 纯 `export` 汇集。保留。 |
| studio_bridge_error.dart | 31 | 已审读 | 单一 `BridgeErrorCode → StudioFailureCode` 穷举映射。保留。 |
| studio_delegation_converters.dart | 164 | 已审读 | `delegationModelDetailFromFrb` 公开供 Client 契约测试使用。`source.measurement!` 多次断言改为局部变量需把表达式体改成块体，收益不明确，保留。 |
| studio_file_download.dart | 86 | 已审读 | 真实句柄收束正确；原导入 `features/conversation/timeline/connectors/timeline_file_download.dart` 形成 infrastructure → features 反向依赖；根执行者已将下载启动值与接口迁入 `lib/src/domain/timeline_file_download.dart`，本文件直接导入 domain，句柄实现不变。 |
| studio_frb_converters.dart | 1811 | 已审读 | `_exactSignedTimelineInt(Object)` 的 `BigInt` 与 `int` 两个分支都是活分支：FRB `PlatformInt64` 在原生平台是 `int`、Web 是 `BigInt`（`flutter_rust_bridge-2.13.0/lib/src/platform_types/_io.dart` / `_web.dart`），不能收紧为 `BigInt`。`_persistenceQueueFromFrb` 非死代码。`_settingsCommandReplyFromFrb` 的 `receipt.targets.first` 由 Rust 唯一回执构造保证非空，详见最终核查结论。精确非负计数与时间检查迁至 `studio_numeric_converters.dart`，本 part 真实调用共享函数。 |
| studio_presentation_converters.dart | 657 | 已审读 | 枚举按 `.name` 映射属 FRB/领域同名约定；`_timelineTimestampFromFrb(Object?)` 入参为 `PlatformInt64?`，保持。保留。 |
| studio_settings_converters.dart | 280 | 已处理 | `_accountSettingsFromFrb` 的 `catalogModels ?? const []` 与 `catalog == null ? const []` 合并为一个 `?.` 表达式。 |
| studio_state_converters.dart | 276 | 已处理 | `_modelCatalogStateFromFrb` 删除只为取 `accounts` 的 `convert` 闭包，四种有值分支用 or-pattern 直接映射列表。 |
| studio_thread_preparation.dart | 50 | 已处理 | `_studioFailureCode(error.code)` 改为 `studioFailureCodeFromBridge(error.code)`。 |
| studio_thread_stream.dart | 797 | 已处理 | 删除 `_studioFailureCode` 纯别名及其误导注释（2 个调用点改为 `studioFailureCodeFromBridge`）；`_currentNotificationFrameFromEnvelope` 的 8 个分支各自重复构造同一 `ThreadNotificationFrame`，改为先算 `update` 再构造一次；13 处 `_frbInt/_frbNullableInt` 改为 `.toInt()/?.toInt()`。`_interactionKindFromLabel` 仍被使用，保留。plan 改为共享 mapper，workflow snapshot 保留 revision 检查并调用共享 run mapper，删除重复 plan 实现和内联 run 构造。 |
| studio_numeric_converters.dart | 新增 | 已处理 | 现有 Native 非负精确计数与时间 helper 的唯一实现；所有原调用迁移，错误字段与平台数值表示保持。 |
| studio_workflow_converters.dart | 新增 | 已处理 | ACP 与 Native 共享 plan/run/graph 纯映射，无旧转发别名。 |
| studio_timeline.dart | 487 | 已处理 | 删除 `_FrbRawHistoryReader/_FrbRawCurrentReader` 各一份 `_checkOpen/_guardedCall`（已上提）。`watch/watchBody` 打开样板保留，见保留项。 |
| studio_update_api.dart | 79 | 已审读 | 薄转发；`cancelCurrentPreparation/stopAutomaticUpdate` 不经 `ensureReady`，与“未就绪也允许取消/停止”语义一致。保留。 |
| usage_diagnostics.dart | 144 | 已审读 | 枚举与聚合映射。保留。 |

### M07 infrastructure/demo（8 个）

| 文件 | 初审行数 | 状态 | 笔记 |
| --- | ---: | --- | --- |
| accounts/demo_account_observation.dart | 82 | 已审读 | 有界 pull 观察（dirty 标记 + 等待者，close 等待在途读取）。保留。 |
| statistics/demo_statistics_feed.dart | 448 | 已处理 | `StatisticsSummary` 是 Client 手写 `final class`，没有 `copyWith`，不能借它简化；改为把只被复制一次的 `deepseek` 中间变量合并进 `deepseekSummary` 的单次构造（值不变）。 |
| studio_demo_api.dart | 7937 | 已处理 | `_demoDirectoryPage()` 只是同值重建 `_demoThreadDirectory()`（唯一调用在 topic 基线），删除；10 处 `_demoItem(...)` 改为 `_DemoItem(...)` 构造器；删除文件末尾描述已不存在函数的孤儿文档注释；随 `_DemoReadSource` 清理一并删除 `_ownedHistoryReaders`、`_joinDemoConversations()` 与关闭报告中的 `demo-conversation` 阶段（该阶段只等待已不存在的在途 `pageCurrent` 读）。 |
| studio_demo_conversation.dart | 1105 | 已处理 | 引用核查确认 `_DemoReadSource.pageCurrent`（约 134 行）与 `fit`（约 19 行）在整个 demo 模块零调用，删除；级联删除只为 `pageCurrent` 服务的 `_read/_accepted/_closed/_closing/requestClose/close` 与只写不读的 `h0/itemH0`；删除 `_demoItem(...)` 1:1 转发函数（2 处调用改为构造器）。`cursor/boundary/_body/_itemBodies/_ownsItem`、`_demoEncoded/_demoDemand/_demoMaxBytes` 仍有使用者，保留。 |
| studio_demo_current_history.dart | 1230 | 已处理 | `_DemoCurrentWatch._frame` 对 4 种 update 的“拆包再原样重建”改为恒等透传（它们都是字段 `final` 的 `final class`），仅 `ThreadRuntimeUpdate/ThreadBusinessRefsUpdate` 继续从最新 workspace 取值；两个 reader 不再向 `_DemoReadSource` 转发 `requestClose/close`，`_DemoHistoryReader.close()` 只做自身 `requestClose()`。 |
| studio_demo_resources.dart | 163 | 已处理 | 三个 port 的 `next()` 收敛为 `_DemoPortProxy.nextFrame<T>`（ready 后 next，`ClientResourceClosed` 返回 null）；`_DemoProductTopicResource._listen` 中引用已不存在实现的 “as in the original demo stream” 注释改为直接说明意图。 |
| studio_demo_settings.dart | 494 | 已处理 | 单处使用的 `_demoAutoCompactLimit` 内联，保留“预览态也消费共享模型规则，不维护独立的默认值算法”注释。`DemoAcpAuth` 状态机与 fixture 保留。 |
| studio_demo_timeline.dart | 263 | 已审读 | 显式 display story 声明与冻结逻辑，职责单一。保留。 |

## 保留项与理由

1. `_exactSignedTimelineInt(Object)` / `_timelineTimestampFromFrb(Object?)`（`studio_frb_converters.dart`、`studio_presentation_converters.dart`）：审读时曾判断 `int` 分支是死分支，核实后不成立——入参是 FRB `PlatformInt64`，原生为 `int`、Web 为 `BigInt`，两分支都活。保持原样。
2. `_FrbRawCurrentReader.watch/watchBody` 的 pull 打开样板（`studio_timeline.dart`）：两段各约 28 行，仅 handle 类型、scope 名、open 闭包与 map 函数不同；可复用的 `FrbStudioTransport._openPullObservation` 语义不同（带 `resourceId` 身份、`await entry.ready`），reader 版本是惰性打开且无身份，不能直接复用；新写一个 5 参数私有助手只能省十几行，属新增抽象，按“不造通用 facade”约束保留。
3. `source.measurement!`（`studio_delegation_converters.dart`）：改成局部变量需把箭头表达式改成块体，行数反增，收益不明确，保留。
4. `deepseekSummary` 与 `copyWith`：`StatisticsSummary` 无 `copyWith`，不改 Client；只合并了中间变量。
5. 下载接口依赖已由根执行者收束：`TimelineFileDownloadStart` 与接口归 `lib/src/domain/timeline_file_download.dart`，UI 源只保留 `InheritedWidget` Scope；AppGraph、FRB、两个 connector 与测试直接导入新归属，无转发别名。下载句柄实现不变，真实 `timeline_files` 行为由最终 UI 验证覆盖。Demo 对 `timeline_display_models` 的使用仍保留：`studio_demo_conversation` 持有 `displayBlocks/heads`，`studio_demo_timeline` 用明确脚本构造冻结故事，`studio_demo_current_history` 转成 Client `HistoryTimelineEntry`。这是显式合成故事内部的真实复用，避免平行 Display 数据模型，不代表真实后端验证。
6. plan/workflow 映射已按父决定统一：`studio_workflow_converters.dart` 持有 `planRuntimeFromFrb/workflowRunFromFrb/workflowGraphFromFrb`，ACP mapper 与 Native part 库直接导入调用，`studio_api_contract.dart` 直接调用图映射；旧实现与转发别名删除。两路共享 Native 原有精确性拒绝规则，见下文。
7. 退出预算保留：Rust `code/anywork/rust/src/api/studio/handlers/lifecycle.rs:138` 调用 `fix_exit_deadline(remaining_ms)` 固定全局第一退出期限，后续 shutdown 只复用或缩短；Dart 的 `bound ≤ 2s` 只限制等待早期封闭确认。`remainingMs` 与 `bound` 是两种合同，保留当前传参。
8. settings targets 保留：Rust 唯一 `SettingsCommandReply` 构造位于 `code/pl-studio-runtime/src/studio/runtime/command_receipts.rs:53`，固定 `vec![self.resource_stamp("settings", state.revision)]`；settings_api/accounts/profiles 共用该 helper，stamp 使用同一 `StudioRuntime.owner_epoch`，bridge `convert/commands` 机械映射。没有合法空 targets 返回，不增加 fallback。
9. `BotPlatform.feishuChina` 硬编码、枚举 `.name` 映射、`BotModelRoute` 的 `!` 风格：现状约束，保留。

## 未覆盖风险

- 初轮格式化/LSP 之外的实际定向回归见“独立复核与实际回归”；最终完整 analyze、UI/GUI、native 构建与生成仍由根执行者承担。新增 plan/workflow 用例的实际状态见末节。
- `_frbInt` 旧实现接收 `Object` 并对非数值走 `int.parse(value.toString())` 兜底；39 个调用点的实参都是 `int/BigInt/BigInt?`（`PlatformInt64` 含在内），`.toInt()` 与之等价，但兜底路径已不存在——若将来有人传入字符串会从“解析”变成编译错误，这是预期收紧。
- `_permissionMode(String)` 不再接受 `null/空串/非 String`；生成字段是非空 `String`，原兜底不可达。
- demo 关闭报告不再产生 `demo-conversation` 阶段（原来只等待已不存在的在途读）。`test/`、`integration_test/`、`tool/` 中没有引用该阶段名或 `closeFailed` 的断言，但建议父代理跑一遍涉及 `DemoStudioTransport` 关闭序列的测试（见下）。
- `_DemoCurrentWatch._frame` 现在对 Turn/Activity/Interaction/Storage 四种 update 直接传原实例（类型不可变）；若下游曾依赖“每帧都是新对象”的恒等性，会被影响——按现有 Client 代码看是值语义。
- 其它执行者在同一工作区有未提交改动（accounts views、`studio_reactive_projections.dart` 删除、若干 test/ui 与 test/unit 文件），本记录未触碰、未回滚；集中验证时需一并考虑。

## 验证记录

1. 引用核查（`rg`）：删除符号在 `lib/` 与 `test/` 中无残留（`_demoItem(`、`_demoDirectoryPage`、`pageCurrent`、`ChatAtom fit(`、`_frbInt`、`_frbNullableInt`、`_string(`、`_studioFailureCode`、`_demoAutoCompactLimit`、`_read`、`_accepted`、`_ownedHistoryReaders`、`_joinDemoConversations`、`h0/itemH0` 均为 0 命中；`_string(` 的命中全部是生成代码 `frb_generated*.dart` 中 `record_string_string(` 的子串误报）。
2. 官方格式化：仓库根 `cargo dart format <15 个改动文件>` → `Formatted 15 files (2 changed)`；级联清理后对 3 个文件重跑 → `Formatted 3 files (1 changed)`。
3. LSP 诊断（`.anywork/lsp/dart.toml`，server `dart`，`flutter_rust_bridge` 2.13.0）：对 15 个改动文件、两个 part 库其余 6 个 part 文件（`studio_frb_converters/studio_presentation_converters/studio_bots_converters/studio_acp_business_port/studio_delegation_converters/accounts/demo_account_observation`）与 12 个相关测试文件（`test/unit/frb_adapter/*` 10 个、`demo_current_reader_test.dart`、`demo_directory_observation_test.dart`）先 `documentSymbol` 再 `diagnostics`，全部 0 诊断，且符号表非空证明文件已被服务器实际加载。
4. 过程记录：分析服务器对 `apply_patch`/`sed` 改写的两个文件短暂返回了基于旧内容的诊断（已删 `_frbInt` 的 undefined、已删 `_read` 的 unused）；用 `documentSymbol` 触发重新加载后消失。单看“无诊断”不足以证明已分析，因此第 3 步对每个文件都先强制加载。
5. `git diff --check -- code/anywork/lib/src/infrastructure` → 无空白问题；`git diff --stat` → 15 files changed, 138 insertions(+), 529 deletions(-)。

## 独立复核与实际回归

独立审查已核对全部 15 文件差异、Demo 私有死读路径和现役 reader/watch 所有权、FRB 平台数值类型及 helper 顺序。下列定向命令已实际执行一次，exit 0，71 项通过；父读取原始输出末尾和命令记录核对。包含 Demo 在途 pull 关闭、未监听 watch 关闭、scope 收束、FRB ACK/失败重试、迟到创建接管及退出协调。注入托盘关闭失败用例的错误日志是预期输入，对应断言通过。

完整静态分析、UI、生成和预览仍由最终整合承担；该局部结果不外推 Web 或真实 bridge 动态验证。

```sh
cargo flutter test --no-pub test/unit/frb_adapter test/unit/demo_current_reader_test.dart test/unit/demo_directory_observation_test.dart test/unit/exit_coordinator_test.dart test/unit/studio_shutdown_scope_test.dart test/unit/test_app_lifecycle_test.dart test/unit/start_preparation_observation_test.dart
```

`exit_coordinator_test`、`studio_shutdown_scope_test`、`test_app_lifecycle_test` 直接覆盖 `DemoStudioTransport` 的关闭序列（本次删除了 `demo-conversation` 阶段），`start_preparation_observation_test` 与 `frb_adapter/*` 覆盖 FRB 侧被改的转换与 reader。GUI/集成测试按父代理整体计划安排。

## plan/workflow 共享映射收束

- 事实仍由既有 FRB DTO 提供；共享模块只转换结构，不增加协议、缓存、状态或业务所有者。Native runtime 的 revision 检查留在原 snapshot 装配处，run 由共享 mapper 构造。
- `studio_numeric_converters.dart` 从现有 Native 路径迁出 `exactTimelineInt` 与 `dateFromUnix`，原 part 库的所有真实调用一并迁移，未复制检查逻辑。计数必须非负且从 `BigInt` 转换后精确往返；revision、document version、graphRevision 不接受饱和或截断值。错误保留 `overloaded`、不可重试及 `client-timeline-range`，提示仍是原有 `Timeline state counter cannot be represented exactly`。
- 时间仍接受 FRB `PlatformInt64` 的原生 `int` 与 Web `BigInt`。先在 `BigInt` 上乘 1000，再验证精度及 `DateTime` 范围；拒绝错误时间，保留 `client-timestamp-type` / `client-timestamp-range` 及其原始错误类别和不可重试语义。负时间只要可表示仍合法。
- 新增 `test/unit/frb_adapter/workflow_converters_test.dart`，从共享真实 mapper 与 `acpWorkflowStateFromFrb` 入口验证完整 plan 文档、四种 phase、run 身份与 lifecycle、visited states 冻结、图状态/指令/边/guard、空投影、负数/溢出计数及时间越界；平台表示用共享时间转换的真实边界验证 int/BigInt。没有复制生产转换算法。
- 定向官方格式化已完成（9 个文件，5 个变化），定向空白检查通过。统一生成期间未运行新增测试；LSP 首轮曾出现生成 union 类型缺失，生成完成后的复核已全部消失。
- 根执行者通知统一生成成功后，下面的两文件联合命令实际运行一次，exit 0，30 项全部通过：新增 workflow 转换 20 项，既有 ACP mapper 10 项。无需修复或重跑，没有重复此前 71 项套件。

  ```sh
  cargo flutter test --no-pub test/unit/frb_adapter/workflow_converters_test.dart test/unit/frb_adapter/acp_business_mapper_test.dart
  ```

- 生成完成后对 `studio_api.dart`、`studio_api_contract.dart`、`studio_acp_business_mapper.dart`、`studio_frb_converters.dart`、`studio_presentation_converters.dart`、`studio_thread_stream.dart`、两个新增纯模块及上述两个测试文件逐一先查询 LSP `documentSymbol` 再查询 diagnostics，10 个文件全部 0 诊断。定义查询另已确认 Native 与 ACP 的 run 调用到达同一共享 mapper 声明。
- 本次实际运行平台为 Linux Dart VM；测试中验证了 `int` 与 `BigInt` 表示的转换行为，没有运行浏览器或真实 Native bridge，不外推为 Web、真实供应商或 GUI 验证。本执行者没有生成、pub get、完整 analyze、UI/GUI 或 Git 写操作。
