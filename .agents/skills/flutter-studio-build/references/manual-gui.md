# 原生实验的隔离与平台补充

共同步骤只维护在[无头实验指南](experiments.md)。纯界面布局、局部交互及截图选择官方 Widget
Previewer，不构建 Rust bridge；本页只说明必须运行真实产品时的隔离、凭据与平台责任。

## 入口与显示

```bash
cargo xtask manual-gui --preset gui --inspect
```

harness 持有隔离 `ANYWORK_HOME`、本地模拟供应商、真实 bridge GUI 和进程树，普通 xtask
只按需编译、启动独立 `pl-studio-acceptance`，不链接其重依赖。CLI 的场景参数是 `--preset`，
先读当前帮助，复用已有 fixture 和事实检查，不为新实验创建永久 example、UI 脚本或私有协议。

Linux 无显示环境时，先核对 `xvfb-run`、`Xvfb`、`xauth` 和原生构建依赖。将 `TMPDIR` 指向
当前会话 scratch 内准备好的临时目录，再运行：

```bash
GDK_BACKEND=x11 xvfb-run -a -s '-screen 0 1440x1000x24' \
  cargo xtask manual-gui --preset gui --inspect
```

无需 TTY 或 `script`。通用验收复用已有 debug native launcher、官方检查入口及原生退出报告，
通过官方 VM Service 连接能力附着；不以 resident 工具退出码代证产品退出。Xvfb 只提供显示，
控件和内容截图由官方 MCP 操作；虚拟屏幕尺寸不等于
实际 Flutter 视口。Windows 原生仍需可运行桌面应用的会话。不要把 `DISPLAY` 存在、启动成功、
GUI 截图或编译通过外推成完整业务/原生行为通过。

首次构建与 VM 就绪是不同阶段：复用 native launcher 的准备及启动边界，VM 期限只覆盖实际
产品启动，不包含 helper、bridge 和 Flutter 冷编译。保留首次错误，不以延长 VM 期限或用热缓存
重跑掩盖阶段混用；准备前失败按未启动收束所属构建进程，不能要求或伪造产品退出报告。

Windows 启动树由共享进程层的专属 Job 管理，准备取消后以 Job 活动进程数为零确认回收；
外层 Cargo 退出不代表构建后代已退出。进入 native 启动阶段后仍须校验原生退出报告，
EOF／取消仍报告失败。无需手工调用 `taskkill`，也不增加额外启动脚本。
进程回归可直接运行 `cargo test --locked -p pl-dev-support`，验收阶段衔接使用
`cargo test --locked -p pl-studio-acceptance windows_cleanup_tests`；这些验证 Windows 工程
进程生命周期，不能替代官方 Flutter `integration_test` 或真实原生 GUI 的 done／EOF／取消观察。

