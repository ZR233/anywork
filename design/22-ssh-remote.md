# 22 - SSH 远程开发

## 22.1 边界

Pure 的 SSH 远程开发是本地 runtime 的宿主能力，不是第二套远端 runtime。Flutter 只调用
typed Studio 功能并展示 canonical snapshot；SSH 服务器管理、连接状态机、helper 安装、
协议、重连和远端工具 backend 位于 pl-tool；pl-studio-runtime 只实现 SQLite、可选系统
凭据库与 helper 随包资产 adapter。SSH 服务器配置不是产品数据，唯一事实源是用户
`~/.ssh/config`（Windows 为 `%USERPROFILE%\.ssh\config`）。

远端 helper 是随 SSH stdio channel 生存的能力代理，只维护 workspace handle 与进程 handle。
一个服务器 endpoint 可以拥有多条按需求创建的物理 SSH/helper 连接；Thread 不对应固定连接，
每次操作由租约选择连接，已开始的操作及进程留在原连接直到收束。
它不包含 Thread/Turn、Tool schema、权限、Git/worktree、Skills、LSP 协议、模型、数据库、
Timeline、重试或会话持久化；不监听端口、不 daemonize，也不支持断线后的进程重附着。SSH
连接每 5 秒通过预留控制流发送有应答的心跳，等待应答期间连续 15 秒无实际字节传输进展即关闭
该物理连接并进入连接恢复；不把仍在前进的传输误判为失联。心跳与终止不竞争普通操作子流。
helper 连续 30 秒没有收到心跳或其他入站数据（包括读取
进度）时封闭新请求并回收全部命令监督器及其后代。EOF、单向 shutdown、写入失败和租约
过期走同一清理路径。正常 GUI 退出只尝试写入关闭帧，不等待远端确认或 SSH 失联；GUI 被退出
期限强杀时不写入关闭帧，远端 helper 由 control EOF 与 30 秒租约兜底回收，因此强制退出也不
依赖远端确认。每个命令监督器先发 SIGTERM，2 秒后升级为 SIGKILL，并等待后代退出；helper
完成清理后退出。

## 22.2 最小协议

SSH stdio 上使用 Yamux 复用独立双向子流，由成熟组件负责分帧、调度、按流背压及基于实际
消费带宽和 RTT 的窗口调优。每连接预先建立独立控制流，普通请求各自拥有操作流；没有全连接
业务响应队列、待响应表或进程输出消费计数。控制流只处理有界的小型控制事务，不等待文件传输
或完整进程退出。单个慢消费者只停止其所属子流，不占用其他子流的接收信用。

每连接保留组件的有限流数、聚合接收窗口和发送分片预算。这些是物理资源及调度边界，不限制
逻辑会话总数、目录项数或文件总长度，也不是把旧常量调大。连接内没有普通子流余量时，由
endpoint 合并扩容需求并建立另一物理连接；真实资源不足在可取消准入点等待或明确失败，不
建立无界载荷队列。未准入取消不发送，已开始操作的租约持有到流与清理责任全部收束。
单物理连接提供非阻塞 reservation 探测与可取消的异步 reservation 等待，两者消费同一真实
流预算。异步等待由预算归还或关闭唤醒，不以自旋或反复 yield 代替资源通知；池在串行扩容
裁决点再次检查现有连接可用性，已经消失的需求不继续发布新的扩展连接。

准入同时受 helper 的实际文件描述符能力约束，不能仅因还有 Yamux 流就接纳文件或进程。
`hello.resources` 必填，公布该物理 helper 的 workspace FD 预算、operation FD 预算及各类
操作峰值成本；预算从 OS soft limit、启动期实际已打开 FD 和明确的维护余量派生，不提高
系统限额，也不转换成业务会话数硬顶。缺失、零值、不能容纳其成本或不能表示的预算明确
拒绝握手。不同物理连接可有不同预算，版本、能力集合和执行环境的一致性要求不变。
协议只定义资源描述及请求的穷尽分类，不负责 semaphore、连接选择或调度。

workspace 预算独立承担根能力的打开峰值与持续持有；operation 预算承担文件、目录及
进程的完整峰值，包括启动中间句柄、capture、阻塞工作、发布及取消后的清理。客户端在
发送前以实际请求类别同时预留流和 FD 能力；冷 workspace 还须同时预留打开责任。不能
取得整份需求时不发送，endpoint 合并扩容，直连客户端可取消等待真实预算归还。helper
对收到的请求独立、非等待地裁决整份预算，不足以 `ResourceExhausted` 结束该操作，不
关闭健康连接，也不由客户端透明重放。该错误不代表已发送操作可安全重试。

预算跟随实际 FD 所有者到最后释放，不能因等待者取消或操作 future 析构提前归还；同一
责任在 blocking、暂存清理和进程 owner 间移交或共享，而非重复计费。正常终结响应发布
前先完成该操作应有的资源收束；取消后的远端清理尚未完成时，helper 的预算仍是权威，
后续请求可能得到操作级资源不足，不能把本地 drop 当作远端回收确认。控制流不申请上述
业务预算，CloseWorkspace 确认移除注册责任后，根能力仍由最后实际使用者持有到结束。
所有公开 OpenWorkspace 入口都由可等待 owner 读取裁决：未被调用者认领的成功结果必须
显式关闭，持久预算保留至关闭确认或连接终态；只记录当前活跃责任，不建立历史恢复表。

