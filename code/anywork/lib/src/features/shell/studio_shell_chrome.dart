part of 'studio_shell.dart';

class SessionHeader extends ConsumerWidget {
  const SessionHeader({required this.state, super.key});

  final HeaderView state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = state.selectedRootRow;
    final project = state.selectedProject;
    final recoveryIssues =
        ref.watch(recoveryStoreProvider).value?.values ??
        const <StudioRecoveryIssue>[];
    final projectLabel = project == null
        ? ''
        : project.isStandalone
        ? thread?.workspacePath ?? ''
        : project.name.trim();
    final isNative = thread?.backend is NativeAgentBackendView;
    final subtitleParts = <String>[
      if (projectLabel.isNotEmpty) projectLabel,
      if (thread != null && isNative) ...[
        thread.workspaceMode == ThreadWorkspaceMode.worktree
            ? context.l10n.composerWorkspaceModeWorktree
            : context.l10n.composerWorkspaceModeLocal,
        context.delegationSummary(
          DelegationSettingsView(
            mode: thread.delegationMode,
            preference: thread.delegationPreference,
          ),
        ),
      ],
    ];
    final subtitle = subtitleParts.join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                thread?.title ?? context.l10n.shellNoSession,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (thread != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Tooltip(
                  richMessage: TextSpan(
                    children: [
                      TextSpan(
                        text: thread.workspacePath,
                        style: const TextStyle(
                          fontFamily: studioCodeFontFamily,
                        ),
                      ),
                      if (isNative)
                        TextSpan(text: '\n${context.l10n.delegationFrozen}'),
                    ],
                  ),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          );
          // Actions stay on one row when they fit and stack vertically when the
          // window is too narrow, so the open-workspace menu never overflows.
          final hasWorkspaceTarget =
              state.selectedProject != null && state.selectedRootRow != null;
          final hasHeaderActions =
              state.agents.isNotEmpty || hasWorkspaceTarget;
          final actions = OverflowBar(
            spacing: 8,
            overflowSpacing: 4,
            overflowAlignment: OverflowBarAlignment.start,
            children: [
              if (state.agents.isNotEmpty) ...[
                AgentSwitcherMenu(
                  agents: state.agents,
                  workspaceRows: state.workspaceRows,
                  recoveryIssues: recoveryIssues,
                  selectedThreadId: state.selectedThreadId,
                  pendingInteractionThreadIds: {
                    for (final interaction in state.pendingInteractions)
                      interaction.threadId,
                  },
                ),
                if (thread?.backend is NativeAgentBackendView &&
                    state.agents.every(
                      (agent) => agent.activity is NativeStudioAgentActivity,
                    ))
                  _SessionCostChip(cost: state.sessionCost),
              ],
              if (hasWorkspaceTarget) _SessionOpenWorkspaceMenu(state: state),
            ],
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, if (hasHeaderActions) actions],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              if (hasHeaderActions) ...[
                const SizedBox(width: 16),
                // Bound the actions: this non-flexible row child would
                // otherwise receive unbounded width and let the overflow bar
                // stay on one line past the header. The title keeps the rest,
                // and the overflow bar stacks once actions exceed the cap.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth:
                        constraints.maxWidth * _headerActionsWidthFraction,
                  ),
                  child: actions,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SessionCostChip extends StatelessWidget {
  const _SessionCostChip({required this.cost});

  final SessionCostView? cost;

  @override
  Widget build(BuildContext context) {
    final labelStyle = context.text.labelMedium;
    return Tooltip(
      message: [
        context.l10n.sessionAllAgentsCostTooltip,
        for (final item in cost?.purposeCosts ?? const <PurposeCostView>[])
          '${_purposeLabel(context, item.purpose)}: ${item.label}${item.hasUnpricedUsage ? ' (${context.l10n.statusUnpricedUsageLabel})' : ''}',
      ].join('\n'),
      child: Padding(
        key: StudioDriverKeys.sessionCost,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(cost?.label ?? '-', style: labelStyle),
            if (cost?.hasIncompleteUsage == true)
              Text(context.l10n.sessionCostIncompleteUsage, style: labelStyle),
          ],
        ),
      ),
    );
  }
}

String _purposeLabel(BuildContext context, String? purpose) =>
    switch (purpose) {
      'main' => context.l10n.costPurposeMain,
      'summary' => context.l10n.costPurposeSummary,
      'review' => context.l10n.costPurposeReview,
      'title' => context.l10n.costPurposeTitle,
      null => context.l10n.costPurposeUnknown,
      String value => value,
    };

