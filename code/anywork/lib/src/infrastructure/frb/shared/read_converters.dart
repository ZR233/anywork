import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/observation.dart' as native;
import 'adapter_failure.dart';
import 'exact_numbers.dart';

ReadText readTextFromBridge(native.BridgeReadText value) => switch (value) {
  native.BridgeReadText_Inline(:final text) => ReadText.inline(text: text),
  native.BridgeReadText_Deferred(:final fieldId, :final utf8Bytes) =>
    ReadText.deferred(
      fieldId: exactU64(fieldId, 'text field identity'),
      utf8Bytes: exactU64(utf8Bytes, 'text UTF-8 bytes'),
    ),
};

ReadText? nullableReadText(native.BridgeReadText? value) =>
    value == null ? null : readTextFromBridge(value);

TextChunk textChunkFromBridge(native.BridgeTextChunk value) => TextChunk(
  fieldId: exactU64(value.fieldId, 'text field identity'),
  offset: exactU64(value.offset, 'text UTF-8 offset'),
  text: value.text,
  nextOffset: nullableU64(value.nextOffset, 'next text UTF-8 offset'),
);

TypedListRef typedListFromBridge(native.BridgeTypedListRef value) => TypedListRef(
  listId: exactU64(value.listId, 'typed list identity'),
  total: exactU64(value.total, 'typed list count'),
);

int? nullableU64(BigInt? value, String field) =>
    value == null ? null : exactU64(value, field);

int? nullableI64(BigInt? value, String field) =>
    value == null ? null : exactI64(value, field);

/// A read reply belongs to the immutable scope captured by its actual owner,
/// not merely an equal numeric revision or the latest selected Thread.
void requireReadScope(ReadScopeIdentity actual, ReadScopeIdentity expected) {
  if (actual.scopeId != expected.scopeId ||
      actual.runtimeEpoch != expected.runtimeEpoch ||
      actual.incarnation != expected.incarnation ||
      actual.sourceRevision != expected.sourceRevision) {
    throw adapterProtocol('thread-read-scope-identity');
  }
}
