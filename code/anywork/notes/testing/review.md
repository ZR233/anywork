# B02 测试与夹具边界审读

**最终处理入口**：以下保留独立只读审读的证据与建议；T01–T09 和局部清理均已落实，具体修改及最新验证见[清理记录](../testing-cleanup.md)与[总台账](../flutter-quality-audit.md)。下文“本轮未运行”仅描述审读者的操作，不否定后续执行者已有结果。

范围为 `code/anywork/test/` 与 `code/anywork/integration_test/` 的基线手写 Dart。基线提交、共享分支与总计划见 [总台账](../flutter-quality-audit.md)。实际基线分别为 157 与 32 个文件，均含 support；另有 integration 的验收说明和 PNG 资产，不计入 Dart 数。`tool/` 四文件已有 [platform 审读](../platform/review.md)，本组不重复宣称审读。

本目录只记录只读审查。未修改生产、源测试、生成物、依赖与 Git；未运行 test、analyze、GUI、pub 或生成。LSP 定义/引用查询属于静态语义证据，不能替代测试执行。本轮读的是共享工作区可见版本；邻居的在途测试迁移归原 owner。父已报告统一生成成功，生成一致性不作为本组阻塞。

**B02 基线全文审读已闭合：189/189。** `test/` 157 个与 `integration_test/` 32 个基线手写 Dart 均已逐段阅读全文并记录现役入口与处理理由。交付另有18个新增测试／support 文件，不计入基线分母；原16个已由最终代码审查者完整阅读2849行，后补ACP验收helper和取消回归2个文件共344行也已全文续审通过。T01两文件在全文审读完成后已删除，仍保留基线记录。逐文件事实见 ledger。

| 范围 | 基线文件 | 本轮全文已读 | 待全文补读 |
| --- | ---: | ---: | ---: |
| test/support | 17 | 17 | 0 |
| test/ui | 89 | 89 | 0 |
| test/unit（含 frb_adapter） | 47 | 47 | 0 |
| test 根目录 | 4 | 4 | 0 |
| integration_test/support | 23 | 23 | 0 |
| integration_test 入口 | 9 | 9 | 0 |
| 合计 | 189 | 189 | 0 |

已按真实基线树精确对照 ledger：189个路径无缺项、无多记、无重复，基线行全部为全文已读。台账共207条文件记录，七列结构完整；集合检查只验证记录闭合，全文结论来自各文件连续正文阅读。新增文件分别记录原负责人、最终全文复核与实际运行证据，未把局部通过当作全文审读。

## 证据与台账口径

[逐文件 ledger](review-ledger.tsv) 是覆盖状态的唯一清单。`本轮全文已读` 表示该文件的连续正文已读完，长输出遗漏处从原命令捕获恢复；`待全文补读` 不表示没有覆盖，更不表示可删。清点、文本引用搜索、LSP、以往运行通过均不冒充全文阅读。新增文件另列原 owner 及状态，不计入基线分母。

现有 owner 记录的复用范围如下。生产/预览的全文声明不能自动传递给相关测试；`related-case-read` 明确只证明局部 case。

