import 'package:anywork_client/studio_client.dart' show ModelRouteQueries;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/studio_models.dart';
import '../../presentation/providers/lsp_store.dart';
import '../../presentation/providers/settings_store.dart';
import '../../presentation/providers/thread_directory_store.dart';
import '../../presentation/providers/thread_session_store.dart';
import '../../app/theme/studio_tokens.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'context_usage_readout.dart';
import 'session_selectors.dart';
import 'status_bar_item.dart';
import 'status_detail_panel.dart';

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
    final session = ref.watch(threadSessionStoreProvider(threadId));
    final directory = ref.watch(threadDirectoryStoreProvider);
    final settings = ref.watch(settingsStoreProvider);
    final facts = ModelRouteQueries.threadStatus(
      threadId: threadId,
      directory: [...directory.window.threads, ...directory.overlayThreads],
      runtime: session.runtime,
    );
    final thread = facts.thread;
    if (thread == null) return const SizedBox(height: 38);
    return ThreadStatusBar(
      thread: thread,
      runtime: facts.runtime,
      providers: providersWithCatalogMetadata(
        settings.canonical?.providers ?? const [],
        settings.providerCatalog,
      ),
      lspServers: ref.watch(lspStoreProvider).value?.servers ?? const [],
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
    required this.thread,
    required this.runtime,
    required this.providers,
    required this.lspServers,
    this.showTodo = false,
    this.todoExpanded = false,
    this.onToggleTodo,
    this.showPlanEntry = false,
    this.onOpenPlan,
  });

  final StudioThread thread;
  final ThreadRuntimeView? runtime;
  final List<ProviderSettingsView> providers;
  final List<LspServerStateView> lspServers;
  final bool showTodo;
  final bool todoExpanded;
  final VoidCallback? onToggleTodo;
  final bool showPlanEntry;
  final VoidCallback? onOpenPlan;

  @override
  Widget build(BuildContext context) {
    final runtime = this.runtime;
    if (runtime == null) {
      return SizedBox(
        height: 38,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Text(thread.title),
            const SizedBox(width: 12),
            Text(context.l10n.settingsNotAvailable),
          ],
        ),
      );
    }
    final contextUsage = StudioContextProjection.fromRuntime(
      thread.id,
      runtime,
    );
    final capabilityLabel = _runtimeCapabilityLabel(context, runtime);
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
                final route = runtime.modelRoute;
                final routeModel = route == null
                    ? null
                    : modelForRoute(providers, route.providerId, route.model);
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
                        label: route?.model.isNotEmpty == true
                            ? route!.model
                            : context.l10n.settingsNotAvailable,
                        tooltip:
                            route?.unavailableReason ??
                            route?.model ??
                            context.l10n.settingsNotAvailable,
                        maxWidth: 140,
                      ),
                    if (runtime.workflow?.currentRun case final run?)
                      _WorkflowRuntimeReadout(run: run),
                    ContextUsageReadout(projection: contextUsage),
                    ThreadThroughputReadout(
                      key: StudioDriverKeys.threadThroughput,
                      threadId: thread.id,
                      runtime: runtime,
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
                        detailBuilder: (context) =>
                            _CapabilityDetail(runtime: runtime),
                      ),
                    if (hasOverflow)
                      _StatusOverflow(
                        effort: (rootEffort?.isEmpty ?? true)
                            ? null
                            : rootEffort,
                        capabilities: capabilityLabel,
                        runtime: runtime,
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

/// Owns the status-bar display lifetime for the current Thread's throughput.
///
/// The runtime remains canonical and [ModelRouteQueries.throughput] remains a
/// pure same-sample calculation. This component only keeps the last value that
/// was already valid when a later frame has no new throughput observation.
class ThreadThroughputReadout extends StatefulWidget {
  const ThreadThroughputReadout({
    required this.threadId,
    required this.runtime,
    super.key,
  });

  final String threadId;
  final ThreadRuntimeView runtime;

  @override
  State<ThreadThroughputReadout> createState() =>
      _ThreadThroughputReadoutState();
}

class _ThreadThroughputReadoutState extends State<ThreadThroughputReadout> {
  _ThroughputSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _acceptRuntime();
  }

  @override
  void didUpdateWidget(covariant ThreadThroughputReadout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) _snapshot = null;
    _acceptRuntime();
  }

  void _acceptRuntime() {
    final tokensPerSecond = ModelRouteQueries.throughput(widget.runtime);
    final live = widget.runtime.liveUsage;
    if (tokensPerSecond != null) {
      _snapshot = _ThroughputSnapshot(
        threadId: widget.threadId,
        source: _ThroughputSource.fromLive(live),
        tokensPerSecond: tokensPerSecond,
      );
      return;
    }

    final previous = _snapshot;
    if (previous == null || live == null || previous.source.matchesLive(live)) {
      return;
    }
    // A new live turn/attempt is an explicit invalidation. Do not show the
    // previous turn's speed while this new sample is incomplete.
    _snapshot = null;
  }

  @override
  Widget build(BuildContext context) {
    final tokensPerSecond = _snapshot?.threadId == widget.threadId
        ? _snapshot?.tokensPerSecond
        : null;
    return _StatusReadout(
      icon: Icons.speed_outlined,
      label: context.tokenThroughputLabel(tokensPerSecond),
      tooltip: context.l10n.statusCurrentAgentTokenSpeed,
      maxWidth: 84,
    );
  }
}

