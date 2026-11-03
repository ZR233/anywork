# 原生 GUI 人工验收

## 入口与范围

- 从仓库根目录运行 `cargo xtask manual-gui --preset gui --inspect`，由 harness 创建隔离的 `ANYWORK_HOME`、
  本地模拟供应商和真实 bridge GUI，不修改用户配置或凭据。不要用 demo 证明持久化行为。
  xtask 仅按需编译并调用独立 `pl-studio-acceptance`，不链接该工具的重依赖。
- 先明确要验证的交互、状态变化、异常路径及证据；通过 `code/pl-studio-acceptance/src/`
  核实当前 CLI 与 `--preset` 参数，不为绕过终端检查选择无关场景。
- `cargo xtask verify-gui` 负责生成一致性、格式及静态分析，不包含 GUI 人工结论。
- 真实厂商验收使用 `cargo xtask run-gui` 读取用户已有配置，不把模拟通过外推为真实模型兼容。
  用户数据根已被其它 Studio 占用时，使用受保护的配置/Profile 副本与同一凭据关联建立独立验收
  home，进程级指定 ANYWORK_HOME；不复制正在写入的历史库，不修改用户密钥或原历史。
  使用外部 helper 模式的 Linux Studio/Server 入口需要 PATH 中存在匹配的 remote helper；
  桌面 xtask 入口使用 bundle 内的 `data/remote-helper/`，不能以 PATH 中的程序代替资源校验。
- 自动化桌面/原生生命周期走 `cargo xtask test-project --suite desktop|native`。
  `wait-events` 与 `shutdown` / `single-instance` 由 harness 自动判定；其余 preset 是操作者
  runbook，人类 `verdict.json` 保持 pending。
- 默认通过 Flutter 层取得图像：官方 MCP `flutter_driver_command` 的 `screenshot` 可直接观察
  当前原生应用；harness 的 `ext.anywork.capture` 继续提供带来源元数据的落盘 PNG。
  浏览器预览须标为合成组件证据；Flutter 内容不包含原生装饰、系统菜单或 IME。

Markdown 排版定向复核可运行 `cargo xtask manual-gui --preset markdown-layout`，
通过真实输入框发送 `展示长 Markdown 表格、引用与代码排版样例`。模拟供应商逐行流式返回
长表格、中文、行内代码、路径、链接、引用和缩进代码块；原文保存在 fixture 的
`assets/markdown-layout.md`，可用于核对真实选择与复制。此场景沿用交互式记录与 `done`
收束，不进入自动门禁；截图、快照与临时探针仍只保存在忽略的证据目录。

## 跨平台启动与显示条件

Windows、Linux 的布局、交互和 Flutter 截图共用官方 MCP 接口。`--inspect` 仅启用独立 debug
入口，`integration_test` 仍由自己的 binding 驱动；不把 MCP 操作记录称为自动化断言。

Linux SSH 没有显示服务时，先检查 `xvfb-run`、`Xvfb` 和 `xauth`。执行工具支持伪终端时直接
启用其 TTY；否则使用系统 `script -q -e -c '<命令>' /dev/null`。例如在可写 TTY 中：

```bash
GDK_BACKEND=x11 xvfb-run -a -s '-screen 0 1440x1000x24' \
  cargo xtask manual-gui --preset gui --inspect
```

Xvfb 只提供 Linux 显示环境，不参与控件定位、输入或截图；虚拟屏幕尺寸不是实际 Flutter 视口。
Windows 原生运行仍需可运行桌面应用的会话。保留本次启动日志中的 DTD/VM Service 地址，待应用
就绪后连接；认证地址不提交或公开。首次构建使用同一任务等待，不重复启动。

支持 `--retain-environment` 的 preset 正常关闭后会写出 `retained-environment.json`。
复核时保留整个环境根，避免配置内绝对路径失效；仅复制 home 不足以重开同一合成会话。
按回执中的 home 设置进程级 `ANYWORK_HOME`，不将合成配置写入用户数据根。

## 涉及系统凭据的隔离场景

`ANYWORK_HOME` 只隔离产品数据，系统 keyring 的 `account:<id>` 项不随数据根改变；
账号升级还可能读取迁移前 `provider:<id>` 项并创建新关联，隔离模拟必须覆盖这两个命名空间。
预置实例优先使用唯一 ID；若验收必须通过真实 UI 新增账号（由 UI 自动生成账号 ID），
不能仅靠临时 home 就读写这些 account，也不能新增生产内存凭据开关绕过真实边界。

Linux 可为该场景创建私有 D-Bus 会话，并把 `XDG_DATA_HOME`、`XDG_CONFIG_HOME` 和
`XDG_RUNTIME_DIR` 全部指向自有临时目录；runtime 目录权限为 `0700`，路径保持足够短以容纳
Unix socket。移除继承的 `GNOME_KEYRING_CONTROL`，不复用用户 keyring 的 control socket。
需要 Secret Service 时，在该隔离环境中前台启动 `gnome-keyring-daemon --unlock --components=secrets`，
仅向新建测试 keyring 提供空的合成密码；使用 `gdbus wait` 等待服务注册，不以 sleep 猜测就绪。
daemon 必须归属本次进程树，并在正常完成、失败和取消时停止、wait 和核对 PID；不能尝试解锁
或清空用户已有 keyring。可参考现有 `pl-studio-acceptance` 的 `account_usage` 模块封装
（CLI preset 名仍为 `provider-usage`）。

