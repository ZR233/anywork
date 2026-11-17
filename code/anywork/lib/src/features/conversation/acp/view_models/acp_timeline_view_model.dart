import 'package:anywork_client/acp_sessions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../state/acp_timeline_row.dart';
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
    itemCount: ref.watch(acpTimelineRowsViewModelProvider(threadId)).length,
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
List<AcpTimelineRow> acpTimelineRowsViewModel(Ref ref, String threadId) {
  final state = ref.watch(acpConversationStateProvider(threadId)).value;
  return mapAcpTimelineRows(
    threadId: threadId,
    content: state?.content ?? const [],
    running: state?.activeRun != null,
  );
}

@riverpod
AcpTimelineRow? acpTimelineItemViewModel(Ref ref, String threadId, int index) {
  final rows = ref.watch(acpTimelineRowsViewModelProvider(threadId));
  return index >= 0 && index < rows.length ? rows[index] : null;
}

List<AcpTimelineRow> mapAcpTimelineRows({
  required String threadId,
  required List<AcpConversationContentItem> content,
  required bool running,
}) {
  var lastCommands = -1;
  var lastUsage = -1;
  for (var index = content.length - 1; index >= 0; index--) {
    if (content[index] case AcpConversationUpdateItem(:final update)) {
      if (lastCommands < 0 && update is AcpAvailableCommandsUpdateView) {
        lastCommands = index;
      } else if (lastUsage < 0 && update is AcpUsageUpdateView) {
        lastUsage = index;
      }
    }
  }

  final rows = <AcpTimelineRow>[];
  final process = <AcpTimelineItemPresentation>[];
  var boundaryId = '$threadId:start';

  void flush() {
    if (process.isEmpty) return;
    rows.add(AcpTimelineProcessRow(id: '$boundaryId:process', items: process));
    process.clear();
  }

  for (var index = 0; index < content.length; index++) {
    final source = content[index];
    if (source case AcpConversationUpdateItem(:final update)) {
      if ((update is AcpAvailableCommandsUpdateView && index != lastCommands) ||
          (update is AcpUsageUpdateView && index != lastUsage)) {
        continue;
      }
    }
    final item = mapAcpTimelineItem(
      threadId: threadId,
      index: index,
      item: source,
      isLastAndRunning: running && index == content.length - 1,
    );
    if (item == null) continue;
    if (item case AcpTimelineSessionUpdateItem(
      update: AcpSupersededUpdatePresentation(),
    )) {
      continue;
    }
    final blocks = switch (item) {
      AcpTimelineUserMessage(:final blocks) => blocks,
      AcpTimelineAssistantMessage(:final blocks) => blocks,
      AcpTimelineThoughtItem(:final blocks) => blocks,
      _ => null,
    };
    if (blocks != null &&
        !blocks.any(
          (block) => switch (block) {
            AcpTextBlockPresentation(:final text) => text.trim().isNotEmpty,
            _ => true,
          },
        )) {
      continue;
    }
    if (item is AcpTimelineUserMessage || item is AcpTimelineAssistantMessage) {
      flush();
      rows.add(AcpTimelineMessageRow(item));
      boundaryId = item.id;
    } else {
      process.add(item);
    }
  }
  flush();
  return List.unmodifiable(rows);
}
