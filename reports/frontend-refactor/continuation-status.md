# PR #120 续做状态与所有权

## 用户要求的远程进度检查点（非完成交付）

本次按用户“先把当前进度直接推一次远程”的要求保存当前源码、生成物、测试和设计文档，
不等待剩余返修完成。此检查点不是可发布版本，也不表示 PR 已完成验收。

- 最新历史关闭修复已冻结并送独立复审；主代理实际运行 `cargo check -p pl-studio-runtime --tests`
  返回 101，包含监督任务返回类型不匹配、缺少 `FutureExt` 导入以及关闭责任登记中的可变借用冲突。
  该版本没有执行到测试，不能用此前 Runtime 226 项、SQLite 内核或 256 根计费探针的绿色替代。
- Dart 完整门禁此前为 SDK 435／435、应用 455／455；后续启动绑定顺序修复经独立静审、
  定向格式与分析，以及装配回滚 2／2 测试通过，但原生 GUI 尚待重跑。
- 设计文档按 #161 的中文契约、单一权威源与编号风格适配；最新补充同样先定义关闭和启动契约，
  不把源码实现或逐次验收日志写入设计正文。
- 原生 GUI 首轮 Driver 连接失败的环境与日志保留在会话证据目录，不提交截图、日志、凭据或临时探针。
  尚无本轮成功的 GUI 截图附件，远程新提交的 CI 结果也未取得。
- 本检查点保存原先进行中的主线合并（父提交 `466bc5f45b581a1015606cb496c9b1f26f96eb75`）
  及其后的本地续做；推送前远端主线已到 `900a23c5eae44d3c34fde7319b0f57688b3d3937`。
  本次不额外嵌套合并或覆盖新主线，新增主线内容与祖先关系仍需后续核对和整合。

## 当前合流检查点：吸收 #160、#161 与 #162（尚未整体验收）

本节优先于下方历史检查点。历史记录保留用于追溯，不代表当前提交、审查或验证状态。

- 当前已提交、已推送的任务分支基线为 `8baa9432b12c5157c2b537f80f2c5e6abc6256aa`。
  工作区仍处于合入 `466bc5f45b581a1015606cb496c9b1f26f96eb75` 的未提交合并中；
  内容裁决、索引冲突解决与后续主线历史合入是不同步骤，不能用工作树修改冒充远端已更新。
- 最新已核实主线为 `586162ff08cf906aee04f1b4395800f46c38afa2`：
  `3b5ee70abcb39994ba0c095a85e2a5faed50cf89`（#160）重构独立统计纵向链路，
  `b0785b7d`（#161）调整设计文档术语与写作风格，`586162ff`（#162）规定真实 PR 截图附件证据。三者正在当前工作树中按语义融合，
  尚未形成新的合并提交或推送。
- 用户目标不变：仅重构数据层与架构，保留全部原有功能、主线新增能力及既有界面风格、布局。
  不以弱化断言、删除覆盖、回退旧门面或宣告未批准的界面偏差完成合流。

### 最新验证结论

下文保留逐次验证和返修过程；涉及“当前”结果时，以本节为准。

- 完整 `verify-client` 已通过：SDK **435/435**，应用适配测试 **455/455**。设置往返测试在主体
  返回前完成调用方自有容器的正常关闭，未禁用重试、手工取消计时器或削弱原退出断言。
- 检查点同快照读取版本已通过 Runtime **226/226**、Rust 全仓格式检查和全工作区全目标 clippy；
  缺检查点的故障用例完成真实同例红绿验证，原 16 根程序也以 17 次准确计费及正常关闭通过。
- 原生费用观察的 256/257 准入、同根共享和最后所有者释放，以及 HTTP 64/65 流限制、静默断连
  释放和 320 次新根接续，已在该版本重新通过。它们不代替真实计费材料的规模压力验收。
- 旧版 256 根真实费用压力在第 250 个根提交时达到进程的 1024 文件句柄软限制，关闭报告降级。
  当时 64 根采样显示 64 个历史库仍打开、总句柄 294；关闭后降至 14 且历史库归零。
  失败环境保留，未提高系统限额来掩盖结果。
- 闲置关闭已区分准入内存和未完成保存责任，第 15、17 篇先明确契约，core 与 runtime 均经独立审查。
  原字节计量、容量与活动／错误门不变，零字节有效输出预留仍阻止关闭。同一公开 API 回归在旧判据下
  实际失败，恢复新判据后通过；完整 SQLite 内核测试、Runtime **226/226**、全工作区 clippy 均通过。
- 修复后的 64 根加一根探针完成 65 次准确计费，原费用、全目录身份／标题及最早完整轮次和正文保持不变；
  冷读未启动执行。该轮末尾总句柄为 52、打开历史库为 7，不再与累计根数等量增长。
- 同一新版本的 256 根加一根压力也完成：257 次请求全部消费且逐根费用准确，全部原费用、目录身份／标题、
  最早完整轮次与正文保持不变；活跃空费用观察保留，无观察空条目按原策略淘汰。1024 软限制未变，
  采样最高为 66 个句柄、10 个历史库，末期为 50–53 个句柄、6–7 个历史库；这只是本次采样结果，
  不是新增产品阈值或任意负载上限。
- 最终资源关闭仍有独立缺口：两轮关闭报告虽为 `Clean`，即时采样仍各有 7／6 个历史库句柄。
  已确认历史写入及附属任务未被真实等待，连接也依赖不可作为完成证明的引用释放。保存排空不等于
  任务与连接结束，不能将文档改成允许后台稍后退出；正核定兼顾并发冷读、取消与原关闭期限的修复方案。
- 本轮曾因构建盘空间耗尽中止，未运行到测试；只清理本任务工作树中运行时 crate 的可重建 Cargo
  产物后重新验证，释放 94.7 GiB。未清理其他工作树、源码、用户数据或失败验收证据。
- 设计正文继续按 #161 的中文契约、单一权威源及章节编号维护。最新检查覆盖 37 份 Markdown、
  453 个本地引用，未发现失效路径或锚点。GUI 原生旅程、截图附件、Git 合流和新提交 CI 尚未完成。
- Linux 原生 ACP 首轮已构建并启动真实 GUI，但 Driver 扩展未注册，连接超时，未执行业务交互、
  未取得截图。隔离错误日志证实共享启动先创建普通绑定，随后官方 Driver 扩展二次创建绑定触发断言。
  已先同步第 25 篇的单次绑定与同执行域契约，再最窄调整启动顺序；定向格式和分析通过，独立复审
  及原生重跑仍待完成。失败旅程经中断后已确认所属进程退出，环境和原始失败证据保留。

### 统计实现取舍

| 边界 | 保留与吸收 | 不采用的做法 |
| --- | --- | --- |
| 原生协议与读取 | 保留 #120 统一产品协议、固定来源作用域、真实会话与调用样本身份、有界页与文本读取 | 不并列引入 #160 的桌面专用统计事件流和第二套登记表 |
| 发布与材料 | 吸收 #160 的轻量发布状态与不可变材料分离；未变材料引用保持稳定，状态变化不重读全历史 | 不把业务版本、投影版本、材料版本或 ACK 混用 |
| SDK 所有权 | 统计形成独立领域仓储，内部完整物化后原子发布最近完整快照；保留可见租约、失败与真实关闭责任 | 不把半页或未知状态当成空集合，不在适配器合并缓存，不保留旧分页呈现入口 |
| 相邻领域 | 账号额度和根会话费用保留独立职责；会话费用拆为独立所有者，模型参考摘要回归模型领域 | 不整删原混合的 `account_usage`，不使费用消费者订阅全局性能历史 |
| 界面 | 保留主线 760 表格／卡片断点、始终换行的筛选区、惰性历史列表和原诊断键 | 移除 #120 未获批准的 620 单行切换及界面自动分页结构 |

这些取舍先写入设计契约，再实施。它们是职责与资源约束改善，不是已量化的内存、速度或性能收益。

### 局部交付与审查边界

- SDK、应用与原生统计的未决所有权、单侧重同步、最近完整快照和同步失败呈现返修均已获局部静态批准。
  HTTP 订阅观察租约、容量及断连释放返修也已获认可；完整筛选集合、非空模型选择保持及在途 ACK
  与关闭交错的测试已通过静态复审，尚无当前版本的统一运行通过证据。
- ACP 目录已从整份设置快照迁入原 Configuration 固定作用域，账号写入改用原调用所有者的受管调用。
  原生空配置捕获、SDK 严格回执与目录来源、应用适配及相应 SDK／表单／FRB 测试均已获静态批准。
  普通传输失败不能证明未提交，未知操作不自动重发；结果可重复查询，不把查询次数等同写入次数。
  当前统一生成已完成，运行验证仍在逐项收敛；局部批准不能作为动态验证通过。
- 账号“不计费”开关按主线语义、位置、诊断键及间距恢复。ACP 已保存后的身份解析、连接检查、
  失败重试与取消分别保留真实阶段；真实表单测试覆盖名称、导航、已保存事实和不重复保存。
  新增用例尚未取得运行通过证据，不能仅凭源码和格式检查宣称已验收。
- 关闭链的同次重复原生重试、观察期限丢失重试责任、有限期快照覆盖无界收束均已修复并通过静态审查；
  最后补充的公开重试结果断言已获复核，不接受仍含待完成责任的快照。旧 Timeline 断言未削弱。
- 原受管安装 Driver 旅程及摘要契约测试已恢复；当前目录投影、采集及测试支持接缝已获静态批准。
  新增真实账号页测试的集合比较与读取屏障返修已通过独立复审，尚未运行当前测试或原生旅程。
