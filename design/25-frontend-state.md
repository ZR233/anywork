# 25 - 前端状态架构（Flutter/Dart 侧）

本文是 anywork Flutter/Dart 侧状态与数据流架构的唯一权威源：分层、状态所有权、
数据流契约、命令语义、草稿语义、导航语义与验收观测。Rust 侧产品事实、snapshot、
activation 与订阅协议见 [18](./18-studio-state.md)；UI 呈现、页面组织与组件契约见
[19](./19-studio-ui.md)。Rust 侧协议（typed DTO、revision、topic、CAS）是本架构的地基，
不在本文范围内修改。

本架构取代旧的「单一巨型聚合 state + 巨型 controller」实现：历史证明把三种寿命
不同的状态（Rust canonical、本地乐观投影、本地 UI 草稿）混居在同一容器且无所有权
契约，是设置往返后新会话模型/思考强度不显示新值等 bug 家族反复复发的结构根因。

## 25.1 分层模型

```
┌────────────────────────── Widget 层（features/*）──────────────────────────┐
│  ConsumerWidget 只 ref.watch(职责内 ViewProvider) 渲染；                    │
│  用户交互发送 typed intent：ref.read(命令入口) 或 route 作用域草稿控制器      │
└────────────┬────────────────────────────────────────────▲─────────────────┘
     intent ↓                                     │ immutable View state
┌─────────────▼──────────────────────────────────┴─────────────────────────┐
│ View 层：每 feature 的 ViewProvider，从多个 store 派生只读视图；            │
│ 不持有 canonical 副本、不消费 raw stream、不写状态                          │
├───────────────────────────────────────────────────────────────────────────┤
│ 命令层：SettingsCommand / ThreadCommand / DirectoryCommand                 │
│ 串行 lane + expectedRevision CAS + 冲突 rebase；成功以响应 canonical 应用   │
├───────────────────────────────────────────────────────────────────────────┤
│ Store 层：领域 Notifier 族（keepAlive + family）；纯 reducer：             │
│ (state, typed event) → state；revision 单调、旧帧拒收、单一 merge path     │
├───────────────────────────────────────────────────────────────────────────┤
│ Bridge 层：StudioBridge —— 全 app 唯一 FRB stream 消费点                   │
│ typed topic/thread 流按领域分发到 store；lease 租约；lag 局部重同步         │
└───────────────────────────────────────────────────────────────────────────┘
```

每层只与相邻层通信：Widget 不越过 View/命令层接触 store 或 FRB；store 不感知 Widget；
命令不直接改 store 内部，只以命令响应走 store 的 merge path 收敛。

## 25.2 三种状态寿命与所有权

| 寿命 | 唯一归属 | 规则 |
| --- | --- | --- |
| canonical（Rust 事实） | Store 层各领域 Notifier | 只由 Bridge 帧与命令响应写入；revision 单调；本地写入不得绕过 merge path；不保存第二份副本 |
| draft / ephemeral（UI 意图） | route 作用域草稿控制器 | 不进全局 provider；canonical 永不覆盖草稿，草稿永不写回 canonical store；页面销毁即消失，提交时一次性转命令 |
| in-flight mutation | 命令 lane 的结果状态 | 只含目标值、pending/failed 与 typed 错误；显示规则为 pending 目标值优先、否则 canonical；成功后 canonical revision 到达即收敛，失败就地提示，不做本地回滚双写 |

任何跨层的第二事实源（页面缓存、静态通道副本、demo 旁路状态）都违反本表；
验收观测按 §25.10 从唯一事实源派生。

## 25.3 Bridge 层：唯一流入口

StudioBridge 是全 app 唯一订阅 FRB topic/thread stream 的组件：

- typed topic 帧与 Thread 有序流按领域分发到对应 store 的 reduce 入口；分发是唯一
  接线点，页面与 ViewProvider 不得各自消费底层 stream。
- 产品 topic 的 lease 语义遵循 [18](./18-studio-state.md) §18.2.1：以 topic/作用域为
  身份复用可释放租约；shell 常驻目录/公共配置/诊断摘要 bundle，设置页各标签、
  持久化面板、会话费用等按可见性租用；最后一个观察者释放后取消订阅。
  租约的取得/释放由参数化的统一入口提供，不按页面复制样板。
- `lagged`、`failure`、`closed` 只使对应 topic/作用域进入局部重同步，保留最后有效
  canonical 内容并暴露局部错误；重同步重新执行「先登记接收者、再取基线」。
- Bridge 是旧 revision 帧在 Dart 侧的第一道拒收点：帧在进入 store 前按领域
  revision 比对，较低水位丢弃；store 内再按自身时钟兜底。

## 25.4 Store 层：领域状态族

