# Issue #262 测试入口迁移对照

基线：`044ded39cb508b1ad1db8377a24c50e7642e6549`。
审计单位是行为，不是文件。本表随 PR 供审阅，不作为长期运行器清单。

列含义：

- **行为**：输入等价类 → 动作 → 责任边界 → 独有结果
- **去向**：唯一新位置，或删除理由

## 1. 应用 Dart（`code/anywork/test/`，79 个 `_test.dart`）

| 当前位置 | 行为 | 去向 |
| --- | --- | --- |
| `client/account_domains_adapter_test.dart` | Demo/FRB 账号域装配、独立 AppGraph 账号目录 | `test/unit/frb_adapter/`；Demo 工厂改为 `createDemoAppGraph()` |
| `client/accounts_navigation_contract_test.dart` | 账号导航契约（无 widget） | `test/unit/` |
| `client/accounts_typed_route_contract_test.dart` | 类型化路由 + AppGraph | `test/ui/` |
| `client/accounts_view_models_test.dart` | 账号 ViewModel 规则 | `test/unit/` |
| `client/acp_auth_duplicate_input_test.dart` | ACP 认证重复输入 | `test/unit/` |
| `client/acp_command_notice_adapter_test.dart` | ACP 命令通知适配 | `test/unit/` |
| `client/acp_install_draft_test.dart` | ACP 安装草稿 | `test/unit/` |
| `client/acp_install_summary_contract_test.dart` | 依赖 `test_driver` 的 ACP 摘要契约 | 独有契约并入 `test/unit/`；Driver 依赖删除 |
| `client/agent_detail_read_only_test.dart` | 子会话只读详情 UI | `test/ui/` |
| `client/agent_directory_selection_test.dart` | 目录选择 + AppGraph | SDK 独有归 `anywork_client`；UI 连通性 `test/ui/` |
| `client/agent_list_stop_button_test.dart` | 停止按钮真实点击 | `test/ui/` |
| `client/agent_list_stop_test.dart` | 停止资格规则；两处 Idle+awaitingScheduling 重复 | `test/unit/`，只留一个等待调度规则，合入无停止资格断言 |
| `client/app_graph_observation_test.dart` | AppGraph 观察/关闭 | `test/unit/`（fake transport） |
| `client/app_route_draft_test.dart` | 路由草稿 + `AnyworkApp` | `test/ui/`，挂载共享 body、不装 native host |
| `client/bots_adapter_test.dart` | Bot 适配 + AppGraph | `test/unit/` |
| `client/bots_frb_adapter_test.dart` | Bot FRB 映射 | `test/unit/frb_adapter/` |
| `client/child_interaction_card_test.dart` | 子交互卡片 UI；含 DriverDemo 场景 | UI 留 `test/ui/`；DriverDemo 场景删除 |
| `client/child_interactions_frb_adapter_test.dart` | 子交互 FRB 映射 | `test/unit/frb_adapter/` |
| `client/client_boundary_check_test.dart` | 边界检查规则 | 扩展 UI 闭包检查后仍在静态入口；测试随 `xtask/dart/` |
| `client/client_close_and_bootstrap_test.dart` | Client 关闭/启动 | SDK 已有生命周期则下移；应用装配留 `test/unit/` |
| `client/client_retirement_report_test.dart` | Demo 退役报告 | SDK `chat_lifecycle_test`（A1/A2 未解决责任、healthy-active 排除）；Demo 自测删除 |
| `client/composer_button_matrix_test.dart` | Composer 真实 tap/Enter/身份 | `test/ui/`，不复述 truth table |
| `client/composer_failure_label_test.dart` | 失败标签呈现 | `test/ui/` |
| `client/composer_primary_action_test.dart` | Composer 主按钮 truth table | `test/unit/`，唯一规则表 |
| `client/context_usage_readout_test.dart` | 用量读数 UI | `test/ui/` |
| `client/conversation_chat_admission_test.dart` | 会话准入规则 | `test/unit/` |
| `client/conversation_live_status_test.dart` | 实时状态呈现 | `test/ui/` |
| `client/directory_recovery_route_test.dart` | 恢复路由 UI | `test/ui/` |
| `client/exit_coordinator_test.dart` | 退出协调器竞争/复用期限 | `test/unit/`；进程外退出归 native |
| `client/frb_reader_registration_test.dart` | FRB reader 注册 | `test/unit/frb_adapter/` |
| `client/frb_recovery_adapter_test.dart` | FRB 恢复映射 | `test/unit/frb_adapter/` |
| `client/frb_timeline_adapter_test.dart` | FRB timeline 映射 | `test/unit/frb_adapter/` |
| `client/model_selector_keyboard_test.dart` | 模型选择键盘 | `test/ui/` |
| `client/native_account_auth_widget_test.dart` | 账号认证 widget | `test/ui/` |
| `client/native_account_draft_auth_test.dart` | 账号草稿认证规则 | `test/unit/` |
| `client/plan_detail_status_test.dart` | 计划详情状态 UI | `test/ui/` |
| `client/plan_feedback_lifecycle_test.dart` | 计划反馈生命周期 UI | `test/ui/` |
| `client/plan_runtime_document_entry_test.dart` | 计划文档入口 UI | `test/ui/` |
| `client/session_fact_convergence_test.dart` | 会话事实收敛 | `test/unit/` |
| `client/session_selector_pointer_keyboard_test.dart` | 会话选择器指针/键盘 | `test/ui/` |
| `client/session_selector_sync_test.dart` | 选择器同步；含 Demo | UI 连通性 `test/ui/`；Demo 业务删除 |
| `client/session_stop_continue_test.dart` | 停止/继续；含 Demo 执行 | SDK `studio_command_receipts_test`（含无内容 continue 不写草稿）；Demo 执行自测删除 |
| `client/settings_account_model_origin_adapter_test.dart` | 模型来源适配 UI | `test/ui/` / `test/unit` 按是否挂页面 |
| `client/settings_account_usage_demand_test.dart` | 用量按需加载 | `test/unit/` |
| `client/settings_account_usage_queries_adapter_test.dart` | 用量查询适配 | `test/unit/` |
| `client/settings_command_observation_test.dart` | 设置命令观察 | `test/unit/` |
| `client/start_preparation_observation_test.dart` | 启动准备观察；Demo | `test/unit/` fake transport |
| `client/startup_error_route_test.dart` | 启动失败/重试 UI | `test/ui/`，`AnyworkApp` 不装 host |
| `client/statistics_effort_breakdown_adapter_test.dart` | 统计拆解呈现 | `test/ui/` |
| `client/studio_driver_query_test.dart` | Driver 查询自测 | **删除**（Driver 退出） |
| `client/thread_status_bar_test.dart` | 状态栏 | `test/ui/` 或 `test/unit` 按挂载 |
| `client/timeline_atom_attachments_test.dart` | 附件原子呈现 | `test/ui/` |
| `client/timeline_completed_activity_adapter_test.dart` | 完成活动适配 | `test/unit/` |
| `client/timeline_demo_tail_test.dart` | Demo tail 执行语义 | SDK `timeline_tail_test` / Rust；Demo 自测 **删除** |
| `client/timeline_display_lease_test.dart` | 展示 lease | `test/unit/` |
| `client/timeline_image_card_presentation_test.dart` | 图片卡片 | `test/ui/` |
| `client/timeline_markdown_wrap_test.dart` | Markdown 换行 | `test/ui/` |
| `client/timeline_message_controller_test.dart` | 消息 controller | `test/unit/` |
| `client/timeline_question_receipt_test.dart` | 问答收据 UI | `test/ui/` |
| `client/timeline_raw_origin_test.dart` | 未知内容降级 | `test/ui/` |
| `client/timeline_readiness_adapter_test.dart` | 就绪适配 | `test/unit/` |
| `client/timeline_realtime_history_isolation_test.dart` | 实时/历史隔离；Demo | `test/unit/` fake；Demo 删除 |
| `client/timeline_row_observation_test.dart` | 行观察 UI | `test/ui/` |
| `client/timeline_session_owner_test.dart` | TimelineSessionOwner | `test/unit/` |
| `client/ui_language_test.dart` | 语言切换 + `AnyworkApp` | `test/ui/` |
| `client/worktree_recovery_settings_test.dart` | 工作树恢复设置 UI | `test/ui/` |
| `client/flutter_test_config.dart` | 全局 NativeTransport.testing | **不提升到根**；插件 adapter 局部 fixture |
| `client/support/*` | 合成数据 / RecordingDemo | `test/support/`；去掉 Demo 业务镜像 |
| `driver/host_cwd_directory_proof_test.dart` | Driver 目录证明 | 独有跨层则 `integration_test/functional/`；否则 **删除** |
| `driver/realtime_tool_observation_test.dart` | Driver 实时工具观察自测 | **删除** |
| `driver/timeline_activity_observation_test.dart` | Driver 观察解析自测 | **删除** |
| `driver/tool_probe_read_text_test.dart` | Driver probe 自测 | **删除** |
| `features/settings/accounts/acp_usage_metrics_test.dart` | ACP 用量指标 UI | `test/ui/` |
| `features/timeline/chat_batch_component_test.dart` | ChatBatch 组件 | `test/ui/` |
| `features/timeline/chat_item_rich_presentation_test.dart` | 富文本呈现 | `test/ui/` |
| `features/timeline/conversation_current_connector_test.dart` | current connector | `test/ui/` |
| `features/timeline/frb_content_watch_test.dart` | FRB content watch | `test/unit/frb_adapter/` |
| `features/timeline/timeline_children_component_test.dart` | children 组件 | `test/ui/` |
| `features/timeline/timeline_markdown_test.dart` | Markdown 组件 | `test/ui/` |
| `features/timeline/wait_presentation_integration_test.dart` | Waiting 呈现 | `test/ui/` |
| `platform/macos_terminal_test.dart` | macOS 终端 quoting | 保留为 native/platform 项目测试，CI macOS job |

