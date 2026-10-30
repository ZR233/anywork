import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/agent_list_stop.dart';
import '../../domain/models/agent_membership.dart';
import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/account_domains.dart';
import '../../shared/studio_driver_keys.dart';

/// 智能体切换列表。
///
/// 行选择保持原行为；有当前执行且具备停止资格的行另外提供独立的停止按钮。停止目标
/// 固定为该行的 Thread 与执行身份：点击不触发行选择、不打开子会话、不创建草稿，原
/// 选中会话不变（design/19 §19.6.1、design/25 §25.7）。
class AgentSwitcherMenu extends ConsumerStatefulWidget {
  const AgentSwitcherMenu({
    required this.agents,
    required this.workspaceThreads,
    this.recoveryIssues = const [],
    required this.selectedThreadId,
    this.pendingInteractionThreadIds = const {},
    super.key,
  });

  final List<StudioAgentView> agents;
  final List<StudioThread> workspaceThreads;
  final List<StudioRecoveryIssue> recoveryIssues;
  final String? selectedThreadId;

  /// 有本会话待决交互的成员；只影响状态色，不改变停止资格。
  final Set<String> pendingInteractionThreadIds;

  @override
  ConsumerState<AgentSwitcherMenu> createState() => _AgentSwitcherMenuState();
}

class _AgentSwitcherMenuState extends ConsumerState<AgentSwitcherMenu> {
  final MenuController _controller = MenuController();

  /// Client 命令板里各成员的停止命令状态（threadId → `stop:<threadId>`）。
  ///
  /// 请求在途与失败都从这里派生：命令板跨 widget 重建与菜单重开存活，行内不再维护
  /// 自己的在途表，目录刷新与命令板变化都按同一事实收敛。
  Map<String, CommandStatus> _stopCommands = const {};
  LatestWatch<ThreadCommandBoard>? _stopWatch;
  ResourcePermit? _stopPermit;

  /// 只为「跨过未确认阈值」触发一次重建（threadId 维度）。
  final Map<String, Timer> _stopTimers = {};

  /// 用户重试被 Client 排队的登记时间：threadId → `startedAtMs`（纯视觉信号）。
  ///
  /// `StopQueued` 表示这次点击已排在当前在途请求之后、尚未发出：行内继续按「请求
  /// 在途」渲染并保持禁用；排队重试真正发出时会换登记时间，信号自动失效。
  final Map<String, int?> _queuedStopStartedAt = {};

  /// 计时器已经跨过阈值的那次登记时间：threadId → `startedAtMs`（纯视觉信号）。
  ///
  /// 判定仍以命令板 `startedAtMs` 的 elapsed 为准；换了登记时间（重试）或不再等待
  /// 回执时自动失效。
  final Map<String, int> _stopUnconfirmedFired = {};

  /// 行内请求迟迟未被受理的判定阈值。
  static const Duration _stopUnconfirmedAfter = Duration(seconds: 15);

  /// 行内停止请求的在途事实（尚未受理）：来自命令板，目标编号必须仍是该行执行。
  bool _stopPendingFor(String threadId, String executionId) {
    final command = _stopCommands[threadId];
    return command != null &&
        command.isPending &&
        !command.accepted &&
        command.target.label == executionId;
  }

  /// 该行的在途请求是否已超过阈值且仍未被受理。
  ///
  /// elapsed 来自命令板 `startedAtMs`（跨重建稳定）；`_stopUnconfirmedFired` 只把
  /// 「计时器已到点」的时刻保留到下一次命令板更新。
  bool _stopUnconfirmedFor(StudioAgentView agent) {
    if (agent.execution?.phase.isStopping ?? false) return false;
    final command = _stopCommands[agent.threadId];
    if (command == null ||
        !command.isPending ||
        command.accepted ||
        command.startedAtMs == 0 ||
        command.target.label != agent.execution?.id) {
      return false;
    }
    // 用户已重试且被 Client 排队：按「请求在途」渲染，不显示未确认。
    if (_queuedStopStartedAt[agent.threadId] == command.startedAtMs) {
      return false;
    }
    if (_stopUnconfirmedFired[agent.threadId] == command.startedAtMs) {
      return true;
    }
    return DateTime.now().millisecondsSinceEpoch - command.startedAtMs >=
        _stopUnconfirmedAfter.inMilliseconds;
  }

  /// 已受理、正在等 canonical 收敛的停止目标：来自命令板 `accepted`。
  String? _acceptedStopFor(StudioAgentView agent) {
    final command = _stopCommands[agent.threadId];
    if (command == null || !command.isPending || !command.accepted) return null;
    return command.target.label;
  }

