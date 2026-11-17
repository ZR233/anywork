# 本地 Harbor 评测

本包使用生产 `anywk exec`，由 Harbor 安装式智能体适配器负责私有目录、取消、原生产物校验、ATIF 与统计转换。Harbor 固定在 `06d0e86a8cfbac213548e0caec533afc5d81ff31`（0.25.0），依赖由 `uv.lock` 冻结。只消费原生导出版本 3，不实现模型循环或第二套账本。

**Harbor 安装在本地 Linux 宿主，不加入项目 Docker 构建镜像，也不在持续集成运行 Harbor。** 本地任务仍使用 Harbor 官方 Docker 环境。需要 Python 3.12 以上、uv、可运行 Linux amd64 容器的 Docker；下载正式 Debian 包还需 `dpkg-deb`。真实模型调用仅发生于明确执行 `run` 后。开发回归和完整基准需要运行者自己的原生账号配置及环境变量凭据；本仓库不提供或自动读取个人凭据。

## 二进制安装

正式原生桌面发布构建同时生成 `bin/anywk`、`bin/build-info.json`（Windows 使用 `anywk.exe`）。不增加独立发布资产，不从 `latest` 选择二进制。

| 平台 | 安装后位置与终端入口 |
| --- | --- |
| Linux Debian 包 | `/opt/anywork/bin/anywk`；包管理器维护 `/usr/bin/anywk` 链接，安装后直接调用 |
| Windows 用户安装器 | `%LOCALAPPDATA%\Programs\anywork\bin\anywk.exe`；默认勾选添加用户 PATH，安装后重新打开终端 |
| macOS 应用压缩包 | `anywork.app/Contents/Resources/bin/anywk`；没有安装器，显式将该目录加入用户 shell 的 PATH |

Windows 使用 Inno Setup 官方注册表接口更新 `HKCU\Environment\Path`，保留其他条目，按完整目录忽略大小写、引号及末尾反斜杠避免重复，并用 `ChangesEnvironment=yes` 通知环境刷新。仅记录本安装器实际添加的目录；卸载读取当时的 PATH，只删除该归属条目，原本已有的目录不由安装器认领。升级保留安装任务选择。便携压缩包不改 PATH。

例如 macOS 安装到 `/Applications` 后，可在用户的 `~/.zprofile` 中添加：

```sh
export PATH="$PATH:/Applications/anywork.app/Contents/Resources/bin"
```

若安装位置不同，使用实际绝对路径。不要修改 `HOME`、复制整份桌面用户数据或启动 GUI 来运行 CLI。正式 Linux 包包含标准证书依赖；任务容器须提供兼容 glibc、系统证书库、`/proc` 与 `setsid --wait` 等基础命令。首期 Harbor 仅支持 Linux x86_64 glibc，不承诺 musl。

## 无付费调用的手动验收

以下命令从仓库根目录执行；二进制必须针对任务容器的 glibc 构建。先在既有 Ubuntu 22.04 项目构建环境编译 CLI 和共享供应商夹具，不在该镜像安装 Harbor：

```sh
bash docker/linux/scripts/run.sh "$LINUX_BUILD_IMAGE" \
  env CARGO_TARGET_DIR=target/harbor-linux \
  cargo build --release --locked --target x86_64-unknown-linux-gnu \
  -p pl-studio-cli -p pl-provider-fixture --bin anywk --bin pl-provider-fixture
uv sync --project integrations/harbor --locked
uv run --project integrations/harbor pytest integrations/harbor/tests
uv run --project integrations/harbor ruff check integrations/harbor
uv run --project integrations/harbor python -m anywork_harbor.smoke \
  --binary target/harbor-linux/x86_64-unknown-linux-gnu/release/anywk \
  --fixture target/harbor-linux/x86_64-unknown-linux-gnu/release/pl-provider-fixture \
  --output target/harbor/manual-file
uv run --project integrations/harbor python -m anywork_harbor.smoke --case cancel \
  --binary target/harbor-linux/x86_64-unknown-linux-gnu/release/anywk \
  --fixture target/harbor-linux/x86_64-unknown-linux-gnu/release/pl-provider-fixture \
  --output target/harbor/manual-cancel
```

