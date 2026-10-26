import 'package:freezed_annotation/freezed_annotation.dart';

part 'failures.freezed.dart';

enum StudioFailureCode {
  notInitialized,
  runtimeStopped,
  instanceBusy,
  invalidArgument,
  notFound,
  busy,
  conflict,
  staleRevision,
  superseded,
  permissionDenied,
  cancelled,
  cancellationTooLate,
  overloaded,
  unavailable,
  protocol,
  storage,
  update,
  internal,
}

enum StartupFailureKind {
  modeDefinitions,
  migration,
  persistentData,
  environment,
  cancelled,
  internal,
}

/// Immutable control diagnostics, mirroring the native closed facts contract.
/// These values carry evidence only; they do not own or retry an operation.
@Freezed(toStringOverride: false)
sealed class ControlFailureFacts with _$ControlFailureFacts {
  const factory ControlFailureFacts.unspecified() =
      UnspecifiedControlFailureFacts;
  const factory ControlFailureFacts.childThreadAction({
    required String threadId,
    required String action,
    required String? parentThreadId,
  }) = ChildThreadActionControlFailureFacts;
  const factory ControlFailureFacts.threadAction({
    required String threadId,
    required String action,
  }) = ThreadActionControlFailureFacts;
  const factory ControlFailureFacts.expectedExecution({
    required String threadId,
    required String expectedExecutionId,
  }) = ExpectedExecutionControlFailureFacts;
  const factory ControlFailureFacts.executing({
    required String threadId,
    required String executionId,
    required String phase,
  }) = ExecutingControlFailureFacts;
  const factory ControlFailureFacts.expectedContinuation({
    required String threadId,
    required String expectedContinuationId,
  }) = ExpectedContinuationControlFailureFacts;
  const factory ControlFailureFacts.continuationAccepted({
    required String threadId,
    required String operationId,
    required bool accepted,
  }) = ContinuationAcceptedControlFailureFacts;
  const factory ControlFailureFacts.continuationOperation({
    required String threadId,
    required String operationId,
  }) = ContinuationOperationControlFailureFacts;
  const factory ControlFailureFacts.continuationPointConflict({
    required String threadId,
    required String operationId,
    required String expectedContinuationId,
    required String acceptedContinuationId,
  }) = ContinuationPointConflictControlFailureFacts;
  const factory ControlFailureFacts.continuationRouteConflict({
    required String threadId,
    required String operationId,
    required int expectedModelRouteRevision,
    required int acceptedModelRouteRevision,
  }) = ContinuationRouteConflictControlFailureFacts;
  const factory ControlFailureFacts.staleContinuation({
    required String threadId,
    required String expectedContinuationId,
    required String currentContinuationId,
  }) = StaleContinuationControlFailureFacts;
  const factory ControlFailureFacts.claimedContinuation({
    required String threadId,
    required String continuationId,
  }) = ClaimedContinuationControlFailureFacts;
  const factory ControlFailureFacts.childInteraction({
    required String interactionId,
    required String interactionThreadId,
  }) = ChildInteractionControlFailureFacts;
  const factory ControlFailureFacts.interactionRevision({
    required String interactionId,
    required int expectedRevision,
    required int currentRevision,
  }) = InteractionRevisionControlFailureFacts;
  const factory ControlFailureFacts.interactionTerminal({
    required String interactionId,
    required int currentRevision,
  }) = InteractionTerminalControlFailureFacts;
  const factory ControlFailureFacts.interactionOperation({
    required String operationId,
    required String interactionId,
  }) = InteractionOperationControlFailureFacts;
  const factory ControlFailureFacts.childHost({
    required String hostThreadId,
    required bool hostIsChild,
  }) = ChildHostControlFailureFacts;
  const factory ControlFailureFacts.interactionHost({
    required String hostThreadId,
    required String interactionThreadId,
  }) = InteractionHostControlFailureFacts;
  const factory ControlFailureFacts.decisionDurability({
    required String interactionId,
    required bool decisionSaved,
  }) = DecisionDurabilityControlFailureFacts;
  const factory ControlFailureFacts.unreadableDecision({
    required String threadId,
    required String interactionId,
  }) = UnreadableDecisionControlFailureFacts;
  const factory ControlFailureFacts.decisionIdentity({
    required String interactionId,
    required int currentRevision,
    required bool operationIdentityRecorded,
  }) = DecisionIdentityControlFailureFacts;
}

@Freezed(toStringOverride: false)
abstract class ValidationIssue with _$ValidationIssue {
  const factory ValidationIssue({
    required String code,
    required String path,
    required String message,
  }) = _ValidationIssue;
}

@Freezed(toStringOverride: false)
sealed class StudioFailureDetails with _$StudioFailureDetails {
  const StudioFailureDetails._();

  const factory StudioFailureDetails.startup({
    required String step,
    required StartupFailureKind kind,
  }) = StartupFailureDetails;
  const factory StudioFailureDetails.revision({
    required int expected,
    required int actual,
  }) = RevisionFailureDetails;
  const factory StudioFailureDetails.sshAuthentication({
    required bool? passwordOffered,
  }) = SshAuthenticationFailureDetails;
  const factory StudioFailureDetails.reason({required String reason}) =
      ReasonFailureDetails;
  const factory StudioFailureDetails.control({
    required String reason,
    required ControlFailureFacts facts,
  }) = ControlFailureDetails;
  const factory StudioFailureDetails.identity({required String identity}) =
      IdentityFailureDetails;
  const factory StudioFailureDetails.timelineRevision({
    required String itemId,
    required String field,
    required int revision,
  }) = TimelineRevisionFailureDetails;
  factory StudioFailureDetails.validation({
    required List<ValidationIssue> issues,
  }) = ValidationFailureDetails;
  const factory StudioFailureDetails.thread({required String threadId}) =
      ThreadFailureDetails;
  const factory StudioFailureDetails.resourceLimit({
    required String resource,
    required int capacity,
  }) = ResourceLimitFailureDetails;

  /// Stable published bot diagnostics, not an arbitrary provider response.
  const factory StudioFailureDetails.bot({
    required String code,
    required String? platformCode,
    required String? guidance,
  }) = BotFailureDetails;

  /// The catalog revision a stale delegation/statistics cursor was issued for.
  const factory StudioFailureDetails.catalogRevision({required int revision}) =
      CatalogRevisionFailureDetails;
}

@Freezed(toStringOverride: false)
final class ValidationFailureDetails extends StudioFailureDetails
    with _$ValidationFailureDetails {
  ValidationFailureDetails({required List<ValidationIssue> issues})
    : issues = List.unmodifiable(issues),
      super._();

  final List<ValidationIssue> issues;
}

/// Query errors do not carry evidence about whether a command was dispatched.
@Freezed(toStringOverride: false)
abstract class StudioFailure with _$StudioFailure implements Exception {
  const StudioFailure._();

  const factory StudioFailure({
    required StudioFailureCode code,
    required String message,
    required bool retryable,
    required String correlationId,
    StudioFailureDetails? details,
  }) = _StudioFailure;

  @override
  String toString() =>
      'StudioFailure(code: ${code.name}, correlationId: $correlationId)';
}
