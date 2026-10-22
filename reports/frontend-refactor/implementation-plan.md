# 全链路一次性重写计划 v4：最新主线、完整合同、并行实现、最终统一验证

## 1. 最新要求与本次变更

本计划完整替代此前 v3 的实施节奏，保留已确认的业务目标与安全不变量，落实用户最新指令：

1. **先基于最新主线完成 rebase／同步**，尽量由隔离工作树子代理执行，主代理负责备份、关键冲突决策与最终整合。
2. **一次完成本次重构范围内全部代码的重写**，不再按 Timeline、Thread、Repository、单个页面依次测试放行，也不以旧 Client 外包一层作为中间交付。
3. **中途不测试、不编译**。执行子代理和审查子代理均不得运行构建、测试或编译型检查；完成一项实现后立即安排独立静态审查。
4. 在接口契约完整、写入范围互不重叠时，尽量并行修改不相干模块；不为并行而把关键设计交给执行者决定。
5. **全部手写重写和消费者迁移完成后**，再统一生成、整体静态审查、编译、测试与原生集成验收；在最终验收阶段集中修复发现的问题。
6. SSH 出问题时，**等待10秒再重试连接／只读状态核对**；不得重复启动状态未知的命令或重放可能已受理的业务操作。

“全部重写”指本任务范围内 Dart／Flutter 领域与呈现代码、必要 Rust／FRB／server 接缝及其消费者，不扩展为无关 Rust 内核、供应商协议、第三方库或已生成源码的手工重写。设计、类型、方法和目录可以破坏性调整，但功能、安全语义和用户数据不能丢失。

## 2. 交付目标与非目标

### 2.1 必须实现

- **Feature-First** 功能组织。
- Presentation 严格分为 **Smart Screen／Connector** 与 **Dumb View／Widget**。
- **生成式 AsyncNotifier 是真正 ViewModel**：管理编辑、校验、呈现状态、可见需求和交互编排，不是旧巨型 Client 的只读投影壳。
- **Freezed 定义不可变领域值与 ViewState**；连接、任务、Controller、原生句柄和资源 owner 不强行值对象化。
- **typed FRB push** 按领域、频率、载荷和生命周期分割；历史、详情、原图、长文本使用明确的 typed 按需读取，不轮询实时状态。
- Rust 是业务权威，分域 Repository 是 Dart canonical 镜像的唯一 writer。
- 长寿命 Session、草稿、附件、冻结提交、操作结果和关闭责任留在对应领域／资源服务，不随 Widget 或 Provider 的 dispose 丢失。
- 迁移所有生产、demo、fake、测试、Driver、server、公开导出与生成输入，删除旧入口、兼容别名、重复 owner 和旧目录转发。
- 提交可复算的代码量、架构覆盖、重复实现和工程质量前后对比；最终提交、推送任务分支、更新现有 PR，核对实际 CI 终态。

### 2.2 不变的限制

- 不删除用户数据，不清空数据库、草稿、历史、配置或凭据来解决迁移问题。
- 按项目 v2 数据根隔离规则保留旧目录；本版本 v2 内实际结构变化仍须安全迁移，不能恢复默认值替代。
- 不推 main、不合并 PR、不发布、不部署；不擅自选择版本号或 tag。
- 不重做无关模型供应商协议、不做无关视觉改版、不增加自研状态管理、消息总线或 codec。
- 不把已有局部批准、历史门禁、demo、fixture 请求成功、进程 exit0 或三次未复现冒充最终通过。

## 3. 当前现场与证据保全

当前任务分支为 `pure-session-thread-65e3ee582f0d4-82`，已提交 HEAD 为：

`b98432fa809446d57be87a8b96379455ec8a4828`

此前贡献比较基线为：

`f6cb327ceb3416dca181790575711588571d3ec7`

工作区有大量未提交生产、生成、测试、设计和报告改动。主代理已建立只读备份：

- 70 个已跟踪变更、20 个未跟踪文件，共90个路径；
- tracked binary patch、index patch、NUL-separated status、完整变更文件归档、逐文件 hash／mode／删除身份；
- 备份位于本 Thread 的 `artifacts/main-sync/20261022T011854Z/`；
- identity SHA-256：`1df8ac4781d51af5be300505e89d84728755a75514840161bd7e3e2a6bcc43c4`。

