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
