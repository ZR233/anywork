import 'package:anywork_client/drafts_ports.dart';

import 'attachment_binary_read.dart';

/// The real binary-only leaf, not a partial Drafts factory or a whole-file API.
final class FrbAttachmentBinaryPort implements AttachmentBinaryPort {
  const FrbAttachmentBinaryPort();

  @override
  Future<AttachmentBinaryRead> openDraftBinary(String draftId) async {
    final read = FrbAttachmentBinaryRead.draft(draftId);
    await read.opened;
    return read;
  }

  @override
  Future<AttachmentBinaryRead> openThreadBinary(
    String threadId,
    String attachmentId,
  ) async {
    final read = FrbAttachmentBinaryRead.thread(threadId, attachmentId);
    await read.opened;
    return read;
  }
}
