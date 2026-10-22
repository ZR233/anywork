# v4 写入所有权与依赖合同（尚未派发）

本表由 root 决定；它不替代各域完整接口。只有共享合同、Thread／产品wire、领域动作、VM字段
和验收矩阵都齐全后才按此表释放任务。每份派发另附实际输入hash和完整批准计划。

## 1. 调度与提交规则

工程要求代码提交前执行全门禁，而用户要求全手写完成前不测试、期间不提交阶段实现。
因此本轮大规模实现优先采用**directory executor**，root最终统一验证／提交；不让worktree
执行者为了交付补丁提前创建未经门禁的实现commit。此前同步worktree只重放已有文档提交，
现场保留到最终验收后回收，不混同为后续实现分支。

共享D0先完成最小最终形状（实际文件/公共出口），U0可在互斥UI路径并行；其余上下游在
**全套接口已经冻结**且必须引用的基础文件存在后并行，不等编译/测试绿色。当前本表仍不
满足全套准入，不以这条调度规则偷跑缺少接口的任务。

全部目录任务禁止stage/commit/push、全仓format、生成和测试。每个完成任务立即fresh静态
逻辑审查，其他未迁消费者或过期生成物不单独阻塞；真实本任务逻辑/接口错误必须修复。

## 2. 固定写区

下表中的旧文件清除是迁移责任的一部分；其他任务只能读取该源。若一个旧大文件含多个
领域，各域只在自己的新目录写目标实现，C在所有调用方迁完后删除旧文件，不并写旧大文件。

| Owner | 独占最终写区 | 旧源迁移／删除责任 | 禁止顺带修改 |
| --- | --- | --- | --- |
| R | `code/pl-protocol`、`code/pl-studio-runtime`、`code/pl-studio-server`、`code/anywork/rust/src/api` 的本计划相关手写文件 | 五域/产品feed、query/CAS/receipt、来源观察/真实join、Rust HTTP/SSE/OpenAPI、同范围必要契约测试 | 生成Rust、Dart、core/model/tool无关逻辑、Cargo全局依赖、design |
| D0 | SDK `lib/src/resources`、`lib/src/operations`；所有SDK根`lib/*.dart`最终公共入口；SDK pubspec/build/analysis输入（仅实际需要项） | `src/contracts`、`src/lifecycle`、`src/observation`、`src/commands`迁入共享新域，关闭旧可写公开面 | 领域私有实现、Flutter、FRB、测试、无关依赖升级 |
| D1 | SDK `lib/src/conversation`、`lib/src/drafts` | 会话/内容/草稿/附件/interaction/冻结提交；不写旧studio大facade，只复制所需逻辑后留C删 | 其它数据域、根barrel、FRB、Flutter呈现、测试 |
| D2 | SDK `lib/src/configuration`、`lib/src/models`、`lib/src/account_usage`、`lib/src/modes` 的新领域布局 | 配置/CAS、模型目录/查询、额度、Mode命令；`src/models`现有平铺文件需逐类迁移，最终本域只留models实际职责 | D1/D3、共享barrel、模式呈现undo/graph、测试 |
| D3 | SDK `lib/src/workspace`、`lib/src/updates`；resources中另行划定的产品资源子目录 | 项目/Thread目录/唯一目标协调、MCP/LSP/skills/recovery/persistence/SSH资源、显式StartupRepository与更新owner；全应用退出协调仅U3 | D0共享资源文件、Flutter app、根barrel、测试 |
| A | Flutter `lib/src/infrastructure/frb`手写adapter/demo；两包测试`test/**/support`中明确列出的共享fake | typed ports映射、原生handle/stream责任、demo和公共fake | Rust wire、generated、VM/UI、嵌入测试文件里的fake（由C迁移） |
| U0 | Flutter `lib/src/ui`、`app/theme`、纯视觉l10n输入；shared下明确列出的纯视觉源 | 共享selector/status/确认/附件metadata等纯UI，保原视觉/主题；不新建业务owner | app装配/生命周期、业务VM、diagnostics、FRB |
| U1 | Flutter `features/settings`；原`features/update`的设置呈现部分 | Settings全部真VM/Freezed/Smart-Dumb、Mode单一编辑会话/64undo、账号/额度/SSH等 | D2/D3、app/providers、U0视觉源、测试 |
| U2 | Flutter `features/conversation`；旧`features/interaction,timeline,status,todo`；`presentation/view_models` | Conversation所有真VM及展示coordinator/UI-only binding，迁移并删除旧功能目录/part | SDK数据层、app装配、U0共享视觉、测试 |
| U3 | Flutter `app`除theme、`features/workspace`、旧`features/shell`、旧`presentation/providers` | composition/provider binding/bootstrap/routing/窗口退出、workspace/sidebar、删除旧只读provider链与shell parts | U0theme、各feature内部VM、SDK/data、测试 |
| C | 两包测试（排除A共享support）、Flutter test_driver、diagnostics、旧shared的Driver文件、xtask/CI/acceptance相关消费者、源码计数脚本 | 全调用方测试/Driver/AST迁移；旧SDK `src/studio`／`src/application`／`src/chat`以及无归属兼容入口最终清除；skill_activity新helper调用迁移 | 其它owner仍在写的生产范围、generated、design、发布/tag |
| root | `design`、工程合同/README/验收与对比报告、最终统一生成/依赖锁更新/集成Git | 完整接口与跨任务决定、最终验证、PR/CI、资源回收 | 不代替执行者静默改已审生产范围，不混提交未完成工作 |

