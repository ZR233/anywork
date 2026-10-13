# 25 - Flutter 前端状态与资源生命周期

> 本篇是前端状态的目标契约。内容出口收敛（唯一 ChatView、删除 Dart transport 补丁基线、删除 GUI 普通 SQL 分页旁路、控制操作返回回执）已在 5a8210 落地；随后补页门控、窗口操作确认与旧绑定清理竞争按本节标注推进。不能用「内容出口已经统一」推导出「前端性能重构已经完成」，也不能把尚未存在的规范化 ChatState 写成实施状态。
>
> 对照基线：内容出口收敛 `5a8210f3525cc9eb7da7eb3f6f5dcf9815e14cef`。合入后续切片时必须与 Rust 流协议、调用方及测试一起切换。
>
> **已实现（Dart/core 源码可核对；Windows 原生性能未测）：**
> - 唯一内容泵消费 ChatView 首帧与后续帧；transport 不再维护第二份补丁基线。
> - Timeline 使用窗口交付的 `hasOlder` / `hasNewer` / `canExtendLatest`，不以「有无命令回调」推断补页能力；自动补页在边界/容量未变时不因 loading 落沿重复发起；core 的 extendLatest no-op 不推进版本、不发内容帧。
> - load / extendLatest 在第一个 await 之前占位；回执版本未超过已观察窗口时按 NoChange 结束，不等待不会出现的内容帧；旧操作 token 不能结束新占位。
> - 旧订阅释放只清理自己捕获的资源；await 之后若已有新绑定或新附件，不得清空当前窗口。
> - 缺少 ChatWindowReader 标为内容同步失败，不再静默当成空窗口。
> - 窗口内相同 Latest / 仍可见的 Around 焦点在 core 为 no-op：不推进 generation、不通知。
>
> **部分实现：**
> - 停止命令在点击时冻结 turnId，执行时校验同一轮；普通命令仍是跨会话共享 lane。
> - 内容绑定有身份与泵，但尚未收敛为完整 Idle / Opening / Streaming / Reconnecting / Closed / Failed 状态机；打开成功即复位退避、EOF 与静默 catch 仍不完整。
> - 像素滚动在已浏览同一 item 时跳过 native focus；从跟随最新切入历史阅读仍会 focus。
>
> **尚未实施：**
> - 结构与正文分离的 ChatState（`orderedItemIds` / `itemsById` / 独立 sync）；正文变化仍扇出整个 session / 工作区。
> - 增量显示投影（去掉热路径整窗排序、全文拼接与无条件重分组）。
> - 统一 viewport controller；消除两段 post-frame 底部跟随。
> - expand 结构化结果（Retained / AlreadyComplete / NotInWindow / Unavailable / Superseded）；当前仍由 Option 推断 retained。
> - 删除宿主 Timeline fallback；资源级命令串行；route pending 等实际观察收敛。
> - Windows profile / release 原生性能验收。

本篇定义 Dart read model、命令、草稿、页面与订阅的职责。Rust 的可靠历史/恢复见 15/16/17；产品资源与版本见 18；呈现与滚动见 19；流协议见 07。文档各自拥有自己的定义，其他篇引用而不重新定义一套规则。

## 25.1 核心约束

Rust 是业务事实 owner。Dart 保存供展示的唯一只读镜像，不在本地重新裁决领域状态。对同一资源，一个 reducer 接收全部权威帧；transport 不保留另一份合并后的 canonical。

单一接收者以资源和订阅为作用域，不要求全应用一个巨型总线。配置、目录、会话状态和聊天内容是独立资源。派生视图只做组合，不反向写 canonical。

## 25.2 分层

```text
Widget → 用户 intent → 命令服务 → typed transport → Rust owner
Widget ← 小型 selector ← feature read model ← 有序帧 ← Rust owner
```

复杂 feature 可以有 Binding + Reducer + ReadModel + Selector；简单 feature 不必机械复制所有层。Transport 不依赖 store、Widget 或 Riverpod Ref；read model 不依赖 Widget。命令服务不直接改 canonical，只维护用户操作结果并等待 owner 帧。

资源版本/owner epoch 是业务流身份，客户端 Binding 身份只用于拒收旧订阅回调；不能因订阅重开便让命令回执失去可比较的资源身份。owner 实例确实更换时，以 Reset 和 operation 查询重新确认，不能跨 epoch 比较 revision。

