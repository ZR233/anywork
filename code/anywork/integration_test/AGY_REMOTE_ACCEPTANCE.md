# agy 远程生产会话验收输入

本入口复用 `acp_agy_conversation_test.dart`、`ProductionStudioHarness` 和
`test-project --suite desktop --case acp_agy_conversation`，不是另一套运行时。
agy、ACP 协议进程与 Host MCP 都在运行 Studio 的宿主上；仅业务工作区通过普通 SSH
机制访问 Linux 目标。不向目标安装 agy/MCP，不复制登录态，不建立反向隧道。

## 场景与证明范围

远程场景要求真实 `session/new`、真实 `configOptions` 及其中一项可选配置变更，
随后通过正式 `anywork_` 工具通知、原始工具／协作回执和独立进程／SSH 文件回读
验证行为；模型回复或工具标题不能单独证明远端执行。
没有 live 开关或缺少输入时失败，不使用测试内 `skip` 报绿；普通 full 集的
显式供应商用例选择仍由 xtask 的 opt-in 机制负责。

一轮远程场景在**同一真实 ACP session**中通过三个真实 UI 用户 prompt 执行，
marker 分别为同一运行前缀加 `A`、`B`、`C`。每阶段独立有界 **240 秒**，不把
单个 prompt 的期限累加放宽；外层 16 分钟仅容纳三个阶段、准备与关闭。

| 阶段 | 业务与严格完成点 |
| --- | --- |
| A | 文件／位置挑战、STDIN/EOF、长命令取消；要求原任务终态与独立文件／进程回读，再取得 root 新 run 的成功终态 |
| B | 同账号 ACP child、wait_agent 原报告身份及关闭 child、独立 child 挑战回读；不重做 A，不启动关闭测试任务 |
| C | 第三个任务的真实受理、list 和一次 1 ms wait 证明仍运行；root 此时明确结束本阶段，不能继续等该业务任务终态，随后由测试关闭成员并核对回收 |

每阶段先记录前一 completionSequence/run，再观察本次真实受理的 `activeRun`，
仅接受相同新 run 且 completionSequence 严格增加的成功完成；上一阶段的 idle 或
lastCompleted 不能充当新阶段完成。同一 session/target 身份、阶段用户原文与最终
assistant marker 都须匹配。各阶段只用自己的新 tool call 集验证，再最终重验全阶段来源。

完整场景保留以下必要断言：

- 远程文件读取／写入与小命令的位置回读；
- 阻塞输入的长命令、一次性 STDIN 与 EOF、精确任务 ID 的 wait／终态读取；
- 第二个长命令取消、原始 cancelled payload 与独立所属进程退出核对；
- 真实 ACP 协作子任务、原始 `generation/run/completionSequence` 身份以及
  `anywork_wait_agent`，不虚构 ACP 没有提供的 Native input/turn 字段；
- 在第三个远程进程树仍运行时关闭 ACP，然后核对公开关闭回执、harness shutdown、
  本机所属进程退出与远端进程树退出。干净 shutdown 不单独代证远程退出。

`agy-live-report.json` 只有在所有场景断言完成后才写入场景通过结论。
Native 混合方向回归是独立证明，不由本 ACP 场景外推，也不因此引入额外真实供应商。
没有真实运行时只能报告准备或静态检查结果，不能宣称实际行为通过。

## 运行前条件

1. 使用完成必要统一生成和环境准备的同次源码。实际调用使用项目
   xtask 入口，它负责当前源码的 bridge、宿主 Host MCP 和目标架构 helper 资产；
   不手工复制 bridge 或使用其他工作树的构件。
2. 宿主已有登录成功的官方 agy。保持原 `HOME`，不要传 `--login`、
   `--dangerously-skip-permissions` 或通过远端 agy 绕过宿主模型。
3. 有一个**已存在**的 SSH Host 别名。现有生产 `openRemoteProject` 只接受已配置
   别名；测试只读 `listSshServers`，不会调用 `saveSshServer` 或写 `~/.ssh/config`。
   此场景要求别名解析为显式 `user@host`、端口 22。直接 `ssh user@host` 成功
   不表示产品已经具有相应别名；缺失时明确失败，不自动创建配置。