/// 会话顶栏「打开工作区」菜单：并列 VS Code、Zed 与终端三个外部入口。
///
/// 有当前会话及所属项目即显示入口，不以编辑器安装情况控制整个入口；
/// 三项各自探测可用性，不可用时禁用并说明原因。目标取自所选会话。
class _SessionOpenWorkspaceMenu extends ConsumerWidget {
  const _SessionOpenWorkspaceMenu({required this.state});

  final HeaderView state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = state.selectedProject;
    final thread = state.selectedRootRow;
    if (project == null || thread == null) {
      return const SizedBox.shrink();
    }
    final vsCodeAvailable =
        ref.watch(vsCodeAvailabilityProvider).value ?? false;
    final zedAvailable = ref.watch(zedAvailabilityProvider).value ?? false;
    final terminalAvailable =
        ref.watch(terminalAvailabilityProvider).value ?? false;
    final label = context.l10n.sessionOpenWorkspace;
    // 悬停与读屏都暴露完整打开目标；远端项目补充 Host 别名前缀。
    final alias = project.sshAlias;
    final targetDescription = alias == null
        ? thread.workspacePath
        : '$alias:${thread.workspacePath}';
    return StudioMenuButton(
      tooltip: '$label\n$targetDescription',
      buttonKey: StudioDriverKeys.sessionOpenWorkspaceMenu,
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        workspaceOpenMenuItem(
          key: StudioDriverKeys.sessionOpenWorkspaceVsCode,
          icon: const HostAppLogo(
            app: HostAppIcon.vsCode,
            fallback: Icons.code,
          ),
          label: context.l10n.sessionOpenInVsCode,
          targetDescription: targetDescription,
          available: vsCodeAvailable,
          unavailableReason: context.l10n.sessionVsCodeUnavailable,
          onActivated: () =>
              _openThreadWorkspaceInVsCode(context, ref, project, thread),
        ),
        workspaceOpenMenuItem(
          key: StudioDriverKeys.sessionOpenWorkspaceZed,
          icon: const HostAppLogo(app: HostAppIcon.zed, fallback: Icons.code),
          label: context.l10n.sessionOpenInZed,
          targetDescription: targetDescription,
          available: zedAvailable,
          unavailableReason: context.l10n.sessionZedUnavailable,
          onActivated: () =>
              _openThreadWorkspaceInZed(context, ref, project, thread),
        ),
        workspaceOpenMenuItem(
          key: StudioDriverKeys.sessionOpenWorkspaceTerminal,
          icon: const HostAppLogo(
            app: HostAppIcon.terminal,
            fallback: Icons.terminal,
          ),
          label: context.l10n.sessionOpenInTerminal,
          targetDescription: targetDescription,
          available: terminalAvailable,
          unavailableReason: _terminalUnavailableReason(context),
          onActivated: () =>
              _openThreadWorkspaceInTerminal(context, ref, project, thread),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 18,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(label),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: context.colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// 终端不可用的原因按宿主终端入口说明，不猜测其他已安装终端；
/// 页眉菜单与侧栏会话菜单共用。
String _terminalUnavailableReason(BuildContext context) {
  if (isWindowsPlatform) {
    return context.l10n.sessionTerminalUnavailableWindows;
  }
  if (isLinuxPlatform) {
    return context.l10n.sessionTerminalUnavailableLinux;
  }
  return context.l10n.sessionTerminalUnavailableGeneric;
}

/// 会话级「在 VS Code 打开工作区」：目标始终由会话 canonical
/// `workspacePath` 与项目 SSH 别名决定，远端复用 `~/.ssh/config` 真实
/// 配置；失败通过 SnackBar 反馈，不新增后端能力。供会话页眉菜单与侧栏
/// 会话菜单共用。
Future<void> _openThreadWorkspaceInVsCode(
  BuildContext context,
  WidgetRef ref,
  StudioProject project,
  SessionDirectoryRow row,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = context.l10n;
  // launcher 必须在首个 await 前读取；context 失效后再访问 ref 会抛错。
  final launcher = ref.read(vsCodeLauncherProvider);
  String? uri;
  String? failure;
  if (project.sshAlias case final alias?) {
    try {
      // SSH 列表没有命令 lane。这里直接读 data source，不往 data/ 补方法。
      final servers = await ref
          .read(anyworkClientProvider)
          .remote
          .listSshServers();
      // await 恢复后先确认 context 仍在，再继续启动或反馈 UI。
      if (!context.mounted) return;
      final server = servers
          .where((server) => server.alias == alias)
          .firstOrNull;
      if (server == null) {
        failure = l10n.sessionOpenServerMissing;
      } else {
        uri = buildRemoteVsCodeFolderUri(
          alias: server.alias,
          remotePath: row.workspacePath,
        );
      }
    } on Object {
      failure = l10n.sessionVsCodeOpenFailed;
    }
  } else {
    uri = buildLocalVsCodeFolderUri(row.workspacePath);
  }
  if (uri != null) {
    try {
      await launcher(uri);
    } on Object {
      failure = l10n.sessionVsCodeOpenFailed;
    }
  }
  if (failure != null &&
      context.mounted &&
      messenger != null &&
      messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(failure)));
  }
}

/// 会话级「在 Zed 打开工作区」，与 [_openThreadWorkspaceInVsCode] 共享
/// 同一 canonical 打开目标语义。
Future<void> _openThreadWorkspaceInZed(
  BuildContext context,
  WidgetRef ref,
  StudioProject project,
  SessionDirectoryRow row,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = context.l10n;
  // launcher 必须在首个 await 前读取；context 失效后再访问 ref 会抛错。
  final launcher = ref.read(zedLauncherProvider);
  ZedWorkspaceTarget? target;
  String? failure;
  if (project.sshAlias case final alias?) {
    try {
      // SSH 列表没有命令 lane。这里直接读 data source，不往 data/ 补方法。
      final servers = await ref
          .read(anyworkClientProvider)
          .remote
          .listSshServers();
      // await 恢复后先确认 context 仍在，再继续启动或反馈 UI。
      if (!context.mounted) return;
      final server = servers
          .where((server) => server.alias == alias)
          .firstOrNull;
      if (server == null) {
        failure = l10n.sessionOpenServerMissing;
      } else {
        target = RemoteSshZedWorkspaceTarget(
          alias: server.alias,
          remotePath: row.workspacePath,
        );
      }
    } on Object {
      failure = l10n.sessionZedOpenFailed;
    }
  } else {
    target = LocalZedWorkspaceTarget(directory: row.workspacePath);
  }
  if (target != null) {
    try {
      await launcher(target);
    } on Object {
      failure = l10n.sessionZedOpenFailed;
    }
  }
  if (failure != null &&
      context.mounted &&
      messenger != null &&
      messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(failure)));
  }
}

