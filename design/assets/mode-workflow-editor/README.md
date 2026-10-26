# 工作模式编辑器原生验收证据说明

本目录下的截图采集自 Linux 原生桌面端 `anywork`（Flutter `3.47.7` / GTK / Xvfb），运行于真实的 Rust 桥接层（FRB）、SQLite 与隔离的本地模拟供应商环境。验收中使用的项目、会话、提示词与凭据均为合成测试数据，不读取操作者本机私有配置，也未使用演示模式（Demo）或静态设计稿替代真实实现。

所有图片均由 Flutter Driver 直接捕获，未经裁剪或后期修改。宽屏窗口尺寸为 `1440×1000`，窄屏窗口尺寸为 `760×860`；虚拟桌面采用 Xvfb `1600×1200×24`，区域语言设置为 `zh_CN.UTF-8`。

## 1. 验收场景清单

| 截图文件 | 验收覆盖内容 |
| --- | --- |
| [builtin-read-only.png](builtin-read-only.png) | 内置任务模式保持只读，节点编辑与自动排版按钮禁用，支持一键复制为自定义模式 |
| [custom-graph-editor.png](custom-graph-editor.png) | 自定义模式保存、原生节点拖拽、撤销／重做、鼠标连线、自环／返工／多后继分支及阶段属性编辑 |
| [json-validation.png](json-validation.png) | 终态节点存在出边时被 Rust 编译器拒绝并保留原始 JSON 文本；离开页面时取消／放弃草稿行为符合预期 |
| [workflow-preview.png](workflow-preview.png) | 在隔离内存中按生产状态转换规则从规划阶段推进至实施阶段并验证终态，不创建真实 `Thread` 或调用模型 |
| [narrow-inspector.png](narrow-inspector.png) | 原生窗口缩放（Resize）后属性面板自动下置，真实鼠标滚轮可滚动面板，恢复宽屏后完整保留未保存草稿 |
| [deleted-mode-snapshot.png](deleted-mode-snapshot.png) | 在途轮次（Turn）运行期间删除模式配置，已有会话基于冻结快照继续完成，界面显示自定义阶段及“已删除模式使用快照”提示 |
| [restart-restored-snapshot.png](restart-restored-snapshot.png) | 原模式配置已被删除时冷启动仍可继续运行，并正常完成会话归档与恢复，全局模式目录不会重新混入已删除模式 |
| [recheck-restored-snapshot.png](recheck-restored-snapshot.png) | 二次冷启动完整保留同一会话、消息历史及工作模式／工作流快照，仅打开历史视图不触发额外模型请求 |

## 2. 验收结果与验证边界

[verification.json](verification.json) 记录了完整的三阶段执行结果、Flutter Driver 行为断言、SQLite 检查点（Checkpoint）核对摘要、冷恢复静默窗口、子进程树回收记录及各截图文件的 SHA-256 摘要。

三个独立的原生进程生命周期（`first`、`restart`、`recheck`）全部正常完成并优雅关闭，GUI 未捕获异常、Dart 运行时错误及模拟供应商脚本拒绝计数均为 `0`。自动化断言与智能体截图核对均已通过，人工评审状态保持默认的 `pending`。

SQLite 检查点核对覆盖以下核心不变量：

- 当前在途轮次保持启动时冻结的提示词与工作流状态图不变，下一轮次的模式定义、指令提示词与工作流图散列值（Hash）同步更新并保持一致。
- 工作流状态图结构变更以 `modeUpdated` 原因归档旧运行实例，并在同一谱系（Lineage）下创建替代实例；仅修改提示词文本时保留原运行实例 ID、状态图散列值与图修订版本（Graph Revision）。
- 删除模式定义后，已有会话完整保留已持久化的模式定义快照、消息历史与运行状态；进程重启及归档恢复不依赖全局模式目录，也不重新向全局目录发布已删除模式。
- 当磁盘上的无效配置文件触发显式重载失败时，已发布的模式目录修订版本与既有有效定义保持不变。
- 验收所属的 GUI 进程、Flutter / DTD 守护进程、Driver 连接及模拟供应商夹具（Fixture）均由平台进程树生命周期机制完整回收。

本地代码门禁同步验证通过：`cargo fmt --all --check`、全工作区 Clippy 静态检查（`-D warnings`）、`pl-model` / `pl-core --features sqlite` / `pl-studio-runtime` 单元与集成测试、`cargo xtask verify-client`（SDK 164 项、适配层 177 项）、`cargo xtask verify-gui` 及 `git diff --check`。

本轮验收未覆盖 Windows / macOS 原生窗口交互及真实外部模型供应商兼容性；本地 Linux 模拟环境通过不外推为跨平台或真实供应商环境通过。

## 3. 本地复现命令

在仓库根目录下执行以下命令（`--output` 须指向尚未存在的新目录）：

```bash
cargo install --path code/pl-remote-helper --locked
NO_AT_BRIDGE=1 LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 GDK_BACKEND=x11 \
  PUB_HOSTED_URL=https://pub.dev xvfb-run -a -s '-screen 0 1600x1200x24' \
  cargo xtask manual-gui --scenario mode-editor --output target/manual-gui/mode-editor
```

`manual-gui` 会自动创建并在结束时回收隔离数据根目录，所有 GUI 交互均通过 Flutter Driver 执行。完整的原始运行日志、Widget / Render 树转储、分阶段状态快照与数据库检查点观察记录保存在运行输出目录中，不随截图提交至源码库。
