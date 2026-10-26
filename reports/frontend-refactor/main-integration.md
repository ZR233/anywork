# PR #120 最新主线合流保全清单

## 基线与状态

- 原进度检查点：`5564fae30e04d67a73add35eb1c4b5cb2626bf49`，已推原 PR 分支；不是完成交付。
- 共同祖先：`466bc5f45b581a1015606cb496c9b1f26f96eb75`。
- 首轮调查主线：`900a23c5eae44d3c34fde7319b0f57688b3d3937`。
- 本轮重新 fetch 后冻结主线：`7aa6ee04bb60551ccaf0e7de345803f9d30b9230`，新增 #177；以下以该版本为合流目标。
- 批准计划 revision 2 持续有效。用户要求先解决冲突，原 history-close 返修暂停；合流保留原关闭责任实现及已发现问题，不用 main 覆盖掩盖问题。
- 本文件是实施与证据清单，不是设计权威源。设计见 `design/12`、`14`—`19`、`22`—`26`。
- 当前阶段：设计同步完成、准备真实合并。下表“待迁移/待验证”均不表示通过。无冲突标记或 Git 已暂存不等于语义保全或验收完成。

## 逐提交保全矩阵

| 主线提交 | 目的与必须保全的行为 | 新架构落点及验收 | 状态 |
| --- | --- | --- | --- |
| `3b5ee70a` #160 | 独立模型性能统计、完整快照与 pending/gap/readFailed | 保留当前独立 SDK statistics、应用统计领域及真实 bounded read；不得 add/add 覆盖回旧 settings facade | 已有语义融合，合流复核待办 |
| `b0785b7d` #161 | 中文术语、编号、单一权威源、设计不写运行日志 | 在 PR120 新架构文档上融合，不整体恢复主线旧前端设计 | 本轮设计已同步，内容及链接复核 |
| `586162ff` #162 | 真实 PR 截图附件与可见证据 | 最终 Linux Driver 截图与真实附件上传，不以本地路径代替 | 待最终 GUI 与 PR 更新 |
| `9757f131` #163 | 准备期执行身份、停止/无正文继续、父调度、主会话处理直接子交互 | core 控制/持久化，protocol/runtime/HTTP/FRB，SDK typed execution 与具名命令，目录和 composer VM | 待迁移及独立审查 |
| `d10a0b5c` / `bb327fd2` | 上游 6.27.0 / 6.28.0 发行记录 | 保留最终 6.28.0、manifest/pubspec/CHANGELOG；不自行发版 | 待合流核对 |
| `58025822` #165 | 附件准入冻结真实模型路由、安全拒绝文案 | Drafts 复用现有 ModelSelection/提交 route preparation，三个来源与预算/清理回归 | 待迁移 |
| `52db463e` #169 | 智谱官网黑色 Z，通用与 Coding Plan 一致 | 新 ui/branding 注册表、SVG、来源说明；未知回退不变 | 待迁移 |
| `54f03be0` #170 | Windows 安装器不向更新/启动子进程传播目录链接限制 | `PrivilegesRequired=lowest` + `RedirectionGuard=no`；不提权、不改系统策略 | 待合流核对 |
| `409de852` #171 | 五类 SQLite 唯一迁移调度、升级后会话可载入、错误保现场 | SeaORM migration 2.0.4；schema/导入/model-access/身份分阶段；兼容当前 history lease/显式 close | 待迁移 |
| `900a23c5` #173 | helper 双架构并行，发布消费已提交生成物，不重复源码质量门禁 | RC/release matrix、target 隔离缓存/artifact、GUI 等待两份 helper；保签名/verify/冒烟/attestation与 PR 门禁 | 待合流核对 |
| `7aa6ee04` #177 | 归档与安全清理解耦、退役重建授权、远端结构化诊断 | 归档保历史/目录/分支/未提交内容，取消归档不重建；Recovery inspection/nullable facts/原来源命令；订阅失败无互等 | 设计已同步，源码调查与迁移待办 |

## 跨层共享契约与写入顺序

1. `ExecutionBaseline` 增加可空 `execution: AgentExecution`、`continuation: ContinuationView`，复用主线协议类型。`ExecutionChange` 为两项分别提供 `Unchanged / Replace { value: Option<_> }`，不让 `None` 同时表示未变和清除。五域唯一投影 owner、FRB 手写 DTO/转换、SDK Freezed 值/reducer 与测试一并贯通。不只给旧 runtime snapshot 加字段。
2. SDK Session 将旧 `stopTurn(origin, TurnReadRef)` 替换为 execution 身份停止；继续冻结原 Session/incarnation、continuationId、operationId、modelRouteRevision。目录停止归 ConversationRepository，输入同时包含原 agentDirectory 来源、原行成员与 executionId，不临时选择 Session 或创建草稿。两条入口复用同一 native stop 与既有操作登记/预算/close owner；来源不同不是两个业务事实源。
3. 主会话现有有界交互索引可投影自身与直接 child 的请求。read ref 仍绑定 host 的原 execution 来源；详情增加目标 thread 身份，回应具名能力同时验证 host 来源和原请求身份。后端验证直接父子归属、交互 revision、typed resolution；不是删掉同 Session 校验后放任任意 target。child Plan 只诊断，不可由 root 确认。禁止恢复全局 ChildInteractionStore。
4. 继续控制有独立 pending 可查的操作身份索引；普通 `read_input_acceptance` 的既有非 Pending 规则不能冒充继续保存证明。`accepted=true` 的忙碌结果保留提交事实，Unknown 与 CommittedButUnobserved 不折叠成 Rejected；回查使用原 operation。
5. 附件新建准入传现有 `ModelSelection`，从当前 Ready route preparation 同步冻结。未 Ready 按现有提交的 unavailable 语义明确拒绝，不回退 mode 默认。已有会话用后端 route；提交再校验。fixture 仅 gui preset 补 File（PDF/ResponsesInputFile/DataUrl），不扩大其它模型能力。
6. root 先裁决共享 protocol/SDK 接口；Rust runtime/control/facets 与 storage/history 重叠处必须单 writer。core 可独立处理其 crate 的合流，包含 #171 core SQLite，不与另一个 writer 共享 core migration 文件。下游适配与 UI 按已冻结接口推进。生成物最后统一生成，禁止手工拼接。

