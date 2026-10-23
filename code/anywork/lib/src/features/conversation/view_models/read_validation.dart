import 'dart:convert';

import 'package:anywork_client/resources.dart';

import '../state/read_progress.dart';

StudioFailure readProtocol(String code) => StudioFailure(
  code: StudioFailureCode.protocol,
  message: 'The conversation read did not match its immutable scope',
  retryable: false,
  correlationId: 'conversation-read-$code',
);

void checkScopeOrigin(ReadScopeIdentity scope, String runtimeEpoch, int incarnation) {
  if (scope.runtimeEpoch != runtimeEpoch || scope.incarnation != incarnation) throw readProtocol('scope-origin');
}

void checkReadPage({
  required ReadScopeIdentity expectedScope,
  required ReadScopeIdentity scope,
  required int requested,
  required int offset,
  required int total,
  required int count,
  required int? next,
  int? expectedTotal,
}) {
  if (scope != expectedScope || requested != offset || total < 0 || offset < 0 ||
      (expectedTotal != null && total != expectedTotal) || offset > total ||
      offset + count > total || (count == 0 && offset < total) ||
      (next != null && (next != offset + count || next <= offset || next >= total)) ||
      (next == null && offset + count != total)) {
    throw readProtocol('page-continuity');
  }
}

Map<int, TextReadProgress> registerReadTexts(
  Map<int, TextReadProgress> current,
  Iterable<ReadText> values,
) {
  final result = Map<int, TextReadProgress>.of(current);
  for (final value in values) {
    if (value is! DeferredReadText) continue;
    final previous = result[value.fieldId];
    if (value.utf8Bytes < 0 ||
        (previous != null && previous.totalUtf8Bytes != value.utf8Bytes)) {
      throw readProtocol('field-identity');
    }
    result.putIfAbsent(value.fieldId, () => TextReadProgress(
      fieldId: value.fieldId, totalUtf8Bytes: value.utf8Bytes));
  }
  return result;
}

TextReadProgress applyReadChunk(TextReadProgress before, TextChunk chunk) {
  final bytes = utf8.encode(chunk.text).length;
  final end = before.loadedUtf8Bytes + bytes;
  if (chunk.fieldId != before.fieldId || chunk.offset != before.loadedUtf8Bytes ||
      end > before.totalUtf8Bytes ||
      (chunk.nextOffset != null && (bytes == 0 || chunk.nextOffset != end || end >= before.totalUtf8Bytes)) ||
      (chunk.nextOffset == null && end != before.totalUtf8Bytes)) {
    throw readProtocol('text-continuity');
  }
  return before.copyWith(text: before.text + chunk.text, loadedUtf8Bytes: end,
    complete: chunk.nextOffset == null, loading: false, error: null);
}
