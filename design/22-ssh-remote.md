# 22 - SSH 远程开发

## 22.1 边界

Pure 的 SSH 远程开发是本地 runtime 的宿主能力，不是第二套远端 runtime。Flutter 只调用
typed Studio 功能并展示 canonical snapshot；SSH 服务器管理、连接状态机、helper 安装、
协议、重连和远端工具 backend 位于 pl-tool；pl-studio-runtime 只实现 SQLite、可选系统
凭据库与 helper 随包资产 adapter。SSH 服务器配置不是产品数据，唯一事实源是用户
`~/.ssh/config`（Windows 为 `%USERPROFILE%\.ssh\config`）。

远端 helper 是宿主的物理能力代理。每个宿主运行时与 SSH 别名拥有自己的 helper 实例；
稳态只有一条 SSH stdio channel 承载一条 HTTP/2 connection，所有工作区、命令、文件与
控制操作使用该连接内的独立 stream。首次平台探测和资产安装使用短期 bootstrap 进程，
完成后回收；worker 的本机 IPC 不构成额外 SSH 连接。

helper 实例与连接代次分别拥有生命周期。实例通过私有 Unix socket 接受 SSH relay，
接续凭证经加密通道传递，不进入 argv、日志或产品数据库。新的连接代次接管后旧代不能
继续操作资源。断线只撤销通道；每 5 秒的有应答业务心跳维持 30 秒实例租约，租约内可
接回原进程及文件句柄。PING 只诊断连接，普通数据及 PING 不续租。租约到期或显式关闭
封闭准入、回收进程树和所属暂存、等待物理收束后退出。SIGTERM 给予 2 秒退出机会后
升级 SIGKILL。失败的回收仍保留责任，不把超时报告为成功。

主机拥有工具语义、命令构造、递归遍历、glob、候选搜索、预算分配、恢复及归档策略。
helper 不拥有 Thread/Turn、工具 schema、模型、Git/worktree 策略或 Timeline。它保留
必须依据远端事实执行的文件路径约束、进程监督、物理偏移和提交回执。capture 采用主机
生成的写入计划，helper 直接写远端文件并同步原始输出；格式、计费与写入组件共享，
不把完整日志下载后再上传。实例退出、应用重启或远端重启后不恢复旧任务。

## 22.2 协议、资源与并发

协议版本为 9，删除版本 8 的共享帧 codec 与兼容分支。HTTP/2 组件唯一负责帧、多路复用、
流控及连接错误。目录、文件和命令正文位于 body。生命周期请求与 Stat 使用受独立字节预算
约束的 HEADERS-only 交换，确保 DATA 流控耗尽时仍可确认心跳、取消及文件事实；凭据 header
禁止 HPACK 索引。租约、收尾与元数据拥有独立准入，慢文件关闭不占用终止通道。
普通请求使用短 stream，每个命令输出使用独立长流，文件内容是二进制 body；
应用分片与 HTTP/2 帧独立。Stream ID 不作为跨连接身份；接续按实例、操作身份、文件
偏移和输出序号进行。未知协议版本明确失败，客户端和随包 helper 同步升级。

连接驱动不等待业务消费者、进程结束或磁盘操作。命令启动返回句柄后释放普通请求准入，
运行中的进程另持租约；stdin、stdout、stderr、退出观察、capture 与取消独立推进。
RST_STREAM 只结束传输交换，物理进程由明确终止操作及其 owner 回收。终态只有在进程、
输出交接与必要落盘结束后发布一次；已完成任务按完成顺序释放。

宿主在所有连接之间共享资源预算；helper 报告实际资源占用与余量。预算根据运行环境、
需求、消费进度与宿主配置调整，不按会话复制固定额度。并发、分片、目录页面和未确认
输出按需申请并在消费后归还。实际驻留字节、在途额度、句柄及等待者均计费。`ResourcePolicy` 结合系统可用内存、
cgroup 限额、相对份额和宿主显式 ceiling 产生预算；各连接再按实际连接需求分配，连接窗口
及独立控制池从同一宿主预算预留。等待登记按实际元数据字节计入宿主预算；控制交换池
耗尽只暂停新的交换，不能让等待登记与正在完成的控制消息争用同一子池而提前拒绝请求。
取消等待时同步归还登记费用。16 KiB 只表达 HTTP/2 的标准进展单位。wire 层的并发 stream
上界采用协议可表达值，业务容量由动态租约与逐 stream 物理准入决定，不以初次 SETTINGS
固化整个实例的吞吐量。收缩先减少
未来准入和 credit，继续承担已授予和未确认的数据，空闲后释放容量。

连接级与流级窗口共同纳入预算；数据流不能占满控制请求的 stream 准入和完成资源。
心跳、终止、确认及释放不依赖数据队列排空。按可推进分片准入，避免整文件的大额申请
阻塞小请求；持续小请求也不能使大传输饥饿。不依赖 HTTP/2 PRIORITY 或固定扩大窗口
保证公平。窗口变更等待组件确认，不撤销已经承诺的接收额度。

