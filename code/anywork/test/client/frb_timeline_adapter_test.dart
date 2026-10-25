import 'dart:async';

import 'package:anywork/src/infrastructure/frb/conversation/timeline_port.dart';
import 'package:anywork/src/rust/api/studio/handlers/chat.dart' as wire;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as dto;
import 'package:anywork/src/rust/api/studio/types/error.dart' as err;
import 'package:anywork/src/rust/api/studio/types/shutdown.dart' as shutdown_dto;
import 'package:anywork/src/rust/api/studio/types/thread_stream/item.dart'
    as item_dto;
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // These tests execute the production FRB adapter with generated DTOs and a
  // controlled opaque interface. No native library or Rust sink is loaded.
  test('typed push preserves identity, fields and save facts', () async {
    final bridge = _GeneratedTimeline(
      _baseline(
        source: const dto.BridgeTimelineItemSource.modelRecovery(
          attemptId: 'attempt:中文',
          notice: dto.BridgeTimelineRecoveryNotice.retry,
        ),
      ),
    );
    final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
    addTearDown(connection.close);

    final iterator = StreamIterator<StudioTimelineFeedFrame>(connection.events);
    addTearDown(iterator.cancel);
    expect(await iterator.moveNext(), isTrue);
    final firstData = iterator.current as StudioTimelineFeedData;
    expect(firstData.deliverySequence, 1);
    final initial = (firstData.event as StudioTimelineFeedBaseline).baseline;
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

    final pending = iterator.moveNext();
    bridge.deliverPatch(
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
                field: const dto.BridgeContentField.rawPayload(payloadIndex: 0),
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
    await pending;
    final patchFrame = iterator.current as StudioTimelineFeedData;
    expect(patchFrame.deliverySequence, 2);
    final patch =
        (patchFrame.event as StudioTimelineFeedUpdate).update
            as StudioTimelinePatch;
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
      bridge.streamCalls,
      1,
      reason: 'the adapter maps frames without opening a second stream',
    );
    // ACK 精确往返：非负 int → u64。
    await connection.ackThrough(2);
    expect(bridge.acks.single, BigInt.from(2));
  });

  test(
    'resync keeps the subscription identity and carries a fresh baseline',
    () async {
      final bridge = _GeneratedTimeline(_baseline());
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      addTearDown(connection.close);
      final iterator = StreamIterator<StudioTimelineFeedFrame>(
        connection.events,
      );
      addTearDown(iterator.cancel);
      expect(await iterator.moveNext(), isTrue);
      final pending = iterator.moveNext();
      bridge.deliverPatch(
        dto.BridgeTimelineUpdate.resync(
          subscriptionId: 'sub-1',
          reason: dto.BridgeTimelineResyncReason.lagging,
          baseline: _baseline(version: 60, before: null, hasOlder: false),
        ),
      );
      await pending;
      final resync =
          ((iterator.current as StudioTimelineFeedData).event
                      as StudioTimelineFeedUpdate)
                  .update
              as StudioTimelineResync;
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
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      addTearDown(connection.close);

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
    'a wire u64 outside the platform int range is a typed overload frame',
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
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      addTearDown(connection.close);
      final iterator = StreamIterator<StudioTimelineFeedFrame>(
        connection.events,
      );
      addTearDown(iterator.cancel);
      expect(await iterator.moveNext(), isTrue);
      final frame = iterator.current as StudioTimelineFeedFailure;
      expect(frame.error.code, StudioFailureCode.overloaded);
      expect(frame.error.retryable, isFalse);
    },
  );

  test('a nested preview ordinal outside the platform range is a typed overload frame', () async {
    final bridge = _GeneratedTimeline(
      dto.BridgeTimelineBaseline(
        subscriptionId: 'sub-1',
        version: BigInt.from(3),
        items: [_wireItem(ordinal: BigInt.parse('18446744073709551615'))],
        before: null,
        hasOlder: false,
      ),
    );
    final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
    addTearDown(connection.close);
    final iterator = StreamIterator<StudioTimelineFeedFrame>(connection.events);
    addTearDown(iterator.cancel);
    expect(await iterator.moveNext(), isTrue);
    expect(
      (iterator.current as StudioTimelineFeedFailure).error.code,
      StudioFailureCode.overloaded,
    );
  });

  test('reading events twice does not claim the stream before the first subscription', () {
    final bridge = _GeneratedTimeline(_baseline());
    final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
    addTearDown(connection.close);
    final first = connection.events;
    expect(first, isA<Stream<StudioTimelineFeedFrame>>());
    expect(() => connection.events, returnsNormally);
    expect(bridge.streamCalls, 0, reason: 'getter 既不认领也不建立任何 native 流');
  });

  test('the second actual listen is a typed Conflict even through a fresh getter view', () async {
    final bridge = _GeneratedTimeline(_baseline());
    final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
    addTearDown(connection.close);
    final first = StreamIterator<StudioTimelineFeedFrame>(connection.events);
    expect(await first.moveNext(), isTrue);
    expect(
      () => connection.events.listen((_) {}),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.conflict,
        ),
      ),
      reason:
          '首次实际 listen 才认领；新视图的再次 listen 是 typed Conflict，'
          '不变成原生 StateError、不另开 native 流',
    );
    await first.cancel();
  });

  test(
    'a conversion failure is terminal: no data after it and the feed converges',
    () async {
      final bridge = _GeneratedTimeline(
        _baseline(),
        initialFrames: [
          _wireFrame(
            BigInt.one << 80,
            dto.BridgeTimelineEvent.baseline(baseline: _baseline()),
          ),
          _wireFrame(
            BigInt.one,
            dto.BridgeTimelineEvent.baseline(baseline: _baseline()),
          ),
        ],
      );
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      addTearDown(connection.close);
      final frames = await connection.events.toList();
      expect(frames.first, isA<StudioTimelineFeedFailure>());
      expect(
        frames.whereType<StudioTimelineFeedData>(),
        isEmpty,
        reason: '转换失败 latch 后，后续合法帧也不得作为 Data 交付',
      );
      expect(frames, hasLength(1));
    },
  );

  test(
    'a normal native Failure is terminal: later legal Data is not delivered',
    () async {
      final bridge = _GeneratedTimeline(
        _baseline(),
        initialFrames: [
          dto.BridgeTimelineFrame.failure(
            error: const err.BridgeError(
              code: err.BridgeErrorCode.protocol,
              message: 'scripted native transport failure',
              retryable: false,
              correlationId: 'probe-native-failure',
            ),
          ),
          _wireFrame(
            BigInt.one,
            dto.BridgeTimelineEvent.baseline(baseline: _baseline()),
          ),
        ],
      );
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      addTearDown(connection.close);
      final frames = await connection.events.toList();
      expect(frames, hasLength(1));
      final failure = frames.single as StudioTimelineFeedFailure;
      expect(failure.error.code, StudioFailureCode.protocol);
      expect(failure.error.correlationId, 'probe-native-failure');
      expect(
        frames.whereType<StudioTimelineFeedData>(),
        isEmpty,
        reason: '正常 native Failure 与转换失败同一终态：之后不得再有 Data',
      );
    },
  );

  test(
    'a native stream error is the same single typed terminal failure',
    () async {
      final bridge = _GeneratedTimeline(_baseline());
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      addTearDown(connection.close);
      final iterator = StreamIterator<StudioTimelineFeedFrame>(
        connection.events,
      );
      addTearDown(iterator.cancel);
      expect(await iterator.moveNext(), isTrue);

      bridge.deliverError(
        const err.BridgeError(
          code: err.BridgeErrorCode.storage,
          message: 'native sink failed',
          retryable: true,
          correlationId: 'native-stream-error',
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      final failure = iterator.current as StudioTimelineFeedFailure;
      expect(failure.error.code, StudioFailureCode.storage);
      expect(failure.error.retryable, isTrue);
      expect(failure.error.correlationId, 'native-stream-error');

      // 原生流错误同为传输终态：之后的合法 Data 不被交付。
      bridge.deliverPatch(
        dto.BridgeTimelineUpdate.patch(
          subscriptionId: 'sub-1',
          from: BigInt.from(41),
          to: BigInt.from(42),
          changes: const [],
          priority: dto.BridgeTimelinePriority.coalesced,
        ),
      );
      expect(await iterator.moveNext(), isFalse);
    },
  );

  test(
    'cancelling the stream joins the native close without requestClose',
    () async {
      final bridge = _GeneratedTimeline(_baseline())
        ..closeBarrier = Completer<void>();
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      final received = Completer<void>();
      final subscription = connection.events.listen((_) => received.complete());
      await received.future;

      final cancellation = subscription.cancel();
      await bridge.closeEntered.future;
      expect(bridge.closeCalls, 1, reason: '取消本身必须发起真实 native close，不只封闭准入');
      expect(bridge.disposeCalls, 0);

      bridge.closeBarrier!.complete();
      await cancellation;
      expect(bridge.disposeCalls, 1, reason: 'Clean 的真实 join 之后才 dispose');
      expect(bridge.calls, ['stream', 'requestClose', 'close', 'dispose']);
    },
  );

  test(
    'an explicit close and a concurrent cancel share one native join',
    () async {
      final bridge = _GeneratedTimeline(_baseline())
        ..closeBarrier = Completer<void>();
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      final received = Completer<void>();
      final subscription = connection.events.listen((_) => received.complete());
      await received.future;

      final closing = connection.close();
      final cancellation = subscription.cancel();
      await bridge.closeEntered.future;
      expect(bridge.closeCalls, 1, reason: '并发的 close 与 cancel 共享同一原生 join');
      expect(bridge.disposeCalls, 0);

      bridge.closeBarrier!.complete();
      expect((await closing).outcome, isA<CleanFeedCloseOutcome>());
      await cancellation;
      expect(bridge.disposeCalls, 1);
      expect(bridge.closeCalls, 1);
    },
  );

  test(
    'native stream cancellation must settle before opaque disposal',
    () async {
      final gate = Completer<void>();
      final bridge = _GeneratedTimeline(_baseline())
        ..nativeCancelBarrier = gate;
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      final received = Completer<void>();
      final subscription = connection.events.listen((_) => received.complete());
      await received.future;
      var cancelled = false;
      final cancellation = subscription.cancel().then((_) => cancelled = true);
      try {
        await bridge.nativeCancelEntered.future;
        expect(
          bridge.closeCalls,
          1,
          reason: 'native join starts without waiting for local cancellation',
        );
        expect(bridge.nativeCancelCalls, 1);
        expect(cancelled, isFalse);
        expect(
          bridge.disposeCalls,
          0,
          reason:
              'native Clean alone does not settle the forwarding subscription',
        );
      } finally {
        gate.complete();
        await cancellation;
      }
      expect(bridge.disposeCalls, 1);
    },
  );

  test(
    'local cancellation failure preserves every native unresolved issue',
    () async {
      final bridge = _GeneratedTimeline(_baseline())
        ..nativeCancelFailure = const err.BridgeError(
          code: err.BridgeErrorCode.unavailable,
          message: 'native forwarding cancellation failed',
          retryable: true,
          correlationId: 'forward-cancel-failed',
        )
        ..closeReport = const dto.BridgeFeedCloseReport(
          feedId: 'sub-1',
          outcome: dto.BridgeFeedCloseOutcome.unresolved(
            issues: [
              dto.BridgeFeedCloseIssue(
                diagnostic: shutdown_dto.BridgeShutdownIssue(
                stage: 'sink',
                code: 'timeout',
                message: 'native sink remains unresolved',
                retryable: false,
                correlationId: 'native-sink-unresolved',
                ),
                recovery: dto.BridgeCleanupRecovery.awaitCompletion,
              ),
            ],
          ),
        );
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      final received = Completer<void>();
      final subscription = connection.events.listen((_) => received.complete());
      await received.future;
      // Output detachment observes this same close attempt. It cannot turn
      // the retained native/local report into a second output Protocol error.
      await subscription.cancel();
      final report = await connection.close();
      final issues = (report.outcome as UnresolvedFeedCloseOutcome).issues;
      expect(issues, hasLength(2));
      expect(issues.first.diagnostic.stage, 'sink');
      expect(issues.first.diagnostic.code, 'timeout');
      expect(issues.first.diagnostic.retryable, isFalse);
      expect(issues.first.diagnostic.correlationId, 'native-sink-unresolved');
      expect(issues.first.recovery, CleanupRecovery.awaitCompletion);
      expect(issues.last.diagnostic.code, 'unavailable');
      expect(issues.last.diagnostic.stage, 'timeline-stream-cancel');
      expect(issues.last.diagnostic.retryable, isTrue);
      expect(issues.last.diagnostic.correlationId, 'forward-cancel-failed');
      expect(
        issues.last.recovery,
        CleanupRecovery.terminal,
        reason: 'Diagnostic retryable is not an independent Dart cancel capability',
      );
      expect(bridge.disposeCalls, 0);
      expect(bridge.nativeCancelCalls, 1);
      expect(await connection.close(), same(report));
      expect(
        bridge.closeCalls,
        1,
        reason: 'Unresolved is not silently retried into Clean',
      );

      bridge.nativeCancelFailure = null;
      bridge.closeReport = const dto.BridgeFeedCloseReport(
        feedId: 'sub-1',
        outcome: dto.BridgeFeedCloseOutcome.clean(),
      );
      final recoveredNative = await connection.retryClose();
      final retained =
          (recoveredNative.outcome as UnresolvedFeedCloseOutcome).issues;
      expect(retained, [issues.last]);
      expect(bridge.retryCloseCalls, 1);
      expect(bridge.nativeCancelCalls, 1, reason: 'A failed cancel is never replayed');
      expect(bridge.disposeCalls, 0, reason: 'Native Clean cannot erase terminal local work');
      final stillUnresolved = await connection.retryClose();
      expect(
        (stillUnresolved.outcome as UnresolvedFeedCloseOutcome).issues,
        [issues.last],
      );
      expect(bridge.retryCloseCalls, 1, reason: 'A completed native join is not reopened');
      expect(bridge.nativeCancelCalls, 1);
      expect(bridge.streamCalls, 1);
      expect(bridge.disposeCalls, 0);
    },
  );

  test(
    'output detachment leaves the original native join failure on its recoverable owner',
    () async {
      final bridge = _GeneratedTimeline(_baseline())
        ..closeFailure = const err.BridgeError(
          code: err.BridgeErrorCode.internal,
          message: 'native timeline join failed',
          retryable: false,
          correlationId: 'native-join-failed',
        );
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      final received = Completer<void>();
      final subscription = connection.events.listen((_) => received.complete());
      await received.future;

      await subscription.cancel();
      expect(bridge.disposeCalls, 0, reason: '真正异常必须保留 opaque 供后续 join 重试');

      final unresolved =
          (await connection.close()).outcome as UnresolvedFeedCloseOutcome;
      expect(
        unresolved.issues.single.diagnostic.code,
        'internal',
        reason: 'Output detachment must not erase the original native join diagnostic',
      );
      expect(unresolved.issues.single.diagnostic.stage, 'timeline-native-close');
      expect(unresolved.issues.single.diagnostic.message, 'native timeline join failed');
      expect(unresolved.issues.single.diagnostic.retryable, isFalse);
      expect(unresolved.issues.single.diagnostic.correlationId, 'native-join-failed');
      expect(unresolved.issues.single.recovery, CleanupRecovery.retryClose);

      bridge.closeFailure = null;
      final report = await connection.retryClose();
      expect(report.outcome is CleanFeedCloseOutcome, isTrue);
      expect(bridge.closeCalls, 1);
      expect(bridge.retryCloseCalls, 1, reason: '重试使用原 handle 的新 join，不重开 feed');
      expect(bridge.requestCloseCalls, 1);
      expect(bridge.nativeCancelCalls, 1);
      expect(bridge.disposeCalls, 1);
    },
  );

  test(
    'requestClose rejects new calls and close joins before disposing opaque',
    () async {
      final bridge = _GeneratedTimeline(_baseline())
        ..closeBarrier = Completer<void>();
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      final iterator = StreamIterator<StudioTimelineFeedFrame>(
        connection.events,
      );
      expect(await iterator.moveNext(), isTrue);
      final staleEvents = connection.events;

      connection.requestClose();
      connection.requestClose();
      expect(bridge.requestCloseCalls, 1);
      // 关闭后新调用是 typed Cancelled，不再用 null 伪装正常结束。
      final cancelled = throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      );
      // ackThrough 在 closing 下同步抛 typed Cancelled（非 failed Future）。
      expect(
        () => connection.ackThrough(1),
        cancelled,
        reason: 'closing 的 ACK 调用优先收到 typed Cancelled',
      );
      expect(() => staleEvents.listen((_) {}), cancelled,
          reason: 'Closing is checked before the already-listened Conflict');
      expect(() => connection.events, cancelled);
      await expectLater(() => connection.page(), cancelled);
      await expectLater(
        () => connection.readDetail(
          itemId: 'item-text',
          query: const StudioTimelineDetailQuery(
            field: ThreadTextFieldView(),
            revision: 8,
          ),
        ),
        cancelled,
      );
      // 迟到的 native 帧不能再进入订阅侧。
      bridge.deliverPatch(
        dto.BridgeTimelineUpdate.patch(
          subscriptionId: 'sub-1',
          from: BigInt.from(41),
          to: BigInt.from(42),
          changes: const [],
          priority: dto.BridgeTimelinePriority.coalesced,
        ),
      );
      // done 的投递与真实 join 由同一个 memoized close 收束：先启动 EOF、cancel
      // 与 close 的等待，确认 native join 仍在 barrier 之后且 opaque 未释放，
      // 再放行 barrier 并等待真实完成——不为旧断言排列跳过 join。
      final eof = iterator.moveNext();
      final closing = connection.close();
      expect(connection.close(), same(closing));
      expect(bridge.closeCalls, 1);
      expect(
        bridge.disposeCalls,
        0,
        reason: 'requestClose is not a completed native join',
      );
      bridge.closeBarrier!.complete();
      expect(
        await eof,
        isFalse,
        reason: 'a late native reply cannot be delivered after cancellation',
      );
      final report = await closing;
      expect(report.outcome is CleanFeedCloseOutcome, isTrue);
      expect(bridge.disposeCalls, 1);
      final again = await connection.close();
      expect(again.outcome is CleanFeedCloseOutcome, isTrue);
      expect(bridge.closeCalls, 1);
      expect(bridge.calls, ['stream', 'requestClose', 'close', 'dispose']);
      await iterator.cancel();
    },
  );

  test('a real EOF is a closed frame, not a null update', () async {
    final bridge = _GeneratedTimeline(_baseline());
    final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
    addTearDown(connection.close);

    final iterator = StreamIterator<StudioTimelineFeedFrame>(connection.events);
    addTearDown(iterator.cancel);
    expect(await iterator.moveNext(), isTrue);
    bridge.deliverClosed();
    expect(await iterator.moveNext(), isTrue);
    expect(
      iterator.current,
      isA<StudioTimelineFeedClosed>(),
      reason: '未关闭连接的真实传输结束是 closed 帧，不是 null',
    );
    // 传输结束不伪造 Clean 关闭报告：适配层只同步请求取消原生侧，真实 join 与
    // dispose 仍由 close() 的同一 memoized 路径完成；之后的 Data 不再交付。
    expect(bridge.requestCloseCalls, 1);
    expect(
      await iterator.moveNext(),
      isFalse,
      reason: '传输结束后流以 done 收束，迟到的 Data 不被交付',
    );
    expect(bridge.disposeCalls, 1, reason: 'done 收束来自真实 native join，而不是本地伪关闭');
  });

  test(
    'real generated BridgeError crosses the boundary as the same typed code',
    () async {
      final bridge = _GeneratedTimeline(_baseline());
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      addTearDown(connection.close);

      final iterator = StreamIterator<StudioTimelineFeedFrame>(
        connection.events,
      );
      addTearDown(iterator.cancel);
      expect(await iterator.moveNext(), isTrue);

      bridge.deliverFailure(
        const err.BridgeError(
          code: err.BridgeErrorCode.staleRevision,
          message: 'baseline is stale',
          retryable: false,
          correlationId: 'bridge-stale',
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      final failureFrame = iterator.current as StudioTimelineFeedFailure;
      expect(failureFrame.error.code, StudioFailureCode.staleRevision);
      expect(failureFrame.error.correlationId, 'bridge-stale');

      // 传输 Failure 之后本连接已封准入：查询是 typed Cancelled，而不是借旧 feed
      // 继续读取（失败既不吞成正常 EOF，也不静默恢复成可用连接）。
      const detailQuery = StudioTimelineDetailQuery(
        field: ThreadTextFieldView(),
        revision: 8,
      );
      final cancelled = throwsA(
        isA<StudioFailure>().having(
          (f) => f.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      );
      await expectLater(
        () => connection.page(),
        cancelled,
        reason: 'terminal feed 的查询是 Cancelled，不是旧 feed 的恢复入口',
      );
      await expectLater(
        () => connection.readDetail(itemId: 'item-text', query: detailQuery),
        cancelled,
      );

      // 未终止的连接上，真实 BridgeError 的 code/retryable/correlation 原样穿越。
      final queryBridge = _GeneratedTimeline(_baseline());
      final queryConnection = FrbTimelineConnection(threadId: 'thread-A', handle: queryBridge);
      addTearDown(queryConnection.close);
      queryBridge.pageFailure = const err.BridgeError(
        code: err.BridgeErrorCode.cancelled,
        message: 'connection cancelled',
        retryable: false,
        correlationId: 'bridge-cancelled',
      );
      await expectLater(
        queryConnection.page(),
        throwsA(
          isA<StudioFailure>()
              .having((f) => f.code, 'code', StudioFailureCode.cancelled)
              .having(
                (f) => f.correlationId,
                'correlationId',
                'bridge-cancelled',
              ),
        ),
      );

      queryBridge.detailFailure = const err.BridgeError(
        code: err.BridgeErrorCode.storage,
        message: 'detail read failed',
        retryable: true,
        correlationId: 'bridge-storage',
      );
      await expectLater(
        queryConnection.readDetail(itemId: 'item-text', query: detailQuery),
        throwsA(
          isA<StudioFailure>()
              .having((f) => f.code, 'code', StudioFailureCode.storage)
              .having((f) => f.retryable, 'retryable', isTrue)
              .having(
                (f) => f.correlationId,
                'correlationId',
                'bridge-storage',
              ),
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
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
      addTearDown(connection.close);

      final iterator = StreamIterator<StudioTimelineFeedFrame>(
        connection.events,
      );
      addTearDown(iterator.cancel);
      expect(await iterator.moveNext(), isTrue);
      final initial =
          ((iterator.current as StudioTimelineFeedData).event
                  as StudioTimelineFeedBaseline)
              .baseline;
      final wait = initial.items.single.item.tool?.wait;
      expect(wait, isNotNull);
      expect(wait!.state, ThreadWaitState.waiting);
      expect(wait.messagesReady, isNull);
      final intent = wait.intent as ThreadWaitEventsIntentView;
      expect(intent.timeoutMs, 60000);
      expect(intent.targets, hasLength(1));
      expect(intent.targets.single.taskId, 'task:exec-1');
      expect(intent.targets.single.toolName, 'exec');
      expect(intent.targets.single.summary, 'cargo test');
      expect(intent.targets.single.status, ThreadWaitTargetStatus.running);
      expect(intent.targets.single.summaryTruncated, isTrue);
    },
  );

  test(
    'an unresolved close report keeps the opaque handle and repeats stably',
    () async {
      final bridge = _GeneratedTimeline(_baseline())
        ..closeReport = const dto.BridgeFeedCloseReport(
          feedId: 'sub-1',
          outcome: dto.BridgeFeedCloseOutcome.unresolved(
            issues: [
              dto.BridgeFeedCloseIssue(
                diagnostic: shutdown_dto.BridgeShutdownIssue(
                stage: 'delivery',
                code: 'cancelled',
                message: 'a delivery call is still in flight',
                retryable: true,
                correlationId: 'issue-1',
              ),
                recovery: dto.BridgeCleanupRecovery.awaitCompletion,
              ),
              dto.BridgeFeedCloseIssue(
                diagnostic: shutdown_dto.BridgeShutdownIssue(
                stage: 'sink',
                code: 'timeout',
                message: 'the sink did not drain',
                retryable: false,
                correlationId: 'issue-2',
                ),
                recovery: dto.BridgeCleanupRecovery.retryClose,
              ),
            ],
          ),
        );
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);

      final report = await connection.close();
      expect(report.outcome is CleanFeedCloseOutcome, isFalse);
      expect(report.feedId, 'sub-1');
      final unresolved = report.outcome as UnresolvedFeedCloseOutcome;
      expect(unresolved.issues, hasLength(2));
      expect(unresolved.issues.first.diagnostic.stage, 'delivery');
      expect(unresolved.issues.first.diagnostic.code, 'cancelled');
      expect(unresolved.issues.first.diagnostic.retryable, isTrue);
      expect(unresolved.issues.first.diagnostic.correlationId, 'issue-1');
      expect(unresolved.issues.first.recovery, CleanupRecovery.awaitCompletion);
      expect(unresolved.issues.last.diagnostic.message, 'the sink did not drain');
      expect(unresolved.issues.last.recovery, CleanupRecovery.retryClose);
      expect(
        bridge.disposeCalls,
        0,
        reason: 'an unresolved owner must retain the opaque handle',
      );
      // 重复 close 观察同一报告，不二次 join。
      final again = await connection.close();
      expect(again.outcome, same(unresolved));
      expect(bridge.closeCalls, 1);
      expect(bridge.disposeCalls, 0);

      // An explicit recovery can first settle retryClose work while the same
      // native owner still awaits completion. The next recovery must continue
      // that owner even when none of its remaining issues says retryClose.
      bridge.closeReport = dto.BridgeFeedCloseReport(
        feedId: 'sub-1',
        outcome: dto.BridgeFeedCloseOutcome.unresolved(
          issues: [
            dto.BridgeFeedCloseIssue(
              diagnostic: const shutdown_dto.BridgeShutdownIssue(
                stage: 'delivery',
                code: 'cancelled',
                message: 'the original delivery is still completing',
                retryable: false,
                correlationId: 'issue-1',
              ),
              recovery: dto.BridgeCleanupRecovery.awaitCompletion,
            ),
          ],
        ),
      );
      final waiting = await connection.retryClose();
      final remaining = (waiting.outcome as UnresolvedFeedCloseOutcome).issues;
      expect(remaining, hasLength(1));
      expect(remaining.single.recovery, CleanupRecovery.awaitCompletion);
      expect(remaining.single.diagnostic.retryable, isFalse);
      expect(bridge.retryCloseCalls, 1);
      expect(bridge.disposeCalls, 0);

      bridge.closeReport = const dto.BridgeFeedCloseReport(
        feedId: 'sub-1',
        outcome: dto.BridgeFeedCloseOutcome.clean(),
      );
      bridge.closeBarrier = Completer<void>();
      final recovering = connection.retryClose();
      expect(connection.retryClose(), same(recovering));
      expect(bridge.retryCloseCalls, 2);
      expect(bridge.disposeCalls, 0);
      bridge.closeBarrier!.complete();
      final clean = await recovering;
      expect(clean.outcome, isA<CleanFeedCloseOutcome>());
      expect(bridge.closeCalls, 1);
      expect(bridge.requestCloseCalls, 1);
      expect(bridge.streamCalls, 0, reason: 'Recovery never opens a replacement feed');
      expect(bridge.disposeCalls, 1);
      expect((await connection.retryClose()).outcome, isA<CleanFeedCloseOutcome>());
      expect(bridge.retryCloseCalls, 2);
      expect(bridge.disposeCalls, 1);
    },
  );

  test('a report with an empty feed id or empty issues is a protocol failure that keeps the handle', () async {
    final bridge = _GeneratedTimeline(_baseline())
      ..closeReport = const dto.BridgeFeedCloseReport(
        feedId: '',
        outcome: dto.BridgeFeedCloseOutcome.clean(),
      );
    final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
    await expectLater(
      connection.close(),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.protocol,
        ),
      ),
    );
    expect(bridge.disposeCalls, 0);

    final emptyIssues = _GeneratedTimeline(_baseline())
      ..closeReport = const dto.BridgeFeedCloseReport(
        feedId: 'sub-1',
        outcome: dto.BridgeFeedCloseOutcome.unresolved(issues: []),
      );
    final emptyConnection = FrbTimelineConnection(threadId: 'thread-A', handle: emptyIssues);
    await expectLater(
      emptyConnection.close(),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.protocol,
        ),
      ),
    );
    expect(emptyIssues.disposeCalls, 0);
  });

  test(
    'failed native join retains opaque and permits supervisor close retry',
    () async {
      const failure = err.BridgeError(
        code: err.BridgeErrorCode.internal,
        message: 'native timeline join failed',
        retryable: false,
        correlationId: 'unclaimed-native-join-failed',
      );
      final bridge = _GeneratedTimeline(_baseline())..closeFailure = failure;
      final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);

      // 关闭失败同样以 typed 失败穿越边界，但句柄与许可保留供重试。
      await expectLater(
        connection.close(),
        throwsA(
          isA<StudioFailure>()
              .having((failure) => failure.code, 'code', StudioFailureCode.internal)
              .having((failure) => failure.correlationId, 'correlationId',
                'unclaimed-native-join-failed'),
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
      final report = await connection.retryClose();
      expect(report.outcome is CleanFeedCloseOutcome, isTrue);
      expect(bridge.closeCalls, 1);
      expect(bridge.retryCloseCalls, 1);
      expect(bridge.requestCloseCalls, 1);
      expect(bridge.disposeCalls, 1);
    },
  );

  test('output cancellation before the first identity observes but does not replace the retained close error', () async {
    final bridge = _GeneratedTimeline(_baseline(), initialFrames: const [])
      ..closeFailure = StateError('private native close failure before the first baseline');
    final connection = FrbTimelineConnection(threadId: 'thread-A', handle: bridge);
    final subscription = connection.events.listen((_) => fail('No baseline was supplied'));
    await bridge.streamEntered.future;
    final closing = connection.close();
    final retained = expectLater(closing, throwsA(isA<StudioFailure>()
      .having((failure) => failure.code, 'code', StudioFailureCode.protocol)
      .having((failure) => failure.retryable, 'retryable', isFalse)
      .having((failure) => failure.correlationId, 'correlationId', 'adapter-bridge-call')
      .having((failure) => failure.message, 'message', isNot(contains('private native close failure')))));
    await subscription.cancel();
    await retained;
    await expectLater(connection.close(), throwsA(isA<StudioFailure>().having(
      (failure) => failure.correlationId, 'correlationId', 'adapter-bridge-call')));
    expect(bridge.closeCalls, 1);
    expect(bridge.nativeCancelCalls, 1);
    expect(bridge.disposeCalls, 0,
      reason: 'Output detachment does not prove native Clean or release the handle');
    bridge.closeFailure = null;
    final report = await connection.retryClose();
    expect(report.outcome, isA<CleanFeedCloseOutcome>());
    expect(bridge.closeCalls, 1);
    expect(bridge.retryCloseCalls, 1);
    expect(bridge.nativeCancelCalls, 1);
    expect(bridge.streamCalls, 1);
    expect(bridge.disposeCalls, 1);
  });
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

dto.BridgeTimelineFrame _wireFrame(
  BigInt sequence,
  dto.BridgeTimelineEvent event,
) => dto.BridgeTimelineFrame.data(deliverySequence: sequence, event: event);

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
  _GeneratedTimeline(this.baseline, {this.initialFrames});

  final dto.BridgeTimelineBaseline baseline;
  final List<dto.BridgeTimelineFrame>? initialFrames;
  final calls = <String>[];
  final pageRequests = <({String? before, int? limit})>[];
  final detailRequests =
      <({String itemId, dto.BridgeTimelineDetailQuery query})>[];
  Completer<void>? closeBarrier;
  Completer<void>? nativeCancelBarrier;
  Object? nativeCancelFailure;
  int nativeCancelCalls = 0;
  Completer<void>? readBarrier;
  Object? closeFailure;
  dto.BridgeFeedCloseReport? closeReport;
  Object? pageFailure;
  Object? detailFailure;
  final List<BigInt> acks = [];
  int streamCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;
  int disposeCalls = 0;
  final closeEntered = Completer<void>();
  final streamEntered = Completer<void>();
  final nativeCancelEntered = Completer<void>();

  StreamController<dto.BridgeTimelineFrame>? _frames;
  bool _streamClaimed = false;
  bool _closed = false;
  int _nextSequence = 1;

  @override
  Stream<dto.BridgeTimelineFrame> stream() {
    if (_streamClaimed) {
      throw StateError('The generated fake stream was already claimed');
    }
    _streamClaimed = true;
    streamCalls++;
    calls.add('stream');
    streamEntered.complete();
    final controller = StreamController<dto.BridgeTimelineFrame>();
    _frames = controller;
    controller.onCancel = () async {
      nativeCancelCalls++;
      if (!nativeCancelEntered.isCompleted) nativeCancelEntered.complete();
      await nativeCancelBarrier?.future;
      if (nativeCancelFailure case final failure?) throw failure;
    };
    controller.onListen = () {
      final staged = initialFrames;
      if (staged != null) {
        for (final frame in staged) {
          controller.add(frame);
        }
        return;
      }
      controller.add(
        dto.BridgeTimelineFrame.data(
          deliverySequence: BigInt.from(_nextSequence++),
          event: dto.BridgeTimelineEvent.baseline(baseline: baseline),
        ),
      );
    };
    return controller.stream;
  }

  void deliverPatch(dto.BridgeTimelineUpdate update) {
    final controller = _frames;
    if (controller == null || controller.isClosed) return;
    controller.add(
      dto.BridgeTimelineFrame.data(
        deliverySequence: BigInt.from(_nextSequence++),
        event: dto.BridgeTimelineEvent.update(update: update),
      ),
    );
  }

  void deliverFailure(err.BridgeError error) {
    final controller = _frames;
    if (controller == null || controller.isClosed) return;
    controller.add(dto.BridgeTimelineFrame.failure(error: error));
  }

  void deliverError(Object error) {
    final controller = _frames;
    if (controller == null || controller.isClosed) return;
    controller.addError(error);
  }

  void deliverClosed() {
    final controller = _frames;
    if (controller == null || controller.isClosed) return;
    controller.add(const dto.BridgeTimelineFrame.closed());
  }

  @override
  Future<void> ackThrough({required BigInt deliverySequence}) async {
    if (_closed) {
      throw const err.BridgeError(
        code: err.BridgeErrorCode.cancelled,
        message: 'the timeline feed is closed',
        retryable: false,
        correlationId: 'fake-timeline-closed',
      );
    }
    acks.add(deliverySequence);
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
    if (_closed) return;
    _closed = true;
    // 真实 native 取消会同步打断在途等待：订阅侧以 done 收束，迟到帧不再交付。
    final controller = _frames;
    if (controller != null && !controller.isClosed) {
      scheduleMicrotask(controller.close);
    }
  }

  @override
  Future<dto.BridgeFeedCloseReport> close() {
    closeCalls++;
    calls.add('close');
    if (!closeEntered.isCompleted) closeEntered.complete();
    return _joinOriginalHandle();
  }

  @override
  Future<dto.BridgeFeedCloseReport> retryClose() {
    retryCloseCalls++;
    calls.add('retryClose');
    return _joinOriginalHandle();
  }

  Future<dto.BridgeFeedCloseReport> _joinOriginalHandle() {
    final failure = closeFailure;
    if (failure != null) return Future.error(failure);
    return (closeBarrier?.future ?? Future<void>.value()).then((_) {
      return closeReport ??
          dto.BridgeFeedCloseReport(
            feedId: baseline.subscriptionId,
            outcome: const dto.BridgeFeedCloseOutcome.clean(),
          );
    });
  }

  @override
  void dispose() {
    disposeCalls++;
    calls.add('dispose');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
