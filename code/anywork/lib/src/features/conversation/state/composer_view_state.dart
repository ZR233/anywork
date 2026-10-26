import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'editor_keys.dart';

part 'composer_view_state.freezed.dart';

/// Current catalog presentation only. Unknown and failed reads never infer
/// support, and this value never owns draft attachments or admission policy.
@Freezed(toStringOverride: false)
abstract class ComposerAttachmentState with _$ComposerAttachmentState {
  const ComposerAttachmentState._();
  const factory ComposerAttachmentState({
    @Default([]) List<ModelInputCapability> local,
    @Default([]) List<ModelInputCapability> remote,
    StudioFailure? error,
  }) = _ComposerAttachmentState;

  List<String> get localExtensions {
    final modalities = local.map((capability) => capability.modality).toSet();
    if (modalities.contains(ModelModality.file)) return const [];
    return [
      if (modalities.contains(ModelModality.image)) ...const [
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
      ],
      if (modalities.contains(ModelModality.video)) ...const [
        'mp4',
        'mov',
        'webm',
        'mkv',
      ],
    ];
  }
}

@Freezed(toStringOverride: false)
abstract class ComposerViewState with _$ComposerViewState {
  const ComposerViewState._();
  const factory ComposerViewState({
    required ComposerKey key,
    ComposerDraftState? draft,
    StartDraftState? startDraft,
    StartRoutePreferences? preferences,
    @Default('') String urlRaw,
    ValidationIssue? inputIssue,
    StudioFailure? error,
    StudioFailure? platformError,
    OperationState? operation,
    @Default(0) int latestIntent,
    @Default(false) bool pending,
    @Default(false) bool platformPending,
    @Default(false) bool closing,
  }) = _ComposerViewState;

  /// Borrow the D1 value; do not create a second text or attachment ledger.
  String get text => draft?.text ?? startDraft?.text ?? '';
  List<AttachmentMetadata> get attachments =>
      draft?.attachments ?? startDraft?.attachments ?? const [];
  DraftSubmissionState? get submission =>
      draft?.submission ?? startDraft?.submission;
  StudioFailure? get submissionFailure => switch (submission) {
    FailedDraftSubmission(:final error) ||
    UnknownDraftSubmission(:final error) => error,
    _ => null,
  };
  bool get hasInput => text.trim().isNotEmpty || attachments.isNotEmpty;
}