正常等待依靠 channel、watch、Notify、任务完成及流控事件；定时器只承担心跳、退避和
截止点。字节等待队列允许小请求绕过暂不能满足的申请，但绕过的累计字节达到最老申请的
一个进展分片后为它积累释放额度，避免持续小请求使其饥饿。建连与接续的在途结果由管理器共享，取消一个等待者不取消其他需求。显式连接意图拥有可取消
身份；自动退避只继续原意图，不能在 disconnect 后重新登记意图。发布连接与取消意图采用
同一短登记边界。工作区的单次在途打开先发布弱缓存，再移除在途登记；调用返回前等待
结果生产者关闭，避免完成结果继续持有最后一个工作区引用。close 先封闭准入，再等待连接 owner 的接管步骤交接，随后关闭其确认的通道。
未发布连接也先登记清理责任，任一清理失败不能跳过其他独立资源。锁只保护
短状态变更，不跨网络、磁盘、进程等待或外部回调。准入先于副作用，一次预留下一步
必要资源，避免持有一类额度等待另一类额度。所有等待可被取消、关闭和截止点唤醒。

目录以可释放的单层迭代句柄增量读取；helper 不做递归搜索、glob、Skill 扫描、过滤或排序。
主机完成递归、过滤和产品分页；游标绑定实例、
工作区及查询，取消或换目录即释放。不为全目录排序收集无界快照。隐式路径恢复跳过
运行时命令缓存，使用低优先级可取消预算；无候选、预算不足与搜索失败分别表达，不
限制用户显式读取工作区产物。

文件只接受普通文件。下载绑定源文件身份及偏移，以变化信息和 SHA-256 校验完整性；
上传写本操作拥有的暂存，确认完整分片后推进偏移。Create、Overwrite、Append 的
编排由主机拥有，helper 返回真实写入/同步/原子发布回执。重连先查询事实，禁止重复
追加或发布。Append 在路径级提交锁内构造完整替换并原子发布，源文件变化或复制失败不
留下部分追加。`copy_file_from` / `copy_file_to` 直接消费异步读写端，不要求整文件常驻内存；
分片并行数、分片大小与管线内字节随预算调整。stdin 和 spawn 同样不盲目重发；不确定的执行结果明确报告。

主机分页游标绑定路径、cwd、glob、目录包含规则与隐式恢复策略；显式关闭或取消当前页
立即释放底层 reader，遗漏的产品分页句柄由 300 秒空闲租约回收。页面排序仅作用于当前页，
不会为全目录排序先收集全部内容。目录选择器只持有当前页，换目录与退出通过 Client 关闭
游标；Client 关闭等待迟到页与关闭回执，失败的关闭仍保留责任。

每个命令的未确认输出按序号保留并计费，满后只背压该命令。主机确认交接后释放；终态
回执确认后删除登记，不保留历史墓碑。最后工作区租约释放后关闭句柄，连接接续只恢复
真实活跃资源。关闭并发收束独立 owner，单个失败不阻断其他回收。

请求编码、容量和业务错误只影响对应 stream；真正的连接错误撤销当前通道，仍在租约
内的物理资源可接续。诊断关联实例、连接代次、操作、阶段和额度，不包含凭据或正文；
SSH EOF 后有界排空 stderr。请求回执携带单调时钟计量的远端准入、接收、进程操作及文件
I/O 阶段时长，DATA trailers 携带发送流控等待；host 另记录自身准入、交换及回执释放时长。
远端阶段是 host 交换时长的组成部分，不能跨机器比较时间戳或把重叠阶段直接相加；文件
I/O 阶段包括必要的校验计算，不能等同于内核设备服务时间。心跳报告结果恢复查询次数与
RPC body 重传字节，诊断查询不会驱动正常业务。单条 TCP/SSH 链路故障仍可能影响全部 stream。

握手返回协议、helper build、OS/架构、capability 和实际 shell descriptor。Linux 实例
创建时采集一次用户导出环境，复用原有受监督的 shell 环境采集能力；接回同一实例不
重新执行启动脚本。实例重建重新采集环境。普通命令、Git 和 LSP 使用同一环境，显式
请求 env 最后覆盖；不继承 alias、函数或依赖真实终端的状态，不额外补写 PATH。
不提供 PTY、端口转发、调试器或跨实例后台恢复。

## 22.3 本地工具与 SSH 管理

pl-tool 的 SSH 管理器负责服务器校验、系统 OpenSSH、架构探测、随包 helper
bootstrap、握手 shell descriptor、连接状态与自动重连，并返回带执行环境的远端 workspace
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
死亡信号。正常关闭停止心跳、等待 helper 的物理清理回执，再关闭本地 transport 并有界回收
本地 SSH 进程；关闭回执未在截止点内确认时报告结果不确定，远端心跳租约继续承担回收责任。关闭编排把 SSH transport 的真实关闭排在对它
有依赖的远端 MCP / LSP / 工具停止请求与结果处理（以及驱动远端工具的生产者停止 ACK）**之后**：
管理器封闭连接准入后只跟踪 manager 交互 / 连接 / 浏览 / open_workspace 类 token，远端命令 /
backend / worker 仍持有原始 client，因此 transport 关闭不能与依赖抢跑，否则会先切断通信、把
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
GUI 退出。传输保存首次失败阶段与有界诊断，持续排空进程错误输出，密码不
进入诊断。单个本地输出接收端关闭只丢弃该端的迟到输出，不使同一连接上的其他进程和
文件操作断线；真实协议错误仍关闭连接。通道断开时现有操作进入接续等待，由宿主以 1、2、4、8、15、30 秒退避尝试接回原实例，
实际等待受剩余租约和操作截止点约束。接续成功保持工作区与进程身份，只替换连接代次；
实例过期则旧操作明确失败，新工作才建立新实例。实例重建通知活跃 root/child 刷新
工具绑定、shell descriptor 与相关 LSP/Skills 状态，不复活已关闭的工作区。

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
