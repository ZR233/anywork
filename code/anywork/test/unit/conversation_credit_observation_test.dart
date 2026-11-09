import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/conversation_credit_observation.dart';

const _targetId = 'text-b-block';
const _targetPos = 5;
const _body = ContentRef(
  databaseId: 'db',
  target: BodyContentTarget(
    owner: ItemContentOwner(itemId: 'text-b-completion'),
    key: 'body',
  ),
);
final _bytes = List<int>.filled(54, 120);

SingleDisplayBlock _single(String id) => SingleDisplayBlock(
  completionId: id == _targetId ? 'text-b-completion' : '$id-completion',
  atom: ChatAtom(
    id: '$id-atom',
    completionItemId: id == _targetId ? 'text-b-completion' : '$id-completion',
    completionSeq: 8,
    source: const ForegroundTurnChatSource(turnId: 'turn'),
    sourceOrder: 1,
    kind: ChatAtomKind.text,
    delivery: ChatDeliveryKind.foreground,
    lifecycle: const TerminalChatAtom(
      started: null,
      ended: null,
      outcome: ChatTerminalOutcome.completed,
    ),
    turnId: 'turn',
    contents: id == _targetId
        ? [const ChatAtomContent(role: ChatContentRole.body, reference: _body)]
        : [],
  ),
);

DisplayBlock _block(String id, int pos) =>
    DisplayBlock(id: id, historyPos: pos, body: _single(id));

LiveDisplayWindow _live(int through, {bool showTarget = false}) =>
    LiveDisplayWindow(
      revision: through,
      historyThrough: through,
      executionPresent: true,
      blocks: [
        if (showTarget)
          LiveDisplayBlock(
            id: _targetId,
            blockOrder: 1,
            body: _single(_targetId),
            closing: false,
          ),
      ],
    );

ConversationTimelineEvent _append(
  List<DisplayBlock> blocks, {
  int from = 3,
  int through = 5,
  bool finalCut = true,
  bool showTarget = false,
}) => ConversationTimelineEvent(
  batch: TimelineBatch(
    presentationVersion: 1,
    placement: ChatPlacement.append,
    blocks: blocks,
    fromPos: from,
    throughPos: through,
    live: finalCut ? _live(through, showTarget: showTarget) : null,
  ),
);

final class _Harness {
  _Harness(
    List<ConversationEvent> successors, {
    String frameThread = 'thread',
    String frameSubscription = 'subscription',
    String readerThread = 'thread',
    int sequenceOffset = 0,
    bool acceptFutureAck = false,
  }) {
    feed = _Feed(
      successors,
      frameThread: frameThread,
      frameSubscription: frameSubscription,
      readerThread: readerThread,
      sequenceOffset: sequenceOffset,
      acceptFutureAck: acceptFutureAck,
    );
    observation = ConversationCreditObservation(feed, evidence);
    addTearDown(() async {
      await observation.close();
      await feed.dispose();
    });
  }

  final evidence = <String, Object?>{};
  late final _Feed feed;
  late final ConversationCreditObservation observation;

  Future<void> holdAndQuery() async {
    await observation.holdInitialSet();
    await observation.queryCompletedText(
      blockId: _targetId,
      historyPos: _targetPos,
      single: _single(_targetId),
    );
    expect(feed.acks, isEmpty);
    expect(feed.originalReader.manifestCalls, 1);
    expect(feed.originalReader.contentCalls, 1);
    expect((evidence['query'] as Map)['actualBytes'], 54);
  }

  Future<void> observe() =>
      observation.observeSuccessors(blockId: _targetId, historyPos: _targetPos);
}

