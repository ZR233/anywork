# 原生 GUI 人工验收

## 入口与范围

- 从仓库根目录运行 `cargo xtask manual-gui`，由 harness 创建隔离的 `ANYWORK_HOME`、
  本地模拟供应商和真实 bridge GUI，不修改用户配置或凭据。不要用 demo 证明持久化行为。
  xtask 仅按需编译并调用独立 `pl-studio-acceptance`，不链接该工具的重依赖。
- 先明确要验证的交互、状态变化、异常路径及证据；通过 `code/pl-studio-acceptance/src/`
  核实当前 CLI 与场景参数，不为绕过终端检查选择无关场景。
- `cargo xtask verify-gui` 负责生成一致性、格式及静态分析，不包含 GUI 人工结论。
- 真实厂商验收使用 `cargo xtask run-gui --driver`，不把模拟通过外推为真实模型兼容。
  用户数据根已被其它 Studio 占用时，使用受保护的配置/Profile 副本与同一凭据关联建立独立验收
  home，进程级指定 ANYWORK_HOME；不复制正在写入的历史库，不修改用户密钥或原历史。
  使用外部 helper 模式的 Linux Studio/Server 入口按根 `AGENTS.md` 预先安装 remote helper；
  桌面 xtask 入口使用 bundle 内的 `data/remote-helper/`，不能以 PATH 中的程序代替资源校验。

## Linux SSH：补齐终端和显示环境

先检查事实，不根据控制端环境猜测：

```bash
test -t 0 && echo 'stdin: tty' || echo 'stdin: not a tty'
printf 'DISPLAY=%s WAYLAND_DISPLAY=%s\n' "$DISPLAY" "$WAYLAND_DISPLAY"
command -v script xvfb-run Xvfb xauth
```

默认 `gui` 场景要求交互 stdin；非 TTY 会返回 `manual-gui requires an interactive terminal`。
显示环境变量为空说明未指定桌面会话，并不证明本机无法运行 GUI。工具齐全时，可用伪终端和
隔离虚拟显示器，不占用用户桌面，也不绕开 xtask：

```bash
GDK_BACKEND=x11 xvfb-run -a -s '-screen 0 1440x1000x24' \
  script -q -e -c 'cargo xtask manual-gui' /dev/null
```

`xvfb-run` 只设置 X11 显示，不强制 GTK 选择该后端；即使 `WAYLAND_DISPLAY` 为空，
也不能仅凭进程的 `DISPLAY` 认定窗口在 Xvfb 上。隔离 X11 验收显式设置
`GDK_BACKEND=x11`，并核对本次显示上的窗口及 `_NET_WM_PID`。若 Driver 截图正常但
所属 X11 显示没有窗口，先排查显示后端，不修改产品或绕过窗口归属检查。

需要固定证据目录时，给内部命令增加 `--output target/manual-gui/<本次唯一目录名>`，
目录必须尚不存在；不要删除旧证据来复用路径。已有可用显示会话时按需要只用 `script`。
`script -e` 透传子命令退出状态，`xvfb-run -a` 自动分配显示号并在命令退出后回收 Xvfb。
不要把示例虚拟屏幕大小当作实际窗口大小；窗口尺寸须从截图、Driver 或窗口信息核实。

保持命令的 stdin 可写，保存后台 taskId；给首次 Rust/Flutter 构建留足时间，用 `wait`
等待，不重复启动。GUI ready 后才能交互。若启动迟迟未完成，检查本次进程树及其日志，
区分构建中、VM Service 未就绪、显示失败与应用异常，不盲目重试。

`tool-scroll`、`stress-body` 与 `wait-events` 使用性能分析构建。支持 `--retain-environment` 的场景
（包括 `tool-scroll`、`wait-events`）在场景成功、
运行时正常关闭且所属进程回收后，把本次合成环境保留在证据目录中，并写出
`retained-environment.json`。保留整个环境根，避免配置及工作区里的绝对路径失效；仅复制 home
不足以重开同一合成会话。随后可构建正式程序，以该文件中的 home 作为进程级 `ANYWORK_HOME`
运行 `cargo xtask run-gui --release`，进行系统截图复核；不要将合成配置写入用户的数据根。

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
（CLI 场景名仍为 `provider-usage`）。

