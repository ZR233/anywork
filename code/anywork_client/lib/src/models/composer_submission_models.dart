import 'dart:typed_data';

import 'attachment_models.dart';

enum ComposerSubmissionPhase { sending, accepted, unknownOutcome }

/// A temporary, immutable view of a submitted composer input.
final class ComposerSubmission {
  ComposerSubmission({
    required this.inputId,
    required this.text,
    required Iterable<AttachmentDraftView> attachments,
    required this.phase,
  }) : attachments = freezeAttachments(attachments);

  ComposerSubmission._({
    required this.inputId,
    required this.text,
    required this.attachments,
    required this.phase,
  });

  final String inputId;
  final String text;
  final List<AttachmentDraftView> attachments;
  final ComposerSubmissionPhase phase;

  ComposerSubmission withPhase(ComposerSubmissionPhase phase) =>
      ComposerSubmission._(
        inputId: inputId,
        text: text,
        attachments: attachments,
        phase: phase,
      );

  static List<AttachmentDraftView> freezeAttachments(
    Iterable<AttachmentDraftView> attachments,
  ) => List.unmodifiable(
    attachments.map((attachment) {
      final preview = attachment.previewBytes;
      return AttachmentDraftView(
        id: attachment.id,
        modality: attachment.modality,
        mediaType: attachment.mediaType,
        filename: attachment.filename,
        byteSize: attachment.byteSize,
        width: attachment.width,
        height: attachment.height,
        previewBytes: preview == null
            ? null
            : Uint8List.fromList(preview).asUnmodifiableView(),
      );
    }),
  );
}