备份不是提交，也不是回滚授权。恢复前核对 hash，保留旧 stash 和原件，不重复 apply、不 drop 他人 stash、不清理无关 worktree。

原生 QA 已按主代理要求暂停，报告三轮 v2 新环境 history-only 旅程已完成、所属进程已退出；其正式 v2 汇总尚未落库，原件仍保留。这些属于**旧基线的已有证据**，需要静态核对后记录，不能直接证明新主线重写后的版本。初始 connection failure 的旧原因仍未知；后续不再单独循环该诊断，纳入最终风险与验收矩阵。

当前远端主线确实已前进，包含存储路径、Timeline、生图与退出流程等更新。远端实际名称／URL／提交以工具实核为准，不能用旧摘要中的仓库名或缓存 `origin/main` 冒充最新主线。

## 4. 第一阶段：安全同步最新主线

### 4.1 冻结与备份

- 保持所有正在修改当前工作区的执行者暂停；确认其任务、GUI、fixture、Driver、编译器和子进程终态。
- 在现有备份基础上复核最终冻结状态；如有新的合法文件变化，仅补充新的不可覆盖快照。
- 记录任务分支、HEAD、upstream、已发布 PR head、remote、stash 清单、所有未提交和未跟踪文件身份。
- 临时脚本、归档、冲突清单和命令输出只用各代理自身 session 目录；不把会话路径沉淀为正式设计。

### 4.2 子代理隔离执行

使用一个 `worktree_executor` 拥有本次主线同步任务：

1. 在宿主分配的独立工作树核对基线，fetch 实际远端 main，记录本次冻结的主线完整 commit。
2. 先确认已提交任务历史与主线的关系，rebase 任务已有提交；不修改 main 或其他 worktree 的分支。
3. 将冻结的未提交成果以可追踪方式在候选工作树重放，必要时由主代理提供备份／stash 内容身份与受控传递；不把未审的重构成果提交为“备份 commit”并混入交付历史。
4. 同步主线保留上游新能力，重构成果保留已批准的目标语义；不能用整文件 ours/theirs 丢掉一侧。
5. 文档或业务接口冲突涉及关键语义时，由主代理先决定并同步设计；执行者不自行删字段、扩大输入、改保存／取消／凭据语义。
6. 生成物冲突只记录输入与后续统一生成责任，不手工创造生成内容；若为安全重放需要暂时保留一侧，必须明确未验收，最终统一生成替换。

### 4.3 静态接受与整合

- 完成即派 fresh reviewer，仅静态审查 commit ancestry、diff、冲突解决、文件身份、上游能力和成果保全；**不测试、不编译**。
- 主代理审查通过后，串行将候选基线与未提交成果整合到任务工作区；保留回退备份、旧 HEAD 与原件。
- 不在同步阶段强推已发布分支。最终推送是否需要 lease-protected history update，依据真实提交图和已批准 rebase 范围处理；绝不覆盖 main 或他人的新提交。
- 以本次冻结的新 main 作为新的贡献比较基线，重新计算静态源码基线；上游新增代码不算本任务收益。
- 同步阶段只运行读取、hash、Git 完整性／差异空白等非编译核对，不跑旧基线或新基线测试。

## 5. 第二阶段：主代理一次性冻结完整设计包

在大规模并行重写前，主代理完成**全部共享接缝**，不是只给各子代理任务标题。

### 5.1 固定目标调用链

```text
Rust canonical owner / Session / persistence
  → typed resource feeds / queries / commands
  → FRB adapter（生成 DTO、句柄、typed 转换）
  → Dart domain Repository / Session services
  → generated AsyncNotifier + Freezed ViewState
  → Smart Screen / Connector
  → Dumb View / Widget
```

- `anywork_client` 按 configuration、workspace、models、account_usage、conversation、drafts、modes、resources、updates 等真实领域组织。
- Flutter `app` 负责 composition、bootstrap、routing、lifecycle；功能按 workspace、conversation、settings 组织。
- Presentation 内按 screens/connectors、view_models、state、views/widgets 区分实际责任，不造空目录。
- 通用视觉组件、主题、格式化、platform、FRB adapter、diagnostics 各有明确归属，不回到万能 shared。
- 领域层已在纯 Dart 包时，Flutter 不再创建同构 Repository／Model。

### 5.2 依赖许可

