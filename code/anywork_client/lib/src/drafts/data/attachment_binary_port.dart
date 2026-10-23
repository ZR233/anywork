import 'dart:typed_data';

import '../../../resources.dart' show FeedCloseReport;
import '../domain/attachment_binary_identity.dart';

/// Opens only the native-authorized original file. No whole-buffer fallback,
/// arbitrary path, attachment admission or model/permission policy lives here.
abstract interface class AttachmentBinaryPort {
  Future<AttachmentBinaryRead> openDraftBinary(String draftId);
  Future<AttachmentBinaryRead> openThreadBinary(String threadId, String attachmentId);
}

/// Producer-less query scope. Identity and length remain those of the same pin.
/// Closing joins opening/IO and uses identity.scopeId as FeedCloseReport.feedId.
abstract interface class AttachmentBinaryRead {
  AttachmentBinaryIdentity get identity;
  int get byteLength;

  /// maxBytes is 1..262144, default 64 KiB; offset==byteLength is a valid empty
  /// terminal block. Every returned buffer is exclusively owned by the caller.
  /// Offsets outside 0..byteLength are InvalidArgument; premature file EOF is
  /// a real Storage failure, not an empty successful intermediate block.
  Future<AttachmentBinaryChunk> read({required int offset, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

/// A temporary owned binary result, never a Freezed/canonical/ViewState value.
final class AttachmentBinaryChunk {
  AttachmentBinaryChunk({required this.offset, required Uint8List bytes, required this.nextOffset})
      : bytes = Uint8List.fromList(bytes);
  final int offset;
  final Uint8List bytes;
  final int? nextOffset;
}