证据脱敏应保留当前场景的判定信息：安全的 HTTP method/path、凭据 alias、请求计数与错误
类别，而不是 Authorization 或完整请求正文。通用日志投影可能只保留启动计时；扩展场景时
核实实际失败原因也能落盘并传播退出码，不能因脱敏而把不同失败都变成不可诊断的空日志。

### 飞书平台的原生组合环境

需要同时观察真实 bridge GUI 与本地飞书平台时，显式运行：

```bash
cargo xtask manual-gui --preset gui --bots-fixture
```

该模式仅用于 Linux debug 的隔离验收，自动持有模型 fixture、Feishu peer 与私有凭据环境；
不支持的平台或不兼容场景明确拒绝，不回落到操作者 keyring 或真实飞书。SSH 下仍按前文
补齐伪终端与 Xvfb。环境成功启动、局部编译或 CLI 负例通过均不证明首配/E2E 已通过。

harness ready 后，可向其 stdin 写入以下固定环境动作；它们不是 GUI 操作或手机授权：

```text
bots-env registration pending
bots-env registration slow-down
bots-env registration denied
bots-env registration expired
bots-env registration complete
bots-env registration complete-without-user
```

动作只设置本次 peer 后续轮询的合成回包，不改已捕获的在途响应；单步脚本消费后恢复
Pending。`complete` 包含合成首用户身份，`complete-without-user` 不构造用户身份，仍须从
GUI 观察其默认拒执行与本地配对流程。不要传 URL、device code、secret 或真实联系人，
不要把模拟 `expired` 当作点击产品取消；未知动作只安全拒绝，普通动作码仍只记录。

配对与分页环境另提供三个固定动作，不接受联系人、正文或凭据参数：

```text
bots-env message unknown-direct
bots-env message resend-direct
bots-env conversations prepare-pages
```

先等真实连接，再送 `unknown-direct`，用真实界面确认只产生配对而未执行模型；本机批准后
送 `resend-direct`（同合成联系人，不同消息身份），由真实界面与模型/平台记录证明续发结果。
每个动作重复执行都是固定身份重投，不能靠反复发送来等成功；默认模型场景只消费一次主
输入，准备新的已授权消息旅程时使用独立环境。`prepare-pages` 只在 peer 设置 25 项合成群
目录与历史（含一个历史权限拒绝群），需通过 GUI 真实查询、翻页与错误展示判定，不写产品
授权或账本。没有活跃 socket 的消息动作会真实报错并进入清理，不能把 `event-queued` 或
`environment-set` 当作产品已消费、批准或发送成功。

`operations.json` 中的固定环境动作及 `script-set` 只证明脚本设置，不能证明产品已消费或
保存。人工结论仍为 pending；平台报告的资源成功只覆盖 peer listener/socket，最终还须
核对私有 D-Bus、keyring、Flutter/GUI 的真实退出。截图前使授权过期/取消或完成脱敏，
不能直接分享仍带二维码、验证链接的原始 capture。

## 人工操作与内容捕获

临时文件位置遵循当前 `studio.session-files`，工程入口明确指定的证据目录除外。下面的
`target/gui-acceptance/` 是显式的本地工程探针示例，不是产品的命令 capture 或通用会话
临时目录。

1. 读取当前 Dart MCP 的工具 schema；`dtd.connect` 使用启动日志中的 DTD URI，
   `appUri` 使用已连接应用的 VM Service URI，不能混用两者。仅有 VM Service 的原生直启
   可按官方 `vm_service.connect` 的 schema 附着，或直接使用 Flutter Driver SDK。
   用 `widget_inspector` 的 `get_widget_tree` 发现真实控件；用 `flutter_driver_command` 的
   `get_diagnostics_tree` / `get_offset`、`tap`、`enter_text`、`scroll` 和 `screenshot`
   检查布局、交互与画面。多应用时显式指定 `appUri`，不猜定位器。自动化断言使用
   `test-project` 或 `cargo flutter test --no-pub test/ui`；系统交互才使用真实键盘/指针。
2. 控件身份优先读取本次 widget tree，源码中的 `StudioDriverKeys` / `StudioDriverKeyValues` 用于补充定位。动态 key 可包含
   account/profile ID，不能猜测为空或照抄上次 ID。折叠面板只点真实标题行；存在性、可见
   几何与标准组件的真实展开态分别核对。
3. 关键状态分别保存内容捕获 PNG、必要的最小快照和日志，并实际打开截图核对。检查布局
   溢出、菜单边界、禁用态与键盘可访问性；按需求覆盖长名称、窄窗口、空数据及无效选择。
   保存行为必须观察 bridge canonical 状态，必要时重新打开验证；仅点击当前值不能证明
   更换值后的持久化。只有一个 fixture 模型时，明确记录覆盖不足。
