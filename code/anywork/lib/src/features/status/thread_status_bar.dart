import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../presentation/providers/mode_catalog_store.dart';
import '../conversation/workspace/conversation_workspace.dart';
import '../conversation/timeline/view_models/thread_runtime_fields.dart';
import '../../shared/studio_driver_keys.dart';

import 'context_usage_readout.dart';
import 'started_items_panel.dart';
import 'status_bar_item.dart';
import 'status_view.dart';
import 'views/workflow_graph_panel.dart';

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
      workflowReadout: _WorkflowRuntimeConnector(
        threadId: threadId,
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
                      if (row.isChildRow) ...[
                        StatusBarItem(
                          icon: Icons.account_tree_outlined,
                          label:
                              '$role · ${row.title} · ${context.threadStatusLabel(backend.status)}',
                        ),
                        StatusBarItem(
                          icon: Icons.smart_toy_outlined,
                          label:
                              route?.unavailableReason ??
                              route?.modelId ??
                              context.l10n.settingsNotAvailable,
                        ),
                      ],
                      ?workflowReadout,
                      if (showTodo) ...[
                        const SizedBox(width: 4),
                        StatusBarButton(
                          key: const ValueKey('todo-open-button'),
                          icon: Icons.checklist_rounded,
                          iconOnly: true,
                          label: context.l10n.rightSidebarTabTodo,
                          tooltip: context.l10n.timelineTodoListFallback,
                          selected: todoExpanded,
                          onPressed: onToggleTodo,
                        ),
                      ],
                      if (showPlanEntry) ...[
                        const SizedBox(width: 4),
                        StatusBarButton(
                          key: StudioDriverKeys.statusPlanEntry,
                          icon: Icons.description_outlined,
                          iconOnly: true,
                          label: context.l10n.rightSidebarTabPlan,
                          tooltip: context.l10n.statusPlanEntry,
                          selected: planExpanded,
                          onPressed: onOpenPlan,
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
                      const SizedBox(width: 8),
                      startedItemsEntry,
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

class _WorkflowRuntimeConnector extends ConsumerWidget {
  const _WorkflowRuntimeConnector({
    required this.threadId,
    this.expanded = false,
    this.onToggle,
  });

  final String threadId;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflow = ref.watch(threadWorkflowRunProvider(threadId));
    if (workflow.isLoading) return const SizedBox.shrink();
    if (workflow.hasError) {
      return StatusBarButton(
        key: const ValueKey('workflow-status-pill'),
        icon: Icons.error_outline,
        label: context.l10n.rightSidebarTabWorkflow,
        tooltip: context.l10n.workflowGraphPanelLoadFailed,
        selected: expanded,
        onPressed: onToggle,
      );
    }
    final run = workflow.asData?.value?.run;
    if (run == null) return const SizedBox.shrink();
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
      child: WorkflowStatusPill(
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