每个领域一个 store（keepAlive；带作用域者为 family），state 为不可变值，reducer
为纯函数。store 只接受三类输入：Bridge 分发的帧、命令响应的 canonical、跨领域
依赖的显式订阅（如 threadSession 依赖 selection）。

| Store | 职责（canonical 事实） | 输入事件 | revision 时钟 | family |
| --- | --- | --- | --- | --- |
| settings | 配置快照 + 模型目录快照 | SettingsConfigBaseline / ModelCatalogBaseline 帧、设置命令响应 | settingsRevision 与 modelCatalogRevision 双时钟独立比较 | — |
| project | 项目目录、Agent 目录 | 目录帧、目录命令响应 | 目录 revision | — |
| threadDirectory | 会话目录分页窗口与增量合并，含搜索命中但落在窗口外的线程 overlay（供定位选中，不推进水位） | 目录帧（页/delta）、目录命令响应、搜索响应 | 目录 revision + cursor | — |
| selection | 当前选中 project/thread 与待打开标记 | 仅本地选择命令与启动恢复快照 | 无（纯 UI 选择事实，不参与 canonical 水位） | — |
| threadSession | 该会话 runtime/turn/interaction/workflow/activity/storage 投影与 Timeline 有界窗口 | Thread 有序流帧、快照、历史分页、会话命令响应 | epoch/baseRevision/revision 单流水位 | threadId |
| modeCatalog | Mode 目录 | 目录帧 | 目录 revision | — |
| mcp / lsp | 服务状态与诊断 | 对应 topic 帧、命令响应 | 各自 revision | — |
| skills | 项目 Skills 状态 | 作用域 topic 帧 | 各自 revision | projectId |
| providerUsage | 服务商用量查询结果 | 用量命令响应/帧 | 查询代次 | — |
| sessionCosts | 根会话费用 | 作用域 topic 帧 | 各自 revision | rootThreadId |
| persistence | 持久化队列状态 | topic 帧 | 各自 revision | — |
| updater / recovery / modelPerformance | 更新、恢复、模型统计 | 各自 topic 帧 | 各自 revision | — |

合并规则统一：同一水位幂等丢弃，较低水位不得覆盖较新事实；direct response、topic
frame 与 baseline 进入同一条 merge path，任何调用方不得按到达顺序整体替换。
设置域保持 [18](./18-studio-state.md) 的配置/目录双时钟语义：配置水位前进只替换
配置字段，目录水位前进只替换模型目录。Thread 单流水位语义遵循 [18](./18-studio-state.md)
§18.10；Dart 侧可细分 selector，但不得建立绕过同一水位的旁路流。

## 25.5 命令层：typed command lane

设置、会话与目录命令分别进入一条串行 lane；lane 内命令按提交顺序执行，携带
调用时读取的最新 canonical revision 做 CAS。staleRevision/conflict 由 lane 就地
刷新 canonical 后重试，至多重试两次；重试仍失败保留原 canonical 并向调用处返回
typed 错误，界面就地提示。

- 命令成功以响应携带的 canonical snapshot 应用回对应 store（同一条 merge path），
  不额外触发「显式刷新」。响应里哪些字段可用由资源 owner 决定：settings 命令合并
  响应中的配置与目录快照；Thread route 变更只合并 settings，route 本身等 Thread
  有序流帧；mode 变更由 `ThreadDirectoryChanged` 增量与 Thread 运行时帧交付。
  **任何命令成功后都不得重新读取聚合状态、目录快照或 thread snapshot 去补齐显示值**：
  那会让同一事实出现第二条合并路径，并让「帧没到」这类缺陷在验收里不可见。
- lane 的结果状态（in-flight 目标值/失败）供 ViewProvider 组合显示；不把目标值写入
  canonical store，也不在本地维护回滚逻辑——canonical 收敛永远以下一帧/响应为准。
- 不存在「导航前等待写入」的 flush 契约：页面离开只释放观察者租约，不取消也不等待
  lane 中在途命令；后续依赖最新配置的命令（如创建会话）在执行时读取 lane 收敛后的
  canonical 组装 payload。
- 附件/草稿提交等复合命令按 18/19 的产品语义组装，禁止把整页旧配置副本写回。

## 25.6 草稿层：route 作用域 ephemeral

草稿是未提交的本地 UI 意图，归属使用它的页面生命周期，不进入全局 provider：

- 新会话草稿（Mode、工作区模式、模型路由/思考强度意图、输入正文与附件引用）由
  起始页的 route 作用域控制器持有；提交时一次性组装创建命令，成功后销毁。
- 会话输入草稿由按 threadId 参数化的草稿控制器持有，随会话归档释放。
- 附件草稿的 admission/preview 仍遵循 [19](./19-studio-ui.md) 的两阶段语义，
  逻辑收敛在 interaction 域单一控制器内，不使用额外的生命周期令牌或屏障。
