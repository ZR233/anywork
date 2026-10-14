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
              if (projectLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Tooltip(
                  message:
                      thread?.workspacePath ?? project?.path ?? projectLabel,
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
              children: [title, if (state.workspaceThreads.isNotEmpty) actions],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              if (state.workspaceThreads.isNotEmpty) ...[
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
  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'session-open-workspace-menu',
  );

  @override
  void dispose() {
    _triggerFocusNode.dispose();
    super.dispose();
  }

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
      childFocusNode: _triggerFocusNode,
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        _menuItem(
          key: StudioDriverKeys.sessionOpenWorkspaceVsCode,
          icon: _appIcon(HostAppIcon.vsCode, Icons.code),
          label: context.l10n.sessionOpenInVsCode,
          targetDescription: targetDescription,
          available: vsCodeAvailable,
          unavailableReason: context.l10n.sessionVsCodeUnavailable,
          onActivated: () =>
              _openThreadWorkspaceInVsCode(context, ref, project, thread),
        ),
        _menuItem(
          key: StudioDriverKeys.sessionOpenWorkspaceZed,
          icon: _appIcon(HostAppIcon.zed, Icons.code),
          label: context.l10n.sessionOpenInZed,
          targetDescription: targetDescription,
          available: zedAvailable,
          unavailableReason: context.l10n.sessionZedUnavailable,
          onActivated: () =>
              _openThreadWorkspaceInZed(context, ref, project, thread),
        ),
        _menuItem(
          key: StudioDriverKeys.sessionOpenWorkspaceTerminal,
          icon: _appIcon(HostAppIcon.terminal, Icons.terminal),
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
          focusNode: _triggerFocusNode,
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
    // 覆盖整个按钮（包括禁用项），并保留 Tooltip 默认的读屏说明。
    final tooltipMessage = available
        ? '$label\n$targetDescription'
        : '$label\n$targetDescription\n$unavailableReason';
    return MenuItemButton(
      key: key,
      overflowAxis: Axis.vertical,
      onPressed: available ? onActivated : null,
      child: Tooltip(
        message: tooltipMessage,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 12),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appIcon(HostAppIcon app, IconData fallback) {
    final bytes = ref.watch(hostAppIconProvider(app)).value;
    if (bytes == null) return Icon(fallback, size: 20);
    return Image.memory(
      bytes,
      width: 20,
      height: 20,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, error, stackTrace) => Icon(fallback, size: 20),
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
          .read(studioBridgeDataSourceProvider)
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
          .read(studioBridgeDataSourceProvider)
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
          .read(studioBridgeDataSourceProvider)
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
  final FocusNode _triggerFocusNode = FocusNode(debugLabel: 'agent-switcher');

  @override
  void dispose() {
    _triggerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threads = _orderedAgentThreads(widget.state.workspaceThreads);
    final aggregateColor = _aggregateAgentColor(context, widget.state, threads);
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
    return MenuAnchor(
      controller: _controller,
      childFocusNode: _triggerFocusNode,
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(menuWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(menuWidth, menuHeight)),
      ),
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        for (final thread in threads)
          MenuItemButton(
            key: StudioDriverKeys.agentRow(thread.id),
            overflowAxis: Axis.vertical,
            onPressed: () {
              unawaited(
                ref
                    .read(directoryCommandsProvider.notifier)
                    .selectAgentThread(thread.id),
              );
            },
            style: thread.id == widget.state.selectedThreadId
                ? ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.surfaceContainerHigh,
                    ),
                  )
                : null,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 真实层级深度逐级缩进，不设固定深度上限；宽度不足时
                // 先压缩间距、再整体缩放，任何有限正行宽都不产生
                // RenderFlex overflow。
                final indent = _agentDepth(thread, threads) * 12.0;
                final width = constraints.maxWidth;
                if (width.isFinite && width < _agentRowCompactFixedContent) {
                  // 极窄：整行按紧凑最小宽整体缩放（缩放而非裁剪；
                  // 此宽度下层级缩进让位给内容本身）。
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: _agentRowCompactFixedContent,
                      child: _agentRow(
                        context,
                        thread,
                        threads,
                        gap: 4,
                        indent: 0,
                      ),
                    ),
                  );
                }
                // 正常宽度用完整间距，紧凑区间把间距压到 4；图标、
                // 正文、状态与选中勾全部保留，缩进只裁剪到行宽减去
                // 对应固定内容预算，不产生负 padding。
                final compact = width.isFinite && width < _agentRowFixedContent;
                final gap = compact ? 4.0 : 12.0;
                var budget = width.isFinite
                    ? width -
                          (compact
                              ? _agentRowCompactFixedContent
                              : _agentRowFixedContent)
                    : indent;
                if (budget < 0) {
                  budget = 0;
                }
                return _agentRow(
                  context,
                  thread,
                  threads,
                  gap: gap,
                  indent: indent > budget ? budget : indent,
                );
              },
            ),
          ),
      ],
      child: TextButton(
        key: StudioDriverKeys.agentSwitcher,
        focusNode: _triggerFocusNode,
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
            Text(context.l10n.statusAgentsCount(threads.length)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 14),
          ],
        ),
      ),
    );
  }

  /// One agent row with parameterized in-row spacing, shared by the normal
  /// and compact width branches of the row builder above.
  Widget _agentRow(
    BuildContext context,
    StudioThread thread,
    List<StudioThread> threads, {
    required double gap,
    required double indent,
  }) {
    final hasError = _agentForThread(widget.state, thread.id)?.error != null;
    return Row(
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(start: indent),
          child: Icon(
            hasError ? Icons.error_outline : Icons.circle,
            size: hasError ? 16 : 9,
            color: hasError
                ? Theme.of(context).colorScheme.error
                : _statusColor(context, widget.state, thread),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          // 正文与状态按固定比例分配行内空间，两者行内省略，
          // 窄视口不再依赖固定像素宽度。
          flex: 11,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: _agentDisplayName(context, thread),
                child: Text(
                  _agentDisplayName(context, thread),
                  key: StudioDriverKeys.agentTaskSummary(thread.id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (thread.role.trim().isNotEmpty)
                Text(
                  thread.isRetiredAgent
                      ? context.l10n.agentRoleRetired
                      : context.roleLabel(thread.role),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
            ],
          ),
        ),
        SizedBox(width: gap),
        Flexible(
          flex: 9,
          child: Text(
            _agentForThread(widget.state, thread.id)?.error ??
                _agentShortStatus(context, thread),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
        if (thread.id == widget.state.selectedThreadId) ...[
          SizedBox(width: gap),
          const Icon(Icons.check, size: 18),
        ],
      ],
    );
  }
}

/// `n agents` 菜单最多占用的高度，超出部分滚动查看。
const double _agentMenuMaxHeight = 320;

/// agent 行内固定内容的最小保留预算：状态图标（最大 16）＋两个 12 的
/// 间距＋选中勾 18。极端层级深度把缩进裁剪到行宽减去该预算，保证
/// 条目不溢出且正文仍由 flex/ellipsis 收敛；这不是深度上限，正常
/// 深度完全按真实层级缩进。
/// Widest fixed content an agent row can carry: the error icon (16), the
/// spacing after the icon (12) and after the body (12), the spacing before
/// the selected check mark (12) and the check itself (18). Selected normal
/// rows only need 63; error rows with the check need the full 70.
const double _agentRowFixedContent = 16 + 12 + 12 + 12 + 18;

/// Compact fixed-content budget once the real row width drops below
/// [_agentRowFixedContent]: the same error icon (16) and check (18) with
/// the three in-row gaps squeezed to 4.
const double _agentRowCompactFixedContent = 16 + 4 + 4 + 4 + 18;

/// 宽屏顶栏 actions 最多占用的横向比例，其余横向空间留给会话标题。
const double _headerActionsWidthFraction = 0.7;

/// 运行状态展示分组：执行中、失败、空闲、关闭中或已关闭。
int _agentStatusPriority(ThreadStatusView status) => switch (status) {
  // 执行中，与 ThreadStatusView.isActive 保持一致。
  ThreadStatusView.queued ||
  ThreadStatusView.running ||
  ThreadStatusView.waitingTool ||
  ThreadStatusView.waitingInteraction ||
  ThreadStatusView.cancelling => 0,
  ThreadStatusView.faulted => 1,
  ThreadStatusView.idle => 2,
  ThreadStatusView.closing || ThreadStatusView.closed => 3,
};

/// 按运行状态分组稳定排序，同组内保持 canonical 的 owner/父子顺序。
List<StudioThread> _orderedAgentThreads(List<StudioThread> threads) {
  final indexed = [
    for (var index = 0; index < threads.length; index++)
      (index, threads[index]),
  ];
  indexed.sort((left, right) {
    final byStatus = _agentStatusPriority(left.$2.status)
        .compareTo(_agentStatusPriority(right.$2.status));
    return byStatus != 0 ? byStatus : left.$1.compareTo(right.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

StudioAgentView? _agentForThread(HeaderView state, String threadId) {
  for (final agent in state.agents) {
    if (agent.threadId == threadId) return agent;
  }
  return null;
}

int _agentDepth(StudioThread thread, List<StudioThread> threads) {
  var depth = 0;
  var parentId = thread.parentThreadId;
  final visited = <String>{thread.id};
  while (parentId != null && visited.add(parentId)) {
    final parent = threads
        .where((candidate) => candidate.id == parentId)
        .firstOrNull;
    if (parent == null) {
      break;
    }
    depth += 1;
    parentId = parent.parentThreadId;
  }
  return depth;
}

Color _aggregateAgentColor(
  BuildContext context,
  HeaderView state,
  List<StudioThread> threads,
) {
  if (threads.any((thread) => _isFaultedAgentStatus(thread.status))) {
    return context.colors.error;
  }
  if (state.pendingInteractions.any(
    (interaction) => threads.any((thread) => thread.id == interaction.threadId),
  )) {
    return context.statusColors.warning;
  }
  if (threads.any((thread) => _isRunningAgentStatus(thread.status))) {
    return context.statusColors.activeIndicator;
  }
  return context.statusColors.success;
}

Color _statusColor(
  BuildContext context,
  HeaderView state,
  StudioThread thread,
) {
  if (_isFaultedAgentStatus(thread.status)) {
    return context.colors.error;
  }
  if (state.pendingInteractions.any(
    (interaction) => interaction.threadId == thread.id,
  )) {
    return context.statusColors.warning;
  }
  if (_isRunningAgentStatus(thread.status)) {
    return context.statusColors.activeIndicator;
  }
  return context.statusColors.success;
}

bool _isRunningAgentStatus(ThreadStatusView status) => status.isActive;

bool _isFaultedAgentStatus(ThreadStatusView status) =>
    status == ThreadStatusView.faulted;

String _agentShortStatus(BuildContext context, StudioThread thread) =>
    context.threadStatusLabel(thread.status);

String _agentDisplayName(BuildContext context, StudioThread thread) {
  if (!thread.isRoot && thread.title.trim().isNotEmpty) {
    return thread.title.trim();
  }
  if (thread.isRetiredAgent) return thread.id;
  final role = thread.role.trim();
  if (role.isEmpty) {
    return thread.isRoot ? context.l10n.roleEmpty : thread.id;
  }
  return context.roleLabel(role);
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.threadId,
    required this.showTodo,
    required this.todoExpanded,
    required this.onToggleTodo,
    required this.compact,
    this.contentKey,
  });

  final String threadId;
  final bool showTodo;
  final bool todoExpanded;
  final VoidCallback? onToggleTodo;

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
          .read(studioBridgeDataSourceProvider)
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
  });

  final bool showTodo;
  final bool todoExpanded;
  final VoidCallback? onToggleTodo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(statusBarViewProvider);
    if (status == null) return const SizedBox.shrink();
    return ThreadStatusBar(
      view: status,
      showTodo: showTodo,
      todoExpanded: todoExpanded,
      onToggleTodo: onToggleTodo,
    );
  }
}

class _ComposerHost extends ConsumerWidget {
  const _ComposerHost({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(shellComposerWorkspaceProvider);
    if (workspace == null) return const SizedBox.shrink();
    return ComposerDock(workspace: workspace, compact: compact);
  }
}
