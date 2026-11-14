import 'display_record_observation.dart';

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
  final _historyIds = <String>{};
  int? _through;
  int? _liveRevision;
  int _acknowledged = 0;
  bool _joined = false;
  bool _cancelled = false;

  Future<TimelineBatch> _next(
    int sequence, {
    Duration timeout = deadline,
  }) async {
    if (!await _events.moveNext().timeout(timeout)) {
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
    if (frame.deliverySequence != sequence ||
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
    if (event is! ConversationTimelineEvent) {
      throw StateError('Timeline credit requires Timeline-only frames');
    }
    final batch = event.batch;
    if (batch.presentationVersion != presentationVersion) {
      throw StateError('Credit Timeline has an unsupported version');
    }
    final initial = sequence == 1;
    final validPlacement = initial
        ? batch.placement == ChatPlacement.set &&
              batch.fromOrder == null &&
              batch.live != null
        : batch.placement == ChatPlacement.append &&
              batch.before == null &&
              batch.fromOrder == _through &&
              (batch.throughOrder > _through! ||
                  (batch.throughOrder == _through &&
                      batch.blocks.isEmpty &&
                      batch.live != null));
    if (!validPlacement || batch.throughOrder < 0) {
      throw StateError(
        'Credit Timeline placement or history cut is discontinuous',
      );
    }
    final ids = <String>{};
    var previous = batch.fromOrder ?? 0;
    var hasGap = false;
    for (final block in batch.blocks) {
      if (block.id.isEmpty ||
          !ids.add(block.id) ||
          _historyIds.contains(block.id) ||
          block.blockOrder <= previous ||
          block.blockOrder > batch.throughOrder) {
        throw StateError(
          'Credit Timeline blocks are duplicated or out of order',
        );
      }
      if (!initial && block.blockOrder != previous + 1) {
        hasGap = true;
      }
      previous = block.blockOrder;
    }
    if (hasGap) {
      throw StateError('Credit Timeline history positions contain a gap');
    }
    if (!initial && previous != batch.throughOrder) {
      throw StateError(
        'Credit Timeline history cut includes undelivered blocks',
      );
    }
    if (batch.live case final live?) {
      if (live.readyFrontier != batch.throughOrder ||
          live.revision < (_liveRevision ?? 0)) {
        throw StateError('Credit Timeline live cut is discontinuous');
      }
      var order = 0;
      final cutIds = {...ids};
      for (final block in live.blocks) {
        if (block.id.isEmpty ||
            !cutIds.add(block.id) ||
            _historyIds.contains(block.id) ||
            block.blockOrder <= order) {
          throw StateError(
            'Credit Timeline live blocks are duplicated or out of order',
          );
        }
        order = block.blockOrder;
      }
      _liveRevision = live.revision;
    }
    _historyIds.addAll(ids);
    _through = batch.throughOrder;
    if (initial) {
      _setItemIds = List.unmodifiable(ids);
      _setContentItemIds = List.unmodifiable([
        for (final block in batch.blocks)
          if (block.body case SingleDisplayBlock(
            record: DisplayRecord(
              contentSource: CompletedOriginal(:final completionId),
            ),
          ))
            completionId,
      ]);
      evidence['heldSetItemIds'] = _setItemIds;
      evidence['heldSetContentItemIds'] = _setContentItemIds;
    }
    observation.addAll({
      'event': 'timeline',
      'presentationVersion': batch.presentationVersion,
      'placement': batch.placement.name,
      'itemIds': ids.toList(),
      'blocks': [
        for (final block in batch.blocks)
          {'blockId': block.id, 'blockOrder': block.blockOrder},
      ],
      'blockCount': batch.blocks.length,
      'fromOrder': batch.fromOrder,
      'throughOrder': batch.throughOrder,
      'liveRevision': batch.live?.revision,
    });
    _frames.add(Map.unmodifiable(observation));
    _operations.add({'operation': 'frame', 'deliverySequence': sequence});
    evidence['actualOrdinaryFrameCount'] = _frames.length;
    evidence['acknowledgedThrough'] = _acknowledged;
    evidence['outstandingSequence'] = sequence;
    evidence['outstandingCount'] = 1;
    return batch;
  }

  Future<void> _rejectFuture(
    int sequence, {
    Duration timeout = deadline,
  }) async {
    await _expectFailure(
      'future-ack',
      () => feed.acknowledge(sequence),
      StudioFailureCode.invalidArgument,
      sequence: sequence,
      timeout: timeout,
    );
  }

  Future<void> _expectFailure(
    String operation,
    Future<void> Function() action,
    StudioFailureCode code, {
    int? sequence,
    Duration timeout = deadline,
  }) async {
    try {
      await action().timeout(timeout);
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
    required int blockOrder,
    required SingleDisplayBlock single,
  }) async {
    final atom = single.record.atom;
    final itemId = completedOriginalId(single.record);
    final terminal = atom.lifecycle;
    if (_frames.length != 1 ||
        _acknowledged != 0 ||
        atom.kind != ChatAtomKind.text ||
        itemId == null ||
        blockOrder <= 0 ||
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
      'blockOrder': blockOrder,
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

  Future<void> observeSuccessors({
    required String blockId,
    required int blockOrder,
  }) async {
    final query = evidence['query'];
    if (_frames.length != 1 ||
        _acknowledged != 0 ||
        query is! Map ||
        query['blockId'] != blockId ||
        query['blockOrder'] != blockOrder ||
        blockOrder <= _through!) {
      throw StateError(
        'Credit target must be the original queried completed text',
      );
    }
    final clock = Stopwatch()..start();
    Duration remaining() {
      final left = deadline - clock.elapsed;
      if (left <= Duration.zero) {
        throw TimeoutException(
          'Credit target delivery exceeded its budget',
          deadline,
        );
      }
      return left;
    }

    while (true) {
      final sequence = _frames.length;
      // Only acknowledge a frame already received, then await its successor.
      await feed.acknowledge(sequence).timeout(remaining());
      _acknowledged = sequence;
      evidence['acknowledgedThrough'] = sequence;
      evidence['outstandingSequence'] = null;
      evidence['outstandingCount'] = 0;
      _operations.add({'operation': 'ack', 'deliverySequence': sequence});
      final batch = await _next(sequence + 1, timeout: remaining());
      await _rejectFuture(sequence + 2, timeout: remaining());
      final target = batch.blocks
          .where((block) => block.id == blockId)
          .singleOrNull;
      if (target != null) {
        if (target.blockOrder != blockOrder) {
          throw StateError(
            'Credit target block arrived at the wrong history position',
          );
        }
        evidence['targetDelivery'] = {
          'blockId': blockId,
          'blockOrder': blockOrder,
          'deliverySequence': sequence + 1,
          'throughOrder': batch.throughOrder,
          'actualOrdinaryFrameCount': _frames.length,
          'acknowledgedThrough': _acknowledged,
          'outstandingSequence': sequence + 1,
        };
        // Retain this actually received frame unacknowledged for close/join.
        return;
      }
      if (batch.throughOrder >= blockOrder) {
        throw StateError(
          'Credit Timeline passed the target position without its block',
        );
      }
    }
  }

  Future<void> verifyClosed(String itemId) async {
    final heldSequence = _frames.length;
    await close();
    await _expectFailure('closed-reader-query', () async {
      await _reader.listContents(
        itemId: itemId,
        demand: const ReadDemand(maxItems: 32, maxBytes: 64 * 1024),
      );
    }, StudioFailureCode.cancelled);
    await _expectFailure(
      'closed-feed-ack',
      () => feed.acknowledge(heldSequence),
      StudioFailureCode.cancelled,
      sequence: heldSequence,
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
