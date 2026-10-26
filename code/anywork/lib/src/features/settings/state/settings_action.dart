import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_action.freezed.dart';

enum SettingsActionOutcome {
  succeeded,
  rejected,
  unknownOutcome,
  synchronizationFailed,
}

/// Presentation of one frozen intent. Repository operations remain the owner
/// after this value, its observer, or the whole editor has gone away.
@freezed
abstract class SettingsAction with _$SettingsAction {
  const SettingsAction._();

  const factory SettingsAction({
    required int intent,
    @Default(false) bool pending,
    OperationState? operation,
    SettingsActionOutcome? outcome,
    StudioFailure? error,
    StudioFailure? observationError,
  }) = _SettingsAction;

  bool get succeeded => outcome == SettingsActionOutcome.succeeded;

  bool get uncertain => outcome == SettingsActionOutcome.unknownOutcome;

  bool get preventsResubmission =>
      pending ||
      uncertain ||
      outcome == SettingsActionOutcome.synchronizationFailed;
}

/// Deliberately inspects the typed command result, never its error code/text.
SettingsAction settledSettingsAction<T>(
  int intent,
  CommandResult<T> result, {
  OperationState? operation,
}) => switch (result) {
  CommittedCommandResult<T>() => SettingsAction(
    intent: intent,
    operation: operation,
    outcome: SettingsActionOutcome.succeeded,
  ),
  AcknowledgedCommandResult<T>() => SettingsAction(
    intent: intent,
    operation: operation,
    outcome: SettingsActionOutcome.succeeded,
  ),
  RejectedCommandResult<T>(:final error) => SettingsAction(
    intent: intent,
    operation: operation,
    outcome: SettingsActionOutcome.rejected,
    error: error,
  ),
  UnknownOutcomeCommandResult<T>(:final error) => SettingsAction(
    intent: intent,
    operation: operation,
    outcome: SettingsActionOutcome.unknownOutcome,
    error: error,
  ),
  SyncFailedCommandResult<T>(:final error) => SettingsAction(
    intent: intent,
    operation: operation,
    outcome: SettingsActionOutcome.synchronizationFailed,
    error: error,
  ),
  AcknowledgedSyncFailedCommandResult<T>(:final error) => SettingsAction(
    intent: intent,
    operation: operation,
    outcome: SettingsActionOutcome.synchronizationFailed,
    error: error,
  ),
};
