# 统计管线显式基准

本入口只由非默认 `benchmarks` feature 编译，不进入普通测试或默认 Clippy/CI。
它调用实际 CallsStore、JSONL、费用查询、可靠 Thread writer、live projection 和 observer；
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

## 稳定负载与边界

| case | 输入与测量边界 |
| --- | --- |
| `history/recent_{0,100,3000}/old_{0,6000}` | 相同最近 3000 个成功样本；多出的 6000 条旧成功日志索引不改变最近结果。真实 `recent_performance_samples` 调用计时，之后校验返回条数和全部字段的 SHA-256。 |
| `billing/single`、`billing/batch_64` | 每次使用空的新 calls store，计时从受理前到真实 JSONL 与 SQL commit 后的 durable ticket；每条记录另存其受理至 durable 屏障返回的真实耗时。64 条是一组业务输入，不强制改变 writer 原有按条数/字节聚批的调度。 |
| `billing/segment_rotation_64` | setup 先写 52 条各含 300 KiB 合法字段的记录，测量再写 64 条并验证实际 segment open。每条低于记录上限；基准不覆盖生产的批次、16 MiB segment 或同步设置，实际 flush/sync 次数由钩子记录。 |
| `effects/no_billing_change/active_{1,32}/working_1` | 每次连续提交 32 个无计费变化 effect；真实 admit、live projection、history/checkpoint commit、calls durable 与所有活跃 observer 的真实单 Thread 水位查询均在各 effect 屏障内。其余 Thread 存活但不产生工作，实际 15 秒 observer tick 仍运行。 |
| `costs/roots_{1,32,256}/purposes_4/currencies_3` | 每个 root 4 个 Thread、4 purpose、3 currency；真实 summary 写入用于 setup，测量真实费用聚合查询，按精确二进制小数验证全部币种与 purpose 的累计值和身份摘要。 |
| `parallel/recent_3000/batch_64` | 4 次真实 3000 样本读取与连续 8 组 64 条真实写入并行。先观察首个真实查询已进入，再启动写任务；不注入人工锁或 sleep，也不要求重构后的查询仍持有旧日志锁。写入的是更旧样本，因此每次读取仍验证同一最近集合。保存写吞吐、逐读/逐记录/逐批耗时、队列高水位和真实读写锁等待。 |
| `publication/materialize_3000/roots_32` | 实际统计 owner 对 3000 个样本、32 个 root 费用执行显式物化，计时包含读取、采用及事件发送；计时外核验已发布历史、样本和费用条数。此只读负载不推进 owner revision，缓存持久化分支可能跳过，不宣称覆盖持久化成功；它也不测 GUI 消费延迟或“后到 Summary”的故障场景。 |

所有数据库首开、迁移、目录创建、seed、fixture 数据构造、返回结果摘要计算和 teardown
均不进入普通操作计时。Billing/并行场景每次重建以固定历史规模；只读场景复用不变数据；
无计费 effect 场景复用可靠 writer 的最新 checkpoint/watermark，sequence 继续单调前进。
并行窗口总计时包含实际任务编排与结果处理；其中逐读和逐写样本另有独立操作边界。
全局“物化刷新”计数钩子也只在 feature 下存在；存储/observer cases 不装配产品 owner，
该计数可为零。独立的 publication case 覆盖实际 owner 物化发布，不把它外推为 GUI 消费或后到 Summary 的正确性证明。
