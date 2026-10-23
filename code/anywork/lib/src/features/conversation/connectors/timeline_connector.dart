import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_bindings.dart';
import '../state/timeline_view_state.dart';
import '../view_models/plan_view_model.dart';
import '../view_models/timeline_view_model.dart';
import '../views/plan_panel_props.dart';
import '../views/timeline_state_view.dart';
import '../views/timeline_view.dart';
import '../widgets/conversation_markdown.dart';
import 'markdown_connector.dart';
import 'timeline_row_connector.dart';

class TimelineConnector extends ConsumerWidget {
  const TimelineConnector({required this.threadId, super.key});
  final String threadId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = timelineViewModelProvider(threadId);
    final value = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final coordinator = ref.read(timelineCoordinatorProvider);
    final planProvider = planViewModelProvider(threadId);
    final plan = ref.watch(planProvider).value;
    final planVm = ref.read(planProvider.notifier);
    return value.when(loading: () => TimelineStateView(state: TimelineViewState(threadId: threadId),
        onRetry: () => vm.retryConnection().ignore()),
      error: (error, stack) => const Icon(Icons.error_outline),
      data: (state) {
        final display = coordinator.display(threadId);
        if (display == null || display.retired || display.generation != state.generation) {
          return TimelineStateView(state: state, onRetry: () => vm.retryConnection().ignore());
        }
        PlanPanelProps? panel;
        if (plan != null && plan.plan != null) {
          panel = PlanPanelProps(state: plan,
            onRetry: () => planVm.loadDocument().ignore(),
            documentBuilder: (_, markdown) => MarkdownConnector(
              id: 'plan:$threadId:${plan.document?.version}:${plan.document?.contentHash}',
              text: markdown, surface: MarkdownSurface.panel));
        }
        return TimelineView(threadId: threadId, state: state, binding: display.canvas,
          onLoadOlder: vm.loadOlder, onRetryOlder: vm.retryOlder, onReturnLive: vm.returnLive,
          onEnterHistory: vm.enterHistory, onRetryConnection: vm.retryConnection,
          plan: panel,
          onPlanToggle: planVm.toggle,
          messageBuilder: (context, message) => TimelineRowConnector(
            key: ValueKey((display.generation, message.id)), message: message, display: display));
      });
  }
}
