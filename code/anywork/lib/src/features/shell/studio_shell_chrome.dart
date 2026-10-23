part of 'studio_shell.dart';

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final HeaderView state;

  @override
  Widget build(BuildContext context) {
    final thread = state.selectedRootThread;
    final project = state.selectedProject;
    final projectLabel = project?.name.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
              if (thread != null)
                Tooltip(
                  message: context.l10n.delegationFrozen,
                  child: Text(
                    context.delegationSummary(
                      DelegationSettingsView(
                        mode: thread.delegationMode,
                        preference: thread.delegationPreference,
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              if (projectLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Tooltip(
                  richMessage: TextSpan(
                    text:
                        thread?.workspacePath ?? project?.path ?? projectLabel,
                    style: const TextStyle(fontFamily: studioCodeFontFamily),
                  ),
                  child: Text(
                    projectLabel,
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
          final actions = OverflowBar(
            spacing: 8,
            overflowSpacing: 4,
            overflowAlignment: OverflowBarAlignment.start,
            children: [
              _AgentSwitcher(state: state),
              _SessionCostChip(cost: state.sessionCost),
              _SessionOpenWorkspaceMenu(state: state),
            ],
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, if (state.agents.isNotEmpty) actions],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              if (state.agents.isNotEmpty) ...[
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
    return Tooltip(
      message: [
        context.l10n.sessionAllAgentsCostTooltip,
        for (final item in cost?.purposeCosts ?? const <PurposeCostView>[])
          '${_purposeLabel(context, item.purpose)}: ${item.label}${item.hasUnpricedUsage ? ' (${context.l10n.statusUnpricedUsageLabel})' : ''}',
      ].join('\n'),
      child: Padding(
        key: StudioDriverKeys.sessionCost,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(cost?.label ?? '-', style: context.text.labelMedium),
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
/// 三项各自探测可用性，不可用时禁用并说明原因。三个入口的目标都由会话
class _SessionOpenWorkspaceMenu extends ConsumerStatefulWidget {
  const _SessionOpenWorkspaceMenu({required this.state});

  final HeaderView state;

  @override
  ConsumerState<_SessionOpenWorkspaceMenu> createState() =>
      _SessionOpenWorkspaceMenuState();
}

class _SessionOpenWorkspaceMenuState
    extends ConsumerState<_SessionOpenWorkspaceMenu> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final project = widget.state.selectedProject;
    final thread = widget.state.selectedRootThread;
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
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        _menuItem(
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
        _menuItem(
          key: StudioDriverKeys.sessionOpenWorkspaceZed,
          icon: const HostAppLogo(app: HostAppIcon.zed, fallback: Icons.code),
          label: context.l10n.sessionOpenInZed,
          targetDescription: targetDescription,
          available: zedAvailable,
          unavailableReason: context.l10n.sessionZedUnavailable,
          onActivated: () =>
              _openThreadWorkspaceInZed(context, ref, project, thread),
        ),
        _menuItem(
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
      child: Tooltip(
        message: '$label\n$targetDescription',
        child: TextButton(
          key: StudioDriverKeys.sessionOpenWorkspaceMenu,
          onPressed: () {
            if (_controller.isOpen) {
              _controller.close();
            } else {
              _controller.open();
            }
          },
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
        ),
      ),
    );
  }

  /// 单行条目按内容自然收紧；完整目标与不可用原因由提示和读屏说明承载。
  MenuItemButton _menuItem({
    required Key key,
    required Widget icon,
    required String label,
    required String targetDescription,
    required bool available,
    required String unavailableReason,
    required VoidCallback onActivated,
  }) {
    // 菜单项保持 Material 原生布局；完整目标与不可用原因由 Tooltip 和
    // semanticsLabel 承载，不把路径挤进菜单行。
    final tooltipMessage = available
        ? '$label\n$targetDescription'
        : '$label\n$targetDescription\n$unavailableReason';
    return MenuItemButton(
      key: key,
      semanticsLabel: tooltipMessage,
      leadingIcon: icon,
      onPressed: available ? onActivated : null,
      child: Tooltip(
        message: tooltipMessage,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
  StudioThread thread,
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
          remotePath: thread.workspacePath,
        );
      }
    } on Object {
      failure = l10n.sessionVsCodeOpenFailed;
    }
  } else {
    uri = buildLocalVsCodeFolderUri(thread.workspacePath);
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
  StudioThread thread,
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
          remotePath: thread.workspacePath,
        );
      }
    } on Object {
      failure = l10n.sessionZedOpenFailed;
    }
  } else {
    target = LocalZedWorkspaceTarget(directory: thread.workspacePath);
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
  StudioThread thread,
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
          remotePath: thread.workspacePath,
        );
      }
    } on Object {
      failure = l10n.sessionTerminalOpenFailed;
    }
  } else {
    target = LocalHostTerminalTarget(directory: thread.workspacePath);
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

class _AgentSwitcher extends ConsumerStatefulWidget {
  const _AgentSwitcher({required this.state});

  final HeaderView state;

  @override
  ConsumerState<_AgentSwitcher> createState() => _AgentSwitcherState();
}

class _AgentSwitcherState extends ConsumerState<_AgentSwitcher> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final agents = AgentDirectoryQueries.menuOrder(widget.state.agents);
    final aggregateColor = _aggregateAgentColor(context, widget.state, agents);
    final viewport = MediaQuery.sizeOf(context);
    final availableWidth = (viewport.width - 24)
        .clamp(0.0, double.infinity)
        .toDouble();
    final minimumWidth = availableWidth < 240 ? availableWidth : 240.0;
    final menuWidth = (viewport.width * 0.36)
        .clamp(minimumWidth, availableWidth)
        .toDouble();
    // Reserve the compact header and overlay insets so a long menu can stay
    // below its anchor and scroll instead of being flipped over the header.
    // 高度上限让菜单只占用有限纵向空间，其余条目滚动查看。
    final menuHeight = (viewport.height - 96)
        .clamp(0.0, _agentMenuMaxHeight)
        .toDouble();
    final selectedId = widget.state.selectedThreadId;
    return MenuAnchor(
      controller: _controller,
      // 关闭官方 UnconstrainedBox 包装，让下方 MenuStyle 的宽度约束真正生效；
      // 菜单宽度因此稳定、各行等宽，标题过长只做行内省略。
      crossAxisUnconstrained: false,
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(menuWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(menuWidth, menuHeight)),
      ),
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        for (final agent in agents)
          _agentRow(
            agent,
            selected: agent.threadId == selectedId,
            menuWidth: menuWidth,
          ),
      ],
      child: TextButton(
        key: StudioDriverKeys.agentSwitcher,
        onPressed: () {
          if (_controller.isOpen) {
            _controller.close();
          } else {
            _controller.open();
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 6, color: aggregateColor),
            const SizedBox(width: 8),
            Text(context.l10n.statusAgentsCount(agents.length)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 14),
          ],
        ),
      ),
    );
  }

  /// 单个智能体行：层级缩进、状态图标、任务概要/角色、右侧状态与选中勾。
  ///
  /// 图标、正文与尾部件分别落在 [MenuItemButton] 的官方槽位上，行内空间由 Flex
  /// 与行内省略分配；正文持有显式有限宽度，状态列单独保留空间，深层缩进在窄窗有界。
  /// 选中勾在所有行保留同宽占位，各行状态右边缘因此对齐。
  Widget _agentRow(
    StudioAgentView agent, {
    required bool selected,
    required double menuWidth,
  }) {
    final thread = widget.state.workspaceThreads
        .where((thread) => thread.id == agent.threadId)
        .firstOrNull;
    final error = agent.error;
    final hasError = error != null;
    final summary = thread?.title.trim().isNotEmpty == true
        ? thread!.title
        : agent.task.trim().isNotEmpty
        ? agent.task
        : context.roleLabel(agent.role);
    final status =
        error ?? context.threadStatusLabel(_agentThreadStatus(agent.state));
    final secondaryStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: context.colors.onSurfaceVariant);
    final role = agent.role.trim();
    final roleLabel = role.isEmpty
        ? null
        : (role == 'planner' && agent.parentPath != null
              ? context.l10n.agentRoleRetired
              : context.roleLabel(role));
    final frozen = agent.frozenModel ?? thread?.frozenModel;
    final account = ref
        .watch(settingsStoreProvider)
        .canonical
        ?.accounts
        .where((account) => account.id == frozen?.accountId)
        .firstOrNull;
    final descriptor = account?.models
        .where((model) => model.modelId == frozen?.modelId)
        .firstOrNull;
    final modelLabel = frozen == null
        ? context.l10n.delegationModelNotRecorded
        : descriptor?.displayName.isNotEmpty == true
        ? descriptor!.displayName
        : frozen.modelId;
    final modelTooltip = frozen == null
        ? modelLabel
        : '$modelLabel\n${frozen.accountId} / ${frozen.modelId}\n${context.l10n.statusReasoningEffort}: ${frozen.effort ?? context.l10n.statisticsReasoningEffortUnspecified}';
    final indent = (agent.depth * _agentIndentStep).clamp(
      0.0,
      (menuWidth - 208).clamp(0.0, menuWidth),
    );
    final rowWidth = (menuWidth - 88 - indent).clamp(0.0, menuWidth);
    final statusGap = rowWidth.clamp(0.0, _agentRowGap);
    final statusWidth = (rowWidth - statusGap).clamp(0.0, 84.0);
    return MenuItemButton(
      key: StudioDriverKeys.agentRow(agent.threadId),
      onPressed: () {
        unawaited(
          ref
              .read(anyworkClientProvider)
              .directoryCommands
              .selectAgentThread(agent.threadId)
              .catchError((Object error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error.toString())));
              }),
        );
      },
      // 选中背景走官方样式工厂；内边距、行高、悬浮与墨迹效果沿用
      // MenuItemButton 的官方默认值。
      style: MenuItemButton.styleFrom(
        backgroundColor: selected
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : null,
      ),
      // 层级缩进按真实父子深度表达；Material 菜单项没有对应能力。
      leadingIcon: Padding(
        padding: EdgeInsetsDirectional.only(start: indent),
        child: Icon(
          hasError ? Icons.error_outline : Icons.circle,
          size: hasError ? 16 : 9,
          color: hasError
              ? Theme.of(context).colorScheme.error
              : _statusColor(context, widget.state, agent),
        ),
      ),
      // 未选中行用官方 Visibility 保持同宽占位，状态列与指示列因此始终对齐。
      trailingIcon: Visibility(
        visible: selected,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: const Icon(Icons.check, size: _agentCheckSize),
      ),
      child: SizedBox(
        width: rowWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: summary,
                    child: Text(
                      summary,
                      key: StudioDriverKeys.agentTaskSummary(agent.threadId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                SizedBox(width: statusGap),
                SizedBox(
                  width: statusWidth,
                  child: Tooltip(
                    message: status,
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: secondaryStyle,
                    ),
                  ),
                ),
              ],
            ),
            Tooltip(
              message: modelTooltip,
              child: Text(
                '${roleLabel ?? role} · $modelLabel',
                key: StudioDriverKeys.agentModel(agent.threadId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: secondaryStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `n agents` 菜单最多占用的高度，超出部分滚动查看。
const double _agentMenuMaxHeight = 320;

/// 任务概要与状态文本之间的行内间距。
const double _agentRowGap = 12;

/// 单层层级缩进的步长，以及行尾选中勾占位宽度。
const double _agentIndentStep = 12;
const double _agentCheckSize = 18;

/// 宽屏顶栏 actions 最多占用的横向比例，其余横向空间留给会话标题。
const double _headerActionsWidthFraction = 0.7;

Color _aggregateAgentColor(
  BuildContext context,
  HeaderView state,
  List<StudioAgentView> agents,
) {
  if (agents.any((agent) => agent.state is FaultedStudioAgent)) {
    return context.colors.error;
  }
  if (state.pendingInteractions.any(
    (interaction) =>
        agents.any((agent) => agent.threadId == interaction.threadId),
  )) {
    return context.statusColors.warning;
  }
  if (agents.any((agent) => agent.state.isActive)) {
    return context.statusColors.activeIndicator;
  }
  return context.statusColors.success;
}

Color _statusColor(
  BuildContext context,
  HeaderView state,
  StudioAgentView agent,
) {
  if (agent.state is FaultedStudioAgent) {
    return context.colors.error;
  }
  if (state.pendingInteractions.any(
    (interaction) => interaction.threadId == agent.threadId,
  )) {
    return context.statusColors.warning;
  }
  if (agent.state.isActive) {
    return context.statusColors.activeIndicator;
  }
  return context.statusColors.success;
}

ThreadStatusView _agentThreadStatus(StudioAgentState state) => switch (state) {
  IdleStudioAgent() => ThreadStatusView.idle,
  QueuedStudioAgent() => ThreadStatusView.queued,
  RunningStudioAgent() => ThreadStatusView.running,
  WaitingToolStudioAgent() => ThreadStatusView.waitingTool,
  WaitingInteractionStudioAgent() => ThreadStatusView.waitingInteraction,
  CancellingStudioAgent() => ThreadStatusView.cancelling,
  ClosingStudioAgent() => ThreadStatusView.closing,
  ClosedStudioAgent() => ThreadStatusView.closed,
  FaultedStudioAgent() => ThreadStatusView.faulted,
};

class _Footer extends StatelessWidget {
  const _Footer({
    required this.threadId,
    required this.showTodo,
    required this.todoExpanded,
    required this.onToggleTodo,
    this.showPlanEntry = false,
    this.onOpenPlan,
    required this.compact,
    this.contentKey,
  });

  final String threadId;
  final bool showTodo;
  final bool todoExpanded;
  final VoidCallback? onToggleTodo;
  final bool showPlanEntry;
  final VoidCallback? onOpenPlan;

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
          // 活动条是整条 footer 里**唯一**可伸缩的部分：`Flexible` 把输入区与状态栏
          // 布局之后的实际剩余高度交给它，因此展开详情只能压缩自己，不可能把输入区
          // 顶出窗口。输入区与状态栏保持自身固有高度，始终完整可见。
          //
          // footer 的总预算由 [AgentWorkspacePane] 按「窗口高度 − 时间线最小可视高度」
          // 给出；矮窗口时 [compact] 只收起 composer 留白与输入行数，让展开详情保留可读
          // 高度，同时不隐藏任何操作按钮。
          Flexible(
            fit: FlexFit.loose,
            child: _ConversationActivityHost(threadId: threadId),
          ),
          _ComposerHost(compact: compact),
          _StatusBarHost(
            showTodo: showTodo,
            todoExpanded: todoExpanded,
            onToggleTodo: onToggleTodo,
            showPlanEntry: showPlanEntry,
            onOpenPlan: onOpenPlan,
          ),
        ],
      ),
    );
    return contentKey == null
        ? footer
        : KeyedSubtree(key: contentKey, child: footer);
  }
}

