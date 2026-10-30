# 统计管线显式基准

本入口只由非默认 `benchmarks` feature 编译，不进入普通测试或默认 Clippy/CI。
它调用实际 CallsStore、JSONL、费用查询、可靠 Thread writer 和 live projection；
没有替代保存器、复制的归约器或降低同步保证的设置。

## 显式输入与运行

运行前由调用者创建两个目录，并指定一个 JSON 元数据文件：

```sh
export PL_STATISTICS_BENCH_SCRATCH_ROOT='<本次执行会话的 scratch>'
export PL_STATISTICS_BENCH_ARTIFACTS_DIR='<本次执行会话的 artifacts>'
export PL_STATISTICS_BENCH_METADATA_JSON='<本轮元数据 JSON 文件>'
```

三个变量均为必填项；缺失、空值或目录不存在会明确失败，不回退到 home 或 `/tmp`。
`cargo bench` 以 crate 目录启动基准程序，环境变量应传调用者已核实的绝对路径，不能原样使用仓库根相对路径。
元数据 JSON 示例（替换所有说明值）：

```json
{
  "runLabel": "before-round-1",
  "sourceRevision": "<基线提交>",
  "sourceTreeIdentity": "<包含未提交 benchmark/钩子的源码内容身份>",
  "rustc": "<rustc -Vv 的完整结果>",
  "machine": "<CPU、内存、机器身份与负载约束>",
  "filesystem": "<磁盘、文件系统、挂载及同步条件>",
  "optimizationProfile": "<实际 bench profile、RUSTFLAGS 与编译目标>"
}
```

以上环境事实由调用者记录；入口另存实际 `Cargo.lock` SHA-256、OS、架构、可用并行度
及固定运行参数，不调用 Git 或工具链探测命令。不要把说明占位值作为正式采样证据。

```sh
cargo bench --locked -p pl-studio-runtime --features benchmarks --bench statistics_pipeline -- --save-baseline before
cargo bench --locked -p pl-studio-runtime --features benchmarks --bench statistics_pipeline -- --baseline before
```

在同一机器、文件系统、同步设置、工具链和优化配置下，分别独立执行至少三轮，
为每轮更新元数据。使用不同 baseline 名称（例如 `before-r1/r2/r3`）保留各轮 Criterion
结果，再用对应名称比较；若重复使用 `before`，Criterion 自己可能替换同名基线。
标准结果仍由 Criterion 在其实际输出入口管理；调用者应将实际输出目录与 baseline 名称记录到运行证据，按轮次唯一命名，不覆盖原基线。该目录属于工程工具的标准产物入口，与显式 artifacts 中的额外原始指标相互补充；不更改构建工作目录或猜测 `CRITERION_HOME`。
使用隔离的历史 checkout 时，为不同源码设置独立 `CARGO_TARGET_DIR`，避免跨工作树复用
Cargo 新鲜度缓存而链接到另一版本的依赖。优化 profile、编译参数和负载仍须相同。
若 Criterion 入口因构建目录隔离而不同，只复制对应的已完成 baseline 子目录到完成版的
实际 Criterion 入口，逐文件校验 SHA-256 并记录来源；不修改名称、样本或估计值，不移动、
覆盖原始 baseline。构建目录路径差异须在环境记录中明确，不把复制当作新的前测。
支持 Criterion 的名称过滤；`--test` 和 profile 模式不接受为实际采样入口。

每个执行有唯一 run 目录，每个 fixture 有唯一 case 目录。
正常结束先等待 worker 停止、关闭数据库，再删除自身拥有的目录。
失败时保留现场并输出位置，不删除未知路径。
额外产物为 artifacts 下以 `create_new` 身份创建的唯一 `statistics-pipeline-*.jsonl`，
不覆盖旧结果；失败文件不带成功终态，不可当作完成证据。

## 固定配置

