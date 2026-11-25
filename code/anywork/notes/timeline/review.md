# M05 / M15 / M16 时间线质量清理审读记录

本文记录 presentation、conversation/timeline 与对应预览的逐文件判断。Client、domain 与 shared 的事实源和所有权边界保持原有归属。

已清点基线手写 Dart：presentation 27、timeline 132、timeline previews 10，共 169。生成文件不计入审读。以下按文件记录完整阅读，搜索和统计只用于引用核查，不算审读。

依据 design/25 与 design/26，保留 History 固定 cut 与后端 WorkRange、Current 有界 overlay、唯一串行 Flyer apply、reader generation、cancel/join 和失败清理责任。

## 已完整审读的 presentation

路径均以 `code/anywork/lib/src/presentation/` 为前缀。已清点、已审读；处理与验证分别记录。

| 文件 | 审读判断与处理 |
| --- | --- |
| providers/account_domains.dart | 账号、模型、用量、ACP 观察独立；选模显式持有目录需求，不从账号列表强制加载模型。保留。 |
| providers/account_operation_observation.dart | 只按返回 OperationId 借用观察，不引入第二 MutationBoard。保留。 |
| providers/attachment_drafts.dart | 借用 Client 跨路由草稿，销毁只取消观察。保留生成式入口。 |
| providers/bootstrap_store.dart | bootstrap 同步快照观察，保留。 |
| providers/bots_store.dart | bots/query/send 三个独立源，不能因形式重复合并领域。保留。 |
| providers/client_provider.dart | AppGraph 单 Client 装配，保留。 |
| providers/composer_draft_controller.dart | 等待规范会话身份，existingComposer 不从构建创建业务 owner；缺席需求失败单独呈现。保留。 |
| providers/lsp_store.dart | LSP 只读主题适配，保留。 |
| providers/mcp_store.dart | scope catalog 与 thread demand 失败归属不同，不能模板化为同一个 provider。保留。 |
| providers/mode_catalog_store.dart | 目录只读观察，保留。 |
| providers/mode_editor_store.dart | 编辑草稿观察借用；已将注释误称 account 修正为 provider。 |
| providers/observe_client.dart | watchLatest 同步初值、异常撤销已建立观察、Ref 只拥有观察；需求失败只读。保留。已将注释 account 修正为 provider。 |
| providers/persistence_store.dart | 持久化状态观察，保留。 |
| providers/project_store.dart | watch Client 身份并观察 project，保留。 |
| providers/recovery_store.dart | 恢复主题只读，保留。 |
| providers/selection_store.dart | Client 选择意图唯一来源，保留。 |
| providers/session_costs_store.dart | rootThread 成本需求的失败归属和空闲态，保留。 |
| providers/settings_store.dart | Client 设置快照只读，保留。 |
| providers/skills_store.dart | workspace 技能需求及 selection-topic 失败归属，保留。 |
| providers/start_session_controller.dart | Client 新会话草稿与既有导出，保留。 |
| providers/studio_update_controller.dart | 更新请求与操作跨路由存活；request provider 直接返回 observeClient 同步初值。controller 必须观察 source 后返回 owner.state，保留禁用更新和无快照时的 Client 投影；source 的 CanonicalClockState 不能替代 UpdaterStateSnapshot。 |
| providers/thread_directory_store.dart | metadata demand 与 display rebuild 分离，保留。 |
| providers/thread_lsp_store.dart | 页面持有 demand，provider 仅借用现有 owner，保留。 |
| providers/thread_session_store.dart | 可见会话 registry 变化驱动重读，缺席不创建会话。保留。 |
| providers/updater_store.dart | canonical updater 主题与 update operation 是不同事实，保留。 |
| providers/use_client_resource.dart | scope 负责异步清理并保留失败，Ref 只 requestClose。保留。 |
| view_models/timeline_session_owner.dart | 全文 2562 行已读。会话接纳、唯一串行 apply、display lease、Current atoms 和 reader cleanup 相互有私有生命周期约束，不机械拆成 forwarding owner。已把独立 DisplayMembers 实现移至 timeline/view_models/history_work_range_members.dart；同步迁移唯一外部测试 import，不保留旧导出。删除未参与 partition 的 ownerId 参数，以及仅被空列表调用的 Current input 参数。 |

