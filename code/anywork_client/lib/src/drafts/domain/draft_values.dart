import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../modes.dart';
import '../../../models.dart';
import '../../../resources.dart';
import '../../../workspace.dart';
import '../../configuration/domain/configuration_state.dart';
import '../../configuration/domain/start_route_values.dart';

part 'draft_values.freezed.dart';

enum AttachmentModality { image, video, file }

@Freezed(toStringOverride: false)
abstract class AttachmentMetadata with _$AttachmentMetadata {
  const factory AttachmentMetadata({
    required String id,
    required AttachmentModality modality,
    required String mediaType,
    required String filename,
    required int byteSize,
    int? width,
    int? height,
  }) = _AttachmentMetadata;
}

@Freezed(toStringOverride: false)
sealed class AttachmentAdmissionContext with _$AttachmentAdmissionContext {
  const factory AttachmentAdmissionContext.existingThread(String threadId) =
      ExistingThreadAttachmentAdmissionContext;
  const factory AttachmentAdmissionContext.newThread({
    required ModelSelection route,
  }) = NewThreadAttachmentAdmissionContext;
}

@Freezed(toStringOverride: false)
sealed class AttachmentDraftSource with _$AttachmentDraftSource {
  const factory AttachmentDraftSource.localFile(String path) =
      LocalFileAttachmentDraftSource;
  const factory AttachmentDraftSource.remoteUrl(
    String url, {
    String? filename,
  }) = RemoteUrlAttachmentDraftSource;
}

@Freezed(toStringOverride: false)
final class StudioPromptInput with _$StudioPromptInput {
  StudioPromptInput({
    required this.inputId,
    required this.text,
    required List<String> attachmentDraftIds,
  }) : attachmentDraftIds = List.unmodifiable(attachmentDraftIds);
  final String inputId;
  final String text;
  final List<String> attachmentDraftIds;
}

@Freezed(toStringOverride: false)
sealed class DraftSubmissionState with _$DraftSubmissionState {
  const factory DraftSubmissionState.idle() = IdleDraftSubmission;
  const factory DraftSubmissionState.submitting({
    required OperationId operationId,
    required String inputId,
  }) = SubmittingDraft;
  const factory DraftSubmissionState.failed({
    required OperationId? operationId,
    required String? inputId,
    required StudioFailure error,
  }) = FailedDraftSubmission;
  const factory DraftSubmissionState.unknownOutcome({
    required OperationId operationId,
    required String inputId,
    required StudioFailure error,
  }) = UnknownDraftSubmission;
}

@Freezed(toStringOverride: false)
abstract class AttachmentCleanupIssue with _$AttachmentCleanupIssue {
  const factory AttachmentCleanupIssue({
    required String attachmentDraftId,
    required StudioFailure error,
  }) = _AttachmentCleanupIssue;
}

@Freezed(toStringOverride: false)
final class ComposerDraftState with _$ComposerDraftState {
  ComposerDraftState({
    required this.stamp,
    required this.text,
    required List<AttachmentMetadata> attachments,
    required this.attachmentGeneration,
    required this.submissionRevision,
    required this.submission,
    required List<AttachmentCleanupIssue> cleanupIssues,
  }) : attachments = List.unmodifiable(attachments),
       cleanupIssues = List.unmodifiable(cleanupIssues);
  final DraftStamp stamp;
  final String text;
  final List<AttachmentMetadata> attachments;
  final int attachmentGeneration;
  final int submissionRevision;
  final DraftSubmissionState submission;
  final List<AttachmentCleanupIssue> cleanupIssues;
}

