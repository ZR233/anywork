import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/mode_catalog_store.dart';
import '../../shared/studio_driver_keys.dart';
import 'context_usage_readout.dart';
import 'session_selectors.dart';
import 'started_items_panel.dart';
import 'status_bar_item.dart';
import 'status_view.dart';

/// The shell supplies identity and UI intentions, never domain lists.
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
      status: status,
      contextReadout: _ContextUsageConnector(threadId: threadId),
      throughputReadout: ThreadThroughputReadout(
        key: StudioDriverKeys.threadThroughput,
        threadId: threadId,
      ),
      startedItemsEntry: StartedItemsEntry(threadId: threadId),
      workflowReadout: status.workflowRun == null
          ? null
          : _WorkflowRuntimeConnector(run: status.workflowRun!),
      showTodo: showTodo,
      todoExpanded: todoExpanded,
      onToggleTodo: onToggleTodo,
      showPlanEntry: showPlanEntry,
      onOpenPlan: onOpenPlan,
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
    this.onOpenPlan,
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
  final VoidCallback? onOpenPlan;

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
      decoration: BoxDecoration(color: context.colors.surface),
      child: SizedBox(
        height: 38,
        // No width thresholds hide entries. Extremely narrow windows can scroll
        // the small icon strip, retaining keyboard and pointer access.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (showTodo)
                IconButton(
                  key: const ValueKey('todo-open-button'),
                  tooltip: context.l10n.timelineTodoListFallback,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: Icon(
                    todoExpanded ? Icons.checklist : Icons.checklist_outlined,
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
              ?workflowReadout,
              contextReadout,
              throughputReadout,
              startedItemsEntry,
              if (hasEffort || showPlanEntry)
                _StatusOverflow(
                  effort: hasEffort ? route?.effort : null,
                  showPlanEntry: showPlanEntry,
                  onOpenPlan: onOpenPlan,
                ),
            ],
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
    return StatusBarItem(
      icon: Icons.speed_outlined,
      label:
          '${context.l10n.statusLastConfirmedAgentTokenSpeed}: ${context.tokenThroughputLabel(projection?.tokensPerSecond)}',
    );
  }
}

class _WorkflowRuntimeConnector extends ConsumerWidget {
  const _WorkflowRuntimeConnector({required this.run});
  final WorkflowRunView run;

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
      child: StatusBarItem(
        key: ValueKey('workflow-state-${run.currentStateId}'),
        icon: run.terminal ? Icons.check_circle_outline : Icons.route_outlined,
        label:
            '$modeName · $stateTitle${deleted ? ' · ${context.l10n.modeDeletedUsingSnapshot}' : ''}',
      ),
    );
  }
}

class _StatusOverflow extends StatefulWidget {
  const _StatusOverflow({
    required this.effort,
    required this.showPlanEntry,
    this.onOpenPlan,
  });
  final String? effort;
  final bool showPlanEntry;
  final VoidCallback? onOpenPlan;

  @override
  State<_StatusOverflow> createState() => _StatusOverflowState();
}

class _StatusOverflowState extends State<_StatusOverflow> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) => MenuAnchor(
    key: const ValueKey('status-overflow'),
    controller: _controller,
    menuChildren: [
      if (widget.effort case final effort? when effort.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('${context.l10n.statusReasoningEffort}: $effort'),
        ),
      if (widget.showPlanEntry)
        MenuItemButton(
          key: StudioDriverKeys.statusPlanEntry,
          onPressed: () {
            _controller.close();
            widget.onOpenPlan?.call();
          },
          child: Text(context.l10n.statusPlanEntry),
        ),
    ],
    builder: (context, controller, child) => IconButton(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.more_horiz, size: 18),
    ),
  );
}
