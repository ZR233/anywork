import 'package:anywork_client/acp_sessions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../state/acp_view_state.dart';
import 'acp_session_view_model.dart';

part 'acp_plan_card_view_model.g.dart';

AcpPlanPriorityKind _mapPriority(AcpPlanPriorityView priority) =>
    switch (priority) {
      AcpPlanPriorityView.high => AcpPlanPriorityKind.high,
      AcpPlanPriorityView.medium => AcpPlanPriorityKind.medium,
      AcpPlanPriorityView.low => AcpPlanPriorityKind.low,
    };

AcpPlanStatusKind _mapStatus(AcpPlanStatusView status) => switch (status) {
  AcpPlanStatusView.pending => AcpPlanStatusKind.pending,
  AcpPlanStatusView.inProgress => AcpPlanStatusKind.inProgress,
  AcpPlanStatusView.completed => AcpPlanStatusKind.completed,
};

/// Selects ONLY `state.value?.plan` so streaming message chunks never notify
/// plan listeners while the canonical `AcpPlanView` reference is unchanged.
@riverpod
AcpPlanCardViewState? acpPlanCardViewModel(Ref ref, String threadId) {
  final plan = ref.watch(acpConversationStateProvider(threadId)).value?.plan;
  if (plan == null || plan.entries.isEmpty) return null;
  var completed = 0;
  final entries = <AcpPlanEntryPresentation>[];
  for (final entry in plan.entries) {
    final status = _mapStatus(entry.status);
    if (status == AcpPlanStatusKind.completed) {
      completed++;
    }
    entries.add(
      AcpPlanEntryPresentation(
        content: entry.content,
        priority: _mapPriority(entry.priority),
        status: status,
      ),
    );
  }
  return AcpPlanCardViewState(entries: entries, completedCount: completed);
}
