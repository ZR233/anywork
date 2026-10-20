import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/handlers/chat.dart' as wire;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as dto;
import 'package:anywork/src/rust/api/studio/types/error.dart' as err;
import 'package:anywork/src/rust/api/studio/types/thread_stream/item.dart'
    as item_dto;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // These tests execute the production FRB adapter with generated DTOs and a
  // controlled opaque interface. No native library or Rust sink is loaded.
  test(
    'baseline and typed changes preserve identity, fields and save facts',
    () async {
      final bridge = _GeneratedTimeline(
        _baseline(
          source: const dto.BridgeTimelineItemSource.modelRecovery(
            attemptId: 'attempt:中文',
            notice: dto.BridgeTimelineRecoveryNotice.retry,
          ),
        ),
      );
      final connection = FrbTimelineConnection(bridge);
      addTearDown(connection.close);

      final initial = await connection.initial();
      expect(initial.subscriptionId, 'sub-1');
      expect(initial.version, 41);
      expect(initial.before, 'tlp1.opaque');
      expect(initial.hasOlder, isTrue);
      final first = initial.items.single;
      expect(first.source, isA<StudioTimelineRecoverySource>());
      expect(
        (first.source as StudioTimelineRecoverySource).attemptId,
        'attempt:中文',
      );
      expect(
        (first.source as StudioTimelineRecoverySource).notice,
        StudioTimelineRecoveryNotice.retry,
      );
      expect(first.item.id, 'item-text');
      expect(first.item.threadId, 'thread-A');
      expect(first.item.ordinal, 1000000007);
      expect(first.item.revision, 8);
      expect(first.saved, isFalse);
      expect(first.terminal, isTrue, reason: 'terminal does not imply durable');
      expect(first.item.executionTerminal, isTrue);
      expect(first.omittedBytes, 13);
      expect(first.details.single.field, isA<ThreadTextFieldView>());
      expect(first.details.single.revision, 8);
      expect(first.details.single.totalBytes, 4096);
      expect(first.details.single.previewBytes, 64);
      expect(
        first.details.single.truncated,
        isTrue,
        reason: 'the full body stays readable through the detail ref',
      );
      final text = first.item.state as ThreadTextItemStateView;
      expect(text.channel, ThreadTextChannel.finalAnswer);
      expect(text.text, '中文 🐱\nfirst');

      final pending = connection.next();
      bridge.deliver(
        dto.BridgeTimelineUpdate.patch(
          subscriptionId: 'sub-1',
          from: BigInt.from(41),
          to: BigInt.from(45),
          changes: [
            dto.BridgeTimelineChange.updateItem(
              itemId: 'item-text',
              expectedRevision: BigInt.from(8),
              revision: BigInt.from(9),
              omittedBytes: BigInt.zero,
              saved: true,
              lifecycle: dto.BridgeTimelineLifecycle.terminal,
              itemShell: null,
              fields: [
                dto.BridgeTimelineFieldUpdate(
                  field: const dto.BridgeContentField.text(),
                  change: const dto.BridgeTimelineFieldChange.append(
                    text: '\nsecond',
                  ),
                  totalBytes: BigInt.from(15),
                  previewBytes: BigInt.from(15),
                ),
                dto.BridgeTimelineFieldUpdate(
                  field: const dto.BridgeContentField.rawPayload(
                    payloadIndex: 0,
                  ),
                  change: const dto.BridgeTimelineFieldChange.remove(),
                  totalBytes: BigInt.zero,
                  previewBytes: BigInt.zero,
                ),
              ],
            ),
            dto.BridgeTimelineChange.add(
              item: _wireItem(id: 'item-next', terminal: false, saved: true),
            ),
            const dto.BridgeTimelineChange.remove(itemId: 'paged-only'),
          ],
          priority: dto.BridgeTimelinePriority.immediate,
        ),
      );
      final patch = (await pending) as StudioTimelinePatch;
      expect(patch.subscriptionId, 'sub-1');
      expect(patch.from, 41);
      expect(patch.to, 45, reason: 'consolidated patches may skip versions');
      expect(patch.priority, StudioTimelinePriority.immediate);
      expect(patch.changes, hasLength(3));

      final update = patch.changes.first as StudioTimelineUpdateItem;
      expect(update.itemId, 'item-text');
      expect(update.expectedRevision, 8);
      expect(update.revision, 9);
      expect(update.omittedBytes, 0);
      expect(update.saved, isTrue);
      expect(update.lifecycle, StudioTimelineLifecycle.terminal);
      expect(
        (update.fields.first.change as AppendThreadFieldChangeView).text,
        '\nsecond',
      );
      expect(update.fields.first.totalBytes, 15);
      expect(update.fields.first.previewBytes, 15);
      expect(update.fields.last.field, isA<ThreadRawPayloadFieldView>());
      expect(update.fields.last.change, isA<RemoveThreadFieldChangeView>());

      final added = patch.changes[1] as StudioTimelineAdd;
      expect(added.item.id, 'item-next');
      expect(added.item.saved, isTrue);
      expect(
        added.item.terminal,
        isFalse,
        reason: 'saved and execution terminal remain independent',
      );
      expect((patch.changes.last as StudioTimelineRemove).itemId, 'paged-only');
      expect(
        bridge.initialCalls,
        1,
        reason: 'the adapter maps frames without reading a second baseline',
      );
    },
  );

  test(
    'resync keeps the subscription identity and carries a fresh baseline',
    () async {
      final bridge = _GeneratedTimeline(_baseline());
      final connection = FrbTimelineConnection(bridge);
      addTearDown(connection.close);
      await connection.initial();
      final pending = connection.next();
      bridge.deliver(
        dto.BridgeTimelineUpdate.resync(
          subscriptionId: 'sub-1',
          reason: dto.BridgeTimelineResyncReason.lagging,
          baseline: _baseline(version: 60, before: null, hasOlder: false),
        ),
      );
      final resync = (await pending) as StudioTimelineResync;
      expect(resync.subscriptionId, 'sub-1');
      expect(resync.reason, StudioTimelineResyncReason.lagging);
      expect(resync.baseline.version, 60);
      expect(resync.baseline.before, isNull);
      expect(resync.baseline.hasOlder, isFalse);
    },
  );

  test(
    'page and detail queries carry opaque cursors and typed fields',
    () async {
      final bridge = _GeneratedTimeline(_baseline());
      final connection = FrbTimelineConnection(bridge);
      addTearDown(connection.close);
      await connection.initial();

      final page = await connection.page(before: 'tlp1.opaque', limit: 32);
      expect(bridge.pageRequests.single.before, 'tlp1.opaque');
      expect(bridge.pageRequests.single.limit, 32);
      expect(page.before, 'tlp1.next');
      expect(page.hasOlder, isTrue);
      expect(page.items.single.id, 'item-older');

      final chunk = await connection.readDetail(
        itemId: 'item-text',
        query: const StudioTimelineDetailQuery(
          field: ThreadToolOutputArtifactsFieldView(),
          revision: 8,
          continuation: 'tld1.offset',
          maxBytes: 8,
        ),
      );
      final request = bridge.detailRequests.single;
      expect(request.itemId, 'item-text');
      expect(request.query.revision, BigInt.from(8));
      expect(request.query.continuation, 'tld1.offset');
      expect(request.query.maxBytes, 8);
      expect(
        request.query.field,
        isA<dto.BridgeContentField_ToolOutputArtifacts>(),
        reason: 'artifacts are a typed content field, not static metadata',
      );
      expect(chunk.text, 'ab');
      expect(chunk.totalBytes, 6);
      expect(chunk.continuation, 'tld1.next');
      expect(chunk.field, isA<ThreadToolOutputArtifactsFieldView>());
    },
  );

  test(
    'a wire u64 outside the platform int range is a typed overload',
    () async {
      final bridge = _GeneratedTimeline(
        dto.BridgeTimelineBaseline(
          subscriptionId: 'sub-1',
          version: BigInt.parse('18446744073709551615'),
          items: [_wireItem()],
          before: null,
          hasOlder: false,
        ),
      );
      final connection = FrbTimelineConnection(bridge);
      addTearDown(connection.close);
      await expectLater(
        connection.initial(),
        throwsA(
          isA<StudioFailure>()
              .having(
                (failure) => failure.code,
                'code',
                StudioFailureCode.overloaded,
              )
              .having((failure) => failure.retryable, 'retryable', isFalse),
        ),
      );
    },
  );

  test(
    'a nested preview ordinal outside the platform range is a typed overload',
    () async {
      final bridge = _GeneratedTimeline(
        dto.BridgeTimelineBaseline(
          subscriptionId: 'sub-1',
          version: BigInt.from(3),
          items: [_wireItem(ordinal: BigInt.parse('18446744073709551615'))],
          before: null,
          hasOlder: false,
        ),
      );
      final connection = FrbTimelineConnection(bridge);
      addTearDown(connection.close);
      await expectLater(
        connection.initial(),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.overloaded,
          ),
        ),
      );
    },
  );

  test(
    'requestClose rejects new reads and close joins before disposing opaque',
    () async {
      final bridge = _GeneratedTimeline(_baseline())
        ..closeBarrier = Completer<void>();
      final connection = FrbTimelineConnection(bridge);
      final inFlight = connection.next();

      connection.requestClose();
      connection.requestClose();
      expect(bridge.requestCloseCalls, 1);
      // 关闭后 new read 是 typed Cancelled，不再用 null 伪装正常结束。
      await expectLater(
        connection.next(),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.cancelled,
          ),
        ),
      );
      expect(bridge.nextCalls, 1);
      await expectLater(connection.initial(), throwsA(isA<StudioFailure>()));
      await expectLater(connection.page(), throwsA(isA<StudioFailure>()));
      bridge.deliver(
        dto.BridgeTimelineUpdate.patch(
          subscriptionId: 'sub-1',
          from: BigInt.from(41),
          to: BigInt.from(42),
          changes: const [],
          priority: dto.BridgeTimelinePriority.coalesced,
        ),
      );
      await expectLater(
        inFlight,
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.cancelled,
          ),
        ),
        reason: 'a late native reply cannot be delivered after cancellation',
      );

      final closing = connection.close();
      expect(connection.close(), same(closing));
      expect(bridge.closeCalls, 1);
      expect(
        bridge.disposeCalls,
        0,
        reason: 'requestClose is not a completed native join',
      );
      bridge.closeBarrier!.complete();
      await closing;
      expect(bridge.disposeCalls, 1);
      await connection.close();
      expect(bridge.closeCalls, 1);
      expect(bridge.calls, ['next', 'requestClose', 'close', 'dispose']);
    },
  );

  test('关闭后迟到的首帧、页与详情统一返回 typed Cancelled', () async {
    final barrier = Completer<void>();
    final bridge = _GeneratedTimeline(_baseline())..readBarrier = barrier;
    final connection = FrbTimelineConnection(bridge);
    final cancelled = throwsA(
      isA<StudioFailure>().having(
        (error) => error.code,
        'code',
        StudioFailureCode.cancelled,
      ),
    );
    final reads = [
      expectLater(connection.initial(), cancelled),
      expectLater(connection.page(), cancelled),
      expectLater(
        connection.readDetail(
          itemId: 'item-text',
          query: const StudioTimelineDetailQuery(
            field: ThreadTextFieldView(),
            revision: 8,
          ),
        ),
        cancelled,
      ),
    ];
    connection.requestClose();
    barrier.complete();
    await Future.wait(reads);
    await connection.close();
    expect(bridge.disposeCalls, 1);
  });

  test(
    'failed native join retains opaque and permits supervisor close retry',
    () async {
      final failure = StateError('native timeline join failed');
      final bridge = _GeneratedTimeline(_baseline())..closeFailure = failure;
      final connection = FrbTimelineConnection(bridge);

      // 关闭失败同样以 typed 失败穿越边界，但句柄与许可保留供重试。
      await expectLater(
        connection.close(),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.internal,
          ),
        ),
      );
      expect(
        bridge.disposeCalls,
        0,
        reason: 'an unresolved owner must retain the opaque handle',
      );
      expect(bridge.requestCloseCalls, 1);
      expect(bridge.closeCalls, 1);

      bridge.closeFailure = null;
      await connection.close();
      expect(bridge.closeCalls, 2);
      expect(bridge.requestCloseCalls, 1);
      expect(bridge.disposeCalls, 1);
    },
  );

  test(
    'only a real EOF on an open connection ends the stream with null',
    () async {
      final bridge = _GeneratedTimeline(_baseline());
      final connection = FrbTimelineConnection(bridge);
      addTearDown(connection.close);

      final pending = connection.next();
      bridge.deliver(null);
      expect(await pending, isNull, reason: '未关闭连接的真实 EOF 仍然是 null');

      final inFlight = connection.next();
      await connection.close();
      // 在途关闭：真实回包晚到也不能被当作正常结束。
      bridge.deliver(null);
      await expectLater(
        inFlight,
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.cancelled,
          ),
        ),
      );
      // 关闭之后再读同样以 typed Cancelled 优先。
      await expectLater(
        connection.next(),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.cancelled,
          ),
        ),
      );
    },
  );

  test(
    'real generated BridgeError crosses the boundary as the same typed code',
    () async {
      final bridge = _GeneratedTimeline(_baseline());
      final connection = FrbTimelineConnection(bridge);
      addTearDown(connection.close);

      bridge.initialFailure = const err.BridgeError(
        code: err.BridgeErrorCode.staleRevision,
        message: 'baseline is stale',
        retryable: false,
        correlationId: 'bridge-stale',
      );
      await expectLater(
        connection.initial(),
        throwsA(
          isA<StudioFailure>()
              .having((f) => f.code, 'code', StudioFailureCode.staleRevision)
              .having((f) => f.correlationId, 'correlationId', 'bridge-stale'),
        ),
      );

      bridge.pageFailure = const err.BridgeError(
        code: err.BridgeErrorCode.cancelled,
        message: 'connection cancelled',
        retryable: false,
        correlationId: 'bridge-cancelled',
      );
      await expectLater(
        connection.page(),
        throwsA(
          isA<StudioFailure>().having(
            (f) => f.code,
            'code',
            StudioFailureCode.cancelled,
          ),
        ),
      );

      bridge.detailFailure = const err.BridgeError(
        code: err.BridgeErrorCode.storage,
        message: 'detail read failed',
        retryable: true,
        correlationId: 'bridge-storage',
      );
      await expectLater(
        connection.readDetail(
          itemId: 'item-text',
          query: const StudioTimelineDetailQuery(
            field: ThreadTextFieldView(),
            revision: 8,
          ),
        ),
        throwsA(
          isA<StudioFailure>()
              .having((f) => f.code, 'code', StudioFailureCode.storage)
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
    },
  );

  test(
    'typed wait presentation survives FRB adapter without JSON parsing',
    () async {
      final bridge = _GeneratedTimeline(
        dto.BridgeTimelineBaseline(
          subscriptionId: 'sub-wait',
          version: BigInt.from(7),
          items: [_wireWaitItem()],
          before: null,
          hasOlder: false,
        ),
      );
      final connection = FrbTimelineConnection(bridge);
      addTearDown(connection.close);

      final initial = await connection.initial();
      final wait = initial.items.single.item.tool?.wait;
      expect(wait, isNotNull);
      expect(wait!.state, ThreadWaitStateView.waiting);
      expect(wait.messagesReady, isNull);
      final intent = wait.intent as ThreadWaitEventsIntentView;
      expect(intent.timeoutMs, 60000);
      expect(intent.targets, hasLength(1));
      expect(intent.targets.single.taskId, 'task:exec-1');
      expect(intent.targets.single.toolName, 'exec');
      expect(intent.targets.single.summary, 'cargo test');
      expect(intent.targets.single.status, ThreadWaitTargetStatusView.running);
      expect(intent.targets.single.summaryTruncated, isTrue);
    },
  );
}

dto.BridgeTimelineBaseline _baseline({
  dto.BridgeTimelineItemSource source =
      const dto.BridgeTimelineItemSource.content(),
  int version = 41,
  String? before = 'tlp1.opaque',
  bool hasOlder = true,
}) => dto.BridgeTimelineBaseline(
  subscriptionId: 'sub-1',
  version: BigInt.from(version),
  items: [_wireItem(source: source)],
  before: before,
  hasOlder: hasOlder,
);

dto.BridgeTimelineItem _wireWaitItem() => dto.BridgeTimelineItem(
  source: const dto.BridgeTimelineItemSource.content(),
  item: item_dto.BridgeThreadItem(
    id: 'tool:wait-1',
    threadId: 'thread-A',
    turnId: 'turn-7',
    ordinal: BigInt.from(4),
    revision: BigInt.from(1),
    createdAt: 1700000000,
    updatedAt: 1700000001,
    state: item_dto.BridgeThreadItemState.tool(
      invocation: const item_dto.BridgeThreadToolInvocation(
        toolCallId: 'call-wait',
        name: 'wait',
        arguments: '{"taskIds":["task:exec-1"],"timeoutMs":60000}',
      ),
      state: const item_dto.BridgeThreadToolState.running(streamedOutput: ''),
      wait: item_dto.BridgeThreadWaitPresentation(
        intent: item_dto.BridgeThreadWaitIntent.events(
          targets: const [
            item_dto.BridgeThreadWaitTarget(
              taskId: 'task:exec-1',
              toolName: 'exec',
              summary: 'cargo test',
              summaryTruncated: true,
              status: item_dto.BridgeThreadWaitTargetStatus.running,
            ),
          ],
          timeoutMs: BigInt.from(60000),
        ),
        state: item_dto.BridgeThreadWaitState.waiting,
      ),
    ),
  ),
  saved: true,
  lifecycle: dto.BridgeTimelineLifecycle.streaming,
  omittedBytes: BigInt.zero,
  details: const [],
);

dto.BridgeTimelineItem _wireItem({
  dto.BridgeTimelineItemSource source =
      const dto.BridgeTimelineItemSource.content(),
  String id = 'item-text',
  bool terminal = true,
  bool saved = false,
  BigInt? ordinal,
}) => dto.BridgeTimelineItem(
  source: source,
  item: item_dto.BridgeThreadItem(
    id: id,
    threadId: 'thread-A',
    turnId: 'turn-7',
    ordinal: ordinal ?? BigInt.from(1000000007),
    revision: BigInt.from(8),
    createdAt: 1700000000,
    updatedAt: 1700000001,
    state: item_dto.BridgeThreadItemState.text(
      channel: item_dto.BridgeThreadTextChannel.final_,
      text: '中文 🐱\nfirst',
      attachments: const [],
      lifecycle: terminal
          ? const item_dto.BridgeThreadContentLifecycle.completed(
              completedAt: 1700000001,
            )
          : const item_dto.BridgeThreadContentLifecycle.streaming(),
    ),
  ),
  saved: saved,
  lifecycle: terminal
      ? dto.BridgeTimelineLifecycle.terminal
      : dto.BridgeTimelineLifecycle.streaming,
  omittedBytes: BigInt.from(13),
  details: [
    dto.BridgeTimelineDetailRef(
      field: const dto.BridgeContentField.text(),
      revision: BigInt.from(8),
      totalBytes: BigInt.from(4096),
      previewBytes: BigInt.from(64),
    ),
  ],
);

class _GeneratedTimeline implements wire.BridgeTimeline {
  _GeneratedTimeline(this.baseline);

  final dto.BridgeTimelineBaseline baseline;
  final calls = <String>[];
  final pendingFrames = <Completer<dto.BridgeTimelineUpdate?>>[];
  final pageRequests = <({String? before, int? limit})>[];
  final detailRequests =
      <({String itemId, dto.BridgeTimelineDetailQuery query})>[];
  Completer<void>? closeBarrier;
  Completer<void>? readBarrier;
  Object? closeFailure;
  Object? initialFailure;
  Object? pageFailure;
  Object? detailFailure;
  int initialCalls = 0;
  int nextCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<dto.BridgeTimelineBaseline> initial() async {
    initialCalls++;
    calls.add('initial');
    await readBarrier?.future;
    if (initialFailure case final failure?) throw failure;
    return baseline;
  }

  @override
  Future<dto.BridgeTimelineUpdate?> next() {
    nextCalls++;
    calls.add('next');
    final pending = Completer<dto.BridgeTimelineUpdate?>();
    pendingFrames.add(pending);
    return pending.future;
  }

  void deliver(dto.BridgeTimelineUpdate? frame) {
    pendingFrames.removeAt(0).complete(frame);
  }

  @override
  Future<dto.BridgeTimelinePage> page({String? before, int? limit}) async {
    pageRequests.add((before: before, limit: limit));
    await readBarrier?.future;
    if (pageFailure case final failure?) throw failure;
    return dto.BridgeTimelinePage(
      items: [_wireItem(id: 'item-older', terminal: true, saved: true)],
      before: 'tlp1.next',
      hasOlder: true,
    );
  }

  @override
  Future<dto.BridgeTimelineDetailChunk> readDetail({
    required String itemId,
    required dto.BridgeTimelineDetailQuery query,
  }) async {
    detailRequests.add((itemId: itemId, query: query));
    await readBarrier?.future;
    if (detailFailure case final failure?) throw failure;
    return dto.BridgeTimelineDetailChunk(
      itemId: 'item-text',
      field: const dto.BridgeContentField.toolOutputArtifacts(),
      revision: BigInt.from(8),
      text: 'ab',
      totalBytes: BigInt.from(6),
      continuation: 'tld1.next',
    );
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    calls.add('requestClose');
    // 真实 native 取消不会替我们收回已发出的回包：保留挂起读，让测试能证明迟到回包
    // 不会在取消之后被交付。
  }

  @override
  Future<void> close() {
    closeCalls++;
    calls.add('close');
    final failure = closeFailure;
    if (failure != null) return Future.error(failure);
    return closeBarrier?.future ?? Future.value();
  }

  @override
  void dispose() {
    disposeCalls++;
    calls.add('dispose');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
