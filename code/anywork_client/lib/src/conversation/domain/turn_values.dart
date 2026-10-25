import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'thread_identity.dart';

part 'turn_values.freezed.dart';

enum TurnPhase {
  preparing,
  thinking,
  responding,
  planning,
  runningTool,
  persisting,
}

enum TurnCompletion { normal, interactionRequested }

enum TurnCancellationKind {
  unspecified,
  userRequested,
  runtimeShutdown,
  agentClosed,
  interrupted,
  recovery,
  coalesced,
}

enum TurnFailureCategory {
  provider,
  providerCapacity,
  tool,
  validation,
  protocol,
  internal,
}

enum ProviderFailureKind {
  authentication,
  authorization,
  capacity,
  configuration,
  transport,
  protocol,
  unknown,
}

enum TurnRolloverKind { notAttempted, succeeded, failed }

enum TurnStatus { queued, running, completed, cancelled, failed, budgetLimited }

@freezed
sealed class RetryDisposition with _$RetryDisposition {
  const factory RetryDisposition.retryable({required int? retryAfterMs}) =
      RetryableDisposition;
  const factory RetryDisposition.permanent() = PermanentRetryDisposition;
}

@freezed
abstract class TurnBrief with _$TurnBrief {
  const factory TurnBrief({
    required TurnReadRef reference,
    required int revision,
    required int updatedAt,
    required TurnBriefState state,
  }) = _TurnBrief;
}

@freezed
sealed class TurnBriefState with _$TurnBriefState {
  const factory TurnBriefState.queued({required int queuedAt}) =
      QueuedTurnBrief;
  const factory TurnBriefState.running({
    required int startedAt,
    required TurnPhase phase,
  }) = RunningTurnBrief;
  const factory TurnBriefState.completed({
    required int? startedAt,
    required int completedAt,
    required TurnCompletion completion,
  }) = CompletedTurnBrief;
  const factory TurnBriefState.cancelled({
    required int? startedAt,
    required int requestedAt,
    required int completedAt,
    required TurnCancellationKind cause,
  }) = CancelledTurnBrief;
  const factory TurnBriefState.failed({
    required int? startedAt,
    required int completedAt,
    required TurnFailureCategory category,
    required ProviderFailureKind? providerKind,
    required int? httpStatus,
    required RetryDisposition retry,
  }) = FailedTurnBrief;
  const factory TurnBriefState.budgetLimited({
    required int? startedAt,
    required int completedAt,
    required BudgetLimitSnapshot limit,
    required TurnRolloverKind rollover,
  }) = BudgetLimitedTurnBrief;
}

@Freezed(toStringOverride: false)
sealed class TurnCancellationCause with _$TurnCancellationCause {
  const factory TurnCancellationCause.unspecified() =
      UnspecifiedTurnCancellation;
  const factory TurnCancellationCause.userRequested() =
      UserRequestedTurnCancellation;
  const factory TurnCancellationCause.runtimeShutdown() =
      RuntimeShutdownTurnCancellation;
  const factory TurnCancellationCause.agentClosed() =
      AgentClosedTurnCancellation;
  const factory TurnCancellationCause.interrupted() =
      InterruptedTurnCancellation;
  const factory TurnCancellationCause.recovery() = RecoveryTurnCancellation;
  const factory TurnCancellationCause.coalesced({
    required String targetTurnId,
  }) = CoalescedTurnCancellation;
}

@Freezed(toStringOverride: false)
sealed class TurnRolloverOutcome with _$TurnRolloverOutcome {
  const factory TurnRolloverOutcome.notAttempted() = TurnRolloverNotAttempted;
  const factory TurnRolloverOutcome.succeeded() = TurnRolloverSucceeded;
  const factory TurnRolloverOutcome.failed({required String error}) =
      TurnRolloverFailed;
}

@Freezed(toStringOverride: false)
abstract class TurnFailure with _$TurnFailure {
  const factory TurnFailure({
    required TurnFailureCategory category,
    required ProviderFailureKind? providerKind,
    required String? code,
    required int? httpStatus,
    required String message,
    required RetryDisposition retry,
  }) = _TurnFailure;
}

/// Full materialized state, unlike the bounded execution brief.
@Freezed(toStringOverride: false)
sealed class TurnState with _$TurnState {
  const TurnState._();

  const factory TurnState.queued({required int queuedAt}) = QueuedTurn;
  const factory TurnState.running({
    required int startedAt,
    required TurnPhase phase,
  }) = RunningTurn;
  const factory TurnState.completed({
    required int? startedAt,
    required int completedAt,
    required TurnCompletion completion,
  }) = CompletedTurn;
  const factory TurnState.cancelled({
    required int? startedAt,
    required int requestedAt,
    required int completedAt,
    required TurnCancellationCause cause,
  }) = CancelledTurn;
  const factory TurnState.failed({
    required int? startedAt,
    required int completedAt,
    required TurnFailure failure,
  }) = FailedTurn;
  const factory TurnState.budgetLimited({
    required int? startedAt,
    required int completedAt,
    required BudgetLimitSnapshot limit,
    required TurnRolloverOutcome rollover,
  }) = BudgetLimitedTurn;

