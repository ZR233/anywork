import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/studio_models.dart';
import '../../presentation/providers/lsp_store.dart';
import '../../presentation/providers/mode_catalog_store.dart';
import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'context_usage_readout.dart';
import 'session_selectors.dart';
import 'status_bar_item.dart';
import 'status_detail_panel.dart';
import 'status_view.dart';

/// Reads one stable Thread owner and passes a single frame to the pure View.
class ThreadStatusConnector extends ConsumerWidget {
  const ThreadStatusConnector({
    super.key,
    required this.threadId,
    this.showTodo = false,
    this.todoExpanded = false,
    this.onToggleTodo,
    this.showPlanEntry = false,
    this.onOpenPlan,
  });

  final String threadId;
  final bool showTodo;
  final bool todoExpanded;
  final VoidCallback? onToggleTodo;
  final bool showPlanEntry;
  final VoidCallback? onOpenPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(statusBarViewProvider(threadId));
    if (status == null) return const SizedBox(height: 38);
    return ThreadStatusBar(
      threadId: threadId,
      thread: status.thread,
      accounts: status.accounts,
      lspServers: ref.watch(lspStoreProvider).value?.servers ?? const [],
      modelRoute: status.modelRoute,
      workflowRun: status.workflowRun,
      activeSkills: status.activeSkills,
      activeMcpServers: status.activeMcpServers,
      activeLspServers: status.activeLspServers,
      showTodo: showTodo,
      todoExpanded: todoExpanded,
      onToggleTodo: onToggleTodo,
      showPlanEntry: showPlanEntry,
      onOpenPlan: onOpenPlan,
    );
  }
}

class ThreadStatusBar extends StatelessWidget {
  const ThreadStatusBar({
    super.key,
    required this.threadId,
    required this.thread,
    required this.accounts,
    required this.lspServers,
    this.modelRoute,
    this.workflowRun,
    this.activeSkills = const [],
    this.activeMcpServers = const [],
    this.activeLspServers = const [],
    this.showTodo = false,
    this.todoExpanded = false,
    this.onToggleTodo,
    this.showPlanEntry = false,
    this.onOpenPlan,
  });

  final String threadId;
  final StudioThread thread;
  final List<AccountSettingsView> accounts;
  final List<LspServerStateView> lspServers;
  final ThreadModelRouteView? modelRoute;
  final WorkflowRunView? workflowRun;
  final List<String> activeSkills;
  final List<String> activeMcpServers;
  final List<String> activeLspServers;
  final bool showTodo;
  final bool todoExpanded;
  final VoidCallback? onToggleTodo;
  final bool showPlanEntry;
  final VoidCallback? onOpenPlan;