Windows 工程进程层暂时固定引用 `process-wrap` 上游已合并提交
`2f4bc393d8bd03b4b1c81fee2e13ce82dd42906e`，其共享 Job 句柄能力尚未包含在 crates.io 10.0.1；
不修改产品运行时依赖，也不复制依赖的 Job 创建及挂起／恢复实现。调用方持有清理期限，
Job 完成仅作一次官方 accounting 查询，避免完成端口排空或析构等待越过期限。
接口依据为上游 [JobObjectHandle](https://github.com/watchexec/process-wrap/blob/2f4bc393d8bd03b4b1c81fee2e13ce82dd42906e/src/windows.rs)
与 Windows [QueryInformationJobObject](https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-queryinformationjobobject)。

真实供应商仅在具体授权后使用 `cargo xtask run-gui --inspect` 读取已有配置，不更改凭据；
若数据根已占用，先核实独立、受保护的配置与凭据关联，不复制正在写入的数据库。
桌面资源从 bundle 的 `data/remote-helper/` 校验加载，不用 PATH 中 helper 冒充资源完整。

## 专项场景仍复用原所有者

- `plan-recovery --inspect`、`history-fault --inspect` 沿原多生命周期、锁及保存断言运行，
  每次重开重新发现、连接本次应用。通用实验方法不替代这些事实检查。
- `history-fault` 默认 Profile，`--inspect` 显式选择 debug；计时证据不能跨模式混用。
  Profile 的普通 Driver 命令不表示支持 debug Inspector 的全部能力。
- 自动化功能和 OS 生命周期走 `test-project --suite desktop|native`，断言由官方
  `integration_test` 或进程外裁判持有，不恢复 `test_driver`、`requestData` 或业务状态注入。
- `--native-launch` 直接运行原生构件，提供真实 PID/退出码；通用隔离验收复用这一条实现，
  不把它当作热重载入口。跨层开发确需热重载时才用普通 resident `run-gui --inspect`，
  不把该工具退出码当作原生验收；Rust/FRB/runner 变化需要完整重开。
- `--retain-environment` 的回执给出自有环境位置；复核须保留整个根目录，不能只复制 home
  后假定配置中的绝对路径仍有效。失败现场的保留与清理遵循原工具，不删除未知目录。
- 迁移观察的 `--seed-home-copy` 仅消费已关闭、经 SQLite backup API 制作的一致性副本，
  不接纳 WAL/SHM 或符号链接，不修改来源、原件或迁移备份。

## 系统凭据隔离

`ANYWORK_HOME` 只隔离产品数据，不隔离系统 keyring。模拟账号优先使用唯一 ID，覆盖当前
`account:<id>` 和迁移前 `provider:<id>` 关联；不能在真实 UI 创建账号后假定随机 ID 足以保护凭据。
不为验收增加生产内存凭据开关。

Linux 涉及真实凭据 API 时复用现有 `account_usage` 的私有 D-Bus/Secret Service 装配：
独立 XDG data/config/runtime、runtime 权限 `0700`、短 socket 路径，移除继承的 keyring control
socket；仅解锁本次空合成 keyring，用服务注册通知等待就绪，不固定 sleep 或解锁用户 keyring。
服务启动失败必须失败，不能退回操作者凭据或把访问失败当作条目缺失。

所属 daemon 正常、失败或取消都要停止并 wait。清理前核对本次私有根与用户身份，通过
`findmnt` 检查挂载，只对精确的自有 `runtime/doc`（`fuse.portal`）和 `runtime/gvfs`
（`fuse.gvfsd-fuse`）使用一次普通 `fusermount3 -u`；不强制/懒卸载，不跨挂载递归删除。
未知挂载、身份变化或卸载失败保留目录并报告。原命令失败不被清理覆盖，原命令成功而清理失败则整体失败。

## 机器人模拟环境

`manual-gui --preset gui --bots-fixture` 复用 Linux 私有凭据、模型和 Feishu peer 的原所有者；
当前组合不支持 `--inspect`，不能声称已完成 MCP 原生机器人旅程。不兼容选项明确失败，不退回真实平台。
环境输入只设置合成对端，不执行产品授权或 UI 动作：

```text
bots-env registration pending|slow-down|denied|expired|complete|complete-without-user
bots-env message unknown-direct|resend-direct
bots-env conversations prepare-pages
```

使用当前 CLI 支持的单个实际动作，不能把上面的候选分隔形式原样发送。
动作不接收 URL、凭据、联系人或正文；同固定身份重投不能用于等成功。脚本设置与排队记录不证明
产品消费、配对、保存或发送；这些结果由真实生产界面与对应请求证据判定。截图不得泄露活跃二维码或验证链接。

## 收束与证据

通用实验的 `done` 只请求产品正常退出、等待启动器并校验已有原生退出报告；截图在此之前用官方工具采集和核图。
EOF、取消、关闭失败及未完成 fixture 主步骤分别报告，人类 verdict 默认 pending。
内部内容捕获和 VM 脚本仅服务现有自动化/测量，不再作为人工截图教程。

结合产品关闭结果、所属 launcher 终态及进程树事实判断回收。Windows Job Object、Linux
subreaper、macOS `process-wrap` 进程组各有边界，macOS 不涵盖主动脱离组的子进程。
若必须强制回收残留，不能称应用自然退出。取消只处理本次所有的进程，不无差别杀桌面或邻居会话。

Flutter 内容不含窗口装饰、系统菜单、IME 或平台剪贴板。真实文本选择/复制须通过真实手势并逐字
核对剪贴板，不能直接写期望文本。原生输入不以框架文本 action 代证物理回车或 IME；仅在任务要求时补验。
多生命周期以不可覆盖的阶段事实、真实 Thread/Turn/call/task 身份和保存水位关联证据，
不以短暂 latest 值、同名条目或 completed 状态代替持久化完成。