- 附件能力和设置首屏保真修复的独立审查发现跨来源就绪误判、初读失败无法恢复及异步平台交互后
  漏验原能力三项问题，返修均已通过静态复审；URL 弹窗能力变化订阅的补修也已单独批准。
  保留旧错误页样式，以退出后重进设置进行显式读取重试，不增加按钮或额外布局。
- 零问题交互的“非空提示正文丢失”尚未得到生产来源证据支持：旧生产桥接从问题列表拼接正文，
  零问题时原值即为空；非空样例来自旧演示数据。当前不据此臆造新的协议或持久化提示字段，
  原输入行数、非空提交及类型化来源约束继续保留。

### 文档与验证

- 以 #161 的标准中文术语、单一权威源、章节编号及契约写法适配设计文档；对没有本 PR
  独有差异的文档采用上游内容，对有差异的文档保留原约束后改写，不恢复旧全局客户端架构。
  进一步修正了重复术语、未编号小节和章节顺序；配置发布权威归第 20 篇，SDK 固定目录消费归第 25 篇。
  第 24 篇进一步收敛为测试责任、五层证据、原生人工判据及规模计量；原 870 行的场景参数和细节
  完整保存在[验收条目保全清单](./acceptance-inventory.md)，还原后的 SHA-256 与搬移前完全一致。
  这不是删测或缩小验收；清单中的旧“已验证”原句不代表当前版本通过。
  第 25 篇合并附件读取与阈值保存的重复说明，共享壳层几何及诊断身份归第 19 篇唯一维护；
  清除旧全局状态的正向描述并消解启动顺序歧义。行为数值、来源身份、错误和关闭责任保留。
  设计、根文档与本轮两个报告的机械检查覆盖 37 份 Markdown、452 个本地引用，未发现失效路径或锚点，
  编号检查与差异检查通过。独立文档复核未发现契约遗漏或冲突；这不代替最终实现与运行验收。
- 此前纯 SDK 390 项通过和 GUI 门禁通过只覆盖当时版本。新统计类型、计费字段、视图模型和
  模型摘要归属调整产生新的生成输入；全部手写局部静态审查收敛后，统一生成已成功完成，
  307 个生成 part 的来源／声明核对未发现孤儿，两个新视图模型的生成文件已产生。
  Dart 格式化检查了 1,805 个文件，调整 70 个文件；Rust 全仓格式检查已通过。
- 生成后的首轮静态分析未通过：SDK 报 44 项、应用报 40 项，主要为迁移后的导入缺失、
  测试类型及少量 lint。最窄修复与复审后，SDK 第二轮分析已无诊断；应用剩余的 3 处空安全警告
  已修复并通过对应文件的定向分析，不恢复兼容导出、不删除断言或关闭检查。
- Rust 全工作区、全目标 clippy 已通过；模型、启用 SQLite 的内核和运行时测试均通过，
  运行时为 225/225。bridge 首轮 15/16，修正未挂流所有者关闭身份的陈旧期望并独立复审后为 16/16；
  生产身份与关闭行为未改，原失败记录保留。
- 首批 7 文件 Flutter 定向测试未通过：统计 7 个用例明确报告物化未完成，ACP 2 个用例明确失败，
  另有新 UI／设置离开用例在 6 分 46 秒取消时仍未完成。取消后已核对所属进程全部退出。
  日志中的 FRB 4 例与安装摘要 24 例已各自完成，但不代表取消批次整体通过。
  统计替身的固定身份接线、ACP 读取基线及主题依赖、新 UI 等待点分别由原作者修复或诊断，
  不把取消后的临时目录清理异常倒推为原等待原因。当前 Dart 完整门禁及 GUI 仍未完成。
- 后续改为逐文件、带明确进度的运行：Driver 查询当前 16/16 通过，设置离开保护 7/7 通过。
  附件能力首例在补齐官方文件平台注册后通过；整文件为 3 过 2 失败，剩余为路由选择被拒绝和
  拖放文件读取屏障未到达。常规设置 5 例在测试环境尚未实际监听时发布基线而失败，正在局部返修。
  统计身份材料修复后不再阻塞于物化，先得到 6 过 4 失败；未构建的惰性历史行现通过官方有界滚动
  触发构建后保持原身份断言，完整集合仍由视图模型精确断言。独立复审后正式重跑为 10/10。
  ACP 清理使用既有有界队列驱动后，正式文件完整结束，先得到 7 过 1 失败；
  最后一例在关闭编辑器后重新读取自动销毁的保存视图模型，修复改从原操作与取消后的目录证明保存事实。
  独立复审与当前版本正式重跑均已通过，结果为 8/8；此处使用脚本化原生响应，不代表真实磁盘持久化通过。
  上述失败均保留原断言含义，不靠增加等待上限或删除覆盖通过。
- 当前源码的远程辅助进程已按正式入口安装成功；SSH 环境具备伪终端和 Xvfb 所需工具。
  这些只是原生验收准备，不代表 Server、GUI 或真实供应商业务已通过。
- Server 构建成功，但隔离启动在 Templates 路由装配阶段因重复 `POST` 方法路由而退出；
  首次费用观察的 HTTP 容量探针未能执行，所属进程组已退出。按锁定官方组件契约逐处理器注册后，
  八文件修复通过独立审查，287 个声明处理器均保留。重新构建并运行同一隔离探针已通过：
  64 条流各收到基线，第 65 条返回可重试的 `overloaded`／429；断开一条静默流后约 12 毫秒内
  再准入，另外 320 个不同根身份连续断连再准入均成功，公开会话目录保持不变。
  Server 以 0 退出且所属进程组已回收。HTTP 64 流闸门与原生 256 个费用观察闸门独立计量，
  此结果不代替原生 256/257 与真实费用材料压力验收。
- 随后公开 Runtime API 的独立探针验证了原生容量：1,024 次纯费用查询不登记观察；持有全局
  汇总与历史租约时，256 个不同根观察均成功，第 257 个明确可重试拒绝。同根双所有者共享额度，
  释放其中一个仍满额，释放最后一个后才准入新根；注册集合与无需求空条目回收均精确匹配。
  公开会话目录保持不变、没有活动轮次，运行时真实关闭报告为 Clean。
  该探针仅验证空根的准入和释放，不证明既有冷会话绝不激活，也不覆盖 256 个真实费用根的淘汰压力。
- 本轮正式 `verify-client` 已完整运行至 SDK 测试失败：1,096 个源码文件的边界检查通过，
  625 个 SDK 文件的格式检查无变更，静态分析无诊断；SDK 测试为 401 过、33 失败，应用测试阶段未启动。
  失败分为生命周期／草稿 10 项、ACP 配置 18 项、统计 5 项，分别交回原作者按真实证据返修；
  ACP 配置连续超时不能推断为编译等待或机器负载。当前仍不具备完整 Dart 门禁通过证据。
- 第二轮 `verify-client` 的 SDK 测试为 433 过、2 失败：ACP 配置和统计的上述失败已消除，
  剩余是新增关闭身份回归未进入预期同步回调，以及部分取消用例过早读取阶段快照。
  两项由原作者按实际进入屏障修复并通过局部静审，不改变原身份、错误、预算和真实关闭判据。
  Timeline 观察边界另补齐同一已接受连接的 open/page/detail 计数，并覆盖提交与创建来源两类路径；
  不因已存在界面连接而跳过读取检查。计数基线在执行／配置确认后接受当前待打开连接时取得，
  不冒充 Timeline 就绪证明。修正后的正式 SDK 验证已为 435/435 通过，应用测试阶段也已实际执行。
- General 设置的正式五例已全部通过：异步清理回调中的断言改用官方同步入口 `expectSync`，
  原 matcher、关闭结果与次数均保留，单点差异通过独立审查。Composer 路由用例已通过；
  拖放用例的真实文件系统操作改在明确的真实异步区间推进，门控回执仍由测试显式给出。
  同一候选用例的正反两分支通过后，正式移植已获独立审查批准，正式文件五例也已全部通过。
  新增关闭身份回归的缺陷敏感度检查已真实触发预期身份失败，但首次错误版运行还暴露测试提前
  抛出断言后跳过原生清理回复的问题；测试改为先冻结身份判据，再收束全部已接受的关闭工作、
  最后断言，并通过独立复审。第二次临时错误版仅触发预期身份失败，恢复正确版后同一用例通过；
  两次均已校验生产文件恢复原哈希，未改变测试判据。这证明关闭 Future 的身份保护，不证明重复原生副作用。
- 正确版完整 `verify-client` 已越过 SDK 阶段，应用适配测试为 451 过、4 失败：一处工作区测试
  缺少独立会话费用仓储注入，一处账号测试缺少 ACP 认证仓储注入，另有目录选择的原生打开观察
  边界及设置往返等待超时。失败已按互斥范围交原相关作者处理，尚不具备完整 Dart 门禁通过结论。
  账号用量用例的 ACP 仓储注入修复已获独立批准，正式文件五例全部通过。其余三项修复也已
  通过静审；定向实跑中，工作区目录两例与智能体导航九例全部通过。设置往返用例已越过原目录
  读取阻塞，但退出后仍有 Riverpod 重试计时器未收束，正按实际调用栈继续定位，未关闭计时器检查。
