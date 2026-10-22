# T1.A 初始连接失败定向取证合同 v2

v2 按用户最新指令恢复执行：SSH 失败等待10秒再重试连接；恢复后核原任务／进程，不能因
断连重复启动。v1 已中断的第1轮与其已审报告原样保留。本文只调整运输恢复与取证编排，
不修改产品重试、输入、预算、成功判据或旧证据。

## 1. 目的与完成口径

这是已批准计划内的有界原生诊断任务，不是重新请求整套 displacement 验收。
原 a1 已观察到 `connection:failed / generation:0 / ready:false / itemCount:0 / scroll:null`，
但没有保存原因。原件不能补造，新一轮绿色不能证明旧 a1 已修复或已归因。

新四字段只读诊断已完成独立局部审查；本任务用该实际生产构建取得**新失败的安全原因元数据**，
或如实记录在有界样本中未复现。发现相同表象也只说明本轮可复现类别，不自动等同旧 a1 原因。
不猜 Busy、Conflict、环境或时序，不修改业务来人为制造错误或绿色。

## 2. 已验证基线与前置

- HEAD `b98432fa809446d57be87a8b96379455ec8a4828`，分支
  `pure-session-thread-65e3ee582f0d4-82`，贡献基线 `f6cb327ceb3416dca181790575711588571d3ec7`。
- 四字段合同 `t1a-connection-diagnostics-contract.md` v1 SHA-256
  `9e03436698e4d4bf8e4c0901400b53b0cdbc53080d6683015071e9769324836a`；
  fresh reviewer `thread-65e5613c07449-345` 的本轮 completed / commitSequence117 明确批准五文件。
- root 随后完整 `verify-client` / `verify-gui` / `git diff --check` 均 exit0：SDK204、APP214，
  AST298、analyze零问题、format零变化、canonical生成稳定。
- 诊断门禁对应输入身份保存在 root 的已核 artifacts 清单，SHA-256
  `4e49b01d64b012a0b5d4d79fc32230e783b0420522e857e57468c006c076a150`。
  该清单验证 SDK20、APP21、控制73、生成88、相邻诊断6、新诊断5及删除3项；
  除明确新诊断与先行设计外没有意外输入变更。
- 本轮 root 重新核对上述清单，仅明确容许新增的 T1.B 来源设计文档变化：
  `design/18-studio-state.md` 为 `951d4bca2d8ed77014d9531bcfa72a2556bfc55cefe461fe5cc0dde30f3e70e3`；
  五文件诊断及其余生产／生成输入必须保持原已审身份，不为文档变更重复全量门禁。
- root 第六次官方 history + displacement 的完整通过与看图证据、raw run4 可观测链及
  已获局部批准的正式报告继续有效，本任务不重复其矩阵、不修改其原件。

## 3. 执行者、写范围与资源所有权

续跑原 QA executor `thread-65e5534d4c813-2bc`，不改变其已有报告与四份冻结脚本。
v2 唯一正式写文件：`reports/frontend-refactor/t1a-connection-investigation-v2.md`。
v1 的 `t1a-connection-investigation.md`（SHA-256
`f75ebc7724f975edf0e269598015749055fb25484fde92a5a242dcaf47fac04b`）及 raw 已审报告不修改。
其余 reports、design、生产、测试、生成、manifest、CI、配置与 Git 均禁写。
一次性编排或提取脚本只在执行者自己的最新 session scratch；输出在其 artifacts。
不写 root／邻居 session，不复用已运行的历史输出目录或 xauth，不删除旧失败现场。

QA 独占本 workspace 的 GUI／fixture／native build；root 不并发启动这些进程或全局生成。
其他独立只读探索可以继续。每次先核本 workspace 所属验收进程已退出；不得杀无关进程。
采用官方 harness 管理合成 home／project／fixture，不能修改用户配置或凭据、手工改数据库。

## 4. 固定编排与停止条件

1. 完整阅读本合同、原诊断合同和相关现有脚本，核五文件 hash 与当前输入身份。
2. v2 最多 **3 轮实际进入 app 的产品取证**，使用独立的新环境官方 `timeline-history`（不带
   displacement）。仅构建／SSH中断且可证明未到 app 的尝试另列为运输失败，不当产品样本，
   每次仍保留独立编号和全部原件；连续3次这样的无样本中断后先报告 root 调整编排，不无限
   重启昂贵构建。每轮都是新输出、
   新 xauth、官方 harness 创建的新 home／Thread，而不是在同一个已含20k的 Thread 上重放输入。
   可直接复用自身 `run_timeline_acceptance.py` 的冻结版本；旧文件不改。如需新增证据提取器，
   使用新名称和自身 scratch，不能修改原四脚本或成功断言。