## 2. SDK（`code/anywork_client/test/`，32 个）

全部保留在 SDK 包。`verify-client` 只跑这里，不再隐式跑应用 `test/client`。

Demo 执行语义中属于 Client owner 的独有断言（若现有 SDK 未覆盖）并入对应 SDK 测试，不新增第二套 reducer。

## 3. 官方 integration_test

| 当前位置 | 行为 | 去向 |
| --- | --- | --- |
| `integration_test/wait_events_test.dart` | 真实 FRB Waiting/停止/继续；测试运行器拥有进程 | `integration_test/functional/wait_events_test.dart`；共享 `AnyworkApp` body，`enableDesktopHost: false` |
| `integration_test/conversation_read_work_test.dart` | 真实冷读/分页/独立页 | `integration_test/functional/conversation_read_work_test.dart`；共享 body |
| （缺口）desktop smoke | 生产装配启动→隔离会话→fixture 文本→关闭 | 新增 `integration_test/functional/desktop_smoke_test.dart` |
| （缺口）性能 | watchPerformance / reportData | `integration_test/performance/`，与 functional 发现隔开 |

## 4. 旧 `test_driver/`（整树删除）

正式业务回归退出项目 `FlutterDriver`。无转发兼容层。`code/anywork/test_driver/` 已整树删除。

