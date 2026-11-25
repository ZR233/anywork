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

平台为 Linux，供应商测试使用本地模拟服务。

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

本次未运行真实付费模型、原生桌面端到端测试或其他平台测试。此记录不代表远端 PR 检查或合并完成。
