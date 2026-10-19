# 工作模式编辑器原生验收证据

这些图片来自 Linux 原生 anywork（Flutter 3.47.7 / GTK / Xvfb），使用真实 Rust bridge、SQLite 和隔离的本地模拟供应商。项目、会话、Prompt 和凭据均为验收合成数据，不读取用户私有配置，也未使用 Demo API 或设计稿替代实现。

图片是 Flutter Driver 捕获的原图，未裁剪或修改。宽屏窗口为 1440×1000，窄屏为 760×860；桌面使用 Xvfb 1600×1200×24，语言为 `zh_CN.UTF-8`。

## 场景

| 图片 | 检查内容 |
| --- | --- |
| [builtin-read-only.png](builtin-read-only.png) | 内置任务模式只读，编辑和自动排列禁用，可复制为自定义模式 |
| [custom-graph-editor.png](custom-graph-editor.png) | 自定义定义保存、原生节点拖动、撤销/重做、鼠标连线、自环/返工/多个后继、阶段属性编辑 |
| [json-validation.png](json-validation.png) | 终态出边被 Rust 编译器拒绝，保留原始 JSON；离开时取消/放弃草稿行为正确 |
| [workflow-preview.png](workflow-preview.png) | 在隔离内存中按生产转换规则从规划推进到实施，再验证终态；不创建 Thread 或调用模型 |
| [narrow-inspector.png](narrow-inspector.png) | 原生 resize 后属性面板下置，真实鼠标滚轮移动面板，回到宽屏保持草稿 |
| [deleted-mode-snapshot.png](deleted-mode-snapshot.png) | 在途 Turn 中删除配置，已有会话继续完成，显示自定义阶段及「已删除模式使用快照」 |
| [restart-restored-snapshot.png](restart-restored-snapshot.png) | 配置不存在时冷启动继续运行，并完成归档与恢复，目录不重新加入该模式 |
| [recheck-restored-snapshot.png](recheck-restored-snapshot.png) | 再次冷启动保留同一会话、历史和 Mode/工作流快照，打开历史不触发模型请求 |

## 结果与边界

[verification.json](verification.json) 保存完整三阶段结果、Driver 行为断言、SQLite checkpoint 核对摘要、冷恢复静默窗口、进程回收记录及图片 SHA-256。

三个全新原生进程生命周期（`first`、`restart`、`recheck`）均完成并正常关闭，GUI 未处理异常、Dart 错误和供应商脚本拒绝均为零。自动断言与代理截图核对已完成，人工评审状态仍为 `pending`。

checkpoint 核对包含：

- 当前 Turn 保留原 Prompt/图，下一 Turn 的定义、instructions Prompt 和工作流图 hash 一致。
- 图变更以 `modeUpdated` 归档并创建同 lineage replacement；仅 Prompt 变更保留 run ID、图 hash 和 graph revision。
- 删除后保留已保存的完整定义、历史与运行状态；重启和归档恢复不依赖全局目录，也不重新发布模式。
- 无效文件显式重载失败时，已发布的目录 revision 与有效定义保持不变。
- 所属 GUI、Flutter/DTD、Driver 和供应商 fixture 由现有进程树生命周期机制回收。

本地代码门禁通过：`cargo fmt --all --check`、workspace Clippy（`-D warnings`）、`pl-model` / `pl-core --features sqlite` / `pl-studio-runtime` 测试、`cargo xtask verify-client`（SDK 164 项、adapter 177 项）、`cargo xtask verify-gui` 及 `git diff --check`。生成文件通过统一生成入口验证。

未覆盖 Windows/macOS 原生交互和真实供应商兼容；本地模拟通过不外推为这些场景通过。GitHub CI 的实际终态在 PR 中单独记录。

## 复现

在仓库根目录执行，输出目录需是新的目录：

```bash
cargo install --path code/pl-remote-helper --locked
NO_AT_BRIDGE=1 LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 GDK_BACKEND=x11 \
  PUB_HOSTED_URL=https://pub.dev xvfb-run -a -s '-screen 0 1600x1200x24' \
  cargo xtask manual-gui --scenario mode-editor --output target/manual-gui/mode-editor
```

`manual-gui` 自动创建并回收隔离数据根；GUI 操作使用 Flutter Driver。完整原始日志、widget/render tree、分阶段快照和 checkpoint 观察保留在运行输出目录，不随图片提交。
