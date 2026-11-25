part of 'studio_sidebar.dart';

/// 侧栏行内快捷操作按钮：桌面 32px、触控 44px 真实命中区。
///
/// 全局主题是 `VisualDensity.compact`，这里显式 standard 防止 constraints
/// 被每边减 4（compact 会把 44 缩到 36/40、32 缩到 24）；shrinkWrap 不
/// 膨胀到默认 48，保持单行密度与标题宽度稳定。
Widget _tileIconButton({
  Key? key,
  required String tooltip,
  required IconData icon,
  Color? color,
  double iconSize = 16,
  double minTarget = 32,
  VoidCallback? onPressed,
}) {
  return IconButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: iconSize, color: color),
    visualDensity: VisualDensity.standard,
    style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    padding: EdgeInsets.zero,
    constraints: BoxConstraints(minWidth: minTarget, minHeight: minTarget),
  );
}

const _sidebarMenuStyle = MenuStyle(
  maximumSize: WidgetStatePropertyAll(Size(360, double.infinity)),
);

ButtonStyle _sidebarMenuButtonStyle(double target) => IconButton.styleFrom(
  minimumSize: Size.square(target),
  maximumSize: Size.square(target),
  visualDensity: VisualDensity.standard,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  padding: EdgeInsets.zero,
);

/// 侧栏项目行的更多菜单。共享触发器负责锚定、键盘交互与焦点恢复。
class SidebarProjectMenu extends StatelessWidget {
  const SidebarProjectMenu({
    super.key,
    required this.menuKey,
    this.minTarget = 32,
    required this.pinned,
    this.recoveryIssueId,
    this.canRetryRecovery = false,
    required this.onAction,
  });

  final Key menuKey;
  final double minTarget;
  final bool pinned;
  final String? recoveryIssueId;
  final bool canRetryRecovery;
  final FutureOr<void> Function(SidebarProjectAction action) onAction;

  void _select(SidebarProjectAction action) {
    final result = onAction(action);
    if (result is Future<void>) unawaited(result);
  }

  @override
  Widget build(BuildContext context) {
    return StudioMenuButton.icon(
      key: menuKey,
      tooltip: context.l10n.sidebarProjects,
      icon: const Icon(Icons.more_horiz, size: 18),
      buttonStyle: _sidebarMenuButtonStyle(minTarget),
      crossAxisUnconstrained: false,
      menuStyle: _sidebarMenuStyle,
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        if (canRetryRecovery && recoveryIssueId != null)
          MenuItemButton(
            key: ValueKey('project-retry-recovery-$recoveryIssueId'),
            overflowAxis: Axis.vertical,
            onPressed: () => _select(SidebarProjectAction.retryRecovery),
            child: Text(context.l10n.runtimeFatalRetry),
          ),
        MenuItemButton(
          overflowAxis: Axis.vertical,
          onPressed: () => _select(SidebarProjectAction.pin),
          child: Text(
            pinned ? context.l10n.sidebarUnpin : context.l10n.sidebarPin,
          ),
        ),
        MenuItemButton(
          overflowAxis: Axis.vertical,
          onPressed: () => _select(SidebarProjectAction.copyPath),
          child: Text(context.l10n.sidebarCopyPath),
        ),
        MenuItemButton(
          key: ValueKey('project-close'),
          overflowAxis: Axis.vertical,
          onPressed: () => _select(SidebarProjectAction.close),
          child: Text(context.l10n.sidebarCloseProject),
        ),
      ],
    );
  }
}

/// 侧栏会话行的更多菜单：重命名、归档、复制会话工作区路径，以及
/// 通过 Material [SubmenuButton] 承载的会话级打开方式入口（VS Code、Zed、
/// 终端；不可用时禁用并说明原因），并保留 recovery issue 的重试入口。
/// [StudioMenuButton] 和 [SubmenuButton] 负责锚定、二级菜单、键盘导航与焦点恢复。
class SidebarThreadMenu extends StatelessWidget {
  const SidebarThreadMenu({
    super.key,
    required this.row,
    required this.canRetryRecovery,
    this.recoveryIssueId,
    this.recoveryIssue,
    required this.blocked,
    required this.targetDescription,
    required this.hostApps,
    required this.minTarget,
    required this.onAction,
    this.removalPending = false,
  });

  final SessionDirectoryRow row;
  final bool canRetryRecovery;
  final String? recoveryIssueId;
  final StudioRecoveryIssue? recoveryIssue;
  final bool blocked;
  final String targetDescription;
  final SidebarHostApps hostApps;
  final double minTarget;
  final bool removalPending;
  final FutureOr<void> Function(SidebarThreadAction action) onAction;

  void _select(SidebarThreadAction action) {
    final result = onAction(action);
    if (result is Future<void>) unawaited(result);
  }

