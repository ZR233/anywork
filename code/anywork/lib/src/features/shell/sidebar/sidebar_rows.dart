part of 'studio_sidebar.dart';

class SidebarProjectRow extends StatelessWidget {
  const SidebarProjectRow({
    super.key,
    required this.project,
    required this.selected,
    required this.expanded,
    required this.pinned,
    required this.onToggle,
    required this.onSelect,
    required this.onNewSession,
    required this.onAction,
    this.recoveryIssue,
    this.touchMode = false,
  });

  final StudioProject project;
  final bool selected;
  final bool expanded;
  final bool pinned;
  final VoidCallback onToggle;
  final VoidCallback onSelect;
  final VoidCallback onNewSession;
  final ValueChanged<SidebarProjectAction> onAction;
  final StudioRecoveryIssue? recoveryIssue;
  final bool touchMode;

  @override
  Widget build(BuildContext context) {
    final issue = recoveryIssue;
    final target = touchMode ? 44.0 : 28.0;
    return KeyedSubtree(
      key: StudioDriverKeys.projectRow(project.id),
      child: _SidebarHoverDetail(
        detailBuilder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _projectDetailCard(context),
            if (issue != null) Text(context.recoveryIssueLabel(issue)),
          ],
        ),
        child: _SidebarTile(
          selected: selected,
          emphasized: true,
          title: project.name,
          leadingPadding: 0,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tileIconButton(
                key: StudioDriverKeys.projectExpand(project.id),
                tooltip: context.l10n.sidebarProjects,
                icon: expanded ? Icons.expand_more : Icons.chevron_right,
                minTarget: target,
                onPressed: onToggle,
              ),
              SizedBox.square(
                dimension: 16,
                child: Center(
                  child: Icon(
                    project.sshAlias == null
                        ? Icons.folder_outlined
                        : Icons.dns_outlined,
                    size: 16,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
          onTap: issue?.blocksAccess == true ? null : onSelect,
          touchMode: touchMode,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (project.sshAlias != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text('SSH', style: context.text.labelSmall),
                ),
              if (issue != null) _recoveryIndicator(context, issue),
              // 常驻新建入口：折叠热区与项目的行内操作互不干扰。
              _tileIconButton(
                key: StudioDriverKeys.projectNewSession(project.id),
                tooltip: '${context.l10n.sidebarNewSession} · ${project.name}',
                icon: Icons.add,
                minTarget: target,
                onPressed: issue?.blocksAccess == true ? null : onNewSession,
              ),
            ],
          ),
          actions: SidebarProjectMenu(
            menuKey: StudioDriverKeys.projectMenu(project.id),
            pinned: pinned,
            minTarget: target,
            recoveryIssueId: issue?.scope == RecoveryIssueScope.project
                ? issue?.id
                : null,
            canRetryRecovery:
                issue?.scope == RecoveryIssueScope.project &&
                issue?.canRetry == true,
            onAction: onAction,
          ),
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

class SidebarThreadRow extends StatelessWidget {
  const SidebarThreadRow({
    super.key,
    required this.row,
    required this.project,
    required this.selected,
    required this.pinned,
    required this.hostApps,
    required this.onSelect,
    required this.onAction,
    this.recoveryIssue,
    this.archived = false,
    this.touchMode = false,
  });

  final SessionDirectoryRow row;
  final StudioProject project;
  final bool selected;
  final bool pinned;
  final SidebarHostApps hostApps;
  final VoidCallback onSelect;
  final ValueChanged<SidebarThreadAction> onAction;
  final StudioRecoveryIssue? recoveryIssue;
  final bool archived;
  final bool touchMode;

  @override
  Widget build(BuildContext context) {
    final issue = recoveryIssue;
    final target = touchMode ? 44.0 : 28.0;
    final alias = project.sshAlias;
    return KeyedSubtree(
      key: StudioDriverKeys.threadRow(row.threadId),
      child: _SidebarHoverDetail(
        detailBuilder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _threadDetailCard(context),
            if (issue != null) Text(context.recoveryIssueLabel(issue)),
          ],
        ),
        child: _SidebarTile(
          selected: selected && !archived,
          title: row.title,
          touchMode: touchMode,
          leadingPadding: 8,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                key: ValueKey('thread-status-slot-${row.threadId}'),
                dimension: 16,
                child: Center(
                  child: archived
                      ? const SizedBox.shrink()
                      : _ThreadStatusBadge(status: row.status),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
          onTap: archived || issue?.blocksAccess == true ? null : onSelect,
          leadingActionsAlwaysVisible: pinned && !archived,
          leadingActions: archived
              ? null
              : _tileIconButton(
                  key: StudioDriverKeys.pinThread(row.threadId),
                  tooltip: pinned
                      ? context.l10n.sidebarUnpin
                      : context.l10n.sidebarPin,
                  icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  minTarget: target,
                  onPressed: () => onAction(SidebarThreadAction.pin),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (issue != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _recoveryIndicator(context, issue),
                ),
              if (row.workspaceMode.isWorktree)
                SizedBox.square(
                  dimension: 28,
                  child: Center(
                    child: Tooltip(
                      message: context.l10n.sidebarSessionWorktree,
                      child: Icon(
                        Icons.account_tree_outlined,
                        key: StudioDriverKeys.threadWorkspaceMode(row.threadId),
                        size: 15,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          actions: archived
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tileIconButton(
                      key: ValueKey(
                        'thread-archived-workspace-${row.threadId}',
                      ),
                      tooltip: context.l10n.sidebarOriginalWorkspace,
                      icon: Icons.folder_outlined,
                      minTarget: target,
                      onPressed: () =>
                          onAction(SidebarThreadAction.originalWorkspace),
                    ),
                    _tileIconButton(
                      key: ValueKey('thread-restore-${row.threadId}'),
                      tooltip: context.l10n.sidebarRestore,
                      icon: Icons.unarchive_outlined,
                      minTarget: target,
                      onPressed: () => onAction(SidebarThreadAction.restore),
                    ),
                  ],
                )
              : SidebarThreadMenu(
                  row: row,
                  blocked: issue?.blocksAccess == true,
                  recoveryIssue: issue,
                  recoveryIssueId: issue?.scope == RecoveryIssueScope.thread
                      ? issue?.id
                      : null,
                  canRetryRecovery:
                      issue?.scope == RecoveryIssueScope.thread &&
                      issue?.canRetry == true,
                  targetDescription: alias == null
                      ? row.workspacePath
                      : '$alias:${row.workspacePath}',
                  hostApps: hostApps,
                  minTarget: target,
                  onAction: onAction,
                ),
        ),
      ),
    );
  }

  Widget _threadDetailCard(BuildContext context) {
    final alias = project.sshAlias;
    final environment = alias == null
        ? context.l10n.sidebarLocal
        : 'SSH · $alias';
    final statusLabel = context.threadStatusLabel(row.status);
    final updated = _relativeUpdatedLabel(context, row.updatedAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 详情卡内部可滚动，完整展示 canonical 标题（含 80 字 CJK 长标题）；
        // 截断只发生在行内单行渲染。
        Text(
          row.title,
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
          value: row.workspacePath,
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

  Color _statusDotColor(BuildContext context) => switch (row.status) {
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

Widget _recoveryIndicator(BuildContext context, StudioRecoveryIssue issue) =>
    Tooltip(
      message: context.recoveryIssueLabel(issue),
      child: Icon(
        issue.impact == RecoveryIssueImpact.advisory
            ? Icons.info_outline
            : Icons.error_outline,
        size: 16,
        color: issue.impact == RecoveryIssueImpact.advisory
            ? context.colors.primary
            : context.colors.error,
      ),
    );