证据脱敏应保留当前场景的判定信息：安全的 HTTP method/path、凭据 alias、请求计数与错误
类别，而不是 Authorization 或完整请求正文。通用日志投影可能只保留启动计时；扩展场景时
核实实际失败原因也能落盘并传播退出码，不能因脱敏而把不同失败都变成不可诊断的空日志。

## Flutter Driver 操作与取证

临时文件位置遵循当前 `studio.session-files`，工程入口明确指定的证据目录除外。下面的
`target/gui-acceptance/` 是显式的本地工程探针示例（便于复用相对导入），不是产品的命令
capture 或通用会话临时目录；换位置时同时按本地真实目录调整导入和 Dart 启动参数。

1. 使用 Flutter Driver，不用 Computer Use 覆盖 Driver 已支持的交互。优先复用
   `code/anywork/test_driver/flutter_driver_session.dart`；它提供有截止时间的操作和
   `readSnapshot()`、`renderTree()`、`screenshot()`。客户端在 `finally` 中关闭连接。
2. 从**本次**启动日志取得 VM Service URL。harness 最终日志会脱敏该地址，故需要在运行中
   根据本次子进程/日志定位；不要硬编码端口、PID、临时目录或以广泛扫描他人临时目录代替定位。
   区分 VM Service 与 DevTools 地址；VM 根路径可能只有 `/`，不能假定总有认证路径。
   不占用项目保留端口 `1420`，不对外暴露调试服务。
3. 先读当前源码中的 `StudioDriverKeys`、实际控件 key 与快照，再构建 Finder。
   动态 key 可包含 account/profile ID，不能猜测为空或照抄上次 ID。
   Linux 原生环境中普通 tap 的 hit-test 可能超时，项目已有 `rawTap` 扩展会验证目标及
   模态遮挡，应复用该入口而不是屏幕坐标点击；查找超时先核对 key、滚动位置及模态状态。
   折叠面板只点真实标题行，不点整个展开面板或静态正文的中心；展开后中心可能在空白、
   屏幕外或裁剪区。存在性、可见几何与标准组件的真实展开态分别核对，不把正文可点击当作
   成功条件，也不在已经展开时再次点击把它收起。
4. 临时定向客户端可放在忽略的 `target/gui-acceptance/probe.dart`，无需增加永久测试。
   该位置可通过 `../../code/anywork/test_driver/flutter_driver_session.dart` 导入会话封装。
   从根目录运行（将 `<本次VM_URL>` 替换为实测地址）：

   ```bash
   cargo dart --packages=.dart_tool/package_config.json \
     ../../target/gui-acceptance/probe.dart '<本次VM_URL>'
   ```

   包装命令实际 cwd 为 `code/anywork`；脚本的文件输出路径也须据此计算，或显式传入
   已确认的路径。不在 SDK 目录运行项目命令，不直接调用单个 GUI 生成器。
   独立 Driver 进程需要调用 Xlib 调整窗口时，启动它也须使用已核实的本次 GUI
   `DISPLAY` 与 `XAUTHORITY`；窗口枚举子进程成功不代表当前进程的 `XOpenDisplay`
   已获得授权。不使用 `xhost +` 等放宽访问控制的办法。
5. 对关键状态分别保存截图、界面树、必要的最小快照，并实际打开截图核对。检查日志异常、
   布局溢出、菜单边界、禁用态与键盘可访问性；按需求覆盖长名称、窄窗口、空数据及无效选择。
   菜单尺寸同时核对外框与真实菜单项几何，不能以外框收窄证明内容未溢出。使用
   `MenuAnchor` 的受控宽度时，核对官方 `crossAxisUnconstrained` 契约；默认允许横轴
   自然尺寸，单独设置 `MenuStyle.maximumSize` 不保证内部长内容受限，不另套布局兜底。
   保存行为必须观察 bridge canonical 状态，必要时重新打开验证；仅点击当前值不能证明
   更换值后的持久化。只有一个 fixture 模型时，明确记录覆盖不足。
6. 不把临时原始快照/界面树当作已脱敏产物；可能包含正文、配置与路径。只收集需要的字段，
   分享前检查并脱敏；不提交截图、运行日志、VM URL 或一次性脚本到源码库。

