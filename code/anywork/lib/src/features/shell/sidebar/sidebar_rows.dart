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
    final target = touchMode ? 44.0 : 30.0;
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
              Icon(
                project.sshAlias == null
                    ? Icons.folder_outlined
                    : Icons.dns_outlined,
                size: 16,
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
            ],
          ),
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tileIconButton(
                key: StudioDriverKeys.projectNewSession(project.id),
                tooltip: '${context.l10n.sidebarNewSession} · ${project.name}',
                icon: Icons.add,
                minTarget: target,
                onPressed: issue?.blocksAccess == true ? null : onNewSession,
              ),
              SidebarProjectMenu(
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
            ],
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
    required this.thread,
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

  final StudioThread thread;
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
    final target = touchMode ? 44.0 : 30.0;
    final alias = project.sshAlias;
    Widget statusSlot(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: child,
    );
    return KeyedSubtree(
      key: StudioDriverKeys.threadRow(thread.id),
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
          title: thread.title,
          touchMode: touchMode,
          onTap: archived || issue?.blocksAccess == true ? null : onSelect,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (thread.workspaceMode.isWorktree)
                statusSlot(
                  Tooltip(
                    message: context.l10n.sidebarSessionWorktree,
                    child: Icon(
                      Icons.account_tree_outlined,
                      key: StudioDriverKeys.threadWorkspaceMode(thread.id),
                      size: 15,
                    ),
                  ),
                ),
              if (thread.status != ThreadStatusView.idle)
                statusSlot(_ThreadStatusBadge(status: thread.status)),
              if (issue != null) statusSlot(_recoveryIndicator(context, issue)),
            ],
          ),
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: archived
                ? [
                    _tileIconButton(
                      key: ValueKey('thread-archived-workspace-${thread.id}'),
                      tooltip: context.l10n.sidebarOriginalWorkspace,
                      icon: Icons.folder_outlined,
                      minTarget: target,
                      onPressed: () =>
                          onAction(SidebarThreadAction.originalWorkspace),
                    ),
                    _tileIconButton(
                      key: ValueKey('thread-restore-${thread.id}'),
                      tooltip: context.l10n.sidebarRestore,
                      icon: Icons.unarchive_outlined,
                      minTarget: target,
                      onPressed: () => onAction(SidebarThreadAction.restore),
                    ),
                  ]
                : [
                    _tileIconButton(
                      key: StudioDriverKeys.pinThread(thread.id),
                      tooltip: pinned
                          ? context.l10n.sidebarUnpin
                          : context.l10n.sidebarPin,
                      icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      minTarget: target,
                      onPressed: () => onAction(SidebarThreadAction.pin),
                    ),
                    SidebarThreadMenu(
                      thread: thread,
                      blocked: issue?.blocksAccess == true,
                      recoveryIssue: issue,
                      recoveryIssueId: issue?.scope == RecoveryIssueScope.thread
                          ? issue?.id
                          : null,
                      canRetryRecovery:
                          issue?.scope == RecoveryIssueScope.thread &&
                          issue?.canRetry == true,
                      targetDescription: alias == null
                          ? thread.workspacePath
                          : '$alias:${thread.workspacePath}',
                      hostApps: hostApps,
                      minTarget: target,
                      onAction: onAction,
                    ),
                  ],
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
