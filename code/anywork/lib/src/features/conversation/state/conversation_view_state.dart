import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'composer_primary_action.dart';
import 'editor_keys.dart';

part 'conversation_view_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class ConversationViewState with _$ConversationViewState {
  const ConversationViewState._();
  const factory ConversationViewState({
    required String threadId,
    ThreadMetadataState? metadata,
    ThreadExecutionState? execution,
    ThreadConfigurationState? configuration,
    ComposerBlocker? workspaceBlocker,
    @Default(false) bool acceptsUserInput,
    InteractionIndexReadState? interactions,
    @Default([]) List<InteractionEditorKey> visibleEditors,
    @Default({}) Set<InteractionEditorKey> currentEditors,
    @Default(false) bool indexLoading,
    StudioFailure? indexError,
    @Default(false) bool stopSourceCurrent,
    ConversationStopState? stop,
    ConversationContinuationState? continuation,
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
      execution?.value?.execution != null;
  bool get retiredPlanner =>
      thread?.parentThreadId != null && thread?.role == 'planner';
  bool get runtimeDriven => thread?.parentThreadId != null;
  int? get pendingInteractionCount => execution?.value?.interactions.pending;
  bool get canCompose =>
      metadataCurrent &&
      executionCurrent &&
      acceptsUserInput &&
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
    String? executionId,
    OperationState? operation,
    CommandResult<Unit>? result,
    StudioFailure? localError,
    StudioFailure? observationError,
  }) = _ConversationStopState;

  bool get unknown =>
      !accepted &&
      (result is UnknownOutcomeCommandResult<Unit> ||
          operation?.failurePhase == OperationFailurePhase.unknownOutcome);
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

/// Continuation presentation evidence; the original Session/ticket stays in VM.
@Freezed(toStringOverride: false)
abstract class ConversationContinuationState with _$ConversationContinuationState {
  const ConversationContinuationState._();
  const factory ConversationContinuationState({
    required int intent,
    required ThreadFacetStamp origin,
    required String continuationId,
    required int modelRouteRevision,
    OperationState? operation,
    CommandResult<ContinueThreadReply>? result,
    ContinuationOperationView? recovered,
    StudioFailure? error,
    @Default(false) bool reading,
  }) = _ConversationContinuationState;

  bool get unknown =>
      !accepted &&
      (result is UnknownOutcomeCommandResult<ContinueThreadReply> ||
          operation?.failurePhase == OperationFailurePhase.unknownOutcome);

  /// Historical acceptance remains true after consumption or discard. It is
  /// not evidence that this control input is still waiting to be consumed.
  bool get accepted =>
      recovered != null ||
      operation?.receipt != null ||
      operation?.acknowledged == true ||
      result is CommittedCommandResult<ContinueThreadReply> ||
      result is AcknowledgedCommandResult<ContinueThreadReply> ||
      result is SyncFailedCommandResult<ContinueThreadReply> ||
      result is AcknowledgedSyncFailedCommandResult<ContinueThreadReply>;

  /// Identity observation and durability can both precede consumption. Only
  /// the typed query state (or actual effect evidence before that query) ends
  /// this wait; an unconfirmed Unknown never fabricates accepted progress.
  bool get inProgress => switch (recovered?.state) {
    PendingContinuation() => true,
    ConsumedContinuation() || DiscardedContinuation() => false,
    null => accepted && !_hasEffectEvidence,
  };

  bool get _hasEffectEvidence =>
      operation?.effective == true ||
      operation?.receipt?.effective == true ||
      switch (result) {
        CommittedCommandResult<ContinueThreadReply>(:final receipt) ||
        SyncFailedCommandResult<ContinueThreadReply>(:final receipt) =>
          receipt.effective,
        AcknowledgedCommandResult<ContinueThreadReply>(:final value) =>
          value.receipt.effective,
        AcknowledgedSyncFailedCommandResult<ContinueThreadReply>(:final value) =>
          value?.receipt.effective == true,
        RejectedCommandResult<ContinueThreadReply>() ||
        UnknownOutcomeCommandResult<ContinueThreadReply>() || null => false,
      };

  bool get pending =>
      !accepted && !unknown && error == null && result == null &&
      operation?.failurePhase != OperationFailurePhase.rejected;
}