递归 copy/remove 使用现有 capability 文件系统组件，并在所属物理 helper 独占 operation
预算，避免深度相关的临时 FD 与其他上传、进程或未完清理相互耗尽。workspace 与控制面
仍独立；其他业务需求由池选择其他连接。此隔离不承诺任意深度具有无限 FD，极端深度
仍可返回真实操作错误；不另造 walker、不增加目录深度业务限制，也不丢弃 parent 能力后
重新解析路径发布。剩余 OS 资源不足与清理失败保持可见，不用扩大 ulimit 掩盖准入缺口。

空闲 endpoint 保留一个基线连接，扩展连接在最后操作、进程及 workspace 释放责任结束后关闭
并等待回收。窗口高水位随流和连接释放回收，不承诺仍存活子流的窗口会主动缩小。
驱动任务由连接 owner 唯一拥有，封闭准入、取消、等待任务及关闭底层 SSH 是同一生命周期；
任务不能通过持有外部 owner 的强引用循环延长自身寿命。
监督任务异常退出或物理回收责任失去确认时，连接 owner 必须主动获知并进入统一收尾，不能
等下一次业务输入或最终宿主退出才观察；普通命令非零退出和文件业务错误仍按操作隔离。

远程进程使用与本地相同的命令租约。受跟踪监督任务拥有启动响应、输入转发、终止和退出；
启动已提交时，取消必须等待启动结果再终止，输入传输错误进入终态并等待回收。内部任务不
拥有连接寿命，外部命令租约与客户端拥有连接。所有连接结束原因统一封闭准入并等待任务、
进程与发送资源回收。文件原语只接受普通文件，实际打开句柄必须拒绝可无限阻塞的特殊文件。

工具 backend 持有逻辑 workspace 身份，每次操作取得所选物理连接上的 workspace 租约；
逻辑 backend 不永久固定一个物理 workspace 句柄，首次 canonical 校验使用的临时租约也在校验
结束后释放；稳定绑定身份来自 endpoint 代次与 canonical 路径。连接间不转移 workspace id 或
process id。每次操作准入必须核对 backend 捕获的代次，跨重连等待也不能把旧绑定放到新
代次执行；只有重新装配的 host 可以使用新代次。工作区由真实使用租约拥有，缓存不得永久保留历史
工作区。最后使用者及其命令释放后通过原连接执行 closeWorkspace，完成后才可收缩该连接。
连接管理器不保留历史路径恢复表；新操作按活跃逻辑工作区取得物理租约，不复活已关闭路径。工具刷新
只消费所属项目与相关连接的变化，扫描进度本身不使其他项目的目录失效。