/// Identity of the live turn/attempt that produced the last valid value.
///
/// A missing live observation is deliberately not treated as a new speed
/// sample: the status bar keeps its last confirmed display until a new live
/// turn/attempt is actually observed or a replacement speed is available.
class _ThroughputSource {
  const _ThroughputSource({this.turnId, this.attemptId});

  factory _ThroughputSource.fromLive(ThreadRuntimeLiveUsageView? live) =>
      _ThroughputSource(turnId: live?.turnId, attemptId: live?.attemptId);

  final String? turnId;
  final String? attemptId;

  bool matchesLive(ThreadRuntimeLiveUsageView live) =>
      turnId != null &&
      attemptId != null &&
      turnId == live.turnId &&
      attemptId == live.attemptId;
}

class _ThroughputSnapshot {
  const _ThroughputSnapshot({
    required this.threadId,
    required this.source,
    required this.tokensPerSecond,
  });

  final String threadId;
  final _ThroughputSource source;
  final double? tokensPerSecond;
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

class _WorkflowRuntimeReadout extends StatelessWidget {
  const _WorkflowRuntimeReadout({required this.run});

  final WorkflowRunView run;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('workflow-runtime-${run.runId}'),
      child: _StatusReadout(
        key: ValueKey('workflow-state-${run.currentStateId}'),
        icon: run.terminal ? Icons.check_circle_outline : Icons.route_outlined,
        label: context.workflowStateLabel(run.currentStateId),
        tooltip:
            '${context.workflowModeLabel(run.modeId)} · ${context.workflowStateLabel(run.currentStateId)}',
        maxWidth: 140,
      ),
    );
  }
}

String _runtimeCapabilityLabel(
  BuildContext context,
  ThreadRuntimeView runtime,
) {
  final parts = [
    if (runtime.activeSkills.isNotEmpty)
      context.l10n.statusSkillsCount(runtime.activeSkills.length),
    if (runtime.activeMcpServers.isNotEmpty)
      context.l10n.statusMcpCount(runtime.activeMcpServers.length),
    if (runtime.activeLspServers.isNotEmpty)
      context.l10n.statusLspCount(runtime.activeLspServers.length),
  ];
  return parts.join(' · ');
}

class _StatusOverflow extends StatefulWidget {
  const _StatusOverflow({
    required this.effort,
    required this.capabilities,
    required this.runtime,
    this.lspServers = const <LspServerStateView>[],
    this.showPlanEntry = false,
    this.onOpenPlan,
  });

  final String? effort;
  final String capabilities;
  final ThreadRuntimeView runtime;
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
        runtime: widget.runtime,
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
  const _CapabilityDetail({required this.runtime});

  final ThreadRuntimeView runtime;

  @override
  Widget build(BuildContext context) {
    return StatusDetailPanel(
      title: context.l10n.statusCapabilitiesTitle,
      children: [
        if (runtime.activeSkills.isNotEmpty)
          StatusDetailIconList(
            icon: Icons.extension_outlined,
            title: context.l10n.statusSkillsSection,
            items: runtime.activeSkills,
            itemKey: StudioDriverKeys.statusActiveSkill,
            tone: StudioTone.brand,
          ),
        if (runtime.activeMcpServers.isNotEmpty)
          StatusDetailIconRow(
            icon: Icons.hub_outlined,
            title: context.l10n.statusMcpSection,
            detail: runtime.activeMcpServers.join(', '),
            tone: StudioTone.success,
          ),
        if (runtime.activeLspServers.isNotEmpty)
          StatusDetailIconRow(
            icon: Icons.terminal_outlined,
            title: context.l10n.statusLspSection,
            detail: runtime.activeLspServers.join(', '),
            tone: StudioTone.neutral,
          ),
      ],
    );
  }
}
