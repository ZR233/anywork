import 'dart:convert';
import 'dart:math' as math;

import '../../../resources.dart';
import '../../../resources_ports.dart' show ResourceBudgetExceeded;

/// Field readers are pure queries over an already owned, immutable Config pin.
/// The repository owns cancellation/join; these helpers never open a handle.
Future<String> readConfigurationText(
  ReadText value,
  Future<TextChunk> Function(int, {int offset, int maxBytes}) read,
) async {
  if (value case InlineReadText(:final text)) {
    if (utf8.encode(text).length > 4096)
      throw configurationProtocol(
        'An inline configuration field exceeds its limit.',
      );
    return text;
  }
  final deferred = value as DeferredReadText;
  if (deferred.utf8Bytes < 0)
    throw configurationProtocol(
      'A deferred configuration field has an invalid length.',
    );
  final text = StringBuffer();
  var offset = 0;
  while (offset < deferred.utf8Bytes) {
    final limit = math.min(65536, deferred.utf8Bytes - offset);
    final chunk = await read(deferred.fieldId, offset: offset, maxBytes: limit);
    final bytes = utf8.encode(chunk.text).length;
    final end = offset + bytes;
    if (chunk.fieldId != deferred.fieldId ||
        chunk.offset != offset ||
        bytes == 0 ||
        bytes > limit ||
        end < offset ||
        end > deferred.utf8Bytes ||
        chunk.nextOffset != (end == deferred.utf8Bytes ? null : end))
      throw configurationProtocol(
        'A configuration text chunk does not match its pinned field.',
      );
    text.write(chunk.text);
    offset = end;
  }
  return text.toString();
}

typedef ConfigurationListPage<T> = ({
  int listId,
  int offset,
  int total,
  List<T> items,
  int? nextOffset,
});

Future<List<T>> readConfigurationList<T>(
  TypedListRef reference,
  Future<ConfigurationListPage<T>> Function(int) read,
) async {
  if (reference.total < 0)
    throw configurationProtocol('A configuration list has an invalid length.');
  final items = <T>[];
  var offset = 0;
  while (offset < reference.total) {
    final page = await read(offset);
    final end = offset + page.items.length;
    if (page.listId != reference.listId ||
        page.offset != offset ||
        page.total != reference.total ||
        page.items.isEmpty ||
        page.items.length > 32 ||
        end < offset ||
        end > reference.total ||
        page.nextOffset != (end == reference.total ? null : end))
      throw configurationProtocol(
        'A configuration list page does not match its pinned field.',
      );
    items.addAll(page.items);
    offset = end;
  }
  return List.unmodifiable(items);
}

StudioFailure configurationProtocol(String message) => StudioFailure(
  code: StudioFailureCode.protocol,
  message: message,
  retryable: false,
  correlationId: 'configuration',
);

StudioFailure configurationFailure(Object error) => switch (error) {
  StudioFailure() => error,
  ResourceBudgetExceeded() => error.failure,
  _ => const StudioFailure(
    code: StudioFailureCode.internal,
    message: 'The configuration operation failed.',
    retryable: false,
    correlationId: 'configuration',
  ),
};

const configurationCancelled = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The Configuration repository is sealed.',
  retryable: false,
  correlationId: 'configuration',
);
const configurationSuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The original configuration read version is no longer current.',
  retryable: true,
  correlationId: 'configuration',
);
