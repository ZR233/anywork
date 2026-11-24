import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../presentation/providers/mode_catalog_store.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../status/status_bar_item.dart';
import '../../../status/workflow_graph_panel.dart';
import '../../workspace/conversation_workspace.dart';
import '../state/acp_view_state.dart';
import '../view_models/acp_external_history_view_model.dart';
import '../view_models/acp_plan_card_view_model.dart';
import '../view_models/acp_session_view_model.dart';
import '../view_models/acp_status_bar_view_model.dart';
import '../views/acp_status_bar_view.dart';
import 'acp_external_history_connector.dart';

/// Stable identity and layout only; readouts own their subscriptions.
class AcpStatusBarConnector extends StatelessWidget {
  const AcpStatusBarConnector({
    super.key,
    required this.threadId,
    this.workflowExpanded = false,
    this.onToggleWorkflow,
    this.showPlanEntry = false,
    this.planExpanded = false,
    this.onTogglePlan,
    this.stepsExpanded = false,
    this.onToggleSteps,
    this.hasSidebarPanels = false,
    this.sidebarOpen = false,
    this.onToggleSidebar,
  });

  final String threadId;
  final bool workflowExpanded;
  final VoidCallback? onToggleWorkflow;
  final bool showPlanEntry;
  final bool planExpanded;
  final VoidCallback? onTogglePlan;
  final bool stepsExpanded;
  final VoidCallback? onToggleSteps;
  final bool hasSidebarPanels;
  final bool sidebarOpen;
  final VoidCallback? onToggleSidebar;

  @override
  Widget build(BuildContext context) => AcpStatusBarView(
    status: AcpConnectionStatusConnector(threadId: threadId),
    workflow: _AcpWorkflowStatusConnector(
      threadId: threadId,
      expanded: workflowExpanded,
      onToggle: onToggleWorkflow,
    ),
    plan: showPlanEntry
        ? _AcpPlanStatusPill(expanded: planExpanded, onTap: onTogglePlan)
        : const SizedBox.shrink(),
    steps: _AcpStepsStatusConnector(
      threadId: threadId,
      expanded: stepsExpanded,
      onTap: onToggleSteps,
    ),
    contextUsage: AcpContextUsageConnector(threadId: threadId),
    cost: AcpCostConnector(threadId: threadId),
    throughput: _AcpThroughputConnector(threadId: threadId),
    externalHistory: AcpExternalHistoryButtonConnector(threadId: threadId),
    sidebarToggle: ConversationSidebarToggleButton(
      available: hasSidebarPanels,
      expanded: sidebarOpen,
      onPressed: onToggleSidebar,
    ),
  );
}