void main() {
  for (final split in [false, true]) {
    test(
      '${split ? 'split Appends' : 'coalesced Append'} deliver the exact target and retain final credit',
      () async {
        final h = _Harness([
          if (split)
            _append([_block('work-b', 4)], through: 4, finalCut: false),
          _append([
            if (!split) _block('work-b', 4),
            _block(_targetId, _targetPos),
          ], from: split ? 4 : 3),
        ]);
        await h.holdAndQuery();
        await h.observe();
        final last = split ? 3 : 2;
        expect(h.feed.acks, split ? [1, 2] : [1]);
        expect(h.evidence['actualOrdinaryFrameCount'], last);
        expect(h.evidence['acknowledgedThrough'], last - 1);
        expect(h.evidence['outstandingSequence'], last);
        expect(h.evidence['outstandingCount'], 1);
        expect(h.evidence['targetDelivery'], {
          'blockId': _targetId,
          'historyPos': _targetPos,
          'deliverySequence': last,
          'throughPos': 5,
          'actualOrdinaryFrameCount': last,
          'acknowledgedThrough': last - 1,
          'outstandingSequence': last,
        });
        final frames = h.evidence['frames'] as List;
        expect(
          frames.every((frame) => (frame as Map)['outstandingCount'] == 1),
          isTrue,
        );
        expect(h.feed.futureAcks, split ? [2, 2, 3, 4] : [2, 2, 3]);
        await h.observation.verifyClosed('text-b-completion');
        expect(h.feed.heldAtClose, last);
        expect(h.feed.acks, split ? [1, 2] : [1]);
        expect(h.feed.closedAcks, [last]);
        expect(h.evidence['unacknowledgedSequenceAtClose'], last);
        expect(h.evidence['nativeJoined'], isTrue);
        expect(h.evidence['streamCancelled'], isTrue);
        expect(h.evidence['closedAdmissionsVerified'], isTrue);
      },
    );
  }

  test(
    'pure live is not target delivery; a fourth frame can deliver it',
    () async {
      final h = _Harness([
        _append([], through: 3, showTarget: true),
        _append([_block('work-b', 4)], through: 4, finalCut: false),
        _append([_block(_targetId, 5)], from: 4),
      ]);
      await h.holdAndQuery();
      await h.observe();
      expect(h.feed.acks, [1, 2, 3]);
      expect((h.evidence['targetDelivery'] as Map)['deliverySequence'], 4);
      final frames = h.evidence['frames'] as List;
      expect((frames[1] as Map)['blocks'], isEmpty);
      expect((frames[1] as Map)['fromPos'], 3);
      expect((frames[1] as Map)['throughPos'], 3);
      expect(h.evidence['outstandingSequence'], 4);
    },
  );

  final invalid = <String, (ConversationEvent, String)>{
    'wrong target ID at its position': (
      _append([_block('work-b', 4), _block('not-text-b', 5)]),
      'passed the target position without its block',
    ),
    'target ID at a wrong position': (
      _append([_block(_targetId, 4)], through: 4),
      'target block arrived at the wrong history position',
    ),
    'discontinuous history cut': (
      _append([_block(_targetId, 5)], from: 4),
      'placement or history cut is discontinuous',
    ),
    'duplicate block IDs': (
      _append([_block('duplicate', 4), _block('duplicate', 5)]),
      'blocks are duplicated or out of order',
    ),
    'missing block before the target': (
      _append([_block(_targetId, 5)]),
      'history positions contain a gap',
    ),
    'history cut advances beyond delivered blocks': (
      _append([_block('work-b', 4)]),
      'history cut includes undelivered blocks',
    ),
    'out-of-order positions': (
      _append([_block(_targetId, 5), _block('work-b', 4)]),
      'blocks are duplicated or out of order',
    ),
    'replayed held Set identity': (
      _append([_block('seed-1', 4), _block(_targetId, 5)]),
      'blocks are duplicated or out of order',
    ),
    'State is not a Timeline successor': (
      const ConversationStateEvent(
        frame: ThreadResyncRequiredFrame(threadId: 'thread', dropped: 1),
      ),
      'requires Timeline-only frames',
    ),
    'Activity is not a Timeline successor': (
      ConversationActivityEvent(
        snapshot: ActivitySnapshot(
          revision: 1,
          completedThrough: 5,
          executionPresent: true,
          entries: [],
        ),
      ),
      'requires Timeline-only frames',
    ),
    'Closed before target': (
      const ConversationClosedEvent(),
      'closed before ordinary frame 2',
    ),
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key}', () async {
      final h = _Harness([entry.value.$1]);
      await h.holdAndQuery();
      await expectLater(
        h.observe(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(entry.value.$2),
          ),
        ),
      );
      expect(h.evidence, isNot(contains('targetDelivery')));
      expect(h.feed.acks, [1]);
    });
  }

  for (final source in ['thread', 'subscription', 'reader']) {
    test('rejects a changed original $source identity', () async {
      final h = _Harness(
        [],
        frameThread: source == 'thread' ? 'other' : 'thread',
        frameSubscription: source == 'subscription' ? 'other' : 'subscription',
        readerThread: source == 'reader' ? 'other' : 'thread',
      );
      await expectLater(
        h.observation.holdInitialSet(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Credit observation changed its original source',
          ),
        ),
      );
      expect(h.feed.acks, isEmpty);
    });
  }

  test(
    'failure including a producer budget error propagates unchanged',
    () async {
      const failure = StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Timeline frame exceeds the encoded-byte demand',
        retryable: false,
        correlationId: 'budget',
      );
      final h = _Harness([const ConversationFailureEvent(failure: failure)]);
      await h.holdAndQuery();
      await expectLater(h.observe(), throwsA(same(failure)));
      expect(h.evidence, isNot(contains('targetDelivery')));
    },
  );

  test('rejects nonconsecutive deliverySequence', () async {
    final h = _Harness([
      _append([_block(_targetId, 5)]),
    ], sequenceOffset: 1);
    await h.holdAndQuery();
    await expectLater(
      h.observe(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Credit observation requires one outstanding frame',
        ),
      ),
    );
  });

  test('an accepted future ACK fails the real helper credit proof', () async {
    final h = _Harness([], acceptFutureAck: true);
    await expectLater(
      h.observation.holdInitialSet(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Credit future-ack unexpectedly succeeded',
        ),
      ),
    );
    expect(h.feed.acks, isEmpty);
  });
}