| 既有记录 | 可复用证据 | 限制 |
| --- | --- | --- |
| [timeline ledger](../timeline/review-ledger.tsv)、[state and views](../timeline/state-and-views.md)、[previews](../timeline/previews.md) | `wait_presentation_integration_test` 迁现役工具行；3 项等待用例、1 项组件挂载、6 项模型滚动；新增 metadata 8 项、projection 10 项。生产 owner、工具适配和预览调用链全文证据可复用。 | 原测试状态为 related-case-read。本组已逐份补齐所有基线测试全文；新增两份仍按owner记录。运行结果属于 owner 报告，非本轮执行。 |
| [infrastructure](../infrastructure/m06-m07-frb-demo-cleanup.md) | FRB/Demo 的真实所有权与映射边界审读；`frb_adapter/`、Demo readers、exit/shutdown/test lifecycle/start preparation 的联合命令 71 项通过。 | 测试 documentSymbol/diagnostics 与运行不等于测试全文已审；本组已补齐基线正文。新增workflow转换由owner负责，另有workflow 20项与ACP mapper 10项联合通过报告。 |
| [accounts](../accounts/review.md)、[Gemini 呈现](../accounts/gemini-presentation.md) | 账号 VM/焦点生产入口、模板及 ACP 阶段；原四个账号文件和两项 modes 联合 79 项；新增 ACP template loading 1 项。 | 新测试由账号 owner 负责；不把 79 项拆成未经报告的单文件项数。 |
| [conversation input](../conversation-input/review.md)、[说明](../conversation-input/README.md) | composer/interactions/ACP 生产和预览全文；新增 interaction cleanup 自身通读；最新权限身份6/6、过程分组25/25、交互2/2来自分次运行的owner报告。 | 原有相关测试由本组补齐全文；不把生产78文件计入B02，不把33项说成同次联合全绿。 |
| [shared](../shared-components.md) | 共享菜单/Unicode initials 14 项、Native/ACP 状态栏另14项；真实菜单组件族和root迁移依据。 | 新文件归父/shared；单组件通过不外推领域动作映射。 |
| [modes](../modes/quality-review.md) | 画布focus及表单的原始问题与调用链，新增行为测试由owner负责；联合运行见总台账。 | 模式生产全文不等于所有离页测试全文。 |
| [update](../update.md) | 新窄窗/notes错误3例修前失败，修后与delivery/VM联合11项通过。 | 不证明原生安装器或真实网络。 |
| [shell](../shell/review.md)、[settings](../settings/cleanup-review.md)、[driver](../driver/review.md)、[statistics](../statistics/cleanup-review.md) | 现役入口及已删除接口的责任边界、建议回归、Driver选择器迁移。 | 文本引用/定向诊断与待跑建议不记成实际通过。 |

## 待父裁定的具体清理

### T01：退役安装验收夹具及其专属自测，整链删除建议已在共享现场落地

`test/support/acp_install_contract.dart` 全文 719 行定义旧 acp-auto-install 旅程的 summary、截图写入、保存身份、认证与固定 AGY 1.4.1 ZIP 期望。现役 `integration_test/`、`tool/`、Rust acceptance 和应用均不再消费这条验收链。全仓引用核查只剩 `test/unit/acp_usage_query_contract_test.dart` 导入它；该测试全文 130 行，仅用手工 JSON 快照验证 `acpUsageQueryReady` 与 `requireAcpFixtureUsage`，没有消费者把这些判据接回实际旅程。

交付清点时，两文件在共享工作区均已删除，基线差异分别为719与130行删除；这是父/邻居的在途改动，本执行者没有改源测试。以下保留原审读证据和最窄验证建议，最终实施身份与验证由父确认。

已有真实语义查询：`acpUsageQueryReady` 引用只有声明和该单测调用；`writeAcpInstallCapture` 只有自身声明。结合完整夹具正文、单测正文和仓库消费者核查，才作此判断。理由不是“测试没有直接导入生产”，而是整个被测验收入口已退役，剩余测试只保护它自己。

最小修法（共享现场已实施删除）：父在源测试权限内删除这两文件；无需搬出 helper、保留旧接口或新造替代测试。先核对无导入/调用残留，再由统一窗口执行现役 ACP auth/usage/install VM 与组件回归；已有 `acp_auth_duplicate_input_test`、`acp_install_draft_test`、`acp_auth_test`、`acp_usage_metrics_test` 分别属于真实 VM/交互边界，应按最终差异选择，不能删除这些测试来凑数量。此项基线已存在，不列作本轮引入的回归。

### T02：生命周期文件中有一项纯夹具字段回读，建议删单例

`test/unit/test_app_lifecycle_test.dart` 首项创建 `ChatGptSceneTransport`，调用其 `loadAccountCatalog` 后检查注入的 OpenAI 模板为 subscription。这只重读 `test/support/chatgpt_scene_transport.dart` 的静态测试配置，不触发 ChatGPT 编辑/登录/计费产品路径。建议删除这一个 test；后两项未监听 stream owner 关闭、app/root 兄弟隔离继续保留。文件整体有真实资源契约价值，不能整份删除。

最窄验证是原生命周期文件两项真实关闭场景，以及现役 `chatgpt_auth_test.dart` 的订阅账号行为。未取得本轮运行证据。

### T03：计划卡测试的键盘覆盖声明与操作不符，应补操作或收窄名称

