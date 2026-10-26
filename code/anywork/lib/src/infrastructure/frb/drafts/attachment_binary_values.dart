import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/attachment_binary.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/exact_numbers.dart';

AttachmentBinaryIdentity attachmentBinaryIdentityFromBridge(
  native.BridgeAttachmentBinaryIdentity value,
) {
  final target = switch (value.target) {
    native.BridgeAttachmentBinaryTarget_Draft(:final draftId) =>
      AttachmentBinaryTarget.draft(draftId: draftId),
    native.BridgeAttachmentBinaryTarget_Thread(
      :final threadId,
      :final attachmentId,
    ) =>
      AttachmentBinaryTarget.thread(
        threadId: threadId,
        attachmentId: attachmentId,
      ),
  };
  return AttachmentBinaryIdentity(
    scopeId: value.scopeId,
    runtimeEpoch: value.runtimeEpoch,
    incarnation: exactU64(value.incarnation, 'attachment binary incarnation'),
    target: target,
  );
}

void requireAttachmentBinaryIdentity(
  AttachmentBinaryIdentity value,
  AttachmentBinaryTarget expectedTarget,
) {
  if (value.scopeId.isEmpty ||
      value.runtimeEpoch.isEmpty ||
      value.target != expectedTarget) {
    throw adapterProtocol('attachment-binary-identity');
  }
}

// FRB 2.13 uses int for desktop PlatformInt64. Normalize it to the shared exact
// checker, rather than treating an i64 as a u64 or truncating a BigInt with toInt.
int attachmentBinaryLengthFromBridge(int value) {
  final length = exactI64(BigInt.from(value), 'attachment binary byte length');
  if (length < 0) throw adapterProtocol('attachment-binary-length');
  return length;
}

void requireAttachmentBinaryArguments(
  int offset,
  int maxBytes,
  int byteLength,
) {
  if (maxBytes < 1 || maxBytes > 262144 || offset < 0 || offset > byteLength) {
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message:
          'Binary maxBytes must be in 1..262144 and offset in 0..byteLength',
      retryable: false,
      correlationId: 'adapter-attachment-binary-arguments',
    );
  }
}

AttachmentBinaryChunk attachmentBinaryChunkFromBridge(
  native.BridgeAttachmentBinaryChunk value, {
  required int offset,
  required int maxBytes,
  required int byteLength,
}) {
  final actualOffset = exactI64(
    BigInt.from(value.offset),
    'attachment binary offset',
  );
  final nativeNext = value.nextOffset;
  final nextOffset = nativeNext == null
      ? null
      : exactI64(BigInt.from(nativeNext), 'attachment binary next offset');
  final count = value.bytes.length;
  // Subtract before adding: once these bounds hold, end is representable and
  // cannot wrap past the length of the same original pin.
  final remaining = byteLength - offset;
  if (actualOffset != offset ||
      count > maxBytes ||
      count > remaining ||
      remaining > 0 && count == 0) {
    throw adapterProtocol('attachment-binary-chunk-binding');
  }
  final end = offset + count;
  if (nextOffset != (end < byteLength ? end : null)) {
    throw adapterProtocol('attachment-binary-chunk-continuation');
  }
  // FRB Vec<u8> is a mutable Uint8List, not an immutable value. The SDK chunk
  // constructor copies it into a caller-exclusive buffer; retain no native view
  // or adapter cache and do not claim that `final` makes its contents immutable.
  return AttachmentBinaryChunk(
    offset: actualOffset,
    bytes: value.bytes,
    nextOffset: nextOffset,
  );
}
