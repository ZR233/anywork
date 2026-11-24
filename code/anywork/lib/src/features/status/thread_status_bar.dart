import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/mode_catalog_store.dart';
import '../../presentation/providers/thread_session_store.dart';
import '../conversation/timeline/view_models/timeline_view_model.dart';
import '../conversation/workspace/conversation_workspace.dart';
import '../../shared/studio_driver_keys.dart';

import 'package:anywork_client/conversation.dart'
    show CurrentQueryScope, CurrentStateFieldReader, decodeCurrentWorkflowState;

import 'context_usage_readout.dart';
import 'session_selectors.dart';
import 'started_items_panel.dart';
import 'status_bar_item.dart';
import 'status_view.dart';
import 'workflow_graph_panel.dart';

/// The shell supplies identity and UI intentions, never domain lists.
class ThreadStatusConnector extends ConsumerWidget {
  const ThreadStatusConnector({
    super.key,
    required this.threadId,
    this.showTodo = false,
    this.todoExpanded = false,
    this.onToggleTodo,
    this.workflowExpanded = false,
    this.onToggleWorkflow,
    this.showPlanEntry = false,
    this.planExpanded = false,
    this.onOpenPlan,
    this.hasSidebarPanels = false,
    this.sidebarOpen = false,
    this.onToggleSidebar,
  });

  final String threadId;
  final bool showTodo;
  final bool todoExpanded;
  final VoidCallback? onToggleTodo;
  final bool workflowExpanded;
  final VoidCallback? onToggleWorkflow;
  final bool showPlanEntry;
  final bool planExpanded;
  final VoidCallback? onOpenPlan;
  final bool hasSidebarPanels;
  final bool sidebarOpen;
  final VoidCallback? onToggleSidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(statusBarViewProvider(threadId));
    if (status == null) return const SizedBox(height: 38);
    return ThreadStatusBar(
      status: status,
      contextReadout: _ContextUsageConnector(threadId: threadId),
      throughputReadout: ThreadThroughputReadout(
        key: StudioDriverKeys.threadThroughput,
        threadId: threadId,
      ),
      startedItemsEntry: StartedItemsEntry(threadId: threadId),
      workflowReadout: _DeferredWorkflowReadout(
        threadId: threadId,
        inline: status.workflowRun,
        expanded: workflowExpanded,
        onToggle: onToggleWorkflow,
      ),
      showTodo: showTodo,
      todoExpanded: todoExpanded,
      onToggleTodo: onToggleTodo,
      showPlanEntry: showPlanEntry,
      planExpanded: planExpanded,
      onOpenPlan: onOpenPlan,
      hasSidebarPanels: hasSidebarPanels,
      sidebarOpen: sidebarOpen,
      onToggleSidebar: onToggleSidebar,
    );
  }
}

/// Pure chrome. Each live readout owns its own observation below this boundary.
class ThreadStatusBar extends StatelessWidget {
  const ThreadStatusBar({
    super.key,
    required this.status,
    required this.contextReadout,
    required this.throughputReadout,
    required this.startedItemsEntry,
    this.workflowReadout,
    this.showTodo = false,
    this.todoExpanded = false,
    this.onToggleTodo,
    this.showPlanEntry = false,
    this.planExpanded = false,
    this.onOpenPlan,
    this.hasSidebarPanels = false,
    this.sidebarOpen = false,
    this.onToggleSidebar,
  });