4. 宿主落盘使用应用 `--packages=.dart_tool/package_config.json` 执行
   `code/anywork/tool/capture_ui.dart`，调用 `ext.anywork.capture`。发布构建不注册该
   extension。需要协调退出时同一工具加 `--exit`，由 `ext.anywork.requestExit` 请求产品
   退出；不能把截图成功当作原生进程已退出。
5. 不把临时原始快照当作已脱敏产物。用户明确要求产品截图证据时，优先用 PR 附件；仅按
   授权保留必要的已脱敏展示资产。

原生文本输入优先用真实键盘与平台 IME。不对聚焦文本框使用「全局动画全部停止」作为编辑
完成条件。`sendTextInputAction` 一类框架通道不证明物理回车。Linux 可在私有 D-Bus、Xvfb
与独立 XDG 目录中使用系统 IBus；它们的 config owner、引擎与凭据服务也须由本次进程树持有
并回收。保留组词预览、确认后文本与未提交状态的实际证据。

## 跨重启交互

- `cargo xtask manual-gui --preset plan-recovery` 使用同一隔离 home 的多个原生 GUI 生命周期，
  覆盖待确认计划重开后的批准、修改和已回答计划不再弹出；Linux 无显示环境时配合 Xvfb。
- 起始页的 Thread 在提交 prompt 后才创建，不能先等待 Thread ID 再提交。Turn 已 completed
  也可能仍在 flushing；成功等待须包含持久化就绪，不能把 completed 当作等待失败条件。
- 打开项目后，composer 存在不代表项目选择已完成：它可能仍属于旧页面或尚未绑定项目的
  起始页。首次业务操作前等待 canonical `selectedProjectId` 非空，且与当前 `project.id`
  及本次选择的 `project.path` 一致；不要靠重复创建或提交补偿尚未确认的导航状态。
- 跨进程阶段使用独立不可覆盖的阶段事实或显式握手，不依赖 latest-stage 的短暂值。用于
  证明无额外请求的观测文件必须传播写失败，不能用陈旧计数制造静默窗口通过。
- 多 Turn 旅程按本次 canonical callId/itemId 绑定工具与 UI 断言；同名工具可以多次出现，
  不能用全历史第一个或最后一个同名条目替代精确身份。

## 原生专项（不属于通用截屏合同）

下列证明走 `cargo xtask test-project --suite native` 或对应平台作业，不靠通用 X11 PID
检查或系统窗口截图代证：

- Linux 进程树回收与 subreaper
- Windows Job Object（Linux 上列为批准的 `notrun`）
- macOS `process-wrap` 进程组、AppKit 终止与 bundle 身份
- 真实 native pid / 退出码 / 重开 / 第二实例交接

可访问性补验先确认构建模式。profile/AOT 会裁去 Flutter 的诊断属性；需要只读 VM evaluate
时使用独立 debug 原生窗口，沿用完整保留的合成环境，不修改生产入口或 SDK。Linux 先核对
当前 Flutter engine 的设置来源；写 GTK/GSettings 不自动证明 Flutter 收到了
`disableAnimations`。活动中的动画观察须先确认目标仍在等待。

富文本选择与复制：排版截图正确不代表复制正确。覆盖中文与行内代码、连续代码片段、长路径、
标题后有/无空行，在正常/窄窗口及不同文字缩放下执行真实选择与复制，逐字核对剪贴板。
不得直接写入期望文本伪造成功。

## 结束、回收与判定

- 在 harness ready 后，通过所属 task 的 stdin 发送实际发生的动作代码（如
  `open-settings`、`select-model`），这些代码只是记录，不会替你执行 UI 操作。
- 完成后发送 `done\n`。harness 调用 `tool/capture_ui.dart` 保存 Flutter 内容 PNG，并经
  `ext.anywork.requestExit` 请求应用 shutdown；必须等待原任务终态，核对
  `capture-stage.txt` 的 `shutdown_completed`，再以原生退出报告的退出码和子进程回收结果
  核验。漏发退出请求会触发已武装的原生期限。
- 失败或取消也要回收：优先向本次伪终端发送 Ctrl-C，让 harness 清理；必要时使用任务取消
  并等待终态。核对本次所属 Flutter、GUI、fixture 与 Xvfb 进程是否退出。
  不使用无差别 `pkill`，不杀用户已有桌面或无关任务；仍有残留则明确报告并按所有权处理。
- 结合截图、快照、日志和进程状态给结论。`verdict.json` 默认为 `pending`；命令 exit 0、
  日志无错误或截图成功均不自动构成完整验收。未执行 fixture 主流程时可能提示
  `Fixture main step was not exercised`，可报告定向 UI 结果，但不能宣称端到端流程通过。
- 汇报实际平台/显示方式、覆盖项、未覆盖项、证据目录、命令退出状态和回收结果。
  遇阻记录真实命令及原始错误，区分缺 TTY、显示服务、原生构建依赖、VM Service 定位问题。
  缺工具时报告具体缺项，不擅自安装系统包，也不写死机器专用 include/library 路径。
