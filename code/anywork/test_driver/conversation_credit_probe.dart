import 'dart:async';

import 'package:anywork_client/studio_client.dart';

/// Driver-only observation of one real transport feed. No completion bodies,
/// replacement transport or automatic ACKs are retained here.
final class ConversationCreditProbe {
  ConversationCreditProbe(this.feed) {
    _subscription = feed.events.listen(
      _receive,
      onError: (Object error, StackTrace stack) {
        _failure = error;
        _notify();
      },
      onDone: () {
        _done = true;
        _notify();
      },
    );
  }

  final ConversationFeed feed;
  late final StreamSubscription<ConversationFrame> _subscription;
  final _frames = <Map<String, Object?>>[];
  final _rejections = <int>[];
  Completer<void> _changed = Completer<void>();
  Object? _failure;
  String? _baselineEpoch;
  int? _baselineThrough;
  int _acknowledged = 0;
  bool _done = false;
  bool _joined = false;

  void _notify() {
    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }

  void _receive(ConversationFrame frame) {
    if (frame.threadId != feed.threadId ||
        frame.subscriptionId != feed.subscriptionId) {
      _failure = StateError('credit probe received a different source');
    } else if (frame.event case ConversationFailureEvent(:final failure)) {
      _failure = failure;
    } else if (frame.event is ConversationClosedEvent) {
      _done = true;
    } else if (frame.deliverySequence != _frames.length + 1 ||
        _frames.length >= 3) {
      _failure = StateError('credit probe exceeded its actual sent prefix');
    } else {
      if (frame.event case ConversationBaselineEvent(:final baseline)) {
        _baselineEpoch = baseline.timelineEpoch;
        _baselineThrough = baseline.completedCursor.appendSeq;
      }
      _frames.add({
        'deliverySequence': frame.deliverySequence,
        'event': frame.event.runtimeType.toString(),
      });
    }
    _notify();
  }

  Future<void> _received(int count) async {
    while (_frames.length < count) {
      if (_failure case final failure?) throw failure;
      if (_done) throw StateError('credit probe closed before frame $count');
      await _changed.future.timeout(const Duration(seconds: 20));
    }
    if (_failure case final failure?) throw failure;
  }

  Future<void> _rejectFuture(int sequence) async {
    try {
      await feed.acknowledge(sequence);
    } on StudioFailure catch (failure) {
      if (failure.code != StudioFailureCode.invalidArgument) rethrow;
      _rejections.add(sequence);
      return;
    }
    throw StateError('native feed accepted the future ACK $sequence');
  }

  /// A rejected future ACK proves the native sent prefix at that call, unlike
  /// merely waiting for an interval without seeing a third Dart callback.
  Future<Map<String, Object?>> holdTwo() async {
    await _received(2);
    await _rejectFuture(3);
    if (_acknowledged != 0 ||
        _baselineEpoch == null ||
        _baselineThrough == null) {
      throw StateError('credit probe did not hold its initial real baseline');
    }
    return snapshot();
  }

  Future<Map<String, Object?>> acknowledgeOne() async {
    if (_acknowledged != 0 || _frames.length != 2) {
      throw StateError(
        'credit probe ACK requires exactly two unacknowledged frames',
      );
    }
    await feed.acknowledge(1);
    _acknowledged = 1;
    await _received(3);
    await _rejectFuture(4);
    return snapshot();
  }

  /// Opens an independent real query capability while this feed has no credit.
  /// The caller first causes a new real completion through the normal GUI.
  Future<Map<String, Object?>> query(ConversationTransport transport) async {
    if (_acknowledged != 0 || _frames.length != 2) {
      throw StateError('query evidence requires the original two-frame hold');
    }
    final reader = await transport.openHistoryReader(feed.threadId);
    try {
      final page = await reader.page(limit: 100);
      if (reader.timelineEpoch != _baselineEpoch ||
          page.timelineEpoch != _baselineEpoch ||
          page.items.isEmpty ||
          page.items.last.header.appendSeq <= _baselineThrough!) {
        throw StateError('independent page did not observe a new completion');
      }
      final item = page.items.lastWhere(
        (item) =>
            item.header.appendSeq > _baselineThrough! &&
            item.fields.any(
              (field) =>
                  field.field is ThreadTextFieldView && field.totalBytes > 0,
            ),
      );
      final chunk = await reader.readDetail(
        itemId: item.header.id,
        query: ConversationDetailQuery(
          timelineEpoch: page.timelineEpoch,
          field: const ThreadTextFieldView(),
          maxBytes: 64,
        ),
      );
      if (chunk.timelineEpoch != page.timelineEpoch ||
          chunk.itemId != item.header.id ||
          chunk.text.isEmpty) {
        throw StateError('independent detail did not read the completed text');
      }
      // Recheck native credit after both queries. This still must not ACK data.
      await _rejectFuture(3);
      return {
        ...snapshot(),
        'queryEpoch': page.timelineEpoch,
        'queryHead': page.items.last.header.appendSeq,
        'detailItemId': chunk.itemId,
        'detailAppendSeq': item.header.appendSeq,
        'detailTotalBytes': chunk.totalBytes,
        'detailReadCharacters': chunk.text.length,
      };
    } finally {
      reader.requestClose();
      await reader.close();
    }
  }

  Future<Map<String, Object?>> close() async {
    if (!_joined) {
      feed.requestClose();
      // Join the retryable native close before Dart memoizes subscription cancel.
      await feed.close();
      await _subscription.cancel();
      _joined = true;
    }
    return snapshot();
  }

  Map<String, Object?> snapshot() => {
    'source': 'real-frb-conversation-feed',
    'threadId': feed.threadId,
    'subscriptionId': feed.subscriptionId,
    'frames': List<Map<String, Object?>>.of(_frames),
    'baselineEpoch': _baselineEpoch,
    'baselineThrough': _baselineThrough,
    'acknowledged': _acknowledged,
    'futureAckRejections': List<int>.of(_rejections),
    'done': _done,
    'joined': _joined,
    'failure': _failure?.runtimeType.toString(),
  };
}