该表明确两处需要在逐文件manifest中消除的父子目录重叠：

1. D0 resources只拥有共享机制的`domain`/`data`文件；D3的MCP/LSP/skills/recovery/persistence/SSH
   产品资源分别放`resources/{mcp,lsp,skills,recovery,persistence,remote}`。D3不得写D0文件。
2. 旧SDK `src/models`混合多域。D2只写新的`src/models/domain`和`src/models/data`；旧35个平铺
   文件统一由C在新域与消费者完成后删除，逐文件迁移责任见§6。任何领域执行者不得编辑这些
   旧源；从其已冻结内容移植必要语义到自己新目录，不把它们继续留作转发或公共依赖。

公共根barrel/manifest仅D0写，其他域只报所需最终导出清单；D0不增加兼容出口来维持中间编译。
U3只从最终feature公共入口装配，不导入另一feature私有VM来修补接口空白。

## 3. 旧共享源的确定归属

- `shared/studio_driver_{keys,key_values,projection,state}.dart`：C迁入diagnostics相应位置；保留
  Driver key与四个connection error字段语义，不带异常正文或凭据。
- `shared/account_brand.dart`、`host_app_logo.dart`、`model_route_selector.dart`、`studio_badges.dart`、
  `studio_chrome.dart`、`studio_code_block.dart`、`studio_hover_detail.dart`、`studio_loading.dart`、
  `studio_menu_label.dart`、`studio_messages.dart`、`studio_panel.dart`：U0，目标ui分类目录。
- `shared/recovery_check_status.dart`：U3，与app recovery/退出呈现同步；如其纯视觉部分抽取需root
  明确交U0，不能两方直接编辑。
- `shared/typed_json.dart`：C清理剩余真实opaque/tool-argument/authoring消费者后决定删除；
  不能用此旧helper实现新的typed实时协议兼容入口。
- `presentation/view_models/timeline_session_owner.dart`：U2独占，不能由A顺带修；接口问题root协调。
- `features/status/session_selectors.dart`：U2迁移功能connector，U0只写新的纯selector，旧文件由U2删。
- `features/todo/todo_panel.dart`：U2，不因旧目录没有列在最初功能入口就遗漏。
- `code/anywork/lib/src/l10n/studio_l10n.dart`及`lib/l10n/app_{en,zh}.arb`：U0；helper当前仍
  导入旧models桶，必须改为实际需要的领域公共值。生成的app_localizations仅root。
- `code/anywork_client/test/support/timeline_transport.dart`和
  `code/anywork/test/client/support/recording_demo_transport.dart`：A独占；
  `code/anywork/test/client/support/pump_client_future.dart`：C，不是adapter fake。
- 旧`presentation/providers`所有手写文件：U3统一移除；U1/U2只读取其旧业务语义并写新VM。
  不按当前provider功能名把旧源分给多个writer。生成part由root统一清理。
- SDK所有根barrel，包括旧`anywork_client.dart`/`studio_client.dart`/`studio_ports.dart`的
  删除均归D0，C只迁消费者并核残留。`models.dart`最终只导出models域，不复用为旧巨桶。

## 4. 本轮逻辑问题归属与最终封闭

- U2负责候选Session/binding/latest epoch及全部consumer/candidate join；D1只提供原attempt查询
  能力，不把展示控制器拉进纯Dart。