@Freezed(toStringOverride: false)
final class StartDraftState with _$StartDraftState {
  StartDraftState({
    required this.stamp,
    required this.text,
    required List<AttachmentMetadata> attachments,
    required this.attachmentGeneration,
    required this.submissionRevision,
    required this.submission,
    required List<AttachmentCleanupIssue> cleanupIssues,
    required this.mode,
    required this.workspaceMode,
    required this.delegationModeOverride,
    required this.delegationPreferenceOverride,
    required this.routePreparation,
    required this.preparation,
  }) : attachments = List.unmodifiable(attachments),
       cleanupIssues = List.unmodifiable(cleanupIssues);
  final DraftStamp stamp;
  final String text;
  final List<AttachmentMetadata> attachments;
  final int attachmentGeneration;
  final int submissionRevision;
  final DraftSubmissionState submission;
  final List<AttachmentCleanupIssue> cleanupIssues;
  final ThreadModeId mode;
  final ThreadWorkspaceMode workspaceMode;

  /// Independent draft intent. null follows canonical configuration at freeze;
  /// it is not replaced by a copied default when settings or observers change.
  final DelegationMode? delegationModeOverride;

  /// Profile mode keeps this intent without applying its automatic-mode prompt.
  final DelegationPreference? delegationPreferenceOverride;
  final StartRoutePreparation routePreparation;
  final NewThreadPreparation? preparation;
}

/// Local read preparation, separate from a dispatched creation's progress.
/// lastKnown retains its own sources/query; it never authorizes a new submit.
@Freezed(toStringOverride: false)
sealed class StartRoutePreparation with _$StartRoutePreparation {
  const factory StartRoutePreparation.unread({
    required StartRouteIntent intent,
    required StartRouteRead? lastKnown,
  }) = UnreadStartRoutePreparation;
  const factory StartRoutePreparation.loading({
    required ConfigurationRoleReadTarget? sources,
    required StartRouteQuery query,
    required StartRouteIntent intent,
    required StartRouteRead? lastKnown,
  }) = LoadingStartRoutePreparation;
  const factory StartRoutePreparation.failure({
    required ConfigurationRoleReadTarget? sources,
    required StartRouteQuery query,
    required StartRouteIntent intent,
    required StudioFailure error,
    required StartRouteRead? lastKnown,
  }) = FailedStartRoutePreparation;
  const factory StartRoutePreparation.unavailable({
    required UnavailableStartRouteRead result,
  }) = UnavailableStartRoutePreparation;
  const factory StartRoutePreparation.ready({
    required ReadyStartRouteRead result,
  }) = ReadyStartRoutePreparation;
}

@freezed
abstract class StartModelIntent with _$StartModelIntent {
  const factory StartModelIntent({
    required String accountId,
    required String modelId,
  }) = _StartModelIntent;
}

@freezed
final class StartRoutePreferences with _$StartRoutePreferences {
  StartRoutePreferences({
    required Map<String, StartModelIntent> models,
    required Map<String, String> efforts,
  }) : models = Map.unmodifiable(models),
       efforts = Map.unmodifiable(efforts);
  final Map<String, StartModelIntent> models;
  final Map<String, String> efforts;
}

enum NewThreadPreparationPhase { preparing, failed, unknownOutcome }

enum ThreadPreparationStage {
  checkingProject,
  preparingWorkspace,
  resolvingRepository,
  creatingWorktree,
  initializingSession,
  submittingPrompt,
}

@Freezed(toStringOverride: false)
abstract class ThreadPreparationProgress with _$ThreadPreparationProgress {
  const factory ThreadPreparationProgress({
    required String projectId,
    required String inputId,
    required ThreadPreparationStage stage,
    required String? workspacePath,
    required String? branch,
  }) = _ThreadPreparationProgress;
}

@Freezed(toStringOverride: false)
abstract class NewThreadPreparation with _$NewThreadPreparation {
  const factory NewThreadPreparation({
    required String projectId,
    required String inputId,
    required ThreadWorkspaceMode workspaceMode,
    required ThreadPreparationProgress? progress,
    required NewThreadPreparationPhase phase,
    required StudioFailure? failure,
  }) = _NewThreadPreparation;
}
