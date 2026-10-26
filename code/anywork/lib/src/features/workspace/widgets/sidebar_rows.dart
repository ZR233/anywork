import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../platform/studio_platform.dart';
import '../../../ui/branding/host_app_logo.dart';
import '../../shell/views/thread_status_indicator.dart';
import 'sidebar_hover_detail.dart';
import 'sidebar_tile.dart';

enum SidebarProjectAction { pin, copyPath, archive }

enum SidebarThreadAction {
  pin,
  rename,
  archive,
  restore,
  retryRecovery,
  copyPath,
  vsCode,
  zed,
  terminal,
}

/// UI-only host capabilities/artwork supplied by a Smart connector.
class WorkspaceHostApps {
  const WorkspaceHostApps({
    required this.vsCode,
    required this.zed,
    required this.terminal,
    this.vsCodeImage,
    this.zedImage,
    this.terminalImage,
  });
  final bool vsCode;
  final bool zed;
  final bool terminal;
  final ImageProvider? vsCodeImage;
  final ImageProvider? zedImage;
  final ImageProvider? terminalImage;
}

/// 侧栏项目行：折叠箭头、文件夹、项目名、真实本地/SSH 标识、常驻新建
/// 与更多菜单。完整路径不再常驻占用辅助行，悬停时在只读浮层中查看，
/// 通过更多菜单复制；存在 recovery issue 时诊断提示优先。
class SidebarProjectRow extends StatelessWidget {
  const SidebarProjectRow({
    required this.project,
    required this.expanded,
    required this.selected,
    required this.pinned,
    required this.touchMode,
    required this.onSelect,
    required this.onToggleExpanded,
    required this.onNewThread,
    required this.onAction,
    this.recovery,
    super.key,
  });
  final ProjectRecord project;
  final bool expanded;
  final bool selected;
  final bool pinned;
  final bool touchMode;
  final RecoveryIssue? recovery;
  final VoidCallback? onSelect;
  final VoidCallback onToggleExpanded;
  final VoidCallback? onNewThread;
  final ValueChanged<SidebarProjectAction> onAction;

  @override
  Widget build(BuildContext context) {
    final issue = recovery;
    if (issue != null) {
      // 诊断提示优先：存在 recovery issue 时只保留名称区 Tooltip，不展示详情卡。
      return _buildRow(context, nameTooltip: issue.message);
    }
    // 只读详情锚定整行；浮层忽略指针，不挡住新建/更多按钮。
    return SidebarHoverDetail(
      detailBuilder: (context) => _projectDetailCard(context),
      child: _buildRow(context),
    );
  }