`test/ui/plan_summary_card_test.dart` 首个 test 名称为 “whole plan card toggles one reader with keyboard and expanded semantics”，正文只对标题、图标和动作文字执行三次 `tester.tap`。它实际保护单一点击目标、展开 semantics 与后续中英文窄窗几何，仍应保留；当前没有键盘事件，不能声称键盘回归已覆盖。

最小修法：在该原例给真实卡片焦点，发送 Enter/Space 并检查 toggles 与 expanded semantics；若本轮没有键盘保护目标，至少删除名称中的 keyboard。前者的最窄行为验证就是此文件首例，后者只需统一检查；不新增平行 fake。

### T04：时间线夹具保留无效位置输入，建议移除脚手架

`test/support/display_fixtures.dart:43` 的 `TimelineFixtureBatch.from` 只有构造/保存。全文两条消费链分别是 `applyFixtureUpdate`（只交付 blocks/placement）与 `historyFixturePage`（读取 throughOrder/before），均不读取 from。`completion_run_controller_test.dart` 给多个 batch 传 `from: 3`，并不会触发任何生产位置检查；原测试真实的行顺序、duplicate拒绝和异步失败保留意图断言仍有效。

最小修法：删除字段、构造参数、displayBatch透传及对应 from 实参，不删 controller 行为测试。相邻 `completion_run_view_test.dart` 的 `_runTitle(tester, int count)` 从不读 count，也可删除形参和传值，避免 100000 这个字面量暗示实际装配了十万个成员。没有据此报告生产数量缺陷。最窄验证为这两个现役文件。LSP references 本次超时，未将超时当零引用；此结论来自全文消费路径及 scoped 文本核对。

### T05：真实登录验收的额度刷新缺少本次调用证据，应增强原等待

`integration_test/acp_real_login_test.dart` 点击 queryUsage 后只等精确账号/connection 为 Verified 且 usage 非空；`chatgpt_real_login_test.dart` 只等精确账号 phase 为 succeeded。两者均未记住点击前的修订、checkedAt 或本次操作。重启旅程可能已有已保存/已观察额度，这种旧成功不能证明新刷新成功。

真实链为 `AcpAccountViewModel.queryUsage` → `AcpServiceImpl.queryUsage` → `_startAuth`：VM 只发意图，Client 保留旧 canonical，在 await 详情及 port 回执后才应用新的 auth 帧，不同步清空旧 usage。因此从断言本身不能排除命令未派发、迟到或失败而先读旧成功。此处是确认的证明缺口，尚未实际运行复现假通过；不是声称现役 provider 已失败。

最小修法：在点击前保存该账号/连接的 canonical 修订与本次动作的观察位置；等待本次新 operation 被接纳并达到完成，或等待对应修订确实推进且成功额度属于该次刷新，再检查原 UI/额度。保留账号/connection身份和错误传播。优先在已有受控 auth/ChatGPT 测试里加入“先有旧成功、刷新延迟/失败不得提前通过”的场景；真实供应商旅程仅在已有明确授权时验证，普通统一回归不为本建议额外触发登录或付费请求。

### T06：原生窗口夹具仍保留自写 C allocator，已有 ffi 可直接复用

`integration_test/support/window_control.dart` 的 `_cString`、`_freeCString`、`_cLibraries` 及 malloc/free typedefs 自行遍历 process/libc 符号来分配 display 字符串。注释称 package:ffi 未声明，但当前 `code/anywork/pubspec.yaml` 已直接声明 ffi 开发依赖，同库 Windows part 已使用 `ffi.using`。这一旧替代实现的前提失效；分配与释放分别独立寻找库，也没有把 allocator身份绑定在返回句柄上。

最小修法：复用已导入的 `ffi.calloc`（或包内官方UTF-8分配帮助），用同一个 allocator分配与finally释放，删除这三个helper及不再需要的malloc/free typedefs；保留 Xlib lookup、PID窗口定位、失败可见性与实际几何验证。无需新增依赖或手写另一层allocator。现有 Linux/Windows integration窗口路径是最窄真实验证；本组未运行原生GUI，也不把只读FFI检查外推为跨平台通过。

### T07：load-only 把成员关闭误当共享 SDK 关闭，建议修正错误断言