## 关键不变量与定向证据

### #163

- execution 在 Preparing/AwaitingStorage/AwaitingAdmission/Running/Stopping 均有稳定身份，建 Turn 不换编号，旧停止不作用后继。停止受理不代表清理完成。
- continuation 为 core 持久化事实，控制输入无正文/无固定提示词；普通与父消息拒保留格式、拒未知字段。claim 不清点，模型请求实际准入时消费/水位/轮次关系/清点同提交；固定 durable sequence 不在 lifecycle 锁内等待或等待自身外层 flush。
- 重复同操作同内容返回原回执，不重复唤醒或解除后来停止；不同内容冲突。替换控制不丢真实正文，只开一轮，外部停止胜出。
- 用户仅 root 可发送/继续；child 详情只读，目录行唯一停止入口，不停止父兄弟、不永久关闭、不清工作区。计数只含未关闭成员，关闭成员仍可查看。
- root hosted 请求保持 host_thread_id + 原 interaction_id + revision + operation + typed resolution；child 回答只保存决定/通知，不自动运行；审批仅释放仍存活且参数/权限代次匹配的原调用。通知 durable 后发布、稳定幂等、敏感脱敏，不唤醒 paused root。
- 禁止普通问答占用 plan_confirmation；旧历史不改写，pending 结构错误保留。审批当前 `{decision,operationId}` 编码与明确 legacy 边界不丢。
- idle 判据保留 `has_uncommitted_work`、零字节预留与原全部活动/fault门，增加 execution 门；已 durable 未 claim 的纯 continuation 不永久阻回收。新增测试 store 需显式维护该 flag。
- continuation supersession 使用同次 interrupt 返回代次，避免两次取锁之间夹外部 stop。
- 保留 main `continuation_execution.rs` 所有独特断言及 PR120 idle 红绿覆盖；主按钮矩阵、目录 stop、raw origin、child 交互断言迁到新 owner，不恢复旧 facade。

### #165 / #171

- local/URL/clipboard 暂存与排队中改选不变更已冻结 route；拒绝保文本/已有附件，已知拒绝归还本次预算，未知保原责任；后继合法准入用新 route，discard 归零，不产生 settings 写入。
- 不扩大附件白名单、字节/数量/宽高限制；安全 invalidArgument 文案不泄路径/URL/凭据，内层 cause 保留。child 提交在激活和准备附件之前拒绝。
- 五库（core、history、Calls、product、bots）具名 migration 唯一调度，旧数字版本只接管识别。preflight 完整性/归属/未来格式检查；表 current 不跳过 checkpoint migration。
- SQLite 框架默认不自动事务；原子步骤显式 `Some(true)`。Calls SQL/JSONL 不是跨文件 SQL 事务，确认日志及索引后再清旧表登记，失败可续不重复计费。
- 冷读不建库/迁移/执行，checkpoint/水位/身份同一只读快照；非零 history 无 checkpoint且无legacy严格失败。保输入绑定、context来源、问答回执、隐藏续接、账单/幂等身份。
- 保当前 HistoryStateLease 与显式 close 责任；本 PR 原关闭修复尚有已知编译与审查问题，合流不能洗白。

### #177（取代 #163 中旧归档恢复重建约定）

- 归档先终止/保存已驻留活动工作，再仅更新目录；不探测/删除 worktree。缺失或 SSH 离线不阻止目录归档。取消归档不重建、不授予新恢复许可、不切项目主目录。
- 独立安全清理核 leaseRevision、归属、活动 owner、仓库/Git 注册/分支；dirty/untracked/ignored 阻止，非 force 移除，保分支与历史。取消等待不丢已受理 cleanup owner，shutdown 真等待。
- inspection 区分 available/missing/identityMismatch/unavailable；head/dirty/changedFiles 未知为空，不以空列表当干净。只明确 PathNotFound 认缺失，保远端原生错误类型/阶段及有界脱敏摘要。
- 旧 restore 授权只在版本迁移边界退役，身份/修订/状态/历史不变，cleaned不伪装可用；不重建/删残留/清库。
- 订阅创建失败先发布创建决定再等取消，不以跳过取消/预算释放/隐藏错误解决互等。

## 生成、验证与剩余原任务

当前 children 仅源码、只读 Git、diffcheck/hash；所有 Cargo、格式、分析、测试、生成及 GUI 由 root 串行承担。迁移与静态审查就绪后统一 `cargo xtask generate-gui`，再依批准计划执行全量门禁、真实迁移与 Linux Driver 验收。旧 435/455 Client、226 runtime 或之前 workspace 绿色均不覆盖本轮合流。

主线合流完成后恢复 history-close 原返修：嵌套任务结果与借用编译错误、dirty predecessor 的 task failure 不可洗白、真正取消 owning future、确定性 ACK、supervisor/helper join、Bots stage 唯一性。最后补立即归零的 FD 验收、修正 binding 顺序后的原生 GUI 重跑、截图附件和新 head CI。
