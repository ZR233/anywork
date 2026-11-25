# PR #593 冲突协调记录

## 范围与依据

- PR 原提交：`268d96174112948c54ccc7d6143895d6e9fb110f`。
- 主线功能基线：`5e90f4922f91c86255d3f369bb6b7428108823c7`，包含 PR #585、#591、#592、#594、#595。
- 最终合并基线：`e601431cd0fe8b23c5013ecb62da57eff4ea15ea`。它在上述功能基线上仅增加 6.52.0 发布记录与版本同步，已一并纳入。
- 核对了 PR #592 的开发过程及本仓库 [Gemini 协议审计](gemini-protocol-audit.md)。其中的真实模型长任务和历史 CI 结果只作为提交意图依据，不计入本次验证。

## 语义协调

1. **供应商失败分类**：保留 #593 的供应商策略、完整类型化失败和统一恢复预算；把 #592 的 Gemini 校验接入新接口，保留候选结构、响应身份、工具参数、签名、空回答及原始用量校验。
2. **Gemini 生成失败**：`MALFORMED_RESPONSE` 继续采用有预算的重新生成策略；其他明确失败原因不因此变为可重试。失败同帧的用量仍可结算，失败工具和签名不进入成功上下文。
3. **默认结束值**：`FINISH_REASON_UNSPECIFIED` 在中间帧不截断后续内容和签名；若流最终没有有效结束原因，则保留该原始值和已观察用量并报告协议失败。[官方枚举说明](https://aistudio.google.com/api-reference/generate-content#Resource:Candidate)将它定义为未使用的默认值，不能据此判定成功。
4. **费用唯一来源**：把 #592 的失败尝试账单接入 #593 的逐次结算，不同时保留终态嵌套账单与独立账单两套计费。每次实际请求只计一次传输；失败样本不借用最终成功的模型身份或耗时，未知用量保持未知。
5. **连接边界与副作用**：保留 #585 的可靠断线、重连记录。WebSocket 达到寿命上限按[官方定义](https://developers.openai.com/api/docs/guides/error-codes)归为连接故障，普通繁忙和限流不冒充断线。远端工具可能已经执行时不重放当前请求，但保留断线记录及下一轮 HTTP 回退。
6. **历史迁移**：保留主线第 27 版数据库结构；第 26 版到第 27 版的升级在同一事务中先执行必要的失败载荷维护。已处于第 27 版的旧库先备份，再执行维护修订 2。原正文、冻结费用、身份及追加写入约束保持不变。
7. **生成与检查**：桥接和本地化通过统一入口重新生成。静态检查发现新增失败详情扩大了错误值及状态事件，改为堆上保存相应大字段，并同步内存预算计算；不改变产品序列化格式。

## 本次验证

平台为 Linux；下表为冲突协调阶段的确定性验证，真实模型验证单独列在后文。

| 检查 | 结果 |
| --- | --- |
| `cargo test --locked -p pl-model --test integration` | 178 项通过 |
| `cargo test --locked -p pl-model-gemini` | 32 项通过 |
| `cargo test --locked -p pl-model-runtime --lib` | 41 项通过 |
| `cargo test --locked -p pl-studio-runtime --lib history::upgrade` | 36 项通过 |
| `cargo test --locked -p pl-studio-runtime --lib studio::thread_projection` | 36 项通过，已在内存布局调整后补验 |
| `cargo test --locked -p pl-studio-runtime --lib run_export` | 20 项通过，包括失败账单、费用导出与历史重新打开 |
| `cargo xtask verify-client` | 678 项测试、712 个源文件边界检查及静态分析通过 |
| `cargo flutter analyze` | 无诊断 |
| 时间线、费用读数、ACP 顶栏三个界面测试文件 | 9 项通过 |
| `cargo xtask generate-gui` | 通过 |
| `cargo clippy --locked --workspace --all-targets -- -D warnings` | 最终源码的整仓全部目标通过 |
| `cargo fmt --all --check`、`git diff --check` | 通过，无剩余冲突标记 |

桥接内存布局调整后重新执行统一生成与 Flutter 静态分析，均通过。最终版本文件与主线一致；没有额外升级依赖版本。

本地未运行原生桌面端到端测试或其他平台测试；这些边界由当前提交的远端持续集成分别验证。此记录不代表 PR 已合并。

## 持续集成发现与修复

首轮提交 `71f768a10338c0b4bff25ae9fd9112641a5e5b9e` 的 Linux 前端检查发现，费用顶栏测试直接导入 FRB 类型，违反界面测试的无桥接依赖边界。修复保留两层行为证据：

- 界面测试直接消费 `SessionCostView`，继续验证已知金额、用量不完整标记与未计价提示。
- 原有桥接转换场景移入 `test/unit/frb_adapter/session_costs_frb_adapter_test.dart`，独立验证金额和两个完整性标记的转换，避免删除转换覆盖。
- `client_boundary_check.dart --all` 通过：712 个源文件、88 个界面测试入口；费用顶栏 5 项、桥接转换 1 项测试通过。

同轮 Rust 整仓检查还暴露了关闭等待范围过宽的问题：`CloseStage::Flush` 等待整个维护任务队列，普通 `flush()` 尚在等待写盘时，最终关闭栅栏无法启动。现在沿既有串行所有者单独计数模型账单确认与辅助调用退出，仅等待这些必要义务，仍然保留账单保存确认。原有关闭回归能先观察到最终栅栏，再验证存储失败和显式重试。

两项上下文阶段测试同步到 #593 的恢复契约：服务端恢复带一次性授权，压缩实际缩短已提交上下文；缺少压缩钩子时同时保留原始上下文超限和修复失败原因。没有放宽生产代码的缩短检查或绕过恢复预算。

`cargo test --locked -p pl-core --test integration --features sqlite` 的 323 项全部通过；`cargo clippy --locked -p pl-core --all-targets --features sqlite -- -D warnings` 通过。真实 SQLite 的 `preserving_close_waits_for_the_registered_auxiliary_call_and_its_sqlite_save` 回归 1 项通过，证明关闭仍等辅助模型和账单写盘。最终持续集成状态以 PR 最新提交对应运行的终态为准。

## 真实 GPT 6 Luna 与故障工况

使用本次源码编译的 `target/debug/anywk`，不使用系统中旧版本。下述首轮二进制的源码提交为 `71f768a10338c0b4bff25ae9fd9112641a5e5b9e`，因此不将其当作后来关闭等待修复的验证。用户账户只读取既有 `OPENAI_API_KEY` 环境引用；配置、历史、任务目录与输出隔离，原用户配置 SHA-256 在执行前后相同。

长任务通过用户兼容账户实际使用 Responses WebSocket、`gpt-6-luna`、`high`，执行八阶段 SQLite 持久队列开发：幂等、租约、优先级、失败重试、数据迁移、命令行、多进程及最终审计。

| 观察项 | 本次实际结果 |
| --- | --- |
| 运行时间 | 521,562 毫秒，约 8 分 42 秒 |
| 模型请求 | 54 次实际尝试：53 次成功、1 次真实供应商流失败 |
| 自然故障恢复 | `websocket_connection_limit_reached` 被归为连接故障，自动重连后完成任务 |
| 账单唯一性 | 54 个独立尝试账单，54 次传输，未重复记账 |
| 任务独立复测 | `python3 -m unittest discover -v`：45 项通过，0 失败、0 跳过；含 8 进程领取 80 个任务 |
| 归档与退出 | 退出码 0，`completed`、`clean`、持久化 `drained`；事件摘要校验通过 |
| 用量边界 | 失败尝试未返回用量，完整总量与费用保持 `null`；已知部分 2,347,032 tokens、估算 0.04204304 USD，不冒充完整费用 |

采用 [mitmproxy 官方反向代理](https://docs.mitmproxy.org/stable/concepts/modes/#reverse-proxy)和[请求钩子](https://docs.mitmproxy.org/stable/addons/examples/#example-http-reply-from-proxy)注入可控错误。代理只监听回环地址，成功请求仍转发到用户实际供应商；只记录方法、路径、状态和时间，不保存凭据或请求正文。限流和额度错误是人工注入，不能描述为供应商自然发生。

| 工况 | 结果 |
| --- | --- |
| 模型端点首次 429，随后真实 Luna 回答 | 共 2 次尝试；实际间隔约 810 毫秒，满足 500 毫秒等待；失败账单未知值保留 |
| 429 `insufficient_quota` | 模型尝试 1 次，永久失败，退出码 10，不重试 |
| 连续 429 `rate_limit_exceeded` | 模型尝试 6 次，重试数 5，`budgetExhausted`，退出码 10 |
| 60 秒限流等待中发送 SIGTERM | 取消后无第二次模型尝试，退出码 143，正常关闭并完成持久化 |
| 已收到真实 Luna WebSocket 消息时发送 SIGTERM | 约 164 毫秒后退出，退出码 143，正常关闭 |
| 取消后复用同一隔离配置目录重新运行 | 真实 Luna 正常返回，退出码 0，用量及费用完整 |

所有工况的归档都已核对事件摘要、尝试计数、关闭与持久化状态。一次性配置、代理脚本、完整导出与验证结果保留在工程运行目录 `target/anywk-observe/pr593-luna-20261125/`，不进入源码提交。初次代理探针误将目录发现请求计入首次 429，已排除该探针；表中恢复工况重新限定为 `/v1/responses`，依据实际模型请求和账单计数。