`integration_test/support/agy_load_only.dart:395` 要求 `close.localComplete && close.sdkFinished` 为 true；同目录 `agy_phase_runner.dart:316` 正确区分 localComplete=true 与 sdkFinished=false，并在应用退出后独立检查进程回收。load-only 的错误断言会把符合当前合同的正常成员关闭记为 cleanup error，导致整个 load 证据失败。

证据已追到真实实现：Dart LSP 将 load-only 的 `owner.closeMember()` 定位到 `code/anywork_client/lib/src/acp_sessions/data/acp_conversation_session.dart:858`，方法直接交 `AcpSessionClient`/FRB `closeAcpSession`，不追加关闭账号 SDK。Rust `code/pl-acp/src/session.rs:1074` 的成员 driver exit 设置 sdk_finished=false；`code/anywork/rust/src/api/studio/handlers/acp_business/feed.rs:293` 与 `:359` 的真实 bridge 回归也要求成员 local_complete 且非 sdk_finished，随后确认共享账号进程仍在，最终由 fixture finish 回收。没有 Rust LSP 配置或运行；Rust部分结论来自所列原实现/回归源码。

最小修法：将 load-only 原断言拆为 `localComplete` 为 true、`sdkFinished` 为 false，与现役成员合同一致；保留 timeout/unfinished/ownerFailures/sdkError/driverError 检查，继续在 harness shutdown 后执行 `processes.verifyClosed`。不为让错误测试通过而提前杀共享 SDK。可先复用现有 bridge 成员关闭契约回归；真实 load-only 旅程仍须专门 live 授权，本轮未执行。此问题基线已存在，当前生产实现没有因本组改动发生变化。

### T08：工作流图用例把互斥写在测试回调中，应接回生产状态 owner

`test/ui/workflow_graph_and_mode_selector_test.dart:166` 声称 Workflow 与 Todo 互斥，但 `:227` 回调自己翻转 showWorkflow 并把 showTodo 置 false，sidebarBuilder 的选择也由这两测试变量决定。实际路径是 `lib/src/features/shell/agent_workspace_pane.dart:374` / `acp_workspace_connector.dart:219` → `ConversationSidebarState.togglePanel`。Dart 真实定义查询已将前者定位到 `conversation_sidebar_state.dart:80`；生产通过单一 activeKind 切换面板，该用例未调用它。

最小修法：保留图节点/当前态/纵向布局等组件断言，将同例局部双布尔改为生产 ConversationSidebarState 驱动，或迁入已有真实workspace测试点击 Workflow/Todo，并核对只显示所选面板及折叠。若只保留纯图组件场景，收窄名称的互斥声明。不能把当前结果当生产互斥已回归，也没有生产互斥缺陷证据。该文件相对基线无差异，是既有证明缺口。

### T09：取消问答的窄窗用例没有装配长答案，应补原场景或收窄名称

`test/ui/timeline_question_receipt_test.dart:240` 名称声称 narrow long answers do not overflow，正文只挂固定短文本的 cancelled receipt，且不展开问答。它确实保护窄窗取消标签与只读性；长答案控件没有进入布局，末尾 takeException 不能证明长答案几何。

最小修法：在原receipt输入增加可控长公开答案，展开实际回执，在320px场景核对答案可读及无overflow，保留secret缺席和取消只读断言；或把名称收窄为窄窗取消回执只读。最窄验证为该原用例，不新增平行renderer。文件相对基线无差异；本轮未运行或复现实际overflow。

另有同类名称清理：`test/ui/acp_usage_metrics_test.dart:402` 名称包含 deletion，正文实际到重新check/login为Verified结束，没有删除动作。建议删名称中的 deletion，保留跨导航/重复登录/取消回归；现役 `acp_auth_test.dart` 已有真实删除旅程，无需为名称再复制一组。`acp_workspace_lifecycle_test.dart:391` 的空 `if (index == 0) {}` 可直接删除，不影响四项权限选项测试。

## 局部脚手架与名称清理

以下均只需在原测试内处理，不能据此删除整个行为场景；本轮未运行，也未确认生产缺陷。

