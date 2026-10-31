part of 'studio_shell.dart';

class _Header extends ConsumerWidget {
  const _Header({required this.state});

  final HeaderView state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = state.selectedRootThread;
    final project = state.selectedProject;
    final recoveryIssues =
        ref.watch(recoveryStoreProvider).value?.values ??
        const <StudioRecoveryIssue>[];
    final projectLabel = project == null
        ? ''
        : project.isStandalone
        ? thread?.workspacePath ?? ''
        : project.name.trim();
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
              AgentSwitcherMenu(
                agents: state.agents,
                workspaceThreads: state.workspaceThreads,
                recoveryIssues: recoveryIssues,
                selectedThreadId: state.selectedThreadId,
                pendingInteractionThreadIds: {
                  for (final interaction in state.pendingInteractions)
                    interaction.threadId,
                },
              ),
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

/// 宽屏顶栏 actions 最多占用的横向比例，其余横向空间留给会话标题。
const double _headerActionsWidthFraction = 0.7;

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
          ComposerDockConnector(threadId: threadId, compact: compact),
          ThreadStatusConnector(
            threadId: threadId,
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

/// 仅观察 SDK 当前活动。展开、滚动和计时状态由活动栏自身持有。
class _ConversationActivityHost extends ConsumerWidget {
  const _ConversationActivityHost({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final input = ref.watch(conversationActivityInputProvider(threadId));
    final view = input == null
        ? null
        : projectConversationActivity(
            current: input.currentActivity,
            storage: input.storage,
            interaction: input.interaction,
          );
    StudioDriverState.publishConversationActivity(view);
    if (view == null) return const SizedBox.shrink();
    return ConversationActivityBar(
      view: view,
      onExpandedChanged: StudioDriverState.publishActivityExpanded,
    );
  }
}