每次使用新输出目录。正常场景要求真实文件修改、验证器奖励 1、清洁关闭、完整原生轨迹及官方 ATIF 验证；取消场景要求保留 Harbor 超时异常、控制命令成功、无已知残留进程，且验证器开始后文件大小不再变化。取消不是正常完成。共享夹具只监听任务容器回环地址，任何模型请求都由严格脚本核对；合成任务的 Dockerfile 不包含 Harbor、Rust 或 Flutter。

## 冻结计划、执行与报告

先以无付费的 smoke 运行完整命令链：

```sh
uv run --project integrations/harbor anywk-bench prepare \
  --binary target/harbor-linux/x86_64-unknown-linux-gnu/release/anywk \
  --fixture-binary target/harbor-linux/x86_64-unknown-linux-gnu/release/pl-provider-fixture \
  --base-config integrations/harbor/profiles/fixture.toml \
  --suite smoke --task-manifest integrations/harbor/manifests/smoke.json \
  --account fixture --model vendor/harbor-fixture --skip-model-parsing \
  --cost-stop-usd 1 --output target/harbor/plan
uv run --project integrations/harbor anywk-bench run \
  --plan target/harbor/plan/plan.json --output target/harbor/run --cost-stop-usd 1
uv run --project integrations/harbor anywk-bench-summary \
  --input target/harbor/run --output target/harbor/report
```

`prepare` 不调用任务模型，但会解析官方数据集、下载固定发布包或准备 Docker 镜像。可用 `--release <固定 x.y.z>` 替代 `--binary`：仅下载该版本的 `anywork-<版本>-linux-x86_64.deb`，核对 sidecar，提取 `bin/anywk` 及构建身份。旧发布包没有 CLI 时直接失败。也可提供本地 `--build-info`；没有声明时明确记录未知提交和环境，不能冒充正式发布比较。

Docker 镜像通过 Docker 官方解析器固定到仓库摘要；只改写冻结的任务副本。含未解析镜像构建参数或缺少单 Dockerfile 的任务会明确拒绝，需运行者先提供显式镜像输入，不能静默跟随浮动标签。

计划保存任务配置/内容摘要、二进制版本/提交/摘要、Harbor 提交/锁文件摘要、适配器源码摘要、原生配置与能力/候选目录/价格摘要、技能副本、种子身份、实验组/重复/顺序、资源/超时、奖励键/阈值及费用停止阈值。执行前重核冻结输入；修改输入须生成新计划。`--skip-model-parsing` 使带斜杠的 Anywork 模型标识原样传递；不传时按 Harbor 官方 provider/model 解析。

真实开发回归示例（配置路径和模型替换为已准备的数据，不使用 fixture 配置）：

```sh
uv run --project integrations/harbor anywk-bench prepare \
  --release 6.42.0 --base-config /evaluation/base-config.toml \
  --suite dev --task-manifest integrations/harbor/manifests/dev.json \
  --account benchmark --model openai/model-id --baseline-version <固定版本> \
  --variants A B C --env-name OPENAI_API_KEY \
  --cost-stop-usd 20 --output /evaluation/dev-plan
uv run --project integrations/harbor anywk-bench run \
  --plan /evaluation/dev-plan/plan.json --output /evaluation/dev-run \
  --cost-stop-usd 20 --wall-budget-sec 18000
```

版本号必须选实际包含 CLI 的已发布版本，上例的版本号不是发布承诺。凭据变量必须由所选原生账号的 `bearer_token_env` 声明，只保存变量名。A 组外部执行框架还需其官方支持的凭据变量；模型必须确实相同。基线费用沿用其原始记录，不按当前目录重新计价，比较前须核对价格口径。

原生输入要求 `schema_version=33`、API 账号、`catalog.source="explicit"` 及完整模型能力/连接/上下文/价格；拒绝内联凭据和凭据头。渲染器关闭 MCP、网络搜索和自动技能学习。B 将两种 mode 和已有角色路由统一到同一账号/模型/effort，并检查实际全树账单；C/D 使用相同自动委派配置和候选池。关闭隐式用户技能，显式外部技能用重复 `--skill-dir` 冻结上传；不接受未冻结的 `skills.external_dirs`。

`dev` 固定取 `terminal-bench/terminal-bench@4.0.0` 按任务标识排序的前十项，默认每任务三次、智能体超时 1800 秒，仅供开发观察。完整基准使用 `--suite full --task-manifest integrations/harbor/manifests/full.json`，默认每任务五次，保留官方任务资源和超时；不得将修改过的任务或开发子集称为官方完整成绩。完整基准需自行提供能长时运行的 Linux Docker 宿主，不安排 GitHub 工作流、定时任务或自动付费执行。

