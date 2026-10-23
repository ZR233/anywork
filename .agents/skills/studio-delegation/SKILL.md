---
name: studio-delegation
description: Use when implementing, configuring, or validating Studio subagent delegation modes, model enablement, frozen child routes, or final task evaluations.
category: guides
---

# Studio 分发与最终评价

先读 [协作契约](../../../design/12-collaboration.md#127-分发模式模型查询与最终评价)、
[配置契约](../../../design/20-config.md) 和 [前端状态](../../../design/25-frontend-state.md)。
配置版本以 `code/pl-studio-runtime/src/config/mod.rs` 的 owner 常量为准；不要仅改版本号
跳过迁移，也不要复制旧示例覆盖当前配置。配置和凭据的通用安全边界见 `studio-config`。

## 资格与配置

- 身份始终是 `(accountId, modelId)`；账号有效目录是唯一成员来源。
- 先复用 `AccountModelEntry::type_support(ModelType::Text)`，再应用统一 enabled、
  当前路由准入和子任务能力要求。不另建自动模式白名单，不从内置目录补回撤下成员。
- 管理页保留完整目录和不可用原因；选择器排除禁用项。禁用不删除 desired route 或
  冻结身份，不取消在途模型调用；下一 Turn、恢复执行和派发重新准入。
- 启用与计费使用各自 typed CAS 字段命令，不能回传陈旧账号快照。
  模型管理窄命令同样必须携带调用方 OperationId，回执原样返回；不能以目标描述替代
  提交身份，也不能由 Client 重写不匹配的回执来伪造成功关联。
  计费 override 缺省表示自动推导，显式 `unknown` 不是清除；关闭金额统计不是订阅证明。

## 冻结边界

- 全局默认只用于新 root 创建。外部请求可分别省略 mode/preference，GUI 在草稿提交时
  与文本、附件、项目、工作区和主模型一起同步解析，并发送两个显式值。
- 已创建会话的策略只读；验证固定模式和三种自动偏好时创建多个 root，不能运行中切换。
- Profile 拥有角色与工作区权限。自动模式只选择账号、模型与 effort；固定模式拒绝覆盖。
  不向 composer 添加子代理 Profile 选择器，不用 metadata 传递路由或权限。
- child 的实际模型由冻结 Profile 拥有，`studio.delegation` 只存策略。列表消费 typed
  冻结身份，不能从当前 Profile、root 模型或供应商别名反推；未知历史保留未知。

## 评价与生命周期

- `list_delegation_models`、`get_delegation_model` 提供有界资料；任务评价不是调用性能历史。
  性能直接复用现有 TPS、平均 TTFT 和样本数，不另算 median 或隐藏综合分。
  `discover_tools.query` 是单个工具 ID 子串，不分拆空格中的多个名字；使用合法共同子串
  或逐一精确查询，并核对真实揭示结果。权限负例不能用必然不匹配的查询证明工具缺席。
- `evaluate_agent` 绑定真实直接父子关系、最新 committed 终态与冻结模型。
  完整交付、审查和所有返修结束后再评价；Turn 停止不等于任务完成。
  Core 热快照中的 Turn 集合会退休，不能用其末项作为唯一终态历史。复用可靠历史及保存水位
  证明最新 Turn，同时核对当前活动与待处理工作；持有同目标操作边界，不能借旧终态绕过准入。
- 同 child 只有一条有效评价；原内容重试幂等，后续最终 Turn 用 revision 更新同条。
  评论按原字符串 Unicode 字符数限制，首尾空白计入长度；`notRated` 不入能力均分。
- 取消等待不表示数据库回滚。实际写任务必须有 owner、完整事务结论和真正 join；
  完成任务及时回收，临时 seal 不充当永久关闭历史索引。
- 冷 child 评价只读已保存事实；显式冷关闭可以恢复关闭所需事实，但不提交输入或启动模型。
  只读要求作用于实际数据库连接和事务；不能因为已经持有 writer，就复用可迁移、导入或清理
  文件的加载路径。缺 canonical、旧 schema 或坏内容应保留现场并明确拒绝。
  项目归档边界更窄：只读目录和驻留状态，不读取冷历史、不激活冷 owner。
- 同目标的评价、续跑、激活和关闭必须有一致顺序；项目归档还须覆盖根创建与 spawn 准备。
  正常宿主退出与显式关闭意图分离：Core Closed 只证明当次 owner 关闭，不证明禁止恢复。
  显式关闭意图由版本化 Studio Thread 扩展拥有，目录只投影；复用现有持久化和资源 owner，
  不以永久内存 tombstone 替代恢复语义。旧记录无法证明意图时不从 Closed 或 lease 猜测。
  清理策略也只能在意图真正 durable 后发布给普通 shutdown 可消费的资源 owner；内存中已有
  marker 不代表保存成功。提交前失败保留现场，提交后清理失败保留原策略供显式重试。

## 验证证据

遵守 `test-quality`、`rust-concurrency-safety` 与 `flutter-studio-build`；项目门禁见 AGENTS.md。

- 模拟供应商只提供外部响应与阻塞边界，不能重写被测资格、选模或评价规则。
  `/models` 库存和配置回读不证明 child 实际路由；核对真实 completion 请求与 spawn 回执。
- 从真实 child 报告取得 childId、最新 Turn 和未结束工作，从真实评价收据取得 revision；
  Turn ID 仅在所属 Thread 内解释，跨 child 核对 `(childId, turnId)`，不要求裸 ID 全局唯一。
  不把父 Turn、受理 ACK 或旧报告当作最终身份。
  inputId 可空，messages 是终态身份命中的投影子集，不保证含所有已消费输入；不解析 opaque
  Turn ID 猜消息身份。续跑验收结合真实 send 回执、新输入/输出、最新 committed Turn 和状态。
  `list_agents.lastTurn` 是可空的轻量投影，不是完整终态历史索引；缺失时不能直接推断失败或
  没有新 Turn，需要终态历史证据时按需消费现有公开会话读取接口，并保持有界与身份核对。
- 供应商请求已到达的可控响应 gate 可验证“禁用不杀在途、下一 Turn 拒绝”。没有公开
  锁内停点时，不把 sleep、重复竞速或一次成功当作确定性线性化证明，不加生产测试捷径。
- GUI 使用真实 bridge 与 Driver，结合 canonical 状态、截图和请求日志判定。
  智能体成员来自完整 AgentDirectory，不与 Thread 分页或热集合取交集；冷成员按显式选择读取。
  快速导航测试必须走公开命令入口，新意图在 enqueue 前使旧读取失效；只直接改 store 不能
  证明串行 lane 中的真实快速改选不会发布旧结果。
  生成物只由工程入口生成；截图、临时客户端和环境配置留在本 Thread 会话目录或工具
  规定的证据目录，不提交源码。等待 shutdown_completed 及所属进程真正退出。
  冷恢复须实跑正常退出、同数据根重开、同 child 续跑且冻结模型不变；另证显式关闭后重开
  仍拒执行且无新增 child 调用。只读历史或冷关闭不能代替冷续跑证据。
- 禁用准入负例使用真实外层错误与联合证据：禁用前同身份可选、禁用后明确不可用、精确调用
  关联、目录无新增或残留、目标和全部 child 请求均不增。计数基线只在真实派发时保存，
  回放读取原基线；发送合法 sample，使误准入能真正到达供应商，不能由 fixture 自拒造绿。