  /// 构建整行（折叠箭头、名称、常驻新建与更多菜单）。详情宿主/诊断 Tooltip
  /// 由调用方决定，本方法只返回行内控件与 `projectRow` 键。
  Widget _buildRow(BuildContext context, {String? nameTooltip}) {
    final l10n = context.l10n;
    final target = touchMode ? 44.0 : 32.0;
    final nameArea = _buildProjectNameArea(context);
    return KeyedSubtree(
      key: StudioDriverKeys.projectRow(project.id),
      child: Row(
        children: [
          sidebarTileIconButton(
            key: StudioDriverKeys.projectExpand(project.id),
            tooltip: l10n.sidebarProjects,
            icon: expanded ? Icons.expand_more : Icons.chevron_right,
            iconSize: 18,
            minTarget: target,
            onPressed: onToggleExpanded,
          ),
          Expanded(
            child: nameTooltip == null
                ? nameArea
                : Tooltip(message: nameTooltip, child: nameArea),
          ),
          sidebarTileIconButton(
            key: selected
                ? StudioDriverKeys.newSession
                : ValueKey('project-new-session-${project.id}'),
            tooltip: '${l10n.sidebarNewSession} · ${project.name}',
            icon: Icons.add,
            iconSize: 18,
            minTarget: target,
            onPressed: recovery == null ? onNewThread : null,
          ),
          SizedBox.square(
            dimension: target,
            child: _SidebarMenu(
              menuKey: StudioDriverKeys.projectMenu(project.id),
              tooltip: l10n.sidebarProjects,
              children: [
                MenuItemButton(
                  overflowAxis: Axis.vertical,
                  onPressed: () => onAction(SidebarProjectAction.pin),
                  child: Text(pinned ? l10n.sidebarUnpin : l10n.sidebarPin),
                ),
                MenuItemButton(
                  overflowAxis: Axis.vertical,
                  onPressed: () => onAction(SidebarProjectAction.copyPath),
                  child: Text(l10n.sidebarCopyPath),
                ),
                MenuItemButton(
                  key: const ValueKey('project-close'),
                  overflowAxis: Axis.vertical,
                  onPressed: () => onAction(SidebarProjectAction.archive),
                  child: Text(l10n.sidebarCloseProject),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectNameArea(BuildContext context) {
    final l10n = context.l10n;
    final issue = recovery;
    return InkWell(
      onTap: issue == null ? onSelect : null,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: touchMode ? 12 : 7),
        child: Row(
          children: [
            Icon(
              issue == null ? Icons.folder_outlined : Icons.error_outline,
              size: 17,
              color: issue == null ? null : context.colors.error,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              project.sshAlias == null ? l10n.sidebarLocal : 'SSH',
              style: context.text.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectDetailCard(BuildContext context) {
    final l10n = context.l10n;
    final alias = project.sshAlias;
    final environment = alias == null ? l10n.sidebarLocal : 'SSH · $alias';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 详情卡内部可滚动，完整展示 canonical 项目名，不设行数上限；
        // 截断只发生在行内单行渲染。
        Text(
          project.name,
          style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SidebarDetailRow(
          leading: Icon(
            alias == null ? Icons.computer_outlined : Icons.dns_outlined,
            size: 15,
            color: context.colors.onSurfaceVariant,
          ),
          value: environment,
        ),
        SidebarDetailRow(
          leading: Icon(
            Icons.folder_open_outlined,
            size: 15,
            color: context.colors.onSurfaceVariant,
          ),
          value: project.path,
          monospace: true,
        ),
      ],
    );
  }
}

/// 归档视图中的会话行：单行标题与常驻恢复入口，不提供其余会话操作。
class SidebarArchivedThreadRow extends StatelessWidget {
  const SidebarArchivedThreadRow({
    required this.thread,
    required this.touchMode,
    required this.onRestore,
    this.recovery,
    super.key,
  });
  final WorkspaceThreadRecord thread;
  final bool touchMode;
  final VoidCallback? onRestore;
  final RecoveryIssue? recovery;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final issue = recovery;
    final tile = SidebarCompactTile(
      selected: false,
      title: thread.title,
      onTap: null,
      touchMode: touchMode,
      trailing: sidebarTileIconButton(
        key: ValueKey('thread-restore-${thread.id}'),
        tooltip: l10n.sidebarRestore,
        icon: Icons.unarchive_outlined,
        iconSize: 17,
        minTarget: touchMode ? 44 : 32,
        onPressed: onRestore,
      ),
    );
    return KeyedSubtree(
      key: StudioDriverKeys.threadRow(thread.id),
      child: issue == null
          ? SidebarHoverDetail(
              detailBuilder: (context) => _archivedDetailCard(context),
              child: tile,
            )
          : Tooltip(message: issue.message, child: tile),
    );
  }

  Widget _archivedDetailCard(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        thread.title,
        style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      SidebarDetailRow(
        leading: Icon(
          Icons.folder_open_outlined,
          size: 15,
          color: context.colors.onSurfaceVariant,
        ),
        value: thread.workspacePath,
        monospace: true,
      ),
    ],
  );
}

/// 侧栏会话行：紧凑单行标题，右侧固定状态区（会话工作树标识与行级
/// canonical 运行状态），悬停或聚焦时出现置顶快捷操作与更多菜单，并展示
/// 完整标题、项目、环境、会话工作区路径与状态时间的悬浮详情。
/// 每行的状态只读自己的 [WorkspaceThreadRecord.status]。
class SidebarThreadRow extends StatelessWidget {
  const SidebarThreadRow({
    required this.thread,
    required this.project,
    required this.selected,
    required this.pinned,
    required this.hostApps,
    required this.onSelect,
    required this.onAction,
    this.recovery,
    this.touchMode = false,
    super.key,
  });
  final WorkspaceThreadRecord thread;
  final ProjectRecord project;
  final bool selected;
  final bool pinned;
  final WorkspaceHostApps hostApps;
  final RecoveryIssue? recovery;
  final VoidCallback? onSelect;
  final ValueChanged<SidebarThreadAction> onAction;

  /// 触控输入模式：快捷操作常显，命中区放大到 44px；桌面使用 30px 的紧凑
  /// 操作槽，避免三个连续图标之间出现过宽留白。由侧栏按最近指针输入对
  /// 整个侧栏统一判定。
  final bool touchMode;

  @override
  Widget build(BuildContext context) {
    final issue = recovery;
    final blocked = issue?.blocksAccess ?? false;
    // Only worktree diagnostics lose their archive veto. Other recovery
    // blockers and the original Workspace action's admission remain intact.
    final archiveBlocked =
        blocked &&
        !(issue?.category == RecoveryCategory.repository &&
            issue?.worktree != null);
    final l10n = context.l10n;
    // 会话操作共享同一槽位与图标尺寸：桌面收紧视觉间距，触控仍保留
    // 44px 命中区；菜单触发器也复用同一尺寸，保持操作区密度一致。
    final actionTarget = touchMode ? 44.0 : 30.0;
    // 会话级打开入口的完整目标：本地用工作区路径，远端带 Host 别名前缀。
    final alias = project.sshAlias;
    final targetDescription = alias == null
        ? thread.workspacePath
        : '$alias:${thread.workspacePath}';
    // 状态标识与三个操作按钮共用同一网格：没有工作树或空闲状态时不保留
    // 空槽；存在多个标识时按工作树、运行状态的顺序排列，视觉中心始终等距。
    Widget statusSlot(Widget child) => SizedBox.square(
      dimension: actionTarget,
      child: Center(child: child),
    );

    final statusIndicators = <Widget>[
      if (thread.workspaceMode == ThreadWorkspaceMode.worktree)
        statusSlot(
          Tooltip(
            message: l10n.sidebarSessionWorktree,
            child: Icon(
              Icons.account_tree_outlined,
              key: StudioDriverKeys.threadWorkspaceMode(thread.id),
              size: 16,
            ),
          ),
        ),
      if (issue != null)
        statusSlot(
          Icon(Icons.error_outline, size: 18, color: context.colors.error),
        )
      else if (thread.status != ThreadStatus.idle)
        statusSlot(ShellThreadStatusIndicator(status: thread.status)),
    ];
    final statusArea = Row(
      mainAxisSize: MainAxisSize.min,
      children: statusIndicators,
    );
    final Widget tile = SidebarCompactTile(
      selected: selected,
      title: thread.title,
      onTap: !blocked ? onSelect : null,
      trailing: statusArea,
      touchMode: touchMode,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          sidebarTileIconButton(
            key: StudioDriverKeys.pinThread(thread.id),
            tooltip: pinned ? l10n.sidebarUnpin : l10n.sidebarPin,
            icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
            iconSize: 18,
            minTarget: actionTarget,
            onPressed: () => onAction(SidebarThreadAction.pin),
          ),
          SizedBox.square(
            dimension: actionTarget,
            child: _SidebarMenu(
              menuKey: StudioDriverKeys.threadMenu(thread.id),
              tooltip: l10n.sessionMoreActionsTooltip,
              // 受控紧凑宽度需要约束横轴；默认 UnconstrainedBox 会让长路径撑开内容。
              crossAxisUnconstrained: false,
              style: const MenuStyle(
                maximumSize: WidgetStatePropertyAll(Size(360, double.infinity)),
              ),
              children: [
                if (issue?.canRetry == true)
                  MenuItemButton(
                    key: StudioDriverKeys.retryRecoveryIssue(issue!.id),
                    overflowAxis: Axis.vertical,
                    onPressed: () =>
                        onAction(SidebarThreadAction.retryRecovery),
                    child: Text(l10n.runtimeFatalRetry),
                  ),
                MenuItemButton(
                  overflowAxis: Axis.vertical,
                  onPressed: () => onAction(SidebarThreadAction.pin),
                  child: Text(pinned ? l10n.sidebarUnpin : l10n.sidebarPin),
                ),
                MenuItemButton(
                  key: StudioDriverKeys.renameThread(thread.id),
                  overflowAxis: Axis.vertical,
                  onPressed: blocked
                      ? null
                      : () => onAction(SidebarThreadAction.rename),
                  child: Text(l10n.sidebarRenameSession),
                ),
                MenuItemButton(
                  key: ValueKey('thread-menu-archive-${thread.id}'),
                  overflowAxis: Axis.vertical,
                  onPressed: archiveBlocked
                      ? null
                      : () => onAction(SidebarThreadAction.archive),
                  child: Text(l10n.sidebarArchiveSession),
                ),
                MenuItemButton(
                  key: StudioDriverKeys.copyThreadWorkspace(thread.id),
                  overflowAxis: Axis.vertical,
                  onPressed: () => onAction(SidebarThreadAction.copyPath),
                  child: Text(l10n.sidebarCopyPath),
                ),
                const Divider(
                  key: ValueKey('thread-menu-workspace'),
                  height: 1,
                ),
                SubmenuButton(
                  key: StudioDriverKeys.openThreadWorkspace(thread.id),
                  leadingIcon: const Icon(Icons.open_in_new, size: 18),
                  menuChildren: [
                    _hostItem(
                      context,
                      StudioDriverKeys.openThreadVsCode(thread.id),
                      SidebarThreadAction.vsCode,
                      hostApps.vsCode,
                      hostApps.vsCodeImage,
                      Icons.code,
                      l10n.sessionOpenInVsCode,
                      l10n.sessionVsCodeUnavailable,
                      targetDescription,
                    ),
                    _hostItem(
                      context,
                      StudioDriverKeys.openThreadZed(thread.id),
                      SidebarThreadAction.zed,
                      hostApps.zed,
                      hostApps.zedImage,
                      Icons.code,
                      l10n.sessionOpenInZed,
                      l10n.sessionZedUnavailable,
                      targetDescription,
                    ),
                    _hostItem(
                      context,
                      StudioDriverKeys.openThreadTerminal(thread.id),
                      SidebarThreadAction.terminal,
                      hostApps.terminal,
                      hostApps.terminalImage,
                      Icons.terminal,
                      l10n.sessionOpenInTerminal,
                      _terminalUnavailableReason(context),
                      targetDescription,
                    ),
                  ],
                  child: Tooltip(
                    message: '${l10n.sessionOpenWith}\n$targetDescription',
                    child: Text(l10n.sessionOpenWith),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return KeyedSubtree(
      key: StudioDriverKeys.threadRow(thread.id),
      child: issue == null
          ? SidebarHoverDetail(
              detailBuilder: (context) => _threadDetailCard(context),
              child: tile,
            )
          : Tooltip(message: issue.message, child: tile),
    );
  }

  /// 会话菜单二级入口中的应用条目；不可用时禁用并说明原因，悬停与读屏
  /// 可获取完整打开目标。布局完全交给 Material [MenuItemButton]，菜单行
  /// 只显示应用图标与操作名称。
  Widget _hostItem(
    BuildContext context,
    Key key,
    SidebarThreadAction action,
    bool available,
    ImageProvider? image,
    IconData fallback,
    String label,
    String unavailable,
    String targetDescription,
  ) {
    final message = available
        ? '$label\n$targetDescription'
        : '$label\n$targetDescription\n$unavailable';
    return MenuItemButton(
      key: key,
      semanticsLabel: message,
      leadingIcon: HostAppLogo(image: image, fallback: fallback),
      onPressed: available ? () => onAction(action) : null,
      child: Tooltip(
        message: message,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _threadDetailCard(BuildContext context) {
    final l10n = context.l10n;
    final alias = project.sshAlias;
    final environment = alias == null ? l10n.sidebarLocal : 'SSH · $alias';
    final statusLabel = context.threadStatusLabel(thread.status);
    final updated = sidebarRelativeUpdatedLabel(
      context,
      DateTime.fromMillisecondsSinceEpoch(thread.updatedAt * 1000),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 详情卡内部可滚动，完整展示 canonical 标题（含 80 字 CJK 长标题）；
        // 截断只发生在行内单行渲染。
        Text(
          thread.title,
          style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SidebarDetailRow(
          leading: Icon(
            Icons.folder_outlined,
            size: 15,
            color: context.colors.onSurfaceVariant,
          ),
          value: project.name,
        ),
        SidebarDetailRow(
          leading: Icon(
            alias == null ? Icons.computer_outlined : Icons.dns_outlined,
            size: 15,
            color: context.colors.onSurfaceVariant,
          ),
          value: environment,
        ),
        SidebarDetailRow(
          leading: Icon(
            Icons.folder_open_outlined,
            size: 15,
            color: context.colors.onSurfaceVariant,
          ),
          value: thread.workspacePath,
          monospace: true,
        ),
        SidebarDetailRow(
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: _statusDotColor(context),
              shape: BoxShape.circle,
            ),
            child: const SizedBox.square(dimension: 8),
          ),
          value: '$statusLabel · $updated',
        ),
      ],
    );
  }

  Color _statusDotColor(BuildContext context) => switch (thread.status) {
    ThreadStatus.faulted => context.colors.error,
    ThreadStatus.waitingInteraction => context.statusColors.warning,
    ThreadStatus.queued ||
    ThreadStatus.running ||
    ThreadStatus.waitingTool ||
    ThreadStatus.cancelling ||
    ThreadStatus.closing => context.statusColors.activeIndicator,
    ThreadStatus.idle || ThreadStatus.closed =>
      context.colors.onSurfaceVariant.withValues(alpha: 0.6),
  };
}

/// 终端不可用的原因按宿主终端入口说明，不猜测其他已安装终端；
/// 页眉菜单与侧栏会话菜单共用同一判定。
String _terminalUnavailableReason(BuildContext context) {
  if (isWindowsPlatform) {
    return context.l10n.sessionTerminalUnavailableWindows;
  }
  if (isLinuxPlatform) {
    return context.l10n.sessionTerminalUnavailableLinux;
  }
  return context.l10n.sessionTerminalUnavailableGeneric;
}

/// 侧栏行内更多菜单：Material [MenuAnchor] + [IconButton] 触发器，锚定与
/// 键盘交互为框架行为。触发按钮与 [MenuAnchor.childFocusNode] 共用同一
/// [FocusNode]，焦点转移和恢复交给框架。
class _SidebarMenu extends StatefulWidget {
  const _SidebarMenu({
    required this.menuKey,
    required this.tooltip,
    required this.children,
    this.crossAxisUnconstrained,
    this.style,
  });
  final Key menuKey;
  final String tooltip;
  final List<Widget> children;
  final bool? crossAxisUnconstrained;
  final MenuStyle? style;

  @override
  State<_SidebarMenu> createState() => _SidebarMenuState();
}

class _SidebarMenuState extends State<_SidebarMenu> {
  final _controller = MenuController();
  final _focus = FocusNode(debugLabel: 'sidebar-row-menu');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    key: widget.menuKey,
    controller: _controller,
    childFocusNode: _focus,
    crossAxisUnconstrained: widget.crossAxisUnconstrained ?? true,
    style: widget.style,
    alignmentOffset: const Offset(6, 6),
    menuChildren: widget.children,
    child: IconButton(
      focusNode: _focus,
      tooltip: widget.tooltip,
      onPressed: () =>
          _controller.isOpen ? _controller.close() : _controller.open(),
      visualDensity: VisualDensity.standard,
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz, size: 18),
    ),
  );
}