### Driver 宿主与原生文本输入

- Journey 客户端由独立 Dart VM 执行，不能导入 `package:flutter/services.dart` 等依赖
  `dart:ui` 的库；这些导入仅用于 app 侧 extension。`flutter_driver` 已导出宿主可用的
  `TextInputAction`，键盘扩展的 wire 参数使用已有纯 Dart 键值。`flutter analyze` 不证明
  宿主能运行；先用无参数入口核对预期 usage 退出码，再进行原生旅程。
- 仅连接现有 GUI 的纯 Dart 脚本统一使用当前应用的 `--packages=.dart_tool/package_config.json`
  直接执行，不通过 `dart run` 重新触发应用的构建钩子或原生资源构建。工具包装可能把非零退出映射成
  自身失败；同时核对原始 Dart 退出码，不能把 usage 失败误认为导入或编译失败。
- Driver 的 DTO 列表投影使用显式类型的空集合，避免 `?? const []` 将循环元素降为 dynamic、
  令分析器漏报已删除的 getter。统计等接口须以非空真实记录调用取证，空列表成功不能证明字段迁移完整。
- 不对聚焦文本框使用「全局动画全部停止」作为编辑完成条件，光标闪烁可以持续产生帧。
  优先读 `TextField.controller.text` 的 Driver `getText` 结果、当前交互身份及精确后置状态。
  产品会自动打开的面板或菜单先观察当前状态，再决定是否点击，避免把已打开状态反向关闭；
  这只适用于无副作用的 UI 开关，不能据此重放批准或提交。
- `sendTextInputAction` 只证明框架 `performAction` 通道，不证明物理回车或 IME。需要覆盖
  原生输入时先用 `setTextEntryEmulation(enabled: false)` 恢复平台文本输入，再通过本次
  GUI 专属显示器的原生键盘通道验证。Linux 可在私有 D-Bus、Xvfb 与独立 XDG 目录中使用
  系统 IBus 和输入法引擎；它们的 config owner、引擎与凭据服务也须由本次进程树持有并回收。
  保留组词预览、确认后文本与未提交状态的实际证据；输入法的 Return 可能确认原始拼音，
  不应把「Return 必须输出汉字」当成所有输入法的通用判据。

## 跨重启交互与 Driver 判定

- `cargo xtask manual-gui --scenario plan-recovery` 使用同一隔离 home 的多个原生 GUI 生命周期，
  覆盖待确认计划重开后的批准、修改和已回答计划不再弹出；Linux 无显示环境时配合 Xvfb。
- 起始页的 Thread 在提交 prompt 后才创建，不能先等待 Thread ID 再提交。Turn 已 completed
  也可能仍在 flushing；成功等待须包含持久化就绪，不能把 completed 当作等待失败条件。
- 点击命令超时不证明动作未发生。对已有明确前置状态和可验证后置状态的动作，可在只读重连
  后有界确认结果并记录证据；不得重放批准、提交等副作用，也不得吞掉未达成后置状态的错误。
- 跨进程阶段使用独立不可覆盖的阶段事实或显式握手，不依赖 latest-stage 的短暂值。用于
  证明无额外请求的观测文件必须传播写失败，不能用陈旧计数制造静默窗口通过。
- 多 Turn 旅程按本次 canonical callId/itemId 绑定工具与 UI 断言；同名工具可以多次出现，
  不能用全历史第一个或最后一个同名条目替代精确身份。实时截图前后也须核对活动身份与展开态，
  不能把旧活动的展开结果算到新活动。
- 就绪返回中的目标状态是返回时的一致快照；慢速展开或截图之后查询到的当前终态，不能反推
  等待没有提前返回。按精确 taskId 核对返回快照中的已完成来源与仍运行目标；核心 future 的
  时序由受控公开 API 测试证明。确需观察短暂实时窗口时，用有所有权、会 join 的只读观察与
  UI 操作并行，不要求可能合并更新的 GUI topic 暴露每一个中间状态。

## 原生可访问性补验

- 先确认构建模式。profile/AOT 会裁去 Flutter 的诊断属性，不能依靠 render tree 或
  `getWidgetDiagnostics` 必然读到 `textScaler`、减少动画等值；需要只读 VM evaluate 时使用
  独立 debug 原生窗口，沿用完整保留的合成环境，不修改生产入口或 SDK。