- 真实费用小规模验收暴露了新的原生发布缺口：一次模拟供应商调用已结束，模型汇总与历史各一项，
  会话费用却在 120 秒观察内未出现。此前同例隔离调用库确有 `USD 0.000059` 的可靠会话累计费用，
  最后一次复现中只有一个供应商请求，运行时正常关闭。这不是价格计算或消费者分页失败；
  调用计费记录与后到的可靠历史摘要独立落盘，原发布任务未被后者再次唤醒。
  第 18 篇已先补充受理、持久化与自然发布契约，第 25 篇补充原所有者的显式重试及关闭责任；
  新条款继续使用 #161 的契约写法，不加入源码位置、操作命令或测试过程。
  原作者已交付复用存储进度通知和受监督后台任务的修复。首次独立审查发现摘要替换失败可能丢失
  旧受理责任、读取失败后无关历史写入反复触发整库读取，以及停止拒绝漏发缺口通知；第 18 篇已先
  补清相应契约。后续复审又发现重复标记同一缺口会通过共享通知触发自身重读；改为仅首次状态
  跃迁通知后获批准。Runtime 全目标 clippy 和 Rust 全仓格式检查已通过。
  真实小规模程序随后观察到发布继续推进；首份合法空累计摘要不是最终计费材料，等待条件补为
  可靠保存完成且计费材料可用，金额与用途判据未改。重新运行通过：第一笔在下一笔提交前自然
  显示 `USD 0.000059`，后继调用后原费用不变，活跃空观察保留，运行时正常关闭。
  费用修复版本随后通过 Runtime 225/225、Bridge 16/16 及全工作区全目标 clippy。
- 真实 256 个费用根压力尚未完成：前十次调用发布成功后，第十一个根的公开调用报
  `history exists without a recovery checkpoint`，程序退出并正常关闭运行时。缩小至 16 个根、
  仅补充调用阶段上下文后再次复现，实际栈定位为第十一个根提交时的历史检查点读取，
  不是创建失败或费用发布停止。失败环境的历史库最终均保有一致检查点，未发现持久损坏证据。
  现有检查点与历史水位分开读取存在跨提交窗口；第 17 篇已先明确同一只读快照判定的契约，
  同时保留真实缺失检查点的错误与迁移保全要求。最窄存储读取修复已获生产逻辑复核，另补一项
  无迁移来源、无轮次而非零水位缺检查点的真实 SQLite 故障回归。首次红测因测试辅助函数返回
  类型错误未能编译，零用例执行不算红测；临时生产变异已恢复，单点类型修正已交付复审。
  类型修正获批准后，临时放宽损坏判据的同一用例确实失败；恢复正确生产文件并校验哈希后，
  Runtime 全套 226/226 通过。同一 16 根程序也已通过，17 次调用均准确计费并正常关闭；
  这一结果不代替尚在进行的完整 256 根压力验收。
- 正式 `verify-gui` 已通过：canonical 再生成稳定、Rust 格式检查通过，应用与 Driver 的
  1,098 个文件格式无变更，Flutter 静态分析无诊断。这不代替原生 GUI 人工旅程及截图证据。
- 未执行本轮 Linux 原生 GUI 人工验收，未形成新提交、推送或新实现版本 CI 结论。
  整体工作流仍为实施与局部审查阶段。

## 历史检查点（非当前状态）

## 基线与证据范围

- 批准计划身份：`sha256:fb87b0ff6d6848b9f15f6851c1c7c77a04eb1875f09a9ee09cb4173b29b00c37`。
- PR 实现：`07bd17550475364419c6307ac5f1dea4ddbadcd2`。
- 冻结 main：`0226f8060a6af8a778ac8685633707b497c8c8a2`。
- 共同祖先：`d3bc74189b81dd8ad50ce71caa8aaaef4e3db525`。
- 续做工作区开始时干净；采用保留两侧提交的非提交式合并，未改写或推送远端历史。
- 合并最初产生 65 个冲突路径（16 个内容冲突、49 个 modify/delete）；不能仅按 ours/theirs
  全选解决，删除的旧路径所承载的 main 新业务须迁移进新领域与呈现结构。
