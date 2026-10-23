import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'editor_keys.dart';

part 'composer_view_state.freezed.dart';

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
  List<AttachmentMetadata> get attachments => draft?.attachments ?? startDraft?.attachments ?? const [];
  DraftSubmissionState? get submission => draft?.submission ?? startDraft?.submission;
  StudioFailure? get submissionFailure => switch (submission) {
    FailedDraftSubmission(:final error) || UnknownDraftSubmission(:final error) => error,
    _ => null,
  };
  bool get hasInput => text.trim().isNotEmpty || attachments.isNotEmpty;
}