- `test/ui/composer_button_matrix_test.dart:544` 名称称停止与继续被拒绝“不清草稿”，但两次发起前都主动清空文本，末尾也没有保稿断言。可删名称的“不清草稿”；同文件后例已真实验证停止失败保留在途新稿。若要补继续失败保稿，在点击继续发出后、响应失败前输入新稿，再核对保留，不能保留非空稿却误触发送按钮。最窄只验证原受控continue场景。
- 同文件 `:1424` 与 `:1430` 连续检查同一个 Stopping finder，可去一份；保留卸载前后和超16秒的独立检查。
- `test/ui/timeline_immutable_live_status_test.dart:931` 刚保存settledReplyMessage就立即identical回读，属局部自明断言，可去掉这一条；`:999` 下一Turn后的身份断言有实际保护价值。展开History的等待含“正文出现或已展开”，当前只证明展开态及加载样式，不夸大为最终成员正文可达验证。
- `test/ui/app_route_draft_test.dart:267` 的hiddenFrames和hiddenAcks都取同一个watchCalls，后续两次相同断言可合并。watch计数不能被命名为独立ACK证据；其余隐藏页面资格与重新baseline断言保留。

新增16文件的归属与状态见ledger。最新owner资料还明确：settings Bot菜单修后已在30项联合通过；shell测试纳入最终完整UI；workflow converters已有30项联合通过；浏览器 `test/web/cross_cache_lifecycle_test.dart` 已3项通过，官方快速卸载6轮无缓存异常。上述均为owner记录，本组没有重跑或将其标作通过。

## 已核实的保留边界

- `test_app_lifecycle`、`test_resource_owners` 与 `frb_test_lifecycle` 把资源接入真实 ClientScope，关闭报告必须 complete；FRB mock 保留到原生资源已收束。它们被多份真实 Client/VM/UI 回归间接消费，不能按 import 图误报为零覆盖。
- `AcpComponentHarness` 仅提供帧和外部端口，生产 AppGraph、Client、Riverpod 与组件仍真实装配。instance/run、connection/query revision 及精确取消身份在所读用例中有正反例。
- `display_fixtures.historyFixturePage` 是测试输入编码器：从显式 DisplayBlock 合成事件与折叠标志，不证明后端 WorkRange 切分。相应 UI/reader 测试仍保护前端读入、身份和迟到页拒绝；不得把这一限制写成测试全无效。
- `RecordingDemoTransport` 包装真实 Demo reader、保留 close Future、精确 gate 和 late frame。其空 `_FixtureCurrentBodyWatch.close` 只支持输入流场景，不能拿来证明原生 watch 自身收束；实际关闭回归由有状态 reader/watch 与原生验收分别承担。
- `test_statistics_feed` 是显式空数据装配端口；connection上仅写的 `_closed` Completer 已由共享现场移除。scope上的同名bool被 `_ensureOpen` 实际读取，必须保留，不能连同误删。虽然 connection.close 不直接等待 `_events.close`，真实 StatisticsRepository 的 `_retireAttempt` 在其后继续 join `attempt.pump`，目前没有证据把它报告为产品关闭缺陷，也不以空夹具证明真实 feed ACK/持久化。
- `timeline_current_terminal_projection_test` 的 raw-body case 证明 connector 选择 render 入口，未验证 body owner 的 I/O；同文件真实 overlay/冻结/外run拒绝断言有独立意义。
- `wait_presentation_integration_test` 已全文补读：确实装配 TimelineToolItemView，waiting 到三终态保留原 task 身份和展开状态，诊断复制走官方 SelectableText；旧 TimelineWaitPanel 的迁移已完成，不重复提删除。
- `macos_terminal_test` 使用真实 `/bin/sh` 捕获生成命令参数，保护特殊字符引用；不是实际终端/SSH/AppleScript验收，Windows明确skip。不能因文件名macOS而否定Linux上执行shell参数验证的价值。

## 验证边界与交接

本轮只有读取、LSP 语义引用和笔记写入。owner 记录的局部通过独立列出，没有执行或复跑。父代理在稳定窗口统一做全应用 analyze、UI、必要 unit 与原生验收；父已报告统一生成成功，本组不把此前临时编译不一致记为发现。

基线全文审读已完成；九项T编号保留发现时的具体证据与最窄修法。主任务已落实清理并统一收束验证，见篇首链接；本组没有用源修改或测试执行代替只读结论。新增文件的owner状态独立列示，不影响189个基线全文记录。