- R/D0/D1/A共同遵守已定CloseIssue recovery与retryClose签名，root统一契约；实现各自互斥。
- A负责共享fake late-claim，C负责测试文件中其余fake迁移，二者不能并写同一测试文件。
- C修skill_activity旧helper引用，禁止兼容alias；它不阻塞此前同步保全，但最终不能残留。
- 全部任务结束后C做旧名/旧路径/手写part/依赖扫描；发现生产逻辑问题返回原owner，不由C
  随手改其他模块。root最终跨任务审查并统一验证，不把各局部批准相加冒充整体通过。

## 5. 派发前仍必须完成

- [x] 当前源file身份manifest与平铺models/UI domain唯一owner；见§6–8。新公共文件接口仍需补齐。
- [ ] 每个公共新文件的接口/fields/variant/错误/版本/预算/输入约束完整，无“执行时自行设计”。
- [ ] 每个consumer/test/fake/Driver文件只有一个writer，跨范围引用按冻结接口协调。
- [ ] 全部生成文件与锁文件明确由root最终统一处理，不能漏进执行者写列表。

所有源码探索都只读；当前没有开始任何一组新手写实现。

## 6. SDK旧平铺模型：35文件完整迁移表

本节路径均相对`code/anywork_client/lib/src/models/`。每个旧文件writer/删除者均为**C**；
下表“新目标责任”是领域实现责任，不是旧文件写授权。各新领域用Freezed保存原合法值，
runtime owner不因同处models文件而值对象化。跨域共享类型只有一个定义及canonical出口。

| 旧文件 | 新目标责任 |
| --- | --- |
| account_models.dart | D2：configuration账号desired/能力值；models目录/模型/模板；account_usage额度，真实分开 |
| agent_models.dart | D3 workspace：运行期Agent目录及状态，不混同Profiles配置 |
| agent_profile_models.dart | D2 configuration：Profile值与draft命令输入；workspace赋值快照只在实际消费者域精确引用 |
| attachment_models.dart | D1 drafts：附件准入、引用、输入；ledger/permit仍为运行时owner |
| collection_equality.dart | C删除；Freezed值相等替代原模型手写比较，不引入Flutter依赖或新公共util桶 |
| collection_extensions.dart | C删除；项目目标Dart的Iterable.firstOrNull已有标准能力 |
| command_receipts.dart | D0 operations共同receipt；D1/D2/D3各自typed命令payload，不能另造同构receipt |
| composer_models.dart | D1 drafts/conversation：草稿、冻结发送与结果；D3消费其值/命令，不复制Board或发送owner |
| conversation_activity_models.dart | D1 conversation活动详情；UI格式化留U2 |
| failure_models.dart | D0 resources共享typed失败；命令结果归operations，不拆成多份错误enum |
| interaction_models.dart | D1 conversation完整Interaction/回应值；U2只拥有编辑呈现 |
| mode_editor_models.dart | D2 modes文档/校验/预演；U1拥有唯一Mode编辑会话/undo，不留SDK编辑owner |
| model_catalog.dart | D2 models目录来源、错误、origin与warning |
| persistence_models.dart | D3 resources/persistence定义持久化值；D1 Thread execution引用同一ThreadStorage值，不再定义第二份 |
| product_topic_models.dart | 各领域自己的typed frame/基线；D0只定义资源共同能力，不复制旧万能topic union |
| recovery_models.dart | D3 resources/recovery全部issue、工作树预览和恢复值 |
| remote_models.dart | D3 resources/remote全部SSH/认证/目录值；typed错误详情不从message猜 |
| runtime_models.dart | D2 account_usage统计/费用；D1 conversation Thread usage/route/Plan/Workflow；原按币种展示函数迁U0 |
| settings_models.dart | D2 configuration所有desired设置、route及配置投影；MCP运行态值归D3 resources/mcp，不混可写配置 |
| settings_snapshot_projection.dart | D2分别实现config与catalog reducer；旧双时钟聚合删除，不包装为两个假Repository |
| startup_models.dart | D3 workspace显式启动值/StartupRepository与startup typed read；U3只装配/呈现，不把全局Recovery审计混为启动快照 |
| studio_commands.dart | D1会话/草稿；D2设置/Mode；D3目录/资源/SSH；D0只负责共同操作机制 |
| studio_enums.dart | D2 configuration PermissionMode、modes ThreadModeId；D3 workspace ThreadWorkspaceMode；D1 context/timeline/interaction；同步观察状态归D0 resources |
| studio_shutdown_models.dart | D0 resources共同ShutdownIssue/CloseReport/SourceStateError；D3 workspace生命周期port与退出报告、updates安装结果；U3唯一全应用退出协调器 |
| studio_state_snapshots.dart | D0 resources只读观察状态；D2/D3各自完整产品值；旧全状态桶和mutation facade删除 |
| thread_activity_models.dart | D1 conversation活动与细节；ThreadStorage引用D3唯一值 |
| thread_directory_models.dart | D3 workspace项目/Thread目录/页/过滤；退出进度另归D3 resources，不留混合文件 |
| thread_models.dart | D1 conversation typed内容与字段变化 |
| thread_preparation_models.dart | D1 drafts的NewThreadPreparation/进度值与冻结发送/未知结果；D3只经原selection generation接收已创建结果，不另建submission owner |
| thread_wait_models.dart | D1 conversation完整Wait typed值 |
| timeline_models.dart | D1 conversation内容/技能激活/工具片段；展示Controller留U2 |
| timeline_todo.dart | D1 conversation Todo值；U2只读呈现 |
| token_format.dart | U0新`ui/formatters/token_format.dart`；保design/19单位/unknown规则，C删旧SDK源 |
| turn_models.dart | D1 conversation完整Turn状态/失败/预算/rollover |
| typed_json.dart | C删除旧运行期兼容解码；authoring原文/opaque参数只在已批准的明确边界处理 |