协议以 Yamux stream identity 区分操作，以 process id 标识实际进程；typed 记录与原始二进制
chunk 仅在所属子流内传输。元数据、正文块和终结记录各自有界，目录全集和文件全集不进入
单条元数据。记录编码、业务校验和文件错误只结束对应操作；连接级协议损坏、EOF 或物理 I/O
失败才关闭该物理连接。序列化必须在发布该记录前完成，不能因尚未写出的本地编码错误杀死
共享驱动。流内半条记录不得继续复用该子流，但不损坏其他子流。
记录适配器在已开始 I/O 的读写被取消或失败后保持失效状态，后续调用明确失败；调用方仍须
丢弃所属操作流。尚未发布任何字节的本地编码或长度拒绝不污染记录状态。
每条记录包含一份 typed 元数据和一份原始正文，空正文也有独立帧边界；使用成熟长度分帧组件，
元数据和单块正文各最多 64 KiB，正文生产块为 16 KiB。限制作用于单条记录而非操作总量；
物理连接保留 512 个子流及组件聚合窗口预算，其中一个专供控制，其余需求由 endpoint 扩容。
控制事务一旦开始发布就由独立 owner 执行到响应或连接终态，调用方取消不能遗弃半条事务。
控制流的首次建立若在接管前取消，必须可靠终止该连接而非留下不可恢复的健康假象；重复建立
属于独立的本地状态错误，不伪装成连接已断开。所有已由组件接纳的入站流必须保留到消费或
显式取消，不能因额外交接队列满而丢弃最旧流。关闭一开始即封闭准入，并在通知资源已关闭前
释放未接管流；等待关闭必须等待真实驱动任务退出，包括尚未首次执行就取消的任务。
endpoint 封闭与物理连接安装采用同一个准入裁决；关闭还必须等待在途扩容及被拒绝连接的
真实清理，清理失败保留 owner。控制响应按请求类型验证，不能把任意成功 envelope 当作
workspace 已释放或进程终止请求已接收的确认。
同一准入裁决也覆盖现有连接的真实 reservation 与退休转换，关闭或退休后不能再接纳操作。
连接异常终止的诊断结果与资源是否已回收分别保留：清理成功不能把异常改报正常；资源已确认
回收也无需为保留失败诊断而永久保有物理连接。关闭等待超时只说明该次等待尚未完成，不能
将它缓存为不可重试的最终结果。连接创建与观察任务在健康运行期即由 owner 实际 join 并释放，
关闭则等待封闭前后仍归属本 endpoint 的所有在途责任，不保留随历史连接波次增长的任务集合。
一次 endpoint 关闭等待采用 30 秒总期限，并并发推进各物理连接的清理；期限结束只报告仍在
处理的责任，不销毁真实关闭任务。后续调用继续观察相同 owner，不能把等待超时当成释放确认。
握手期 transport 与心跳任务也属于连接 owner 的清理范围，最后一个外部 endpoint 句柄消失
不会把已创建的 SSH、驱动或 stderr 任务降格为仅剩错误文本。
公开连接入口的握手等待被取消时，同样由独立于等待者的清理责任完成真实驱动 join；仅请求
关闭不等于确认完成。重连监视器在等待退避、建连或旧端点回收时也必须响应 manager 关闭，
不能先等待监视器结束，再发出它所等待的端点取消信号。取消监视器只结束其等待，不丢弃
端点的真实清理 owner；统一端点关闭继续完成回收，不通过延长退出期限解决等待顺序问题。
监视器停止等待后，连接尝试的非预期失败仍由其监督 owner 记录有界诊断；明确的关闭取消
不升级为连接故障，也不通过保留无界的历史错误集合来实现诊断。
endpoint 消失必须通知其观察任务结束，并保留尚未回收的实际资源直到
终态，不以固定尝试次数耗尽作为释放条件。关闭总期限包含准入封闭的等待；任一等待被取消
都不能使资源脱离可继续观察的所有权槽。有界 stderr 尾部与首次失败一同跨清理重试保留。
stderr 尾部本身只是诊断，非空不代表关闭失败；实际 I/O、owner task 异常和清理超时才决定
失败。客户端将本地 I/O 与 task 异常分别暴露为 `RemoteClientError::Io`、`Task`，保留可共享
的原始 source；补充清理阶段与有界诊断使用 `Context` 保留首个类型化原因，不能扁平化为
协议错误字符串。Studio 对 I/O 映射为不可用、task 异常映射为内部失败，Context 沿 source
分类；现有认证、远端应用、协议与取消分类保持不变，不改变 wire DTO。
客户端已完整发布单向 shutdown 后，对端正常结束是预期的传输终态，但不能掩盖真实 I/O、
协议或任务错误；此判断不代替物理 owner 对 SSH/helper 退出状态的核验。无论 driver 是否先
结束，显式 close 都须通知并 join 客户端自身的控制与连接 owner，不能只等待已结束的 driver。
握手严格协商协议版本、helper build、远端 OS/架构、实际 shell descriptor 和 capability；
未知版本或未知穷尽变体必须失败，不能降级猜测。
客户端要求 helper 构建版本与自身 package 版本一致，并具有目录浏览、workspace 文件和可观察
命令三项能力；池内连接的构建版本与 capability 集合也必须一致，集合顺序不参与身份比较。

`hello` 返回结构化 shell descriptor（dialect 与已验证的可执行路径）。Linux helper 启动时
优先验证 `/bin/bash`，缺失时验证 `/bin/sh`；descriptor 只描述实际命令解释器，与用户环境
加载 shell 分开。每次 SSH 连接先按用户账户信息、有效 `$SHELL`、`/bin/sh` 的顺序选择环境
加载 shell，未知解释器明确失败。Bash 以交互非登录模式读取 `.bashrc`，Zsh/Fish 使用交互
登录模式，sh 使用登录模式读取 profile。配置仅由对应解释器执行，不跨 shell source，不
要求 PTY；只继承 exported 环境，不继承 alias、函数或依赖真实终端的状态。采集受物理进程
监督器管理，stdin 为 `/dev/null`，启动输出与 SSH 协议隔离；15 秒超时、提前退出或无效
快照导致连接失败并回收进程树，诊断不包含环境值。

完整环境快照仅在远端连接内存中存在，通过私有 Unix socket 采集，helper 在该环境下启动
服务，不依赖远端 Python 或 `env -0`。普通命令、Git 和 LSP 统一继承此环境（包括 unset），
请求显式 env 最后覆盖；普通进程不重复执行继承的启动钩子，显式请求可覆盖；PATH 完全
尊重远端配置，不额外补入固定目录；同一连接不重复加载配置，重连重新采集。本地 process
worker 的环境策略不受影响。

客户端与 helper 必须同步更新协议，不保留旧帧协议兼容路径。控制面提供 `hello`、有应答的
`heartbeat`、`terminate`、`closeWorkspace` 和单向 `shutdown`；普通操作提供 GUI 专用的
`browseDirectories`、`openWorkspace` 和文件/进程能力。文件面只提供远端事实所必需的 `stat`、`readFile`、`writeFile`、
`listDirectory`、`createDirectory`、`removePath`、`renamePath` 与 `copyPath`；文本解码、
glob、patch/diff、工具 JSON、图片识别和 Skill 解析留在本地 core。helper 必须用远端文件
系统事实完成 canonicalize、链接分类与 workspace 越界拒绝。`spawn` 的独占双向流在启动裁决后
接收 stdin 数据与关闭输入意图，并发布 `processOutput` 与 `processExit`；`terminate` 经预留
控制流请求，不等待输出消费者。输出事件携带 process id、该进程单调 sequence、stdout/stderr
分类与原始 bytes；helper 同时把
完整输出写到 core 指定的 workspace capture path。core 继续拥有超时、模型输出截断、tool
record、Timeline、artifact 与最终 JSON。不提供 PTY、终端面板、端口转发、调试器或后台
任务恢复。