- 草稿与 canonical 的组合显示规则：草稿存在时显示草稿值（选中即所见）；草稿
  提交后的等待期显示命令 lane 的 in-flight 目标值；成功后显示 canonical。
  canonical 到达不清除、不覆盖草稿；路由不可用时显示占位与原因，不静默隐藏选择器。

## 25.7 View 层与 Widget 消费契约

每个 feature 拥有自己的 ViewProvider：从若干 store、命令 lane 结果与草稿控制器
派生只读、不可变、值相等的视图对象。Widget：

- 只 `watch` 职责内 ViewProvider（或其字段 select）；不 watch 聚合全局状态。
- 用户交互通过命令入口或草稿控制器发送 typed intent；不在回调里捕获可变视图快照，
  只携带稳定 identity（project/thread/role/provider/model id）。
- 禁止事项：内联 select 底层聚合 state；以一次性 `read` 读取本应由订阅提供的
  事实；直接订阅 FRB stream、raw JSON 或 SQLite；在 provider 初始化中执行写副作用；
  派生值通过副作用写回状态。派生值一律在 ViewProvider 中即时计算。

## 25.8 导航与订阅生命周期

导航只决定哪些页面（因此哪些 ViewProvider 与租约）有观察者，不产生任何业务写入
或等待：

- 不存在「会话可见性」代次、可见性屏障、返回前 flush 或 pop 拦截。
- `threadSession(threadId)` 的订阅随其观察者存在：shell 挂载即保持当前会话流，
  设置页等栈式推入页面不中断该流；shell 销毁即释放。
- 设置页返回不触发刷新、不重建会话状态；起始页显示值由草稿、命令 lane 结果与
  settings store 的 canonical 三者按 §25.6 规则组合，天然反映最新事实。
- 页面级 ViewProvider 与租约随路由自动建立与释放；跨页面需要保留的选择属于
  selection store 或草稿控制器的显式职责，不依赖隐藏全局变量。

## 25.9 相等性与通知语义

项目使用 Riverpod 3：所有 provider 通知统一按 `==` 过滤（含流事件）。因此：

- store state 与 ViewProvider 产物必须不可变且实现结构相等；revision、水位与
  代次参与相等，canonical 前进永远不满足相等短路。
- 禁止原地修改集合或「同引用重新赋值」传递更新；集合更新必须产生新实例。
- family 参数必须实现稳定 `==`/`hashCode`（threadId、projectId、rootThreadId 等
  稳定字符串标识满足要求）。

## 25.10 验收观测

Flutter Driver / 验收工具的观测快照从 store 与 ViewProvider 派生，是同一事实源
的只读投影；不再存在与 Riverpod 状态平行的静态发布通道。既有验收 key 的语义
保持不变，观测面迁移只改数据来源，不改产品契约。demo 数据源与真实 FRB 数据源
实现同一 Bridge 数据契约，上层分层不感知差异。

该一致性是验收可信的前提，因此 demo 必须**逐条实现真实侧会发出的帧**，而不是只
让命令返回正确的快照：命令若在 native 侧同时推进 topic/有序流水位，demo 也必须
发出对应帧并推进同一水位。只发响应而不发帧的 demo 会让「帧丢失」被命令响应路径
掩盖，`--demo` 验收在真实构建回归时仍然变绿。已识别的 demo 实现缺口：配置与模型
目录在 demo 中共用同一 revision，使 §25.4 的双时钟分支在 demo 不可达；在该缺口关闭
前，settings 双时钟相关收敛不得只依赖 `--demo` 结论。

两条例外按本节约束成立：其一，纯 UI 诊断（timeline 滚动几何、活动条展开态、
关机阶段等不属于任何领域 store 的瞬时观测）保留静态发布入口，仅供驱动断言，
不得回流业务；其二，FRB 数据源层内联的 canonical settings 双时钟合并投影与
settings store 的投影语义一致但实现独立——store 依赖数据源，反向复用会成环，
该分层例外在数据源层注释中标注，修改任一侧必须同步另一侧。

## 25.11 旧实现的下线

以下旧机制整体删除，不迁移：巨型聚合 state 与其单一 controller、settings/thread
双 intent generation map、settings 写屏障与 mutation coordinator 的 failure-free
Future 链、有界 `flushPending` 与 pop 拦截、导航可见性协调器（observer 推断业务
可见性）、三层并存的 settings merge 路径、零消费者的死投影类型与成环 selector、
legacy 转发 selector 层、按页面复制的租约样板。设置/线程 reducer 的领域纯函数
语义保留并拆分进对应 store；[18](./18-studio-state.md) 与 [19](./19-studio-ui.md)
中与本文冲突的旧 Dart 侧契约已按本文修订。