  @override
  Widget build(BuildContext context) {
    final capabilityLabel = _capabilityLabel(
      context,
      activeSkills: activeSkills,
      activeMcpServers: activeMcpServers,
      activeLspServers: activeLspServers,
    );
    final lspActiveServers = [
      for (final server in lspServers)
        if (_lspActiveActivity(server) != null) server,
    ];
    return DecoratedBox(
      decoration: BoxDecoration(color: context.colors.surface),
      child: SizedBox(
        height: 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.center,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showModel = constraints.maxWidth >= 610;
                final showCapabilities = constraints.maxWidth >= 840;
                final showLspActivity = constraints.maxWidth >= 850;
                final route = modelRoute;
                final routeModel = route == null
                    ? null
                    : modelForRoute(accounts, route.accountId, route.modelId);
                final hasOverflow =
                    (thread.isRoot &&
                        (routeModel?.reasoningEfforts.isNotEmpty ?? false)) ||
                    (!showCapabilities && capabilityLabel.isNotEmpty) ||
                    (!showLspActivity && lspActiveServers.isNotEmpty) ||
                    showPlanEntry;
                final rootEffort = thread.isRoot ? route?.effort?.trim() : null;
                return Row(
                  children: [
                    if (showTodo)
                      IconButton(
                        key: const ValueKey('todo-open-button'),
                        tooltip: context.l10n.timelineTodoListFallback,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        iconSize: 18,
                        icon: Icon(
                          todoExpanded
                              ? Icons.checklist
                              : Icons.checklist_outlined,
                          color: todoExpanded
                              ? context.colors.onPrimaryContainer
                              : context.colors.onSurfaceVariant,
                        ),
                        onPressed: onToggleTodo,
                      ),
                    _StatusReadout(
                      icon: Icons.account_tree_outlined,
                      label: thread.isRetiredAgent
                          ? context.l10n.settingsStateDisabled
                          : context.roleLabel(thread.role),
                      tooltip: thread.isRetiredAgent
                          ? context.l10n.agentRoleRetired
                          : '${thread.title} · ${context.threadStatusLabel(thread.status)}',
                      maxWidth: 96,
                    ),
                    if (showModel && thread.isAgent)
                      _StatusReadout(
                        icon: Icons.smart_toy_outlined,
                        label: route?.modelId.isNotEmpty == true
                            ? route!.modelId
                            : context.l10n.settingsNotAvailable,
                        tooltip:
                            route?.unavailableReason ??
                            route?.modelId ??
                            context.l10n.settingsNotAvailable,
                        maxWidth: 140,
                      ),
                    if (workflowRun case final run?)
                      _WorkflowRuntimeReadout(
                        run: run,
                        maxWidth: constraints.maxWidth >= 1000 ? 260 : 140,
                      ),
                    _ContextUsageConnector(threadId: threadId),
                    ThreadThroughputReadout(
                      key: StudioDriverKeys.threadThroughput,
                      threadId: threadId,
                    ),
                    if (showLspActivity && lspActiveServers.isNotEmpty)
                      _LspActivityReadout(servers: lspActiveServers),
                    if (showCapabilities && capabilityLabel.isNotEmpty)
                      _StatusReadout(
                        icon: Icons.tune_outlined,
                        label: capabilityLabel,
                        tooltip: context.l10n.statusCapabilitiesTitle,
                        detailWidth: 520,
                        maxWidth: 160,
                        detailBuilder: (context) => _CapabilityDetail(
                          activeSkills: activeSkills,
                          activeMcpServers: activeMcpServers,
                          activeLspServers: activeLspServers,
                        ),
                      ),
                    if (hasOverflow)
                      _StatusOverflow(
                        effort: (rootEffort?.isEmpty ?? true)
                            ? null
                            : rootEffort,
                        capabilities: capabilityLabel,
                        activeSkills: activeSkills,
                        activeMcpServers: activeMcpServers,
                        activeLspServers: activeLspServers,
                        lspServers: showLspActivity
                            ? const <LspServerStateView>[]
                            : lspActiveServers,
                        showPlanEntry: showPlanEntry,
                        onOpenPlan: onOpenPlan,
                      ),
                    const Spacer(),
                    const SizedBox(width: 8),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextUsageConnector extends ConsumerWidget {
  const _ContextUsageConnector({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projection = ref.watch(statusContextProjectionProvider(threadId));
    if (projection == null) return const SizedBox.shrink();
    return ContextUsageReadout(projection: projection);
  }
}

/// Pure readout for the current Thread's canonical throughput query.
class ThreadThroughputReadout extends ConsumerWidget {
  const ThreadThroughputReadout({required this.threadId, super.key});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projection = ref.watch(statusThroughputProjectionProvider(threadId));
    return _StatusReadout(
      icon: Icons.speed_outlined,
      label: context.tokenThroughputLabel(projection?.tokensPerSecond),
      tooltip: context.l10n.statusLastConfirmedAgentTokenSpeed,
      maxWidth: 84,
    );
  }
}

class _LspActivityReadout extends StatelessWidget {
  const _LspActivityReadout({required this.servers});

  final List<LspServerStateView> servers;

  @override
  Widget build(BuildContext context) {
    final activeServers = servers;
    if (activeServers.isEmpty) {
      return const SizedBox.shrink();
    }
    final first = activeServers.first;
    final firstActivity = _lspActiveActivity(first)!;
    final firstLabel = _lspActivityLabel(context, firstActivity);
    final percentage = _lspActivityPercentage(firstActivity);
    final label = activeServers.length == 1
        ? (percentage == null
              ? firstLabel
              : '$firstLabel ${context.l10n.statusLspActivityPercentage(percentage)}')
        : '$firstLabel · ${context.l10n.statusLspCount(activeServers.length)}';
    final tooltip = [
      for (final server in activeServers)
        '${server.displayName} · ${_lspServerActivitySummary(context, server)}',
    ].join('\n');
    return KeyedSubtree(
      key: StudioDriverKeys.lspActivity(),
      child: _StatusReadout(
        key: StudioDriverKeys.lspActivityDetail(),
        icon: Icons.terminal_outlined,
        label: label,
        tooltip: tooltip,
        maxWidth: 120,
        detailBuilder: (context) => _LspActivityDetail(servers: activeServers),
      ),
    );
  }
}

LspActivity? _lspActiveActivity(LspServerStateView server) {
  return switch (server.state) {
    LspAvailableState(activity: final activity)
        when activity is! LspIdleActivity =>
      activity,
    LspAvailableState() ||
    LspCheckingState() ||
    LspUnavailableState() ||
    LspDisabledState() => null,
  };
}

String _lspActivityLabel(BuildContext context, LspActivity activity) {
  return switch (activity) {
    LspIndexingActivity() => context.l10n.statusLspIndexing,
    LspBusyActivity() => context.l10n.statusLspBusy,
    LspIdleActivity() => context.l10n.settingsLspActivityIdle,
  };
}

int? _lspActivityPercentage(LspActivity activity) => switch (activity) {
  LspBusyActivity(:final percentage) ||
  LspIndexingActivity(:final percentage) => percentage,
  LspIdleActivity() => null,
};

String _lspServerActivitySummary(
  BuildContext context,
  LspServerStateView server,
) {
  final activity = _lspActiveActivity(server);
  if (activity == null) return '';
  return [
    _lspActivityLabel(context, activity),
    if (_lspActivityPercentage(activity) case final percentage?)
      context.l10n.statusLspActivityPercentage(percentage),
    if (activity
        case LspBusyActivity(title: final title?) ||
            LspIndexingActivity(title: final title?)
        when title.isNotEmpty)
      title,
    if (activity
        case LspBusyActivity(message: final message?) ||
            LspIndexingActivity(message: final message?)
        when message.isNotEmpty)
      message,
  ].join(' · ');
}

class _LspActivityDetail extends StatelessWidget {
  const _LspActivityDetail({required this.servers});

  final List<LspServerStateView> servers;

  @override
  Widget build(BuildContext context) {
    return StatusDetailPanel(
      title: context.l10n.statusLspSection,
      children: [
        for (final server in servers)
          StatusDetailIconRow(
            icon: Icons.terminal_outlined,
            title: server.displayName,
            detail: _lspServerActivitySummary(context, server),
            tone: StudioTone.neutral,
          ),
      ],
    );
  }
}

class _WorkflowRuntimeReadout extends ConsumerWidget {
  const _WorkflowRuntimeReadout({required this.run, this.maxWidth = 140});

  final WorkflowRunView run;
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(modeCatalogStoreProvider).value;
    final deleted = catalog == null
        ? run.modeDeleted
        : !catalog.modes.any((mode) => mode.id == run.modeId);
    final stateTitle = run.currentStateTitle.isEmpty
        ? context.workflowStateLabel(run.currentStateId)
        : run.currentStateTitle;
    final modeName = run.modeDisplayName.isEmpty
        ? context.workflowModeLabel(run.modeId)
        : run.modeDisplayName;
    return KeyedSubtree(
      key: ValueKey('workflow-runtime-${run.runId}'),
      child: _StatusReadout(
        key: ValueKey('workflow-state-${run.currentStateId}'),
        icon: run.terminal ? Icons.check_circle_outline : Icons.route_outlined,
        label: deleted
            ? '$stateTitle · ${context.l10n.modeDeletedUsingSnapshot}'
            : stateTitle,
        tooltip:
            '$modeName · $stateTitle${deleted ? ' · ${context.l10n.modeDeletedUsingSnapshot}' : ''}',
        maxWidth: deleted ? maxWidth : 140,
      ),
    );
  }
}

String _capabilityLabel(
  BuildContext context, {
  required List<String> activeSkills,
  required List<String> activeMcpServers,
  required List<String> activeLspServers,
}) {
  final parts = [
    if (activeSkills.isNotEmpty)
      context.l10n.statusSkillsCount(activeSkills.length),
    if (activeMcpServers.isNotEmpty)
      context.l10n.statusMcpCount(activeMcpServers.length),
    if (activeLspServers.isNotEmpty)
      context.l10n.statusLspCount(activeLspServers.length),
  ];
  return parts.join(' · ');
}

class _StatusOverflow extends StatefulWidget {
  const _StatusOverflow({
    required this.effort,
    required this.capabilities,
    required this.activeSkills,
    required this.activeMcpServers,
    required this.activeLspServers,
    this.lspServers = const <LspServerStateView>[],
    this.showPlanEntry = false,
    this.onOpenPlan,
  });

  final String? effort;
  final String capabilities;
  final List<String> activeSkills;
  final List<String> activeMcpServers;
  final List<String> activeLspServers;
  final List<LspServerStateView> lspServers;
  final bool showPlanEntry;
  final VoidCallback? onOpenPlan;

  @override
  State<_StatusOverflow> createState() => _StatusOverflowState();
}

class _StatusOverflowState extends State<_StatusOverflow> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      key: const ValueKey('status-overflow'),
      controller: _controller,
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        if (widget.effort case final value?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '${context.l10n.statusReasoningEffort}: $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (widget.capabilities.isNotEmpty)
          MenuItemButton(
            overflowAxis: Axis.vertical,
            onPressed: () =>
                _showDetail(context, _StatusOverflowAction.capabilities),
            child: Text(
              widget.capabilities,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (widget.lspServers.isNotEmpty)
          MenuItemButton(
            key: StudioDriverKeys.lspActivityOverflow(),
            overflowAxis: Axis.vertical,
            onPressed: () => _showDetail(context, _StatusOverflowAction.lsp),
            child: Text(
              _lspOverflowSummary(context, widget.lspServers),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (widget.showPlanEntry)
          MenuItemButton(
            key: StudioDriverKeys.statusPlanEntry,
            overflowAxis: Axis.vertical,
            onPressed: () {
              _controller.close();
              widget.onOpenPlan?.call();
            },
            child: Text(context.l10n.statusPlanEntry),
          ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_horiz, size: 18),
      ),
    );
  }

  void _showDetail(BuildContext context, _StatusOverflowAction action) {
    final detail = switch (action) {
      _StatusOverflowAction.capabilities => _CapabilityDetail(
        activeSkills: widget.activeSkills,
        activeMcpServers: widget.activeMcpServers,
        activeLspServers: widget.activeLspServers,
      ),
      _StatusOverflowAction.lsp => _LspActivityDetail(
        servers: widget.lspServers,
      ),
    };
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(child: detail),
          ),
        ),
      ),
    );
  }
}

enum _StatusOverflowAction { capabilities, lsp }

String _lspOverflowSummary(
  BuildContext context,
  List<LspServerStateView> servers,
) {
  final first = servers.first;
  final summary =
      '${first.displayName} · ${_lspServerActivitySummary(context, first)}';
  if (servers.length == 1) {
    return summary;
  }
  return '$summary · ${context.l10n.statusLspCount(servers.length)}';
}

class _StatusReadout extends StatelessWidget {
  const _StatusReadout({
    required this.label,
    required this.tooltip,
    this.icon,
    this.detailBuilder,
    this.detailWidth = 300,
    this.maxWidth = 180,
    super.key,
  });

  final IconData? icon;
  final String label;
  final String tooltip;
  final WidgetBuilder? detailBuilder;
  final double detailWidth;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return StatusBarItem(
      icon: icon,
      label: label,
      tooltip: detailBuilder == null
          ? (tooltip.isEmpty ? label : tooltip)
          : null,
      semanticsLabel: tooltip.isEmpty ? label : tooltip,
      detailBuilder: detailBuilder,
      detailWidth: detailWidth,
      maxWidth: maxWidth,
    );
  }
}

class _CapabilityDetail extends StatelessWidget {
  const _CapabilityDetail({
    required this.activeSkills,
    required this.activeMcpServers,
    required this.activeLspServers,
  });

  final List<String> activeSkills;
  final List<String> activeMcpServers;
  final List<String> activeLspServers;

  @override
  Widget build(BuildContext context) {
    return StatusDetailPanel(
      title: context.l10n.statusCapabilitiesTitle,
      children: [
        if (activeSkills.isNotEmpty)
          StatusDetailIconList(
            icon: Icons.extension_outlined,
            title: context.l10n.statusSkillsSection,
            items: activeSkills,
            itemKey: StudioDriverKeys.statusActiveSkill,
            tone: StudioTone.brand,
          ),
        if (activeMcpServers.isNotEmpty)
          StatusDetailIconRow(
            icon: Icons.hub_outlined,
            title: context.l10n.statusMcpSection,
            detail: activeMcpServers.join(', '),
            tone: StudioTone.success,
          ),
        if (activeLspServers.isNotEmpty)
          StatusDetailIconRow(
            icon: Icons.terminal_outlined,
            title: context.l10n.statusLspSection,
            detail: activeLspServers.join(', '),
            tone: StudioTone.neutral,
          ),
      ],
    );
  }
}
