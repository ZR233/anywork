# v4 最新主线同步、审查口径与遗留逻辑

## 1. 当前结论

安全同步与旧成果保全已完成；**没有宣称旧 Timeline 逻辑或全链路重构通过**。
本次仅运行 Git、文本／引用／hash／差异空白核对和静态源码计数，未运行编译、测试、
analyze、clippy、格式化、代码生成或原生 GUI。

| 身份 | 完整值 |
| --- | --- |
| 新贡献基线（本次 fetch 冻结 main） | `b3f22b8f651816851852582a10a970fe25af3ae6` |
| 原任务已提交 HEAD | `b98432fa809446d57be87a8b96379455ec8a4828` |
| 重放后任务 HEAD | `78a2762495772d7fe416faaf5f14876cf46597c4` |
| 重放后的提交 tree | `d2be2b57f356c967f3ae1d0df28e2714b1e3bcd2` |
| 原90路径备份 identity SHA-256 | `1df8ac4781d51af5be300505e89d84728755a75514840161bd7e3e2a6bcc43c4` |
| 整合前保留 stash | `4f8f65c292e2c5110730e84f32c9df8363f33117` |
| 已审 overlay result manifest SHA-256 | `84926827a6313ad3039bde3431f9ca38101d53ca6494e68668c22876fe6feedd` |
| 已审 tracked patch SHA-256 | `0f0d3624c768d3d2d2e1153caec3b1a6ed1292be1f43485bf0dbfec6e33b09dc` |
| 整合回执 SHA-256 | `d89e84e93e6879acd2cf5958a2c402f902b7c2260d7e476db4ec5b56baa8b2d4` |

`78a27624` 只有原文档提交的重放，唯一父提交为冻结 main；生产／测试／生成输入仍未提交。
父任务分支没有推送，main 没有移动，所有旧 stash 均保留。该新 stash 不自动 apply 或 drop，
也不是交付历史中的“备份提交”。原 ignored 证据与用户数据未清理。

## 2. 保全与审查范围

隔离 worktree executor 先更正宿主分配的干净起点，再 rebase 唯一文档提交。文档冲突由 root
先给精确文本：测试职责保留 Timeline 图片行与新吞吐语义；前端契约同时保留图片卡片与
编辑 VM，以及上游更新退出／Router 真实卸载和目标资源 join。独立静态审查批准该提交。

旧90路径随后按 `base=b984 / current=78a / incoming=冻结旧成果` 三方重放：

- 58 个文本合并、18 个新文件、3 个安全删除、1 个 root 精确解决，共80个非生成变更。
- 唯一冲突在 `timeline_view.dart` 的 import。旧成果相对 b984 只把 `studio_client.dart`
  改为 `conversation.dart`；最终在78a只替换这一行，保留 foundation、activity import、
  image card part，以及上游静止隐藏滚动条的其余全部字节。没有用旧整文件覆盖新主线。
- 10 个旧生成物没有重放：8 个已跟踪输出保留78a版本，2 个新增 Freezed 输出暂不存在。
  原字节在备份／输入对象中保留，最后全手写完成后统一生成，不据此宣布当前可编译。
- fresh reviewer 亲核90路径身份、77个存在结果 blob、mode、删除、差异范围和索引；根工作区
  整合后再次核全部身份及完整 tracked patch 一致，索引为空、无冲突、`git diff --check` 通过。

文档 rebase 审查为 `thread-65e63ef75d8f5-6f` 的 `message:1:3`；overlay 保全审查为
`thread-65e64123c5dec-96` 的 `message:2:412`。后者复核了初审五项发现的来源，批准仅限
同步保全，明确不批准旧逻辑。完整命令回执、manifest、三方原件与 reviewer 报告保存在
本任务会话归档，正式报告只记录稳定身份，不写入会话绝对路径。

## 3. 中间审查按目标逻辑判断

用户对 v4 补充：中间审查根据实际情况，局部重构会造成暂时无法编译或功能失败，
**仅针对重构后逻辑是否正确**。它细化执行口径，不放宽最终完成标准：

- 本任务已经负责完成的逻辑、共享接口、状态 owner、错误、预算和关闭义务仍必须正确。
- 其他已分配任务尚未迁完的消费者、延期生成或暂时未闭合的依赖，不单独阻塞局部逻辑审查；
  必须有具体归属与最终完成判据，不能永久留下接口缺口或新增兼容 facade。
- 同步保全审查区分“合并新引入的语义损失”和“原成果已含的缺陷”。继承缺陷不伪装为
  合并丢失，也不因保全批准而消失；进入对应全重写合同与最终验证矩阵。