| 层 | 允许依赖 | 禁止依赖 |
| --- | --- | --- |
| Dumb View／Widget | Flutter、主题／l10n、immutable props、UI-only Controller、typed callback | Riverpod／Ref、Client、Repository、FRB、transport、service locator |
| Freezed ViewState | 领域值、呈现枚举、不可变集合 | Widget、BuildContext、Ref、任务／连接／native handle |
| Smart／Connector | 对应 VM、View、导航／对话框／平台 UI | 直接 FRB、transport、可写领域 store |
| ViewModel | 领域公共接口、Freezed state、Riverpod | Widget／BuildContext、具体 FRB adapter、数据库、初始化业务写入 |
| Repository／Session | typed port、领域模型、操作和资源机制 | Flutter、Riverpod、FRB 生成类型、前端 Controller |
| FRB adapter | 生成 DTO／opaque、typed port、明确转换 | 业务 fallback、UI 草稿、第二 reducer、伪持久化事实 |
| Rust 产品投影 | 真实领域 owner、Session、既有 Tokio 能力 | Widget 几何、GUI 全量正文缓存、第二业务事实源 |

### 5.3 每项派发合同必须完整

主代理给每个执行者提供：

1. 本完整批准计划及其任务验收范围。
2. 最新主线、实际任务 HEAD、未提交前置的文件／diff 内容身份。
3. 架构位置、唯一职责、生产者与消费者、允许／禁止依赖。
4. **精确接口形式**：全部类型、字段、变体、单位、nullable、unknown、方法参数／返回／错误、provider family key、Widget props／callback。
5. 状态 owner、创建／借用／释放者、跨路由保留与预算。
6. **大致实现逻辑和关键时序**：首次 await 前冻结、同步观察登记、CAS、去重、晚到结果隔离、失败与取消路径、关闭顺序。
7. 输入约束与错误矩阵，禁止的重试、fallback、静默截断和默认值。
8. 新旧接口迁移和删除清单，包括测试／demo／Driver／server 消费者。
9. 最窄写目录与逐文件所有权；共享、生成、manifest、Git 和设计禁区。
10. 本轮静态审查清单，以及统一最终验证中对应的测试项；执行期间不得运行这些测试。
11. 可自主选择的私有实现细节与必须交主代理决策的边界。

字段、接口、owner、错误、预算或关键依赖尚有空白时，只做只读探索，不派编码。执行者可以选择合同内的私有函数和局部组织，不能改变架构、公共接口、允许输入或业务语义。

### 5.4 必须补齐的跨层协议

- Thread execution／metrics／context／configuration／authoring 的全部具体 DTO、基线／变化、owner incarnation、域 revision、delivery sequence、错误、队列和字节预算。
- 配置 owner 的 Settings／catalog 相容读取与 retained 来源通知、Mode 独立来源观察、closing 和 Thread 投影真实 join；不把全局产品 sequence 当来源屏障。
- 当前模型策略与历史／在途请求冻结绑定分开，不在 Dart 重算模型策略或用当前配置回填旧来源。
- Interaction 完整问题、选项、isOther／isSecret、purpose／continuation、生命周期与 terminal payload；大载荷读取、旧 revision、动作准入、草稿和回应 CAS 一并冻结。
- Plan 文档只在身份变化交付；Workflow／Todo／指标不重传无关正文。
- TurnFailure、storage last_error、动态活动列表等实际无界字段也纳入预算／读取设计，不只处理 Interaction。
- 产品集合 scoped baseline／upsert-remove、有界分页和统计摘要／历史的独立合同。
- Rust／FRB／server HTTP/SSE/OpenAPI／Dart port／Repository／receipt 的完整迁移，删除旧聚合公开入口；core 内部同名事实类型不误删。
- Settings、ModeEditor、Composer、Interaction、Timeline、Status、Workspace、资源和更新 VM 的完整职责、family／保活规则及共享 UI 参数。

设计文档先记录稳定架构和接口；具体文件迁移、任务归属、输入身份和验收映射放工程合同，不在设计文档粘贴实现流水。

## 6. 状态、命令、流控与关闭的不变合同

### 6.1 状态归属

