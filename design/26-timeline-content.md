# 26 - 原子完成事实与增量展示快照

本文维护 Native 完成内容及 GUI 展示契约，依据 [#364](https://github.com/ZR233/anywork/issues/364) 替换 #316 的按来源开放组、后台结果独立封组、空 Started 切组及来源结束封组规则；保留 #311 的不可变完成原件、统一受理、唯一保存链与 State 业务引用。这里定义合同，不以文档更新冒充实现或性能验收。ACP 外部协议保证不变。执行保存归 [15](./15-session-storage.md)，迁移归 [17](./17-studio-storage.md)，传输归 [07](./07-streaming.md)，客户端资源归 [25](./25-frontend-state.md)，视觉归 [19](./19-studio-ui.md)。

## 26.1 两个完成点与唯一所有者

**开始、首次内容可读与结束是不同事实；每个 Native Thread 只有一个可继续追加的工作尾组，只有首次可靠可显示的独立 Single 才冻结它。** 来源结束、正常成功 Turn 完成、空闲、执行 owner 关闭和冷重开不切组。同组开始/结束合并一行；封存后成员、状态、内容与摘要不回填，迟到终态加入当前尾组。完成原件和展示冻结各有序号，可靠落库不等于已封存或正在执行。

显式用户文件展示沿原工具完成记录封存，不增加独立历史 writer。`builtin.show_files@1` 的 renderer 消费 [09](./09-tool-runtime.md) 定义的 `pl.tool.files@1`，保留成功／失败顺序，成功附件从同一回执的可靠资源引用派生。归档资源的读取资格同时覆盖驻留、pending 和持久回执，冷重开不重新执行工具或读取源文件。旧图片展示格式保留必要只读解码。

新文件展示工具的原子由原 Native owner 标记为 `Independent`，沿既有分类规则产生 `Single`，使文件格直接出现在主时间线，而不隐藏在默认折叠的工作记录中。保留原 Turn 来源、调用身份与完成顺序，不由 Flutter 解析 payload 后重新分类；普通工具及旧图片历史的分类不变。

图片复用原图片 owner；Markdown 和保存按需读取原资源，二进制不进入 ViewState。来源定位元数据不能授予额外读取权限。外部交付状态归发送领域，不回写不可变完成记录；历史打开、GUI 重绘和重新订阅不得发送外部消息。渠道交付使用 [27](./27-bots.md) 的明确来源绑定，不以时间线可见性或附件存在推导外发资格。

Markdown 语法与流式未闭合内容由上游渲染组件解析，采用其 CommonMark 与扩展语法，不在客户端维护第二套修复解析器。解析规则升级只改变展示，不改写已保存原文；普通纯文本继续保真选择与复制。不安全链接不得取得交互手势，来源标签与图片沿原受控访问入口处理；上游支持 HTML 或新增语法不授予额外外发、资源读取或执行权限。

**完成一次，记录一次；历史内容不更新；工作组只是界面组合。** 已接纳输入、完整模型文本/思考 part、工具真实终态、后台启动交接回执、后台最终结果以及完整业务回执，分别形成不可变完成记录。后台启动和最终结果是不同身份，启动不等于成功。停止请求、页面关闭、推测 EOF、token 暂停和模型自述不构成终态。协议没有可靠独立 part 终态时使用最终 attempt 回执；正常失败/取消收束可以冻结已接纳前缀并标记真实结果，异常退出前未完成的前缀不承诺恢复。

| 所有者 | 职责 |
| --- | --- |
| 原 Core Thread / 业务 producer | 真实执行准入、成员开始/终态、来源事实、可靠 effect、检查点与上下文 |
| 原 Native live owner | 完成封存、读取分类、增量展示段与成员关系、同切面发布 |
| Core Session | 原件 seq/run 分配、精确幂等、完整 pending、统一原件读取；不解析展示 metadata |
| 原 HistoryChannel / 唯一 writer | 原件、内容、检查点与冻结展示增量同事务保存，原背压及提交确认 |
| Feed / FRB / HTTP / SDK | 有界读取、固定目标补读、机械串行接纳、信用与资格 |
| Flutter 原 controller / display lease | 一冻结块一卡、局部展开与滚动、历史插入和实时退役的同次公开 |

原 `ChatDraft → ChatItem` 和 `conversation_items` 是唯一完成原件；`conversation_atom_facts` 分别保存轻量 start/terminal 事实，不以展示合并覆盖原件。边界时原 owner 从同一 effect 捕获未结束成员的公开状态、参数和内容前缀，沿原 immutable chunks/content store 保存派生显示快照。它证明当时显示了什么，不是第三条业务事件或执行状态来源；展示头只持小头、身份、引用及计数。无新 actor、线程、全局注册表、writer、可靠展示队列或保存定时器。真实 Plan、交互和配置仍由原领域 State 管理。

会话资源沿原 Session → AgentRuntime → NativeResources 持有，执行与检查点继续归 Core owner；展示投影和当前状态属于稳定的 Native ConversationStore，原观察工作者只持执行绑定及串行驱动，不建立另一份成员登记。关闭先同步撤销发布和新读资格，再由原会话关闭任务汇合订阅、观察及在途读取。冷读只借已保存快照，不物化 Native、不重算分组、不推进计时。

State 与内容是独立资源：Repository 是 Dart State 唯一写入口，State feed 独立确认、恢复和关闭；Timeline、完成内容及成员读取不转发第二份 State，也不因暂停内容信用阻塞状态终态或统计。GUI 的展示流替代旧完成内容流承担卡片交付，不替代 State feed；非 GUI 完成级消费者继续使用原内容接口。本次整组交接规则替代旧版“活动临时组合、不延续历史身份”的约定，而不是撤销状态/内容分域或会话资源所有权。

当前正文／思考活动的资格由原 owner 已可靠准入且仍 Active 的同 Turn、同 attempt 原子决定；有界 progress 只为这些原子提供当前摘要，不单独创造活动资格。缺少 progress 窗口不撤销真实 Active 原子，已结束原子的残留 progress 也不能恢复旧正文或思考。State 独立交付不等于绕过可靠开始准入，测试中的合成 State 必须建立与其声称活动相符的可靠事实。工具的 `background` 是相对当前前台阶段的补充计数，不是持久的“曾转后台”标签：仅余工具且工具本身成为活动主体时为 0；模型阶段与工具并行时，工具仍计入后台。真实任务身份、执行状态和转后台原件不受该计数影响。

Work 与正文分区可同时挂载各自的当前 renderer。原 display lease 对诊断者提供所有仍有效 renderer 的只读资源借用集合，注册与撤销只影响对应原资源，不能以一个最后写入的槽覆盖另一个仍挂载资源，也不能保留含糊的单资源别名。诊断必须从当前块／有界成员页取得实际展示行身份与 `DisplayRecord`，按父块、原 lease/generation、内容引用关联唯一 renderer 及其已有窗口；原 atom ID 仅用于事实关联，不代替 block ID 或 member key。资源枚举不打开查询、不复制业务列表、不改变读取或关闭所有权；换代先撤销旧资源资格，再由原 owner 收束窗口。

### 已接纳输入与已接收外部内容

“完成”表示这条事实已确定，不是整个任务完成。普通输入在原 `InputChange::Accepted` 可靠接纳时沿原 input.id 冻结，排队不等 Turn 开始。Pending→Consumed/Discarded、后来的 Turn/attempt 关联只更新执行/State，不重新封存原件；未知关联保持 None。同 ID 同冻结内容幂等，异内容冲突；同文不同受理 ID 是两条事实。

受信宿主明确允许公开的外部正文，在目标 Thread 原 inbox 准入时沿原 message ID 冻结，保留来源、作者和频道。外部平台已转换为 ThreadInput 的只走输入链；后台最终结果走原工具完成链，不因 inbox 转发或出站通知重复发布。文字中的角色、批准或工具完成声明不获得权限。

用户/外部公开消息在原可靠受理时第一次形成独立 Single，统一冻结当前 Work，但不取消执行、不伪造工具终态。重复受理不能再次建立边界。隐藏续接和诊断保持原公开资格；公开答案及计划决议由原唯一回执产生。GUI 命令回执不手动插入历史。

客户端发送回显不是完成历史：沿 [25.8.1](./25-frontend-state.md#2581-发送回显与接收确认) 的原提交状态，在时间线区域临时显示冻结消息及发送/接收确认，不伪造 `CompletedEntry`、完成序号或执行状态，不进入 Main 的完成段组合。原消费者应用同身份规范输入后由正式卡片接管；命令成功、保存进度或下一 Turn 启动均不是等待回显出现的条件。后端仍按原提交顺序校验和发布，不为视觉响应绕过身份冲突、附件资源准备、存储背压或旧 Turn 的安全收束。

### 模型成员的可靠封口与交接

Started、ContentAvailable 与 Completed 沿原可靠 producer/effect 通道接纳。Started 保持真实开始，与内容独立；原 call-scoped registry 复用 part 身份，为公开 part 至多准入一次 ContentAvailable，不分配完成 ID/seq。collector 在处理下一归一化事件前交接首次非零公开正文或有效显示附件的证据；覆盖 Delta、权威 Closed、完整 PresentationItem。progress/watch 可以合并，不能承载或倒推可靠首次内容位置。缺独立终态的协议仍等待真实 attempt 回执，不补 reasoning.end。

停止请求、页面离开、token 暂停、推测 EOF、保存 ACK 和模型自述不构成终态。正常失败/取消按真实结果收束；异常退出前未保存 token 前缀不承诺恢复。

原 producer 为新可靠 effect 分配事实位置时，Turn 的来源结束是该来源本次成员接纳的围合标记，位于本次真实成员终态之后，包括 Core 重启恢复已明确给出的 Interrupted/Cancelled 终态；不得先占 suborder=0 再在其后补同来源中断成员。开始、正文 Started、工具/后台交接及独立业务回执仍保留各自真实因果顺序，不为展示移位；只有表达该 Turn 最终收束的派生回执在相应成员终态之后。来源结束不等待独立后台来源，也不把停止请求升级为完成。位置分配须受检且确定，不以饱和运算制造顺序别名；确认丢失重放复用原冻结位置与材料，不按最新内存重新排序。

同批出现边界和成员终态，仍以完整可靠 `(effect_seq,suborder)` 判断谁先接纳：只有终态不晚于该边界时，才可免去该行未结束观察的捕获；同批较晚终态不能使边界前观察消失。所需不可变材料由原 owner 在退役前保留到 PreparedEffect，禁止从稍后原件或最新动态引用补读。新捕获失败仍使原 effect 失败，不能借“不可用”吞掉内部缺失。

## 26.2 展示身份、来源与真实边界

原件 `item_id` 是稳定业务身份，`seq` 是完成发布顺序，范围为 `1..=i64::MAX`，由原 Session 在 RAM 分配，不是时间戳或开始顺序。原件历史始终按完成 seq，不反向改写。

展示组不按来源分桶。唯一 open_work 接纳前台、后台与旧 Turn 的所有新 Work；关联键仍由 typed source、真实 atom/call/part ID 与责任阶段组成。当前组已有同键行则补真实终态并保留 member_key/位置/total；没有则新增 terminal-only 行，不查旧组、不补开始。原业务准入必须拒绝重复派发，不能因旧行已释放再次插入。段首 source/source_key 只作诊断；成员保留各自来源，捕获校验成员自己的来源、关联键和阶段，不要求等于组头来源。ID 不透明，既有已发布 ID、history_pos 不改。

同一 Native Thread 维护唯一未封存 Work、仅指向该组的关联索引及统一有序待发布块。结束只查询当前组同关联身份的开始行：存在则补充该行结束引用，不存在则按本次结束事实创建新行；合法 terminal-only 来源不补造开始。封存立即撤销旧组可更新资格，后续 progress/terminal 不回查历史、不命中旧成员位置。事实幂等和矛盾检查仍在原接纳/PreparedEffect 层，不因新组无开始而重复显示结束。统一按块顺序推进 ready 前缀，不重排已发布块。

| 输入 | 展示动作 |
| --- | --- |
| Work 开始/终态、后台结果、迟到终态 | 加入唯一尾组；同组同键补行，否则新增结束行 |
| SourceEnded、正常成功 Turn、idle、owner 关闭、冷重开 | 保留业务/保存责任，不切组 |
| 用户/外部公开输入、真实独立业务/文件/故障回执 | 首次可靠可显示时统一冻结 Work 并建立 Single |
| 空 Text Started/始终空 Closed | 保全真实开始和原件，不创建可见块或边界 |
| Text 首次公开内容/有效附件 | 一次 ContentAvailable→TextVisible，冻结 Work |
| 已可见 Text 后续 token/终态 | 只更新自身，不再次封组 |
| 曾可见 Text 权威终值为空 | 保留边界，显示 FinalEmptyAfterContent |
| ACK、COMMIT、绘制、计时、批次 | 均不产生边界 |

冻结条件是首次可靠可显示 Single 的边界；历史前沿只越过全部已冻结的创建位置。复用原 BTreeMap 作为唯一有序容器，不另建来源队列或全局顺序副本。未结束正文可以挡住后继历史位置，但不挡原件保存及 live 窗口呈现。冻结立即撤销组更新资格，不等未结束任务；边界材料先 fallible 准备再提交 fold，每批只索引一次终态位置，不能用未来终态免去边界前捕获。

目标故事：A/R 开始进入 G1；空 Text Opened→空 Closed 不切 G1；后台 X 完成加入 G1；T 首次有内容冻结 G1 并建立 T；B 开始创建 G2，旧 A/R 与后台 Y 的迟到结束进入 G2；T 终态只更新 T，不再切 G2。全部暂时空闲、关闭及重开后仍为同 ID 的 G2；新用户输入受理才冻结 G2，下一条工作事实创建 G3。

普通工具和后台结果都是 Work，不因终态、来源或工具文字成为 Single。前台 Transferred 与后台最终结果保留不同责任身份，不误合。明确文件展示由原 typed producer 赋予 Single 资格；读取图片仍属工作成员，不按 MIME 或客户端解析结果重新分类。真实独立 Plan/交互回执、公开失败/取消/中断回执按各自产品合同首次建立 Single。SourceEnded 仅保留业务事实，不进入 冻结链，也不新增 ThreadSettled 展示事件。

既有已发布 Single 普通工具结果通过正式派生展示迁移转换为单成员 Work；只改变展示形态，保留原块身份、既有显示顺序和成员身份、原完成记录与原子事实。不将多个已发布块回溯合并，不重排或回填已封存前台组；独立文件展示等非目标记录保持原样。迁移须可安全重入，升级后重开与成员读取继续沿原身份工作。

### 空正文与附件

任务查询的版本化机器载荷属于既有工具成员的 `output_artifacts`，来源是同一原始结果而非展示标题。它不形成新的 Single／Work，不改变分组、历史顺序、完成事实或模型上下文；机器读取边界见 [09.1](./09-tool-runtime.md#91-工具身份所有权与历史落盘栅栏)。旧投影缺少此附件不授权从展示字符串猜测或补造原件。

零字节 Text Started 不建可见块、不封 Work，领域资格留在原调用 owner，不在展示层镜像空 part。原适配以一次 TextVisible 携 ContentAvailable 位置建块；DisplayHeader version3 增 first_content_at，首次填入后不改，DisplayRecord.start_fact 仍是真实开始。后续 token/progress/Terminal 只更新自己的 Text，不重复封闭后来创建的 Work。始终为空且无附件时保全原件但不建 Single；不 trim、不解析 Markdown，空白与未闭合 Markdown 保真。曾可见而权威终值为空且无附件时，保全真实空原件并以 SingleVisibility::FinalEmptyAfterContent 显示“该输出的最终内容为空”，不删除已发生边界。普通内容用 Content。RemoveEmpty 只限正式迁移中可证明从未可见的旧空壳，不用于新数据终值撤回。

仅附件消息有效。图片读取仍属原工具成员；媒体失败不拆组、不制造顶层工具失败、不改变业务终态。Hidden 分类不能通过文本外观猜测边界。

## 26.3 增量状态与保存交接

稳定的 ConversationStore 持有唯一展示投影。块第一次可见时分配正整数 `BlockOrder`，冻结后位置不变，允许序号洞；完成原件的 seq 和业务 effect_seq 各自独立。`last_order` 是已接纳的最大创建位置，空库为 0；`unready` 只含未冻结块，`ready_frontier` 为其最小位置减一，无未冻结块时等于 last_order。前沿单调前进，越过大量已冻结块时不逐行发布、不重新编号或复制头。来源结束、空闲和页面关闭不冻结唯一可追加工作尾组。

- H/D 仍表示完成原件的发布上界与已保存连续前缀，原 Session pending 完整覆盖 `(D,H]`。
- 展示历史范围为 `block_order <= ready_frontier`，尾部为 `(ready_frontier,last_order]`；冻结且已耐久的等待块可立即回收，不能据前沿判断是否已耐久。
- 展示增量只携该 effect 实际改变的头、成员、观察内容及同切面的 effect_seq、ready_frontier、last_order，不带逐块发布列表或普通删除空壳动作。writer 不读取后来变化的 Store 补字段。

原 writer 在一个事务保存 effect、checkpoint/context、原件、内容、展示增量及水位，任一失败整批回滚。精确重放复用同冻结材料和原提交凭据；不允许 OR REPLACE、无条件旧头覆盖、OR IGNORE 吞冲突或异步修复队列。同一 writer 批次可合并同一小头中间写值，但保留所有成员和原业务增量。

成功确认只对应实际批次，不等 GUI ACK、不制造展示事件。长期尾组保留小头、内部未完成计数、下一 member_order、未结束关联和未保存责任；按每批实际变动位置释放已耐久 terminal 行及正文驻留引用，复用 sparse overlay/成员索引，不等封组、不每次 COMMIT 扫全组。已释放事实靠原准入/effect 位置及处理水位幂等，不新建永久全会话 ID 缓存。查询沿短锁捕获切点、共享引用与其后 SQLite 短读快照补齐，不跨 await 持投影锁。

## 26.4 展示快照、冷打开与恢复

Store 的冷态、初始化中、就绪和失败是明确的生命周期状态，不由订阅数推断。冷读先在生命周期 gate 外取得可取消的数据库读连接，再在 gate 内重新核对模式，并以首次元数据 SELECT 建立 SQLite 快照；仅 BEGIN DEFERRED 不构成切面。随后释放 gate，在同一短事务内读取所请求的有界页。初始化可以在页面读取期间启动，不能改变已经建立的快照。若已进入初始化，读者等待 Store 保留的同一个恢复结果；取消单个等待者不放弃该结果，也不另开忽略待恢复状态的冷读。

就绪时在短同步边界捕获数据库身份、完成及展示上界，以及请求窗口的共享引用，再在锁外补读 SQLite。捕获时仍可变的行覆盖随后数据库中的同键行，上界排除切面之后新增的行；未保存冻结材料和可变行保留在 RAM。只有冻结且真实提交的材料具备释放资格，保存确认不依赖执行驱动仍存活或 GUI 确认。数据库身份失效时明确结束旧读取，不把新库接作旧游标续页。执行驱动退出不撤销仍持有 Store 的内容读资格；整个运行时关闭则沿原全局取消边界撤销旧资格，并等待在途读取结束。


冻结观察的公开 payload 复用原聊天内容编码器的 `anywork.chat/1` 信封、类型描述和
`bodies` 清单。内部 `ThreadItemState` JSON 不能直接作为公开 payload；正文 chunk
已经保存也不表示缺失正文清单的 payload 可读。观察入口按边界切面的真实活动状态编码，
包括 Streaming 和工具仍在运行、等待的状态；完成原件入口仍严格拒绝未终态成员。
两入口共享类型与正文编码规则，不伪造 completion、终态或结束时间来套用完成入口，
也不在投影或客户端建立第二套 codec。

原 owner 先保留同切面的公开状态和不可变内容材料，展示块及成员身份确定后，再在原
PreparedEffect 内生成观察 payload。参数、摘要和正文清单中的内容引用均属于该
DisplayObservation 自有命名空间，不借用当前 atom 或未来完成原件；捕获时刻和可靠
位置仍表示观察切面，不充当业务完成事实。公开信封和正文引用必须由真实 producer
路径及原 reader 的内容窗口验证，不能仅用带人工正文的 descriptor 证明可读。

存储表和迁移归 [17](./17-studio-storage.md)。块小头保存种类、来源、boundary、计数、真实时间、有界概要和内容/成员引用，不保存全成员 ID 数组、全部 ChatAtom、正文、完整 payload 或 ThreadSnapshot。成员保存展示行身份、关联身份、顺序、可空开始/结束事实引用及类型化内容来源。完成原件使用真实 completion_id；未结束观察使用独立命名的 sealed 显示快照，不分配 completion ID 或 finished_at。冻结引用不得指向会变化的当前 atom，也不能仅存 generation/长度后再读最新前缀。

历史、尾部和成员页均按同方向、同键范围有界读取。短 Store 锁捕获数据库身份、修订、前沿、最大位置、目标组头及成员上界，并保留请求范围前 K 个驻留行的不可变 Arc；随后在锁外新建 SQLite 短快照，查询同范围前 K 行。按键归并至多 2K 个候选，捕获 Arc 始终覆盖同键数据库行，再以 K/字节预算截成完整行。数据库查询不先按 sealed 或 terminal 过滤，避免旧数据库状态改变候选集合；合并后才解释冻结状态。新增键由 captured last_order/next_member 排除，旧值由 captured Arc 保留。每个独立页形成新切面，不承诺跨页长快照。

两个可丢弃的驻留下界分别证明块尾部和当前组成员尾部的完整覆盖。冷恢复从已知最大位置加一开始，回收位置 q 后下界只向 q+1 提升；溢出时放弃证明。DESC 足 K 行且候选均在完整范围内，或整个请求范围已覆盖时可零 SQL；ASC 必须从完整范围内开始。仅有 K 行驻留不足以跳过夹在其中的数据库行。不满足证明则执行一次有界查询，不补 COUNT、存在性查询、全历史检查或正文解码。

游标绑定库、读取资格、展示版本、上界和排他位置，非空边界必须为正。分页按实际交付的最后键推进；已检查完的空洞和空页允许推进到目标上界，字节拆页不跳过未交付行。旧页可保守返回继续尝试的游标，正常空页确认结束。最小元数据仍超出预算时明确报错，不返回游标不动的空页。

热 current 头和摘要直接读内存；成员轻量头按序页读。历史/冷成员从展示索引读取，不用原完成 seq 范围猜组。明确请求的成员正文、payload 与媒体才按 completion_id/ContentRef 走原 RAM 优先、SQLite 补齐及范围预算。

冷打开只读取同一 SQLite 切面的元数据和所需历史／尾部页，不 hydrate 可变集合、不激活执行。执行附加前按开放头索引和未结束成员索引分块恢复全部可变行、唯一尾组、计数和必要关联；不加载已冻结等待块或长期尾组的已耐久终态成员。全 Terminal 的开放尾组静态 Resting，不标未恢复；仅冷源且有未收束/不可用成员为 Unrestored。sealed 待发布块永不恢复更新资格。Core 的真实中断/恢复事实仍按唯一尾组接纳；无执行 owner 不造业务终态；经过时间仍按未封口组的开始时间计算。Applied 后坏结构或引用明确拒绝并保原件，不在线重建。

## 26.5 展示协议与同切面交付

公共展示协议为 presentation_version=6，严格匹配，错误版本明确拒绝，不双轨解码。DisplayBlockRef 绑定 database_id/block_id；DisplayBlock 携稳定 id/block_order/body。Work 仅持 WorkTiming（可空 startedAt、可空 finishedAt，均为 Unix 秒；旧组缺少可靠时间时保留 null）和成员引用；Single 持 DisplayRecord 与 SingleVisibility。LiveDisplayBlock 额外交付当前组的 hasUnfinishedMembers 和有界 thinkingSummary；后者由原工作组投影接收流式及完成摘要，仅驻留内存，封口后释放，不写历史快照，Flutter 不再读取另一份活动摘要作为组标题兜底。未完成资格直接由原 owner 的结构计数派生，不再交付或保存组级结果统计。


LiveDisplayWindow 携 revision、ready_frontier=P、execution_present、current_work_id、有界 blocks 和 older。current_work_id 由 Rust owner 唯一确定，规范最新窗口必须包含它指向的未 sealed Work；预算不足明确 InvalidDemand，不丢头让客户端猜。旧页只描述该页，不写回规范最新身份。更早窗口保留原读取资格与结构代次；token 不换代，stale 只刷新受影响 live 窗口。execution_present 只证明资源存在，不证明正在工作。

每个 LiveDisplayBlock 的可空 typed source 仍直接来自 DisplayHeader.source，保留作段首来源诊断；它不表示所有成员共同来源，不决定布局、当前组、活动资格或恢复多个 lane。不得从块 ID、来源、activeTurnId 是否非空、lastOrNull 或分页末项推断当前组。

TimelineBatch 携 presentation_version、Set/Prepend/Append、blocks、before、from_order、through_order 及可空 live。GUI Timeline feed 仅交付 Timeline/Failure/Closed，不转发 State，也不同时交 Chat/Activity 让 Flutter 合并；状态沿独立 State feed。原 completedHistoryVersion=1、Thread State schema17 及原完成 feed 语义保留给完成级消费者。

1. 先登记观察再捕获 `(P0,live0)`；首 Set 建立同切面历史页与 live。
2. 后续固定目标 `(Pt,live_t)`，按预算追赶冻结头，不追逐无限变化目标。
3. 每帧一次追加本帧历史 blocks，并按相同 block_id 退役对应实时块；未交付块保留。
4. 未追至 Pt 的 live=None 表示保持剩余 live；只有追至 Pt 才替换完整 live_t。
5. P 不变但 live 变化时发送空 blocks、from_order=through_order=P、live=Some 的 Append，不枚举/操作历史 controller。
6. Prepend 不带 live、不推进订阅位置；独立查询不需要流 ACK。

SDK 与 Flutter 将历史插入和 live 退役作为一次可观察接纳提交：两者完成后才发一次视图更新并 ACK，不能先清空再异步查历史，也不能一帧双显同 ID。Dart 接纳不等待 Flutter 绘制。

watch 只保存最新切面并唤醒；漏中间通知不漏冻结头，后者在原 Store/SQLite。慢 GUI 只阻塞自身有限在途帧，不反压执行保存。query 短锁准入后锁外 IO，不等 events/credit；request_close 同步撤销准入并唤醒，close 汇合在途资源。旧成功、错误、finally 和 ACK 都复核原 lease，保护 A→B→A。

## 26.6 业务引用由 State 交付

ThreadBusinessRefs 只含 `plan: Option<CurrentPlanHead>` 与 `interactions: Option<CurrentCollectionRef>`，必填于 ThreadSnapshot；BusinessRefsChanged 整体替换两个引用，沿原 epoch/revision/信用接纳，不建第二订阅或业务 ACK。原 State.interactions/runtime.plan 保持可操作业务事实；引用仅供详情读取，不反向重建业务。

引用由原 Plan/交互 owner 在同一切面先建立可读内容后发布，只有真实领域变化才换代；token、查询、保存 ACK 和 GUI 组交接不推动它。冷读以同一短事务取得领域字段、Plan 引用和交互集合，不把无执行 owner 当成无业务引用。

状态与内容使用独立 Frame 身份、投递序号及有界信用，交付和关闭规则见 [07](./07-streaming.md#710-会话推送交付确认与关闭)。状态通道交付 State、Failure、Closed，完成级内容通道交付 Chat、Activity、Failure、Closed，GUI 展示通道交付 Timeline、Failure、Closed；首个 State 声明 completedHistoryVersion=1，不支持时明确 ProtocolVersionMismatch，不双解码。各通道 ACK 在实际接纳完成且原资格有效后推进，不等布局、query、详情或 SQLite，也不等待另一通道消费。低层已读位置不冒充外层 ACK；内容连续性丢失关闭原内容资格，新内容句柄以 Set 重同步，状态失连续只重建状态基线。

plan=None 为真无计划；Some/document=None 为有计划无文档。interactions=None 为未建立资源，已初始化空集合可有有效引用，不能吞失败为空。交互集合的 interaction_collection_revision 随原 Core checkpoint 保存，描述 permissions/interactions 联合集合，不用剩余单项最大 revision 或无关 effect 序号代替。transfer 与 resident 剪裁实际改变集合时分别 checked 推进，重复剪裁不推进；旧 schema6 缺字段只初始化 0，不猜过去代次或重写原件。

原 reader 的 read_business_refs 与 State 基线共用领域投影。一次性工具可查询，GUI 持续跟踪只消费 State，不在命令/Timeline 后补偿刷新。不恢复 ChatBatch.current，不把组和正文放进 State。

## 26.7 内容、成员窗口与资源

listContents/readContent/readAttachment/watchContent/pageCurrent 沿原 reader、权限、范围和短读租约。大正文按 offset 读取，不先拼全文再截取。ContentRef 绑定库/资格和 ItemPayload/Body；原执行内容向完成原件的 ContentBlock 移交不复制全文，追加不换 generation、替换才换。边界派生观察使用独立命名空间并共享 immutable chunks，不覆盖 canonical atom 内容；CurrentAtom→FrozenObservation 可更换内容引用，稳定不变的是所属块/行身份。普通内容窗口保留 offset、bytes、generation、availableThrough、sealed。

DisplayMemberWindow 为 Latest 或 Before{member_order}。DisplayMemberPage 携块引用、revision、sealed、有界轻量 entries 与 before。句柄首次 next 返回当前页，后续在该块成员结构/状态或封存资格改变时返回完整最新页；单个在途 next，接纳后再取。交付身份为 `(revision, sealed)`：封存若仅改变资格，可接同 revision 的封存页；若捕获改变了记录或内容引用，须推进 revision。普通重复、版本倒退及封存后新数据仍是错误。token 不触发成员列表重读；切换窗口替换观察，不拼不同 revision 的可变页。

成员页的 sealed 只表示**本次有界观察的快照不再变化**，不同于 DisplayHeader.sealed 的业务块冻结事实，也不等于全部成员 terminal。冷 saved-only 源没有成员变化订阅，首次 next 在原短读事务内取得该窗口的一致切面，以 sealed 页交付，之后正常 EOF；不为读取明细激活执行、促 flush、封组或分配第二展示位置。该切面在首次查询时形成，不承诺句柄创建时已固定全组，也不把多个 Before 窗口拼成跨 revision 的事务快照。同一 Store 的执行附加不替换读取身份，每页按当次模式捕获切面；原数据库身份、读取权限、source epoch、取消和资格复核仍适用，运行时重启或数据库身份变化明确使旧资格失效。

热源中业务块仍开放时，即使全部成员已 terminal，也继续原成员订阅，后续工作仍可更新该窗口；真实业务边界冻结块后交付 sealed 页，即使其中有未终态的 FrozenObservation。正常 EOF 前必须交付一张 sealed 页；首页缺失、未固定的热观察意外结束和资格失效仍是错误，不能以任意 EOF 充当完成。固定页不保持无用 watch，页封存或 EOF 都不能反向改写业务块小头。

DisplayMemberHead 含稳定 member_key/order、轻量 ChatAtom、可空开始/结束事实引用和类型化内容来源：CurrentAtom、FrozenObservation、CompletedOriginal。CurrentAtom 只用于开放行；FrozenObservation 绑定本库、本块/行及 sealed 内容命名空间，缺失旧切面明确 Unavailable，不回退最新内容；CompletedOriginal 使用真实 completion_id。同组开始/结束可同一行，跨组必须新 member_key；同一行实时到历史 ref/key 不变。组总数来自头，不用窗口长度覆盖。展开意图由 display lease 按 block_id 保存，不依赖跨父 Widget 移动自动保留 State。

共享形状统一为 `DisplayRecord { atom, start_fact: Option<ChatFactPosition>, end_fact: Option<ChatFactPosition>, content_source }`，Single 持一份 record，成员头持 member_key/order 及 record，不另复制可空 completion_id。`DisplayContentSource` 为 CurrentAtom、FrozenObservation{captured_at: Option<i64>, available: bool} 或 CompletedOriginal{completion_id: String}；FrozenObservation.available=false 明确旧切面不可用，不能授予动态内容读取资格。公开 payload/Body 引用在捕获时重写到 `ContentOwner::DisplayObservation{block_id,member_key}` 的独立 owner，沿原内容存储和权限读取；真实完成原件和媒体资源继续原身份。Live 的 `DisplayBlockState` 为 Open 或 Sealed，后者只表示已冻结待发布，不是 closing 等待成员结束。事实引用仅表示该展示行实际接纳的事实：跨组 terminal-only 新行的 start_fact 为 None，即使 atom 保留原执行 started 时间也不能声称本组收到过开始。

`available=false` 不仅约束正文：无法证明的旧等待/运行状态、公开参数和摘要也不得呈现为边界事实，显示中性“旧边界观察不可用”；能证明尚未终态时可同时说明“封存时尚未结束”。不可用证据属于具体成员，不维护组级未知、运行或等待计数，也不借较新摘要填补。新边界捕获必须完整，不能以 Unavailable 掩盖捕获失败。

`DisplayMembers` 是查询 scope 交出的有界只读观察能力，声明在 Client 公开会话领域接口；transport 使用同一能力类型。Feature 通过公开查询 API 使用它，不为取得类型导入底层传输端口。

完成卡的 Deferred payload 是原件定位，不是把业务卡降级为原始 JSON 的展示类型。实际挂载且仍有资格的 Single 卡或展开成员，沿原 `read_completed` 以 completion 身份、有界预算读取 canonical envelope，核对原件、atom、来源及完成身份后，复用原业务解码和 renderer；保留外层 block/member key、展开意图与 Main controller，不把解码结果回写展示头或另建消息列表。折叠 Work 不枚举或预读成员原件；正文、输出和媒体仍由原引用按各自窗口读取。metadata 单次读取采用现有 64 KiB 预算；若返回仍为 Deferred、身份矛盾或解码失败，明确呈现该限制或错误，不自动扩大预算、累计任意全文或把截断信封当作业务卡。离页、收起及资格换代撤销局部读取，迟到结果不得恢复已退役视图。底层原文范围查看器不承担业务 envelope 解码。

正文是否直接显示不取决于长度或外层信封的 Inline/Deferred：已挂载正文沿原有界窗口复用 Markdown、选择复制、换行与安全链接/媒体规则。已知用户 Input 的公开 Body 声明独立于外层预算，按明确归属于当前输入项的正文引用直接显示，不先要求解码原始信封；未知域及 `accepted.payload` 不推断为正文，缺声明保留诊断边界。工具和思考详情仍按语义折叠。文件卡继续消费显式 `pl.tool.files@1` 与原附件资源身份，保留 ready/failed 区别、跨布局读取资格和敏感内容边界，不复活旧工具实现或从 opaque 外观猜格式。

交互 Deferred 请求是结构化信封：沿原独立资格按窗口累计最多 1 MiB 后解码，超预算明确失败，不截断或显示原始 JSON。跨窗验证 ref/generation/总长/sealed，按字节累计后 UTF-8 解码。展示/复制仅用 canonical 解码及敏感过滤结果，无原始信封复制/下载旁路。旧 Plan 引用读原版本或 stale，不静默换最新文档。

引用换代只退役受影响详情；折叠、换窗或离开撤销本视图资格并汇合读取，不关闭其他观察或执行。搜索区分借入 cursor 与新建未交付资格，失败回收后者，完整结果成功后才退休旧资格，不驱逐其他 scope 或突破原上限。清理失败保留待 join 义务，不掩盖业务错误。

原 Main/Run/Children 完成查询、read_completed 与内容工具继续服务原子用途，Run 列不删除、不反写；GUI 不再用它们分组，也不提供失败后回落旧 Run 的旁路。原件读取的预算、parent 资格和精确完成身份仍有效。

正文窗口已包含完整正文时不显示范围导航，超出窗口明确显示当前范围及下一段操作，不自动累计无限全文。正文不增加键名或字节数折叠栏；原始 ItemPayload/诊断查看器仍按原始内容展示，不将 JSON 信封当 Markdown。缺少公开 Body 声明不阻止已合法解码信封中的附件沿原附件路径呈现，正文读取也不自动公开原始请求。

已声明公开 Body 的 Input 在 canonical metadata 恢复之前即可沿原内容窗口呈现；metadata 读取只补足附件等已公开元数据，不是正文准入条件。恢复等待、64 KiB 预算限制、解码失败或身份错误均不得遮蔽这份独立且合法的正文；metadata 的限制或错误单独明确呈现，不回显原信封。恢复成功后仍只有一份正文组件和原正文读取 owner，沿同一 item/ref/generation 保持读取资格，不重复显示或再读同一窗口；附件按原成功身份核对后才取得读取资格。没有公开声明的 Input 仍沿原 canonical 限制，不能把其他域当正文绕过。读取资格判定在原呈现模型内复用，不在包装器与 Widget 各复制一套放宽规则。

## 26.8 Flutter 状态栏与唯一组件集合

Main 每个 DisplayBlock 对应一个 Message.custom，metadata 唯一持已加载块。Set 一次 setMessages，Prepend 批量前插完整旧块，Append 批量追加冻结块；没有历史尾组 merge/update 或“隐藏最后组”。纯 live/token 帧不枚举 Main。布局补载沿块页继续，无总页数上限，ACK 不等布局或用户展开。

发送临时回显继续归原 Composer 提交 owner：同步冻结 inputId、正文和附件后立即交出当前草稿，区分发送中、已接纳等待同步、明确发送失败及发送结果待确认，精简呈现遵循 [19.11](19-studio-ui.md#1911-运行中发送消息与剪贴板粘贴)。明确失败保留内容及原因，并提供仅针对该失败项的重试与移除；未知结果不暴露普通重试，防止重复发送。内容与附件所有权按 [25.8](25-frontend-state.md#258-输入草稿与附件所有权账本) 结算，展示不能复制另一套提交状态。临时回显不是 canonical 输入或工作成员；原输入接纳后按 inputId 结算，不按正文去重、不因封组重复插入、不扫描历史或新增持久消息仓储。回显与正式正文共用现有 Markdown 展示能力。

唯一当前尾组由 current_work_id 定位，不限前台或当前 Turn。Active 时进入实时状态栏；无真实活动为 Resting 静态尾卡；冷源确有未收束/不可用成员为 Unrestored；有可见边界为 Sealed。它们是原 State、sealed 和内容资格的派生呈现，不增加可写业务 owner。Resting 仍位于 ready_frontier 之后的可变尾部，不插入历史 controller 后撤回。当前尾卡只挂一处，同 ID 动静切换保留展开意图与原读取 owner，不因样式关闭共享资源。Plan/问答 dock 仅遮蔽，不删除尾组或重建审批资格。

### 折叠呈现与文案

- 真实实时正文或压缩记录已经承担当前前台轮次的展示时，不再叠加同类普通活动提示。接管仅适用于执行在场、开放块内的当前活跃记录，记录与提示须同属当前前台轮次且类型匹配；压缩状态只保留原记录的一行图标、标题与可靠计时。缺少对应记录、冻结观察、终态、跨轮次或冷读记录均不能接管提示；带错误的提示以及停止、审批、存储故障等关键提示仍独立保留，不按文案去重。
- 实时 Work 初次呈现默认折叠；每个折叠组只有一行：左侧 `32×32` 定宽槽承载语义图标或真实活动指示，中间为 `15px` 单行有界思考摘要（支持单行 Markdown，无链接或媒体手势）或当前状态短文案，右侧对齐 `12.5px` 组开始至当前时刻的经过时间及展开入口。不再为同一组叠加一行普通“思考中”提示和一行“工作记录 · N 项”，也不默认展示成员列表、计数明细或终端输出。摘要单行省略，完整语义仍可通过无障碍说明或提示访问。
- 准备、思考及压缩使用同一固定顶行几何呈现对应轻量状态；压缩不伪造工作组。已有同源当前正文 renderer 时不再叠加普通“正在输出”。上一正文可靠结束后，权威 owner 清除该正文活动资格及旧摘要，不从有界窗口缺正文推断无活动，也不从已有 response parts 推断仍在输出。
- 普通活动提示归属于 current_work_id 指向的开放 Work，活动内容来自原 State，不要求来源/Turn 相同。普通提示不能覆盖真实保存、停止、审批、错误和冷源提示；缺真实活动不播放动画。有可靠组摘要时可复用原单行摘要/展开组件，旧失败、取消与 Transferred 不替换真实活动阶段。来源字段与成员计数不推导执行状态；无 activeTurnId 的纯后台活动仍正常呈现。
- 已封存待发布段及已冻结历史 Work 位于 Timeline 工作区且默认折叠，主标题保持纯文本“工作了 2 分 5 秒”等同口径完成态文案，不展示思考摘要，也不以“工作记录 · N 项”、裸小数秒或原始进度数替代。组内调用失败同样不改变标题颜色与图标，真实结果、取消和交接均保留在具体成员详情与其可访问说明；正常停止保持中性，不伪装错误或成功。
- 点击才展开原成员窗口；按稳定 block_id 保存的用户展开意图跨 live→history 交接保持，不能因“默认折叠”强制收起用户已打开的组。实时展开区沿原有界阅读区滚动；历史展开内容跟随主时间线，不另设固定 186 像素高的小型纵向滚动容器。
- 窄窗和大字号下优先压缩或省略摘要，保留图标、时长与可操作的展开入口，不靠缩小字号、重复标题换行或裁掉操作掩盖溢出。复用现有主题、字体、图标和交互组件，不另造预览专用外观。

### 组计时口径与所有权

工作组创建时由原 owner 写入 startedAt，真实可见边界封口时写入 finishedAt。正文首个内容开始输出即封存前组，不等正文完成，也不等待组内尚未完成的成员。两者随原 PreparedEffect 和唯一 writer 的快照事务保存；同一组的开始不被后加入成员、切换阶段、展开或重开重置，结束只写一次，晚到终态不能修改已封口时间。

未封口实时右侧显示 now−startedAt，包含空闲、暂停及隔夜间隔；封口后使用 finishedAt−startedAt，标题为“工作了 2 分 5 秒”。这是一段完整经过时间，不表示模型或 CPU 的累计活动时长，动画仍只由真实活动决定。隐藏界面停止周期唤醒，重新显示从原开始计算；时钟不写表、不推 revision、不遍历成员、不操作 Main。

零及不足一秒使用“执行了不到 1 秒／工作了不到 1 秒”；已知时长按分钟、秒本地化格式化，未知或时间证据倒序则省略时长。工具成员自身原有“用时”与推理成员“思考了”文案保留各自含义，不通过全局替换误改。

问答占用只遮蔽实时区域，不清数据或补终态。保存阻塞、停止、审批及真实错误提示仍须可见，不得被普通组概要合并或折叠隐藏；无执行 owner 保持静态活动图标，工作组经过时间仍继续计算。展开、滚动与跟随输出属于局部 UI 状态；成员读取和媒体资格由原 display lease 持有。Work/Single 复用原成员 renderer，不维护 rawAtoms/groups/messages 三份完整内容，不新增状态机依赖或第二消息 store。

### 修改补丁的片段展示

`builtin.apply_patch@1` 展开后仅呈现请求中的修改片段：按文件和片段分隔，以绿色背景及 `+` 标记表示新增、红色背景及 `-` 标记表示删除，中性背景表示补丁已有的上下文。保留缩进、空行、代码选择与长行横向滚动，适配明暗主题；不读取完整文件、不计算另一份文件差异，不推断原文件行号。文件移动展示原路径与目标路径；删除声明没有旧内容时只表达删除操作，不补造被删内容。

此展示只消费当前契约的 freeform 补丁正文或 JSON `input` 信封内的同一正文，不显示原始参数、信封、补丁控制标记或重复的成功输出。补丁是请求修改的事实，不是落盘结果；真实执行状态和必要失败、拒绝诊断保持可见，失败片段不得表述为已应用。其他工具与未知契约不按名称启用此渲染。

直接正文与已声明正文使用同一片段语义，读取仍由原有展开资格和有界窗口持有，不在界面累计全文或读取工作区文件。截断窗口不得伪装成完整补丁；缺少片段归属或无法完整解析时明确提示不可用，保留既有范围与下一段操作，不猜测归属，也不回退公开原始参数。原始诊断查看器的既有独立入口与权限不因此扩大或改变。

### 语言服务工具的语义展示

`builtin.lsp_query@1`、`builtin.lsp_capabilities@1` 与 `builtin.lsp_status@1` 折叠行按具体语义操作与工具职责呈现单行短动词及紧凑目标（文件名与行号、搜索词或语言标识）；展开区将已内联的查询上下文融合进顶部语义标签栏，不单独展示原始 JSON 请求参数块，也不在已声明内容路径重复读取 `toolArguments` 窗口。未知或未完成契约不按工具名启用此渲染。

直接输出与已声明的 `toolOutput` 有界窗口共用同一结构化语义投影：位置查询按文件分组展示行列定位，悬停说明复用 Markdown 与代码块呈现类型签名和文档，文件符号按层级缩进与 `SymbolKind` 呈现大纲，工作区符号、调用层级与代码诊断按结构化条目展示，能力与状态卡片展示服务阶段、索引进度、相对配置路径及最近错误。有界预览截断必须显式提示省略字节数，非标准输出保底展示可读文本，不在客户端访问工作区或累计无限全文；失败与拒绝诊断保持可见。

## 26.9 热路径成本与验收

纯 token 更新只触及原正文范围与必要有界预览：原历史 SQL=0、display 写入=0、Main controller 操作=0，不访问已完成成员集合。成员终态只更新当前组合格行或创建新行及小头。边界从原内存切面捕获未结束观察和共享 immutable chunks，不查历史、不重读或拼接全部正文；快照成本计入边界 effect，不转嫁每 token。Plan/交互以真实 revision 缓存共享材料，token 不遍历或重序列化。

折叠 10 万成员组只读有界头；主列表不 JOIN/COUNT、不读正文媒体。测量单事件节点、候选/选中行、编码字节、正文驻留、controller 操作和真实 UI 时间，区分 SQL 条数与扫描成本。首内容沿现有参考平台 p95≤500ms 目标回归，实际报告平台、范围与未覆盖项。

验收映射 #364 V01–V30，覆盖唯一跨来源尾组、一次可见边界、始终空与终值撤回、迟到终态、跨批次/suborder、闲置重开、长期耐久清理与幂等、事务回滚、迁移、分页、慢消费、max_items=1 与资源关闭。生产 Rust→FRB→SDK→View 证明与概念稿、参考模型分开；截图来自本次运行，不能代替帧级接纳断言及 SQL/内存证据。

## 26.10 当前快照格式与旧数据边界

当前展示格式沿正式迁移序列使用单一创建位置和独立历史前沿，公共协议为 presentation v6。旧已发布顺序仅在正式迁移中解码并转换，正常 reader 不接纳旧游标或第二位置。组时间只保存开始、结束两个值；成员序号、未完成关联、内容引用与可靠封口位置保留原有读取和生命周期职责。

旧展示快照只在正式存储迁移边界解码升级，保留原块身份、成员与内容引用，并归档旧快照。历史中没有组创建或封口证据时，时间保持未知，界面不显示推算耗时。尚未生成展示快照的旧库按原完成顺序建立引用，不改写原件。迁移失败事务回滚，原件和已有备份保留；升级不是删除或清空用户数据的授权。其他账号、凭据和非展示存储的约定不因本次快照调整而改变。

当前快照的保存、回滚、重放和重开继续由唯一 writer 与原读池持有；坏结构、错误引用或版本冲突明确失败，不修库、不伪造开始或结束时间。
