import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'editor_keys.dart';

part 'conversation_view_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class ConversationViewState with _$ConversationViewState {
  const ConversationViewState._();
  const factory ConversationViewState({required String threadId,
    ThreadMetadataState? metadata, ThreadExecutionState? execution,
    InteractionIndexReadState? interactions,
    @Default([]) List<InteractionEditorKey> visibleEditors,
    @Default({}) Set<InteractionEditorKey> currentEditors,
    @Default(false) bool indexLoading, StudioFailure? indexError,
  }) = _ConversationViewState;

  WorkspaceThreadRecord? get thread => switch (metadata?.value) {
    ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>(:final current) => current.value,
    _ => null,
  };
  bool get metadataCurrent => metadata?.projection.sync.phase == ResourceSyncPhase.ready && thread != null;
  bool get executionCurrent => execution?.sync.phase == FacetSyncPhase.ready && execution?.value != null;
  bool get running => execution?.value?.activeTurn?.state is QueuedTurnBrief ||
    execution?.value?.activeTurn?.state is RunningTurnBrief;
  bool get retiredPlanner => thread?.parentThreadId != null && thread?.role == 'planner';
  bool get runtimeDriven => thread?.parentThreadId != null;
  int? get pendingInteractionCount => execution?.value?.interactions.pending;
  bool get canCompose => metadataCurrent && executionCurrent && !runtimeDriven && pendingInteractionCount == 0 &&
    !const {ThreadStatus.closing, ThreadStatus.closed, ThreadStatus.faulted}.contains(execution?.value?.status);
}