3. 每轮真实命令保持以下形状；路径取自身 session 的真实绝对路径：

   ```bash
   GDK_BACKEND=x11 xvfb-run -a -f <own-absolute-xauth> \
     -e <own-xvfb-log> -s '-screen 0 2560x1600x24' \
     script -q -e -c 'cargo xtask manual-gui --scenario timeline-history \
       --retain-environment --output <own-new-output>' /dev/null
   ```

4. 原有30秒运输心跳允许保留，只维持 stdout 活动，不改变官方90秒条件、50ms读取、fixture、
   旅程动作、成功判据、环境或预算。helper 已安装，不重复安装、不直调 Flutter build/run。
5. **任何产品断言失败立即停止整个 campaign**，保存和检查该轮全部证据后报告 root；不为
   取得绿再开下一轮，不重发写入、不切原始错误码或阈值。尤其捕获到 gen0/failed 时，先交
   元数据。构建失败按真实错误报告，不能统称为运输故障；只有可证的运输中断按第7项恢复。
6. 仅在该轮官方旅程全部通过、中央 shutdown clean、GUI／Driver／fixture／Xvfb 及后代已确认
   回收后，才允许下一轮。三轮均通过则停止并明确“本次有界样本未复现，旧原因仍未知”。
   这三轮仅用于复现概率未知的故障取证，不能用通过票数消除旧失败。
7. SSH 读取或等待失败后，**等待10秒再重试只读连接／状态检查**；仍失败则按同一间隔重试，
   不连续无等待轰击，也不重新启动尚未确认退出的命令。恢复后先核原任务与所属进程／报告：
   原任务仍活着就继续等待；已结束且有产品失败则按第5项停止；可证明只有构建期运输中断、
   未进入 app 且所属进程全部不存在时，允许新label／新home替代该无样本尝试。若 app 已启动
   但失去结果或无法核定是否提交，停止交 root，不在原 Thread 重发写入。无论如何都不把
   取消、截断、权限等待或缺失结果算通过；只报告实际观察到的signal，不猜发送方或因果链。

不得增加自动业务重试、手动点 Retry 掩盖首连接失败、主动 flush、query 轮询业务来源或注入
产品状态。无新 raw 20k 探针任务，不再给旧大历史 Thread 追加输入。

## 5. 元数据、证据和隐私

每轮记录实际命令、输入源身份、输出目录、平台／构建形态、每阶段断言／错误、fixture状态、
真实PID／退出与后代回收、关键原件SHA。失败日志必须保留原错误链，不只记录 exit0。

首条件超时读取 Driver 原有 `last` / `lastWhileBusy` 中：
Thread、generation、ready、connection、mode、itemCount、loadingOlder、preparingLive、
scroll，以及新增的 `connectionErrorType`、`connectionErrorCode`、
`connectionErrorRetryable`、`connectionErrorCorrelationId`。严格区分缺键与合法null，
不能因为没有原因字段而补默认值或继续判断为某类错误。
新字段不输出异常 message、detailsJson、stack、正文或凭据。

如四字段不足以定位具体阶段，保留现有日志与相关身份，明确其分辨能力；不擅自新增生产日志／
字段或开第二种实验。需要进一步诊断交 root 冻结。
正式报告只保必要身份、计数、typed错误、hash和相对证据标签，不提交原始日志、VM URL、
敏感快照、截图、会话绝对路径或完整模型正文。允许本轮在自身私有 artifacts 保留原件。

## 6. 验收与交付

此任务可在官方旅程失败时完整交付**诊断证据**，不伪称功能通过；运行失败与取证交付是两件事。
报告必须逐轮列全部结果，不能只选最后一次绿色。失败说明实际观察的元数据及未知项；通过
说明只覆盖本次样本，不能对旧 a1 归因。根因判断、必要生产修复、阶段验收和 Git 均由 root。

正式报告内容／引用／脱敏／空白检查即可，不跑全仓自动门禁；新增scratch提取器按实际语言
做局部语法检查。完成时给正式报告SHA、脚本／原件身份、实际task／日志引用、所有资源已退出
或具体未结束资源，冻结报告供新fresh reviewer。不得改旧raw已审报告来并入本任务结果。