/// 会话级「在终端打开工作区」，与 [_openThreadWorkspaceInVsCode] 共享
/// 同一 canonical 打开目标语义。
Future<void> _openThreadWorkspaceInTerminal(
  BuildContext context,
  WidgetRef ref,
  StudioProject project,
  SessionDirectoryRow row,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = context.l10n;
  // launcher 必须在首个 await 前读取；context 失效后再访问 ref 会抛错。
  final launcher = ref.read(terminalLauncherProvider);
  HostTerminalTarget? target;
  String? failure;
  if (project.sshAlias case final alias?) {
    try {
      // SSH 列表没有命令 lane。这里直接读 data source，不往 data/ 补方法。
      final servers = await ref
          .read(anyworkClientProvider)
          .remote
          .listSshServers();
      // await 恢复后先确认 context 仍在，再继续启动或反馈 UI。
      if (!context.mounted) return;
      final server = servers
          .where((server) => server.alias == alias)
          .firstOrNull;
      if (server == null) {
        failure = l10n.sessionOpenServerMissing;
      } else {
        target = RemoteSshTerminalTarget(
          alias: server.alias,
          remotePath: row.workspacePath,
        );
      }
    } on Object {
      failure = l10n.sessionTerminalOpenFailed;
    }
  } else {
    target = LocalHostTerminalTarget(directory: row.workspacePath);
  }
  if (target != null) {
    try {
      await launcher(target);
    } on Object {
      failure = l10n.sessionTerminalOpenFailed;
    }
  }
  if (failure != null &&
      context.mounted &&
      messenger != null &&
      messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(failure)));
  }
}

/// 宽屏顶栏 actions 最多占用的横向比例，其余横向空间留给会话标题。
const double _headerActionsWidthFraction = 0.7;

class _Footer extends StatelessWidget {
  const _Footer({
    required this.threadId,
    required this.compact,
    this.contentKey,
  });

  final String threadId;

  /// 矮窗口紧凑布局：只收缩 composer 的留白与输入行数，不隐藏任何操作。
  final bool compact;

  /// footer 区域的可定位句柄（供驱动按区域定位）。
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    final footer = DecoratedBox(
      decoration: BoxDecoration(color: context.colors.surface),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 固定在输入区上方：滚历史时依旧可见，且与 Timeline 解耦。
          //
          // 活动条是整条 footer 里**唯一**可伸缩的部分：`Flexible` 把输入区布局之后
          // 的实际剩余高度交给它，因此展开详情只能压缩自己，不可能把输入区顶出窗口。
          Flexible(
            fit: FlexFit.loose,
            child: LiveStatusBar(threadId: threadId),
          ),
          Composer(
            target: ComposerTarget.thread(threadId: threadId),
            compact: compact,
          ),
        ],
      ),
    );
    return contentKey == null
        ? footer
        : KeyedSubtree(key: contentKey, child: footer);
  }
}
