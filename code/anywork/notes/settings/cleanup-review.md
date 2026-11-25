# Settings 通用模块清理审查

## 范围与结论

审查 `lib/src/features/settings/` 根目录下 36 个手写 Dart 文件。`accounts/` 子目录完全排除；其中父代理正在改动的文件只通过只读调用关系核对。另审查设置页内 `statistics/` 的边界调用，不把统计业务改动混进本模块。当前仅做了一项可局部验证的清理：Bot 会话菜单改用共享 `StudioMenuButton`，菜单项与原回调语义保留。没有改配置格式、产品设置行为、Rust、Client、生成物或长期设计文档。

所有文件按实现、入口和消费者关系判定保留/清理；未因文件大小、行数或 `rg` 命中数拆分文件。未发现可证明无消费者而应删除的设置接口或夹具。新增 `test/ui/settings_cleanup_test.dart` 作为本次 Bot 菜单迁移的行为回归覆盖，不直接构造私有 `_BotDetail`，也不复制生产 View。

## 逐文件清单

| 文件 | 职责与代码证据 | 处理结论 |
| --- | --- | --- |
| `agent_workspace_mode_label.dart` | `agentWorkspaceModeLabel` 将完整 `AgentWorkspaceMode` 枚举映射到 l10n。 | 保留；作为领域枚举的展示映射，仍由 Profile/角色设置展示使用。 |
| `settings_agent_profile_dialog.dart` | `AgentProfileDialog` 持有草稿、表单验证、路由选项及异步保存错误；保留 canonical account/model/effort。 | 保留；其草稿与“不可解析时不静默改值”的行为属于产品语义。 |
| `settings_agent_routes.dart` | Profile/agent route 的模型选项与 route 值解析。 | 保留；共享模型路由选择器的设置域适配。 |
| `settings_agents_tab.dart` | 展示 agent profile 和角色配置，发出保存/删除等 UI 意图。 | 保留；仍是设置页面入口及命令调用者。 |
| `settings_bot_conversation_page.dart` | 单会话 route 页面，向 `BotsTab` 传递 bot/chat 标识。 | 保留；深链页面承载者，不能由列表行替代。 |
| `settings_bots_detail.dart` | Bot 详情、会话行、访问授权、消息与控制操作；本次会话行菜单是唯一清理点。 | 将 `PopupMenuButton` 迁移到共享 `StudioMenuButton.icon` / `MenuItemButton`；保留 `botsConversationActions` key、禁用条件、平台工具/信任切换/新建线程三项动作及原回调。 |
| `settings_bots_editor.dart` | Bot 注册信息编辑与验证 UI。 | 保留；仍由 BotsTab 编辑流程调用。 |
| `settings_bots_registration.dart` | Bot 手动/平台注册和凭据提交 UI。 | 保留；负责既有注册入口及凭据交接。 |
| `settings_bots_tab.dart` | Bot 设置状态、列表/详情选择、查询生命周期、命令组装；新增共享菜单 import。 | 保留；作为 `settings_bots_detail.dart` 的 library/part owner，状态与 Client 所有权仍留在原处。 |
| `settings_common.dart` | re-export 设置布局、字段、readout、反馈和行组件。 | 保留；多个页面共享的呈现 barrel 有消费者。 |
| `settings.dart` | 设置模块公开导出入口。 | 保留；仍作为 feature 导出面。 |
| `settings_delegation.dart` | 显示并提交默认 delegation mode/preference。 | 保留；直接绑定 settings store/commands，影响已有设置行为。 |
| `settings_feedback.dart` | 保存中/失败等 inline feedback 呈现。 | 保留；多个设置表单复用。 |
| `settings_fields.dart` | `SettingsTextEdit`、响应式字段布局及设置表单输入构件。 | 保留；表单字段管理 TextEditingController 生命周期并同步外部草稿值，非冗余的原生 `TextFormField` 替代品。 |
| `settings_form_dialog.dart` | 统一的设置表单对话框壳和提交/取消按钮。 | 保留；当前 AgentProfileDialog 有实际调用，不能按“仅一个消费者”误判成无消费者。 |
| `settings_general_tab.dart` | 通用设置字段与命令映射。 | 保留；持有一般设置 UI 和字段保存连接。 |
| `settings_instructions_tab.dart` | 用户/项目指令查看编辑入口及保存状态。 | 保留；作用域与文案由此功能呈现。 |
| `settings_layout.dart` | 设置面板、section/card 与响应式布局原语。 | 保留；供多个设置 tab 与统计组件共享。 |
| `settings_lsp_tab.dart` | LSP 配置列表、状态、刷新与操作呈现。 | 保留；客户端配置查询/命令的 UI owner。 |
| `settings_mcp_tab.dart` | MCP server 配置、连接状态与操作 UI。 | 保留；MCP 设置命令与状态展示均有实际调用。 |
| `settings_page.dart` | 设置路由页、tab 可见性和 tab 选择状态。 | 保留；feature 页面入口及可见性边界。 |
| `settings_readouts.dart` | key/value、metric 与只读展示组件。 | 保留；设置和 statistics 页面共用。 |
| `settings_remote_directory_dialog.dart` | 远程目录选择/校验对话框及异步错误显示。 | 保留；负责 SSH 目录选择交互和失败反馈。 |
| `settings_resource_row.dart` | 技能/资源条目的状态、元信息与动作行。 | 保留；由 skills 设置列表复用。 |
| `settings_rows.dart` | 设置列表行与分隔等通用布局。 | 保留；多个设置区域共用。 |
| `settings_scope.dart` | settings-domain 可见性订阅/租约适配。 | 保留；决定何时持有设置域数据订阅，属资源生命周期边界。 |
| `settings_section.dart` | 单一设置 section 的轻量呈现构件。 | 保留；由设置内容组装使用，职责窄且未发现重复 owner。 |
| `settings_security_tab.dart` | 安全与敏感操作相关设置说明/入口。 | 保留；用户可见安全语义单独展示。 |
| `settings_skills_tab.dart` | skills 列表、状态及管理操作。 | 保留；复用 resource row 与 settings commands。 |
| `settings_ssh_password_dialog.dart` | SSH 密码输入、提交和错误反馈。 | 保留；敏感输入及控制器/表单生命周期需要独立对话框。 |
| `settings_ssh_server_dialog.dart` | SSH server 创建/编辑表单与异步提交。 | 保留；配置保存 owner 仍为现有 Client command。 |
| `settings_ssh_server_row.dart` | SSH server 单行状态与操作。 | 保留；由 SSH 设置 tab 列表使用。 |
| `settings_ssh_tab.dart` | SSH server 列表、连接/选择和对话框入口。 | 保留；已有 route 和 Client 命令消费者。 |
| `settings_views.dart` | settings 各 view model / projection provider 与展示派生。 | 保留；跨设置视图的 Riverpod 读模型，避免重复状态事实源。 |
| `settings_web_search.dart` | web search 配置表单和供应商/选项呈现。 | 保留；现有设置项及命令状态展示，不擅改 schema/行为。 |
| `settings_worktree_recovery.dart` | 恢复问题、worktree 预览和清理/重试交互。 | 保留；失败责任委托给 Client command 并展示错误，不能在 UI 隐去清理失败。 |