  @override
  Widget build(BuildContext context) {
    final issue = recoveryIssue;
    final blockReason = issue == null
        ? context.l10n.composerBlockedWorkspace
        : context.recoveryIssueLabel(issue);
    return SizedBox.square(
      dimension: minTarget,
      child: StudioMenuButton.icon(
        key: StudioDriverKeys.threadMenu(row.threadId),
        tooltip: MaterialLocalizations.of(context).showMenuTooltip,
        icon: const Icon(Icons.more_horiz, size: 18),
        buttonStyle: _sidebarMenuButtonStyle(minTarget),
        // 受控紧凑宽度需要约束横轴；默认 UnconstrainedBox 会让长路径撑开内容。
        crossAxisUnconstrained: false,
        menuStyle: _sidebarMenuStyle,
        alignmentOffset: const Offset(6, 6),
        menuChildren: [
          if (canRetryRecovery && recoveryIssueId != null)
            MenuItemButton(
              key: StudioDriverKeys.retryRecoveryIssue(recoveryIssueId!),
              overflowAxis: Axis.vertical,
              onPressed: () => _select(SidebarThreadAction.retryRecovery),
              child: Text(context.l10n.runtimeFatalRetry),
            ),
          MenuItemButton(
            key: StudioDriverKeys.renameThread(row.threadId),
            overflowAxis: Axis.vertical,
            onPressed: blocked
                ? null
                : () => _select(SidebarThreadAction.rename),
            child: Text(context.l10n.sidebarRenameSession),
          ),
          MenuItemButton(
            // 归档不依赖工作区访问状态；物理工作树检查与归档相互独立。
            key: StudioDriverKeys.archiveThread(row.threadId),
            overflowAxis: Axis.vertical,
            onPressed: removalPending
                ? null
                : () => _select(SidebarThreadAction.archive),
            child: Text(context.l10n.sidebarArchiveSession),
          ),
          MenuItemButton(
            key: StudioDriverKeys.deleteThread(row.threadId),
            style: removalPending
                ? null
                : ButtonStyle(
                    foregroundColor: WidgetStatePropertyAll(
                      context.colors.error,
                    ),
                  ),
            overflowAxis: Axis.vertical,
            onPressed: removalPending
                ? null
                : () => _select(SidebarThreadAction.delete),
            child: Text(context.l10n.sidebarDeleteSession),
          ),
          MenuItemButton(
            key: StudioDriverKeys.copyThreadWorkspace(row.threadId),
            overflowAxis: Axis.vertical,
            onPressed: row.workspacePath.isEmpty
                ? null
                : () => _select(SidebarThreadAction.copyWorkspace),
            child: Text(context.l10n.sidebarCopyPath),
          ),
          const Divider(key: ValueKey('thread-menu-workspace'), height: 1),
          SubmenuButton(
            key: StudioDriverKeys.openThreadWorkspace(row.threadId),
            leadingIcon: const Icon(Icons.open_in_new, size: 18),
            menuChildren: [
              workspaceOpenMenuItem(
                key: StudioDriverKeys.openThreadVsCode(row.threadId),
                icon: HostAppArtwork(
                  bytes: hostApps.vsCodeIcon,
                  fallback: Icons.code,
                ),
                label: context.l10n.sessionOpenInVsCode,
                targetDescription: targetDescription,
                available:
                    hostApps.vsCode && !blocked && row.workspacePath.isNotEmpty,
                unavailableReason: blocked
                    ? blockReason
                    : context.l10n.sessionVsCodeUnavailable,
                onActivated: () => _select(SidebarThreadAction.openVsCode),
              ),
              workspaceOpenMenuItem(
                key: StudioDriverKeys.openThreadZed(row.threadId),
                icon: HostAppArtwork(
                  bytes: hostApps.zedIcon,
                  fallback: Icons.code,
                ),
                label: context.l10n.sessionOpenInZed,
                targetDescription: targetDescription,
                available:
                    hostApps.zed && !blocked && row.workspacePath.isNotEmpty,
                unavailableReason: blocked
                    ? blockReason
                    : context.l10n.sessionZedUnavailable,
                onActivated: () => _select(SidebarThreadAction.openZed),
              ),
              workspaceOpenMenuItem(
                key: StudioDriverKeys.openThreadTerminal(row.threadId),
                icon: HostAppArtwork(
                  bytes: hostApps.terminalIcon,
                  fallback: Icons.terminal,
                ),
                label: context.l10n.sessionOpenInTerminal,
                targetDescription: targetDescription,
                available:
                    hostApps.terminal &&
                    !blocked &&
                    row.workspacePath.isNotEmpty,
                unavailableReason: blocked
                    ? blockReason
                    : hostApps.terminalUnavailableReason,
                onActivated: () => _select(SidebarThreadAction.openTerminal),
              ),
            ],
            child: Tooltip(
              message: '${context.l10n.sessionOpenWith}\n$targetDescription',
              child: Text(context.l10n.sessionOpenWith),
            ),
          ),
        ],
      ),
    );
  }
}

/// 会话页眉及侧栏打开菜单共用的应用条目；不可用时禁用并说明原因，
/// 悬停与读屏可获取完整打开目标。布局完全交给 Material
/// [MenuItemButton]，菜单行只显示应用图标与操作名称。
MenuItemButton workspaceOpenMenuItem({
  required Key key,
  required Widget icon,
  required String label,
  required String targetDescription,
  required bool available,
  required String unavailableReason,
  required VoidCallback onActivated,
}) {
  final message = available
      ? '$label\n$targetDescription'
      : '$label\n$targetDescription\n$unavailableReason';
  return MenuItemButton(
    key: key,
    semanticsLabel: message,
    leadingIcon: icon,
    onPressed: available ? onActivated : null,
    child: Tooltip(
      message: message,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}
