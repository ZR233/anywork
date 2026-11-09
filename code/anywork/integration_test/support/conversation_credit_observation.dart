import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';

/// A bounded observation of one original FRB handle, not a second UI owner.
/// No reducer, completion body cache, automatic ACK or replacement reader.
final class ConversationCreditObservation {
  ConversationCreditObservation(this.feed, this.evidence)
    : _reader = feed.reader,
      _events = StreamIterator(feed.events) {
    evidence.addAll({
      'source': 'real-frb-timeline-feed',
      'threadId': feed.threadId,
      'subscriptionId': feed.subscriptionId,
      'readerThreadId': _reader.threadId,
      'readerSource': 'original-held-feed',
      'sourceQualified': true,
      'frames': _frames,
      'operations': _operations,
      'closeRequested': false,
      'nativeJoined': false,
      'streamCancelled': false,
    });
  }

  static const deadline = Duration(seconds: 20);
  final TimelineFeed feed;
  final Map<String, Object?> evidence;
  final ConversationReader _reader;
  final StreamIterator<ConversationFrame> _events;
  final _frames = <Map<String, Object?>>[];
  final _operations = <Map<String, Object?>>[];
  List<String> _setItemIds = const [];
  List<String> _setContentItemIds = const [];
  int _acknowledged = 0;
  bool _joined = false;
  bool _cancelled = false;

  Future<void> _next(int sequence) async {
    if (!await _events.moveNext().timeout(deadline)) {
      throw StateError('Credit feed ended before ordinary frame $sequence');
    }
    final frame = _events.current;
    if (frame.threadId != feed.threadId ||
        frame.subscriptionId != feed.subscriptionId ||
        _reader.threadId != feed.threadId) {
      throw StateError('Credit observation changed its original source');
    }
    final event = frame.event;
    if (event case ConversationFailureEvent(:final failure)) throw failure;
    if (event is ConversationClosedEvent) {
      throw StateError('Credit feed closed before ordinary frame $sequence');
    }
    if (sequence > 3 ||
        frame.deliverySequence != sequence ||
        _frames.length != sequence - 1 ||
        _acknowledged != sequence - 1) {
      throw StateError('Credit observation requires one outstanding frame');
    }
    final observation = <String, Object?>{
      'threadId': frame.threadId,
      'subscriptionId': frame.subscriptionId,
      'deliverySequence': frame.deliverySequence,
      'acknowledgedThrough': _acknowledged,
      'outstandingSequence': sequence,
      'outstandingCount': 1,
    };
    switch (event) {
      case ConversationTimelineEvent(:final batch):
        if (batch.presentationVersion != presentationVersion) {
          throw StateError('Credit Timeline has an unsupported version');
        }
        final ids = [for (final block in batch.blocks) block.id];
        final contentIds = [
          for (final block in batch.blocks)
            if (block.body case SingleDisplayBlock(:final completionId?))
              completionId,
        ];
        if (sequence == 1) {
          if (batch.placement != ChatPlacement.set) {
            throw StateError('Credit first frame is not the original Set');
          }
          _setItemIds = List.unmodifiable(ids);
          _setContentItemIds = List.unmodifiable(contentIds);
          evidence['heldSetItemIds'] = _setItemIds;
          evidence['heldSetContentItemIds'] = _setContentItemIds;
        }
        observation.addAll({
          'event': 'timeline',
          'presentationVersion': batch.presentationVersion,
          'placement': batch.placement.name,
          'itemIds': ids,
          'blockCount': batch.blocks.length,
          'throughPos': batch.throughPos,
          'liveRevision': batch.live?.revision,
        });
      case ConversationStateEvent(:final frame):
        if (sequence == 1) {
          throw StateError('Credit first frame is state rather than Set');
        }
        if (frame is ThreadSnapshotFrame &&
            (frame.schemaVersion != 17 || frame.completedHistoryVersion != 1)) {
          throw StateError('Credit State lacks the completed handshake');
        }
        observation.addAll({
          'event': 'state',
          'frameKind': frame.runtimeType.toString(),
        });
      case ConversationChatEvent() || ConversationActivityEvent():
        throw StateError('Timeline credit must not accept atomic GUI events');
      default:
        throw StateError('Credit observation received a nonordinary frame');
    }
    _frames.add(Map.unmodifiable(observation));
    _operations.add({'operation': 'frame', 'deliverySequence': sequence});
    evidence['actualOrdinaryFrameCount'] = _frames.length;
    evidence['acknowledgedThrough'] = _acknowledged;
    evidence['outstandingSequence'] = sequence;
    evidence['outstandingCount'] = 1;
  }

  Future<void> _rejectFuture(int sequence) async {
    await _expectFailure(
      'future-ack',
      () => feed.acknowledge(sequence),
      StudioFailureCode.invalidArgument,
      sequence: sequence,
    );
  }

  Future<void> _expectFailure(
    String operation,
    Future<void> Function() action,
    StudioFailureCode code, {
    int? sequence,
  }) async {
    try {
      await action().timeout(deadline);
    } on StudioFailure catch (failure) {
      if (failure.code != code) rethrow;
      _operations.add({
        'operation': operation,
        'deliverySequence': ?sequence,
        'failureCode': failure.code.name,
        'acknowledgedThrough': _acknowledged,
        'observedFrameCount': _frames.length,
      });
      return;
    }
    throw StateError('Credit $operation unexpectedly succeeded');
  }

