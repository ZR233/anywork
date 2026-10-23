import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'exit_state.freezed.dart';

enum ApplicationExitPhase {
  running,
  sealing,
  closingDartOwners,
  finalizingRuntime,
  finishingDiagnostics,
  finished,
}

/// Presentation only: deadlines, tasks, handles and permits stay with owners.
@Freezed(toStringOverride: false)
abstract class ApplicationExitState with _$ApplicationExitState {
  const ApplicationExitState._();

  const factory ApplicationExitState({
    required ApplicationExitPhase phase,
    required ExitIntent? intent,
    required String? readyUpdateVersion,
    required List<UnresolvedResource> unresolved,
    required List<StudioShutdownIssue> externalIssues,
    required StudioExitReport? report,
    required StudioShutdownIssue? diagnosticsIssue,
  }) = _ApplicationExitState;

  bool get exiting => phase != ApplicationExitPhase.running;

  /// Installer launch is separate from shutdown; neither proves installation.
  bool get failed =>
      diagnosticsIssue != null ||
      report?.shutdown.outcome == ShutdownOutcome.degraded ||
      report?.updateHandoff is FailedUpdateHandoff;
}
