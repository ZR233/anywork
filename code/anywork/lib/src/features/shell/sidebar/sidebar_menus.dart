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

/// 侧栏项目行的更多菜单：Material [MenuAnchor] + [IconButton] 触发器，
/// 锚定与键盘交互为框架行为。触发按钮与 [MenuAnchor.childFocusNode]
/// 共用同一 [FocusNode]，焦点转移和恢复交给框架。
class SidebarProjectMenu extends StatefulWidget {
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

  @override
  State<SidebarProjectMenu> createState() => _SidebarProjectMenuState();
}

class _SidebarProjectMenuState extends State<SidebarProjectMenu> {
  final MenuController _controller = MenuController();
  final FocusNode _triggerFocus = FocusNode(debugLabel: 'project-menu-trigger');

  void _open() {
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _controller.open();
    }
  }

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  void _select(SidebarProjectAction action) {
    final result = widget.onAction(action);
    if (result is Future<void>) unawaited(result);
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      key: widget.menuKey,
      controller: _controller,
      childFocusNode: _triggerFocus,
      crossAxisUnconstrained: false,
      style: const MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(360, double.infinity)),
      ),
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        if (widget.canRetryRecovery && widget.recoveryIssueId != null)
          MenuItemButton(
            key: ValueKey('project-retry-recovery-${widget.recoveryIssueId}'),
            overflowAxis: Axis.vertical,
            onPressed: () => _select(SidebarProjectAction.retryRecovery),
            child: Text(context.l10n.runtimeFatalRetry),
          ),
        MenuItemButton(
          overflowAxis: Axis.vertical,
          onPressed: () => _select(SidebarProjectAction.pin),
          child: Text(
            widget.pinned ? context.l10n.sidebarUnpin : context.l10n.sidebarPin,
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
      child: IconButton(
        constraints: BoxConstraints.tightFor(
          width: widget.minTarget,
          height: widget.minTarget,
        ),
        tooltip: context.l10n.sidebarProjects,
        onPressed: _open,
        focusNode: _triggerFocus,
        visualDensity: VisualDensity.standard,
        style: const ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_horiz, size: 18),
      ),
    );
  }
}

/// 侧栏会话行的更多菜单：重命名、归档、复制会话工作区路径，以及
/// 通过 Material [SubmenuButton] 承载的会话级打开方式入口（VS Code、Zed、
/// 终端；不可用时禁用并说明原因），并保留 recovery issue 的重试入口。
/// Material [MenuAnchor] 和 [SubmenuButton] 负责锚定、二级菜单、键盘导航
/// 与焦点恢复，与页眉菜单共用同一套打开实现，不新增后端能力。
/// 触发按钮与 [MenuAnchor.childFocusNode] 共用同一 [FocusNode]。
class SidebarThreadMenu extends StatefulWidget {
  const SidebarThreadMenu({
    super.key,
    required this.thread,
    required this.canRetryRecovery,
    this.recoveryIssueId,
    this.recoveryIssue,
    required this.blocked,
    required this.targetDescription,
    required this.hostApps,
    required this.minTarget,
    required this.onAction,
  });

  final StudioThread thread;
  final bool canRetryRecovery;
  final String? recoveryIssueId;
  final StudioRecoveryIssue? recoveryIssue;
  final bool blocked;
  final String targetDescription;
  final SidebarHostApps hostApps;
  final double minTarget;
  final FutureOr<void> Function(SidebarThreadAction action) onAction;

  @override
  State<SidebarThreadMenu> createState() => _SidebarThreadMenuState();
}

class _SidebarThreadMenuState extends State<SidebarThreadMenu> {
  final MenuController _controller = MenuController();
  final FocusNode _triggerFocus = FocusNode(debugLabel: 'thread-menu-trigger');

