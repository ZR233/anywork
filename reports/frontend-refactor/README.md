# 前端全链路重构工程证据

本目录记录契约和可复算证据，不以目录存在表示重构完成。整体实施与 GUI 验收尚未完成；
[Draft PR #120](https://github.com/ZR233/anywork/pull/120) 已建立，阶段提交与验证范围见下文，
不能将文档阶段 CI 通过外推为当前未提交代码通过。

## 当前执行口径（v4）

[完整批准计划 v4](./implementation-plan.md) 已替代下文历史阶段的逐项测试／提交节奏。
主线同步与旧成果三方保全已完成，详见 [同步记录与待修逻辑](./main-sync-v4.md)；当前任务
重构输入基线为 `78a2762495772d7fe416faaf5f14876cf46597c4`，生产成果仍未提交、未推送。
用户追加要求推送当前进度，本次仅提交设计与工程合同checkpoint；范围及未交付项见
[进度推送记录](./progress-checkpoint.md)。后续文档commit不改变上述源码输入身份。
接下来由 root 冻结全部共享接口，再并行完成全范围手写重构，最后统一生成和验证。

实施中不编译、不测试、不运行 GUI、不生成。中间审查判断目标逻辑、接口与所有权，
不因其他任务尚未迁完而造成的暂时编译／功能失败阻塞；实际逻辑缺陷仍记录并由对应任务
解决。同步保全批准不等于旧 Timeline 逻辑批准，已发现的四类旧逻辑问题和一项新消费者
迁移仍列在同步记录中，全部重写完成前不能宣称最终通过。

## 基线

用户要求基于最新主干继续。本次 fetch 冻结主线为
`b3f22b8f651816851852582a10a970fe25af3ae6`；任务文档提交已 rebase，未提交成果经三方保全
整合。最终贡献比较以该主线为基线，不把上游的存储布局、生图、吞吐口径、Timeline 和退出
更新算成本任务贡献。旧 `f6cb327c` 基线及其证据保留在旧提交，不再用于最终收益比较。

`baseline-source-metrics.json` 是该提交的已跟踪源码统计。以下复算脚本当前已在本地保全，
尚未纳入本次纯文档checkpoint；最终代码交付时一并提交，不能将本次阶段推送视为完整可复算交付：

```bash
python3 reports/frontend-refactor/source_metrics.py \
  b3f22b8f651816851852582a10a970fe25af3ae6
```

最终版本用同一脚本和已验收 commit 复算；尚未提交时可用 `--worktree` 包含新增但未暂存的源文件，
其记录会明确标为 worktree，不冒充一个已提交版本。脚本输出源文件内容总 hash，便于绑定证据。

| 分类 | 文件数 | 物理行 | 非空行 |
| --- | ---: | ---: | ---: |
| 应用手写生产 Dart | 206 | 61,689 | 57,833 |
| 应用生成 Dart | 85 | 118,535 | 96,272 |
| 应用 test Dart（含支持／非门禁用例） | 32 | 16,493 | 15,641 |
| Driver Dart（单列） | 66 | 35,270 | 33,403 |
| 纯 Dart 包手写生产 | 87 | 23,299 | 20,948 |
| 纯 Dart 包测试 | 21 | 8,968 | 8,480 |
| Rust 手写源码（限定范围，含内嵌测试） | 474 | 112,075 | 105,327 |
| Rust FRB 生成源码 | 1 | 33,315 | 32,273 |

统计口径：

- Dart 生产仅计算 `lib`；`.g.dart`、`.freezed.dart`、应用生成 FRB／l10n 独立统计。
- Rust 仅计算 protocol、Studio runtime、server、bridge 的 `src`，**不是整个 workspace**。
  内嵌 `#[cfg(test)]` 与私有测试模块包含在手写源码中，不将该数字称为纯生产逻辑 LOC。
- 测试、生成、Driver 与工程证据脚本不并入 Dart 手写生产总量；不能用生成量增加或移动
  文件制造维护成本下降的结论。
- 物理行使用 UTF-8 `splitlines`；空白行判定为 `strip()` 后为空；大文件阈值严格为 `>500`。
- library 指标按直接手写 `part` 指令计算，生成 part 排除；这只是源码规模度量，不能替代 AST
  依赖门禁或语义分析。基线最大手写 library 是 FRB adapter：12,464 行／10 个手写 part。

基线大文件分布：应用生产 42、纯 Dart 包生产 14、限定 Rust 手写源码 49，分别保留，不将
混合总量 105 宣称为 105 个 Dart 文件。完整最大文件及 library 清单在 JSON 中。

## 旧基线已有验证证据及边界

以下为 v4 同步之前的历史记录，不表示同步后的版本已运行这些命令；既有失败记录继续保留。

- `b98432fa809446d57be87a8b96379455ec8a4828` 已提交／推送完整计划、目标设计、T1.A-v2 契约和
  基线数据；[该文档阶段 CI](https://github.com/ZR233/anywork/actions/runs/39403619776) 的
  Conventional PR title、Release configuration、Rust (Windows)、Studio server (Linux)、Flutter
  五项全部成功。它只覆盖该已提交版本，不覆盖工作区后续 native／Dart／生成变更。
- `23dc4e87` 已执行 `cargo xtask verify-client`，纯 Dart 测试全部通过、应用 adapter 194 测试通过；
  `cargo flutter analyze --no-pub` 零问题。同步到 `f6cb327c` 的三文件增量未改变 Dart／Flutter 输入，
  可作为相同输入的基线证据复用，不能证明后续修改后的版本通过。
- 新基线统计脚本已实际运行，其原有七类 cohort 与此前统计逐项相等，大文件总量同为 99；
  Driver 是新增单列口径，不是新增加的代码。
- 原始命令日志、敏感运行快照和截图留在忽略目录，不随报告提交。
- 最终质量结论还需实际局部审查、全量门禁、native GUI 旅程和 PR CI 终态。当前没有性能
  提升百分比或 FRB wire 字节实测结论。

## Timeline 旧阶段历史（不作为 v4 当前验证结论）

- Native T1.A-v2 经 R1／R2／R3 修复和独立复审，R3 当前版本已获局部批准。已落实 ACK
  登记与等待顺序、同步 delivery 登记、真正 Clean 谓词、空失败 opening 回收和 retained close
  自引用清理。B1 丢唤醒与 B4 空 owner 自引用均取得同一真实生产回归的非零红／恢复绿证据。
- 最终 native 16 个定向用例通过，包含真实 spawned task／close poll-drop、真实 registry、
  panic 保留失败及真正 saved + Terminal 数据在满窗口等待 ACK；5 文件格式、bridge lib
  check／clippy 和差异空白检查通过。该证据不冒充真实 FRB/native GUI。
- root 在 R3 获批后再次运行 `cargo xtask check-gui-generated`，exit 0，当前两包生成集合
  与内容稳定；没有手改 generated 或保留公开 pull alias。
- root 随后执行 Rust 阶段门禁：`cargo fmt --all --check` 通过，但
  `cargo clippy --workspace --all-targets -- -D warnings` 在 bridge 的 registry 测试发现同步
  MutexGuard 临时值跨 await（`await_holding_lock`）。局部 `--lib` 检查未覆盖该 cfg(test)
  路径，不能拿局部批准代替 all-target 通过；最小修复已交原执行者。续跑遇到模型服务 503，
  root 随后冻结原范围并将这一处测试增量移交 fresh 执行者；显式拆开 clone 与 await 后，
  获得独立定向审查批准，没有 allow、换锁或生产行为变化。root 再跑全仓格式、workspace
  all-target clippy 与 bridge lib 测试，均 exit 0（16 passed），原始失败没有被静默覆盖。
- 不依赖上述 lint 修复的检查已实际通过：standalone core 的无数据库与 SQLite 两个
  `--no-default-features --all-targets` profile、`cargo test -p pl-model`、
  `cargo test -p pl-core --features sqlite`、`cargo test -p pl-studio-runtime`（130 passed），
  以及 `cargo build -p pl-studio-server`。结合上述实际修复后的 clippy 复验，本阶段 Rust 门禁
  已齐，但不覆盖 Dart 或原生 GUI。原始完整命令日志保存在当前执行会话，不随报告提交。
- 一条关于 Published Clean owner 仍因已完成 Shared 留存闭包的审查备注，经 root 核对锁定
  `futures-util 0.3.34` 的 `Shared::poll` 不成立：完成时 `FutureOrOutput` 替换为 Output，
  原 Future 及捕获引用被 drop。空 Aborted 中被放弃的 Pending Shared 则不同，已用 B4 红绿
  回归修复；不为未经证实的已完成 Future 泄漏新增清理分支。
- SDK Freezed／AST／双包生成前置已完成；A2 消费闭环现按 v3 合同实施。root 核对第二个
  生成前检查点的 41 个手写文件与冻结身份一致后，实际运行统一生成；SDK build_runner
  因 Channel 类边界的语法错误返回非零，原执行者随后修复缺失括号并纠正之前格式命令
  隐藏退出码的问题。root 核对第三个检查点后，完整 `generate-gui` 及随后
  `check-gui-generated` 均 exit 0；最终只增加两个预期 SDK Freezed part，原有 86 个生成
  输出、41 个手写输入及 native／manifest／lock 等 73 项控制文件均保持冻结身份。
  该生成证据不包含后续手写修复的行为验证，不能外推为整个 T1 或最终交付通过。
- A2 正式验证期间，执行者触发模型服务配额限制，本轮失败并保留未交付现场。root 随后
  独立运行 SDK analyze（零问题）与7个相关测试文件：108 passed、2 failed，实际 exit 1。
  两个失败分别为 `timeline_query_scope_test` 的“close 失败时连接许可保持到显式重试”和
  `chat_lifecycle_test` 的“close failure holds a permit until explicit cleanup succeeds”，
  均暴露 native close 异常未完全收束。这份真实失败保留为回归证据，不以服务故障将其忽略。
- 用户确认额度恢复后，原执行者修复首登记 close Future 的异常归属与 stream cancel 失败
  收束，并完成 APP adapter／demo／展示交接修复。当前冻结待审报告为：SDK analyze 零问题、
  相关7文件110 passed；APP analyze 零问题、正式10文件134 passed；非门禁 binding 27 passed
  单列补证。root 已核对全部41手写内容身份、3删除项，73控制文件和88生成输出未变，并立即
  派 fresh 独立审查。审查者亲跑上述 SDK／APP 定向组合及 analyze 通过，并给出局部静态
  批准；root 随后以真实公开生产路径补充反例，实际复现同步重绑交付旧 baseline、未订阅前
  getter 提前认领及转换 Failure 后仍交付 Data 三项失败，**因此未接受该版本为可交付**。
  相关回调 join／许可释放与非必要公开方法也交原作者作合同内修复。R2 报告 SDK 114 项、
  APP 正式137项及非门禁 binding 27项通过，原三项探针转绿；root 已核对本轮全部内容身份，
  并立即安排新的 fresh 复审。但 root 补充的两项真实适配器探针仍实际失败：正常 native
  Failure 后继续交付 Data，以及先 requestClose 后取消订阅会在 native close 尚未开始时
  返回。R2 因此仍未被接受为可交付，需继续定点修复、独立复审和跨层验收。
  临时日志已原样归档，旧非 retryable／saved-current 的真实红绿原件也已找回并由 root
  逐项亲读核实；不以摘要或普通测试数量代替完整合同证据，不提交未通过阶段验收的代码。
- 用户要求更换执行者后，root 停止旧任务、保留接手快照，并按最新 Profile 新建任务。
  新执行者迁移了正式测试，但随后与另一只读探索任务一起遇到连接拒绝、重试耗尽；这是
  代理服务故障，不将失败轮次当作交付。root 确认无遗留任务后单点接管四文件剩余修复。
  正式回归实际证明了 native join 错误处理挂接过晚、本地取消未结束即 dispose，以及取消
  失败未保留 native issues 三条失败路径；随后同一回归全部转绿。
- root 先将 A2 合同细化为 v4、同步 design/26，再修复 adapter 的共同关闭责任：native join
  与底层转发取消同时登记并等待，只有两者成功才 dispose；取消失败以既有 typed issue
  并入 Unresolved，保留完整原生诊断。公共类型／签名／领域预算和 native v2 不变。
  当前 APP analyze 零问题，正式10文件 **144 passed**，root 的两项 FRB 与三项 Demo 反例
  **5 passed**；局部格式／差异检查通过。随后 fresh reviewer 亲核当前四文件／v4 合同，
  独立复跑两核心正式文件 **53 passed**，并补充同步打开失败、native join 与本地取消同时
  失败的真实适配器用例，明确批准该局部范围；批准不外推到真实 FFI／GUI。
- root 随后完整执行 `cargo xtask verify-client`、`cargo xtask verify-gui` 与差异检查，
  均 exit 0：SDK **204 passed**、APP `test/client` **211 passed**，AST 扫描298个手写源文件，
  两侧 analyze 零问题、格式零变化、统一生成 canonical 稳定。一次 SSH 失联尝试没有
  可靠退出码，已保留为失败历史；恢复后确认旧进程已结束、冻结输入未变，才重跑取得上述结果。
- 真实 Linux／Xvfb 原生验收的早期尝试未通过。首次因 root 传入相对 XAUTHORITY，
  原生程序切换工作目录后无法访问显示器；已用两个工作目录的真实 X11 探针确认并改用绝对路径。
  第二次 GUI 启动、fixture 完成且原生进程干净退出，但 live Driver 以255失败，阶段停在
  `prompt_submitted`；fixture 完成与退出码0不能替代 GUI 断言通过。
- 第二次失败暴露验收工具只归档成功阶段、丢弃失败阶段日志的诊断缺口。root 先同步
  design/24，再修复阶段预登记、真实退出状态、脱敏错误日志和原错误链保留。初次修复被
  独立审查阻塞后，三项问题逐一修正，四个 Rust 文件与设计文档获新的 fresh 局部批准；
  定向 Clippy、格式和差异检查通过。Driver 新增有界的超时最小状态，也获独立批准，未改
  原90秒／成功判据。真实日志曾记录 Live 首条件超时；后续两次 Live／restart 均通过，
  但没有因此宣称已证明早先超时的根因。
- 一次位移矩阵接近完成时 SSH 断连，原生报告明确 `cancelled=true`；恢复后核实进程均已
  回收才重开，不将该次部分结果视为通过。随后仅在外层增加低频运输心跳，原官方场景、
  fixture、矩阵和断言不变。第六次完整旅程 exit 0：Live／冷重启均通过，6组各96次与
  3组各600次 rapid（共1800次）、burst40次、分页交叠8次全过，failureCount=0。
  三次 GUI 生命周期均正常退出，无 signal／cancel／残留后代；fixture accepted2／rejected0，
  全部必需步骤已消费。root 实际打开正常1920×1200、窄900×760及Busy／冻结／回Live截图
  复核，未见明显溢出。该结论限 Linux／本地模拟供应商，不外推 Windows 或真实厂商。
- raw FRB 首次实际构建／运行暴露探针装配问题：给20k历史Thread追加输入在 fixture 匹配前
  收到 HTTP413，fixture请求数0，不能冒充窗口／query通过。未放宽 fixture 限制或断言；
  已冻结改为正常API创建独立小基线Thread、再运行一次20k源的方案，并交执行者在其自身
  隔离环境完成定向补证。实际查明 fixture HTTP handler 的请求体上限为1MiB，超限在剧本
  匹配前返回413；不是 Axum 默认上限，也没有提高限制来制造绿色。
- 独立执行者的 run4 已取得真实 raw query／ACK／close 可观测链：source Turn Completed
  时仍有2个未ACK数据帧；detail4B完成，page首读typed Busy，未释放ACK并观察应用级队列
  Ready 后重读page32成功；ACK越界／幂等／前缀释放、满窗并发重复close／cancel／dispose、
  中央退出及所属进程回收均有真实原件。[正式报告](./t1a-native-acceptance.md) 经返工和
  fresh review 获得**报告真实性与证据边界的局部批准**，不表示整个 Timeline 阶段通过。
  应用级 `Ready + pendingCommits==0` 不证明该 Thread／Turn 的 durable checkpoint；raw
  探针不测内部pending槽、8MiB预算、wire或RSS。全部失败轮次和旧artifact键名保留并解释。
- 初始 a1 真实出现 `connection:failed / generation:0 / ready:false / itemCount:0`，
  旧Driver未保存原因；fixture正常、native exit0和后次通过均不能反推原因。root已先同步
  design/26并冻结[四字段只读诊断合同](./t1a-connection-diagnostics-contract.md)，执行者
  完成五文件增量、旧投影3项真实失败→同文件8项全过及定向format/analyze，已获fresh局部
  批准；审查者独立复跑8项及五文件format/analyze均通过。
  诊断不输出异常正文、不改变业务重试／预算／90秒判据。连接失败原因仍未定位，原生取证、
  阶段跨层验收与代码阶段提交尚未完成；不靠复跑绿色将该风险标为已修复。
- root 在诊断局部批准后重新完整执行 `verify-client`／`verify-gui`／差异检查，均 exit0：
  SDK仍为204项，APP增至214项；AST298、两侧analyze、格式与canonical生成检查通过。
  再核SDK20／APP21输入、73控制、88生成及3删除项，除明确诊断／先行设计外没有意外变更。
- 新的初始连接取证只实际启动第1轮官方history-only，日志停在bridge构建，task返回
  `remoteDisconnected`，wrapper另记录signal15与KeyboardInterrupt；发送方和详细因果链未知。
  未观察到app／VM／Driver启动，没有超时快照，四字段不可得；恢复后的owned-process扫描为空，
  但没有native／descendant退出报告，不能宣称exit0或完整回收报告。按首败即停未运行第2／3轮，
  未新开替代运行，原件全部保留。[取证过程报告](./t1a-connection-investigation.md) 经原作者
  文字返工与fresh复核获局部批准，只覆盖报告真实性，不代表核心原生取证或功能通过。

获批 native 内容身份：

| `code/anywork/rust/src/api/studio/` 下文件 | SHA-256 |
| --- | --- |
| types/chat.rs | b0c2de4bb51fdab61b89d1dd3de6b28729c6f9d682c5c59547ad20ebe486c527 |
| handlers/chat.rs | 55a6ba5b988a5bc83ae8e167f8bb78b12ecf7d973b9b29c5d16fe3afb92882f7 |
| subscription/mod.rs | a4c5682c328896bce37f68c70cc250ecf7173ef70ff720cefd13283a25e53fbe |
| convert/timeline_content.rs | 2cc121aded13310074d13d4fea6a889abfc24c6848b38993af54188c0b7f27c2 |
| subscription/timeline.rs（含获批 R4 测试短锁增量） | fe6789904e4f8ed5cbc36352ebd3fcdd5dabd31feb4b8448e511467e80bbcb32 |

## 实施契约

- 批准计划 v4，canonical revision 9，内容身份
  `sha256:f8b26bdc7c55994ad3beb154fbcdffe57a81509f2ec2b5c515d3c9f1259727c8`。
- [最新主线同步记录](./main-sync-v4.md)：保全审查范围、生成延期、代码量新基线、
  中间逻辑审查口径与尚待全重写修复的具体问题。
- v4 root 共享设计包正在定稿：[共享能力与操作](./v4-shared-contract.md)、
  [资源关闭与候选身份](./v4-lifecycle-contract.md)、[Thread wire](./v4-thread-wire-contract.md)、
  [Presentation 接缝](./v4-presentation-contract.md)、
  [Interaction／Mode／Timeline 编辑与展示接缝](./v4-editing-vm-contract.md)、
  [写入所有权与依赖](./v4-ownership-contract.md)。只有全部准入项完成后才派全量编码；
  文档中的未完成字段／方法／所有权不交执行者自由决定。
  当前逐路径输入身份见[所有权manifest](./v4-source-ownership.json)，不表示其中代码已重写。
- 产品/命令接缝正在补齐：[产品集合与配置分域](./v4-product-wire-contract.md)、
  [领域公共能力与port](./v4-domain-ports-contract.md)、[typed错误与写入结果](./v4-failure-contract.md)。
- [Conversation／草稿／输入持久化](./v4-conversation-contract.md)固定Session借用、草稿
  唯一owner和输入身份durable的证据；不再从任一Turn.saved推断整次提交已可靠保存。
  产品合同已分开来源metadata与业务详情版本，保Thread目录keyset分页；剩余类型册/全端口
  仍须补齐，尚未释放新实现。
- [应用启动与退出](./v4-application-lifecycle-contract.md)固定显式启动、按需启动详情、
  first-deadline、externalIssues在finalizer之前及installer结果矩阵；Workspace/Updates
  剩余公共动作与全部VM字段继续定稿。
  当前已明确来源/投影水位、无value与空集合、独立统计窗口、部分成功及UnknownOutcome；
  各文档末尾仍有待闭合的具体接口，不视为全量编码放行。
- [产品类型册](./v4-product-type-catalog.md)展开19域业务值与Read字段闭包，包括Agent
  全部状态、Skills真实序列化边界、Updates完整installer详情和统计稳定source identity。
- [产品读取port与只读状态](./v4-product-read-ports-contract.md)固定物化值版本、未知与空集合、
  19域state字段、具体feed/read打开方法及typed页/实体/定位能力；不是新通用状态管理器。
- [Server运输接缝](./v4-server-contract.md)固定具名POST SSE、ACK/close、父feed监督读取scope
  与typed错误；完整Turn历史与runtime纯查询替代等剩余项仍须闭合，不能用活跃摘要丢历史。
- [receipt与观察水位](./v4-receipt-observation-contract.md)逐项固定真实来源、效果和持久化
  证明；Profile独立源、Thread Mode binding及目录冷读/搜索相容性不再由聚合revision代替。
- [Workspace接缝](./v4-workspace-contract.md)固定唯一选择writer、目录query/单实体读取、
  冻结意图和项目打开步骤的独立结果；默认后继选择与命令大载荷等待补项仍明确保留。
- [T1.A Timeline push](./t1a-timeline-contract.md)：完整新接口、原 payload 清单、2 个未确认 data、
  1 个待发槽、8 MiB 业务载荷预算、typed 错误、真实关闭、生产者—消费者迁移与局部验证。
- [T1.A2 Dart 消费闭环](./t1a2-dart-timeline-contract.md)：Timeline Freezed 值、typed ports、
  唯一可靠消费者与 ACK、可等待展示写入、双包生成准备及完整消费者迁移；v3 明确首基线
  未消费的 opening 接入例外与关闭封准入；当前 v4 细化 adapter 本地转发取消与 native join
  的共同关闭／typed Unresolved，不新增公共 API 或改变预算。
- [T1.A2 生成前置证据](./t1a2-generation-preflight.md)：精确 SDK 依赖、AST 正反例及双包
  canonical 新增／稳定／孤儿删除实测；不替代 native 审查或尚未实施的 Dart 消费闭环。
- [T1.A 原生证据报告](./t1a-native-acceptance.md)：真实raw query／ACK／close链、全部失败轮次
  与证据边界；局部报告批准不替代root整阶段验收。
- [T1.A 连接失败诊断合同](./t1a-connection-diagnostics-contract.md)：仅当前owner错误的四个
  安全nullable元数据、严格Driver schema与定向回归，不是新业务重试或根因修复。
- [T1.A 初始连接取证合同](./t1a-initial-connection-investigation-contract.md)：独立新环境、
  最多3轮、首败即停及因果／缺失证据边界；不是放宽旅程或以重复通过消除旧失败。
- [T1.B 字段准入表](./t1b-thread-field-map.md)：核对当前 Thread／runtime 全字段、五域归属与
  单位／unknown／冻结绑定约束；不是可派发实施合同，未冻结项不下放执行者决定。
- 上述切片合同保留历史证据与可复用语义，不再单独触发逐阶段测试／推送；v4 要求 root
  先冻结全部共享接缝，再并行全量重写。旧合同与最新要求不一致的部分必须先更新，
  不能把历史切片批准当整个重构已完成。

后续交付报告补充最终版本对比、真实去重份数、架构依赖、同场景传输高水位、能力迁移矩阵、
实际验证记录及 PR／CI 链接；没有数据的项目不提前填“通过”或推算收益。
