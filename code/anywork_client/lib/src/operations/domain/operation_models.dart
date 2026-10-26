import 'package:freezed_annotation/freezed_annotation.dart';

import '../../resources/domain/failures.dart';
import '../../resources/domain/identity.dart';

part 'operation_models.freezed.dart';

enum CommitDisposition { applied, noChange }

enum EffectPoint { immediate, nextTurn, futureSession }

enum OperationFailurePhase { rejected, unknownOutcome, syncFailed }

@freezed
abstract class Unit with _$Unit {
  const factory Unit() = _Unit;
}

@freezed
final class CommitReceipt with _$CommitReceipt {
  CommitReceipt({
    required this.operationId,
    required this.disposition,
    required List<ObservationStamp> targets,
    required this.effect,
    this.effective = false,
    this.durable = false,
    this.requiresIdentityObservation = false,
  }) : targets = List.unmodifiable(targets);

  final OperationId operationId;
  final CommitDisposition disposition;
  final List<ObservationStamp> targets;
  final EffectPoint effect;
  final bool effective;
  final bool durable;
  final bool requiresIdentityObservation;
}

@Freezed(toStringOverride: false)
sealed class CommandResult<T> with _$CommandResult<T> {
  const factory CommandResult.committed({
    required T value,
    required CommitReceipt receipt,
  }) = CommittedCommandResult<T>;
  const factory CommandResult.acknowledged({required T value}) =
      AcknowledgedCommandResult<T>;
  const factory CommandResult.rejected({required StudioFailure error}) =
      RejectedCommandResult<T>;
  const factory CommandResult.unknownOutcome({required StudioFailure error}) =
      UnknownOutcomeCommandResult<T>;
  const factory CommandResult.syncFailed({
    required T? value,
    required CommitReceipt receipt,
    required StudioFailure error,
  }) = SyncFailedCommandResult<T>;
  const factory CommandResult.acknowledgedSyncFailed({
    required T? value,
    required StudioFailure error,
  }) = AcknowledgedSyncFailedCommandResult<T>;
}

@Freezed(toStringOverride: false)
abstract class OperationState with _$OperationState {
  const OperationState._();

  const factory OperationState({
    required OperationId id,
    required String target,
    DraftStamp? draft,
    CommitReceipt? receipt,
    @Default(false) bool acknowledged,
    @Default(false) bool observed,
    @Default(false) bool effective,
    @Default(false) bool durable,
    OperationFailurePhase? failurePhase,
    StudioFailure? error,
    StudioFailure? evidenceError,
  }) = _OperationState;

  /// Unknown dispatch and an unobserved receipt remain protected even after a
  /// failure result has settled. No observer disappearing makes them resolved.
  bool get isPending =>
      failurePhase == OperationFailurePhase.unknownOutcome ||
      (receipt != null
          ? !observed
          : !acknowledged && failurePhase != OperationFailurePhase.rejected);
}
