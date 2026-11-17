# anywk 命令行

在 Studio 运行时中执行一个 Native 或 ACP 任务，等待终态和资源关闭后输出最终助手文本。

从仓库根目录构建：

```sh
cargo build --locked -p pl-studio-cli --bin anywk
```

将当前原生配置准备到独立目录 `run-home/config.toml`，通过运行环境注入账号 `bearer_token_env` 指定的凭据，然后执行：

```sh
anywk exec \
  --studio-home ./run-home \
  --cwd ./task \
  --account benchmark \
  --model vendor/model \
  --prompt-file ./prompt.txt \
  --no-default-user-skills \
  --skill-dir ./evaluation-skills
```

`task` 可以是普通非 Git 目录。所有相对路径以进程启动目录解析；不会改变全局工作目录、HOME 或 USERPROFILE。`--prompt-file -` 从标准输入读到结束，任务须为非空白 UTF-8。`--reasoning-effort` 由该模型原生能力校验；`--mode` 默认 `mode.simple`。`--max-model-steps` 只能收紧根输入的模型步数，不是整棵任务树的总预算。

配置必须事先存在且有效。严格启动保留坏配置和恢复现场，不创建默认配置或自动重置。凭据仅来自原生账号的环境变量引用，不能使用 ChatGPT/OAuth、交互登录或系统凭据库。OpenAI-compatible 可以无凭据；其他协议仍遵守原生凭据要求。CLI 当前沿用产品的实际 FullAccess 权限。

技能优先级为项目、默认用户、系统、配置 `external_dirs`，最后是重复 `--skill-dir` 的出现顺序。追加参数直接指向只读技能集合根，不再附加 `.agents/skills`，不增加写权限；归一化重复路径保留第一次。`--no-default-user-skills` 只关闭隐式用户来源，仍可显式重新加入同一路径。显式目录缺失、不可读或路径不安全会失败，运行中失效也不会回退。

Harbor 容器内可使用固定挂载路径：

```sh
anywk exec --studio-home /runs/profile --cwd /workspace/task \
  --account benchmark --model vendor/model --prompt-file /runs/prompt.txt \
  --no-default-user-skills --skill-dir /opt/evaluation/skills
```

评测配置使用显式模型目录，并通过已有配置关闭不参与评测的 MCP、自学习及动态目录探测；隔离 home 不包含启用的机器人配置。`--output-dir` 导出版本 2 的结果、追踪及用量归档，目录必须尚不存在；格式与完整性边界见下方命令行设计文档。

标准输出仅为最终助手文本，诊断写标准错误。退出码：正常 0，输入/配置/路由 2，等待输入或审批 3，预算耗尽 4，任务失败 10，启动环境/内部错误 11，关闭失败 13，其他取消 14，SIGINT 130，SIGTERM 143。关闭失败优先；清理预算为 30 秒。Windows 原生监听 Ctrl+C，Unix 原生监听 SIGINT/SIGTERM。

## ACP 会话

使用已有 Studio home 中配置的 ACP 账号 ID；官方代理沿用自己的登录态。以下探测不发送任务，也不执行登录，清洁关闭后只输出服务端实际声明的能力与当前会话配置 JSON：

```sh
anywk acp-options --studio-home ./run-home --cwd ./task --account my-acp
```

按探测返回的配置 ID 和值 ID 执行任务，不能用显示名替代。配置依参数顺序设置，每次重新读取当前选项并核对回读；后续配置若改变此前明确请求的值，会在发送任务前失败：

```sh
anywk exec-acp --studio-home ./run-home --cwd ./task --account my-acp \
  --prompt-file ./prompt.txt --config model=SERVER_MODEL_ID \
  --config thought_level=SERVER_VALUE_ID --no-default-user-skills \
  --skill-dir ./evaluation-skills
```

`--prompt-file -` 支持标准输入；路径和技能来源规则与 `exec` 相同。ACP 不接受 Native 的 `--model`、`--mode`、`--reasoning-effort`、`--max-model-steps` 或 `--output-dir`。非打包运行要求 PATH 中已有与源码匹配的 `pl-studio-mcp`。权限请求一律拒绝并返回 3，不自动批准；观察缺口、断连、失败与非正常停止不会输出成功文本。关闭预算 30 秒，关闭失败返回 13，信号返回 130/143。

完整契约见 [命令行宿主与 Harbor 接入](../../design/29-cli-harbor.md)；所有参数见各命令的 `--help`。

CLI 分别观察 Current 和 History：Current 的真实等待交互状态使非交互任务以退出码 `3` 结束；终态只从 History 的不可变 Turn 原件读取。等待交互不会被改写为历史完成事件，导出结果保留 `blockedOnInput` 的退出原因。