  bool get isTerminal => switch (this) {
    QueuedTurn() || RunningTurn() => false,
    _ => true,
  };
  TurnStatus get status => switch (this) {
    QueuedTurn() => TurnStatus.queued,
    RunningTurn() => TurnStatus.running,
    CompletedTurn() => TurnStatus.completed,
    CancelledTurn() => TurnStatus.cancelled,
    FailedTurn() => TurnStatus.failed,
    BudgetLimitedTurn() => TurnStatus.budgetLimited,
  };
  String? get reason => switch (this) {
    FailedTurn(:final failure) => failure.message,
    BudgetLimitedTurn(:final limit) =>
      'Turn budget limited: ${limit.kind.name}',
    CancelledTurn(:final cause) => switch (cause) {
      UnspecifiedTurnCancellation() => 'Cancelled',
      UserRequestedTurnCancellation() => 'Cancelled by user',
      RuntimeShutdownTurnCancellation() => 'Runtime shutdown',
      AgentClosedTurnCancellation() => 'Agent closed',
      InterruptedTurnCancellation() => 'Interrupted',
      RecoveryTurnCancellation() => 'Cancelled during recovery',
      CoalescedTurnCancellation(:final targetTurnId) =>
        'Merged into Turn $targetTurnId',
    },
    _ => null,
  };
}

@Freezed(toStringOverride: false)
abstract class ConversationTurn with _$ConversationTurn {
  const factory ConversationTurn({
    required String? inputId,
    required String id,
    required String threadId,
    required int revision,
    required int updatedAt,
    required TurnState state,
  }) = _ConversationTurn;
}

@Freezed(toStringOverride: false)
sealed class TurnReadCancellationCause with _$TurnReadCancellationCause {
  const factory TurnReadCancellationCause.unspecified() =
      UnspecifiedTurnReadCancellation;
  const factory TurnReadCancellationCause.userRequested() =
      UserRequestedTurnReadCancellation;
  const factory TurnReadCancellationCause.runtimeShutdown() =
      RuntimeShutdownTurnReadCancellation;
  const factory TurnReadCancellationCause.agentClosed() =
      AgentClosedTurnReadCancellation;
  const factory TurnReadCancellationCause.interrupted() =
      InterruptedTurnReadCancellation;
  const factory TurnReadCancellationCause.recovery() =
      RecoveryTurnReadCancellation;
  const factory TurnReadCancellationCause.coalesced({
    required ReadText targetTurnId,
  }) = CoalescedTurnReadCancellation;
}

@Freezed(toStringOverride: false)
sealed class TurnReadRolloverOutcome with _$TurnReadRolloverOutcome {
  const factory TurnReadRolloverOutcome.notAttempted() =
      TurnReadRolloverNotAttempted;
  const factory TurnReadRolloverOutcome.succeeded() = TurnReadRolloverSucceeded;
  const factory TurnReadRolloverOutcome.failed({required ReadText error}) =
      TurnReadRolloverFailed;
}

@Freezed(toStringOverride: false)
abstract class TurnFailureRead with _$TurnFailureRead {
  const factory TurnFailureRead({
    required TurnFailureCategory category,
    required ProviderFailureKind? providerKind,
    required ReadText? code,
    required int? httpStatus,
    required ReadText message,
    required RetryDisposition retry,
  }) = _TurnFailureRead;
}

@Freezed(toStringOverride: false)
sealed class TurnReadState with _$TurnReadState {
  const factory TurnReadState.queued({required int queuedAt}) = QueuedTurnRead;
  const factory TurnReadState.running({
    required int startedAt,
    required TurnPhase phase,
  }) = RunningTurnRead;
  const factory TurnReadState.completed({
    required int? startedAt,
    required int completedAt,
    required TurnCompletion completion,
  }) = CompletedTurnRead;
  const factory TurnReadState.cancelled({
    required int? startedAt,
    required int requestedAt,
    required int completedAt,
    required TurnReadCancellationCause cause,
  }) = CancelledTurnRead;
  const factory TurnReadState.failed({
    required int? startedAt,
    required int completedAt,
    required TurnFailureRead failure,
  }) = FailedTurnRead;
  const factory TurnReadState.budgetLimited({
    required int? startedAt,
    required int completedAt,
    required BudgetLimitSnapshot limit,
    required TurnReadRolloverOutcome rollover,
  }) = BudgetLimitedTurnRead;
}

@Freezed(toStringOverride: false)
abstract class TurnReadHeader with _$TurnReadHeader {
  const factory TurnReadHeader({
    required ReadScopeIdentity scope,
    required ReadText? inputId,
    required ReadText id,
    required ReadText threadId,
    required int revision,
    required int updatedAt,
    required TurnReadState state,
  }) = _TurnReadHeader;
}
