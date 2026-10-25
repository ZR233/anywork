import 'package:anywork_client/conversation.dart'
    show ConversationActivationFailure, $ConversationActivationFailureCopyWith;
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'workspace_view_state.freezed.dart';

enum WorkspaceNavigationDestination { workspace, settings }

enum WorkspaceNameTarget { project, thread }

enum WorkspaceNameProblem { empty, tooLong }

@freezed
abstract class WorkspaceNavigationIntent with _$WorkspaceNavigationIntent {
  const factory WorkspaceNavigationIntent({
    required int serial,
    required WorkspaceNavigationDestination destination,
  }) = _WorkspaceNavigationIntent;
}

@Freezed(toStringOverride: false)
abstract class WorkspaceActionPresentation with _$WorkspaceActionPresentation {
  const factory WorkspaceActionPresentation({
    required int intent,
    required bool waiting,
    required OperationState? operation,
    required StudioFailure? admissionError,
    StudioFailure? observationError,
  }) = _WorkspaceActionPresentation;
}

@Freezed(toStringOverride: false)
abstract class WorkspaceNameEditor with _$WorkspaceNameEditor {
  const factory WorkspaceNameEditor({
    required int serial,
    required WorkspaceNameTarget target,
    required String id,
    required String raw,
    required WorkspaceNameProblem? problem,
    required bool saving,
    required StudioFailure? error,
  }) = _WorkspaceNameEditor;
}

@Freezed(toStringOverride: false)
abstract class WorkspaceViewState with _$WorkspaceViewState {
  const factory WorkspaceViewState({
    required WorkspaceState workspace,
    required ConversationActivationFailure? activationFailure,
    required ProjectDirectoryState projects,
    required AgentDirectoryState agents,
    required ProjectRecord? selectedProject,
    required bool projectLoading,
    required StudioFailure? projectReadError,
    required ThreadMetadataState? selectedMetadata,
    required StudioFailure? metadataDemandError,
    required Map<String, WorkspaceActionPresentation> actions,
    required WorkspaceOpenResult? openResult,
    required bool opening,
    required StudioFailure? openAdmissionError,
    required WorkspaceNavigationIntent? navigation,
    required WorkspaceNameEditor? nameEditor,
  }) = _WorkspaceViewState;
}
