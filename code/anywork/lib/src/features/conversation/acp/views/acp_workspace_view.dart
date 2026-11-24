import 'package:material_ui/material_ui.dart';

import '../../composer/views/composer_dock_view.dart';
import '../../workspace/conversation_workspace.dart';

/// 复用统一会话工作区壳的 ACP 工作区视图：
/// 底部状态栏全宽贯穿，右侧可收缩边栏向下延伸至状态栏顶部并将主时间线与输入区
/// 压缩至左侧列，跨折叠 / 并排 / 全宽 / 窄窗浮层切换时保持子状态不变。
class AcpWorkspaceView extends StatelessWidget {
  const AcpWorkspaceView({
    super.key,
    required this.readingArea,
    required this.composerBuilder,
    required this.statusBar,
    this.permissionDock,
    this.sidebarBuilder,
    this.sidebarExpanded = false,
    this.expandedDockBehavior = ConversationExpandedDockBehavior.coverAll,
    this.sidebarCustomWidth,
    this.sidebarDefaultWidthBuilder,
    this.onSidebarWidthChanged,
    this.onCollapseSidebar,
  });

  final Widget readingArea;
  final Widget? permissionDock;
  final Widget Function(BuildContext context, bool compact) composerBuilder;
  final Widget statusBar;
  final Widget? Function(
    BuildContext context,
    ConversationSidebarPresentation presentation,
  )?
  sidebarBuilder;
  final bool sidebarExpanded;
  final ConversationExpandedDockBehavior expandedDockBehavior;
  final double? sidebarCustomWidth;
  final double Function(double containerWidth)? sidebarDefaultWidthBuilder;
  final ValueChanged<double?>? onSidebarWidthChanged;
  final VoidCallback? onCollapseSidebar;

  @override
  Widget build(BuildContext context) {
    return ConversationWorkspaceShell(
      readingArea: readingArea,
      footerDockBuilder: (context, compact) => ComposerDockView(
        compact: compact,
        additionalDiagnostics: const [],
        childInteractions: permissionDock,
        content: composerBuilder(context, compact),
      ),
      statusBar: statusBar,
      sidebarBuilder: sidebarBuilder,
      sidebarExpanded: sidebarExpanded,
      expandedDockBehavior: expandedDockBehavior,
      sidebarCustomWidth: sidebarCustomWidth,
      sidebarDefaultWidthBuilder: sidebarDefaultWidthBuilder,
      onSidebarWidthChanged: onSidebarWidthChanged,
      onCollapseSidebar: onCollapseSidebar,
    );
  }
}
