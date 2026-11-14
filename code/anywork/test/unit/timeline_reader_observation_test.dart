import 'dart:convert';

import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/timeline_reader_observation.dart';
import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';
import '../support/mapped_conversation_feed.dart';

const _demand = ReadDemand(maxItems: 32, maxBytes: 65536);
void main() {
  for (final split in [false, true]) {
    test(
      'cursor observation preserves the held cut and reads completed bytes before ${split ? 'split' : 'coalesced'} delivery',
      () async {
        final h = await _Harness.open();
        await h.observe.holdInitialSet();
        await h.query();
        expect(h.peer.acceptedCursors, isEmpty);
        if (split) {
          h.peer.emitTimeline(
            displayBatch(
              [displayWork('work-b', 4)],
              placement: ChatPlacement.append,
              from: 3,
              through: 4,
            ),
          );
        }
        h.peer.emitTimeline(
          displayBatch(
            [
              if (!split) displayWork('work-b', 4),
              displaySingle(h.target, blockOrder: 5),
            ],
            placement: ChatPlacement.append,
            from: split ? 4 : 3,
            through: 5,
            live: TailSnapshot(
              revision: 2,
              layoutRevision: 2,
              readyFrontier: 5,
              executionPresent: false,
              currentWorkId: null,
              blocks: [],
            ),
          ),
        );
        await h.observe.observeSuccessors(
          blockId: h.target.recordId,
          blockOrder: 5,
        );
        expect((h.evidence['query'] as Map)['actualBytes'], 54);
        expect(
          (h.evidence['targetDelivery'] as Map)['blockId'],
          h.target.recordId,
        );
        expect(h.evidence['replayedSameCut'], isTrue);
        expect(h.peer.acceptedCursors, hasLength(split ? 2 : 1));
        await h.observe.close();
        expect(h.evidence['nativeJoined'], isTrue);
      },
    );
  }
  test('observation rejects a prefix that passes the actual queried target without its identity', () async {
    final h = await _Harness.open();
    await h.observe.holdInitialSet();
    await h.query();
    h.peer.emitTimeline(
      displayBatch(
        [displayWork('different', 5)],
        placement: ChatPlacement.append,
        from: 3,
        through: 5,
      ),
    );
    await expectLater(
      h.observe.observeSuccessors(blockId: h.target.recordId, blockOrder: 5),
      throwsStateError,
    );
    expect(h.evidence['targetDelivery'], isNull);
  });
}

final class _Harness {
  _Harness(this.api, this.peer, this.target) {
    observe = TimelineReaderObservation(peer, evidence);
    addTearDown(() async {
      await observe.close();
      expect(await api.cancelDartSubscriptions(budgetMs: 1000), isEmpty);
    });
  }
  final DemoStudioTransport api;
  final ScriptedTimelineReader peer;
  final CompletedEntry target;
  final evidence = <String, Object?>{};
  late final TimelineReaderObservation observe;
  static Future<_Harness> open() async {
    final api = DemoStudioTransport();
    await api.readBootstrap();
    final original = await api.openTimelineReader(
      'thread-main',
      presentationVersion: 6,
      readerProtocolVersion: 1,
      demand: _demand,
    );
    final first = await original.next(after: original.metadata.initialCursor);
    final peer = ScriptedTimelineReader(
      queries: MappedTimelineReader(
        original,
        reader: _ContentFixture(original.reader),
      ),
      initial: () => first,
    );
    final target = chatMessage(
      'queried-target',
      body: 'x' * 54,
      completionSeq: 100,
    );
    api.seedTimelineItems('thread-main', [target]);
    return _Harness(api, peer, target);
  }

  Future<void> query() => observe.queryCompletedText(
    blockId: target.recordId,
    blockOrder: 5,
    single: displaySingle(target, blockOrder: 5).body as SingleDisplayBlock,
  );
}

/// Explicit external body fixture; it does not interpret or apply timeline responses.
final class _ContentFixture extends Fake implements ConversationReader {
  _ContentFixture(this.original);
  final ConversationReader original;
  @override
  String get threadId => original.threadId;
  @override
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  }) async => ContentManifestPage(
    entries: [
      ContentManifestEntry(
        key: 'body',
        payload: utf8.encode(jsonEncode({'byteLength': 54})),
        reference: ContentRef(
          databaseId: 'fixture',
          target: BodyContentTarget(
            owner: ItemContentOwner(itemId: itemId),
            key: 'body',
          ),
        ),
      ),
    ],
  );
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) async => ContentWindow(
    offset: range.offset,
    bytes: List.filled(54, 120),
    generation: 'fixed',
    availableThrough: 54,
    sealed: true,
  );
  @override
  void requestClose() => original.requestClose();
  @override
  Future<void> close() => original.close();
}
