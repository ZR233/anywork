library;

/// 工作模式（Mode）feature 公共入口。
///
/// 设置页目录 tab 与全屏工作区路由页从这里导出；面板、画布与详情
/// 组件属于 feature 内部实现，不经由此 barrel 对外暴露。
export 'mode_editor_dialogs.dart' show confirmLeaveModeEditor;
export 'views/mode_catalog_tab.dart';
export 'views/mode_workspace_page.dart' show ModeWorkspacePage;
export 'views/mode_detail_page.dart' show ModeDetailPage;