- Rust owner 保存业务权威和可靠历史。
- 各 Repository 唯一归并自己的 canonical 镜像；不暴露可写 reducer/store 给 UI。
- 操作身份、UnknownOutcome、receipt、effect／durable 水位由领域操作 owner 持有。
- Session 服务持有 attempt、待返回 open、订阅、查询、预算和真实关闭责任。
- 草稿、冻结提交和附件 ledger 属于领域，不因 Settings 往返或 Ref.dispose 消失。
- VM 管编辑、校验、防抖、可见需求、pending／error／latestIntent，不重建 canonical reducer。
- Mode JSON／graph／undo 使用单一编辑会话；最多64次撤销／重做的既有边界保留。
- Timeline 唯一 Message 集合和 UI Controller 由展示 coordinator／lease 持有，不复制进 VM。
- go_router 负责导航，Workspace session coordinator 是唯一可写业务目标，不保留第二 selection provider。

### 6.2 命令与观察

- 首次 await 前冻结 Thread、operation、revision、draft stamp、attachment ownership 和目标；旧完成只结算自己。
- 同步登记观察并取得当前值，不能 snapshot→await→listen 丢首帧。
- 同目标 canonical 更新不清 dirty draft；保留 last-known 与局部错误，不为一次保存清空整页。
- Accepted、Observed、Effective、Durable 独立，ACK 与业务 Completed 都不证明 durable。
- UnknownOutcome 不自动重放，错误保留 typed 分类与 correlation，不从文本猜业务决策。
- 相同资源冲突写串行；停止、分页、详情不排在无关长写 FIFO 后。
- 成功不靠聚合 reload 补状态；冲突只恢复相关 owner，不顺带重开 Timeline。
- 手动压缩没有原生 receipt 的现状不能被伪造为已保存 operation；若修改接口须完整迁移并保留未知结果语义。

### 6.3 Feed 与关闭

- typed push；Timeline 公开 initial/next pull 泵不恢复。
- 每 feed 最多2个未 ACK data，baseline 也占额度；latest 待发仅1份，可靠队列另有明确帧数与源载荷字节预算。
- ACK 只确认同一具体句柄已连续处理的前缀，旧 ACK 幂等，超 sent 明确拒绝；转换／归并／必要交接失败不 ACK。
- 可靠域缺口显式 ResyncRequired／Lagged，只重建受影响域基线，不重放业务操作。
- 业务终态是有序数据，不绕过窗口；取消控制与至多一次 Failure／Closed 不能被满窗口阻塞。
- requestClose 同步封准入，close 真实等待 open、producer、sink、查询、consumer、stream cancel；全部结束后才释放 permit／dispose。
- 关闭失败保留 unresolved owner、handle、全部 typed issues 和重试能力，不用超时、Drop、GC 或 Stream.cancel 假装 join。
- 不发明第二套正文、配置、Model catalog 或交互事实源；预算不冒充 FRB wire bytes 或进程 RSS。

## 7. 第三阶段：按冻结接口并行完成全部重写

### 7.1 调度原则

- 尽量使用本地 directory executor；跨目录共享协议、主线同步或需要物理隔离时使用 worktree executor。
- 同一执行者同时只拥有一个清晰任务；同一文件只有一个 writer。
- **依赖冻结接口，而不是等待前一模块测试通过。** 接口已冻结后，上下游可以按合同并行实现；允许中途尚未编译通过，但不允许接口自行漂移。
- 若某任务必须等具体基础文件存在，先完成最小共享基础手写接缝，再释放依赖任务；不以临时兼容 facade 补缺。
- 共享文件清理、公共导出和生成输入由指定单一 owner 负责，不能让各功能执行者互相修改 barrel、manifest 或 composition。

### 7.2 预计任务组与所有权

最终逐文件范围在新主线核对后冻结，以下责任划分固定：