## 调用关系与验证

- Dart LSP `findReferences` 对共享 `StudioMenuButton` 返回了 settings 的 `settings_bots_detail.dart` 调用点（迁移后）、shell、conversation/status 及 tests；accounts 下的 `AccountMenuButton` 只读观察，未编辑。
- Dart LSP 对目标 `settings_bots_detail.dart` 和 `settings_bots_tab.dart` 均返回 `No diagnostics.`。Dart formatter 实际执行：`cargo dart format lib/src/features/settings/settings_bots_tab.dart lib/src/features/settings/settings_bots_detail.dart`，结果 `Formatted 2 files (0 changed)`。
- 新增 `settings_cleanup_test.dart` 使用真实 `AppGraph`、`createApplicationRouter()` 生成的 typed route table、生产 `BotDetailsPage`/`BotsTab` 和 Demo transport。它断言 platform action 推入 typed route、目的页收到正确 bot/chat 并读取该 chat；还验证 group trust/revoke 反转当前信任值、创建 thread 使用正确 bot/chat、direct conversation 不显示信任动作，以及 enabled 写入 pending 时菜单触发器禁用。Demo transport 仅提供对话 fixture、记录请求，并用可释放 completer 暂停 enabled command；测试 teardown 会释放并等待该命令完成。
- `cargo flutter test --no-pub test/ui/settings_cleanup_test.dart` 已实际运行四次，均 exit 1。第一次日志还包含 direct 菜单按钮位于视口外，测试已用 `ensureVisible` 处理；第二次确认 platform action 会推入 `BotPlatformToolsRoute`，测试最初错误期待本页直接读取消息；父代理串行轮又确认 `routeInformationProvider` 在 imperative `push` 后仍报告 `/bots/bot-1`，已改为检查 typed route 构造的 keyed `BotDetailsPage`。本轮成功走过该 route assertion 和目的页读取，随后因 busy command 保持期间对仍在动画的 UI 调用了 `pumpAndSettle` 而超时；已改成单帧 pump，并在释放命令后直接检查按钮恢复启用。父串行轮与本轮均未报告 shader mismatch；shader/目录写入竞争只见于前两次。修正后已在七文件联合回归中通过（总计 30 项，exit 0）；本文件的真实 Bot 动作、目的页面与 busy 禁用断言均通过。
- 共享组件的一般行为仍由 `studio_menu_button_test.dart` 覆盖；Bot action 接线由本文件覆盖。未运行全量 analyze、生成、GUI 或 Git 写操作。设置表单/数据契约没有进入统计/Client/Rust 侧。
