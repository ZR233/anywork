import 'dart:convert';

import '../../models/current_state_field.dart';
import '../../models/chat_models.dart';
import 'conversation_read_scope.dart';

/// Reads one deferred State field through an already-owned Current scope.
///
/// No bytes or decoded values are retained here. Each read uses bounded
/// ContentWindow calls and validates the exact field generation/length.
extension CurrentStateFieldReader on CurrentReadScope {
  static const _windowBytes = 64 * 1024;

  Future<Object?> readStateField(CurrentStateField field) => switch (field) {
    BodyCurrentStateField() => readStateBody(field),
    CollectionCurrentStateField() => throw const FormatException(
      'State collection requires explicit pageStateCollection',
    ),
  };

  Future<Object?> readStateBody(BodyCurrentStateField field) async {
    if (field.byteLength < 0) {
      throw const FormatException('Negative CurrentStateBody byte length');
    }
    final bytes = <int>[];
    while (bytes.length < field.byteLength) {
      final remaining = field.byteLength - bytes.length;
      final window = await readBody(
        reference: field.reference,
        range: ContentRange(
          offset: bytes.length,
          maxBytes: remaining < _windowBytes ? remaining : _windowBytes,
        ),
      );
      if (window.offset != bytes.length ||
          window.generation != field.reference.generation ||
          window.availableThrough != field.byteLength ||
          window.bytes.isEmpty) {
        throw const ConversationStateFieldDiscontinuity();
      }
      bytes.addAll(window.bytes);
      if (window.sealed && bytes.length < field.byteLength) {
        throw const ConversationStateFieldDiscontinuity();
      }
    }
    return jsonDecode(utf8.decode(bytes));
  }

  Future<CurrentCollectionPage> pageStateCollection(
    CollectionCurrentStateField field, {
    String? continuation,
    required ReadDemand demand,
  }) => pageCollection(
    reference: field.reference,
    continuation: continuation,
    demand: demand,
  );
}

final class ConversationStateFieldDiscontinuity implements Exception {
  const ConversationStateFieldDiscontinuity();

  @override
  String toString() =>
      'Deferred Current State field is discontinuous or changed generation';
}