- Linux 先核对当前 Flutter engine 的设置来源；写 GTK/GSettings 不自动证明 Flutter 收到了
  `disableAnimations`。需要 Portal 时复用系统官方 backend，在启动私有 D-Bus **之前**设置
  独立 XDG/Portal 环境，按已安装版本的正式选择机制启用 backend，再用 Settings.Read 核实。
  不自造 Portal 服务、不修改用户会话偏好。
- 临时目录的所有者必须覆盖整个私有 D-Bus 生命周期：先停止并等待自有服务，再退出 bus，
  最后确认自有挂载已释放并清理目录，避免自动激活的文档/VFS 服务仍持有目录。进程核对使用
  本次 PID 及启动身份，不按名称全局清理。
- 活动中的动画观察须先确认目标仍在等待；Thinking、动画结束后的终态或系统偏好配置成功，
  都不能替代真实等待指示器的减少动画证据。结合原生偏好、实际布局/帧条件及截图判定。

## 富文本选择与复制回归

- 排版截图正确不代表复制正确。覆盖中文与行内代码、连续代码片段、长路径、标题后有/无空行，
  在正常/窄窗口及不同文字缩放下执行真实选择与复制，逐字核对剪贴板中的字符、空白和顺序。
  代码块若使用独立 `SelectableText`，需单独验证，不能把外层全选当作代码块复制证据。
- 优先用 Driver 完成交互；Driver 无法读取剪贴板或诊断选择几何时，可在本次隔离 debug GUI
  的 VM Service 中使用一次性探针调用现有选择/复制操作，再读 `Clipboard.getData`。不得直接
  写入期望文本伪造成功，不修改生产 Driver 或 SDK。hot reload 后先等待一帧稳定再访问布局。
- `WidgetSpan` 可切分选择片段；占位字符未进入剪贴板，并不证明片段顺序正确。Flutter 的
  几何排序读取文本选择盒，不等于 `RenderParagraph.size`；单纯拉宽容器不能证明修复有效。
  如需诊断，读取当前 SDK 实现，再在真实 RenderParagraph 上按片段范围调用
  `getBoxesForSelection`，使用与 SDK 一致的 `BoxHeightStyle` 并转换到同一全局坐标。
  前导换行的零宽选择盒也可能扩大片段包围框，应一并记录，避免仅凭文字墨迹或截图推断。
- VM 探针、原始剪贴板和几何数据仅保存在忽略的证据目录；不固化 VM URL、PID、临时路径或
  调试私有 API 为产品接口。复制回归以实际结果为准，静态推演与格式/分析通过不能替代。

## 结束、回收与判定

- 在 harness ready 后，通过所属 task 的 `write_stdin` 发送实际发生的动作代码（如
  `open-settings`、`select-model`），这些代码只是记录，不会替你执行 UI 操作。
- 完成后发送 `done\n`。harness 调用 `test_driver/manual_capture.dart` 保存最终截图和摘要，
  请求应用 shutdown；必须等待原任务终态，核对 `capture-stage.txt` 的 `shutdown_completed`。
- 失败或取消也要回收：优先向本次伪终端发送 Ctrl-C，让 harness 清理；必要时使用任务取消
  并等待终态。核对本次所属 Flutter、DTD、GUI、fixture、Driver 与 Xvfb 进程是否退出。
  不使用无差别 `pkill`，不杀用户已有桌面或无关任务；仍有残留则明确报告并按所有权处理。
- 结合截图、快照、日志和进程状态给结论。`verdict.json` 默认为 `pending`；命令 exit 0、
  日志无错误或截图成功均不自动构成完整验收。未执行 fixture 主流程时可能提示
  `Fixture main step was not exercised`，可报告定向 UI 结果，但不能宣称端到端流程通过。
- 汇报实际平台/显示方式、覆盖项、未覆盖项、证据目录、命令退出状态和回收结果。
  遇阻记录真实命令及原始错误，区分缺 TTY、显示服务、原生构建依赖、Driver 连接/定位问题。
  缺工具时报告具体缺项，不擅自安装系统包，也不写死机器专用 include/library 路径。