| 组 | 处置 |
| --- | --- |
| `timeline_native_gate_{app,main,test}.dart` | **已删除**（冻结窗口 PoC） |
| `driver_main.dart` 及全部 CommandExtension | **已删除** |
| `flutter_driver_session.dart`、`manual_capture.dart`、`request_shutdown.dart` | **已删除**；截图改 `tool/capture_ui.dart` |
| `*_journey.dart`、`stress_*`、`*_probe.dart` | **已删除**；人工场景改为 operator runbook + `ext.anywork.requestExit`；native 退出走 launcher report |
| ACP 摘要/用量契约 | 独有合同迁入 `test/support/acp_*.dart` 与 `test/unit/acp_*_contract_test.dart` 后删除旅程 |
| `*_observation*_test.dart`、`*_contract_test.dart`、Driver 解析自测 | **已删除** |
| `shutdown_fault_driver.dart` | 改为 `tool/native_fault_main.dart` + `ANYWORK_NATIVE_SHUTDOWN_FAULT` |
| `window_control*.dart` | **已删除** |
| `fixtures/tool-image.png` | **已删除** |

## 5. Rust tests / examples

| 入口 | 行为 | 去向 |
| --- | --- | --- |
| `pl-core/tests/chat_page.rs::class_and_typed_parent_indexes_never_budget_hidden_candidates` | Session::page 索引/预算/无历史 I/O | **唯一规范测试**，吸收 hidden 规模、kind、非首尾、visited seq |
| `pl-core/tests/chat_performance.rs::increasing_hidden_pending_does_not_increase_scoped_budget_work_or_history_io` | 同上 | **删除**（语义重复） |
| `pl-core/tests/chat_performance.rs` 其余确定性 work/IO | 快速正确性 | **保留在 PR 门禁**；墙钟/RSS 才进 performance |
| 其余 `pl-core/tests`、`pl-model/tests`、`pl-patch/tests`、`pl-studio-runtime/tests` | 各 crate 公开规则 / SQLite / 协议 | 保留；CI 用 workspace 一次发现，不再按 crate 白名单漏跑 |
| `pl-tool/examples/command_capture_limit_validation.rs` | UTF-8/字节预算、exec 拒绝、真文件双流 | excerpt → `pl-output/tests/excerpt_budget.rs`；拒绝/no-spawn/预算 → `pl-tool/tests/command_capture_limit.rs`；真 helper → `helper_capture.rs`。**已删除 example** |
| `pl-tool/examples/helper_capture_budget.rs` | 真实 helper 预算 | `pl-tool/tests/helper_capture.rs` |
| `pl-tool/examples/remote_directory_validation.rs` | 远端目录边界 | `pl-tool/tests/remote_directory.rs` |
| `pl-tool/examples/remote_resource_validation.rs` | 重连/释放 vs 压力 | 功能/重连/释放 → `pl-tool/tests/remote_resource.rs`；预算准入 → `pl-remote-helper/tests/resource_budget.rs`；大规模并发压力不进默认发现 |
| `pl-tool/examples/ssh_remote_validation.rs` | 真实 SSH | `pl-tool/tests/ssh_remote.rs` `#[ignore]`；默认未执行，`--ignored` 缺条件失败 |
| `pl-core/examples/task_lookup_scaling.rs` 及 Criterion | 性能 | 保留 performance；确定性预算留 PR |
| `pl-studio-runtime/examples/{model,collaboration,context_cache,session_layout,updater}_observe.rs` | 人工/live 观察 | 保持显式 opt-in，不进默认 CI |
| `pl-core/examples/minimal_thread.rs` | 示例 | 只编译不执行 |

