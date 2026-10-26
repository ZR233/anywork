import 'dart:convert';
import 'dart:math' as math;

import '../../../resources.dart';
import '../../../resources_ports.dart' show ResourceBudgetExceeded;

/// One bounded statistics list page. A page is complete material for the
/// pinned list, not a UI window: the caller reads to `total` before publishing.
typedef StatisticsListPage<T> = ({
  int listId,
  int offset,
  int total,
  List<T> items,
  int? nextOffset,
});

/// The page size used for every complete statistics read. It keeps the native
/// per-page bound; it is not a cap on the number of materialized rows.
const statisticsPageLimit = 32;

Future<String> readStatisticsText(
  ReadText value,
  Future<TextChunk> Function(int, {int offset, int maxBytes}) read,
) async {
  if (value case InlineReadText(:final text)) {
    if (utf8.encode(text).length > 4096)
      throw statisticsProtocol('An inline statistics field exceeds its bound.');
    return text;
  }
  final deferred = value as DeferredReadText;
  if (deferred.utf8Bytes < 0)
    throw statisticsProtocol('A statistics field has an invalid length.');
  final output = StringBuffer();
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
      throw statisticsProtocol(
        'A statistics text chunk does not match its pinned field.',
      );
    output.write(chunk.text);
    offset = end;
  }
  return output.toString();
}

/// Reads every page of one pinned list to its declared total. A repeated,
/// reordered, shrunk or overlong page is a protocol failure, never a partial
/// material.
Future<List<T>> readStatisticsList<T>(
  TypedListRef reference,
  Future<StatisticsListPage<T>> Function(int) read,
) async {
  if (reference.total < 0)
    throw statisticsProtocol('A statistics list has an invalid length.');
  final output = <T>[];
  var offset = 0;
  while (offset < reference.total) {
    final page = await read(offset);
    final end = offset + page.items.length;
    if (page.listId != reference.listId ||
        page.offset != offset ||
        page.total != reference.total ||
        page.items.isEmpty ||
        page.items.length > statisticsPageLimit ||
        end < offset ||
        end > reference.total ||
        page.nextOffset != (end == reference.total ? null : end))
      throw statisticsProtocol(
        'A statistics list page does not match its pinned field.',
      );
    output.addAll(page.items);
    offset = end;
  }
  return List.unmodifiable(output);
}

StudioFailure statisticsProtocol(String message) => StudioFailure(
  code: StudioFailureCode.protocol,
  message: message,
  retryable: false,
  correlationId: 'statistics',
);

StudioFailure statisticsFailure(Object error) => switch (error) {
  StudioFailure() => error,
  ResourceBudgetExceeded() => error.failure,
  _ => const StudioFailure(
    code: StudioFailureCode.internal,
    message: 'The statistics material could not be read.',
    retryable: false,
    correlationId: 'statistics',
  ),
};

/// A superseded attempt/read is retryable evidence, not a clean result.
const statisticsSuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The original statistics attempt is no longer current.',
  retryable: true,
  correlationId: 'statistics',
);

StudioFailure statisticsNoVisibleDemand() => const StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'Statistics synchronisation requires a visible demand.',
  retryable: false,
  correlationId: 'statistics',
);

/// The original attempt ended without closing its resources; only an explicit
/// retry may replace it.
StudioFailure statisticsUnresolvedCleanup(String message) => StudioFailure(
  code: StudioFailureCode.busy,
  message: message,
  retryable: true,
  correlationId: 'statistics',
);

/// One lane exhausted its bounded automatic resubscriptions. The attempt keeps
/// the last complete snapshot, reports this typed failure and leaves the rest to
/// an explicit retry.
StudioFailure statisticsResyncExhausted(String side) => StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The statistics $side feed exhausted its bounded resubscriptions.',
  retryable: true,
  correlationId: 'statistics',
);
