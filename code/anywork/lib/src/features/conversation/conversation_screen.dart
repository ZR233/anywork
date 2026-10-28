import 'dart:async';

import 'package:anywork_client/conversation.dart' show PlanPhase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/studio_l10n.dart';
import '../interaction/interaction.dart';
import 'connectors/agent_read_only_connector.dart';
import 'connectors/interaction_editor_close_connector.dart';
import 'connectors/plan_connector.dart';
import 'connectors/thread_context_connector.dart';
import 'connectors/thread_metrics_connector.dart';
import 'connectors/thread_status_connector.dart';
import 'connectors/timeline_connector.dart';
import 'connectors/todo_connector.dart';
import 'state/plan_view_state.dart';
import 'view_models/conversation_view_model.dart';
import 'view_models/plan_view_model.dart';
import 'view_models/todo_view_model.dart';
import 'views/conversation_view.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({required this.threadId, super.key});
  final String threadId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  ModalRoute<dynamic>? _route;
  ConversationStopPage? _stopPage;
  ConversationViewModel? _stopVM;

  void _retireStopPage() {
    final page = _stopPage;
    _stopPage = null;
    if (page != null) {
      page.retire();
      _stopVM?.deferStopPage(page);
    }
  }

  void _refreshStopPage() {
    final route = _route;
    if (route == null || !route.isCurrent) {
      _retireStopPage();
      return;
    }
    if (_stopPage != null) return;
    final threadId = widget.threadId;
    late final ConversationStopPage page;
    page = ConversationStopPage(
      isCurrent: () =>
          mounted &&
          identical(_stopPage, page) &&
          identical(_route, route) &&
          route.isCurrent &&
          widget.threadId == threadId,
    );
    _stopPage = page;
    _stopVM?.deferStopPage(page);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) _retireStopPage();
    _route = route;
    _refreshStopPage();
  }

  @override
  void didUpdateWidget(covariant ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId == widget.threadId) return;
    _retireStopPage();
    _stopVM = null;
    _refreshStopPage();
  }

  @override
  void dispose() {
    _retireStopPage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threadId = widget.threadId;
    final provider = conversationViewModelProvider(threadId);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    if (!identical(_stopVM, vm)) {
      _stopVM = vm;
      if (_stopPage case final page?) vm.deferStopPage(page);
    }
    final todoProvider = todoViewModelProvider(threadId);
    final todo = ref.watch(todoProvider).value;
    final todoVm = ref.read(todoProvider.notifier);
    final planProvider = planViewModelProvider(threadId);
    final plan = ref.watch(planProvider).value;
    final planVm = ref.read(planProvider.notifier);
    // The Plan panel takes precedence over the Todo side panel; closing it
    // leaves Todo with its own untouched UI state.
    final planOpen = plan?.open == true && plan?.plan != null;
    // The approved projection with a current document is the only source of the
    // post-approval reading entrance; it lives in the chat status bar's
    // more-menu, never as a second timeline row (design/13-plan.md §13.5).
    final approvedPlan = plan?.plan;
    final showPlanEntry =
        approvedPlan?.state == PlanPhase.approved &&
        approvedPlan?.document != null;
    final todoProviderValue = todo?.todo;
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => const Center(child: Icon(Icons.error_outline)),
      data: (state) {
        final page = _stopPage;
        final stop = page == null || state.retiredPlanner || state.runtimeDriven
            ? null
            : vm.captureStop(page);
        final VoidCallback? onStop = stop == null
            ? null
            : () => unawaited(stop());
        // A temporarily unknown source forbids a new action, not the display
        // of already accepted/unknown evidence from this original operation.
        final stopState = page == null ? null : vm.stopStateFor(page);
        final hasInteractions =
            state.visibleEditors.isNotEmpty ||
            (state.pendingInteractionCount ?? 0) > 0 ||
            state.indexLoading ||
            state.interactions?.loading == true ||
            state.indexError != null ||
            state.interactions?.error != null ||
            state.interactions?.current?.nextOffset != null;
        return ConversationView(
          timeline: TimelineConnector(threadId: threadId),
          status: ThreadStatusConnector(
            threadId: threadId,
            contextUsage: ThreadContextConnector(threadId: threadId),
            throughput: ThreadMetricsConnector(threadId: threadId),
            showPlanEntry: showPlanEntry,
            onOpenPlan: planVm.open,
          ),
          onToggleTodo: todoVm.toggle,
          todoExpanded: todo?.expanded == true,
          todoBuilder: todoProviderValue == null
              ? null
              : ({required bool inDrawer, required VoidCallback? onClose}) =>
                    TodoConnector(
                      threadId: threadId,
                      inDrawer: inDrawer,
                      onClose: onClose,
                    ),
          planOpen: planOpen,
          planFullWidth: plan?.fullWidth ?? false,
          planPanelWidth: plan?.panelWidth ?? planDefaultPanelWidth,
          onPlanWidthChanged: planVm.setPanelWidth,
          planPanelBuilder: (sideBySideFeasible) => PlanPanelConnector(
            threadId: threadId,
            sideBySideFeasible: sideBySideFeasible,
          ),
          composerBuilder: (compact) => state.runtimeDriven
              ? AgentReadOnlyConnector(threadId: threadId)
              : ConversationInputConnector(
                  threadId: threadId,
                  onStop: onStop,
                  stopState: stopState,
                  compact: compact,
                ),
          interactions: state.runtimeDriven || !hasInteractions
              ? null
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .4,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if ((state.pendingInteractionCount ?? 0) > 0 &&
                            state.visibleEditors.isEmpty)
                          Text(context.l10n.timelineUserInputAwaiting),
                        for (final key in state.visibleEditors)
                          InteractionEditorCloseConnector(
                            key: ValueKey(key),
                            target: key,
                            enabled:
                                state.currentEditors.contains(key) &&
                                state.executionCurrent,
                            onDirty: (dirty) => vm.setEditorDirty(key, dirty),
                            onClosed: () => vm.closeEditor(key),
                          ),
                        if (state.indexLoading ||
                            state.interactions?.loading == true)
                          const LinearProgressIndicator(),
                        if (state.indexError != null)
                          Text(state.indexError!.message),
                        if (state.interactions?.error != null &&
                            state.interactions?.error != state.indexError)
                          Text(state.interactions!.error!.message),
                        if (state.interactions?.current?.nextOffset != null ||
                            state.indexError != null ||
                            state.interactions?.error != null ||
                            ((state.pendingInteractionCount ?? 0) > 0 &&
                                state.currentEditors.isEmpty))
                          TextButton(
                            onPressed:
                                state.indexLoading ||
                                    state.interactions?.loading == true
                                ? null
                                : () => vm.loadInteractions().ignore(),
                            child: Text(context.l10n.timelineItemBodyLoad),
                          ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