四组为 A 外部成熟执行框架固定模型、B Anywork 全角色固定模型、C 自动选模冷启动、D 同配置与同一开发历史种子。D 必须提供具有真实提交的二进制构建声明及 `--history-seed`。需要相同比较约束时，不单独改变某组模型、effort、工具、技能或任务资源。

每次只运行一个单 trial Harbor job：并发 1、独立 attempt 1、错误重试 0。执行前原子记录 started，结束写 terminal。重复执行同一 `run` 命令只继续未调度 slot，不覆盖已完成样本；started 无可信终态改记 interrupted/未知成本，停止自动投放，需人工核对旧任务。当前不提供自动补跑，补跑须用新计划保留原结果。费用阈值是完成后停止下一次投放的阈值，最后一次可能超额，不是模型账单硬上限。未知费用、清理失败或成功产物验证失败会停止后续投放。墙钟预算包含环境构建、安装、智能体、验证器与清理余量。

## 冻结历史

只从专用开发/合成任务产生的、已关闭的同版本原生 home 冻结，不使用任意日常用户目录：

```sh
uv run --project integrations/harbor anywk-freeze-history-seed \
  --studio-home /evaluation/development-home --artifacts /evaluation/development-export \
  --development-manifest /evaluation/development-tasks.json \
  --output /evaluation/history-seed
```

源运行须有 Clean/Drained 最终结果、可核对的配置摘要与构建提交。冻结期间持续持有原生排他锁，只复制 `data/`，不复制配置、环境、凭据或业务工作区。在独立副本使用 SQLite 官方 backup API 合并写前日志，源目录保持不变，再以不可变只读模式检查当前布局/数据库版本、SQLite 一致性/外键、归属清单、活动会话、机器人、未完成关闭/工作树租约及迁移恢复。源开发清单使用 `{"suite":"development","tasks":[{"id":"专用开发任务"}]}`；种子开发任务与待评测任务不得重叠。

每 trial 启动前核对种子版本、候选账号/模型目录与文件摘要，再独立复制到新的私有 home，单独上传本次原生配置。种子不回写，冷组不上传历史。旧业务路径缺失保持原生局部诊断，不重写历史路径。新运行只导出本次成员，旧历史不计本次费用。

## 结果口径与错误边界

`summary.json`、`trials.csv`、`report.md` 保留全部已调度尝试及复现计划。有效 reward 平均分只以可信有效样本为分母；成功交付率以全部已调度尝试为分母。验证器奖励决定任务通过，不以 CLI 退出 0 替代。未知用量和费用保持 null，已知小计只作下界；费用包含失败与取消，存在未知值时总费用和成功一次的完整费用保持未知，无成功样本时费用不适用。

有多个奖励键时在任务清单声明 `rewardKeys` 并显式传 `--reward-key`；未声明而运行时才发现多个键时，该样本记为歧义无效，不能静默挑选。

报告逐次保留完整性、异常、清理、原生 byModel、按 purpose/auxiliary 分组的调用及原始计量、缓存/推理词元、各阶段时间。输入包含缓存、输出可能包含推理词元，不能把这些子项再次相加。成功有效样本延迟使用线性插值 P50/P95，报告 n，超时单列截尾。先按 task 汇总重复，再以固定 seed=20261113 做 10,000 次 task 级配对 bootstrap；披露缺失配对，少于十个独立任务不作稳定性结论。A/B 和 B/C/D 分开解释。

适配器在 `run()` 返回前验证版本、身份、真实退出码、关闭、事件序号/哈希、成员 History 水位、完成事件/typed Head 身份、NDJSON 内容 manifest、每个原件与正文分块的路径/长度/摘要、账单去重与 ATIF。退出码和原生 `TurnFailure` 决定错误分类，禁用基类文本匹配。成功轨迹但缺少 token/价格不是基础设施错误。post-run 只填上下文，晚发现的损坏写入诊断并在报告标无效，不伪称 Harbor 已追溯改判。外层取消以随机运行标识、PID/starttime 与 session 归属回收，控制命令最多等待五秒，不按进程名清理。边界失败保留原始证据。

本地合成验收只证明接入与统计契约，不证明真实模型质量提升，也不证明 Windows/macOS 原生执行或完整官方基准成绩。