- 种子 `209`；fixture 时间固定在一个未来 UTC 日，以免日期和 retention 改变工作量。
- Tokio worker 4，blocking worker 上限 4。
- Criterion warmup 3 秒、measurement 5 秒、sample size 20、bootstrap resamples 100000；
  noise threshold 0.05、confidence level 0.95。固定统计配置在 CLI 解析后应用。
- 每个实际执行的 case 在 Criterion 之后再取 32 次逐操作分布。
  此分布单独标为 `postWarmup`；p50/p95 使用 nearest-rank，
  不来自 Criterion 的批平均，也不混入其无法区分阶段的校准/预热调用。
- 每个 `criterionInvocation` 保存实际操作计数与计时合计，阶段明确标为
  `criterionUnspecified`。统计置信区间和 Criterion 吞吐/耗时结果以 Criterion 自己的结果为准。
  吞吐单位分别为 query 次数、持久化 Billing 条数或可靠 effect 数；并行场景是整个并行窗口内的
  持久化写入条数。完整 Criterion 名称以前缀 `statistics_pipeline/` 开头。
- SQL/IO 计数表示到达实际操作点的尝试；`calls_batch_commit`、摘要 written/skipped
  表示对应成功完成点。高水位为 setup 排空后、本 store/case 生命周期的绝对值，
  其余计数为每次测量的差值。观察状态不跨 store 或执行共享。

## 单问题有界短诊断

`PL_STATISTICS_BENCH_PROFILE` 未设置或为 `standard` 时，继续使用上面的固定标准参数。
显式设置为 `diagnostic` 时，使用 10 个 Criterion 样本、250 ms 预热目标、
500 ms 测量目标及每 case 4 次逐操作分布；bootstrap、95% CI、5% 噪声阈值、
种子、数据规模、同步设置与正确性校验不变。未知值和非 UTF-8 值明确失败，
不静默回退。实际 profile 与全部参数写入原始 run header。

```sh
PL_STATISTICS_BENCH_PROFILE=diagnostic cargo bench --locked -p pl-studio-runtime --features benchmarks --bench statistics_pipeline -- --save-baseline short-before '^statistics_pipeline/effects/reliable_history_no_call_material/active_32/working_1$'
```

先为一个具体问题固定对照身份、相同 selector、运行顺序、预算及停止条件，再采样。
调用者的进程生命周期管理器须保证该问题定位与修后实验累计至多 60 秒，
到期终止并回收原进程树，不重新采样挑选好结果。夹具准备、校验与收尾虽然不进入
操作计时，仍计入实验墙钟；构建和负载预检单列。Criterion 的目标时间并非墙钟上限，
慢场景可能无法在预算内完成，不能将不完整样本报告为通过。

短诊断仅证明它实际覆盖的问题；子链使用独立名称，不冒充原固定场景。
四次操作分布不足以证明稳定尾延迟。两侧须采用同一 profile；不能与旧标准轮混合
计算百分比，亦不以分析/SQL 次数下降替代实测改善。标准入口和默认 CI 不受此影响。

## 存储字节与队列年龄

Linux 的每条 `operationDistribution.measurement.storageIo` 保存本进程
`/proc/self/io` 的 `readBytes`、`writeBytes`、`cancelledWriteBytes` 差值和独立的
`elapsedNanos`。存储层吞吐按 `bytes / (elapsedNanos / 1e9) / 2^20` 得到 MiB/s；
不要以 `rchar/wchar`、JSONL 长度或 Billing records/s 代替真实存储层字节。
此独立区间包含操作及结果校验，不含夹具准备、关闭和报告写入，不改变 Criterion
原操作计时边界。内核取消写回单列，缓存命中的零读取如实保留；它不代表全机设备或
介质吞吐。非 Linux 保存 `null`，Linux 读取失败则明确失败，不回退成零。

