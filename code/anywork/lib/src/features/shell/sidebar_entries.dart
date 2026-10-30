part of 'studio_shell.dart';

/// 侧栏项目行：折叠箭头、文件夹、项目名、真实本地/SSH 标识、常驻新建
/// 与更多菜单。完整路径不再常驻占用辅助行，悬停时在只读浮层中查看，
/// 通过更多菜单复制；存在 recovery issue 时诊断提示优先。
class _ProjectTile extends ConsumerWidget {
  const _ProjectTile({
    required this.project,
    required this.selected,
    required this.expanded,
    required this.onToggle,
    this.onNavigate,
    required this.recoveryIssue,
    this.touchMode = false,
  });
  final StudioProject project;
  final bool selected;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onNavigate;
  final StudioRecoveryIssue? recoveryIssue;

  /// 触控输入模式：名称命中区按触控密度放大，与 `_SidebarState` 的
  /// 全侧栏输入模式一致。
  final bool touchMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issue = recoveryIssue;
    if (issue != null) {
      // 诊断提示优先：存在 recovery issue 时只保留名称区 Tooltip，不展示详情卡。
      return _buildRow(
        context,
        ref,
        nameTooltip: context.recoveryIssueLabel(issue),
      );
    }
    // 只读详情锚定整行；浮层忽略指针，不挡住新建/更多按钮。
    return _SidebarHoverDetail(
      detailBuilder: (_) => _projectDetailCard(context),
      child: _buildRow(context, ref),
    );
  }

  /// 构建整行（折叠箭头、名称、常驻新建与更多菜单）。详情宿主/诊断 Tooltip
  /// 由调用方决定，本方法只返回行内控件与 `projectRow` 键。
  Widget _buildRow(BuildContext context, WidgetRef ref, {String? nameTooltip}) {
    final general = ref.watch(shellGeneralProvider);
    final nameArea = _buildProjectNameArea(context, ref);
    return KeyedSubtree(
      key: StudioDriverKeys.projectRow(project.id),
      child: Row(
        children: [
          _tileIconButton(
            key: StudioDriverKeys.projectExpand(project.id),
            tooltip: context.l10n.sidebarProjects,
            icon: expanded ? Icons.expand_more : Icons.chevron_right,
            iconSize: 18,
            minTarget: touchMode ? 44 : 32,
            onPressed: onToggle,
          ),
          Expanded(
            child: nameTooltip == null
                ? nameArea
                : Tooltip(message: nameTooltip, child: nameArea),
          ),
          _tileIconButton(
            key: StudioDriverKeys.projectNewSession(project.id),
            tooltip: '${context.l10n.sidebarNewSession} · ${project.name}',
            icon: Icons.add,
            iconSize: 18,
            minTarget: touchMode ? 44 : 32,
            onPressed: recoveryIssue?.blocksAccess != true
                ? () async {
                    final commands = ref
                        .read(anyworkClientProvider)
                        .directoryCommands;
                    await commands.beginNewThread(workspaceId: project.id);
                    if (!context.mounted) return;
                    onNavigate?.call();
                  }
                : null,
          ),
          SizedBox.square(
            dimension: touchMode ? 44 : 32,
            child: _ProjectMenuButton(
              menuKey: StudioDriverKeys.projectMenu(project.id),
              pinned: general.pinnedProjectIds.contains(project.id),
              recoveryIssueId:
                  recoveryIssue?.scope == RecoveryIssueScope.project
                  ? recoveryIssue?.id
                  : null,
              canRetryRecovery:
                  recoveryIssue?.scope == RecoveryIssueScope.project &&
                  recoveryIssue?.canRetry == true,
              onAction: (action) async {
                if (action == 'retry') {
                  await ref
                      .read(anyworkClientProvider)
                      .directoryCommands
                      .retryRecovery();
                }
                if (action == 'pin') {
                  await _saveSidebarPreferences(
                    ref,
                    general: general,
                    workspaceId: project.id,
                  );
                }
                if (action == 'copy') {
                  await Clipboard.setData(ClipboardData(text: project.path));
                }
                if (action == 'close') {
                  await ref
                      .read(anyworkClientProvider)
                      .directoryCommands
                      .archiveProject(project.id);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectNameArea(BuildContext context, WidgetRef ref) {
    final issue = recoveryIssue;
    return InkWell(
      onTap: issue?.blocksAccess != true
          ? () async {
              await ref
                  .read(anyworkClientProvider)
                  .directoryCommands
                  .selectProject(project.id);
              onNavigate?.call();
            }
          : null,
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
              project.sshAlias == null ? context.l10n.sidebarLocal : 'SSH',
              style: context.text.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectDetailCard(BuildContext context) {
    final alias = project.sshAlias;
    final environment = alias == null
        ? context.l10n.sidebarLocal
        : 'SSH · $alias';
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
        _SidebarDetailRow(
          leading: Icon(
            alias == null ? Icons.computer_outlined : Icons.dns_outlined,
            size: 15,
            color: context.colors.onSurfaceVariant,
          ),
          value: environment,
        ),
        _SidebarDetailRow(
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

/// 侧栏会话行：紧凑单行标题，右侧固定状态区（会话工作树标识与行级
/// canonical 运行状态），悬停或聚焦时出现置顶快捷操作与更多菜单，并展示
/// 完整标题、项目、环境、会话工作区路径与状态时间的悬浮
/// 详情。每行的状态只读自己的 [StudioThread.status]。
class _ThreadTile extends ConsumerWidget {
  const _ThreadTile({
    required this.thread,
    required this.project,
    required this.selected,
    required this.recoveryIssue,
    this.onNavigate,
    this.touchMode = false,
  });

  final StudioThread thread;
  final StudioProject project;
  final bool selected;
  final StudioRecoveryIssue? recoveryIssue;
  final VoidCallback? onNavigate;

  /// 触控输入模式：快捷操作常显，命中区放大到 44px；桌面使用 30px 的紧凑
  /// 操作槽，避免三个连续图标之间出现过宽留白。由 `_SidebarState` 按最近
  /// 指针输入对整个侧栏统一判定。
  final bool touchMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issue = recoveryIssue;
    final blocked = issue?.blocksAccess ?? false;
    final general = ref.watch(shellGeneralProvider);
    final pinned = general.pinnedThreadIds.contains(thread.id);
    final vsCodeAvailable =
        ref.watch(vsCodeAvailabilityProvider).value ?? false;
    final zedAvailable = ref.watch(zedAvailabilityProvider).value ?? false;
    final terminalAvailable =
        ref.watch(terminalAvailabilityProvider).value ?? false;
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
      if (thread.workspaceMode.isWorktree)
        statusSlot(
          Tooltip(
            message: context.l10n.sidebarSessionWorktree,
            child: Icon(
              Icons.account_tree_outlined,
              key: StudioDriverKeys.threadWorkspaceMode(thread.id),
              size: 16,
            ),
          ),
        ),
      if (thread.status != ThreadStatusView.idle)
        statusSlot(_ThreadStatusBadge(status: thread.status)),
      if (issue != null) statusSlot(RecoveryIssueIndicator(issue: issue)),
    ];
    final statusArea = Row(
      mainAxisSize: MainAxisSize.min,
      children: statusIndicators,
    );
    Widget tile() => _SidebarTile(
      selected: selected,
      title: thread.title,
      onTap: !blocked
          ? () async {
              await ref
                  .read(anyworkClientProvider)
                  .directoryCommands
                  .selectThread(thread.id);
              onNavigate?.call();
            }
          : null,
      trailing: statusArea,
      touchMode: touchMode,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tileIconButton(
            key: StudioDriverKeys.pinThread(thread.id),
            tooltip: pinned
                ? context.l10n.sidebarUnpin
                : context.l10n.sidebarPin,
            icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
            iconSize: 18,
            minTarget: actionTarget,
            onPressed: () async {
              await _saveSidebarPreferences(
                ref,
                general: general,
                threadId: thread.id,
              );
            },
          ),
          _ThreadMenuButton(
            thread: thread,
            canRetryRecovery:
                issue?.scope == RecoveryIssueScope.thread &&
                issue?.canRetry == true,
            recoveryIssueId: issue?.scope == RecoveryIssueScope.thread
                ? issue?.id
                : null,
            recoveryIssue: issue,
            pinned: pinned,
            blocked: blocked,
            targetDescription: targetDescription,
            vsCodeAvailable: vsCodeAvailable,
            zedAvailable: zedAvailable,
            terminalAvailable: terminalAvailable,
            minTarget: actionTarget,
            onAction: (action) async {
              if (action == 'retry') {
                await ref
                    .read(anyworkClientProvider)
                    .directoryCommands
                    .retryRecovery();
              }
              if (action == 'pin') {
                await _saveSidebarPreferences(
                  ref,
                  general: general,
                  threadId: thread.id,
                );
              }
              if (action == 'rename' && context.mounted) {
                await _renameThreadFromSidebar(context, ref, thread);
              }
              if (action == 'archive' && context.mounted) {
                await _archiveThreadFromSidebar(context, ref, thread.id);
              }
              if (action == 'copy-workspace') {
                await Clipboard.setData(
                  ClipboardData(text: thread.workspacePath),
                );
              }
              if (action == 'open-vscode' && context.mounted) {
                await _openThreadWorkspaceInVsCode(
                  context,
                  ref,
                  project,
                  thread,
                );
              }
              if (action == 'open-zed' && context.mounted) {
                await _openThreadWorkspaceInZed(context, ref, project, thread);
              }
              if (action == 'open-terminal' && context.mounted) {
                await _openThreadWorkspaceInTerminal(
                  context,
                  ref,
                  project,
                  thread,
                );
              }
            },
          ),
        ],
      ),
    );
    return KeyedSubtree(
      key: StudioDriverKeys.threadRow(thread.id),
      child: issue == null
          ? _SidebarHoverDetail(
              detailBuilder: (detailContext) =>
                  _threadDetailCard(detailContext),
              child: tile(),
            )
          : Tooltip(message: context.recoveryIssueLabel(issue), child: tile()),
    );
  }

  Widget _threadDetailCard(BuildContext context) {
    final alias = project.sshAlias;
    final environment = alias == null
        ? context.l10n.sidebarLocal
        : 'SSH · $alias';
    final statusLabel = context.threadStatusLabel(thread.status);
    final updated = _relativeUpdatedLabel(context, thread.updatedAt);
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
        _SidebarDetailRow(
          leading: Icon(
            Icons.folder_outlined,
            size: 15,
            color: context.colors.onSurfaceVariant,
          ),
          value: project.isStandalone
              ? context.l10n.sidebarStandaloneSessions
              : project.name,
        ),
        _SidebarDetailRow(
          leading: Icon(
            alias == null ? Icons.computer_outlined : Icons.dns_outlined,
            size: 15,
            color: context.colors.onSurfaceVariant,
          ),
          value: environment,
        ),
        _SidebarDetailRow(
          leading: Icon(
            Icons.folder_open_outlined,
            size: 15,
            color: context.colors.onSurfaceVariant,
          ),
          value: thread.workspacePath,
          monospace: true,
        ),
        _SidebarDetailRow(
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
    ThreadStatusView.faulted => context.colors.error,
    ThreadStatusView.waitingInteraction => context.statusColors.warning,
    ThreadStatusView.queued ||
    ThreadStatusView.running ||
    ThreadStatusView.waitingTool ||
    ThreadStatusView.cancelling ||
    ThreadStatusView.closing => context.statusColors.activeIndicator,
    ThreadStatusView.idle || ThreadStatusView.closed =>
      context.colors.onSurfaceVariant.withValues(alpha: 0.6),
  };
}

/// 侧栏行内快捷操作按钮：桌面 32px、触控 44px 真实命中区。
///
/// 全局主题是 `VisualDensity.compact`，这里显式 standard 防止 constraints
/// 被每边减 4（compact 会把 44 缩到 36/40、32 缩到 24）；shrinkWrap 不
/// 膨胀到默认 48，保持单行密度与标题宽度稳定。
Widget _tileIconButton({
  Key? key,
  required String tooltip,
  required IconData icon,
  double iconSize = 16,
  double minTarget = 32,
  VoidCallback? onPressed,
}) {
  return IconButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: iconSize),
    visualDensity: VisualDensity.standard,
    style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    padding: EdgeInsets.zero,
    constraints: BoxConstraints(minWidth: minTarget, minHeight: minTarget),
  );
}

/// 侧栏项目行的更多菜单：Material [MenuAnchor] + [IconButton] 触发器，
/// 锚定与键盘交互为框架行为。触发按钮与 [MenuAnchor.childFocusNode]
/// 共用同一 [FocusNode]，焦点转移和恢复交给框架。
class _ProjectMenuButton extends StatefulWidget {
  const _ProjectMenuButton({
    required this.menuKey,
    required this.pinned,
    this.recoveryIssueId,
    this.canRetryRecovery = false,
    required this.onAction,
  });

  final Key menuKey;
  final bool pinned;
  final String? recoveryIssueId;
  final bool canRetryRecovery;
  final FutureOr<void> Function(String action) onAction;

  @override
  State<_ProjectMenuButton> createState() => _ProjectMenuButtonState();
}

class _ProjectMenuButtonState extends State<_ProjectMenuButton> {
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

  void _select(String action) {
    final result = widget.onAction(action);
    if (result is Future<void>) unawaited(result);
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      key: widget.menuKey,
      controller: _controller,
      childFocusNode: _triggerFocus,
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        if (widget.canRetryRecovery && widget.recoveryIssueId != null)
          MenuItemButton(
            key: ValueKey('project-retry-recovery-${widget.recoveryIssueId}'),
            overflowAxis: Axis.vertical,
            onPressed: () => _select('retry'),
            child: Text(context.l10n.runtimeFatalRetry),
          ),
        MenuItemButton(
          overflowAxis: Axis.vertical,
          onPressed: () => _select('pin'),
          child: Text(
            widget.pinned ? context.l10n.sidebarUnpin : context.l10n.sidebarPin,
          ),
        ),
        MenuItemButton(
          overflowAxis: Axis.vertical,
          onPressed: () => _select('copy'),
          child: Text(context.l10n.sidebarCopyPath),
        ),
        MenuItemButton(
          key: ValueKey('project-close'),
          overflowAxis: Axis.vertical,
          onPressed: () => _select('close'),
          child: Text(context.l10n.sidebarCloseProject),
        ),
      ],
      child: IconButton(
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

/// 侧栏会话行的更多菜单：置顶、重命名、归档、复制会话工作区路径，以及
/// 通过 Material [SubmenuButton] 承载的会话级打开方式入口（VS Code、Zed、
/// 终端；不可用时禁用并说明原因），并保留 recovery issue 的重试入口。
/// Material [MenuAnchor] 和 [SubmenuButton] 负责锚定、二级菜单、键盘导航
/// 与焦点恢复，与页眉菜单共用同一套打开实现，不新增后端能力。
/// 触发按钮与 [MenuAnchor.childFocusNode] 共用同一 [FocusNode]。
class _ThreadMenuButton extends StatefulWidget {
  const _ThreadMenuButton({
    required this.thread,
    required this.canRetryRecovery,
    this.recoveryIssueId,
    this.recoveryIssue,
    required this.pinned,
    required this.blocked,
    required this.targetDescription,
    required this.vsCodeAvailable,
    required this.zedAvailable,
    required this.terminalAvailable,
    required this.minTarget,
    required this.onAction,
  });

  final StudioThread thread;
  final bool canRetryRecovery;
  final String? recoveryIssueId;
  final StudioRecoveryIssue? recoveryIssue;
  final bool pinned;
  final bool blocked;
  final String targetDescription;
  final bool vsCodeAvailable;
  final bool zedAvailable;
  final bool terminalAvailable;
  final double minTarget;
  final FutureOr<void> Function(String action) onAction;

  @override
  State<_ThreadMenuButton> createState() => _ThreadMenuButtonState();
}

class _ThreadMenuButtonState extends State<_ThreadMenuButton> {
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

  void _select(String action) {
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
              onPressed: () => _select('retry'),
              child: Text(context.l10n.runtimeFatalRetry),
            ),
          MenuItemButton(
            overflowAxis: Axis.vertical,
            onPressed: () => _select('pin'),
            child: Text(
              widget.pinned
                  ? context.l10n.sidebarUnpin
                  : context.l10n.sidebarPin,
            ),
          ),
          MenuItemButton(
            key: StudioDriverKeys.renameThread(thread.id),
            overflowAxis: Axis.vertical,
            onPressed: widget.blocked ? null : () => _select('rename'),
            child: Text(context.l10n.sidebarRenameSession),
          ),
          MenuItemButton(
            // 归档不依赖工作区访问状态；物理工作树检查与归档相互独立。
            key: ValueKey('thread-menu-archive-${thread.id}'),
            overflowAxis: Axis.vertical,
            onPressed: () => _select('archive'),
            child: Text(context.l10n.sidebarArchiveSession),
          ),
          MenuItemButton(
            key: StudioDriverKeys.copyThreadWorkspace(thread.id),
            overflowAxis: Axis.vertical,
            onPressed: () => _select('copy-workspace'),
            child: Text(context.l10n.sidebarCopyPath),
          ),
          const Divider(key: ValueKey('thread-menu-workspace'), height: 1),
          SubmenuButton(
            key: StudioDriverKeys.openThreadWorkspace(thread.id),
            leadingIcon: const Icon(Icons.open_in_new, size: 18),
            menuChildren: [
              _workspaceMenuEntry(
                key: StudioDriverKeys.openThreadVsCode(thread.id),
                icon: const HostAppLogo(
                  app: HostAppIcon.vsCode,
                  fallback: Icons.code,
                ),
                label: context.l10n.sessionOpenInVsCode,
                targetDescription: widget.targetDescription,
                available: widget.vsCodeAvailable && !widget.blocked,
                unavailableReason: widget.blocked
                    ? blockReason
                    : context.l10n.sessionVsCodeUnavailable,
                onActivated: () => _select('open-vscode'),
              ),
              _workspaceMenuEntry(
                key: StudioDriverKeys.openThreadZed(thread.id),
                icon: const HostAppLogo(
                  app: HostAppIcon.zed,
                  fallback: Icons.code,
                ),
                label: context.l10n.sessionOpenInZed,
                targetDescription: widget.targetDescription,
                available: widget.zedAvailable && !widget.blocked,
                unavailableReason: widget.blocked
                    ? blockReason
                    : context.l10n.sessionZedUnavailable,
                onActivated: () => _select('open-zed'),
              ),
              _workspaceMenuEntry(
                key: StudioDriverKeys.openThreadTerminal(thread.id),
                icon: const HostAppLogo(
                  app: HostAppIcon.terminal,
                  fallback: Icons.terminal,
                ),
                label: context.l10n.sessionOpenInTerminal,
                targetDescription: widget.targetDescription,
                available: widget.terminalAvailable && !widget.blocked,
                unavailableReason: widget.blocked
                    ? blockReason
                    : _terminalUnavailableReason(context),
                onActivated: () => _select('open-terminal'),
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

Future<void> _archiveThreadFromSidebar(
  BuildContext context,
  WidgetRef ref,
  String threadId,
) async {
  // 归档是破坏性动作：确认对话框是唯一入口，取消不产生任何副作用。
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.sidebarArchiveSessionConfirmTitle),
      content: Text(context.l10n.sidebarArchiveSessionConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          key: StudioDriverKeys.archiveThreadConfirm,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.sidebarArchiveSessionConfirmAction),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref
        .read(anyworkClientProvider)
        .threadCommands
        .archiveThread(threadId);
  } on Object catch (error) {
    if (!context.mounted) return;
    final message = switch (error) {
      StudioFailure(code: StudioFailureCode.busy) =>
        context.l10n.sidebarArchiveSessionBusy,
      StudioFailure(:final message, :final correlationId) =>
        context.l10n.sidebarArchiveSessionFailedReason(message, correlationId),
      _ => context.l10n.sidebarArchiveSessionFailed,
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<void> _renameThreadFromSidebar(
  BuildContext context,
  WidgetRef ref,
  StudioThread thread,
) async {
  final title = await showDialog<String>(
    context: context,
    builder: (context) => _RenameThreadDialog(thread: thread),
  );
  if (title == null || !context.mounted) return;
  try {
    await ref
        .read(anyworkClientProvider)
        .threadCommands
        .renameThread(thread.id, title);
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.sidebarRenameSessionFailed)),
    );
  }
}

class _RenameThreadDialog extends StatefulWidget {
  const _RenameThreadDialog({required this.thread});

  final StudioThread thread;

  @override
  State<_RenameThreadDialog> createState() => _RenameThreadDialogState();
}

class _RenameThreadDialogState extends State<_RenameThreadDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.thread.title,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _error = context.l10n.sidebarRenameSessionEmpty);
      return;
    }
    if (title.runes.length > 80) {
      setState(() => _error = context.l10n.sidebarRenameSessionTooLong);
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: StudioDriverKeys.renameThreadDialog(widget.thread.id),
      title: Text(context.l10n.sidebarRenameSessionTitle),
      content: TextField(
        key: StudioDriverKeys.renameThreadInput(widget.thread.id),
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: context.l10n.sidebarRenameSessionInput,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          key: StudioDriverKeys.renameThreadSave(widget.thread.id),
          onPressed: _submit,
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}