- 不在中间编译／测试来证明暂时可用；全部手写和消费者完成后再统一生成与验证。

## 4. 全重写必须处理的具体问题（全部仍未解决）

| ID | 任务归属 | 事实与最终判据 |
| --- | --- | --- |
| SYNC-C1 | C，验收消费者 | 上游新增 `manual_gui/skill_activity.rs` 仍调用 `write_realtime_driver_evidence`。最终迁为 `write_process_evidence` 并传真实 `"driver"` kind；不保留兼容 helper。此时未迁不阻塞同步，最终必须清零。 |
| LOGIC-U2-1 | U2，展示候选身份 | 旧 `TimelineSessionOwner` 只按 Thread ID／已发布代次判断迟到基线，查询动态找同 ID Session。新结构在首 await 前冻结具体 Session、consumer 绑定和候选代次；新候选开始即废弃旧发布资格，每次 await 后重查，旧查询不能借用新 Session。 |
| LOGIC-U2-2 | U2，consumer 收束 | 旧 `_consumerClose ??= lease.close()` 会跳过后续 close，期限报告只枚举展示 lease。新结构逐次登记所有已受理 consumer 的 close，等待全部真实结束；尚未发布的候选回调也要计入未决报告，不能空列表假 Clean。 |
| LOGIC-CLOSE-1 | D1／A／R，共享关闭合同 | 正常返回 Unresolved 的已完成 Future 在 Channel／adapter／native 多层缓存，显式 retry 再读同一结果。必须区分进行中 join 的共享和已完成可重试失败：显式重试继续原 owner 的清理，保全部未解决 issues，不新建句柄、不重放业务操作；不可恢复故障不能伪装可重试或 Clean。先冻结完整跨层接口再实现。 |
| LOGIC-FAKE-1 | A／C，替身与测试源码 | 多个 fake 在读取 events getter 时就认领，且二次 listen 给出框架 StateError。目标合同为 getter 无认领，实际 listen 同步认领，重复实际 listen 为 typed Conflict，closing 的 Cancelled 优先。同步迁移全部 fake，最终用例分别证明 getter 重读与实际重复订阅。 |

四类 B 逻辑问题在原输入 overlay 已存在；reviewer 用输入／结果 blob 与局部片段身份实证，
不是新主线三方合成造成。此前绿色用例不能推翻这些静态时序问题，也不能证明修复完成。
上述表是修复准入清单，不是允许执行者自行补齐接口的派发；root 仍须先提供完整设计包。

## 5. 新主线必须保留的语义

- throughput 采用成对 completion tokens／总 response 毫秒，包含首字等待；TTFT 平均值
  使用独立 `ttft_sample_count`。失败／停止撤回原 live generation，不混合重试前后计量。
- Turn canonical idle 后允许在 workflow 仍 active 时切换模型；正在执行／等待输入、关闭、
  closed、faulted 仍按真实准入限制。切换只对后续 Turn 生效，不自动续跑或重置 workflow／Plan。
- 更新准备复用既有后台下载；首次退出冻结意图和期限，安装交接与可靠关闭结果独立。
  隐藏路由子树真实卸载后才能释放展示资源，不依赖隐藏页收到一次 provider 刷新。
- per-project/session 存储布局、安全迁移、图像展示与按需滚动条不被旧成果覆盖。
- Interaction 外部响应目前没有 UI expected revision；内部读取 current revision 做 CAS
  不能冒充 UI 已冻结的 CAS。完整详情／响应协议仍须 root 在目标设计中一并定义。
- compaction Timeline 已有的 before/after tokens 为 unknown；成功 receipt 不提供这两个值，
  不以累计 accounting 伪造。Thread MCP/LSP/progress/health 和部分 prompt 来源的占位也不能
  被表述为已测健康空域。

## 6. 新贡献基线与验证边界

`baseline-source-metrics.json` 已由同一 `source_metrics.py` 对冻结 b3提交只读复算，SHA-256：
`11aa43274275a0fc80671684803e6518de55d658ccdba0559271f2887e0bc949`。
分类与数字见 [证据索引](./README.md)。这是静态计数，不是测试或性能探针，没有收益百分比。
最终以同一口径重算目标版本；上游增长不能算成本次重构增删收益。

旧 SDK／APP／Rust／native 结果仅绑定各自原输入。当前未运行新基线测试，未更新 PR head，
未取得新 CI 终态。初始 connection failure 原因仍未知，旧三轮未复现不解释旧原因。