目录响应由目录元数据、逐条 entry 和明确终结组成。helper 增量枚举，不先收集、排序整目录；
消费者可以提前停止。明确需要完整列表的 GUI 等聚合 API 在消费端收集、排序，其结果内存随
条目数增长，不能据传输流化宣称 UI 聚合本身定长。工具和 Skills/LSP 遍历增量消费，不建立
第二份目录缓存或快照事实源。
同理，返回完整字符串的既有文本 backend 是消费端的显式聚合，不能新增一个 64 KiB 文本
上限冒充传输修复，也不能将其内存代价计作分片传输的定长缓冲。流式文件 reader/writer 才是
超大文件传输入口；现有调用方明确给出的读取预算仍按原语义执行。

文件读取从同一打开的普通文件句柄产生流，开头声明实际总长度、起始偏移及本次传输长度，
正文按偏移分块，成功终结确认完成字节；截短、长度变化与错误终结不得冒充 EOF 成功。
上传从调用方 reader 增量读取，文件总长度及偏移使用 u64，不要求整文件驻留内存。
create/overwrite 的暂存文件位于目标目录内的请求独占暂存区、与目标保持同一文件系统，在完整长度及显式结束校验、同步
完成后原子发布；提交前失败或取消不发布半文件，也不覆盖相邻请求的暂存。提交与取消竞争由
唯一 owner 裁决，提交结果未知不自动重试。append 保留追加的真实副作用，失败不能假装回滚。
所有模式仍拒绝链接、特殊文件和 workspace 越界。
文件操作以实际打开的 workspace root/目标 parent 目录能力为授权边界，采用成熟的 capability
文件系统组件完成相对打开、创建、重命名、链接及删除；不能先检查字符串路径，再在网络传输
结束后按可能已被替换的父路径发布。暂存区、最终目标和清理均绑定同一 parent 目录句柄；
create 以拒绝已存在目标的原子发布保护相邻写者，overwrite 原子替换。持有的目录/文件能力
指向已经获准的实际对象，显示用 canonical 路径不重新成为提交授权。该约束不扩大 shell/Git
的权限沙箱承诺。阻塞文件系统工作必须由可等待的 owner 持有，提交开始后连接关闭也等待其
完成裁决，不得丢弃 blocking 任务句柄后声称已取消或回收。
同样的等待责任覆盖目录与文件原语的阻塞阶段、上传准备与同步、以及取消后的暂存清理；
调用方取消不取消已经开始的系统调用，连接 owner 必须观察真实结束与清理错误。已结束任务
只有被 owner 实际 join 并保留必要失败后才退出登记，不能通过任务自行删除唯一等待句柄来
声明完成。递归文件操作只持有遍历深度所需的目录能力，不按整层扇出预先打开全部目录。
健康连接中的失败上传在暂存清理完成前仍承担该操作的资源责任，不能先释放操作流、再把
清理无限追加到后台队列；连接整体取消时由已登记 owner 收束迟到析构并等待最终清理。
workspace 的 canonical 描述必须与打开的 root 身份一致；命令启动保留已验证 cwd 的目录能力，
不得丢弃后再将可能已被替换的显示路径当作启动定位。此约束保证启动目录一致，不提供 shell
文件系统沙箱，也不改变本地 process-worker 协议。
目录由 `directory` 元数据、`directoryEntry` 记录和 `complete` 终结组成；读取由 `file`
元数据、携带绝对偏移的 `data` 和 `transferred` 终结组成。上传在 `ready` 后接收从零连续
偏移的 `data`，必须收到与声明长度一致的 `uploadFinished` 才能提交，再以 `transferred`
确认。进程流在 `processSpawned` 后全双工承载 `stdin`/`stdinClosed` 与
`processOutput`/`processExit`。错误可以终结操作，裸 EOF 不能代替业务成功终结。
命令 capture 使用 [17](./17-studio-storage.md) 的远端执行侧会话目录，不能写到本地 home
或从 `processId` 推测路径。下载以原 workspace 租约有界读取，在宿主对应会话 `scratch/`
暂存后归档至可靠资源；完整归档前保留远端源，下载失败不冒充本地可靠存储故障。
临时文件由本次传输独占持有，成功、失败、取消和连接关闭均收束其责任，不改变共享连接
其他进程的生命周期；可靠历史读取不重新连接 SSH。

`processId` 是 opaque token，不允许调用方解析其局部序号。core 进程内所有命令进程管理器
共用一个原子单调分配序列，因此 manager 重建或多个 Agent 共享同一 helper 连接时也不会
复用 id；调用方不得重新发送已使用的 id 或重放 spawn。helper 在任何异步进程
准备前把 id 原子登记为 Starting reservation，成功后转换为 live handle，所有失败路径都
释放 reservation；并发同 id 请求不得通过检查后相互覆盖。登记容量只计算仍在准备、执行或
回收的进程，资源任务结束后立即释放条目，不为已结束进程保留登记或不断增长的墓碑。
关闭连接仍回收全部 live 进程组。