class _AcpPlanStatusPill extends StatelessWidget {
  const _AcpPlanStatusPill({required this.expanded, this.onTap});

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

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
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
                        fontWeight: expanded
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AcpStepsStatusConnector extends ConsumerWidget {
  const _AcpStepsStatusConnector({
    required this.threadId,
    required this.expanded,
    this.onTap,
  });

  final String threadId;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(acpPlanCardViewModelProvider(threadId));
    if (plan == null || plan.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final completed = plan.completedCount;
    final total = plan.entries.length;
    final allDone = completed == total;
    final colors = context.colors;
    final fgColor = expanded
        ? colors.primary
        : allDone
        ? StudioTone.success.indicator(context)
        : colors.onSurfaceVariant;
    final bgColor = expanded
        ? colors.primaryContainer.withValues(alpha: 0.45)
        : Colors.transparent;
    final borderColor = expanded
        ? colors.primary.withValues(alpha: 0.55)
        : colors.outlineVariant.withValues(alpha: 0.65);
    final tooltip = context.l10n.acpStepsStatusTooltip(completed, total);

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Semantics(
        button: onTap != null,
        selected: expanded,
        label: tooltip,
        excludeSemantics: true,
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: Material(
            color: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(StudioRadii.sm),
              side: BorderSide(color: borderColor),
            ),
            child: InkWell(
              key: const ValueKey('acp-plan-status-pill'),
              borderRadius: BorderRadius.circular(StudioRadii.sm),
              onTap: onTap,
              child: SizedBox(
                height: 26,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        allDone
                            ? Icons.check_circle_outline
                            : Icons.checklist_outlined,
                        size: 14,
                        color: fgColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$completed/$total',
                        style: context.text.labelSmall?.copyWith(
                          color: fgColor,
                          fontWeight: expanded
                              ? FontWeight.w600
                              : FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AcpWorkflowStatusConnector extends ConsumerWidget {
  const _AcpWorkflowStatusConnector({
    required this.threadId,
    this.expanded = false,
    this.onToggle,
  });

  final String threadId;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflowState = ref.watch(
      acpConversationStateProvider(threadId)
          .select((value) => value.value?.workflowState),
    );
    if (workflowState == null) return const SizedBox.shrink();
    final run = workflowState.run;
    final catalog = ref.watch(modeCatalogStoreProvider).value;
    final modeId = run?.modeId ?? workflowState.modeId ?? '';
    final deleted = catalog == null
        ? (run?.modeDeleted ?? false)
        : !catalog.modes.any((mode) => mode.id == modeId);
    final modeName = (run?.modeDisplayName.isNotEmpty == true)
        ? run!.modeDisplayName
        : (workflowState.modeDisplayName?.trim().isNotEmpty == true)
        ? workflowState.modeDisplayName!.trim()
        : context.workflowModeLabel(modeId);
    final stateTitle = run != null
        ? (run.currentStateTitle.isEmpty
              ? context.workflowStateLabel(run.currentStateId)
              : run.currentStateTitle)
        : modeName;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: WorkflowStatusPill(
        stateTitle: stateTitle,
        modeName: modeName,
        deleted: deleted,
        terminal: run?.terminal ?? false,
        expanded: expanded,
        onTap: onToggle,
      ),
    );
  }
}

class _AcpThroughputConnector extends ConsumerWidget {
  const _AcpThroughputConnector({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TokenThroughputReadout(
    estimated: true,
    tokensPerSecond: ref.watch(acpThroughputViewModelProvider(threadId)),
    triggerKey: ValueKey(AcpViewKeyValues.throughput(threadId)),
    detailKey: ValueKey(AcpViewKeyValues.throughputDetail(threadId)),
    detailMaxWidth: 328,
    detailBuilder: (_) => _AcpThroughputDetailConnector(threadId: threadId),
  );
}

class _AcpThroughputDetailConnector extends ConsumerWidget {
  const _AcpThroughputDetailConnector({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AcpThroughputDetailView(
    state: ref.watch(acpThroughputDetailViewModelProvider(threadId)),
  );
}

class AcpConnectionStatusConnector extends ConsumerWidget {
  const AcpConnectionStatusConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AcpConnectionStatusView(
    state: ref.watch(acpStatusBarViewModelProvider(threadId)),
    threadId: threadId,
    detailBuilder: (_) => _AcpSessionDetailConnector(threadId: threadId),
  );
}

class _AcpSessionDetailConnector extends ConsumerWidget {
  const _AcpSessionDetailConnector({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AcpSessionDetailView(
    state: ref.watch(acpSessionDetailViewModelProvider(threadId)),
  );
}

class AcpContextUsageConnector extends ConsumerWidget {
  const AcpContextUsageConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AcpContextUsageView(
    state: ref.watch(acpContextUsageViewModelProvider(threadId)),
    threadId: threadId,
    detailBuilder: (_) => _AcpContextDetailConnector(threadId: threadId),
  );
}

class _AcpContextDetailConnector extends ConsumerWidget {
  const _AcpContextDetailConnector({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AcpContextDetailView(
    state: ref.watch(acpContextDetailViewModelProvider(threadId)),
  );
}

class AcpCostConnector extends ConsumerWidget {
  const AcpCostConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AcpCostReadoutView(
    state: ref.watch(acpCostViewModelProvider(threadId)),
    threadId: threadId,
    detailBuilder: (_) => _AcpCostDetailConnector(threadId: threadId),
  );
}

class _AcpCostDetailConnector extends ConsumerWidget {
  const _AcpCostDetailConnector({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(acpCostDetailViewModelProvider(threadId));
    if (detail == null) return const SizedBox.shrink();
    return AcpCostDetailView(state: detail);
  }
}

class AcpExternalHistoryButtonConnector extends ConsumerWidget {
  const AcpExternalHistoryButtonConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      acpExternalHistoryButtonViewModelProvider(threadId),
    );
    return AcpExternalHistoryButtonView(
      threadId: threadId,
      state: state,
      onOpen: state.status == AcpExternalHistoryAvailability.available
          ? () => unawaited(showAcpExternalHistoryDialog(context, threadId))
          : null,
    );
  }
}