StudioFailure _failure(StudioFailureCode code) => StudioFailure(
  code: code,
  message: code.name,
  retryable: false,
  correlationId: 'fixture',
);

// Only an event/credit environment. It never groups, reduces, or validates
// Timeline cuts; the real observation helper is responsible for those checks.
final class _Feed extends Fake implements TimelineFeed {
  _Feed(
    List<ConversationEvent> successors, {
    required this.frameThread,
    required this.frameSubscription,
    required String readerThread,
    required this.sequenceOffset,
    required this.acceptFutureAck,
  }) : originalReader = _Reader(readerThread) {
    _script = [
      ConversationTimelineEvent(
        batch: TimelineBatch(
          presentationVersion: 1,
          placement: ChatPlacement.set,
          blocks: [for (var i = 1; i <= 3; i++) _block('seed-$i', i)],
          throughPos: 3,
          live: _live(3),
        ),
      ),
      ...successors,
    ];
    _events = StreamController<ConversationFrame>(onListen: _sendNext);
  }
  final String frameThread;
  final String frameSubscription;
  final int sequenceOffset;
  final bool acceptFutureAck;
  final _Reader originalReader;
  late final List<ConversationEvent> _script;
  late final StreamController<ConversationFrame> _events;
  final acks = <int>[];
  final futureAcks = <int>[];
  final closedAcks = <int>[];
  int _sent = 0;
  int? _outstanding;
  int? heldAtClose;
  bool _closed = false;

  @override
  String get threadId => 'thread';
  @override
  String get subscriptionId => 'subscription';
  @override
  ConversationReader get reader => originalReader;
  @override
  Stream<ConversationFrame> get events => _events.stream;

  void _sendNext() {
    if (_sent == _script.length) return;
    final index = _sent++;
    _outstanding = _sent;
    _events.add(
      ConversationFrame(
        threadId: frameThread,
        subscriptionId: frameSubscription,
        deliverySequence: _sent + (index == 0 ? 0 : sequenceOffset),
        event: _script[index],
      ),
    );
  }

  @override
  Future<void> acknowledge(int sequence) async {
    if (_closed) {
      closedAcks.add(sequence);
      throw _failure(StudioFailureCode.cancelled);
    }
    if (sequence != _outstanding) {
      futureAcks.add(sequence);
      if (acceptFutureAck) return;
      throw _failure(StudioFailureCode.invalidArgument);
    }
    acks.add(sequence);
    _outstanding = null;
    _sendNext();
  }

  @override
  void requestClose() {
    if (!_closed) heldAtClose = _outstanding;
    _closed = true;
    originalReader.closed = true;
  }

  @override
  Future<void> close() async => requestClose();

  Future<void> dispose() => _events.close();
}

final class _Reader extends Fake implements ConversationReader {
  _Reader(this.threadId);
  @override
  final String threadId;
  bool closed = false;
  int manifestCalls = 0;
  int contentCalls = 0;

  @override
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  }) async {
    if (closed) throw _failure(StudioFailureCode.cancelled);
    manifestCalls++;
    expect(itemId, 'text-b-completion');
    expect(demand.maxItems, 32);
    expect(demand.maxBytes, 64 * 1024);
    return ContentManifestPage(
      entries: [
        ContentManifestEntry(
          key: 'body',
          payload: utf8.encode(jsonEncode({'byteLength': _bytes.length})),
          reference: _body,
        ),
      ],
    );
  }

  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) async {
    if (closed) throw _failure(StudioFailureCode.cancelled);
    contentCalls++;
    expect(reference, _body);
    expect(range.offset, 0);
    expect(range.maxBytes, 64);
    return ContentWindow(
      offset: 0,
      bytes: _bytes,
      generation: 'body-generation',
      availableThrough: _bytes.length,
      sealed: true,
    );
  }
}
