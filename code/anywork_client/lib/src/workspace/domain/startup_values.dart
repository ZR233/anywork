import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

part 'startup_values.freezed.dart';

enum StartupStage {
  preparing,
  waitingForSteps,
  closingResources,
  backingUp,
  resetting,
  startingServices,
  openingStorage,
  loadingConfiguration,
  readingProjects,
  preparingResources,
  ready,
  failed,
}

@freezed
sealed class StartupPhase with _$StartupPhase {
  const factory StartupPhase.loadingLibrary() = LoadingLibraryStartupPhase;
  const factory StartupPhase.preparingAttempt() = PreparingAttemptStartupPhase;
  const factory StartupPhase.native({required StartupStage stage}) =
      NativeStartupPhase;
}

@Freezed(toStringOverride: false)
sealed class StartupState with _$StartupState {
  const factory StartupState.idle() = IdleStartupState;
  const factory StartupState.starting({
    required int? attemptId,
    required StartupPhase phase,
  }) = StartingStartupState;
  const factory StartupState.ready({
    required int attemptId,
    required RuntimeReady result,
  }) = ReadyStartupState;
  const factory StartupState.failed({
    required int? attemptId,
    required StudioFailure error,
  }) = FailedStartupState;
}

@freezed
abstract class RuntimeStartupReadRef with _$RuntimeStartupReadRef {
  const factory RuntimeStartupReadRef({
    required int entry,
    required int revision,
  }) = _RuntimeStartupReadRef;
}

@freezed
abstract class RuntimeReady with _$RuntimeReady {
  const factory RuntimeReady({
    required int revision,
    required int readyAt,
    required RuntimeStartupReadRef details,
  }) = _RuntimeReady;
}

@Freezed(toStringOverride: false)
abstract class StartupRecovery with _$StartupRecovery {
  const factory StartupRecovery({
    required String backupPath,
    required String reason,
    required int createdAt,
  }) = _StartupRecovery;
}

@freezed
abstract class StartupActiveTurn with _$StartupActiveTurn {
  const factory StartupActiveTurn({
    required String threadId,
    required String turnId,
  }) = _StartupActiveTurn;
}

@freezed
abstract class StartupActiveTurnPage with _$StartupActiveTurnPage {
  const factory StartupActiveTurnPage({
    required RuntimeStartupReadRef reference,
    required int offset,
    required int total,
    required List<StartupActiveTurn> items,
    required int? nextOffset,
  }) = _StartupActiveTurnPage;
}

enum ExitIntent { exit, updateRestart }
enum ShutdownOutcome { notStarted, clean, degraded }

@freezed
sealed class PendingPersistence with _$PendingPersistence {
  const factory PendingPersistence.unknown() = UnknownPendingPersistence;
  const factory PendingPersistence.pending({required int count}) =
      CountPendingPersistence;
  const factory PendingPersistence.drained() = DrainedPendingPersistence;
}

@Freezed(toStringOverride: false)
final class StudioShutdownReport with _$StudioShutdownReport {
  StudioShutdownReport({
    required this.outcome,
    required List<StudioShutdownIssue> issues,
    required this.persistence,
  }) : issues = List.unmodifiable(issues);

  final ShutdownOutcome outcome;
  final List<StudioShutdownIssue> issues;
  final PendingPersistence persistence;
}

@Freezed(toStringOverride: false)
sealed class UpdateHandoff with _$UpdateHandoff {
  const factory UpdateHandoff.notRequested() = NotRequestedUpdateHandoff;
  const factory UpdateHandoff.launched({required String version}) =
      LaunchedUpdateHandoff;
  const factory UpdateHandoff.failed({required SourceStateError error}) =
      FailedUpdateHandoff;
}

@Freezed(toStringOverride: false)
abstract class StudioExitReport with _$StudioExitReport {
  const factory StudioExitReport({
    required StudioShutdownReport shutdown,
    required UpdateHandoff updateHandoff,
  }) = _StudioExitReport;
}
