import 'package:anywork_client/drafts.dart';

import '../../../rust/api/studio/types/response.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/exact_numbers.dart';

/// Do not reconstruct the native digest from Dart input or serialization.
SubmitPromptReceipt submitReceiptFromBridge(native.SubmitPromptResponse value) {
  if (value.requestDigest.length != 71 ||
      !_digest.hasMatch(value.requestDigest)) {
    throw adapterProtocol('submit-request-digest');
  }
  return SubmitPromptReceipt(
    threadId: value.threadId,
    inputId: value.inputId,
    cursor: exactU64(value.cursor, 'accepted input sequence'),
    requestDigest: value.requestDigest,
  );
}

InputAcceptanceEvidence inputAcceptanceFromBridge(
  native.BridgeInputAcceptanceEvidence value,
) => InputAcceptanceEvidence(
  acceptedSequence: exactU64(
    value.acceptedSequence,
    'persisted input sequence',
  ),
  // Missing legacy evidence is unknown; it is not a fabricated digest or false.
  requestDigest: value.requestDigest,
  disposition: switch (value.disposition) {
    native.BridgePersistedInputDisposition.consumed =>
      PersistedInputDisposition.consumed,
    native.BridgePersistedInputDisposition.discarded =>
      PersistedInputDisposition.discarded,
  },
);

final _digest = RegExp(r'^sha256:[0-9a-f]{64}$');