`queue_dequeued_mutations`、`queue_age_at_dequeue_ns` 和 `queueAgeMaxNanos`
来自实际 writer 取批：分别为条目数、受理至取批年龄总和和本操作最大年龄。
以总和除条目数可报告平均队列年龄；条目数为零时不可用，不补零平均值。
年龄不含本次取批后的文件/SQL 处理；失败重试仍保留原受理时刻，可能包含之前尝试。
补充历史观测必须独立命名并记录仅观测的源码差异，不能倒填或覆盖原前测。

## 稳定负载与边界

| case | 输入与测量边界 |
| --- | --- |
| `history/recent_{0,100,3000}/old_{0,6000}` | 相同最近 3000 个成功样本；多出的 6000 条旧成功日志索引不改变最近结果。真实 `recent_performance_samples` 调用计时，之后校验返回条数和全部字段的 SHA-256。 |
| `billing/single`、`billing/batch_64` | 每次使用空的新 calls store，计时从受理前到真实 JSONL 与 SQL commit 后的 processed ticket，并校验没有拒绝/gap/error；不能单凭处理票据宣称物化成功。每条记录另存其受理至该屏障返回的真实耗时。64 条是一组业务输入，不强制改变 writer 原有按条数/字节聚批的调度。 |
| `billing/segment_rotation_64` | setup 先写 52 条各含 300 KiB 合法字段的记录，测量再写 64 条并验证实际 segment open。每条低于记录上限；基准不覆盖生产的批次、16 MiB segment 或同步设置，实际 flush/sync 次数由钩子记录。 |
| `effects/reliable_history_no_call_material/active_{1,32}/working_1` | 每次连续提交 32 个无调用材料 effect；各操作计时包含真实 admit、live projection、history/checkpoint commit 及可靠 flush ACK。确认 calls 接纳/处理 ticket 均为零，空闲 Thread 的可靠水位不变；操作组后回读 history/checkpoint/可靠累计。旧 `effects/no_billing_change` 额外等待空 calls 水位和观察者，新名称不与其冒充完全等价。架构对照必须明确旧侧冗余义务、相同可靠事实校验及实际计数。 |
| `costs/roots_{1,32,256}/purposes_4/currencies_3` | 每个 root 4 个 Thread、4 purpose、3 currency；真实 summary 写入用于 setup，测量真实费用聚合查询，按精确二进制小数验证全部币种与 purpose 的累计值和身份摘要。 |
| `parallel/recent_3000/batch_64` | 4 次真实 3000 样本读取与连续 8 组 64 条真实写入并行。先观察首个真实查询已进入，再启动写任务；不注入人工锁或 sleep，也不要求重构后的查询仍持有旧日志锁。写入的是更旧样本，因此每次读取仍验证同一最近集合。保存写吞吐、逐读/逐记录/逐批耗时、队列高水位和真实读写锁等待。 |
| `publication/materialize_3000/roots_32` | 实际统计 owner 对 3000 个样本、32 个 root 费用执行显式物化，计时包含读取、采用及事件发送；计时外核验已发布历史、样本和费用条数。此只读负载不推进 owner revision，缓存持久化分支可能跳过，不宣称覆盖持久化成功；它也不测 GUI 消费延迟或“后到 Summary”的故障场景。 |

所有数据库首开、迁移、目录创建、seed、fixture 数据构造、返回结果摘要计算和 teardown
均不进入普通操作计时。Billing/并行场景每次重建以固定历史规模；只读场景复用不变数据；
无计费 effect 场景复用可靠 writer 的最新 checkpoint/watermark，sequence 继续单调前进。
并行窗口总计时包含实际任务编排与结果处理；其中逐读和逐写样本另有独立操作边界。
全局“物化刷新”计数钩子也只在 feature 下存在；存储 cases 不装配产品 owner，
该计数可为零。独立的 publication case 覆盖实际 owner 物化发布，不把它外推为 GUI 消费或后到 Summary 的正确性证明。
