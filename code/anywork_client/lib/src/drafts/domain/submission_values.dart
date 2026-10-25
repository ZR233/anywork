import 'package:freezed_annotation/freezed_annotation.dart';

import '../../workspace/domain/directory_values.dart';

part 'submission_values.freezed.dart';

/// cursor is the native accepted_sequence, never a history/delivery watermark.
@freezed
abstract class SubmitPromptReceipt with _$SubmitPromptReceipt {
  const factory SubmitPromptReceipt({
    required String threadId,
    required String inputId,
    required int cursor,
    required String requestDigest,
  }) = _SubmitPromptReceipt;
}

enum PersistedInputDisposition { consumed, discarded }

@freezed
abstract class InputAcceptanceEvidence with _$InputAcceptanceEvidence {
  const factory InputAcceptanceEvidence({
    required int acceptedSequence,
    required String? requestDigest,
    required PersistedInputDisposition disposition,
  }) = _InputAcceptanceEvidence;
}

@freezed
abstract class StartNewThreadResult with _$StartNewThreadResult {
  const factory StartNewThreadResult({
    required WorkspaceThreadRecord thread,
    required SubmitPromptReceipt receipt,
  }) = _StartNewThreadResult;
}
