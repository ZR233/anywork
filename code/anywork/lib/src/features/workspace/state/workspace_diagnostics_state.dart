import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'workspace_view_state.dart';

part 'workspace_diagnostics_state.freezed.dart';

/// Read-only execution identity, not another writable Workspace selection.
@Freezed(toStringOverride: false)
abstract class StoragePanelTarget with _$StoragePanelTarget {
  const factory StoragePanelTarget({
    required String threadId,
    required int bindingGeneration,
    required ThreadExecutionState execution,
  }) = _StoragePanelTarget;
}

@Freezed(toStringOverride: false)
abstract class WorkspaceDiagnosticsState with _$WorkspaceDiagnosticsState {
  const factory WorkspaceDiagnosticsState({
    required RecoveryState recovery,
    required PersistenceState persistence,
    required PersistenceQueueState queue,
    required Map<String, WorkspaceActionPresentation> actions,
    required Map<String, StudioFailure> readErrors,
    required StoragePanelTarget? storageTarget,
    required bool queueExpanded,
    required Set<String> dismissedRecoveryIssues,
  }) = _WorkspaceDiagnosticsState;
}
