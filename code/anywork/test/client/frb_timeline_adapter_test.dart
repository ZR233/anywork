import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/handlers/chat.dart' as wire;
import 'package:anywork/src/rust/api/studio/handlers/history/timeline_reader.dart'
    as history_wire;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as dto;
import 'package:anywork/src/rust/api/studio/types/chat/descriptor.dart'
    as descriptor;
import 'package:anywork/src/rust/api/studio/types/error.dart' as err;
import 'package:anywork/src/rust/api/studio/types/thread_stream/item.dart'
    as leaf;
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FRB completion DTO maps epoch, append sequence, unknown seal and source facts', () async {
    final native = _GeneratedFeed();
    final feed = FrbConversationFeed(native);
    final received = Completer<ConversationFrame>();
    feed.events.listen((frame) => received.complete(frame));
    native.send(
      dto.BridgeConversationEvent.contentBaseline(
        baseline: _baseline([
          _item(id: 'unknown-seal', appendSeq: 7, sealedAt: null),
          _item(
            id: 'sealed',
            appendSeq: 8,
            sealedAt: 1700000001,
            source: const dto.BridgeTimelineItemSource.modelRecovery(
              attemptId: 'attempt:中文',
              notice: dto.BridgeTimelineRecoveryNotice.retry,
            ),
          ),
        ]),
      ),
    );
    final frame = await received.future;
    final baseline = (frame.event as ConversationBaselineEvent).baseline;
    expect(frame.threadId, 'thread-A');
    expect(frame.subscriptionId, 'sub-1');
    expect(baseline.timelineEpoch, 'epoch-A');
    expect(baseline.completedCursor.timelineEpoch, 'epoch-A');
    expect(baseline.completedCursor.appendSeq, 8);
    expect(baseline.items.map((item) => item.header.appendSeq), [7, 8]);
    expect(baseline.items.first.header.sealedAt, isNull);
    expect(baseline.items.last.header.sealedAt, 1700000001);
    expect(
      (baseline.items.last.source as ConversationRecoverySource).notice,
      ConversationRecoveryNotice.retry,
    );
    expect(
      baseline.items.last.fieldFor(const ThreadTextFieldView())!.text,
      '中文 🐱',
    );
    expect(native.acks, isEmpty, reason: 'adapter 不替消费方 ACK');
    await feed.acknowledge(frame.deliverySequence);
    expect(native.acks, [BigInt.one]);
    await feed.close();
  });

  test(
    'completion batch maps sequence and item without legacy patch reduction',
    () async {
      final native = _GeneratedFeed();
      final feed = FrbConversationFeed(native);
      final iterator = StreamIterator(feed.events);
      native.send(
        dto.BridgeConversationEvent.contentUpdate(
          update: dto.BridgeTimelineUpdate.batch(
            subscriptionId: 'sub-1',
            timelineEpoch: 'epoch-A',
            fromSeq: BigInt.from(4),
            throughSeq: BigInt.from(5),
            items: [_item(id: 'next', appendSeq: 5)],
          ),
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      final batch =
          (iterator.current.event as ConversationUpdateEvent).update
              as ConversationBatch;
      expect(batch.timelineEpoch, 'epoch-A');
      expect((batch.fromSeq, batch.throughSeq), (4, 5));
      expect(batch.items.single.header.appendSeq, 5);
      expect(native.acks, isEmpty);
      await feed.close();
      await iterator.cancel();
    },
  );

  test(
    'history reader adapts page and detail independently of feed creation',
    () async {
      final native = _GeneratedReader();
      final reader = FrbConversationHistoryReader(native);
      final page = await reader.page(
        before: const ConversationQueryCursor('opaque-page'),
        limit: 17,
      );
      expect(native.pageRequests.single, (before: 'opaque-page', limit: 17));
      expect(page.timelineEpoch, 'epoch-A');
      expect(page.items.single.header.appendSeq, 9);
      final detail = await reader.readDetail(
        itemId: 'item-9',
        query: const ConversationDetailQuery(
          timelineEpoch: 'epoch-A',
          field: ThreadThinkingSummaryFieldView(2),
          continuation: ConversationQueryCursor('opaque-detail'),
          maxBytes: 16,
        ),
      );
      expect(native.detailRequests.single.$1, 'item-9');
      expect(native.detailRequests.single.$2.timelineEpoch, 'epoch-A');
      expect(native.detailRequests.single.$2.continuation, 'opaque-detail');
      expect(
        native.detailRequests.single.$2.field,
        const dto.BridgeContentField.thinkingSummary(chunkIndex: 2),
      );
      expect(detail.timelineEpoch, 'epoch-A');
      expect(detail.text, 'ab');
      expect(detail.totalBytes, 6);
      expect(detail.continuation, const ConversationQueryCursor('next'));
      await reader.close();
    },
  );

  test(
    'typed reader errors retain classification and correlation identity',
    () async {
      final native = _GeneratedReader()
        ..pageFailure = const err.BridgeError(
          code: err.BridgeErrorCode.storage,
          message: 'read failed',
          retryable: true,
          correlationId: 'history-page',
        );
      final reader = FrbConversationHistoryReader(native);
      await expectLater(
        reader.page(),
        throwsA(
          isA<StudioFailure>()
              .having(
                (failure) => failure.code,
                'code',
                StudioFailureCode.storage,
              )
              .having((failure) => failure.retryable, 'retryable', isTrue)
              .having(
                (failure) => failure.correlationId,
                'correlationId',
                'history-page',
              ),
        ),
      );
      await reader.close();
    },
  );
}

dto.BridgeTimelineBaseline _baseline(List<dto.BridgeTimelineItem> items) =>
    dto.BridgeTimelineBaseline(
      subscriptionId: 'sub-1',
      timelineEpoch: 'epoch-A',
      items: items,
      before: 'opaque-before',
      hasOlder: true,
      completedCursor: dto.BridgeTimelineCompletionCursor(
        timelineEpoch: 'epoch-A',
        appendSeq: BigInt.from(8),
      ),
    );

dto.BridgeTimelineItem _item({
  String id = 'item',
  required int appendSeq,
  int? sealedAt,
  dto.BridgeTimelineItemSource source =
      const dto.BridgeTimelineItemSource.content(),
}) => dto.BridgeTimelineItem(
  header: descriptor.BridgeTimelineItemHeader(
    id: id,
    threadId: 'thread-A',
    turnId: 'turn-A',
    appendSeq: BigInt.from(appendSeq),
    sourceEffectSeq: BigInt.from(21),
    sealedAt: sealedAt,
  ),
  descriptor: const descriptor.BridgeTimelineDescriptor.text(
    descriptor.BridgeTimelineTextDescriptor(
      channel: leaf.BridgeThreadTextChannel.final_,
      attachments: [],
      outcome: descriptor.BridgeTimelineContentOutcome.completed(
        completedAt: 1700000001,
      ),
    ),
  ),
  source: source,
  fields: [
    dto.BridgeTimelineFieldPreview(
      field: dto.BridgeContentField.text(),
      text: '中文 🐱',
      totalBytes: BigInt.from(10),
    ),
  ],
);

/// Only the generated FRB seam is stubbed; adapter conversion and ownership are production code.
final class _GeneratedFeed implements wire.BridgeConversationFeed {
  final _frames = StreamController<dto.BridgeConversationFrame>();
  final acks = <BigInt>[];
  int _sequence = 0;
  @override
  String threadId() => 'thread-A';
  @override
  String subscriptionId() => 'sub-1';
  @override
  Stream<dto.BridgeConversationFrame> events() => _frames.stream;
  void send(dto.BridgeConversationEvent event) => _frames.add(
    dto.BridgeConversationFrame(
      threadId: 'thread-A',
      subscriptionId: 'sub-1',
      deliverySequence: BigInt.from(++_sequence),
      event: event,
    ),
  );
  @override
  void acknowledge({
    required String subscriptionId,
    required BigInt deliverySequence,
  }) => acks.add(deliverySequence);
  @override
  void requestClose() {}
  @override
  Future<void> close() async {}
  @override
  void dispose() {
    unawaited(_frames.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GeneratedReader implements history_wire.BridgeTimelineReader {
  final pageRequests = <({String? before, int? limit})>[];
  final detailRequests = <(String, dto.BridgeTimelineDetailQuery)>[];
  Object? pageFailure;
  @override
  String threadId() => 'thread-A';
  @override
  String timelineEpoch() => 'epoch-A';
  @override
  Future<dto.BridgeTimelinePage> page({String? before, int? limit}) async {
    pageRequests.add((before: before, limit: limit));
    if (pageFailure case final error?) throw error;
    return dto.BridgeTimelinePage(
      timelineEpoch: 'epoch-A',
      items: [_item(id: 'item-9', appendSeq: 9)],
      before: 'older',
      hasOlder: true,
    );
  }

  @override
  Future<dto.BridgeTimelineDetailChunk> readDetail({
    required String itemId,
    required dto.BridgeTimelineDetailQuery query,
  }) async {
    detailRequests.add((itemId, query));
    return dto.BridgeTimelineDetailChunk(
      timelineEpoch: query.timelineEpoch,
      itemId: itemId,
      field: query.field,
      text: 'ab',
      totalBytes: BigInt.from(6),
      continuation: 'next',
    );
  }

  @override
  void requestClose() {}
  @override
  Future<void> close() async {}
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