生成 DTO 是协议表示；只有确实存在 UI 语义差别时才生成/定义独立 view 类型。不得为了分层把同一个完整对象在多个目录手工镜像。

## 25.3 状态种类

| 状态 | 所有者 | 生命周期 |
|---|---|---|
| 执行、配置、目录、可靠历史 | Rust 领域 owner | 领域生命周期 |
| canonical 显示镜像 | 对应 feature read model | 必要观察期；重型数据严格有界 |
| 用户未提交输入和选项 | 明确的 route/thread draft controller | 产品规定的草稿周期，不由流覆盖 |
| 已提交命令的 pending/failed | mutation 状态 | operationId 从提交到确认/失败 |
| 滚动、焦点、折叠、动画 | Widget 或 UI controller | 页面/窗口周期 |

configuration 与 model catalog 分别建 read model，组合显示由纯 selector 完成，不保留两份配置/目录双时钟合并函数。显示优先级为明确草稿，其次当前 operation 的 pending 目标，最后 canonical。

## 25.4 观察生命周期

App-root 在 Navigator 之外维持必要配置和当前选中会话的小型执行/保存状态观察。页面不再以“仍挂载”为理由假定 Riverpod 监听持续活跃。

聊天正文在有显示需求时打开 ChatView。不可见时可以停止内容消费或关闭 view；返回后获得最新有界 Reset。Rust 执行、可靠事实保存和必要后台投影不依赖 Dart 是否观察。停止观察不等于停止 Turn。

每个 Binding 拥有自己的 native handle、取消信号和有效性身份。失效时立即拒绝迟到回调，再取消本绑定资源。跨 await 的回调需同时检查 Ref 生命周期与 Binding 身份。旧清理只能释放捕获的旧资源，不能清空新绑定内容。

keepAlive 仅用于明确需要驻留的轻状态；不能让每个曾浏览的会话永久持有正文窗口。close 必须有可取消路径，应用退出需要等待实际资源收束，不能用 Dart 对象已回收推断 Rust 已关闭。

## 25.5 聊天内容协议

唯一内容出口为 ChatView.next：首帧 Reset，之后 Reset/Patch。同一 view 同时仅一个未完成 next，前一帧进入 reducer 后才取下一帧。load/focus/expand 仅返回 operation 回执，权威内容仍从同一出口交付。**已实施。**

控制操作不能改变“客户端已收到”的 baseline。focus/load 与 next 的并发由 Rust view 协调；next 的 readiness 等待在窗口锁外，关闭能打断等待。传输层不得自行生成新窗口事实。**已实施。**

窗口控制结果区分 Applied / NoChange / Superseded / Cancelled / Failed。占位发生在第一个 await 之前；Applied 要等匹配的窗口变化进入 read model；NoChange（回执版本未超过已观察窗口，或能力门控判定无事可做）直接结束且终止本轮自动补页，不等待不会出现的内容帧；旧操作不能清除新操作的 loading。回执里的 version 来自会话进度，ChatUpdates 会跳过当前窗口不可见的变化，因此不能把任意采样的全局 version 当作必须在内容帧出现的完成水位。**NoChange 与占位已实施；结构化 disposition 枚举与同流操作完成标记仍待实施。**

Patch 仅在 view/epoch 匹配且 from 等于本地版本时应用，to 必须更大但无需恰好加一；from 匹配时 to ≤ from 拒收并要求 resync。缺口恢复只影响该 view。旧绑定帧不能借新 epoch 覆盖新会话。Reset 来自 core 对尾部、可靠待保存事实和历史的统一视图，不由 Dart 再读 SQL 补齐。**from/to 防线已实施。**

正文是稳定 item/part 身份上的 typed 字段更新，不由字符串形状、当前选中消息或最新一行推断目标。正文终态和保存状态独立；保存确认不删除行、重新查询再插入。

## 25.6 Read model 与通知

ChatState 保存 view stamp、有界 orderedItemIds、有界 itemsById、分页边界和连接状态。阅读意图/像素锚点归 UI，不混入 Rust 执行状态。**尚未实施：** 当前仍是 workspace.items 加整窗投影；外层 pane / 输入区 / header 仍观察整个 session。

内容字段变化不生成新的 ID 序列。列表观察结构，行观察自己的 item；工具/推理活动摘要和输入区分开观察。单行相等性只受本行内容与显示状态影响，不能包含所有消息共有的全局 revision。

