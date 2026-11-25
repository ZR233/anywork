# M09 共享组件审读

基线 27 个文件均已逐文件全文审读。以下记录 23 个生产组件，另外四个 Driver 文件见[专项记录](driver/review.md)。新增 `studio_menu_button.dart` 同时纳入核对。审读完成不代表全局验证已经通过。

## 已审读文件与决定

路径均相对于 `lib/src/shared/`。

| 文件 | 职责与处理决定 |
| --- | --- |
| account_brand.dart | 供应商品牌资源和自定义账号文字头像。保留品牌映射；首字母截取改用 Flutter 导出的 characters，避免截断 emoji、组合字符，保留前两词首字母/单词前两字规则。 |
| composer_action_button.dart | Native/ACP 共用固定尺寸主按钮。状态资格来自调用方，官方 IconButton 和 CircularProgressIndicator 管理交互与动画，保留。 |
| composer_configuration_bar.dart | 配置项宽度分配、窄窗溢出。保留领域布局；溢出入口改用 StudioMenuButton.icon，移除重复 MenuAnchor builder。 |
| composer_input_frame.dart | 共用输入装饰及工具栏几何。已由领域调用方注入动作/配置，保留。 |
| conversation_composer.dart | 本地编辑器、附件动作与键盘行为。稳定 identity 隔离草稿；controller、FocusNode 和输入法组合保护属于组件局部资源，保留。异步粘贴/附件资格和 dispose 清空旧 selection 不能当补丁删除。 |
| delegation_labels.dart | 类型化委派呈现标签，保留。 |
| host_app_artwork.dart | 品牌矢量图形，不属于可替换的通用业务控件，保留。 |
| host_app_logo.dart | 品牌组件装配，保留。 |
| latest_scroll.dart | 阅读暂停、选区、历史恢复和回到最新的产品行为。已依赖官方 ScrollAction/RawScrollbar/Notification；intent 隔离过期恢复，资源与注册正确收束，保留。普通滚动组件不能替代这些阅读语义。 |
| model_route_selector.dart | 按账号分组、搜索、能力标签、唯一 route 身份和选择后的派发。触发器改用公共菜单；保留搜索 controller、当前项滚动定位和 SubmenuButton。定位只作用于菜单自己的 scrollable，不移动设置页面。 |
| recovery_check_status.dart | 恢复检查呈现，保留。 |
| status_detail_panel.dart | 状态详情共用布局，保留。 |
| studio_badges.dart | 各领域共用标记；删除无消费者的 StudioProgressDots，其他标记仍有真实使用者。删除前 LSP findReferences 只有自身类/构造声明两处，全文搜索也无生产/测试/预览消费者。 |
| studio_child_readonly_panel.dart | 子代理只读范围及状态提示，保留。 |
| studio_chrome.dart | 共用界面尺寸与装饰，保留。 |
| studio_code_block.dart | 代码显示和复制局部反馈，保留。 |
| studio_context_usage_ring.dart | Native/ACP 共用的 16px 指标图形。用 CircularProgressIndicator 替换手写 painter；stroke 2.2、内缩和圆头保留原几何，轨道透明度仍为 .74，无轨道间隙。未知值传 0 只显示轨道，ExcludeSemantics 让领域 owner 继续表达“未知”，不新增 0% 或加载动画。 |
| studio_hover_detail.dart | 官方悬浮/焦点详情锚定，保留领域尺寸与可访问性，未新增 Overlay 状态机。 |
| studio_loading.dart | 共用加载呈现，保留。 |
| studio_menu_label.dart | 配置文字、图标和测量几何，保留。 |
| studio_messages.dart | 空状态、行内消息和领域色调提示组件；只负责呈现，无独立消息队列，保留。 |
| studio_panel.dart | 卡片和分区布局，保留。 |
| typed_json.dart | 展示边界的宽容 JSON 解码及非 String 键文字化，保留；收紧会改变历史材料呈现，并非本轮质量修复目标。 |
| studio_menu_button.dart（新增） | 一个稳定 FocusNode 同时交给 MenuAnchor.childFocusNode 和触发按钮。菜单开关、键盘退出/遍历由现有 Material 实现负责；不暴露外层控制器，不镜像开合，不手动 requestFocus。text/icon 共用 owner，保留调用方样式及禁用解释动作。 |

## Driver 专项

- studio_driver_keys.dart
- studio_driver_key_values.dart
- studio_driver_projection.dart
- studio_driver_state.dart

四文件已完成引用与读写链核对、清理及格式/LSP检查，待联合行为验证。删除失效控件选择器、无消费的 topic 诊断端点、重复退出诊断聚合及只写不读的启动失败切片；保留现役 `snapshotJson` 中的 native 预算、退出报告和阶段。父复核发现该聚合并非 native 预算唯一出口，已纠正初次判断。陈旧账号验收说明同步迁移到实际账号控件。

## 菜单迁移调用方

除了 shared 内的 model_route_selector/composer_configuration_bar，本轮同步迁移 `features/status/session_selectors.dart`、`features/conversation/acp/widgets/acp_configuration_bar.dart`、`features/settings/accounts/widgets/account_menu_button.dart`。各领域仍保留选项、动作、布局和样式；这些文件的迁移不代表其整个功能模块已审读。

## 核查依据与验证

- 已读取锁定版本 `material_ui 1.11.0` 的 MenuAnchor/MenuItemButton 与 CircularProgressIndicator 实现及 Flutter 3.50.0 官方焦点契约。应用沿用当前 material_ui 组件族，不能在同一菜单中混用 Flutter 原版 MenuItemButton 和 material_ui MenuAnchor；两者的私有 ancestor owner 不同。
- 首次新菜单测试失败 2/3：测试误用了 Flutter 原版菜单项，选中后无法找到应用菜单的 owner。修正测试 import 后，真实生产组件组合通过；未通过改动关闭断言掩盖问题。
- `cargo flutter test --no-pub test/ui/studio_menu_button_test.dart test/unit/account_initials_test.dart`：exit 0，14 项通过。覆盖 text/icon 的指针打开、Escape 退出、Enter 重开、选择后关闭、输入保留、菜单内容刷新、禁用解释，以及 11 组字符缩写数据。
- `cargo flutter test --no-pub test/ui/context_usage_readout_test.dart test/ui/acp_status_bar_test.dart`：exit 0，14 项通过，覆盖未知语义、压缩资格、窄窗与放大字体、会话切换、断线读数保留、超容量和悬浮详情。环形指标仍待官方预览观察；整应用分析、完整 UI 和最终复核另在总台账记录。