/// 固定活动条的接线点。
///
/// 阶段/摘要/存储/交互来自当前已打开会话。展开详情是 host 的 ephemeral 状态：
/// 按活动身份按需读取，不写入 store，也不成为第二份 canonical。
class _ConversationActivityHost extends ConsumerStatefulWidget {
  const _ConversationActivityHost({required this.threadId});

  final String threadId;

  @override
  ConsumerState<_ConversationActivityHost> createState() =>
      _ConversationActivityHostState();
}

class _ConversationActivityHostState
    extends ConsumerState<_ConversationActivityHost> {
  var _expanded = false;
  var _detail = const ThreadActivityDetailState();
  Future<void>? _inFlight;
  String? _inFlightIdentity;
  var _refreshQueued = false;
  var _loadScheduled = false;
  var _generation = 0;

  @override
  void didUpdateWidget(covariant _ConversationActivityHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId == widget.threadId) return;
    _generation++;
    _expanded = false;
    _refreshQueued = false;
    _detail = const ThreadActivityDetailState();
    _inFlight = null;
    _inFlightIdentity = null;
  }

  void _expand() {
    if (_expanded) {
      _requestLoad();
      return;
    }
    setState(() => _expanded = true);
  }

  void _collapse() {
    if (!_expanded && !_refreshQueued) return;
    setState(() {
      _expanded = false;
      _refreshQueued = false;
    });
  }

  void _requestLoad() {
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (mounted) unawaited(_load());
    });
  }

  bool _covers(ThreadActivityView activity) {
    return _detail.covers(activity.identity, activity.revision) &&
        _detail.revision >= activity.revision;
  }

  Future<void> _load() async {
    if (!_expanded || !mounted) return;
    final activity = ref
        .read(conversationActivityInputProvider(widget.threadId))
        ?.activity;
    if (activity == null) return;
    if (_covers(activity)) return;
    if (_inFlight != null && _inFlightIdentity == activity.identity) {
      _refreshQueued = true;
      return;
    }
    final generation = _generation;
    final threadId = widget.threadId;
    _inFlightIdentity = activity.identity;
    setState(() {
      _detail = _detail.copyWith(
        identity: activity.identity,
        revision: activity.revision,
        loading: true,
        error: null,
      );
    });
    final request = _perform(threadId, activity, generation);
    _inFlight = request;
    await request;
    if (identical(_inFlight, request)) {
      _inFlight = null;
      _inFlightIdentity = null;
    }
    if (_refreshQueued && mounted && _expanded && generation == _generation) {
      _refreshQueued = false;
      unawaited(_load());
    }
  }

  Future<void> _perform(
    String threadId,
    ThreadActivityView activity,
    int generation,
  ) async {
    try {
      // 活动详情没有命令 lane。展开时直接读 data source，不写入 store。
      final detail = await ref
          .read(anyworkClientProvider)
          .readThreadActivityDetail(threadId, activity.identity);
      if (!mounted || generation != _generation || !_expanded) return;
      final latest = ref
          .read(conversationActivityInputProvider(threadId))
          ?.activity;
      if (latest != null && latest.identity != activity.identity) return;
      setState(() {
        _detail = ThreadActivityDetailState(
          identity: activity.identity,
          revision: activity.revision,
          detail: detail,
        );
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation || !_expanded) return;
      final latest = ref
          .read(conversationActivityInputProvider(threadId))
          ?.activity;
      if (latest != null && latest.identity != activity.identity) return;
      setState(() {
        _detail = ThreadActivityDetailState(
          identity: activity.identity,
          revision: activity.revision,
          error: error.toString(),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final input = ref.watch(conversationActivityInputProvider(widget.threadId));
    final activity = input?.activity;
    if (_expanded && activity != null && !_covers(activity)) {
      _requestLoad();
    }
    final matches = activity != null && _detail.matches(activity.identity);
    final view = input == null
        ? null
        : projectConversationActivity(
            activity: activity,
            storage: input.storage,
            interaction: input.interaction,
            detail: matches ? _detail.detail : null,
            detailsLoading: matches && _detail.loading,
            detailsError: matches ? _detail.error : null,
          );
    if (view == null) {
      StudioDriverState.publishConversationActivity(null);
      return const SizedBox.shrink();
    }
    StudioDriverState.publishConversationActivity(view);
    return ConversationActivityBar(
      view: view,
      onExpand: _expand,
      onCollapse: _collapse,
      // Driver 可观察的是“实际展开态”，不是 `expandable` 的“可展开能力”。
      onExpandedChanged: StudioDriverState.publishActivityExpanded,
    );
  }
}

class _StatusBarHost extends ConsumerWidget {
  const _StatusBarHost({
    required this.showTodo,
    required this.todoExpanded,
    required this.onToggleTodo,
    this.showPlanEntry = false,
    this.onOpenPlan,
  });

  final bool showTodo;
  final bool todoExpanded;
  final VoidCallback? onToggleTodo;
  final bool showPlanEntry;
  final VoidCallback? onOpenPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadId = ref.watch(shellSelectionProvider).selectedThreadId;
    if (threadId == null) return const SizedBox.shrink();
    return ThreadStatusConnector(
      threadId: threadId,
      showTodo: showTodo,
      todoExpanded: todoExpanded,
      onToggleTodo: onToggleTodo,
      showPlanEntry: showPlanEntry,
      onOpenPlan: onOpenPlan,
    );
  }
}

class _ComposerHost extends ConsumerWidget {
  const _ComposerHost({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadId = ref.watch(shellSelectionProvider).selectedThreadId;
    if (threadId == null) return const SizedBox.shrink();
    return ComposerDock(threadId: threadId, compact: compact);
  }
}
