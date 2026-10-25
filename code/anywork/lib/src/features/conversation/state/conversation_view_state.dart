import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'editor_keys.dart';

part 'conversation_view_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class ConversationViewState with _$ConversationViewState {
  const ConversationViewState._();
  const factory ConversationViewState({
    required String threadId,
    ThreadMetadataState? metadata,
    ThreadExecutionState? execution,
    InteractionIndexReadState? interactions,
    @Default([]) List<InteractionEditorKey> visibleEditors,
    @Default({}) Set<InteractionEditorKey> currentEditors,
    @Default(false) bool indexLoading,
    StudioFailure? indexError,
    @Default(false) bool stopSourceCurrent,
    ConversationStopState? stop,
  }) = _ConversationViewState;

  WorkspaceThreadRecord? get thread => switch (metadata?.value) {
    ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>(:final current) =>
      current.value,
    _ => null,
  };
  bool get metadataCurrent =>
      metadata?.projection.sync.phase == ResourceSyncPhase.ready &&
      thread != null;
  bool get executionCurrent =>
      execution?.sync.phase == FacetSyncPhase.ready && execution?.value != null;
  bool get running =>
      execution?.value?.activeTurn?.state is QueuedTurnBrief ||
      execution?.value?.activeTurn?.state is RunningTurnBrief;
  bool get retiredPlanner =>
      thread?.parentThreadId != null && thread?.role == 'planner';
  bool get runtimeDriven => thread?.parentThreadId != null;
  int? get pendingInteractionCount => execution?.value?.interactions.pending;
  bool get canCompose =>
      metadataCurrent &&
      executionCurrent &&
      !runtimeDriven &&
      pendingInteractionCount == 0 &&
      !const {
        ThreadStatus.closing,
        ThreadStatus.closed,
        ThreadStatus.faulted,
      }.contains(execution?.value?.status);
}

/// Presentation evidence only. The ticket, source and page lifetime stay in the VM.
@Freezed(toStringOverride: false)
abstract class ConversationStopState with _$ConversationStopState {
  const ConversationStopState._();
  const factory ConversationStopState({
    required int intent,
    ThreadFacetStamp? origin,
    TurnReadRef? target,
    OperationState? operation,
    CommandResult<Unit>? result,
    StudioFailure? localError,
    StudioFailure? observationError,
  }) = _ConversationStopState;

  bool get unknown =>
      result is UnknownOutcomeCommandResult<Unit> ||
      operation?.failurePhase == OperationFailurePhase.unknownOutcome;
  bool get accepted =>
      operation?.receipt != null ||
      operation?.acknowledged == true ||
      result is CommittedCommandResult<Unit> ||
      result is AcknowledgedCommandResult<Unit> ||
      result is SyncFailedCommandResult<Unit> ||
      result is AcknowledgedSyncFailedCommandResult<Unit>;
  bool get pending {
    if (unknown || localError != null) return false;
    if (accepted) return operation?.observed != true;
    final evidence = operation;
    if (evidence == null) return result == null;
    if (evidence.failurePhase == OperationFailurePhase.rejected) return false;
    return result == null;
  }

  StudioFailure? get failure =>
      localError ??
      operation?.error ??
      switch (result) {
        RejectedCommandResult<Unit>(:final error) ||
        UnknownOutcomeCommandResult<Unit>(:final error) ||
        SyncFailedCommandResult<Unit>(:final error) ||
        AcknowledgedSyncFailedCommandResult<Unit>(:final error) => error,
        _ => null,
      };
}