| 任务组 | 唯一职责 | 可并行条件 |
| --- | --- | --- |
| R：Rust／protocol／FRB／server | 新分域源投影、feed/query/command、错误、流控、取消/join、HTTP/SSE/OpenAPI迁移 | 共享 wire 合同全部冻结后，与 Dart 实现并行；同一组不再拆重叠协议 writer |
| D0：Dart 共享基础 | typed ports、资源／operation机制、公共导出、共享不可变类型、跨域生命周期接口 | 先提供冻结的公共形状；禁止演变成新 God facade |
| D1：Conversation／drafts 数据域 | 会话分域 Repository、正文消费、冻结提交、草稿与附件 ledger、互动 query/respond | 与 D2/D3 互斥目录；共享 runtime 由 D0 负责 |
| D2：Configuration／models／modes 数据域 | Settings CAS、catalog、账号、额度、模式命令和领域 reducer | 与 D1/D3 按路径互斥 |
| D3：Workspace／resources／updates 数据域 | 目录事实、唯一目标协调、资源、启动退出与更新领域接口 | 不与 Flutter app 装配共享 writer |
| A：FRB adapter／demo／fakes | 新 wire 到 typed port 的唯一转换和资源适配，同步替身及测试调用方 | wire/port已冻结后并行；生成文件不归此组 |
| U0：公共 UI／呈现基础 | 确认、附件元信息、状态展示、主题和共享 props；无业务 reducer | 先固定 props/callback，不反向依赖 feature VM |
| U1：Settings 功能 | 账号、额度、模型、Agents、模式编辑、SSH、资源、一般设置和统计的真 VM／Freezed／Smart-Dumb | D2/D3和共享UI接口冻结后即可并行，不等测试 |
| U2：Conversation 功能 | Composer、Interaction、Timeline、Status、Todo 的真 VM／Freezed／Smart-Dumb | D1和展示lease合同冻结后即可并行，不复制正文 |
| U3：Workspace／App | Shell/sidebar/workspace、composition、bootstrap、routing、退出协调 | 各 feature 公共入口冻结后并行；唯一 app 装配 writer |
| C：最终消费者和旧入口清除 | 跨 feature Driver、测试发现、AST边界、遗留路径及无消费者清理 | 按文件表避免与上组测试迁移重叠；不执行测试 |

不为凑数量保留无职责任务组；可合并写范围过小或强耦合的工作，但必须由主代理调整所有权表，不让执行者自行接管共享目录。

### 7.3 执行期明确禁止

在全部手写重写完成前，执行者、reviewer 和主代理都不运行：

- cargo build/check/test/clippy、Flutter/Dart analyze/test、原生 GUI／fixture／live 验收；
- 以测试名义的临时反例、红绿回归、性能探针、验证性示例构建；
- 单个生成器或会隐式构建／生成的检查入口；
- 为证明中间状态可用而恢复旧 API、降低断言、增加 fallback 或删掉失败测试。

允许的工作为：读取、rg／文件与符号定位、代码和测试源码编辑、静态 diff／契约核对、hash／引用／空白检查、受控 Git 操作。测试源码可以同步重写，但**不得执行**。生成源码不手改，统一留至全部手写范围稳定后处理。

## 8. 每项实现完成后的独立静态审查

- 每份执行报告到达后立即派 fresh reviewer，不等整批。
- 派发包含本完整计划、精确任务合同、实际基线／diff／文件 hash、执行者身份、静态检查记录。
- reviewer 亲读实际工作区、设计与代码，检查接口、层依赖、完整字段、错误、所有权、并发时序、取消/join、迁移删除和测试源码的缺陷敏感度。
- **只静态审查，不运行测试、不编译、不执行 analyze/clippy/GUI。** 明确记录“未执行验证，按用户要求统一留到最终阶段”。
- 不能因为中途生成物过期或未跑测试单独阻塞静态实现完成；但缺少接口、语义冲突、资源错误、遗漏消费者和不符合合同必须阻塞。
- 问题交原执行者修改，再由新的 reviewer 静态复审；关键设计变化由主代理先同步合同。
- 本地成果直接在工作区，不制造合入；worktree 成果静态审查通过且依赖满足后串行整合，影响已审范围的冲突需针对性静态复审。
- 未完成全量重写前不提交／推送阶段实现，也不把局部静态批准当最终可交付。

## 9. 第四阶段：全部完成后统一生成、整体审查与测试

### 9.1 进入条件

所有手写任务完成，全部对应消费者和旧入口删除完成，互斥所有权已释放，worktree 成果已整合；每项有当前版本的静态审查结论。主代理先对完整需求—接口—实现—删除矩阵做跨任务审查。

随后统一执行根 `cargo xtask generate-gui`，再核 canonical 输出和孤儿清理；不手改 FRB、Riverpod、Freezed、l10n 生成物。生成所需的编译属于本最终整体验证阶段，不在执行期提前发生。

### 9.2 最终自动化检查

主代理统一执行适用项目门禁：

- `cargo fmt --all --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test -p pl-model`
- `cargo test -p pl-core --features sqlite`
- `cargo test -p pl-studio-runtime`
- standalone core 两个 feature profile
- 必要 bridge 契约测试及 server 编译
- `cargo xtask verify-client`
- `cargo xtask verify-gui`
- 新 AST 规则及反例 fixture
- `git diff --check`