## 6. Native / 脚本 / acceptance

| 入口 | 去向 |
| --- | --- |
| `pl-studio-acceptance` `manual-gui --scenario` | 人工 `--preset`；自动 desktop/native 从 `test-project` 调用 |
| 正常退出 / 重开 / 第二实例交接 / 重复退出共享期限 | `test-project --suite native` 的 `shutdown`：薄装配 `tool/native_fault_main.dart` + 生产 Client 提交，进程外裁判真实 native pid / 退出码 |
| Dart hang / 初始化中关闭 / bridge 失败 / 订阅故障 | 同套 `shutdown`：`ANYWORK_NATIVE_SHUTDOWN_FAULT` 只开该场景所需故障；hang 在 `beginExit` 后冻结 isolate，由 30s native 期限给出退出码 1 |
| SQLite 写锁 / 无响应供应商 | 同套 `shutdown`：真实 `BEGIN IMMEDIATE` 与 fixture SIGSTOP；prime 不得丢失，reopen `quick_check` |
| MCP / LSP / tool 子树与 SIGTERM-ignoring grandchild | 同套 `shutdown`：场景自有 stdio peer；产品 supervisor 必须在 harness 介入前回收；Linux 进程树证明 |
| concurrent-stop（MCP+tool+写锁） | 同套 `shutdown`：28s cleanup 预算、15s ACK 界、独立 monitor 时钟；`cleanExit` 不算通过 |
| `--seed-home-copy` 关闭库迁入 | **独特迁移证明**，仍在人工 `manual-gui --preset gui`；人类 verdict 保持 pending，不进自动 shutdown |
| Windows Job Object | Linux 跑列为 `coverage.json` `windowsNativeAcceptance=notrun`（批准的平台缺口）；需 Windows 宿主执行同一 `--preset shutdown` |
| `.github/scripts/studio-macos-termination-tests.py` | macOS native job / process group |
| `.github/scripts/studio-release-assets.tests.ps1` | 发布校验，非业务回归 |
| `code/anywork/linux/install-desktop-entry.py` | 安装脚本，非测试套件 |

## 7. 命令与 CI

| 旧入口 | 新入口 |
| --- | --- |
| `verify-client` 跑应用 `test/client` | 仅 SDK |
| `verify-gui` 格式 `lib test_driver integration_test` | `lib test tool integration_test`，静态不冒充测试 |
| `run-gui --driver` / `--integration-test` | **删除公开别名**；`test-project --suite desktop` |
| `run-gui --native-launch` + Driver | `NativeLaunchSpec` + `test-project --suite native` |
| `manual-gui --scenario` | `manual-gui --preset` |
| 新增 | `run-gui --capture`；`tool/capture_ui.dart` |
| PR `paths-ignore: design/**` | cheap `changes` + 始终 `ci-gate` |
| 指定 crate `cargo test -p …` | Linux `cargo test --locked --workspace --features pl-core/sqlite` |
| Flutter job 含 verify-client adapter | UI job：`cd code/anywork && flutter test --no-pub test/ui`，无 `-d`、无 Rust |
| `native-acceptance.yml` Driver 标签路径 | 退役；functional/native 进主门禁 |

## 8. 必须保留的不同风险（不去重）

- Core 内存索引 vs 真实 SQLite 事务/回滚
- stream 未结束发布 vs SQLite 写锁 pending 交接
- 不同存储迁移阶段
- Windows Job Object / Linux 进程树 / macOS process group
- `chat_performance` 确定性 work/IO（墙钟统计除外）
