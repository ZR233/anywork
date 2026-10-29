import 'dart:async';
import 'dart:convert';

import '../../../conversation_ports.dart';
import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';
import '../domain/content_lifecycle.dart';
import '../domain/conversation_repository.dart';
import 'completion_budget.dart';

/// One independently retired read scope; it never borrows a feed or its credit.
final class ConversationReadScope implements ConversationQueryScope {
  ConversationReadScope({
    required this.threadId,
    required this.timelineEpoch,
    required this.generation,
    required ConversationTransport transport,
    required ResourceBudget budget,
  }) : _transport = transport,
       _budget = budget;
  final String threadId;
  final String timelineEpoch;
  final int generation;
  final ConversationTransport _transport;
  final ResourceBudget _budget;
  final Set<Future<void>> _pending = {};
  ConversationHistoryReader? _reader;
  Future<ConversationHistoryReader>? _opening;
  Future<void>? _closingReader;
  ResourcePermit? _readerPermit;
  Object? _closeError;
  Object? _identityError;
  bool _readerClosed = false;
  bool _retired = false;
  int _sequence = 0;
  bool get isActive => !_retired;
  int get pendingQueries => _pending.length;
  bool get isSettled => _retired && _pending.isEmpty && _readerPermit == null;

  Future<ConversationPage> page({ConversationQueryCursor? before, int? limit}) {
    final resolved = limit ?? conversationPageDefaultLimit;
    if (resolved < 1 || resolved > conversationPageMaxLimit)
      return Future.error(ArgumentError.value(limit, 'limit'));
    return _run((reader) async {
      final page = await reader.page(before: before, limit: resolved);
      if (page.threadId != threadId ||
          page.timelineEpoch != timelineEpoch ||
          page.items.length > resolved ||
          page.hasOlder != (page.before != null))
        throw const ConversationContinuityError(
          'page identity or bounds mismatch',
        );
      validateCompletionBudget(page.items);
      var last = -1;
      final ids = <String>{};
      for (final item in page.items) {
        if (item.header.threadId != threadId ||
            item.header.appendSeq <= last ||
            !ids.add(item.id))
          throw const ConversationContinuityError(
            'page ordering or identity mismatch',
          );
        last = item.header.appendSeq;
      }
      return page;
    });
  }

  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) {
    if (query.timelineEpoch != timelineEpoch)
      return Future.error(
        const ConversationContinuityError('query epoch mismatch'),
      );
    final max = query.maxBytes ?? 65536;
    if (max < conversationDetailMinBytes || max > conversationDetailMaxBytes)
      return Future.error(ArgumentError.value(query.maxBytes, 'maxBytes'));
    return _run((reader) async {
      final result = await reader.readDetail(itemId: itemId, query: query);
      final bytes = utf8.encode(result.text).length;
      if (result.threadId != threadId ||
          result.timelineEpoch != timelineEpoch ||
          result.itemId != itemId ||
          result.field != query.field ||
          bytes > max ||
          bytes > result.totalBytes ||
          (bytes == 0 && result.continuation != null) ||
          (result.continuation != null &&
              result.continuation == query.continuation))
        throw const ConversationContinuityError(
          'detail identity or bounds mismatch',
        );
      return result;
    });
  }

  Future<ConversationHistoryReader> _ensureReader() {
    final existing = _opening;
    if (existing != null) return existing;
    final permit = _budget.acquire(
      ResourceKind.pendingOperation,
      owner: 'timeline-reader:$threadId:$generation',
      phase: ResourcePhase.opening,
    );
    _readerPermit = permit;
    final completer = Completer<ConversationHistoryReader>();
    _opening = completer.future;
    completer.complete(
      Future<ConversationHistoryReader>.sync(
        () => _transport.openHistoryReader(threadId),
      ).then(
        (reader) {
          _reader = reader;
          permit.mark(_retired ? ResourcePhase.retiring : ResourcePhase.active);
          if (_retired) {
            _requestReaderClose();
            throw const StaleConversationScope();
          }
          if (reader.threadId != threadId ||
              reader.timelineEpoch != timelineEpoch) {
            _retired = true;
            _requestReaderClose();
            final error = ConversationContinuityError(
              'reader identity mismatch',
            );
            _identityError = error;
            throw error;
          }
          return reader;
        },
        onError: (Object error, StackTrace stack) {
          permit.release();
          _readerPermit = null;
          Error.throwWithStackTrace(error, stack);
        },
      ),
    );
    return completer.future;
  }

  Future<T> _run<T>(Future<T> Function(ConversationHistoryReader) operation) {
    if (_retired) return Future.error(const StaleConversationScope());
    final permit = _budget.acquire(
      ResourceKind.pendingOperation,
      owner: 'timeline-query:$threadId:$generation:${++_sequence}',
    );
    final completer = Completer<T>();
    late final Future<void> joined;
    joined = completer.future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() {
          _pending.remove(joined);
          permit.release();
        });
    _pending.add(joined);
    completer.complete(
      Future<T>.sync(() async {
        final reader = await _ensureReader();
        if (_retired) throw const StaleConversationScope();
        return operation(reader);
      }).then(
        (value) {
          if (_retired) throw const StaleConversationScope();
          return value;
        },
        onError: (Object error, StackTrace stack) {
          if (_retired && !identical(error, _identityError)) {
            throw const StaleConversationScope();
          }
          Error.throwWithStackTrace(error, stack);
        },
      ),
    );
    return completer.future;
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _requestReaderClose();
  }

  void _requestReaderClose() {
    final reader = _reader;
    if (reader == null || _readerClosed) return;
    _readerPermit?.mark(ResourcePhase.retiring);
    try {
      reader.requestClose();
    } catch (error) {
      _closeError = error;
    }
  }

  Future<void> _joinReader() async {
    final opening = _opening;
    if (opening == null) return;
    try {
      await opening;
    } catch (_) {
      // Open failure has already been delivered to the query; a late reader
      // remains in _reader and must still be joined below.
    }
    final reader = _reader;
    if (reader == null || _readerClosed) return;
    _requestReaderClose();
    final close = _closingReader ??= Future<void>.sync(reader.close);
    try {
      await close;
      _readerClosed = true;
      _closeError = null;
      _readerPermit?.release();
      _readerPermit = null;
      _reader = null;
    } catch (error) {
      _closeError = error;
      _readerPermit?.mark(ResourcePhase.unresolved);
      _closingReader = null;
    }
  }

  Future<CloseReport> close({DateTime? deadline}) async {
    retire();
    final readerJoin = _joinReader();
    final pending = [..._pending, readerJoin];
    if (pending.isNotEmpty) {
      if (deadline == null) {
        await Future.wait(pending);
      } else {
        final remaining = deadline.difference(DateTime.now());
        if (remaining > Duration.zero) {
          try {
            await Future.wait(pending).timeout(remaining);
          } on TimeoutException {
            // The registered native futures and permits remain owned until settlement.
          }
        }
      }
    }
    return CloseReport(
      unresolved: [
        for (var i = 0; i < _pending.length; i++)
          UnresolvedResource(
            owner: 'timeline-query:$threadId:$generation',
            attemptId: AttemptId(generation),
            reason: StateError('query still in flight'),
          ),
        if (_readerPermit != null)
          UnresolvedResource(
            owner: 'timeline-reader:$threadId:$generation',
            attemptId: AttemptId(generation),
            reason:
                _closeError ?? StateError('reader still opening or closing'),
          ),
      ],
    );
  }
}