每个进程的实时输出由自身数据流和 Yamux 背压控制，不维护另一套固定帧计数或进程数硬顶。
客户端独立排空，接收端关闭后丢弃该端的迟到输出；显式取消停止等待业务消费者并继续完成
capture 排空和回收。断线只关闭所属物理连接的输出任务并等待回收；超时终止请求与输出排空
并行，不先等待终止回复再读取输出。

协议 DTO 归 pl-protocol，共用传输适配归 pl-remote-helper，单连接 typed client 与逻辑 endpoint
租约/弹性池归 pl-tool。server 只消费相同的记录契约，不依赖 pl-tool；Studio 不参与窗口、
子流或连接选择。共享类型、错误分类、取消及关闭契约先确定，组件实现只能在该边界内替换。

## 22.3 本地工具与 SSH 管理

pl-tool 的 SSH 管理器负责服务器校验、系统 OpenSSH、架构探测、随包 helper
bootstrap、握手 shell descriptor、endpoint 弹性连接池、连接状态与自动重连，并返回带执行环境的远端 workspace
host；host 实现或组合现有文件、命令、Git、worktree、Skill 与 LSP backend，再经统一安装
入口注册现有工具。模型不得看到 `remote_read`、`remote_exec` 等环境专用名字。

SSH 服务器列表读取解析 `~/.ssh/config`，保存与删除以带标记的 anywork 管理块原子写回该
文件，未触及内容逐字节保留（含行尾风格）。管理块使用
`# BEGIN anywork server: <alias>` / `# END anywork server: <alias>` 包裹
Host/HostName/Port/User/IdentityFile；Host 别名即服务器身份，创建后不可改名，别名必须是
非空单 token 且不含通配或否定字符。解析遵循 ssh 的首次匹配语义（每个关键字取块内首次
出现值，HostName 缺省回退别名），含通配、多模式或 Include 的条目不进入可选列表；用户
手写条目只读展示，编辑与删除仅对管理块开放。新建别名与文件中既有 Host 冲突时分配不冲突
后缀；同别名管理块与待写内容一致时视为同一事实，重试安全。内部 ssh 调用只传 Host 别名，
端口、用户、私钥与代理全部由 ssh config 解析，运行时不维护第二份连接参数。

文件、Git/worktree、Skills、workspace instructions、图片与 LSP 的环境无关逻辑留在本地。
工具读取的远端图片由本地媒体宿主归档；Timeline 的文字入口与行内展开只读取该 Thread
持久化引用的归档资源，不在展开时重新连接 SSH 或读取原始远端文件；源文件变更、删除或
SSH 断线不改变已归档图片，未知或未被该 Thread 引用的资源必须拒绝。`apply_patch` 在本地
匹配并通过远端原子写提交；Git/worktree 在本地编排命令；LSP client 留在本地，language
server 作为远端可观察进程运行。workspace instructions 由远端 file backend 读取后以已加载
文档集合交给指令组装器，保留远端来源路径；远程路径不得再次交给本地文件系统做目录或
文件检查。

SSH 项目与本地项目一样提供会话工作区模式：`local` 使用远端 canonical Project 目录，
`worktree` 在远端仓库按创建时解析的 `HEAD` 创建
`<repo>/.anywork/worktrees/<root-thread-id>/session`，lease 记录 `ssh_alias`，激活时按
identity 匹配的 `active` lease 把该远端路径绑定为会话工作区根。远端 workspace handle 根即
会话工作区根，工具层接受会话工作区根与 canonical Project 目录分离，并按 workspace-relative
POSIX 路径执行同一内置目录写策略。远端 worktree backend 以解析出的仓库根为基准，Project
目录是仓库子目录时同样成立。远端 worktree 的恢复、preview 与显式清理走同一 lease 状态机，
连接可用时经远端 backend；SSH 离线时按既有语义保留现场并给出诊断，不推断 ownership。启动期
「未注册 worktree」审计只覆盖本地文件系统与本地 git，不为远端项目打开 SSH 连接；远端资源由
durable lease 覆盖。

远端会话与本地一样只持有一个工作区地址：`local` 是远端 canonical Project 目录，`worktree`
是远端 `<repo>/.anywork/worktrees/<root-thread-id>/session`，跨端一律 POSIX 形式。归档沿同一
lease 状态机清理会话树工作树；SSH 离线时删除无法执行，按既有语义保留现场并给出诊断，连接
恢复后按同一前置条件重试。

远端路径在任何跨端边界上都是 POSIX 字符串：远端 lease 的 `repository_root` 与 `path`、会话
工作区根、workspace 打开参数与身份比较，以及传给远端 git/helper 的路径参数都以 POSIX 形式
表示。客户端宿主形态（包括 Windows 的路径分隔符与驱动器前缀）只在本地文件系统上使用，不得
跨端出现；跨端前统一归一化，并保证同一个远端路径在目录写操作与 git 路径参数上使用同一结果，
避免物理 worktree 落在与 lease 记录不一致的位置。该绝对路径规范化由
`pl-tool::remote::normalize_remote_absolute_path` 单点负责：反斜杠转换为 `/`，重复分隔符和
`.` 被折叠，空值、相对路径及 `..` 被拒绝；Studio 不复制该逻辑。