  Future<void> holdInitialSet() async {
    await _next(1);
    // The native rejection, not an interval without a Dart callback, proves
    // that sequence 2 has not been sent. Leave sequence 1 unacknowledged.
    await _rejectFuture(2);
  }

  Future<void> queryCompletedText({
    required String blockId,
    required int historyPos,
    required SingleDisplayBlock single,
  }) async {
    final atom = single.atom;
    final itemId = single.completionId;
    final terminal = atom.lifecycle;
    if (_frames.length != 1 ||
        _acknowledged != 0 ||
        atom.kind != ChatAtomKind.text ||
        itemId == null ||
        historyPos <= 0 ||
        (atom.completionSeq ?? 0) <= 0 ||
        terminal is! TerminalChatAtom ||
        terminal.outcome != ChatTerminalOutcome.completed ||
        _setItemIds.contains(blockId) ||
        _setContentItemIds.contains(itemId)) {
      throw StateError('Credit query requires a new, truly completed text');
    }
    final manifest = await _reader
        .listContents(
          itemId: itemId,
          demand: const ReadDemand(maxItems: 32, maxBytes: 64 * 1024),
        )
        .timeout(deadline);
    final body = manifest.entries.singleWhere((entry) => entry.key == 'body');
    final metadata = jsonDecode(utf8.decode(body.payload)) as Map;
    final byteLength = metadata['byteLength'];
    if (byteLength is! int || byteLength <= 0) {
      throw StateError('Completed text manifest has no positive byteLength');
    }
    final target = body.reference.target;
    if (target is! BodyContentTarget ||
        target.owner is! ItemContentOwner ||
        (target.owner as ItemContentOwner).itemId != itemId ||
        target.key != body.key) {
      throw StateError('Manifest reference does not name the completed item');
    }
    // This one explicit test query reads only a bounded prefix, never the
    // hidden full body to fill a viewport.
    final content = await _reader
        .readContent(
          reference: body.reference,
          range: const ContentRange(offset: 0, maxBytes: 64),
        )
        .timeout(deadline);
    final expectedBytes = byteLength < 64 ? byteLength : 64;
    if (content.offset != 0 ||
        content.bytes.isEmpty ||
        content.bytes.length != expectedBytes ||
        content.availableThrough != byteLength ||
        !content.sealed) {
      throw StateError('Original held reader did not return sealed text bytes');
    }
    final query = <String, Object?>{
      'operation': 'query-completed-text',
      'blockId': blockId,
      'historyPos': historyPos,
      'recordId': itemId,
      'contentItemId': itemId,
      'completionSeq': atom.completionSeq,
      'outcome': terminal.outcome.name,
      'absentFromHeldSet': true,
      'readerSource': 'original-held-feed',
      'databaseId': body.reference.databaseId,
      'bodyKey': body.key,
      'byteLength': byteLength,
      'offset': content.offset,
      'maxBytes': 64,
      'actualBytes': content.bytes.length,
      'availableThrough': content.availableThrough,
      'sealed': content.sealed,
      'generation': content.generation,
      'acknowledgedThrough': _acknowledged,
      'outstandingSequence': 1,
    };
    evidence['query'] = query;
    _operations.add(Map.unmodifiable(query));
    // The query must not release the original producer's credit.
    await _rejectFuture(2);
  }

  Future<void> observeSuccessors() async {
    for (final sequence in [1, 2]) {
      // Only acknowledge a frame already received, then await its successor.
      await feed.acknowledge(sequence).timeout(deadline);
      _acknowledged = sequence;
      _operations.add({'operation': 'ack', 'deliverySequence': sequence});
      await _next(sequence + 1);
      await _rejectFuture(sequence + 2);
    }
  }

  Future<void> verifyClosed(String itemId) async {
    await close();
    await _expectFailure('closed-reader-query', () async {
      await _reader.listContents(
        itemId: itemId,
        demand: const ReadDemand(maxItems: 32, maxBytes: 64 * 1024),
      );
    }, StudioFailureCode.cancelled);
    await _expectFailure(
      'closed-feed-ack',
      () => feed.acknowledge(3),
      StudioFailureCode.cancelled,
      sequence: 3,
    );
    evidence['closedAdmissionsVerified'] = true;
  }

  Future<void> close() async {
    Object? failure;
    StackTrace? failureStack;
    void recordFailure(String operation, Object error, StackTrace stack) {
      failure ??= error;
      failureStack ??= stack;
      final failures = evidence.putIfAbsent(
        'closeFailures',
        () => <Map<String, Object?>>[],
      ) as List<Map<String, Object?>>;
      failures.add({
        'operation': operation,
        'error': error.toString(),
        'stack': stack.toString(),
      });
    }

    try {
      if (!_joined) {
        evidence['unacknowledgedSequenceAtClose'] =
            _frames.length > _acknowledged ? _frames.length : null;
      }
      feed.requestClose();
      evidence['closeRequested'] = true;
      evidence['sourceQualified'] = false;
      if (!_joined) {
        // A cancelled Dart subscription is not evidence of native join.
        await feed.close().timeout(deadline);
        _joined = true;
        evidence['nativeJoined'] = true;
        evidence['outstandingSequence'] = null;
        evidence['outstandingCount'] = 0;
        _operations.add({'operation': 'native-close-joined'});
      }
    } catch (error, stack) {
      recordFailure('native-close-join', error, stack);
    }
    try {
      if (!_cancelled) {
        await _events.cancel().timeout(deadline);
        _cancelled = true;
        evidence['streamCancelled'] = true;
      }
    } catch (error, stack) {
      recordFailure('stream-cancel', error, stack);
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
  }
}
