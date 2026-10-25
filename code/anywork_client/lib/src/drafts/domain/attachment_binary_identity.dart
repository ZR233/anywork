import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment_binary_identity.freezed.dart';

/// Native-issued identity of one pinned file, not a facet/product revision.
@Freezed(toStringOverride: false)
abstract class AttachmentBinaryIdentity with _$AttachmentBinaryIdentity {
  const factory AttachmentBinaryIdentity({
    required String scopeId,
    required String runtimeEpoch,
    required int incarnation,
    required AttachmentBinaryTarget target,
  }) = _AttachmentBinaryIdentity;
}

@Freezed(toStringOverride: false)
sealed class AttachmentBinaryTarget with _$AttachmentBinaryTarget {
  const factory AttachmentBinaryTarget.draft({required String draftId}) =
      DraftAttachmentBinaryTarget;
  const factory AttachmentBinaryTarget.thread({
    required String threadId,
    required String attachmentId,
  }) = ThreadAttachmentBinaryTarget;
}
