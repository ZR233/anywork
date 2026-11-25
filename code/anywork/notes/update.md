# 更新模块审读与修复

基线为 `3db5e10d03db6a13bcc44b37d37555bcaf80e2c7`。6 个手写生产文件及 1 个预览文件均已全文审读。更新事实继续来自既有 Client 更新 owner；界面调整不改变下载、安装、取消或退出协调。

| 文件（相对 `lib/src/features/update`） | 职责、处理与保留理由 |
| --- | --- |
| `studio_update_actions.dart` | 连接更新准备、安装与退出协调。保留真实业务资源和错误传播，不在界面复制更新状态。 |
| `connectors/sidebar_footer_connector.dart` | 将共享更新 VM 接到底栏。与设置页共用动作失败提示；删除无样式消费者的 `touchMode` 转发。 |
| `connectors/studio_update_settings_connector.dart` | 绑定呈现及命令。原发布说明回调的 Future 错误没有被 UI 接住，现统一进入已有本地化 SnackBar；保留原错误文本与挂载检查。 |
| `state/studio_update_view_state.dart` | 纯呈现输入，区分更新状态、用户请求、可用操作及错误。保留，避免视图推导业务阶段。 |
| `view_models/studio_update_view_model.dart` | 从 canonical 更新状态派生界面，动作仍交原 owner。保留更新事件接纳、已有可安装包和取消语义。 |
| `views/studio_update_settings_view.dart` | 状态和操作布局。原 Row 给操作 Wrap 无界横向空间，窄窗大字溢出；现用局部 LayoutBuilder 和官方 TextScaler 判断操作是否换到下方，Wrap 获得有限宽度。 |
| 新增 `connectors/update_action_feedback.dart` | 两个 connector 的薄反馈复用；仅等待既有动作、捕获错误及检查当前 context 是否仍挂载，不持有第二份业务状态。 |

预览 `anywork_previews/lib/src/features/update/previews/update_previews.dart` 使用生产 View 和合成状态，原可安装更新保留场景继续存在。官方 Widget Previewer 已实际观察可安装状态：320×420、1.5 倍文字，说明与错误自然换行，两项操作完整可见，无溢出；主代理已核对截图。该观察不代替原生安装验收。

## 行为证据

新增 `test/ui/update_settings_behavior_test.dart` 从真实 View / Connector 进入，覆盖 320×900、1.5 倍文字下可用更新及下载中操作，以及发布说明 Future 失败后的反馈。修复前 3 例失败：布局右侧溢出 706 px，发布说明错误未捕获且无 SnackBar。修复后与原有更新投递和 VM 用例联合运行：

```sh
cargo flutter test --no-pub test/ui/update_settings_behavior_test.dart test/ui/update_event_delivery_test.dart test/unit/studio_update_view_model_test.dart
```

exit 0，11 项通过。包括一个 canonical 更新同时投递底栏和稍后挂载的设置页，设置卸载不会影响底栏，以及原 VM 状态和动作语义。定向格式化通过。该结果不证明原生安装器、真实网络、系统重启或跨平台行为；本轮未改变这些边界。
