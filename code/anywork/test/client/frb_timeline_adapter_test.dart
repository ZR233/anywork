import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/handlers/chat.dart' as wire;
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
  test('typed first frame preserves identity, source, fields, save and terminal facts without ACK', () async {
    final native = _GeneratedFeed();
    final feed = FrbConversationFeed(native);
    final received = <ConversationFrame>[];
    final ready = Completer<void>();
    feed.events.listen((frame) {
      received.add(frame);
      ready.complete();
    });
    native.send(
      dto.BridgeConversationEvent.contentBaseline(
        baseline: _baseline(
          source: const dto.BridgeTimelineItemSource.modelRecovery(
            attemptId: 'attempt:中文',
            notice: dto.BridgeTimelineRecoveryNotice.retry,
          ),
        ),
      ),
    );
    await ready.future;
    final frame = received.single;
    expect(frame.threadId, 'thread-A');
    expect(frame.subscriptionId, 'sub-1');
    expect(frame.deliverySequence, 1);
    final baseline = (frame.event as ConversationBaselineEvent).baseline;
    final item = baseline.items.single;
    expect(baseline.version, 41);
    expect(baseline.before, 'opaque');
    expect(baseline.hasOlder, isTrue);
    expect(item.header.id, 'item');
    expect(item.header.threadId, 'thread-A');
    expect(item.header.turnId, 'turn');
    expect(item.header.ordinal, 1000000007);
    expect(item.header.createdAt.millisecondsSinceEpoch, 1700000000000);
    expect(item.revision, 8);
    expect(item.saved, isFalse);
    expect(item.lifecycle, ConversationLifecycle.terminal);
    expect((item.source as ConversationRecoverySource).attemptId, 'attempt:中文');
    expect(item.fieldFor(const ThreadTextFieldView())!.text, '中文 🐱\nfirst');
    expect(item.fields.single.totalBytes, 4096);
    expect(native.acks, isEmpty);
    await feed.acknowledge(frame.deliverySequence);
    expect(native.acks.single, (subscriptionId: 'sub-1', sequence: BigInt.one));
    await feed.close();
  });

  test('typed patches, equal field identities and resync are not reduced by the adapter', () async {
    final native = _GeneratedFeed();
    final feed = FrbConversationFeed(native);
    final iterator = StreamIterator(feed.events);
    native.send(
      dto.BridgeConversationEvent.contentUpdate(
        update: dto.BridgeTimelineUpdate.patch(
          subscriptionId: 'sub-1',
          from: BigInt.from(41),
          to: BigInt.from(42),
          priority: dto.BridgeTimelinePriority.immediate,
          changes: [
            dto.BridgeTimelineChange.updateItem(
              itemId: 'item',
              expectedRevision: BigInt.from(8),
              revision: BigInt.from(9),
              saved: true,
              lifecycle: dto.BridgeTimelineLifecycle.streaming,
              header: _item().header,
              descriptor: _item().descriptor,
              fields: [
                dto.BridgeTimelineFieldUpdate(
                  field: const dto.BridgeContentField.toolUserInput(
                    questionIndex: 3,
                    part_: dto.BridgeThreadUserInputFieldPart.optionDescription(
                      optionIndex: 2,
                    ),
                  ),
                  change: const dto.BridgeTimelineFieldChange.append(
                    text: '\nsecond',
                  ),
                  totalBytes: BigInt.from(90),
                  previewBytes: BigInt.from(14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(await iterator.moveNext(), isTrue);
    final patch =
        (iterator.current.event as ConversationUpdateEvent).update
            as ConversationPatch;
    expect(patch.from, 41);
    expect(patch.to, 42);
    expect(patch.priority, ConversationPriority.immediate);
    final change = patch.changes.single as ConversationUpdateItem;
    expect(change.expectedRevision, 8);
    expect(change.revision, 9);
    expect(change.header!.turnId, 'turn');
    expect(change.descriptor, isA<ConversationTextDescriptor>());
    final field = change.fields.single;
    expect(
      field.field,
      const ThreadToolUserInputFieldView(
        questionIndex: 3,
        part: ThreadUserInputOptionDescriptionFieldPartView(2),
      ),
    );
    expect((field.change as AppendThreadFieldChangeView).text, '\nsecond');
    expect(field.totalBytes, 90);
    expect(field.previewBytes, 14);
    native.send(
      dto.BridgeConversationEvent.contentUpdate(
        update: dto.BridgeTimelineUpdate.resync(
          subscriptionId: 'sub-1',
          reason: dto.BridgeTimelineResyncReason.lagging,
          baseline: _baseline(),
        ),
      ),
    );
    expect(await iterator.moveNext(), isTrue);
    final resync =
        (iterator.current.event as ConversationUpdateEvent).update
            as ConversationResync;
    expect(resync.subscriptionId, 'sub-1');
    expect(resync.baseline.subscriptionId, 'sub-1');
    expect(resync.reason, ConversationResyncReason.lagging);
    expect(native.acks, isEmpty);
    await feed.close();
    await iterator.cancel();
  });

  test('page and detail preserve opaque tokens and parameterized field without starting events', () async {
    final native = _GeneratedFeed();
    final feed = FrbConversationFeed(native);
    final page = await feed.page(before: 'opaque-before', limit: 17);
    expect(native.pageRequests.single, (before: 'opaque-before', limit: 17));
    expect(page.items.single.id, 'item');
    final chunk = await feed.readDetail(
      itemId: 'item',
      query: const ConversationDetailQuery(
        field: ThreadThinkingSummaryFieldView(4),
        revision: 8,
        continuation: 'opaque-detail',
        maxBytes: 16,
      ),
    );
    expect(
      native.detailRequests.single.query.field,
      const dto.BridgeContentField.thinkingSummary(chunkIndex: 4),
    );
    expect(native.detailRequests.single.query.revision, BigInt.from(8));
    expect(chunk.text, 'ab');
    expect(chunk.totalBytes, 6);
    expect(chunk.continuation, 'next');
    expect(native.eventCalls, 0);
    expect(native.acks, isEmpty);
    await feed.close();
  });

  test('overflow in outer sequence, baseline version or nested ordinal closes without acknowledging', () async {
    for (final where in ['sequence', 'version', 'ordinal']) {
      final native = _GeneratedFeed();
      final feed = FrbConversationFeed(native);
      final failed = Completer<Object>();
      feed.events.listen((_) {}, onError: (Object e) => failed.complete(e));
      final huge = BigInt.one << 100;
      native.send(
        dto.BridgeConversationEvent.contentBaseline(
          baseline: _baseline(
            version: where == 'version' ? huge : null,
            ordinal: where == 'ordinal' ? huge : null,
          ),
        ),
        sequence: where == 'sequence' ? huge : null,
      );
      expect(
        await failed.future,
        isA<StudioFailure>().having(
          (f) => f.code,
          'code',
          StudioFailureCode.overloaded,
        ),
      );
      expect(native.requestCloseCalls, 1);
      expect(native.acks, isEmpty);
      await feed.close();
      expect(native.disposeCalls, 1);
    }
  });

  test(
    'invalid queries reject before native calls rather than reporting overload',
    () async {
      final native = _GeneratedFeed();
      final feed = FrbConversationFeed(native);
      final invalid = throwsA(
        isA<StudioFailure>().having(
          (f) => f.code,
          'code',
          StudioFailureCode.invalidArgument,
        ),
      );
      await expectLater(feed.page(limit: 0), invalid);
      await expectLater(
        feed.readDetail(
          itemId: 'item',
          query: const ConversationDetailQuery(
            field: ThreadTextFieldView(),
            revision: -1,
          ),
        ),
        invalid,
      );
      await expectLater(
        feed.readDetail(
          itemId: 'item',
          query: const ConversationDetailQuery(
            field: ThreadThinkingContentFieldView(-1),
            revision: 1,
          ),
        ),
        invalid,
      );
      expect(native.pageRequests, isEmpty);
      expect(native.detailRequests, isEmpty);
      await feed.close();
    },
  );

  test('Dart listener cancellation synchronously requests native close then waits its real join', () async {
    final native = _GeneratedFeed()..closeBarrier = Completer<void>();
    final feed = FrbConversationFeed(native);
    final subscription = feed.events.listen((_) {});
    final cancelled = subscription.cancel();
    expect(native.requestCloseCalls, 1);
    expect(native.closeCalls, 1);
    expect(native.disposeCalls, 0);
    var settled = false;
    unawaited(cancelled.then((_) => settled = true));
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    native.closeBarrier!.complete();
    await cancelled;
    expect(
      native.calls.indexOf('close'),
      lessThan(native.calls.indexOf('dispose')),
    );
    expect(native.disposeCalls, 1);
  });

  test('close before events never attaches a native sink and refuses later calls with Cancelled', () async {
    final native = _GeneratedFeed();
    final feed = FrbConversationFeed(native);
    feed.requestClose();
    await feed.close();
    await feed.close();
    expect(native.eventCalls, 0);
    expect(native.requestCloseCalls, 1);
    expect(native.closeCalls, 1);
    expect(native.disposeCalls, 1);
    expect(
      () => feed.events,
      throwsA(
        isA<StudioFailure>().having(
          (f) => f.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    await expectLater(
      feed.page(),
      throwsA(
        isA<StudioFailure>().having(
          (f) => f.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
  });

  test(
    'failed native close retains opaque owner and permits supervisor retry',
    () async {
      final native = _GeneratedFeed()
        ..closeFailure = const err.BridgeError(
          code: err.BridgeErrorCode.storage,
          message: 'join failed',
          retryable: true,
          correlationId: 'join',
        );
      final feed = FrbConversationFeed(native);
      await expectLater(
        feed.close(),
        throwsA(
          isA<StudioFailure>().having(
            (f) => f.code,
            'code',
            StudioFailureCode.storage,
          ),
        ),
      );
      expect(native.disposeCalls, 0);
      expect(native.closeCalls, 1);
      native.closeFailure = null;
      await feed.close();
      expect(native.closeCalls, 2);
      expect(native.disposeCalls, 1);
      expect(native.requestCloseCalls, 1);
    },
  );

  test('in-flight page and detail after close report typed cancellation rather than late success', () async {
    final native = _GeneratedFeed()..readBarrier = Completer<void>();
    final feed = FrbConversationFeed(native);
    final failure = throwsA(
      isA<StudioFailure>().having(
        (f) => f.code,
        'code',
        StudioFailureCode.cancelled,
      ),
    );
    final page = expectLater(feed.page(), failure);
    final detail = expectLater(
      feed.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          field: ThreadTextFieldView(),
          revision: 8,
        ),
      ),
      failure,
    );
    feed.requestClose();
    native.readBarrier!.complete();
    await Future.wait([page, detail]);
    await feed.close();
  });

  test('native Failure and Closed remain terminal typed events, not data or EOF null', () async {
    for (final terminal in [
      const dto.BridgeConversationEvent.failure(
        error: err.BridgeError(
          code: err.BridgeErrorCode.storage,
          message: 'failed',
          retryable: true,
          correlationId: 'failure',
        ),
      ),
      const dto.BridgeConversationEvent.closed(),
    ]) {
      final native = _GeneratedFeed();
      final feed = FrbConversationFeed(native);
      final iterator = StreamIterator(feed.events);
      native.send(terminal, sequence: BigInt.zero);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.deliverySequence, 0);
      if (terminal is dto.BridgeConversationEvent_Failure) {
        final error =
            (iterator.current.event as ConversationFailureEvent).failure;
        expect(error.code, StudioFailureCode.storage);
        expect(error.correlationId, 'failure');
        expect(error.retryable, isTrue);
      } else {
        expect(iterator.current.event, isA<ConversationClosedEvent>());
      }
      expect(native.acks, isEmpty);
      await feed.close();
      await iterator.cancel();
    }
  });

  test(
    'second consumer is refused without attaching a second native stream',
    () async {
      final native = _GeneratedFeed();
      final feed = FrbConversationFeed(native);
      final subscription = feed.events.listen((_) {});
      expect(
        () => feed.events,
        throwsA(
          isA<StudioFailure>().having(
            (f) => f.code,
            'code',
            StudioFailureCode.conflict,
          ),
        ),
      );
      expect(native.eventCalls, 1);
      await feed.close();
      await subscription.cancel();
    },
  );

  test('typed tool descriptor preserves wait, optional option count, secret and redacted answer counts', () async {
    final native = _GeneratedFeed();
    final feed = FrbConversationFeed(native);
    final iterator = StreamIterator(feed.events);
    native.send(
      dto.BridgeConversationEvent.contentBaseline(
        baseline: _baseline(tool: true),
      ),
    );
    expect(await iterator.moveNext(), isTrue);
    final tool =
        ((iterator.current.event as ConversationBaselineEvent)
                .baseline
                .items
                .single
                .descriptor
            as ConversationToolDescriptor);
    expect(tool.invocation.toolCallId, 'call');
    expect(tool.state, isA<ConversationToolRunning>());
    expect(tool.userInput!.questions[0].optionCount, isNull);
    expect(tool.userInput!.questions[1].optionCount, 0);
    expect(tool.userInput!.questions.first.isSecret, isTrue);
    final answer =
        (tool.userInput!.state as ConversationUserInputResolved).answers.single;
    expect(answer.questionId, 'secret');
    expect(answer.answerCount, 1);
    expect(answer.redacted, isTrue);
    final wait = tool.wait!;
    expect(wait.state, ThreadWaitStateView.waiting);
    expect(wait.messagesReady, isNull);
    final intent = wait.intent as ThreadWaitEventsIntentView;
    expect(intent.timeoutMs, 60000);
    expect(intent.targets.single.taskId, 'task:exec-1');
    expect(intent.targets.single.summaryTruncated, isTrue);
    await feed.close();
    await iterator.cancel();
  });
  test('原生页和详情错误保留typed分类、重试与correlationId，不泄漏BridgeError', () async {
    final native = _GeneratedFeed()
      ..pageFailure = const err.BridgeError(
        code: err.BridgeErrorCode.cancelled,
        message: 'cancelled',
        retryable: false,
        correlationId: 'page',
      )
      ..detailFailure = const err.BridgeError(
        code: err.BridgeErrorCode.storage,
        message: 'storage',
        retryable: true,
        correlationId: 'detail',
      );
    final feed = FrbConversationFeed(native);
    await expectLater(
      feed.page(),
      throwsA(
        isA<StudioFailure>()
            .having((f) => f.code, 'code', StudioFailureCode.cancelled)
            .having((f) => f.correlationId, 'correlationId', 'page'),
      ),
    );
    await expectLater(
      feed.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          field: ThreadTextFieldView(),
          revision: 8,
        ),
      ),
      throwsA(
        isA<StudioFailure>()
            .having((f) => f.code, 'code', StudioFailureCode.storage)
            .having((f) => f.retryable, 'retryable', isTrue)
            .having((f) => f.correlationId, 'correlationId', 'detail'),
      ),
    );
    await feed.close();
  });
}

dto.BridgeTimelineBaseline _baseline({
  dto.BridgeTimelineItemSource source =
      const dto.BridgeTimelineItemSource.content(),
  BigInt? version,
  BigInt? ordinal,
  bool tool = false,
}) => dto.BridgeTimelineBaseline(
  subscriptionId: 'sub-1',
  version: version ?? BigInt.from(41),
  items: [_item(source: source, ordinal: ordinal, tool: tool)],
  before: 'opaque',
  hasOlder: true,
);
dto.BridgeTimelineItem _item({
  dto.BridgeTimelineItemSource source =
      const dto.BridgeTimelineItemSource.content(),
  BigInt? ordinal,
  bool tool = false,
}) => dto.BridgeTimelineItem(
  header: descriptor.BridgeTimelineItemHeader(
    id: 'item',
    threadId: 'thread-A',
    turnId: 'turn',
    ordinal: ordinal ?? BigInt.from(1000000007),
    createdAt: 1700000000,
    updatedAt: 1700000001,
  ),
  revision: BigInt.from(8),
  descriptor: tool
      ? descriptor.BridgeTimelineDescriptor.tool(
          descriptor.BridgeTimelineToolDescriptor(
            invocation: const descriptor.BridgeTimelineToolInvocation(
              toolCallId: 'call',
              name: 'wait',
            ),
            state: const descriptor.BridgeTimelineToolState.running(),
            userInput: const descriptor.BridgeTimelineUserInputDescriptor(
              interactionId: 'interaction',
              questions: [
                descriptor.BridgeTimelineQuestionDescriptor(
                  id: 'secret',
                  isOther: false,
                  isSecret: true,
                ),
                descriptor.BridgeTimelineQuestionDescriptor(
                  id: 'empty',
                  isOther: false,
                  isSecret: false,
                  optionCount: 0,
                ),
              ],
              state: descriptor.BridgeTimelineUserInputState.resolved(
                answers: [
                  descriptor.BridgeTimelineAnswerDescriptor(
                    questionId: 'secret',
                    answerCount: 1,
                    redacted: true,
                  ),
                ],
              ),
            ),
            wait: leaf.BridgeThreadWaitPresentation(
              intent: leaf.BridgeThreadWaitIntent.events(
                targets: const [
                  leaf.BridgeThreadWaitTarget(
                    taskId: 'task:exec-1',
                    toolName: 'exec',
                    summary: 'cargo test',
                    summaryTruncated: true,
                    status: leaf.BridgeThreadWaitTargetStatus.running,
                  ),
                ],
                timeoutMs: BigInt.from(60000),
              ),
              state: leaf.BridgeThreadWaitState.waiting,
            ),
          ),
        )
      : const descriptor.BridgeTimelineDescriptor.text(
          descriptor.BridgeTimelineTextDescriptor(
            channel: leaf.BridgeThreadTextChannel.final_,
            attachments: [],
            lifecycle: leaf.BridgeThreadContentLifecycle.completed(
              completedAt: 1700000001,
            ),
          ),
        ),
  source: source,
  saved: false,
  lifecycle: dto.BridgeTimelineLifecycle.terminal,
  fields: [
    dto.BridgeTimelineFieldPreview(
      field: const dto.BridgeContentField.text(),
      text: '中文 🐱\nfirst',
      totalBytes: BigInt.from(4096),
    ),
  ],
);

/// Only emulates the generated port. Conversion, cancellation and ownership are production code.
final class _GeneratedFeed implements wire.BridgeConversationFeed {
  final _frames = StreamController<dto.BridgeConversationFrame>();
  final calls = <String>[];
  final acks = <({String subscriptionId, BigInt sequence})>[];
  final pageRequests = <({String? before, int? limit})>[];
  final detailRequests =
      <({String itemId, dto.BridgeTimelineDetailQuery query})>[];
  Completer<void>? closeBarrier;
  Completer<void>? readBarrier;
  Object? closeFailure;
  Object? pageFailure;
  Object? detailFailure;
  int eventCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int disposeCalls = 0;
  int _sequence = 0;
  @override
  String threadId() => 'thread-A';
  @override
  String subscriptionId() => 'sub-1';
  @override
  Stream<dto.BridgeConversationFrame> events() {
    eventCalls++;
    return _frames.stream;
  }

  void send(dto.BridgeConversationEvent event, {BigInt? sequence}) =>
      _frames.add(
        dto.BridgeConversationFrame(
          threadId: 'thread-A',
          subscriptionId: 'sub-1',
          deliverySequence: sequence ?? BigInt.from(++_sequence),
          event: event,
        ),
      );
  @override
  void acknowledge({
    required String subscriptionId,
    required BigInt deliverySequence,
  }) {
    acks.add((subscriptionId: subscriptionId, sequence: deliverySequence));
  }

  @override
  Future<dto.BridgeTimelinePage> page({String? before, int? limit}) async {
    pageRequests.add((before: before, limit: limit));
    if (pageFailure case final error?) throw error;
    await readBarrier?.future;
    return dto.BridgeTimelinePage(
      items: [_item()],
      before: 'next',
      hasOlder: true,
    );
  }

  @override
  Future<dto.BridgeTimelineDetailChunk> readDetail({
    required String itemId,
    required dto.BridgeTimelineDetailQuery query,
  }) async {
    detailRequests.add((itemId: itemId, query: query));
    if (detailFailure case final error?) throw error;
    await readBarrier?.future;
    return dto.BridgeTimelineDetailChunk(
      itemId: itemId,
      field: query.field,
      revision: query.revision,
      text: 'ab',
      totalBytes: BigInt.from(6),
      continuation: 'next',
    );
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    calls.add('requestClose');
  }

  @override
  Future<void> close() async {
    closeCalls++;
    calls.add('close');
    if (closeFailure case final error?) throw error;
    await closeBarrier?.future;
  }

  @override
  void dispose() {
    disposeCalls++;
    calls.add('dispose');
    unawaited(_frames.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
