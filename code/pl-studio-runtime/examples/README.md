# 真实任务人工观察

更新器可通过 `updater_observe` 显式观察，不启动安装器：`state ARTIFACT_DIR` 在隔离 home
将设置文件设为只读并取消一次更新检查，保存 canonical 状态和文件未改写证据；
`download ARTIFACT_DIR [CANCEL_AFTER_BYTES]` 下载真实稳定 Release，可在指定进度取消。
下载前由父进程将 `LOCALAPPDATA` 设为证据目录旁的独立缓存目录；再次启动进程并使用同一
缓存，可观察恢复起点与完成校验。各次运行使用独立证据目录，取消保留非零退出状态和错误报告。
入口为 `cargo run -p pl-studio-runtime --features live-tests --example updater_observe -- ...`。
`report.json` 的 review 默认为 pending，运行完成不替代人工核对进度、文件和结果。

从仓库根目录运行，artifact 目录必须尚不存在：

```bash
cargo run -p pl-studio-runtime --features live-tests --example model_observe -- \
  openai gpt-6-astra /absolute/task.txt /absolute/new-artifacts
```

读取 anywork 用户配置中选定供应商的完整配置与系统凭据，不改写配置或会话库。
任务文件是实际待处理要求，不要求固定回答。可选参数：

- `--image FILE`：图片 bytes。
- `--image-url URL`：远程图片，保存请求期快照。
- `--image-base64 FILE`：保存完整原始 Base64 的文本文件，默认 PNG。
- `--followup TASK_FILE`：在同一模型会话中继续任务，可重复。

`events.jsonl` 保存过程，`response-N.json` 保存响应和服务端用量，
`report.json` 分开记录 execution 与 review。execution 完成不是验收通过；
review 默认 pending，由观察者阅读过程、结果和产物后另行记录结论。
缺少配置、鉴权失败、超时与事件缺口必须保留，不能静默跳过。
不会断言回答文字、工具次数、缓存命中或业务终态。

完整工具/协作任务使用 `collaboration_observe`：
设置 `ANYWORK_OBSERVATION_PROMPT` 为任务文件，
`ANYWORK_WORKFLOW_ARTIFACT_DIR` 为新的证据目录，
`ANYWORK_OBSERVATION_SECONDS` 为观察时长。使用隔离 Studio 数据和工作目录，
读取用户配置并通过系统凭据库鉴权，过程结束回收 runtime。
`ANYWORK_OBSERVATION_ACCOUNT` 与 `ANYWORK_OBSERVATION_MODEL` 必须同时不设置，或同时设置为有效非空 Unicode；仅设置一个或值无效时在初始化前报错，不静默回退默认路由。
同时不设置时沿用已配置路由；显式选择时在隔离副本中选择所有角色的模型，未选中的账号不参与此次配置校验，原配置保持不变。
仅接受不需要凭据迁移的 schema 23 至当前版本配置，更旧、未知或未来版本在初始化前拒绝。
新的隔离 Studio home 通过正常启动迁移配置副本，不复用已有 home，也不能仅手改 schema 版本号。
观察入口在提交任何任务前核对没有发生配置重置，且 canonical 根路由仍是指定账号与模型；
迁移、配置校验或路由核对失败保留证据并返回错误，不将默认配置的运行算作原账号验证。
可用真实任务观察 patch、LSP、跨轮历史、压缩与协作，不再维护固定通过标记。

设置 `ANYWORK_OBSERVATION_WORKSPACE_MODE=worktree` 可创建临时 Git 仓库并通过正常 Studio
命令启动 worktree 根会话；默认 `local` 保持普通隔离目录。worktree 场景可在任务中分别派发
`executor`（带 workspace-relative `writablePaths`）与 `worktree_executor`，观察内置文件
写入、patch、读取与越界拒绝。`root-thread.json`、各 Thread 的事件、timeline、Turn 与 snapshot
以及 `workspace-path.txt` 指向的物理仓库共同构成证据；checkout 保留供检查，runtime 正常关闭。
供应商选择会同步更新隔离配置的 root Mode 与 child 路由，不改用户配置或凭据。

GUI 真实任务通过 `cargo xtask run-gui --driver` 启动，由观察者使用 Flutter Driver
提交任务、查看流、截图和产物，并人工记录结论。自动 Rust 测试仅保留在
`pl-core` 和 `pl-model` 两库；此处不再承诺配置迁移、恢复或
GUI 场景的自动断言；隔离模拟入口使用 `cargo xtask manual-gui`。

执行侧会话目录与 Git 池 ignore 可用 `session_layout_observe` 观察，不读取用户供应商配置：

```bash
cargo run -p pl-studio-runtime --example session_layout_observe -- /absolute/new-artifacts
```

可选 SSH 观察复用已授权的隔离 helper 环境变量（`PURE_SSH_TEST_SERVER` 等），不改用户 `~/.ssh/config`。