本地与远端 prompt 使用同一份执行环境：Platform developer 段声明 transport、目标 OS、
shell dialect 和路径，并按该 dialect 生成命令语法。shell descriptor 只缓存在当前连接和
workspace host；断线自动重连完成新的 hello 后替换旧 descriptor；环境变化会改变动态
developer 内容及其 prompt cache generation。

SSH 连接、平台探测、helper 上传和协议握手都通过统一后台进程工厂启动系统 OpenSSH：Windows
不弹出额外命令行窗口，并用关闭即终止进程树的 Job Object；Linux 使用独立进程组和父进程
死亡信号。正常关闭停止心跳、尝试写入单向 shutdown，再关闭本地 transport 并有界回收
本地 SSH 进程；关闭帧未送达时由远端心跳租约兜底。关闭编排把 SSH transport 的真实关闭排在对它
有依赖的远端 MCP / LSP / 工具停止请求与结果处理（以及驱动远端工具的生产者停止 ACK）**之后**：
管理器封闭连接准入后只跟踪 manager 交互 / 连接 / 浏览 / open_workspace 类 token，远端命令 /
backend / worker 仍持有逻辑 endpoint 及在途物理操作租约，因此 transport 关闭不能与依赖抢跑，否则会先切断通信、把
健康远端资源的正常退出误判为失败；SSH 回收仍与写入链等无关资源并发，不等持久化 / 数据库提交，
依赖停止超时或失败时有界降级并仍请求回收。SSH 通道只承载标准输入
输出协议，因此固定关闭伪终端与 X11 转发，不打开交互式终端或图形会话；未配置或未提供密码时
SSH 以 BatchMode 运行快速探测免密密钥与 ssh-agent，存在可用密码时通过受控本地 `SSH_ASKPASS`
非终端注入密码（单次提示，不在终端阻塞等待输入）。