  void _open() {
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _controller.open();
    }
  }

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  void _select(SidebarThreadAction action) {
    final result = widget.onAction(action);
    if (result is Future<void>) unawaited(result);
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final blockReason = widget.recoveryIssue == null
        ? context.l10n.composerBlockedWorkspace
        : context.recoveryIssueLabel(widget.recoveryIssue!);
    return SizedBox.square(
      dimension: widget.minTarget,
      child: MenuAnchor(
        key: StudioDriverKeys.threadMenu(thread.id),
        controller: _controller,
        childFocusNode: _triggerFocus,
        // 受控紧凑宽度需要约束横轴；默认 UnconstrainedBox 会让长路径撑开内容。
        crossAxisUnconstrained: false,
        style: const MenuStyle(
          maximumSize: WidgetStatePropertyAll(Size(360, double.infinity)),
        ),
        alignmentOffset: const Offset(6, 6),
        menuChildren: [
          if (widget.canRetryRecovery && widget.recoveryIssueId != null)
            MenuItemButton(
              key: StudioDriverKeys.retryRecoveryIssue(widget.recoveryIssueId!),
              overflowAxis: Axis.vertical,
              onPressed: () => _select(SidebarThreadAction.retryRecovery),
              child: Text(context.l10n.runtimeFatalRetry),
            ),
          MenuItemButton(
            key: StudioDriverKeys.renameThread(thread.id),
            overflowAxis: Axis.vertical,
            onPressed: widget.blocked
                ? null
                : () => _select(SidebarThreadAction.rename),
            child: Text(context.l10n.sidebarRenameSession),
          ),
          MenuItemButton(
            // 归档不依赖工作区访问状态；物理工作树检查与归档相互独立。
            key: StudioDriverKeys.archiveThread(thread.id),
            overflowAxis: Axis.vertical,
            onPressed: () => _select(SidebarThreadAction.archive),
            child: Text(context.l10n.sidebarArchiveSession),
          ),
          MenuItemButton(
            key: StudioDriverKeys.deleteThread(thread.id),
            leadingIcon: const Icon(Icons.delete_outline, size: 18),
            style: ButtonStyle(
              foregroundColor: WidgetStatePropertyAll(context.colors.error),
            ),
            overflowAxis: Axis.vertical,
            onPressed: () => _select(SidebarThreadAction.delete),
            child: Text(context.l10n.sidebarDeleteSession),
          ),
          MenuItemButton(
            key: StudioDriverKeys.copyThreadWorkspace(thread.id),
            overflowAxis: Axis.vertical,
            onPressed: thread.workspacePath.isEmpty
                ? null
                : () => _select(SidebarThreadAction.copyWorkspace),
            child: Text(context.l10n.sidebarCopyPath),
          ),
          const Divider(key: ValueKey('thread-menu-workspace'), height: 1),
          SubmenuButton(
            key: StudioDriverKeys.openThreadWorkspace(thread.id),
            leadingIcon: const Icon(Icons.open_in_new, size: 18),
            menuChildren: [
              _workspaceMenuEntry(
                key: StudioDriverKeys.openThreadVsCode(thread.id),
                icon: HostAppArtwork(
                  bytes: widget.hostApps.vsCodeIcon,
                  fallback: Icons.code,
                ),
                label: context.l10n.sessionOpenInVsCode,
                targetDescription: widget.targetDescription,
                available:
                    widget.hostApps.vsCode &&
                    !widget.blocked &&
                    thread.workspacePath.isNotEmpty,
                unavailableReason: widget.blocked
                    ? blockReason
                    : context.l10n.sessionVsCodeUnavailable,
                onActivated: () => _select(SidebarThreadAction.openVsCode),
              ),
              _workspaceMenuEntry(
                key: StudioDriverKeys.openThreadZed(thread.id),
                icon: HostAppArtwork(
                  bytes: widget.hostApps.zedIcon,
                  fallback: Icons.code,
                ),
                label: context.l10n.sessionOpenInZed,
                targetDescription: widget.targetDescription,
                available:
                    widget.hostApps.zed &&
                    !widget.blocked &&
                    thread.workspacePath.isNotEmpty,
                unavailableReason: widget.blocked
                    ? blockReason
                    : context.l10n.sessionZedUnavailable,
                onActivated: () => _select(SidebarThreadAction.openZed),
              ),
              _workspaceMenuEntry(
                key: StudioDriverKeys.openThreadTerminal(thread.id),
                icon: HostAppArtwork(
                  bytes: widget.hostApps.terminalIcon,
                  fallback: Icons.terminal,
                ),
                label: context.l10n.sessionOpenInTerminal,
                targetDescription: widget.targetDescription,
                available:
                    widget.hostApps.terminal &&
                    !widget.blocked &&
                    thread.workspacePath.isNotEmpty,
                unavailableReason: widget.blocked
                    ? blockReason
                    : widget.hostApps.terminalUnavailableReason,
                onActivated: () => _select(SidebarThreadAction.openTerminal),
              ),
            ],
            child: Tooltip(
              message:
                  '${context.l10n.sessionOpenWith}\n${widget.targetDescription}',
              child: Text(context.l10n.sessionOpenWith),
            ),
          ),
        ],
        child: IconButton(
          tooltip: MaterialLocalizations.of(context).showMenuTooltip,
          constraints: BoxConstraints.tightFor(
            width: widget.minTarget,
            height: widget.minTarget,
          ),
          onPressed: _open,
          focusNode: _triggerFocus,
          visualDensity: VisualDensity.standard,
          style: const ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_horiz, size: 18),
        ),
      ),
    );
  }
}

/// 侧栏会话菜单二级入口中的应用条目；不可用时禁用并说明原因，
/// 悬停与读屏可获取完整打开目标。布局完全交给 Material
/// [MenuItemButton]，菜单行只显示应用图标与操作名称。
Widget _workspaceMenuEntry({
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