  final StatusBarView status;
  final Widget contextReadout;
  final Widget throughputReadout;
  final Widget startedItemsEntry;
  final Widget? workflowReadout;
  final bool showTodo;
  final bool todoExpanded;
  final VoidCallback? onToggleTodo;
  final bool showPlanEntry;
  final bool planExpanded;
  final VoidCallback? onOpenPlan;
  final bool hasSidebarPanels;
  final bool sidebarOpen;
  final VoidCallback? onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    final row = status.row;
    final backend = row.backend;
    if (backend is! NativeAgentBackendView) {
      throw StateError('Native status bar cannot consume an ACP session');
    }
    final route = status.modelRoute;
    final routeModel = route == null
        ? null
        : modelForRoute(status.accounts, route.accountId, route.modelId);
    final hasEffort =
        row.isRootRow && (routeModel?.reasoningEfforts.isNotEmpty ?? false);
    final role = row.isChildRow && isRetiredAgentRole(row.role)
        ? context.l10n.agentRoleRetired
        : context.roleLabel(row.role);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: context.colors.outlineVariant)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 38,
        // No width thresholds hide entries. Extremely narrow windows can scroll
        // the compact strip, retaining keyboard and pointer access.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.max(0, constraints.maxWidth - 16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showTodo)
                        IconButton(
                          key: const ValueKey('todo-open-button'),
                          tooltip: context.l10n.timelineTodoListFallback,
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          icon: Icon(
                            todoExpanded
                                ? Icons.checklist
                                : Icons.checklist_outlined,
                            color: todoExpanded
                                ? context.colors.primary
                                : context.colors.onSurfaceVariant,
                          ),
                          onPressed: onToggleTodo,
                        ),
                      StatusBarItem(
                        icon: Icons.account_tree_outlined,
                        label:
                            '$role · ${row.title} · ${context.threadStatusLabel(backend.status)}',
                      ),
                      if (row.isChildRow)
                        StatusBarItem(
                          icon: Icons.smart_toy_outlined,
                          label:
                              route?.unavailableReason ??
                              route?.modelId ??
                              context.l10n.settingsNotAvailable,
                        ),
                      if (workflowReadout case final workflow?) ...[
                        const SizedBox(width: 4),
                        workflow,
                      ],
                      if (showPlanEntry) ...[
                        const SizedBox(width: 6),
                        _StatusPlanPill(
                          expanded: planExpanded,
                          onTap: onOpenPlan,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      contextReadout,
                      throughputReadout,
                      startedItemsEntry,
                      if (hasEffort) _StatusOverflow(effort: route?.effort),
                      ConversationSidebarToggleButton(
                        available: hasSidebarPanels,
                        expanded: sidebarOpen,
                        onPressed: onToggleSidebar,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPlanPill extends StatelessWidget {
  const _StatusPlanPill({required this.expanded, this.onTap});

  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fgColor = expanded
        ? context.colors.primary
        : context.colors.onSurfaceVariant;
    final bgColor = expanded
        ? context.colors.primaryContainer.withValues(alpha: 0.45)
        : Colors.transparent;
    final borderColor = expanded
        ? context.colors.primary.withValues(alpha: 0.55)
        : context.colors.outlineVariant.withValues(alpha: 0.65);
    return Tooltip(
      message: context.l10n.statusPlanEntry,
      child: Material(
        color: bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          key: StudioDriverKeys.statusPlanEntry,
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          onTap: onTap,
          child: SizedBox(
            height: 26,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 14, color: fgColor),
                  const SizedBox(width: 5),
                  Text(
                    context.l10n.rightSidebarTabPlan,
                    style: context.text.labelSmall?.copyWith(
                      color: fgColor,
                      fontWeight: expanded ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
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
    final command = ref.watch(
      startedItemsViewModelProvider(threadId).select((value) {
        final state = value.asData?.value;
        return (
          pending: state?.pending.contains('compact') ?? false,
          error: state?.errors['compact'],
        );
      }),
    );
    final busy =
        ref.watch(
          statusBarViewProvider(threadId).select((value) => value?.isBusy),
        ) ??
        true;
    final compacting = command.pending;
    return ContextUsageReadout(
      projection: projection,
      compacting: compacting,
      compactionFailed: command.error != null,
      onCompact: busy || compacting || !projection.hasUsage
          ? null
          : () => unawaited(
              ref
                  .read(startedItemsViewModelProvider(threadId).notifier)
                  .compact(),
            ),
    );
  }
}

class ThreadThroughputReadout extends ConsumerWidget {
  const ThreadThroughputReadout({required this.threadId, super.key});
  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projection = ref.watch(statusThroughputProjectionProvider(threadId));
    return TokenThroughputReadout(tokensPerSecond: projection?.tokensPerSecond);
  }
}

class _DeferredWorkflowReadout extends ConsumerStatefulWidget {
  const _DeferredWorkflowReadout({
    required this.threadId,
    required this.inline,
    this.expanded = false,
    this.onToggle,
  });

  final String threadId;
  final WorkflowRunView? inline;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  ConsumerState<_DeferredWorkflowReadout> createState() =>
      _DeferredWorkflowReadoutState();
}

class _DeferredWorkflowReadoutState
    extends ConsumerState<_DeferredWorkflowReadout> {
  CurrentStateField? _field;
  CurrentQueryScope? _scope;
  WorkflowRunView? _run;
  bool _loading = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(_sync));
  }

  @override
  void didUpdateWidget(covariant _DeferredWorkflowReadout oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(Future<void>.microtask(_sync));
  }

  void _retire() {
    _epoch++;
    final scope = _scope;
    _scope = null;
    scope?.retire();
    if (scope != null) unawaited(scope.close());
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final runtime = ref
        .read(threadSessionStoreProvider(widget.threadId))
        .runtime;
    final field = runtime?.deferredField('workflow');
    if (field == null) {
      _retire();
      _field = null;
      _run = null;
      _loading = false;
      if (mounted) setState(() {});
      return;
    }
    if (_field == field && (_loading || _run != null)) return;
    _retire();
    _field = field;
    _run = null;
    final lease = ref.read(timelineSessionOwnerProvider).lease(widget.threadId);
    if (lease == null || lease.isRetired) return;
    final epoch = ++_epoch;
    final scope = lease.openCurrentScope(generation: lease.generation);
    _scope = scope;
    _loading = true;
    if (mounted) setState(() {});
    try {
      final run = decodeCurrentWorkflowState(await scope.readStateField(field))
          .currentRun;
      if (!mounted || epoch != _epoch || field != _field || lease.isRetired) {
        return;
      }
      _run = run;
    } finally {
      if (epoch == _epoch) {
        _loading = false;
        if (identical(_scope, scope)) _scope = null;
        scope.retire();
        unawaited(scope.close());
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(
      threadSessionStoreProvider(widget.threadId)
          .select((state) => state.runtime),
    );
    final field = runtime?.deferredField('workflow');
    if (field != null && field != _field && !_loading) {
      unawaited(Future<void>.microtask(_sync));
    }
    final run = field == null
        ? widget.inline
        : field == _field
        ? _run
        : null;
    return run == null
        ? const SizedBox.shrink()
        : _WorkflowRuntimeConnector(
            run: run,
            expanded: widget.expanded,
            onToggle: widget.onToggle,
          );
  }
}

class _WorkflowRuntimeConnector extends ConsumerWidget {
  const _WorkflowRuntimeConnector({
    required this.run,
    this.expanded = false,
    this.onToggle,
  });
  final WorkflowRunView run;
  final bool expanded;
  final VoidCallback? onToggle;

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
      child: WorkflowStatusReadout(
        key: ValueKey('workflow-state-${run.currentStateId}'),
        stateTitle: stateTitle,
        modeName: modeName,
        deleted: deleted,
        terminal: run.terminal,
        expanded: expanded,
        onTap: onToggle,
      ),
    );
  }
}

class WorkflowStatusReadout extends StatelessWidget {
  const WorkflowStatusReadout({
    required this.stateTitle,
    required this.modeName,
    this.deleted = false,
    this.terminal = false,
    this.expanded = false,
    this.onTap,
    super.key,
  });

  final String stateTitle;
  final String modeName;
  final bool deleted;
  final bool terminal;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => WorkflowStatusPill(
    stateTitle: stateTitle,
    modeName: modeName,
    deleted: deleted,
    terminal: terminal,
    expanded: expanded,
    onTap: onTap,
  );
}

class _StatusOverflow extends StatefulWidget {
  const _StatusOverflow({required this.effort});
  final String? effort;

  @override
  State<_StatusOverflow> createState() => _StatusOverflowState();
}

class _StatusOverflowState extends State<_StatusOverflow> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    key: const ValueKey('status-overflow'),
    childFocusNode: _focusNode,
    menuChildren: [
      if (widget.effort case final effort? when effort.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('${context.l10n.statusReasoningEffort}: $effort'),
        ),
    ],
    builder: (context, controller, child) => IconButton(
      focusNode: _focusNode,
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.more_horiz, size: 18),
    ),
  );
}