上述非交互与进程回收约定只适用于 Studio 管理的 helper transport。会话顶栏的外部「终端」
入口是用户主动启动的独立交互 SSH 会话，复用同一 Host 别名与用户 SSH 安全设置，进入会话
canonical 工作区目录，不承载 helper 协议，也不随 Studio 退出终止。平台选择、路径引用与
错误反馈契约见 [18.9](./18-studio-state.md#189-顶栏工作区打开菜单)。

连接状态穷尽为 disconnected、connecting、ready、reconnecting 与 failed。SSH 建连超时为 15 秒，存活探测每 15 秒一次、连续三次无响应后断开；平台与资产
探测最多等待 30 秒，资产上传最多等待 120 秒，helper 握手最多等待 25 秒，目录重开最多
等待 15 秒。超时关闭并回收所属 SSH 进程；本地进程回收失败保留责任，远端失联不阻止
GUI 退出。传输保存首次失败阶段与有界诊断；日志关联 endpoint/connection generation、stream
identity、操作、阶段、计量和 SSH/helper 退出事实，不输出正文、目录全集或凭据。stdout EOF
不停止 stderr 排空，连接 owner 在有界收尾期限内读取至 EOF 并等待排空任务和进程回收，避免
遗漏末尾崩溃原因。单个本地输出接收端关闭只丢弃该端的迟到输出，不使同一连接上的其他进程和
文件操作断线；真实协议错误仍关闭连接。断线使当前远端工具立即以稳定
`remoteDisconnected` 失败，不透明重放写入、stdin 或 spawn；其他健康物理连接继续服务。
endpoint 没有健康连接时以 1、2、4、8、15、30 秒退避重连，新操作只在准入前选择健康连接。
新连接重新取得 shell descriptor，池内 OS/架构/shell descriptor 必须一致，不一致明确拒绝。
仍然活跃的逻辑工作区按需重新打开物理 workspace；endpoint 恢复成功通知原有 root/child
会话刷新工具绑定，无需新建会话。逻辑绑定依据 endpoint 代次与 canonical 工作区身份判断，
物理 lease 依据所属连接判断，不以服务器名称或可重复的 workspace id 代替身份。原工作目录重新打开
失败时报告失败，禁止继续使用旧连接或切换到其他目录；下一次 Turn 重新读取远端 Skills，
并在 host identity 变化后重新探测 LSP。

SSH workspace 的 Skill catalog 由一个共享 registry 组合构成：远端 provider 贡献
Project 源，默认项目目录为远端 workspace 下的 `.agents/skills`；本地配置用户目录、用户
主目录 `.agents/skills`、Studio 物化的系统技能目录和显式 external 目录以只读来源并行
注册，顺序与本地 workspace 一致（目录合同见 [10](./10-skills.md)）。Thread Mode 独立
从本地内存注册表捕获，不进入远端或本地 Skill 发现。Turn 执行与 Settings 的显式技能
发现共用同一组合，因此设置页技能目录展示远端 Project 技能与本地系统/用户/external
技能，且激活 fingerprint 包含 Skills 配置指纹；配置变化后的下一次激活会重新发现。

## 22.4 凭据、路径与持久化

Pure 调用 PATH 中的系统 OpenSSH，复用 ssh config、known_hosts、ProxyJump、ssh-agent 和
用户显式配置的 agent forwarding。认证支持 ssh-agent、密钥以及可选 SSH 密码：密码与供应商
API Key 采用同一套系统凭据库（`CredentialStore`，账号键 `ssh:<alias>`，编辑语义为
`Preserve` / `Replace` / `Clear`）或当前进程内存会话租约，绝不写入 `~/.ssh/config`、
SQLite、DTO、日志、helper 参数、helper 环境或远端协议；删除受管主机时同步清除对应系统凭据。
本地 OpenSSH 子进程仅在存在可用密码时通过受控临时 `SSH_ASKPASS` 脚本（`SSH_ASKPASS_REQUIRE=force`）
读取本地子进程专属环境变量完成非交互密码认证。认证顺序固定为免密优先：每次连接都先用
`BatchMode` 非交互探测 ssh-agent 与密钥（包含默认身份文件、`IdentityFile`、ProxyJump 与用户
ssh 配置），探测成功即继续连接，不请求也不提示密码；只有探测以认证失败结束、且诊断表明服务器
接受密码类方式时，才由 GUI 弹出密码输入弹窗（支持单次会话认证或同时保存到凭据库）。GUI 不得
依据「未保存密码」或「管理块未写 IdentityFile」主动索要密码，该判据的唯一事实源是服务器公布的
认证方式。

OpenSSH 在失败诊断 `Permission denied (<methods>)` 中公布服务器接受的认证方式，因此认证失败错误
本身携带该事实：`password` 或 `keyboard-interactive` 出现在列表中表示还能用密码继续；只公布
`publickey` 等非密码方式时 GUI 不再提示密码，改为报告需要配置密钥或 ssh-agent 的可操作错误；
诊断缺少方法列表、或方法列表为空时按需要密码处理，保持旧行为。该事实通过 StudioError details 的
`sshErrorKind: "authenticationFailed"` 与仅在能判定时出现的 `sshPasswordOffered`（bool）暴露给
前端；GUI 与 SDK 只消费这两个字段，不解析 OpenSSH stderr 文本。
首次主机身份核验沿用用户 ssh 的 known_hosts 语义，不自动信任新主机或已变更的主机密钥。
provider token 不得转发；远端 Git 只使用服务器原生配置与凭据。shell descriptor 不是
login shell 配置，也不携带完整环境变量。

远端文件 backend 与 `exec.cwd` 始终 confined，`full-access` 不放宽该 backend（见
[04](./04-security.md)）。冻结为 directory Profile 的 `writablePaths` 也独立于权限模式：
core 在所有远端内置 mutation 路径上先按 workspace-relative POSIX 路径执行同一策略，包括
`write_file`、创建、删除、复制目标、移动源/目标以及 `apply_patch` 的写入和删除；读取
不受该列表限制。helper 继续负责 canonical workspace 与 symlink 越界防护；目录策略仍只是
Pure 内置工具边界，不能宣称为 shell/Git/MCP 的 OS 沙箱。SSH `exec.cwd` 只接受
workspace-relative POSIX 路径，根目录使用 `.`，不得传远端 canonical root；绝对路径与
`..` 分别返回可操作且不同的稳定错误，runtime 不把绝对路径猜成 `.` 或静默截断前缀。该
约束仍是 Pure 策略而非 OS shell 沙箱，命令正文拥有 SSH 用户本身的系统权限。GUI 目录
浏览是独立宿主功能，不注册为模型工具。

Studio 的"打开远程项目"窗口绑定 `~/.ssh/config` 中的一个 Host 别名，并同时提供目录浏览与
路径输入；输入只接受该服务器上的绝对 POSIX 目录路径，不解析 `~`、相对路径、`ssh://` URI
或 `user@host:path`，也不隐式创建服务器配置。初次进入浏览远端默认目录，之后的向上导航、
子目录导航和手工路径都先通过 Studio 的 `browseRemoteDirectories` 取得 canonical listing；
只有与当前输入一致、已经验证的 canonical path 才能提交给 `openRemoteProject`，再由远端
协议的 `openWorkspace` 打开。后端 product snapshot 只拥有 canonical Project 目录，不拥有
Flutter 当前选择；Studio controller 只有在重新读取的目录中找到与打开结果同 id、同 SSH
别名、同 canonical path 的 Project，并由显式 selection intent 采用它之后才报告成功；
拒绝新工作或 canonical Project 身份未被采用都不是成功，窗口不得因此关闭。浏览与打开
操作必须串行化：pending 期间所有调用入口都拒绝重复或冲突请求，不能只依赖下一帧的按钮
禁用状态；打开期间窗口不可通过取消、遮罩或系统返回动作关闭；浏览或打开失败必须保留
窗口与用户输入，让用户在原上下文中修正并重试。目录没有子目录时显示明确空态，但仍
允许打开已验证的当前目录。窗口在窄视口与放大文本下仍须保持路径输入和主要操作可达；
图标导航必须提供可本地化的可访问名称。

Studio schema 不保存 SSH 服务器表；远端项目以可空 `projects.ssh_alias` 引用
`~/.ssh/config` 的 Host 别名：本地项目按 `path` 唯一，远端项目按 `(ssh_alias, path)`
唯一，远端 path 保存 canonical POSIX path。数据库版本演进遵循统一迁移契约（见
[17](./17-studio-storage.md)）：v20 及更早的 `ssh_servers` 行在升级为 v21 时由启动
协调器先备份产品库，再把每行迁移为 `~/.ssh/config` 管理块（别名取原 name，冲突时分配
后缀；密码认证行不携带 IdentityFile，迁移后需用户自行补充密钥或 agent），同一事务内把
`projects.ssh_server_id` 重写为最终别名并删除旧表；文件写入与别名分配幂等，中断后可安全
重试。Session、Turn、Item、Interaction、working state 与 tool record 的 wire 语义不因
远程 host 改变。远端项目启动时不做本地 canonicalize，服务器离线是连接状态，不是项目损坏。

## 22.5 helper 资产与随包分发

helper 构建为 stripped 静态 musl 资产（aarch64 与 x86_64 两种 Linux 架构），由 xtask
独立准备并以 zstd 压缩资源随 Flutter 桌面 bundle 分发，不嵌入 Rust bridge。Windows/Linux
CMake 将资源安装到应用可执行文件旁的 `data/remote-helper/<target>/`，每个目标包含
`pl-remote-helper.zst` 与 `pl-remote-helper.metadata.json`；元数据使用 camelCase，记录
`target`、`workerProtocolVersion` 与原始可执行文件的 `sha256`。资源不经过 Dart rootBundle
或 FRB 字节传输。原生 GUI 预备并验证两种资产，纯 Dart demo 不加载 bridge，也不需要资产。

桌面 bridge 根据应用可执行文件位置解析资源根，通过明确的运行时启动选项提供随包 helper
来源；runtime 为 SSH 与 Linux 本地 worker 统一持有该来源，不能使用进程全局可变配置。
非打包 Server、开发与观察入口显式使用外部 helper 模式，Linux 本地 worker 从 PATH 查找；
随包模式下缺失、解压失败、目标或协议不匹配、内容摘要不符必须报告资源路径和失败原因，
不得回退到 PATH、开发目录或网络下载。普通运行不依赖 xtask 的构建环境变量。
helper 的随包解析不阻断与其无关的启动：资源缺失或损坏时，没有任何本地 stdio MCP server 的
宿主仍可启动，只有真正需要本地 worker（Linux 本地 stdio MCP 或远端 helper）时才以带资源路径
与失败原因的错误失败。这既不放宽“必须报告资源路径和失败原因”，也不引入裸 shell/PATH 后备。

helper 资源与 bridge 是独立构建产物，在 Flutter 打包阶段汇合；资源路径与内容不作为 Rust
编译输入，内容未变的 staging 不改写文件。仅 helper 资源更新不应重编译 runtime 或重链接
bridge；共享 Rust 源码、依赖与协议变化仍正常触发 Cargo 重建。
helper target 由 `uname -s/-m` 穷尽映射，未知平台明确失败。core 先探测架构，再请求宿主
adapter 解压唯一匹配的 helper bytes，并按内容摘要上传到版本化远端目录；同一摘要已有
可执行文件时直接复用，不重复传输；未匹配架构保持压缩状态，也不产生本地解压文件；远端
不需要网络或 Rust 工具链。交叉编译入口由仓库构建工具统一提供；使用 Zig 时由它编译目标
平台的 C 依赖，Rust 最终链接使用当前工具链随附的 `rust-lld`，不覆盖用户显式指定的
目标链接器，也不调整 Rust 编译优化等级。正式发布流程可在 Linux 侧构建同一提交的
两种 helper 并作为 CI 内部产物
交给 Windows GUI job 打包。两种资源必须包含在最终应用安装包与 dist 中，但不作为独立
Release 下载项发布。

上传后的远端共享资产位于 `$HOME/.anywork/remote-helper/<version>/<digest>/`，归 SSH 用户
所有，不属于某个 Project 或 Thread。每次上传在最终目录内独立创建临时文件，使用私有权限，
完成后原子发布，失败、取消和连接收束只清理本次暂存，不共用固定 `.tmp`。并发上传同一资产
不能暴露截断可执行文件或删除另一请求的暂存；成功发布的共享资产不随单个会话关闭删除。
发布前确认暂存字节数与本次完整资产长度一致；传输提前结束不能仅因 `cat` 遇到 EOF 成功
就缓存残片。该检查复用目标平台标准文件工具，不增加网络下载或凭据转发。
该目录只保存 helper 资产，模型不能将其当作自己的执行 scratch。

两种 musl 标准库目标由固定工具链声明，rustup 在同步该工具链时一并安装，构建者不需要单独
执行 `rustup target add`。目标链接器或 Zig 仍由构建环境提供，缺失时构建入口报告具体目标、
所需可执行文件与替代方案。

Linux 本地 worker 使用同一资产来源，保留匿名不可变可执行镜像和文件句柄 lease；旧会话
持有的镜像不随资源替换而变化，不直接执行可能被覆盖的随包文件。此分发变化不改变进程
监督、取消、Ready 准入、失败保持不可用及退出回收契约，不迁移或删除用户数据。

预编译 helper 除 SHA-256 外必须携带目标架构与 worker 协议版本元数据，缺失或不匹配时
拒绝并提示重建。宿主架构复用 worker Ready 协议做实际握手，其他架构仅校验静态元数据；
探针拥有并回收子进程，退出、版本不符与超时分别报告，有界保留 stderr 和执行路径。同一
物化 helper 的启动失败在当前 runtime 内保持不可用，重启后重新准入，不延长原有超时。