- 仅做 Git、源码、文本与差异检查；旧报告的编译、测试、原生和文档 CI 不覆盖本次输入。
- 本轮按用户要求已向 PR [发布进展说明](https://github.com/ZR233/anywork/pull/120#issuecomment-6382475303)，
  明确区分本地静态成果与未推送代码。远端 PR head 仍为上述 SHA；本地仍有 43 个未解决
  索引冲突项，未绕过门禁形成检查点提交。
- 新观察并抓取的 main 为 `6da843d0c6827c83222b0e558f4576e1f40c0d21`，较原冻结 main
  增加五提交；当前 HEAD/MERGE_HEAD 不变，**尚未合入这五提交**。新增保留范围见下节。

## 新上游 main 的合流边界

精确范围为 `0226f806..6da843d0`：321 个文件、76,228 行新增、3,742 行删除，包含生成物，
不能当作手写规模。独立只读核查及 root 定向 diff 确认以下业务必须保留：

- `809ed172`（#145）：统一 Agent 定义及 Agent/Mode 来源冻结、同代 Profile 的严格 spawn
  schema，以及飞书 Markdown／CardKit 流式卡片的真实发送与未知结果责任。
- `ba703abb`（#149）：Skill 调用级发现与冻结来源授权；迁移原准备能力，不回退 stale catalog。
- `0310c8d1`（#151）：Core 恢复后保存屏障的测试／设计前提，恢复提交不等于新 durable fence。
- `891aa674`（#152）：机器人跨会话交互显式决议，共用原 resolve 边界，不扩大成自动批准。
- `6da843d0`（#143）：Antigravity 1.4.1 ACP 独立配置、schema25 迁移、受管安装与认证；原
  auth/install owner 的取消和真实 join 须纳入本 PR 唯一 shutdown DAG，不塞入 Conversation。

上游未改本片 Observation、WriteBehind/AgentOperations/evaluation 或 Stop 核心接口，
G2b1 与 Stop UI 可继续；共享 assembler、Agent/Mode/Skill 来源、配置迁移及 shutdown
ACP 阶段由 root 后续串行整合。当前活跃 merge 不嵌套 merge、不 reset/abort，也不以
旧 facade、双入口或删除新业务消解差异。已批准不受影响范围保持，实际交叉增量另验另审。

## 已确认缺口与已保留成果

- 附件 native/FRB/HTTP 的同一原文件有界读取已由 R1 补齐并静态批准；生产 Dart adapter
  与 SDK binary cleanup owner 也已静态批准。统一生成、运行及端到端验收尚未执行。
- Drafts 的具体 Repository factory 已经多轮局部静态审查修复并批准，root 核验后登记
  原地成果与窄 factory 导出。生产常规 main 入口仍缺失，真实装配与执行验证尚未闭合。
- 新 Freezed/Riverpod 输入和旧生成物尚未统一生成、清孤儿；这不是允许手改生成物的理由。
- Models 的真实 native read scope 与 bridge owner 已存在，保留后核对完整消费者，不重复重写。
- main 的飞书协作、模型启用/分发/冻结路由/最终评价、6.26.0 发布文件和 CI 改进必须保留。

## 所有权与依赖

| owner | 实施边界 | 前置与交付 |
| --- | --- | --- |
| root | 设计、共享接口、合并索引、提交推送、生成与最终验收 | 单 writer；先文档后新实现 |
| R | protocol/runtime/手写 Rust bridge/Server | 消解 native 冲突，补真实 native 接缝；向 A 发布类型与入口 |
| D1 | SDK Conversation/Drafts | 沿具名 ports 补 factory/提交/ledger/关闭；对齐真实 native 受理语义 |
| D2 | SDK 配置、模型、模式、工作区、资源、更新及公共导出 | 保留 main 业务；只发布窄领域能力 |
| A | 手写 FRB adapter/demo/fake | 消费 R 与 SDK 真实接口；不写生成物 |
| U | Conversation、Settings、App/Workspace 的互斥子范围 | 消费 SDK 领域 API；装配依赖 A/D1 |
| C | 测试、Driver、诊断、AST/xtask/CI 消费者 | 只迁移稳定接口，保留真实失败传播 |

以下多个独立切片已经局部静态批准，但完整领域及整体集成仍未完成。局部 owner 的实际派发目录、输入身份和审查结论随交付更新；
共享文件不并行写，执行者不改 Git 索引或提交。root 在局部审查通过后登记冲突解决；
未审代码不得作为完成成果提交。主线合并不是把原 PR 的全部已有实现重新判为已审。

## 当前局部交付

- R1：40 个原生手写文件，内容身份
  `5392fe770c33c08b01893c431d85ab4d84d93db8bada7107316ed5947b347724`，独立静态审查批准。
  root 复核 40/40 文件 hash 后登记索引；无 commit、无编译或运行通过声明。已消解 9 个
  native 冲突，提供附件 binary runtime/FRB/HTTP，保留 main 的 enabled/botId 等字段。
  root 已将旧 session-layout 迁移测试改为经现有 catalog/path 解析读取实际落盘字节，保留
  原迁移断言，不恢复 whole-read 兼容 helper；测试执行仍延期。
- D2a：44 个 SDK 文件已完成三轮审查修复并批准，root 核身份后登记索引，内容集合
  `cb456ae68d64e691688c1cd912f76ee65f4714d9da92f8d7e61a169989b9f684`。
  包括启用模型、稳定命令意图、分发默认值、精确模型详情来源与 Agent 选择 ABA 防护。
  对应精确模型详情 native scope 的后继已静态批准，FRB/HTTP/生产 adapter 仍待迁移，
  不可用旧 facade 替代。
- D2b：SDK Configuration 的 Start 专用读取接口及 Repository 链六文件已静态批准，
  root 核 6/6 文件身份后登记索引，并补公共导出；内容集合
  `6000b038fd631b2f6fadde6b2f7584b7045b46b3ff7efb98a33ec39bb7654492`。
  按续做合同 §8 消费原配对，不把原生路由策略搬回 Dart。
- D2c：已续派 SDK Configuration 命令调用资源改造，按续做合同 §9.1 接收原调用，
  同步原 targets 并观察后清理；已知拒绝的 CAS 重试须先 Clean-close 旧 call。
  六文件增量已交付并获 fresh 静态审查批准，身份集合
  `f95bd19f7868c591e95e6433de8d197163b1da2df2b6de5ceadae0d3022bcffa`；
  root 亲核完整 32 文件及六文件增量后登记索引；不改变已审 Start read 或公开业务动作。
  已续派原 C 执行者迁移 owned-call fixtures/测试，并消除测试 recorder 与新资源接口同名。
  退出封闭 Models/native 读取后，迟到结果不能假报 observed；§9.1 明确保原证据与真实
  Unresolved/Degraded，不新增消费 lease 或重新开放全局读。该跨域边界仍待最终实际验收。
  C 的后继源码审计发现一次公开 cleanup retry 可经两个收束层重复重试同 call；root
  已明确单次显式 retry 的责任；原 D2 四文件最窄修复已获 fresh 静态复审批准。
  该次完整 Configuration32 身份
  `e748823221938f1e0c276efeebf4d6fe1fd94058a4d56cba3bd6a191585bba8b`，
  root 32/32 核验后仅登记本轮四文件。随后已按 §12 续派 Profile/reload 三 port 与
  调用 owner 的 SDK 迁移；五文件增量现已获 fresh 静态批准，完整 Configuration32 身份
  `8a495a86d29043164219bd2887fca10101308b3d27c56b48358297c78e0003c7`。
  root 32/32 核验后仅登记五文件；保留原业务动作、三 target 观察和无 receipt 的正常
  reload，未完成的 native/adapter/测试消费者不由本批准替代。
  后继 C-Profile 回归源码揭示公开 `observed` 的同因风险：receipt 的 Settings/Profiles
  stamp 已覆盖而 Models 同步失败时，原 Operations 仍可能提前置 true；call 自身仍
  Unresolved。root 已先明确 §15，在原 Operations begin 增加默认关闭的附加身份门槛，
  D2 共用 Configuration begin opt-in，只在全部原 targets 同步后发身份证据。联合三文件
  已获 fresh 静态批准并核验暂存，集合
  `fbafd4965253ba29ac21e6dc6daa62b33ec661a7df7790b8aa6ce50f6bdf399f`；
  最新 Configuration32 身份为
  `6eddfa26c969145bdb99b1c28431ffa9fea35fec853ab248a6b43972567c9be3`。
  测试 oracle 未弱化，相关测试增量仍在独立复审流程中，尚无运行证明。
- D1a：附件 ledger/record 六文件已修复逐 ID 计费及 overflow debt 下的准入保护并批准；
  内容集合 `3ad323bd96f4325e0b5ac993d161528b2d5dc69d0acf73b07ac7d68411dae8de`。
- D1b：admission/create ports 及 Start 两个 nullable override 的五文件已批准，内容集合
  `61eec62e50df05ea6729febb29a12254811665bbf3b04cc60678c62a6d1d548e`。
  root 补窄导出。D2b 批准后，完整 Drafts factory、显式 Start 准备状态及提交／清理
  首轮已交付 12 文件，身份集合
  `e96ebac1ac8e21e12afe959f1e5bc33e3435bb106ed25d5f39dc13576dc9a446`。
  静态审查阻塞：普通 lifetime seal 会取消已受理 archive capture 的 metadata 准备，
  Repository cleanup 未加入 capture 真实工作。当时交原执行者返工，未登记该版索引或
  factory 导出；后续审批与消费状态见下文。
  三文件修复现已交付并进入 fresh 静态复审：capture 接管 metadata，Repository 加入
  capture 清理，ledger 延后全局引用释放。新版完整 12 文件清单身份为
  `750c00676ef590847ff689d7f97cc3470b843edfd225dc53f1073f2535be409c`；
  复审仍阻塞：捕获/等待无关 Start 路由，以及任一 unresolved capture 全局阻挡草稿和
  附件引用清理。该版未获批准，交原执行者收窄等待与保留责任，不以修复自述代替验收。
  第二次四文件修复已交付，含必要的 entry 引用谓词；完整受审 13 文件身份为
  `67526c076fd92ee5a9ff4ee90df8cc58e4a58564b4d84a7e913debb00ef9b77f`，
  该轮复审又阻塞最后一个重叠 capture 释放引用后的实际附件 cleanup join。原执行者
  两文件修复后，新完整 13 文件身份
  `1c3283a570f525a570e4e2f6837b4932e27eb50f3601caae0503d68b84223adb`
  已获 fresh 复审批准；root 13/13 核验后登记累计增量，并补 composition-only factory
  窄导出。新编辑保护、逐引用隔离与真实 entry 清理都保留，公共 factory 回归源码的
  后继已静态批准；其揭示的生产 Turn/input 绑定缺口另按新 §16 修复，不外推原批准。
- D1c：两文件 binary cleanup 修复经最终 fresh review 批准，root 核两文件身份后登记
  索引；内容集合 `e3ae7f947222604c83ff71bf1377ec1614f704fbe2f93db57e2c99245f184e46`。
  scopeId 独立于完整 descriptor，原 handle 可恢复清理；删除无界 retry 诊断历史。
- A1：四文件真实 FRB binary adapter 及 enabled 转换经联合审查批准并登记索引，内容集合
  `194adcbe129a9ffc89aed71ff8073e59ffbefcfb00a31c4f7f9b80a4be0cfdce`。
- S1：ConfigRuntime 原发布边界的 Models 来源捕获、pin、独立 metadata 与锁外通知六文件
  已静态批准并登记索引，不伪造 Ready，也不以 watch latest 重建成员历史。
  精确详情后继核实原无密钥投影不足以重现旧执行资格，root 已先同步 §13，并将旧
  admission 的纯判定提取为单一共享入口、迁移原两个调用。原 S1 已交付 Models
  material 的最小无密钥资格捕获与版本比较三文件，明确未写 Configuration/Profile
  命令或 source-status；连同 root 两文件前置已获 fresh 联合静态批准，root 核九项
  身份后只登记五个源码文件。详情 scope/运输仍是后继，不据此声称完整 Models 已闭合。
- R-Models：依赖 S1 的真实 catalog feed/source-status runtime read 与 FRB catalog feed
  九文件已静态批准并登记索引。source-status FRB wrapper、HTTP 及完整 Models adapter
  仍待后继；不能因此声称 Models 全链完成。
  §13 资格前置获批后，root 已先补 §14 和两个共享 protocol DTO/module 文件，随后
  续派原 R-Models 仅实现 runtime/models 精确详情 scope。八文件实现与 root DTO2
  已获 fresh 联合静态批准，root 核 29 项身份（含未变及前置）后精确暂存十文件。
  同次原资格、性能材料与最近十次评价窗口已接入，不提前声称 FRB/HTTP/Dart 已完成。
  原 native 执行者已只读核实运输缺口与实际目录权限，root 先冻结 §17 后续派实现
  Models FRB 新叶、Catalog retry 转发、独立 HTTP transport 和三个 protocol 叶的
  十三个 schema derive。32 路由复用原 1 Stream / 7 Control / 24 Normal 分类与
  原额度；read 不强绑活 feed。共享模块/StudioOperation/Server 初始化与退出 hooks
  由 root 单 writer 接入。运输层二十文件现已交付并冻结，集合
  `9d5d9595a42ad67664215eebf40b8c4ac499f9a87104d38f45d44d659890aa25`。
  Profile 前置批准后，root 已核验并应用六个共享根接缝，保原七十九个操作 ID，新增
  三十二个真实路由操作；同一退出期限及原 finalizer 不变。二十文件与六根文件已获
  联合 fresh 静态批准，root 核全部 before/index/after 与七个保护根后精确暂存。
  Dart Models 生产 adapter 尚未完成，不外推生成、运行或 Models 全链完成。
- R-E：原 native writer 已交付真实 Execution projection、具名读取、原 source pin 和
  FRB/HTTP 运输 47 文件，内容集合
  `09ae6672066621208f67d1f9e74a62861df195d9da2a9913469925ae81e3fe2a`，首轮独立审查阻塞：
  驻留 Interaction 解析不得回填未实际发送的 exposure，HTTP feed/read 关闭路由须先核
  capability 类型。原 writer 已交付四文件修复，其他 43 文件不变；新版完整集合
  `f42d5d278e5aaa4e23180ea80e1ddfbe0c57c6a31fde1619650dee10aab2d464` 已经 fresh
  复审批准。root 复核完整 47/47 身份并登记索引，保留初审与修复审查的范围边界。
  Execution/Authoring 保可靠 FIFO64/8MiB、单 Data256KiB，不采用 Metrics latest 覆盖。
  R2 命令 owner、真实创建 input/receipt 绑定和 HTTP multipart A 已完整交付 43 文件，
  清单身份 `487482586d41008272fa25f334e9cfcf771214c39ae33d5192c4337589802fdb`，
  初审仅阻塞 FRB mode 输入被 native trim 放宽。单文件修复恢复原严格校验并保持 HTTP
  旧语义，新版清单 `04ddc372cbd6c9ffe4dda516feb66617b21e2860637e87e015d287bccdb90c57`
  已获 fresh 复审批准，root 43/43 核验后登记索引。旧 28 文件部分交付已失效；已审
  R1/R-E 的必要共享入口增量随本轮复核，创建 source 不借普通 live 冒充。
  A-R2 真实 admission/creation/source adapters 七个新增文件已交付、获 fresh 静态批准，
  root 核七文件及 12 个保护依赖后登记索引，集合
  `386b4905c6ea937d31f01769df3b4c53c60e837903aa18299c9fe504f860b71c`。
  生产装配与统一生成仍未完成；不把静态批准当 FRB 运行证据。
- R-Configuration：已交付 55 个 Rust 文件，首轮静态审查阻塞；身份清单
  `16e3b646897606252d8012aa658249a496c8ad2f081ea1e71ca374b97716c4d6`。
  包含原来源／配对、配置/角色/Start reads、八类原提交 mutation 与 FRB/HTTP 域模块。
  初审时 root 的模块/初始化/退出尚未挂接，现进展见下条；reload 三 target 回执仍依赖独立 Profiles
  typed source，不伪造其来源。原 S1/Models 受影响范围须随本单元审查。
  本轮待修的是命令原材料保活、结果关闭后的身份／防重放责任、满额已有请求加入，以及
  FRB 按操作身份登记。root 已先在设计与 §9.1 明确调用资源和有界保留合同，再续派
  原 writer：OperationId 与 callId 分离，原提交材料强持至显式关闭；防重放保证限于
  retained 生命周期，不以无界强历史、永久 tombstone 或持久化去重表规避生命周期问题。
  §9.1 返工已交付 56 文件（原九文件修改、一个新增、其余 46 文件身份不变），完整
  SHA 清单身份为 `2853156d4ecc349ffc2a1dbf7be93495c14f0361378fe1490d2a8341f42a08d4`，
  已获 fresh 静态复审批准，root 亲核 56/56 后登记索引。新的 BridgeRuntime
  字段/init/seal/join hooks 已交接给 root；R2 批准后的实际根接入进展见下条，仍待复核。
  同一 writer 现已续派独立 Profiles source/feed/read 前置，先按新增 §10 同步设计；
  此后继 35 文件已获 fresh 静态批准，清单身份
  `74d201d4c05567eb6bca8a73cff2bcfe59f3c1a0d562c109974c30406ace1af6`，
  root 35/35 核验后登记增量。公开 Profile/reload 调用资源已按新增 §12 先同步设计，
  再续派原 native writer。24 文件首审被 result/query 与 close 缺少共同登记屏障阻塞；
  五文件最窄返工已交付，其余十九文件不变，修后完整清单身份
  `1fb780b436863a5b4e1f243d9e05710cd488616f2e0adb86b1a85d2db361d55c`。
  新 fresh 审查核完整二十四文件后，唯一阻塞 Bridge 退出 deadline 取消 close waiter、
  最后查询随后归零时，缺少 owner 级未完成释放及 RetryClose 诊断。全局 deadline issue
  仍阻止 Clean，不把该缺口误报为假 Clean。原执行者已交付单函数修复，复用真实
  task settled 事实选择 RetryClose/AwaitCompletion；完整二十四文件新清单为
  `14626f163d960f93cbc5460ee2081914d7c555b3a0fbfcedb950e9a10c2f34f8`，
  已获新的 fresh 静态审查批准，root 核二十四项 before/index/after 及八个根保护项后
  精确暂存；仍未运行，不外推 legacy 消费者、Dart adapter 或全链完成。
  不需新增根 registry/退出 hook，原八类 wire 保持；并行 root Authoring 四文件
  已独立核对归属，其余八个根保护文件不变。
- root Configuration/Profiles 接入：R2 批准后已实际修改 11 个共享根文件，接入 runtime sources、
  BridgeRuntime registry、Server router/分类和同 deadline 退出收束，并补 StateOperation
  schema derives。两来源材料只在原 finalizer 满足 Clean 前置后最终释放，不把局部
  read-scopes 清理成功当作外部 transport 已收束。独立静态审查已批准，root 复核
  12 项身份（11 修改、1 保护）后登记 11 文件；仍未编译，不外推全链验收。
- U-Accounts：新 accounts 分域的模型启用、计费类别及精确模型资料／评价消费已交付
  13 个改动文件（8 新增、5 修改），其他 14 文件保持，已获 fresh 静态审查批准。
  root 复核 27/27 文件身份后只登记本轮 13 个改动，身份清单 SHA-256 为
  `636ca45db427a85d0d535850cbe2d6ac2ec6d52e712112bcf6b44484b19bcbc3`。
  现 SettingsScreen 已直连新 AccountsConnector；保留编辑／阈值／额度与 dirty 生命周期，
  不重复建立入口或恢复旧 facade。原生配对详情仍是后继前置。
- A-Execution：七文件真实 Execution feed、五类具名读取与 exact Interaction resolve
  手写 adapter 已静态批准并经 root 7/7 hash 核对登记；内容集合
  `2726194de7f04584df03850531b55ea136e70dbc91264318553254d36f530ad2`。
  其他 Thread facet 与完整端口装配仍需后继，不以 Unsupported 补空缺。完整 Turn 历史
  当前保留 native/HTTP 实际入口；已核新旧手写 Dart 未消费该独立入口，不以 Timeline
  内容页冒充它，也不因缺少 SDK 方法就凭空新增未确认的 UI 功能。
  后继 A-Authoring 已交付十一条路径（五新、五改、一旧 helper 迁移删除），集合
  `7df4acc456edf74c314d9afff33d4ab3d62ca18467a088f28bbfda0915f0ef9a`，
  首轮 fresh 静态审查要求保留原 Execution 的 typed failure correlationId；共享 helper
  抽取不应改变这些可观察诊断。原执行者已交付八文件最窄修复，当前完整十一集合为
  `53e73c9ba90afbec86acd26f84b13f11b7e57f45bb84b579c6984f545262abe7`，
  已获新 fresh reviewer 对修后完整范围的静态批准，root 核十一内容/原索引、二十三个
  同目录未变项及一百九十二个其它保护项后精确暂存；并行 Turn 证据四个 SDK 文件与
  root 两份设计/合同文档另列归属，不纳入该暂存或冒称未变。复用 Thread
  feed/read 公共机械逻辑影响原 Execution 接缝，须随本轮重审，不冒称原七文件全部未变；
  created source 仍保原 fromHandle 入口。
- R-Authoring：root 已先同步原 canonical 扩展、可靠提交与具名读取约定（§11），再
  续派原 native writer 补 Todo/Plan/Workflow 的 native/FRB/HTTP 链。28 文件现已交付，
  集合身份 `1113ef41e3e23b29c5536e53f218108dc44b2c18097b611e35b55ecd9ee83c07`，
  首轮静态审查阻塞 Workflow 读取未核 Mode ID/graph revision/hash，可能把同 ID 新图
  展示元数据拼进旧 run。root 已先明确 §11/设计18 的绑定条件并交原执行者最窄修复；
  单文件 11+/3− 修复已交付，其余 27 不变，新集合
  `59e12e66dfdeed0f3657615b2fa518e0e02195fb0b2b48842056e298fd70341d`
  已获 fresh 复审批准，root 亲核全二十八文件及原索引后暂存。root 四文件模块/router
  hooks 亦已独立静态批准并核验暂存，精确增加 1 Stream / 7 Control / 9 Normal，
  沿原池与 finalizer；Dart adapter 的十一文件后继现已静态批准。Context、Thread
  Configuration 与产品 Configuration 分开，不能由 Authoring 批准代替。
- U-General：既有 General Settings VM、可见读取与 Dumb View 的默认分发 mode／
  preference 六文件已静态批准，root 6/6 hash 核对后登记，保留原搜索 dirty／批次保存。
- U-Agents：普通 Profiles／角色选择器 enabled 筛选及不可用展示首轮五文件已交付，
  审查阻塞旧 descriptor 被用于 effort 候选与校验。原执行者已修复三文件，把当前
  catalog/Ready member 或匹配的真实 detail 与 last-known 名称展示分开，保留显式
  `setEffort(null)` 的编辑意图。新版 13 文件清单 SHA-256 为
  `1045fbc870d16214a9d6b359f93a18b25099ebd7a87af2246ea8ea0715521e72`，
  已获 fresh 静态复审批准，root 逐项核验 13/13 身份后登记实际六文件增量；
  不修改原生策略或自动替换原选择，不代表统一生成或全链验收通过。
- C-Configuration：账号模型窄命令测试、Configuration 测试 port 和 Start 读取回归
  八文件已静态批准并经 root 8/8 hash 核对登记；内容集合
  `a65b35dc16ab74db60a0b9822054f6a2e3ef0c1513c304f839510cf743d5cc33`。
  仅测试源码及静态证据，没有执行测试。旧 account_auto_compact 及其他领域测试、Driver
  消费者仍属后继，native 策略与真实跨语言证明未由这些替身完成。
  owned-call 后继六文件已交付，首轮审查阻塞未脚本化 begin 意外进入未完成 find 等待
  及一处缩进。原执行者已把三个 fixture 的 20 个未脚本化 begin 改为明确未派发的 typed
  rejection，并精确修正缩进；新版六文件集合
  `21592360f20e4d8e295de78b0ed019cd40a438218f50546a32e04fd7152e51aa`
  已获 fresh 静态复审批准。root 核完整九文件及三保护项后只登记六文件；生产 double-retry
  finding 另由 D2 修复并独立批准，不用 fake Clean 掩盖失败。仍没有测试执行或红绿结果。
- C-Drafts：纠偏旧任务回复后，七文件完整迁移已交付并获 fresh 静态批准，root 核七项
  与四保护文件后暂存，集合
  `8d0048c972a26fb4427341d1f7e3417455663734d024bf6d10984884c4ab1b52`。
  原二十旅程有完整映射，新增 archive/binary 缺陷信号，共三十四个静态注册入口，
  不是执行数。真实公开 factory/Repository 参与测试，替身不复制观察或清理算法。
  wrong-input、queued/running 且 durable=false 回归揭示生产 observer 没有 Turn 调用链；
  root 已依据源码先冻结 §16 原 lease pre-ACK 读取合同，不伪造 native queued 能力。
  原 D1 的实际目录权限只含 Drafts，不能盲派 Conversation 写入。已创建明确授权
  Conversation/Drafts 两目录的独立执行单元。该六文件闭包已交付，449 行新增、81 行
  删除，diff 身份 `89db0e909d0ed7df6e388ad13c2ae1818ff936015b6f6a2cf3dc9ef77cb82a2b`；
  原 D1 保持 idle、不并写。C 的公开 factory 回归亦已交付五文件，集合
  `17157c9671b221c6d66a68111e4acf971816899b7b6459c1f701b953e47801a6`，
  覆盖无 UI、created-only/pre-ACK、deferred inputId、同八 scope 与真实关闭交错。
  六文件首审发现两个阻塞：Start 可能借普通 UI baseline 而非原创建 source 完成 ready，
  以及已确认创建后 observer 构造失败的清理报告未由 Draft work 实际收束记录。root
  已先细化 §16；原执行者两文件修复在 fresh 复审中闭合前两项，但又发现失败通知及
  observer 同步清理异常被永久 latch、显式 retry 无法恢复的两项阻塞。root 已明确
  成功步骤不重做、失败步骤保原责任可重试。原作者 R3 已交付，六文件当前完整 diff
  身份为 `faac024964ec627cfb6dd33054b9ff573b27b13c0c82a1e3fedf69e6567e896c`，
  已获新的 fresh reviewer 静态批准。root 核六个 after、原 index blob 及其余索引
  不变后精确暂存六文件；运行验证和 R3 新路径的后继公开回归仍未完成。
  五文件回归首审要求门控原 UI native close，证明 archive 真正 join 而非
  提前释放。原 C 已在新测试单文件中修复并补上述两项生产缺陷的独特公开回归，其余
  四文件不变，当前五文件集合
  `cc557922ef21767d6cc7614f03febfd57770c4064f2ff9c73db2a63e85f42f74`
  已获 fresh 静态批准，root 核 before/index/after 后精确暂存五文件；原断言未弱化，
  全部仍未执行。本五文件不冒称覆盖后续 R3 的通知抛错及同步清理阶段 retry。
- C-Profile/reload：SDK §12 获批后，另派互斥测试消费者单元，只迁 Profile fixture、
  其真实编辑器消费者及最小充分的三 target/无 receipt 调用行为证明，不写 C-Drafts
  的共享范围。九路径已交付并获 fresh 静态批准，root 核十项身份（含 native-pin 保护）
  后只登记九路径。保原 editor 七个、roles 六个注册，新增十五个静态展开实例，均未执行；
  公开 observed 风险的生产修复现已静态批准。后继三测试累计一百五十九行纯新增，
  首审要求补 receiptless acknowledgement 在 identityObserved 前不再 pending 且配额
  已释放的两条断言。原执行者修复后，新 fresh reviewer 已批准当前完整三文件增量；
  root 核原 before/index 与 after 身份后精确暂存三文件。另两文件与原正文保持不变，
  不以测试源码批准代替运行红绿结果。
- root 共享呈现接缝：Driver 键值冲突已消解，静态逐段核对保留 main 与 PR 全部键值，
  使用新领域窄导入。分发／费用／评价标签迁到 `ui/labels/delegation_labels.dart`，原
  文案映射不变，消费新领域类型；旧消费者完整迁移仍未完成。合并未解决路径剩 43 个。
- 本地化：root 合并两侧新增键，严格 JSON 唯一键及三方语义核对通过；en 1511、zh 1452
  键。生成输出仍延期，不以源文件检查代替 l10n 生成验收。

进一步原生能力盘点确认，多数产品域当前只有新 DTO 与 SDK ports，仍缺专用 producer、
pinned read 和生产 adapter；Templates 是已有完整新链，Models 的 value read scope 已有，
Catalog feed/source 前置已补齐并静态批准。旧按 topic 的真实生产链不是新分域/有界读取已完成的
证明，后续按 Configuration/Profiles、目录、资源、统计与更新等实际 owner 继续迁移。
Models 精确详情、source-status 运输及生产 adapter 的后继接缝已完成只读核对并修正
关于 Rust 子模块可见性的错误初判。资格材料与精确详情 scope 已获静态批准；运输层
已依据 §17 续派，生产 adapter 仍未实施。继续复用原 Configuration 配对凭证，不以
请求回显或 latest 材料证明原来源，也不把分页响应的界限外推为整个原材料总内存界限。

- A-Configuration：只读闭包核对后，root 已先冻结 §18 并续派生产 adapter 实施，完整
  覆盖二十一个 ConfigurationPort 入口、两 feed、五 scope 和三个 typed calls。
  同一作者修 roleRead 漏映射、desktop i64 的无损类型适配，并将现有产品 read/open
  helper 收敛为 ProductReadOwner/ProductNativeOpening，完整迁移原 Catalog/Templates
  消费者，不复制 Configuration owner 或改 shared helper。原诊断标识与资源责任保留，
  执行者一轮恢复误回旧 binary 零增量复核，该报告未被接受为本任务交付；root 已明确
  重发当前 §18 合同并纠正持久任务记录要求。现正确任务已交付二十六路径
  （十九新增、五修改、两删除），集合
  `9420cd96e472679d94fa3fae3ac8d0129400cce7b8b9377e62f95d603e31b587`
  的首审发现：已确认结果中的回执／嵌套操作身份校验失败会被外层降为 Unknown。
  root 先在 §18 明确保持已确认类别且拒绝坏回执；原作者仅修 `command_results.dart`，
  新完整二十六路径集合为
  `e07db7854eb160f3c821ea2cd717bef5373ebb7ad289a1a18a5bfa74bcb31de4`，
  已获 fresh 静态批准；root 核完整二十六路径 before/index/after，精确暂存且确认
  其余索引不变。其余二十五路径及输入、初始准入、关闭责任未改；生成仍未执行。
  Models Dart 的共享 helper 前置已解除；root 已按 §23 派原作者实施六入口完整 port、
  Catalog feed、source-status/exact read 与旧临时工厂迁移。十路径已写入，但作者发现
  SDK exact close 后重新查询 descriptor 的接缝，正确停止为未完成交付。root 亲核后
  先补 §23.1，再修改 SDK port/ModelsDetails 两文件提供独立 scopeId 校验；原作者随后
  补 exact 叶 raw getter。该续修现已交付，adapter 十路径集合
  `70452e4c64f24656e36a031c985a7dc70bb31bd777c3ac775411100ebc249d68`，
  联合 root 两 SDK 的十二路径集合
  `4ca58acb8ea43c10a3570e98319425c962bcb3a1acd74125f56be2e6f7058782`，
  已获 fresh 联合静态批准。root 核完整 before/index/after 与其余索引不变后精确
  暂存十二路径；不将源码覆盖表或局部批准当作运行或装配通过。审查另提 Catalog
  native retry 文字疑点，root 亲核具名 read 调原 read.retry_close，而 feed 重等原
  producer completion、保持所有 Terminal issue，无独立可恢复清理动作；§17.1 已
  明确这两个 owner 的指代，没有新增重启流或清终态的兼容逻辑。

## HTTP 责任决定与锁架构研究

用户已明确选择方案二：Thread 五域及相关 identity、Models 指定具名详情独立按原
origin/ref 或完整 target 打开关闭，feed 关闭、断开或重开不撤销已交接详情；其他
Configuration、Profiles、AccountTemplates 等保原父 feed 监督。原版本校验、额度、
显式 close、真实 join、Unresolved/retry 与应用退出责任不变。此决定已同步 design18、
v4 Server 合同与续做合同 §19，不再是等待用户回答的问题。

用户进一步要求研究各种锁模式，现已明确“按照推荐架构调整，继续完成 PR”。root 的
官方资料研究、Config/Mode 事务盘点与 Thread/运输等待图已经完成；推荐路线按 §22
分阶段采用，不能把最小通知修复代称全局大锁已解决。

§20 的 Mode 分阶段通知已进入实施：root 完成 manager/mod 两叶的原提交加显式通知
责任接口，Config 原作者同时接入 save/delete/reload/initialize 并将 catalog sequence
I/O 移出 state guard、保留 command 事务责任。四文件现已获联合静态批准，root 核
before/index/after 与其余索引不变后精确暂存。审查曾把本轮前已有的 observe_registry
待消费事项误作新增阻塞；核对 index 后已校正，仍列整体集成跟踪，不删除接口或加 allow。
原 native 作者已完成 R3 十九阶段的等待/副作用、超时后 completion 及重试归属调查。
root 亲核后在 design18/§24 冻结原 ShutdownRun 唯一持有阶段与条件 Store、typed 恢复
资格、严格调用取消边界和 first-exit/finalizer 许可。原作者已交六文件实现检查点，
但 G1 drain 与 G2 observation/Resource 的恢复依据未闭合，尚未审查或暂存。
root 已应用 runtime/mod 与 builder 两处旧 service_stops 装配迁移；它们与下述存储
三文件联合取得 fresh 静态批准，root 核身份后仅精确暂存这五文件，其余索引未变。
后继 G1 只读核实同 HistoryChannel 队列可按原流程接管，旧“released_dirty 永久不能
由后继清除”的表述过强；也发现错误残留行不等于运行中 writer。root 先同步
design17/18 与 §24.1，再补原 incarnation 准备/运行/结束事实、准备取消的原 detach
责任和 typed 全 incarnation drain 失败，队列/水位算法不重写。首审指出接管期间
Preparing 零计数可能假成功；root 先补合同再让 Preparing 阻止 drain 结论，已获新
审查者静态批准。新存储接缝尚待 R3 消费，原六文件仍未审；原作者曾误回旧 R1 零
改动核对，未计为 G2 完成，已纠偏续查完整关闭可达来源，不按文案猜资格。
纠偏后的 G2 只读报告已完整交付：补齐 collaboration、原 rejected tools、observation、
published/unpublished cleanup 与 WriteBehind 的真实来源及 mixed failure 接续缺口。
root 先在 design17/18 与 §24.2 冻结“只推进原剩余责任、终态继续阻 Clean”，再续派
G2a 原 WriteBehind/AgentOperations typed 失败与原任务生命周期；后继 observation/
Resource envelope 及 R3 collector/continuation 仍待依赖交付，不视为一并完成。
G2a 首版十二文件已正式交付，root 核内容身份后应用两个必要共享根 hook；十四文件
首审发现 root close 可能漏等已通过准入但尚未登记的原协作操作。root 已核真实
seal/admission 调用链，交原作者在原 admission 边界补最窄屏障；不得持锁跨长 join，
修后须新 reviewer 复审。原 R3 六文件仍独立冻结未审。
原作者已交三行屏障返修，核锁序时又发现既有评价无效 self-target 的 target-permit
等待环；root 亲核后同步 design12 与 §24.3，按原直属 child 权限在等待目标前核验，
取得 permit 后仍重核当前事实。评价单叶的九行窄修与原十二文件及两个 root hook
联合十五文件已获 fresh 静态批准，root 核身份后精确暂存，其余索引未变；不改变评价
业务或跳过真 join。后继已先派 G2b1：仅原 observation 的 typed 失败、真实 completion、
固定 fences 与并列关闭问题，资源 phase/identity 和 R3 collector 接续仍为后续独立片段。
G2b1 作者在零源码改动时发现 WB 的纯资格查询与新 flush 不能原子绑定旧 task；root
核实后先同步 design17/§24.2，授权同域重新观察入口与该消费者一并闭合。无关 G2a
批准保持，受影响 handle 增量随 G2b1 新内容复审，不将零增量调查标成实现完成。
当前 G2b1 五文件已正式交付：原 progress/completion 双因、各固定 fence 与原 pass
接续、同次独立 issues、exact owner 退役，以及 WB 原 task 重新观察。root 核内容和
索引后应用两处 crate-private 精确类型导出，联合七文件已获 fresh 静态批准并精确
暂存，其他索引不变；这不代表编译或运行通过。root 先补文档后已续派原作者 G2b2，
补 Resource 的原身份、实际关闭阶段与剩余责任；G2c/R3 消费者仍为后继。
C 原作者误恢复旧 Configuration 九文件的零差异报告未计作本任务完成；纠偏后已交付
两测试文件的三个真实公开回归，覆盖通知失败/重入与 operation-watch 部分取消重试，
已获 fresh 静态批准；root 核两文件 before/index/after 与原 C5 三项保护后精确暂存。
无合法公开注入点的其它同步阶段与私有 cause/stack
明确不冒称测试覆盖，也没有添加生产 hook；所有回归源码仍未运行。
U-General 原作者已完成生产 App/demo/Driver 装配与旧消费者依赖的只读盘点：main
物理缺失，Driver/tray 仍有旧装配引用，多项 mandatory port 缺真实 producer/read，
以及 Bots/Stop/既有 Thread route 的新公共承接缺口。后继按真实领域前置推进，不能
仅补 main 或用 Noop/旧快照 shim 宣称可运行；已核 archive 需真实组合原 owner。

后继调查已分别交付 Startup、Stop/route/botId、Modes 和 Workspace 三目录的只读
报告，尚未冻结各自的新生产实现。Startup 缺安装前初始化监督及原成功材料；Modes
缺真实 feed/read 与受管命令材料；Workspace canonical 是 TOML/原 owner 而非 SQLite
镜像，仍缺不可变来源、发布屏障和具名读取，不能用长期数据库事务或旧全量接口假 pin。
route 的旧自动重试已核实与两侧设计不一致，用户明确选择“不自动重发”；design18
与续做合同 §25 已同步，具体生产结果接口及消费者仍待迁移。
root 已按 §25.1 补齐 botId 在 SDK 两纯值、手写 FRB converter 与同 scope 文本读取
的四文件传递，已获独立静态批准并经 root 核身份精确暂存，其余索引未变。此切片不等于 Thread Configuration
producer、Bots Repository 或托管设置导航已完成，Unknown 与最终 native 权限保持原边界。
独立的 SDK Stop 切片已按 design18/§26 派发：具体 Session、原 Execution origin 与
active Turn read ref 首次 await 前冻结，原具名读取解析 ID，ACK 与真实终态分开，
Unknown 不重发，工作及清理归原 Session。首版八文件已交付，root 应用一行窄导出后
联合取得 fresh 静态批准；root 核九文件身份后精确暂存，其余索引未变。原提交／创建
机械内核的保护仅为源码证据，尚无运行验证。root 已补真实 FRB interrupt 薄适配单叶，
保 Unknown 与已确认 reply 的错误分期；C 已迁移 mandatory commands 的测试装配及
公开 Stop 回归源码。C 已交获权 SDK 四文件，root 补 App 两处
明确 unsupported 的测试端口注入。联合七文件首审发现两处终态帧未同步到真实消费的
测试屏障缺口，已由原 C 作者最窄返修；未修改生产逻辑、未弱化断言，联合七文件已获
新 reviewer 静态批准，root 核七文件 before/index/after 后精确暂存，其余索引未变。
返修内容：离开 UI 的用例等公开 Observed/Effective 状态，
ABA 用例在旧 reply 仍 pending 时等原帧 ACK，再确认旧操作生效和新操作隔离。
测试尚未运行；UI/Driver 与生产总装配仍为后继。原 U-General 已交 Stop UI 只读报告，
root 对照 main 保留 child/interaction 的 Stop-only 入口，先在 design25/§26.1 冻结
Conversation 独立呈现、原来源动作、页面可见性及 Unknown 显式新意图边界。窄续查已
确认八个 Conversation 手写路径可完成接线，不需改 Composer VM／State、app/router
或 SDK 查询；生命周期延迟安全发布与永久退休动作分别处理。原作者无 Conversation
写权，因此由 root 实施八个 Conversation 手写文件及 en/zh 文案。联合十文件首审发现
共享 Observer 的取消重入／失败后短路问题，以及 VM dispose 的清理早退问题；已进入
root 返修。两文件 R1 经新 reviewer 核实修复成立；Observer 先完成原取消
再核最新目标，VM 独立尝试全部清理并观察原 metadata close。已亲核实际 SDK 的
额度释放可同步重入，但 listener 异常由原 zone 隔离；native metadata 未完责任仍在
Workspace，不新建 UI 清理 registry。89 个其它 Conversation 源文件与索引未变，
本片十文件索引保持原值；尚未新增 VM 消费者回归或运行测试，不用旧 facade/Noop 补装配。
R1 复审确认上述两项修复成立，另发现未 Observed 的 result 等待会跨 dispose 保留 VM。
root 已补 R2：完整 VM 销毁信号只结束 UI 等待，标准 Future.any 保留对原 SDK Future
的结果／错误消费，SDK 原操作不取消、不重发；metadata 诊断等待也不捕获 VM。
R2 仅改同一 VM 文件，其余九文件不变，已获新的独立静态批准。root 核当前十文件
before/index/after 后精确暂存，其余索引未变。
root 随后新增两个 App test/client 文件，用真实 ProviderContainer、Conversation／
Workspace／Recovery 和原 operation registry 覆盖三项消费者行为：A-B-A 后旧能力零
派发、遮盖／返回继续观察原 Stop、完整 VM 销毁结束 UI 等待但 SDK 及原 metadata
关闭仍由原 owner 保责。新测试源码已进入独立静态审查，尚未批准／暂存或运行；
不把 SDK 替身环境当真实路由、send/platform pending 或 GUI 证明，生成／运行验收仍延期。
首审确认三项行为调用链，发现 App 锁定依赖不含 `package:test`，而复用的 Client
helper 间接引用它。root 已交原 C 作者将纯 native 测试环境与框架断言分离，App 改从
无框架依赖的入口复用；不增加 package 依赖、不手改 lockfile，修后联合 fresh 复审。
该分层五文件已交付，三个 Turn native helper 的搬移及九条 SDK Stop 用例主体字节
保持；native close 返回原 initial report，SDK／App 各自保初次、重试及预算断言。
root 核七文件身份、其余 Dart 源与索引未变，并复核 App 在场源码依赖闭包无
`package:test`；SDK 五文件与 App 两文件已获联合 fresh 静态批准，root 再核身份后
精确暂存七文件，其他索引项未变。三条新 App 回归与九条既有 SDK 回归仍未运行。

## 合流阶段实测：合并已无冲突，缺口集中在原生产品接口

按“彻底重构、干净基座重做”的口径处理合并现场后，43 个 modify/delete 冲突已全部消解：
业务已在新分层完整体现的旧入口随重构删除；承载 main 真实新能力的入口按新架构重写，
旧文件不保留转发。当前 `git diff --diff-filter=U` 为空，未提交合并仍在进行中。

实测确认重写范围与新缺口：

- PR 树多处只提交了生成物而手写源已被删除：`features/shell/`、`features/interaction/`、
  `features/status/`、`src/shared/` 均是如此，`lib/main.dart` 两侧都缺。这些源已按新架构
  重写（shell／interaction／status／update／shared／platform／settings），旧孤儿生成物
  删除后交由统一生成重建。
- Bots 域的 SDK 侧按 §25.15 重建（`bots.dart`、`bots_ports.dart`、`src/bots/**`），
  App 侧仅保留单一 provider 组合点，未伪造快照；真实数据接线仍待完成。
- **原生产品接口是当前最大阻塞**：`code/anywork/rust/src/api/studio/products/feed/` 仅有
  mcp／lsp／skills／mode_catalog／account_usage／updates／performance_* 等帧值定义，
  `products/feed/mod.rs` 只为 Configuration／Profiles／Models／Templates 声明 transport；
  `products/read/mod.rs` 同样缺少 workspace／recovery／persistence／startup／mcp／lsp／
  skills／remote／modes／account_usage／statistics／updates 的读取 owner。因此
  `lib/src/rust/api/studio/products/` 目录不存在，App 侧对应端口实现无法在不伪造
  feed／read／close 的前提下编写，相关适配任务已按契约拒绝造假并交回。
- 另有三处命令返回值与 SDK 契约不匹配：Startup 仍返回 `RuntimeSnapshot` 而非
  `RuntimeReady`；Recovery／Persistence 的 retry 仍返回整块 snapshot 而非 read target；
  Modes 保存返回 catalog snapshot 而非 `ModeCatalogReadTarget`。

结论：合并层面已完成，剩余为“原生产品接口 + App 适配 + 生产组装与入口 + 统一生成与
门禁”的连续实施，不能以现有局部源码通过代替最终验收。
原 C-Profile 已补 Models exact raw-close 的两文件公开工厂回归并获 fresh 静态批准，
root 核身份后精确暂存：正常关闭、descriptor 不可用仍可凭 raw identity 清理、foreign
Clean 后保原 permit 并显式 retry 三个旅程。未运行测试，也不代替真实 FRB 验证或
旧 model_detail_queries 测试的完整迁移。这些成果不修改 R3 的关闭协调器范围，
不把已有端口/DTO 或只读报告当作生产能力完成。

研究先比较短同步临界区、单 writer、不可变快照、分阶段提交/通知、固定锁序与取消
安全，再依据真实等待边选择改动。性能疑点不冒充已测瓶颈；持锁通知不单独证明实际
死锁；换异步锁或分片锁也不自动消除等待环。现有批准计划、static-only 与局部复审
节奏不变，没有因此新增依赖、第二事实源、通用框架或运行验证。

阶段研究见 [锁与等待关系研究](./locking-research.md)。Config/Mode 只读报告已完成，
确认 command lock 的广域串行责任及 catalog sequence 的 state 读锁内 I/O。Thread/
运输调查也已完成，发现 Execution/Metrics opening 与 strict shutdown 的 lifecycle
循环等待；root 亲核后先同步 §21 与 design18，再交原作者窄修两入口。两文件的
12 行新增、2 行删除已获 fresh 静态批准；root 核 before/index/after 及其余索引
不变后精确暂存。运行验证仍延期，不以局部静态批准代替真实交错验收。
另将 shutdown stage wrapper 超时脱离 join 的监督缺口单列，未混入这次修复。
design20 目录独立 lane 的承诺与实际共享 command lock 的差异已单列，不擅自通过
弱化文档消解。当前研究未证明全仓无死锁，也没有运行复现或性能改善证据。

## Thread Context／Thread Configuration 前置核查

Thread Context/Thread Configuration 的两域原生闭包仍未实施。Models 运输获批后，原
native 作者继续只读核查 current-context policy 的实际来源、Config/Mode 通知的原
Thread 捕获边界，以及 Unsupported 与旧占位字段的证据；这不是新接口或实现批准。

## Profiles／reload 前置调查与当前后继

来源实施前的只读调查确认 `ConfigRuntime` 持有独立 `AgentProfilesResource`；查询消费
已发布缓存，外部文件改动通过显式 reload 扫描，不在订阅中暗中扫描。当时缓存缺少 typed
collection 的 entry 身份登记；该缺口现已由上文获批的 Profiles 来源/读取单元补齐，
不是当前仍缺来源的结论。下面保留原调查依据与后继约束。

- `reload_from_disk` 在原 `command_lock` 下更新 Configuration/Models、采用 Profiles
  scan，并在返回值保留本次 `AgentProfilesSnapshot`。原快照值被持有本身不足以证明
  Profiles read material/source target；后续获批单元已在原边界补入相应 capture。
- Profiles 的旧扫描诊断有自己的语义：目录不存在允许空用户集合，目录不可读和单文件
  失败保留诊断；设置 catalog 保留禁用项，执行 catalog 按固定/自动模式的原资格筛选。
  不能将这些诊断直接当作新的 provider source 状态，或丢失系统 Profile 不可编辑规则。
- 已在原 adoption／提交边界捕获 Profiles material、entry/revision 和诊断来源并接入
  真实 feed/read；当前继续接用户 Profile 保存、系统 enabled 和 reload 的三个原 targets。
  scope、delivery window、read calls 和任务监督复用现有能力，不另建通用框架。
- 相关 Configuration、protocol、bridge 和 Server 文件仍属于当前 Configuration writer；
  Configuration 单元批准后已按 §10 冻结并续派来源/读取前置，公共 Profile 命令与
  reload 调用资源仍后继串行衔接；不把这段只读调查或新派发当作实现完成。

## Bots 迁移前置事实（尚未冻结新接口）

`bots/owner.rs::publish` 已有唯一 canonical 发布与原 publisher join，旧 Bots topic、
SDK commands/queries 和飞书界面是真实实现，不能当成缺失业务重新设计。待迁的是新的
领域 Repository、分域 feed／scope、Smart/Dumb 和完整消费者，而非第一个 Bots topic。

- Bots desired/configRevision/credential scope 独立于主 Configuration，沿 `design/27-bots.md`
  的信任、注册、发送、绑定与取消语义；配置、领域投影、chat binding revision 不混用。
- `pl-protocol/src/studio/bots.rs::BotMessageBody` 只有 Text/Post/Unsupported。旧页面不支持
  消息附件下载；迁移不能自行增加媒体权限或假附件引用。
- 会话与消息分页保持默认 20、clamp 1..50 的原规则。会话 cursor 绑定 Bot 和
  directs/groups 来源；消息 cursor 绑定 Bot/chat/时间范围。它们不承诺跨请求事务快照。
- `bots/storage.rs` 的 pairing 每 Bot 上限 32、TTL 七日，失败保持 last-known 并报诊断。
  Bot 数、trusted users/chats 和 pending credential operations 没有已发现的硬数量上限；
  不能把旧全量聚合快照视为天然有界。注册只保一个 attempt slot，终态可保留至下一次。
- 当前 observed directs 会先读整张本地表再切页；远端历史 response/text 无项目字节 cap。
  新接口冻结前须闭合有界读取方式，不伪称旧返回一页已经实现源侧有界；也不静默截断正文、
  改业务输入范围或伪造远端不可变 revision。
- 旧 BotsQueries 只失效展示请求，底层工作仍运行并由原 lane 在 close 时 join；发送、
  注册和绑定另有真实操作 owner，不能以页面退订取消已受理义务或重放 Unknown 发送。

上述为源码前置盘点，不是新增 Bots 接口批准或实现完成证据；后续先同步具体契约再派实施。

## 验证与交付规则

沿批准计划保留实施期静态审查：全部手写和消费者迁移完成前，不运行编译、测试、分析、
格式化、生成或 GUI。每个执行者完成即 fresh reviewer 审查；真实逻辑问题返原 owner。
全部静态通过后 root 统一生成、适用全量门禁、Linux 真实 bridge/Driver 验收与源码计量。
当前没有本次实现 CI 结果，不声明通过；最终快进更新原 PR 并核对实现 SHA 对应 CI 终态。

## 收尾状态（本轮实测，覆盖上文的历史快照）

上文「43 个未解决索引冲突项」「尚未合入五提交」等描述属于更早阶段，现已被以下事实替代：

- 合并已在工作区完成，HEAD 仍为冻结基线 `0226f8060a6af8a778ac8685633707b497c8c8a2`，
  改动尚未提交。
- Rust 侧门禁（本轮实测）：`cargo fmt --all --check` 通过；
  `cargo clippy --workspace --all-targets -- -D warnings` 通过；
  `cargo check --workspace --all-targets` 通过；`cargo test -p pl-model` 17 passed；
  `cargo test -p pl-core --features sqlite` 15 passed；`cargo test -p pl-studio-runtime` 194 passed。
- Dart 侧：`cd code/anywork && dart analyze lib test test_driver` 与
  `cd code/anywork_client && dart analyze lib test` 均为 0 issue；
  `cargo xtask generate-gui` 与 `cargo xtask check-gui-generated` 通过；
  `cargo xtask verify-gui`（生成一致性 + `cargo fmt` + `dart format --check` + `flutter analyze`）通过。
- 呈现保真：设置页共享壳层与各分页、会话区、交互 dock、composer/附件 rail 已按冻结基线逐项还原，
  约定写入 `design/25-frontend-state.md` §25.17。
- 尚未通过：`cargo xtask verify-client` 的边界规则步骤（重构后的模块形态与旧规则集不一致，
  正在按 `design/25` 逐条裁决「改代码或改规则」）；`code/anywork/test/client` 仍有少量红项
  （目录冷读导航、Configuration facet 水位、分页错误身份）与一个挂起用例。
- 尚未执行：`cargo xtask manual-gui` 与 `cargo xtask run-gui --driver` 的人工验收。
