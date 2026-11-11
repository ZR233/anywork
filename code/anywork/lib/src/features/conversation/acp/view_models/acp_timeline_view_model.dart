import 'package:anywork_client/acp_sessions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../state/acp_view_state.dart';
import 'acp_content_view_model.dart';
import 'acp_session_view_model.dart';

part 'acp_timeline_view_model.g.dart';

List<AcpCapabilityKind> mapAcpCapabilities(AcpAgentCapabilitiesView? caps) {
  if (caps == null) return const [];
  return [
    if (caps.image) AcpCapabilityKind.image,
    if (caps.audio) AcpCapabilityKind.audio,
    if (caps.embeddedContext) AcpCapabilityKind.embeddedContext,
    if (caps.loadSession) AcpCapabilityKind.loadSession,
    if (caps.resumeSession) AcpCapabilityKind.resumeSession,
    if (caps.listSessions) AcpCapabilityKind.listSessions,
  ];
}

AcpGapKind? mapAcpGapKind(AcpObservationGapView? gap) => switch (gap) {
  null => null,
  AcpObservationGapView.windowExceeded => AcpGapKind.windowExceeded,
  AcpObservationGapView.disconnected => AcpGapKind.disconnected,
  AcpObservationGapView.encoding => AcpGapKind.encoding,
};

AcpHistoryOriginKind? mapAcpHistoryOrigin(AcpConversationHistory? history) =>
    switch (history) {
      null => null,
      AcpConversationHistory.newSession => AcpHistoryOriginKind.newSession,
      AcpConversationHistory.loadReplay => AcpHistoryOriginKind.loadReplay,
      AcpConversationHistory.resumedWithoutHistory =>
        AcpHistoryOriginKind.resumedWithoutHistory,
      AcpConversationHistory.residentWithoutObservation =>
        AcpHistoryOriginKind.residentWithoutObservation,
      AcpConversationHistory.incomplete => AcpHistoryOriginKind.incomplete,
    };

@riverpod
AcpTimelineHeaderViewState acpTimelineHeaderViewModel(
  Ref ref,
  String threadId,
) {
  final asyncState = ref.watch(acpConversationStateProvider(threadId));
  final state = asyncState.value;
  final rawError = asyncState.error ?? state?.error;
  return AcpTimelineHeaderViewState(
    loading: asyncState.isLoading || state?.openPending == true,
    ready: state?.ready ?? false,
    disconnected: state?.disconnected ?? false,
    observationEnded: state?.observationEnded ?? false,
    itemCount: state?.content.length ?? 0,
    hasConversationalContent: state == null
        ? false
        : hasConversationalAcpContent(state.content),
    hasPlan: state?.plan != null && state!.plan!.entries.isNotEmpty,
    capabilities: mapAcpCapabilities(state?.capabilities),
    errorMessage: rawError == null ? null : formatAcpError(rawError),
    gapKind: mapAcpGapKind(state?.observationGap),
    historyKind: mapAcpHistoryOrigin(state?.history),
  );
}

@riverpod
AcpTimelineItemPresentation? acpTimelineItemViewModel(
  Ref ref,
  String threadId,
  int index,
) {
  final asyncState = ref.watch(acpConversationStateProvider(threadId));
  final state = asyncState.value;
  final content = state?.content;
  final item = content != null && index >= 0 && index < content.length
      ? content[index]
      : null;
  if (item == null) return null;
  final isLastAndRunning =
      state?.activeRun != null && index == content!.length - 1;
  var supersededUpdate = false;
  if (item case AcpConversationUpdateItem(:final update)) {
    if (update is AcpAvailableCommandsUpdateView) {
      supersededUpdate = content!
          .skip(index + 1)
          .any(
            (later) =>
                later is AcpConversationUpdateItem &&
                later.update is AcpAvailableCommandsUpdateView,
          );
    } else if (update is AcpUsageUpdateView) {
      supersededUpdate = content!
          .skip(index + 1)
          .any(
            (later) =>
                later is AcpConversationUpdateItem &&
                later.update is AcpUsageUpdateView,
          );
    }
  }
  return mapAcpTimelineItem(
    threadId: threadId,
    index: index,
    item: item,
    isLastAndRunning: isLastAndRunning,
    supersededUpdate: supersededUpdate,
  );
}