  /// 命令板记录的停止失败原因：它跨重建可见，不需要菜单自己记住。
  ///
  /// 只在该命令仍指向这一行的当前执行时展示：目录换执行或成员结束后，那条失败
  /// 描述的是上一次目标，不再属于这一行。
  StudioFailure? _stopFailureFor(StudioAgentView agent) {
    final command = _stopCommands[agent.threadId];
    if (command == null || command.phase != CommandPhase.failed) return null;
    if (command.target.label != agent.execution?.id) return null;
    return command.error;
  }

  /// 按命令板事实安排每行「跨过未确认阈值」的那一次重建。
  ///
  /// 只在「已发出、尚未受理、canonical 未进入清理」阶段计时；受理、清理或条目消失即撤销。
  void _syncStopUnconfirmed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final agent in widget.agents) {
      final threadId = agent.threadId;
      final command = _stopCommands[threadId];
      final awaitingReceipt =
          command != null &&
          command.isPending &&
          !command.accepted &&
          !(agent.execution?.phase.isStopping ?? false) &&
          command.target.label == agent.execution?.id;
      _stopTimers.remove(threadId)?.cancel();
      if (!awaitingReceipt || command.startedAtMs == 0) {
        _stopUnconfirmedFired.remove(threadId);
        continue;
      }
      if (_stopUnconfirmedFired[threadId] != null &&
          _stopUnconfirmedFired[threadId] != command.startedAtMs) {
        // 换了登记时间（重试）：旧信号失效。
        _stopUnconfirmedFired.remove(threadId);
      }
      final remaining =
          command.startedAtMs + _stopUnconfirmedAfter.inMilliseconds - now;
      // 已过阈值：本次 build 直接显示未确认，不再安排计时。
      if (remaining <= 0) continue;
      final startedAtMs = command.startedAtMs;
      _stopTimers[threadId] = Timer(Duration(milliseconds: remaining), () {
        _stopTimers.remove(threadId);
        if (!mounted) return;
        setState(() => _stopUnconfirmedFired[threadId] = startedAtMs);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _attachStopCommands();
  }

  bool _hasPendingInteraction(StudioAgentView agent) =>
      widget.pendingInteractionThreadIds.contains(agent.threadId);

  /// 菜单计数只统计仍有意义的成员：永久关闭的成员不再计入，正在关闭仍计入。
  ///
  /// 这只影响标题里的数量，菜单仍列出全部成员，行内的停止、停止资格与选择行为
  /// 都不因计数而改变。
  int _countedMembers(List<StudioAgentView> agents) =>
      agents.where((agent) => agent.state is! ClosedStudioAgent).length;

  Color _aggregateAgentColor(
    BuildContext context,
    List<StudioAgentView> agents,
  ) {
    if (agents.any((agent) => agent.state is FaultedStudioAgent)) {
      return context.colors.error;
    }
    if (agents.any(_hasPendingInteraction)) {
      return context.statusColors.warning;
    }
    if (agents.any((agent) => agent.state.isActive)) {
      return context.statusColors.activeIndicator;
    }
    return context.statusColors.success;
  }

  Color _statusColor(BuildContext context, StudioAgentView agent) {
    if (agent.state is FaultedStudioAgent) {
      return context.colors.error;
    }
    if (_hasPendingInteraction(agent)) {
      return context.statusColors.warning;
    }
    if (agent.state.isActive) {
      return context.statusColors.activeIndicator;
    }
    return context.statusColors.success;
  }

  /// 行内停止：目标固定为该行渲染时的执行编号，结果状态完全由命令板表达。
  ///
  /// 点击不触发行选择、不打开子会话、不创建草稿；`StopQueued` 表示这次点击已排在当前
  /// 请求之后、尚未发出，界面继续按「请求在途」渲染并保持禁用。
  void _requestStop(StudioAgentView agent, String executionId) {
    // 本次点击之前该行的登记时间：被排队时用它标记「这次重试尚未发出」。
    final queuedAtMs = _stopCommands[agent.threadId]?.startedAtMs;
    unawaited(
      ref
          .read(anyworkClientProvider)
          .threadCommands
          .stopAgent(agent.threadId, expectedExecutionId: executionId)
          .then(
            (outcome) {
              if (!mounted) return;
              switch (outcome) {
                // 已受理：命令板随即将 `accepted` 置位，行内据此显示「正在停止」。
                case StopRequested():
                // 没有产生请求：命令板不会出现条目，行按目录事实渲染。
                case StopNoExecution():
                case StopNotQualified():
                  break;
                // 排队重试：尚未发出，继续按「请求在途」渲染（隐藏未确认提示、
                // 保持禁用），不当作成功、不新建计时。
                case StopQueued():
                  setState(
                    () => _queuedStopStartedAt[agent.threadId] = queuedAtMs,
                  );
              }
            },
            // 失败原因由命令板 `CommandStatus.error` 承载，菜单不另存一份。
            onError: (Object error) {},
          ),
    );
  }

  @override
  void dispose() {
    for (final timer in _stopTimers.values) {
      timer.cancel();
    }
    _stopTimers.clear();
    _stopUnconfirmedFired.clear();
    _queuedStopStartedAt.clear();
    _stopWatch?.observation.cancel();
    _stopPermit?.release();
    _stopWatch = null;
    _stopPermit = null;
    super.dispose();
  }

  /// 把命令板按成员归并：行内只关心自己的 `stop:<threadId>`。
  static Map<String, CommandStatus> _stopsByThread(
    Map<String, CommandStatus> commands,
  ) {
    return {
      for (final entry in commands.entries)
        if (entry.key.startsWith('stop:')) entry.key.substring(5): entry.value,
    };
  }

  /// 订阅 Client 命令板：行内停止的在途与失败都随它收敛。
  ///
  /// 菜单在任意位置重建（打开/关闭、切换会话、上层刷新）都不会丢失在途事实，因为
  /// 事实只在命令板里；这里只持有一个只读观察与它的预算 permit。
  void _attachStopCommands() {
    final client = ref.read(anyworkClientProvider);
    final commands = client.threadCommands;
    _stopPermit ??= client.budget.acquire(
      ResourceKind.observer,
      owner: 'presentation:agent-switcher-stop:$hashCode',
    );
    final watch = commands.source.watchLatest((next) {
      if (!mounted) return;
      final stops = _stopsByThread(next.commands);
      if (mapEquals(stops, _stopCommands)) return;
      setState(() => _stopCommands = stops);
      _syncStopUnconfirmed();
    });
    _stopWatch = watch;
    _stopCommands = _stopsByThread(watch.value.commands);
    // 挂载时命令可能已经在途（重建/重开菜单）：立刻按登记时间安排阈值重建。
    _syncStopUnconfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final agents = AgentDirectoryQueries.menuOrder(widget.agents);
    final aggregateColor = _aggregateAgentColor(context, agents);
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
            selected: agent.threadId == widget.selectedThreadId,
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
            Text(context.l10n.statusAgentsCount(_countedMembers(agents))),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 14),
          ],
        ),
      ),
    );
  }

  /// 单个智能体行：层级缩进、状态图标、任务概要/角色、右侧状态、行内停止与选中勾。
  ///
  /// 图标、正文与尾部件分别落在 [MenuItemButton] 的官方槽位上，行内空间由 Flex
  /// 与行内省略分配；正文持有显式有限宽度，状态列单独保留空间，深层缩进在窄窗有界。
  /// 选中勾在所有行保留同宽占位，各行状态右边缘因此对齐。
  Widget _agentRow(
    StudioAgentView agent, {
    required bool selected,
    required double menuWidth,
  }) {
    final thread = widget.workspaceThreads
        .where((thread) => thread.id == agent.threadId)
        .firstOrNull;
    final rootProjectId = widget.workspaceThreads
        .where((candidate) => candidate.isRoot)
        .firstOrNull
        ?.workspaceId;
    final recoveryIssue = recoveryIssuesForTarget(
      widget.recoveryIssues,
      workspaceId: thread?.workspaceId ?? rootProjectId,
      threadId: agent.threadId,
    ).firstOrNull;
    final error = agent.error;
    final hasError = error != null || recoveryIssue != null;
    final summary = thread?.title.trim().isNotEmpty == true
        ? thread!.title
        : agent.task.trim().isNotEmpty
        ? agent.task
        : context.roleLabel(agent.role);
    final status = recoveryIssue == null
        ? error ?? context.threadStatusLabel(_agentThreadStatus(agent.state))
        : context.recoveryIssueLabel(recoveryIssue);
    final secondaryStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: context.colors.onSurfaceVariant);
    final role = agent.role.trim();
    final roleLabel = role.isEmpty
        ? null
        : (isRetiredAgentRow(agent)
              ? context.l10n.agentRoleRetired
              : context.roleLabel(role));
    final frozen = agent.frozenModel ?? thread?.frozenModel;
    final account = ref
        .watch(modelSelectionAccountsProvider)
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
    final stop = AgentListStopState.resolve(
      agent: agent,
      acceptedExecutionId: _acceptedStopFor(agent),
    );
    final rowWidth = (menuWidth - 88 - indent).clamp(0.0, menuWidth);
    final statusGap = rowWidth.clamp(0.0, _agentRowGap);
    final statusWidth = (rowWidth - statusGap).clamp(0.0, 84.0);
    final stopFailure = _stopFailureFor(agent);
    return MenuItemButton(
      key: StudioDriverKeys.agentRow(agent.threadId),
      onPressed: recoveryIssue?.blocksAccess == true
          ? null
          : () {
              unawaited(
                ref
                    .read(anyworkClientProvider)
                    .directoryCommands
                    .selectAgentThread(agent.threadId)
                    .catchError((Object error) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.recoveryIssueFailureLabel(error),
                          ),
                        ),
                      );
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
              : _statusColor(context, agent),
        ),
      ),
      // 行尾：独立的停止按钮 + 选中勾占位；两者各有自己的点击与语义。
      trailingIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recoveryIssue?.canRetry == true)
            IconButton(
              key: StudioDriverKeys.retryRecoveryIssue(recoveryIssue!.id),
              tooltip: context.l10n.runtimeFatalRetry,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: () async {
                try {
                  await ref
                      .read(anyworkClientProvider)
                      .directoryCommands
                      .retryRecovery();
                } on Object catch (error) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },
              icon: const Icon(Icons.refresh),
            ),
          _stopControl(agent, stop, summary: summary),
          Visibility(
            visible: selected,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: const Icon(Icons.check, size: _agentCheckSize),
          ),
        ],
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
            if (stop.action == AgentListStopAction.stopping)
              Text(
                context.l10n.agentStopping,
                key: StudioDriverKeys.agentStopNote(agent.threadId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: secondaryStyle,
              )
            else if (stop.action ==
                AgentListStopAction.stoppedWaitingScheduling)
              Text(
                context.l10n.agentStopWaitingScheduling,
                key: StudioDriverKeys.agentStopNote(agent.threadId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: secondaryStyle,
              ),
            if (stop.action == AgentListStopAction.stop &&
                _stopPendingFor(agent.threadId, stop.executionId!) &&
                _stopUnconfirmedFor(agent))
              Text(
                context.l10n.composerBlockerUnknown,
                key: ValueKey('agent-stop-unconfirmed-${agent.threadId}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: secondaryStyle,
              ),
            if (stopFailure case final failure?)
              Text(
                context.l10n.agentStopFailed(
                  _stopFailureText(context, failure),
                ),
                key: ValueKey('agent-stop-failure-${agent.threadId}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: context.colors.error),
              ),
          ],
        ),
      ),
    );
  }

  /// 行内停止控制：只有可停止、正在停止或等待调度时出现，永不是「继续」。
  Widget _stopControl(
    StudioAgentView agent,
    AgentListStopState stop, {
    required String summary,
  }) {
    if (!stop.showsControl) return const SizedBox.shrink();
    if (stop.action == AgentListStopAction.stop) {
      final executionId = stop.executionId!;
      // 请求在途：只禁用按钮，不写「正在停止」——受理还没被服务端证明。在途事实
      // 来自 Client 命令板，重建或重开菜单都能恢复。
      final pending = _stopPendingFor(agent.threadId, executionId);
      // 迟迟未被受理：允许用同一执行编号再试一次，并说明结果未确认。
      final unconfirmed = pending && _stopUnconfirmedFor(agent);
      return IconButton(
        key: StudioDriverKeys.agentStop(agent.threadId),
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        tooltip: context.l10n.agentStopSemantics(summary),
        onPressed: pending && !unconfirmed
            ? null
            : () => _requestStop(agent, executionId),
        icon: pending && !unconfirmed
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.stop_circle_outlined),
      );
    }
    // 正在停止与等待主智能体调度的行没有可点操作，只在行内说明状态。
    return const SizedBox.shrink();
  }
}

/// `n agents` 菜单最多占用的高度，超出部分滚动查看。
const double _agentMenuMaxHeight = 320;

/// 任务概要与状态文本之间的行内间距。
const double _agentRowGap = 12;

/// 单层层级缩进的步长，以及行尾选中勾占位宽度。
const double _agentIndentStep = 12;
const double _agentCheckSize = 18;

String _stopFailureText(BuildContext context, Object error) {
  final reason = studioFailureReason(error);
  if (reason != null) return context.composerFailureReasonLabel(reason);
  final failure = error is StudioFailure ? error : null;
  return failure?.message ?? error.toString();
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