## 已完整审读的工具层

路径均以 `code/anywork/lib/src/features/conversation/timeline/tools/` 为前缀。每个 item 均完整阅读了 matcher、body policy、输入/输出投影、row summary 与特殊交互；下表不是用注册清单替代源码阅读。保留各工具独立适配器的契约，不把它们合并成配置表。

| 文件 | 审读判断与处理 |
| --- | --- |
| items/acp/acp_tool_details_scope.dart | 通过纯数据作用域注入协议附加内容，避免依赖反转。保留。 |
| items/acp/acp_tool_item.dart | ACP plain/raw 输出不同于 Native 严格 JSON，保留独立适配。路径复制改用 TimelineCopyPathButton，由组件承担原有 1600ms 反馈和 timer 释放，原位置保留 2px padding。 |
| items/collaboration/send_message_tool_item.dart | 消息语义投影；重复动词选择已复用 toolLifecycleVerb。 |
| items/collaboration/spawn_agent_tool_item.dart | messageAccepted 接纳判定独立保留；重复动词选择已复用。 |
| items/command/exec_tool_item.dart | command 语义、真实完成耗时、stdout/stderr 独立保留；重复动词选择已复用。 |
| items/command/write_stdin_tool_item.dart | stdin 与 inputReceipt 投影保留；重复动词选择已复用。 |
| items/filesystem/apply_patch_tool_item.dart | freeform 参数、输入窗口和 patch diff 专有路径保留；重复动词选择已复用。 |
| items/filesystem/copy_path_tool_item.dart | 复用已有 transfer 参数校验与 from→to 目标；动词选择已复用。 |
| items/filesystem/create_directory_tool_item.dart | 必填路径与成功省略输出保留；动词选择已复用。 |
| items/filesystem/delete_path_tool_item.dart | 显式三种删除模式校验保留；动词选择已复用。 |
| items/filesystem/move_path_tool_item.dart | 复用 transfer 支持，独立图标/文案保留；动词选择已复用。 |
| items/filesystem/stat_path_tool_item.dart | exists/type/len/readonly/时间投影及 diagnostic fallback 保留；动词选择已复用。 |
| items/filesystem/write_file_tool_item.dart | create/overwrite/append 与正文窗口保留；动词选择已复用。 |
| items/generic/generic_tool_item.dart | 未知工具 generic@1 中性回退必须保留。 |
| items/lsp/lsp_capabilities_tool_item.dart | 有界能力解析、无输出语义与专用 LSP 视图保留。 |
| items/lsp/lsp_query_tool_item.dart | 按 operation 选择文案、文件坐标与 query 目标不同，暂保留专用分支。 |
| items/lsp/lsp_status_tool_item.dart | 配置/初始化/活动状态独立呈现，保留。 |
| items/media/show_files_tool_item.dart | succeeded/带 artifacts 的 failed 独立媒体路由，保留。 |
| items/media/view_image_tool_item.dart | 专用 statusTitle、driver key 与路径保留；普通动词选择已复用。 |
| items/plan/plan_current_tool_item.dart | 查询无额外输入，复用 plan result，保留。 |
| items/plan/plan_history_tool_item.dart | 历史查询独立契约，保留。 |
| items/plan/plan_next_tool_item.dart | 下一操作查询独立契约，保留。 |
| items/plan/plan_restart_tool_item.dart | reason 与 plan result 保留；动词选择已复用。 |
| items/plan/plan_submit_tool_item.dart | 必填 plan 内容保留；动词选择已复用。 |
| items/plan/plan_transition_tool_item.dart | target/force/reason/content 明确投影，保留；动词选择已复用。 |
| items/session_note/apply_session_note_patch_tool_item.dart | 笔记 patch 与固定语义目标保留；动词选择已复用。 |
| items/session_note/read_session_note_tool_item.dart | 行号/正文语义投影保留；动词选择已复用。 |
| items/session_note/search_session_note_tool_item.dart | query 和匹配内容白名单投影保留；动词选择已复用。 |
| items/session_note/write_session_note_tool_item.dart | 必填 content 和固定笔记目标保留；动词选择已复用。 |
| items/wait/sleep_tool_item.dart | timer 时长与携带 wait 的无契约 atom matcher 保留；动词选择已复用。 |
| items/wait/wait_tool_item.dart | tasks/timedOut/messagesReady 与 lazy diagnostics 保留；动词选择已复用。 |
| items/web/deepseek_web_fetch_tool_item.dart | URL 与文本结果保留；动词选择已复用。 |
| items/web/deepseek_web_search_tool_item.dart | query 数组、文本结果与 artifacts 链接保留；动词选择已复用。 |
| items/web/web_search_tool_item.dart | find/open/search 三类动词和各命令投影不同，保留专用分支。 |
| items/workflow/workflow_current_tool_item.dart | current 查询无运行态时的语义保留。 |
| items/workflow/workflow_graph_tool_item.dart | graph 查询独立契约，保留。 |
| items/workflow/workflow_history_tool_item.dart | history 查询独立契约，保留。 |
| items/workflow/workflow_next_tool_item.dart | next 查询独立契约，保留。 |
| items/workflow/workflow_restart_tool_item.dart | accepted 接纳投影与 reason 保留；动词选择已复用。 |
| items/workflow/workflow_transition_tool_item.dart | completion/evidence 校验与接纳投影保留；动词选择已复用。 |
| support/agent_result_support.dart | 合作结果白名单防止内部 task ID 外泄，保留。 |
| support/execution_result_support.dart | stream 原始诊断、exitCode、signal 和 inputReceipt 语义保留。 |
| support/plan_result_support.dart | plan enum 本地化和已知字段投影，保留。 |
| support/structured_tool_adapter.dart | 集中严格解析、接纳与有界正文呈现，已是公共职责；保留。 |
| support/task_state_values_support.dart | 仅递归已知状态域，不任意本地化用户文本，保留。 |
| support/tool_acceptance_controller.dart | 完整 prefix window 接纳与 callback epoch 退役，保留。 |
| support/tool_detail_panel.dart | 选择边界、语义字段排版复用，保留。 |
| support/tool_detail_values.dart | 严格结构解析、白名单递归、跨平台 basename 与附件格式职责，保留。 |
| support/tool_status_labels.dart | 已增加 toolLifecycleVerb，统一 25 处完全同构的 running/failed/succeeded 判定；queued/stopped/unknown 仍返回 null 走原 statusTitle。 |
| support/transfer_path_support.dart | copy/move 真正同构语义已经共享，保留。 |
| support/wait_presentation_support.dart | wait/sleep summary 与诊断延迟展开共享，保留。 |
| support/web_artifacts_support.dart | 最多 6 条去重 HTTP(S) 来源，保留。 |
| support/workflow_result_support.dart | workflow 无 run、enum 本地化、接纳拒绝原因保留。 |
| tool_item_adapter.dart | matcher、controller epoch、策略与适配接口保留；LSP 引用确认 hasStandardChildren 只有声明，已删除。 |
| tool_item_registry.dart | exactContract 唯一性校验、顺序 matcher 与 generic fallback 保留。 |
| tool_item_view.dart | 单一工具展开路径，动态 icon、接纳、generation 与 group 资格保护保留。 |

## 覆盖与回归入口

初始范围的 presentation 27、timeline 132、对应 preview 10，共 169 个手写 Dart 已全部全文审读。其余逐文件判断见 state-and-views.md 与 previews.md，完整路径、审读、处理与验证状态见 review-ledger.tsv。新增实现和相关回归测试另列于 ledger。

主要回归入口包括 work_group_event_folder_test.dart（固定 cut 与折叠）、timeline_message_controller_test.dart（串行接纳窗口）、timeline_history_projection_test.dart（损坏字段的单行诊断）、wait_presentation_integration_test.dart（等待终态身份、展开、诊断复制），以及 timeline_tool_registry / acceptance_epoch / preview 的工具适配验证。静态诊断、局部用例与完整产品验收各自具有不同覆盖范围；具体运行记录和临时内容摘要归本线程 artifacts，不作为长期源码笔记。
