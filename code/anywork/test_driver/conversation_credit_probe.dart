import 'dart:async';
import 'dart:convert';

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
  List<String>? _baselineIds;
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
      if (frame.event case ConversationChatEvent(:final batch)) {
        if (_baselineIds == null && batch.placement != ChatPlacement.set) {
          _failure = StateError('first Chat was not Set');
        } else if (_baselineIds != null &&
            batch.placement != ChatPlacement.append) {
          _failure = StateError('feed emitted a non-Append after Set');
        }
        _baselineIds ??= [for (final message in batch.messages) message.id];
        _frames.add({
          'deliverySequence': frame.deliverySequence,
          'event': 'chat',
          'placement': batch.placement.name,
          'itemIds': [for (final message in batch.messages) message.id],
        });
      } else {
        _frames.add({
          'deliverySequence': frame.deliverySequence,
          'event': frame.event.runtimeType.toString(),
        });
      }
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
    if (_acknowledged != 0 || _baselineIds == null) {
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

  /// Reads one newly completed, GUI-observed item through the original reader
  /// while this same feed has no credit. No second feed can hide a credit lock.
  Future<Map<String, Object?>> query({required String itemId}) async {
    if (_acknowledged != 0 || _frames.length != 2) {
      throw StateError('query evidence requires the original two-frame hold');
    }
    if (_baselineIds!.contains(itemId)) {
      throw StateError('query target already existed in the held Set');
    }
    final manifest = await feed.reader.listContents(
      itemId: itemId,
      demand: const ReadDemand(maxItems: 32, maxBytes: 64 * 1024),
    );
    final body = manifest.entries.singleWhere((entry) => entry.key == 'body');
    final metadata = jsonDecode(utf8.decode(body.payload)) as Map;
    final totalBytes = metadata['byteLength'];
    if (totalBytes is! int || totalBytes <= 0) {
      throw StateError('completed text manifest has no positive byteLength');
    }
    final chunk = await feed.reader.readContent(
      reference: body.reference,
      range: const ContentRange(offset: 0, maxBytes: 64),
    );
    if (chunk.offset != 0 ||
        chunk.bytes.isEmpty ||
        chunk.availableThrough != totalBytes ||
        !chunk.sealed) {
      throw StateError('original reader did not read the completed text');
    }
    await _rejectFuture(3);
    return {
      ...snapshot(),
      'queryItemId': itemId,
      'detailItemId': itemId,
      'detailTotalBytes': totalBytes,
      'detailReadBytes': chunk.bytes.length,
      'detailGeneration': chunk.generation,
      'readerSource': 'original-held-feed',
    };
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
    'baselineItemIds': _baselineIds,
    'acknowledged': _acknowledged,
    'futureAckRejections': List<int>.of(_rejections),
    'done': _done,
    'joined': _joined,
    'failure': _failure?.runtimeType.toString(),
  };
}