跨域import可消费其它域公共**值**，不能持有另一个Repository的writer或互相编排关闭。
例如D1引用D3的ThreadStorage值不授权D1重写persistence reducer；D3使用D1的冻结提交结果
不授权它创建第二个附件账本。编排依赖仍由root的完整ports合同明确。

## 7. Flutter旧domain：9文件完整迁移表

路径相对`code/anywork/lib/src/domain/models/`，生成part不在下表手写授权内。

| 旧文件 | 唯一writer及迁移 |
| --- | --- |
| agent_workspace_view.dart | U3迁到workspace呈现；是composition值，不复制进SDK |
| studio_models.dart | C删除SDK旧巨桶的再导出，无新的Flutter领域镜像 |
| studio_projection_models.dart | C最终删除；U3迁Chrome/Sidebar/Header，U2迁StatusBar，各写新目标不改旧源 |
| studio_reactive_projections.dart | C最终删除；U2迁Context/Throughput实际消费；U1迁仍需的账号/route呈现，零生产引用成员不保壳 |
| studio_state.dart | C最终删除；U3迁shell preview为组合领域值，不能直接删仍在用的preview行为 |
| timeline_commands.dart | U2迁到conversation呈现意图/enum |
| timeline_messages.dart | U2迁到conversation展示载荷，继续引用D1 canonical typed内容，不另造领域模型 |
| timeline_presentation.dart | U2：ChangeNotifier/分组/listener是UI owner，不能进纯DartSDK或Freezed |
| timeline_presentation_controller.dart | U2：唯一Message集合写入/flush/释放，不是D0资源公共组件 |

全部旧手写part解体由各library的唯一owner负责：FRB A、Timeline/Composer U2、Shell U3。
不为消除part行数把它们改成等价的巨型转发library；按已冻结能力/功能边界形成真实小模块。

## 8. 当前输入身份清单

[v4-source-ownership.json](./v4-source-ownership.json)记录当前1043个相关输入路径（含已删除3项）、
每路径唯一writer、迁移/保留/生成责任和实际SHA-256；不是代码完成报告，也不是基线LOC统计。
生成/manifest/保留的平台源归root；R和C较宽的现有Rust/工程范围只允许必要接缝/消费者迁移，
不授权重写无关内核、供应商、发版或部署流程。D2/D3的新目录尚不存在，故当前文件计数没有
这两组，不能据此认为其业务任务为空或由C代实现。

生成脚本为root本会话scratch中的`v4_source_ownership.py`，只做rg文件清单、只读Git身份和
源码hash，不调用项目编译/测试/GUI生成器。正式JSON为审查输入产物；不把会话绝对路径放进
正式schema。派发前再次核本任务输入hash；后续实际新文件按§2互斥target prefix归属，跨prefix
或新增公共文件必须root先补合同/manifest，不能由executor自行修改共享出口。