最终检查可以先按失败所属范围修复、复审并定向复验，再补齐受影响全量门禁；不为一次失败从头机械重跑未变化的全套。此时已经进入用户要求的“全重写后整体测试”阶段，必要红绿回归、故障注入与真实集成证据在这一阶段集中取得。

不能省略或静默跳过已知失败、零测试、超时、取消、权限等待或环境故障；所有命令必须核真实终态。

### 9.3 最终原生与跨层验收

采用官方 xtask、真实 bridge、隔离本地模拟供应商、Flutter Driver，Linux SSH 下使用私有 Xvfb、绝对 XAUTHORITY 与受控进程树：

- 设置各子域保存、失败／显式重试、切 tab／返回、模型／模式选择、dirty guard；
- 发送、停止、互动回应、UnknownOutcome、冻结目标与附件转移；
- metrics／context 独立更新，catalog／Mode 在无 token 时刷新正确域，Plan／Workflow 不被速度重复投送；
- Timeline 首屏、流式、历史分页、History冻结／回Live、长正文、附件、问答与计划回执；
- 满窗口 ACK、query、resync、切 Thread、冷恢复及真实取消/join/dispose；
- 关闭／更新退出、持久化失败与资源释放；
- 正常和窄窗口截图、快照、日志及进程回收。

原初始连接失败作为待排查风险纳入最终场景：捕获实际 typed 错误，不以旧三次通过解释旧原因。若最终仍存在未解决的用户可见失败，不把阶段勾成通过。

Linux实测、Windows CI、真实供应商覆盖分开报告；模拟通过不等于真实厂商兼容，代理看图不冒用户人工批准。

### 9.4 SSH 恢复规则

SSH失败后等10秒再恢复连接；先读原task、归档及所属进程。活跃任务继续等；确认终止后再恢复必要操作。可能已执行的提交、审批或数据写入不得重放；构建、只读检查可在确认旧进程结束后重启并保留失败证据。

不得使用 nohup／detach 逃避生命周期管理，不全局 pkill，不杀用户桌面，不占1420。持续不可用时保留现场和准确待办，不以免责声明替代完成，也不伪造运行结果。

## 10. 最终工程对比、提交与 PR

以冻结的新 main 和最终完成版本，用同一脚本、同一分类复算：

1. 手写生产 Dart、限定 Rust、测试、Driver、生成代码分别列文件数、LOC／非空行、增删与百分比。
2. 最大文件／library、严格>500行数量、手写 part、平铺目录密度、旧接口及无消费者清理。
3. Thread树选择、附件元信息、确认／状态展示等重复实现份数和实际消费者；搬家、生成替代和去重分别说明。
4. Repository／AsyncNotifier／Freezed／Smart-Dumb 的真实覆盖及依赖规则，不以命名或包装层数量冒充完成。
5. 同条件合成场景下领域投送、无关字段、在途高水位、resync和关闭证据；无可比测量不报性能提升百分比，不把源JSON预算当wire/RSS。
6. 完整迁移、架构、接口、测试和原生验收矩阵，明确未覆盖平台／来源。

全部验收通过后再提交 Conventional Commit、推送任务分支、更新现有 Draft PR #120，等待实际 CI 全部终态。破坏性 Dart／FRB／共享协议使用真实 `!`／BREAKING CHANGE 和升级说明，不隐藏真实迁移成本。

保留执行者与工作树至最终验收完成；成功后按归属关闭和回收，失败／取消保留可恢复现场。最终一次性交付 PR、commit、新基线、质量对比、实际验证与 CI 状态，不把旧文档 CI 或中途静态批准当最终结果。

## 11. 完成标准

- 最新主线已安全整合，原未提交成果和上游能力未丢失。
- 全范围按冻结合同完成真实重写，没有旧 facade、双状态源或兼容路径残留。
- 实施期间遵守不测试、不编译；各模块按精确所有权并行，并经独立静态审查。
- 全部重写后统一生成、整体审查、适用全量测试和原生验收通过，未解决失败为零。
- 质量对比可复算且不混入主线贡献／生成增长／无数据性能猜测。
- 最终 PR 与 CI 对应真实提交，权限边界、数据保全、证据和资源回收全部可追溯。