4. 先以 `BatchMode=yes`、`StrictHostKeyChecking=yes`、有界连接期限对该目标预检。
   信任或凭据不足就停止，不猜密码、不修改 known_hosts、不降低校验。
5. 准备目标上仅归本次验收的临时 Git 项目。路径必须是 `pwd -P`
   给出的绝对规范路径，末级目录形如 `anywork-agy-*`，不要使用已有用户项目。
   夹具只含合成数据：
   - `README.md`：逐字为 `Disposable ACP live acceptance workspace. No private data.`
     并以一个 LF 结束；
   - `input-token.txt`：每次新生成的 64 位小写十六进制随机 token，末尾可带 LF；
   - 已初始化的 `.git`；
   - 尚不存在 `result.txt`、`command-cwd.txt`、`command-system.txt`、
     `child-result.txt`、`stdin.proc`、`cancel.proc`、`shutdown.proc`；
   - 支持 Linux `/proc`，提供 sh、cat、sleep、pwd、uname、git。
   token 是合成挑战，不是凭据；不要在提示词中提供它。不得预先创建期望输出。
6. 本机本 Thread 的 scratch 下准备一个新 sandbox 和空 `studio-home`，
   artifacts 下准备本次证据目录。`studio-home` 不得有旧 data/config/acp，
   不要通过删除历史目录使其变“空”。不要改 `HOME` 或复制账号凭据。

## 显式输入和标准入口

以下是 shell 参数示意，所有占位值都必须替换为本次事实：

```bash
export ANYWORK_AGY_LIVE=1
export ANYWORK_AGY_SANDBOX='<本Thread scratch下新sandbox的绝对路径>'
export ANYWORK_HOME="$ANYWORK_AGY_SANDBOX/studio-home"
export ANYWORK_AGY_ARTIFACTS='<本Thread artifacts下本次证据目录的绝对路径>'
export ANYWORK_AGY_COMMAND='<宿主官方agy可执行文件的绝对路径>'
export ANYWORK_AGY_ARGS='["acp"]'
export ANYWORK_AGY_SSH_ALIAS='<已有SSH Host别名>'
export ANYWORK_AGY_SSH_TARGET='<明确授权的user@host>'
export ANYWORK_AGY_PROJECT='<目标上新建独占anywork-agy-*项目的规范绝对路径>'

cargo xtask test-project --suite desktop --case acp_agy_conversation \
  --output "$ANYWORK_AGY_ARTIFACTS/test-project-report"
```

`--output` 的目录须尚不存在。`--case`、`--suite`、`--output`、`--list` 当前在
`xtask/src/cli/mod.rs` 中定义；该用例已由测试发现机制选取，不新增选择器。
不要运行 `manual-gui --ssh-target` 来代替：该选项仍只属于 `tool-scroll`。
Linux 无显示服务时使用系统 Xvfb，并按构建技能将 `TMPDIR` 指向本 Thread
scratch 中准备好的目录；不能占用 1420 端口。

本场景需要 Linux 宿主和明确的本机 agy 命令，用 `/proc` 观察原位进程身份；
不接受 `ANYWORK_AGY_MANAGED=1`。托管安装的原本地文本分支保留，必须沿原
隔离安装准备，不能把开关当作已验证登录的证明。原本地文本场景继续使用
`ANYWORK_AGY_PROJECT=$ANYWORK_AGY_SANDBOX/project`，且不设置两个 SSH 环境变量。

## 独立证据与失败收束

- Studio 通过公开 Client 打开带 SSH 身份的项目；界面选择 ACP、创建会话、
  变更配置和发送提示都使用真实生产控件与 `WidgetTester`。
- 测试只读夹具获取挑战，不把挑战交给模型。模型必须经 `anywork_` 文件工具
  读取、写入 `result.txt`，并经命令工具把真实工作目录与 Linux 内核类型写入文件。
  独立 `ssh` 观察者只读取这几份合成文件，比较 token、marker 和规范工作目录。
