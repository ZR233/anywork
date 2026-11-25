# Flutter 测试边界清理

本记录汇总 B02 审读后落实的测试与工具清理；基线逐文件记录见 [测试边界](testing/review.md)。真实供应商登录与 load 场景仅修订验收逻辑，本轮未发出真实登录、额度或计费请求。

## 处理结果

- **T01 — 删除退役 ACP 安装验收链**：删除 `test/support/acp_install_contract.dart` 与唯一消费它、仅自测 DTO/谓词的 `test/unit/acp_usage_query_contract_test.dart`。现役 auth、install draft 与 usage metrics 测试保留。
- **T02 — 删除生命周期字段回读单例**：删除 `test_app_lifecycle_test.dart` 的 ChatGPT 静态夹具回读，保留两项真实 Client 关闭测试。
- **T03 — 计划卡片键盘行为**：`plan_summary_card_test.dart` 用真实 Enter/Space 切换展开，并检查有效 expanded 语义。
- **T04 — 删除无消费输入**：删除 `TimelineFixtureBatch.from` 和所有透传；`completion_run_view_test.dart` 的 `_runTitle` 删除无用 count。顺序、重复 ID、失败重试及展示断言保留。
- **T05 — 额度刷新必须证明本次请求**：ChatGPT 保存点击前的配置 `queryRevision`、状态 `revision` 和 `operationId`，只接受同配置、新操作 ID、更高状态 revision 的成功终态，同时观察真实查询失败。配置 revision 不随手动刷新递增。ACP 要求按钮操作只产生一个新命令，持有其 `acp-auth` 受理回执，并在等待及最终接受前确认该命令仍是同目标最新命令、没有失败；再等待同 owner、同连接、晚于受理 revision、操作已退出且 verified/usage ready 的状态。取消或替换不能用保留的旧额度通过验收。
- **T06 — 官方 UTF-8 allocator**：窗口 helper 使用 `String.toNativeUtf8(allocator: ffi.calloc)`，在 finally 用同一 allocator 释放；保留分配错误、Xlib、窗口归属及原错误返回，删除自写 C 库查找与 malloc/free typedef。
- **T07 — load-only 成员关闭合同**：断言 localComplete 为 true、sdkFinished 为 false；其余 timeout、unfinished、owner failure、SDK/driver error 与最终进程核验保留。
- **T08 — 侧栏互斥**：`workflow_graph_and_mode_selector_test.dart` 使用真实 `ConversationSidebarState<void>`，退出仅操作测试内两个布尔值的替身。
- **T09 — 断言与名称一致**：问题取消测试收窄为实际构造的窄窗只读场景；删除 ACP usage 测试名中未覆盖的 deletion、composer 名称中未覆盖的保稿承诺。删除重复 stopping、即时 identical、重复 watchCalls 别名、空分支及仅写不读的统计连接信号；各处已有真实行为断言保留。

## 额度观察的证据边界

Client 的 `LatestValue` 和账户 feed 是有界最新值镜像，可能合并短暂的 querying/activeOperation 帧。提前订阅不能把上游快照变成可靠事件队列。初版返修依赖必见中间帧，新增三例失败；最终修正为终态保留的操作 ID（Native）或本次命令保留的受理回执及最新命令身份（ACP）。ACP 终态不保留操作 ID，故不靠秒级 checkedAt 猜测新旧，也不为验收扩充产品协议。

最终独立审查还发现：ACP 查询被取消后，后端有意保留旧 Verified 和 Ready，同时推进 revision；仅凭受理回执和较新终态仍会假通过。现由真实登录入口和窄回归共用 `test/support/acp_usage_refresh.dart`，分开核对按钮受理与终态观察。点击返回前若查询、取消都已发生，新增命令数不为一，直接拒绝；开始等待后若有取消或替换，原命令不再是最新，拒绝旧额度。回归使用真实 AcpService、MutationBoard 与领域观察，仅脚本化外部端口，保留同秒同额度快速成功的合法情形。

`settings_account_usage_queries_adapter_test.dart` 通过真实 AccountUsage repository 与 observation，验证快速成功、延迟传输失败、配置换代后旧终态拒绝，以及原有可见需求和只读 provider 行为。`ScriptedUsageTransport` 仅提供外部事实，仍保留有界最新帧语义。最终定向命令 5 项通过（exit 0）；两个真实登录入口完成静态检查，没有运行真实供应商验收。

`cargo flutter test --no-pub test/unit/acp_usage_refresh_acceptance_test.dart` 最终 3 项通过（exit 0），helper、测试及 ACP 真实登录入口三文件 `cargo dart analyze` 为 `No issues found!`。首次命令因夹具构造参数误写 `label` 而未能编译，未执行用例；按真实 API 改为 `name` 后完成上述验证。两种取消都确认原查询命令无失败、旧额度仍在，同时共用验收明确拒绝；快速成功允许 checkedAt 和额度值与旧值相同。各用例的 runtime 和 transport 关闭报告均无遗留。

## 已执行验证

- 相关 settings、Gemini、plan、workflow、生命周期和 completion controller/view 共 7 文件联合 30 项通过。
- 完整 UI 首轮 580 通过、2 失败：MCP 重连等待环原先按全页面查找，误包含新官方 context 环；新会话设置按钮的 key 已在按钮自身，旧 descendant finder 为空。按真实组件作用域同步定位，并将 MCP gate／租约／AppGraph 清理注册为失败时也执行的 teardown；保留原行为断言。两个失败场景在一次过滤联合命令中 2 项通过，相关两文件 LSP 0。
- 完整 `test/unit` 在 T05 新增回归之前 438 项通过；T05 修改后用 Native 5 项、ACP 3 项分次定向验证补齐，不把先前完整结果冒充新版本重跑。
- `ffi 2.2.0` 锁定源码核对分配／释放契约。Linux X11 隔离探针直接 import 当前窗口 helper，在自有 Xvfb 和带 PID 属性的空白窗口上执行三条路径：driver 无 DISPLAY 时显式分配并 resize/恢复；同 DISPLAY resize/恢复；分配后认证失败使 XOpenDisplay 返回 null 并正确拒绝。三个 Dart 场景 exit 0，xwininfo 独立确认几何，所属进程与显示均已回收。初次外层采样碰到已退出进程的 `/proc` 竞态，仅修探针并补跑尚未执行的失败路径，已成功场景没有重复运行。
- X11 验证不覆盖逐笔分配泄漏检测、内存耗尽、GTK/Flutter UI、Windows 或 macOS。load 与真实登录没有运行；完整 UI 与最终分析的结果统一记录在 [总台账](flutter-quality-audit.md)。
