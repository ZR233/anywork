# 22 - SSH 远程开发

## 22.1 架构边界与实例生命周期

SSH 是本地产品运行时选择的执行位置。Flutter 仅展示类型化产品快照；`pl-tool::remote::SshManager` 管理系统 OpenSSH、认证、资产引导及连接；`pl-remote-helper` library 提供统一 `Executor / Command / Child`、目标路径、流式文件与 HTTP。同 package 的 binary 在远端以前台 `--stdio` 运行，不保存 Thread、模型、工具注册、Git 工作树租约或授权策略。

原生宿主或受控观察可通过 `StudioRuntimeOptions.ssh_config` 传入既有 `SshConfigFile::at` 句柄；同一文件同时用于服务器目录解析和 OpenSSH 的显式 `-F` 参数，不依赖改变 `HOME` 推断 OpenSSH 会读取哪个文件。省略时保留用户默认配置及 OpenSSH 默认选项行为。该句柄是进程启动依赖，不是新的用户配置文件格式，也不能由模型工具覆盖；目录、认证、辅助进程上传及重连继续由原 `SshManager` 持有。

多个 Thread 可以共享同一 SSH 物理通道与 server，但各自持有独立的 MCP client、协议会话及 stdio 进程，不能因共用服务器而合并 Dart 项目根或调试状态。连接关闭后，旧 MCP 会话明确失效；用户显式重新连接后，新操作绑定新的执行器，不重发结果未知的进程启动或工具调用，不静默转到 Host。关闭一个成员不关闭其他成员的 MCP 或共享通道。MCP 层的错误分类、重连接口及会话状态重置见 [09](./09-tool-runtime.md#96-mcp-能力声明thread-独占运行时与轮次租约)。

每个运行时内的服务器别名至多有一条活动 SSH 连接和一个前台 server。并发 Connect 共享同一个初始化结果，单个观察者取消不取消其他观察者。稳定执行阶段的一条 SSH stdio 承载一条 h2 连接，多个 Thread、工作区、MCP、LSP、Git 与 CLI 共享它；首次平台探测和资产上传仍使用短期引导进程。引导 shell 可以 exec 进入 server，server 不被业务程序替换。

执行器不持有默认工作区。工作区只绑定具体 `{ executor, root }`，Thread 拥有自己创建的 Child、协议运行态和临时目录。关闭一个 Thread 或 MCP 不关闭其他 Thread 共享的 SSH。旧句柄固定绑定创建它的具体连接，连接关闭后永久失效；显式新建连接不能恢复或替换旧句柄。

状态为 `disconnected → connecting → ready → closing → disconnected`，连接或握手失败为 `failed`。不提供自动重连、接续、租约、心跳、h2 PING 监视、输出回放、操作去重或结果追索。网络故障发现跟随 OpenSSH；业务期限与连接存活独立。显式重新连接创建新 server，不重新提交旧操作。

SSH EOF、SSH 退出、h2 致命错误或 Disconnect 使 owner 一次进入 Closing：停止准入、取消准备与 I/O、终止仍持有的直接子进程并回收。客户端和 server 各自从观察到关闭起最多等待两秒；客户端超时保留已登记的本地清理 owner，不能宣称远端清理完成。server 超时从同步 main 对 runtime 执行零等待关闭并以非零码退出，避免 runtime 析构无限等待阻塞 I/O。SIGKILL、机器故障、不可中断内核等待及自行脱离的后代不提供全部回收保证。

## 22.2 传输、流控与文件

一次 Hello 精确核对私有 wire 版本 **2**、helper 构建、目标 OS/arch、home、初始目录和 shell；不传完整环境或恢复身份。版本不符在业务请求前失败，不降级。一次登录 shell 环境采集用于目标 PATH 与工具链初始化，与已删除的 session attach listener 无关。每条命令继承目标执行器冻结环境，再施加 `env_clear/env/env_remove`；不复制桌面环境，不改变全局 cwd 或环境。

进程启动及根退出使用一条主流，stdin/stdout/stderr 各用独立原始字节流，kill 使用独立控制请求。h2 负责多路复用和流控；普通准入 240、控制保留 16，server 同时流上限 256，每流窗口 64 KiB，连接窗口 32 MiB。真实 reader、writer、pump 与未归还流控引用持有许可，EOS 不提前释放未读 reader。公开 AsyncRead 实际交付字节后归还已 poll 的 credit。慢输出、文件或 HTTP 消费不阻塞另一进程的根退出和终止请求。

连接驱动不等待消费者、磁盘或子进程。根退出与输出 EOF／捕获完成独立保存；后者失败不覆盖已知根退出。业务退出码 255 与本地 SSH 退出码分属不同 owner。spawn 错误区分明确未启动、已启动与结果未知。单次参数、文件、非零退出或流取消不关闭共享连接；副作用操作不自动重试。

文件元数据与小型描述有界，内容使用双向原始字节流。read/read_dir 增量返回，目录项支持换行等 UTF-8 名称，非 UTF-8 明确失败。宿主浏览游标持有真实 reader 与至多一个待交付条目；server 不设工作区或游标服务。取消 next 不丢失已读取但尚未交付的条目。

write 必须显式 finish 才校验长度、flush 和发布；flush 不发布，shutdown 返回 Unsupported。ReplaceAtomic 与 CreateNew 使用同目录临时文件，分别原子替换或排他发布；取消或不完整传输保留旧目标。Append 允许留下已写前缀。响应丢失可能发生在发布之后，只报告未知。单执行器复制一次在目标端完成，递归复制不跟随符号链接，复制链接项本身；其他重解析点明确拒绝；跨执行器由产品泵送 reader 到 writer。Overwrite 合并目录并保留无关目标项；FailIfExists 在目标 OS 发布时排他拒绝已有目标，rename 跨设备明确失败，不降级为复制再删除。排他重命名复用目标系统能力：[Linux renameat2](https://man7.org/linux/man-pages/man2/rename.2.html)、[Apple RENAME_EXCL](https://developer.apple.com/documentation/foundation/urlresourcekey/volumesupportsexclusiverenamingkey)、[Windows MoveFileExW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)，底层不支持时保留原始错误。

补丁文本一次送至目标，由共享 `pl-patch` 算法按顺序执行。16 MiB 请求和 1 MiB 报告分别预检；不提供跨文件事务。产品在同一写锁内预检 Add/Delete/Update 和 Move 两端的冻结授权及可写目录，返回有序报告或结构化部分失败，按实际已知变更通知 LSP，不重放。已经开始的 native I/O 由登记任务持有并等待，取消观察不丢弃在途系统操作。

HTTP 在选择的执行侧由 reqwest 发起，使用该侧 DNS、代理、TLS 和 token 环境。状态码、多值原始头和响应体交给 MCP；显式 Authorization 优先。Host 默认仅同源 307/308，SSH 默认不重定向。JSON 可复用有限字节，流式请求不整份缓存。合法提前响应可停止未完成上传并保留完整响应；取消本次交换不关闭共享连接。

## 22.3 工具装配与 SSH 配置

模型使用相同工具名称与结构。普通 exec、stdio MCP、LSP、ACP 及通过命令执行的 Git 使用受管 Child；server 不解析 MCP/LSP。文件工具与临时目录通过同一个 `ExecutorWorkspaceFileBackend` 操作两种执行位置，命令归档通过同一个执行器 reader 只保存已确认的原始前缀。Thread 配置、所有权、媒体与可靠存储仍由产品持有。

### `~/.ssh/config` 管理块读写契约

SSH 服务器列表直接读取并解析用户的 `~/.ssh/config` 文件；新增、修改与删除受管服务器时，以带标记的管理块原子写回该文件，未触及的内容（含原始注释与行尾换行符风格）逐字节原样保留。管理块采用以下定界符包裹 `Host`、`HostName`、`Port`、`User` 与 `IdentityFile` 指令：

```sshconfig
# BEGIN anywork server: <alias>
Host <alias>
    HostName <hostname>
    Port <port>
    User <user>
    IdentityFile <path>
# END anywork server: <alias>
```

`Host` 别名即服务器的唯一身份（创建后不可改名，必须为非空单词元且不含通配符或否定字符）。配置解析遵循 OpenSSH 的首次匹配语义（每个关键字取块内首次出现的值，`HostName` 缺省回退为别名）；包含通配符、多模式或 `Include` 指令的复杂条目不进入可选列表，用户手写的普通 `Host` 条目以只读方式展示，编辑与删除仅对 `anywork` 管理块开放。新建别名若与文件中已有 `Host` 冲突则自动分配无冲突后缀；运行时内部发起的 `ssh` 调用仅传递 `Host` 别名，端口、用户名、私钥与跳转配置（`ProxyJump`）全部交由系统 OpenSSH 根据配置文件解析，运行时不维护第二份连接参数。

### 冻结端点与工作区

持久 SSH profile、规范项目路径及具体活动 Executor 是三个独立事实。工作树、审查绑定与清理须同时核对原端点和路径，旧句柄不能通过别名自动查询新连接。审查的只读归属核验复用原连接，不主动建连、上传或创建模型授权；原连接不可用时明确拒绝。普通显式创建、恢复与用户重新连接仍可创建新的执行绑定。

SSH 项目支持 local 与 worktree；后者在远端仓库的 `.anywork/worktrees/<root-thread-id>/session` 中建立受管 Git 工作树。租约与生命周期按 [12.5](./12-collaboration.md#125-git-工作树worktree生命周期与故障恢复)，归档清理按 [17.16](./17-studio-storage.md#1716-会话归档与临时数据清理)。离线不表示目录不存在，失败保留原责任；不以递归目录删除兜底 Git 移除，也不清理未知目录或用户原件。

持久远端项目、租约与端点比较使用标准 POSIX 绝对路径，由 `normalize_remote_absolute_path` 验证；命令与文件参数则交给绑定 Executor 的 TargetPath，不在桌面折叠 `link/..`。操作只在目标端解析现有路径或祖先。权限由真实工作区边界、调用授权和 writablePaths 决定；仅因为执行位置为 SSH 不强加 WorkspaceOnly。Host 授权仅能放宽 HostPermitted，不能放宽只读或真实 confined 边界。普通路径检查与操作之间仍存在文件系统竞争，不宣称提供沙箱。

SSH 固定使用 `-T/-x` 与建连超时，不注入 ServerAliveInterval/ServerAliveCountMax，用户 OpenSSH 配置继续生效。应用关闭先等待依赖 SSH 的工具、MCP/LSP 和生产者，再关闭 SSH owner。顶栏外部终端是用户独立启动的交互会话，不承载本协议、不随 Studio 退出终止。SSH 项目技能与桌面只读用户／系统来源的合并规则见 [10](./10-skills.md)。

## 22.4 凭据、路径与持久化

系统直接调用 `PATH` 中的系统 OpenSSH，完整复用用户的 `ssh_config`、`known_hosts`、`ProxyJump`、`ssh-agent` 与显式配置的代理转发（agent forwarding）：
- **密码凭据存储与 `SSH_ASKPASS` 非交互注入**：认证支持 `ssh-agent`、公钥文件及可选的 SSH 密码。SSH 密码与模型供应商 API 密钥共用同一套操作系统凭据库（`CredentialStore`，账户键名为 `ssh:<alias>`，编辑语义支持 `Preserve`、`Replace` 与 `Clear`）或当前进程内存会话租约，严禁写入 `~/.ssh/config`、SQLite、DTO、日志、辅助进程参数、环境变量或远端协议；删除受管主机时同步清除对应系统凭据。当存在可用密码时，本地 OpenSSH 子进程通过受控临时 `SSH_ASKPASS` 脚本（配合 `SSH_ASKPASS_REQUIRE=force`）从本地子进程专属环境变量完成非交互密码注入。
- **免密优先探测与服务端认证方式判据**：每次建立连接固定遵循“免密优先”顺序——先以 `BatchMode=yes` 非交互探测 `ssh-agent` 与公钥文件（含默认私钥、`IdentityFile` 与 `ProxyJump`）；若免密探测成功则直接完成连接，不弹出密码输入框。仅当免密探测以认证失败结束，且 OpenSSH 失败诊断 `Permission denied (<methods>)` 表明服务端接受密码类认证（方法列表包含 `password` 或 `keyboard-interactive`，或方法列表缺失）时，才通过 `StudioError` 的 `details` 字段（`sshErrorKind: "authenticationFailed"` 与布尔值 `sshPasswordOffered`）通知 GUI 弹出密码输入框；若服务端仅公布 `publickey` 等非密码认证方式（`sshPasswordOffered: false`），GUI 不弹出密码框，而是就地提示需配置密钥或 `ssh-agent`。前端与 SDK 仅消费这两个类型化字段，不解析 OpenSSH `stderr` 原始文本。
- **打开远程项目窗口契约**：Studio 的「打开远程项目」窗口绑定 `~/.ssh/config` 中的一个 `Host` 别名，仅接受该服务器上的绝对 POSIX 目录路径（不解析 `~`、相对路径、`ssh://` URI 或 `user@host:path`）。目录导航与手动输入路径均须先经 `browseRemoteDirectories` 获取权威目录列表；仅当路径已验证且与当前输入一致时才允许提交给 `openRemoteProject`，并在目录刷新及显式选中意图采纳该权威项目后才关闭窗口。浏览与打开操作严格串行化，失败时保留窗口与用户输入供原地修正重试。
- **产品数据库结构与历史迁移**：Studio 数据库不设独立的 SSH 服务器表，远端项目通过 `projects.ssh_alias` 可空列直接引用 `~/.ssh/config` 中的 `Host` 别名（本地项目按 `path` 唯一，远端项目按 `(ssh_alias, path)` 唯一且保存权威 POSIX 路径）。在数据库版本 `v20 → v21` 升级时，启动协调器先备份产品库，再将旧 `ssh_servers` 表中的记录幂等迁移为 `~/.ssh/config` 管理块，并在同一事务内将 `projects.ssh_server_id` 重写为最终别名后删除旧表。

## 22.5 辅助进程资产构建与随包分发

`pl-remote-helper` 编译为去除符号（stripped）的静态链接 `musl` 可执行文件（覆盖 `aarch64-unknown-linux-musl` 与 `x86_64-unknown-linux-musl` 两种 Linux 架构），由 `cargo xtask` 独立构建并使用 `zstd` 压缩后随 Flutter 桌面发行包分发，不嵌入 Rust 桥接动态库内部。Windows 与 Linux 的 CMake 构建脚本将资产安装至应用可执行文件同级的 `data/remote-helper/<target>/` 目录下，每个目标架构包含 `pl-remote-helper.zst` 与 `pl-remote-helper.metadata.json`（采用 `camelCase` 记录 `target`、`workerProtocolVersion` 与原始可执行文件的 `sha256` 摘要）。

随包资产仅服务远端 server。本地执行器使用相同 native 实现直接创建业务进程，不要求 PATH 中存在 helper，也不为本地 MCP、LSP 或 ACP 再启动监督 helper。

- 宿主根据可执行文件位置解析随包资产并显式注入。缺失、解压失败、架构／协议／摘要不符时明确失败，不回退 PATH、开发目录或网络下载；未使用远端能力时不因此阻断本地启动。外部模式可用于开发与验证，由显式资产适配器提供远端构件。
- **按内容摘要幂等上传与原子发布**：远端目标架构由 `uname -s` 与 `uname -m` 穷尽映射。连接建立后，核心层先探测远端架构，请求宿主适配器解压唯一匹配的辅助进程字节流，并上传至远端共享资产目录 `$HOME/.anywork/remote-helper/<version>/<digest>/`（若该摘要下已存在可执行文件则直接复用，免去重复传输）。每次上传在目标目录内创建具备私有权限的独立临时文件，校验接收字节数等于完整资产长度后原子重命名发布，防止因连接提前中断而缓存截断残片；该目录仅存放辅助进程资产，禁止模型将其用作临时工作区（scratch）。