所有 canonical 值不可变。允许有界 Map/列表复制，但不能为“结构相等”每帧深比较整段巨大正文。优先复用未变对象，以明确内容版本标识变化，并保证保存、状态等可见变化也参与对应 selector。

## 25.7 命令

命令提交时冻结资源身份；执行时重新校验该资源的最新版本。不在排队后的回调中重新读取当前选中对象作为目标。

同一资源冲突写串行，不同资源可以并行。取消/停止不经过长任务 FIFO。只读 body/分页不占用设置或执行命令队列。相同幂等查询可合并为一个在途请求，取消一个观察者不应取消仍被其他观察者使用的共享请求。

命令成功返回 operationId、创建对象 identity 和受影响资源版本。canonical 只由资源观察帧写入；成功后不 readStudioState/重新读取目录或 Thread snapshot 来掩盖缺帧。

Pending 完成条件是该 operation 成功并且本地观察到相关资源目标版本。帧早于响应到达也应正确；旧命令不能清掉后提交的新目标。断连时保留最后事实与明确等待同步状态；恢复通过局部 Reset 或按 operationId 查结果。**窗口 load/extend 的占位、NoChange 与旧 token 隔离已实施；route pending 等实际观察收敛、设置与新建会话的因果依赖仍待实施。**

冲突重基仅适用于可安全重做的字段修改。网络错误不代表未执行，不幂等业务不能自动重放。设置命令与使用设置新建会话存在明确因果依赖，不能以“读取此刻缓存”替代命令完成关系。导航不等待写入；依赖写入结果的业务动作自行协调。

## 25.8 草稿与呈现

草稿控制器只能写用户意图，不得写 canonical。canonical 到达不抹掉未提交输入；提交完成后按 operationId 结束对应草稿。Thread 草稿的保留/清除由产品规定，不能让页面暂停意外删除输入。

连接组件从 provider 取得全部事实；纯显示组件只使用构造输入。同一组件不得在 props 和 provider 之间运行时选择事实来源。

Widget key 基于稳定 identity。Turn 的视觉分组不改变 item 身份，也不要求一个 Turn 是一个无限增长的 Widget。文本作为主要内容，工具、推理与运行提示按照 19 的呈现规范组织。

## 25.9 重试、错误与恢复

provider build 不执行写业务。自动重试仅用于允许重试的读取/观察初始化，显式区分暂时性传输故障与权限/schema/存储损坏等终止错误。重同步保留最后有效内容，不把数据不可用渲染为空列表或已到历史尽头。

ref.mounted 只证明生命周期，不证明请求仍属于当前视图。异步结果使用 binding/view/operation 身份校验；必要代次不能以“简化”为由删除，也不按每个字段建立重复 generation map。

持久化失败只由 Rust typed 状态表示，GUI 不解析错误文本推导健康。重试保存与恢复执行是不同命令，按照 15/18 的故障版本和水位控制。

## 25.10 观测与验证

测试观察同一个 read model 和 Widget 输出，不维护平行静态业务状态。允许只读的帧时延、重建次数、字节交付、滚动几何与资源计数；这些数据不得写回业务。

Dart fake 用于纯 reducer、provider 生命周期与组件测试；真实 Rust fixture/FRB 用于端到端收敛、持久化与背压。Demo 不得代替生产协议，也不得通过正确的命令响应掩盖缺失的状态帧。

最低验证包括：首帧与增量连续；load/focus/next 交错；快速 A→B→A；页面不可见时 provider 暂停；响应和帧两种先后顺序；迟到旧清理；同版本/旧版本/跨 epoch 帧；大正文与工具输出；慢消费者；writer 失败；退出取消等待。性能数值以 README 计划中的校准预算和原生 profile 记录为准。

## 25.11 下线项

下线 GUI 普通历史页与实时项的双路合并、FRB adapter 中的第二 canonical baseline、全应用命令后快照刷新、Timeline props/provider fallback、无状态但包装成 Notifier 的空命令 state、配置/目录重复合并、可选 ChatWindowReader 静默后备、无消费者旧别名。

保留有实际用途的独立查询、原生平台支持、供应商协议适配和必要资源代次；它们不是仅因复杂便应删除的“历史包袱”。切换完成后生产只保留新路径，生成文件、测试与文档同时更新。
