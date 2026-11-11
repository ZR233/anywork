import 'package:anywork_client/acp_sessions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../state/acp_view_state.dart';
import 'acp_content_view_model.dart';
import 'acp_session_view_model.dart';
import 'acp_timeline_view_model.dart';

part 'acp_status_bar_view_model.g.dart';

(AcpStopReasonKind?, String?) _mapStopReason(AcpCompletedRunView? completed) {
  if (completed == null) return (null, null);
  final result = completed.result;
  if (result case AcpSuccessView<AcpPromptResponseView>(:final value)) {
    return (
      switch (value.stopReason) {
        AcpStopReasonView.endTurn => AcpStopReasonKind.endTurn,
        AcpStopReasonView.maxTokens => AcpStopReasonKind.maxTokens,
        AcpStopReasonView.maxTurnRequests => AcpStopReasonKind.maxTurnRequests,
        AcpStopReasonView.refusal => AcpStopReasonKind.refusal,
        AcpStopReasonView.cancelled => AcpStopReasonKind.cancelled,
      },
      null,
    );
  }
  return (null, null);
}

@riverpod
AcpStatusBarViewState acpStatusBarViewModel(Ref ref, String threadId) {
  final asyncState = ref.watch(acpConversationStateProvider(threadId));
  final state = asyncState.value;
  final selected = (
    loading: asyncState.isLoading || state?.openPending == true,
    ready: state?.ready ?? false,
    disconnected: state?.disconnected ?? false,
    ended: state?.observationEnded ?? false,
    isRunning: state?.activeRun != null,
    completed: state?.lastCompleted,
    history: state?.history,
    usage: state == null ? null : extractLatestAcpUsage(state.content),
  );

  final (stopReason, stopReasonRaw) = _mapStopReason(selected.completed);
  final phase = selected.disconnected
      ? AcpSessionStatusPhase.disconnected
      : selected.ended
      ? AcpSessionStatusPhase.ended
      : selected.loading || !selected.ready
      ? AcpSessionStatusPhase.connecting
      : selected.isRunning
      ? AcpSessionStatusPhase.running
      : stopReason != null
      ? AcpSessionStatusPhase.completed
      : AcpSessionStatusPhase.ready;

  return AcpStatusBarViewState(
    phase: phase,
    stopReason: stopReason,
    stopReasonRaw: stopReasonRaw,
    provenance: mapAcpHistoryOrigin(selected.history),
    usage: selected.usage,
  );
}