- 测试在隔离 Studio home 中通过公开设置命令保存一个绑定同一 agy 账号的
  ACP child Profile，在 root 创建前等待其 canonical 快照。不改操作者的配置。
- STDIN 任务从自身 `exec` 原回执获取 taskId，并由 `list_tool_tasks` 确认，
  再执行一次 `write_stdin`（含 EOF）。检查受理字节数与关闭状态，随后读取精确
  taskId 的终态原件；远端 `stdin-value.txt`、`stdin-eof.txt` 和进程退出独立证明
  消费与 EOF，受理不代证消费。
  ACP 工作区任务原件是 `pl.host.tool-result/1` 的 `HostResult`，成功时读取
  `value`，失败时从 `value.output` 读取原命令观察；归档错误、缺页或未知包装均失败。
- 取消任务同样关联原 taskId、cancel acknowledgement、wait 与终态 payload。
  两个远端进程树各记录 shell 与 sleep 子进程的 `/proc/stat`，比较 PID 和
  starttime，不把复用的 PID 当作旧进程。观察者不发送信号或代替产品回收。
- 协作比较 spawn 返回的实际 agentId、wait_agent 的 target／cursor／gap、当前
  ACP 成员的 backend／parentId 及原完成报告。只有取得报告后才关闭 child。
  ACP 的 `generation`、`run.instance`、`run.sequence`、`completionSequence`
  保持原身份，不从模型回答拼装。未知供应商 rawOutput 包装明确失败，不猜字段。
- 首个 prompt 前捕获本机 GUI 所属 agy／MCP／传输后代的 PID/starttime/exe，
  随阶段及正式工具状态事件增量记录，包含非主线程所生后代；已记录原进程即使
  reparent 也须以 PID/starttime 匹配后才能继续追踪。只读原所属树，不扫全系统命令行。
  阶段 C 留下一个仍运行的远端 shell/sleep 任务。
  检查公开 `closeMember` 的 localComplete、sdkFinished、宿主错误和未完成标志，
  记录能力相关的远端协议关闭诊断；不把对端关闭 ACK 当作宿主资源释放的前提。
  再执行原 harness 关闭，独立确认所有已记录本机后代与远端任务身份均已退出。
  HTTP Host MCP 是宿主内服务，没有额外进程；其释放由公开 localComplete／
  driverError 关闭契约覆盖，不把缺少独立 MCP PID 当作进程退出证明。
- 每阶段 before-send、timeout/error、finally 以及关闭前写入独立 JSON 状态文件，
  保存 phase、activeRun、lastCompleted、受理 run、真实 tool call ID/名称/status、
  最后正式调用及进行中调用。必要 rawInput/rawOutput 采用白名单化正式投影：
  保留 taskID、任务终态、stdin receipt、wait_agent cursor/generation/run/完成序号；
  不导出任意命令正文、stdout/stderr/summary 正文、MCP 启动 env、authorization、
  capability、登录链接或凭据。已知合成过程命令和 marker stdin 可保留，其他正文脱敏。
  既有报告和截图只属于本次真实运行，截图不能代证 SSH 任务退出。
- 成功与失败均在同一 finally 路径显式 await closeMember 回执，再独立 await 原
  harness shutdown，并用同一组增量身份核对进程退出。只结束测试等待不算业务回收；
  原阶段错误优先保留，诊断与清理错误另记，不能用清理成功抹去阶段失败。
- 意外权限请求明确失败，不自动授权；失败后由已有 harness 执行产品关闭并保留
  证据。权限交互本身须沿真实生产 UI 验证，不能使用 blanket approval 或测试专用生产接口。
- 保存整个本次隔离 sandbox、远程临时项目路径和证据。测试不递归删除任何远程目录；
  后续只在核实归属与所有进程停止后，按明确授权清理本次资源。

无真实运行时只能报告“准备完成／未运行”，不能报告供应商、协作、关闭或完整验收通过。
