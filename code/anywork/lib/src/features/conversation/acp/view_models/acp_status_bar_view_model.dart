import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/models.dart' show tokenThroughput;
import 'package:riverpod/riverpod.dart' show Provider, ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../state/acp_view_state.dart';
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
  final selected = ref.watch(
    acpConversationStateProvider(threadId).select((asyncState) {
      final state = asyncState.value;
      return (
        loading: asyncState.isLoading || state?.openPending == true,
        ready: state?.ready ?? false,
        disconnected: state?.disconnected ?? false,
        ended: state?.observationEnded ?? false,
        isRunning: state?.activeRun != null,
        stopReason: _mapStopReason(state?.lastCompleted),
        history: state?.history,
      );
    }),
  );

  final (stopReason, stopReasonRaw) = selected.stopReason;
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
  );
}

@riverpod
AcpContextUsageViewState? acpContextUsageViewModel(Ref ref, String threadId) {
  return ref.watch(
    acpConversationStateProvider(threadId).select((asyncState) {
      final usage = asyncState.value?.latestUsage;
      return usage == null || usage.size <= BigInt.zero
          ? null
          : (used: usage.used, size: usage.size);
    }),
  );
}

@riverpod
AcpCostViewState? acpCostViewModel(Ref ref, String threadId) {
  return ref.watch(
    acpConversationStateProvider(threadId)
        .select((asyncState) => asyncState.value?.latestUsage?.cost),
  );
}

/// Readout-only projection. Equal rates do not invalidate the speed widget.
final acpThroughputViewModelProvider = Provider.autoDispose
    .family<double?, String>((ref, threadId) {
      return ref.watch(
        acpConversationStateProvider(threadId).select((asyncState) {
          final sample = asyncState.value?.textPerformance;
          return tokenThroughput(
            sample?.estimatedOutputTokens,
            sample?.responseMillis,
          );
        }),
      );
    });
