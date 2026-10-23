import 'dart:async';

import 'package:anywork_client/anywork_client.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

typedef _Ready = ({
  StudioTimelineChannel channel,
  TestTimelineConnection connection,
});

/// 尾部差量 reducer 的缺陷敏感度：不可证明连续就必须显式失败（重同步），
/// 绝不能猜删除、拼接跨 revision 正文或把错误当成正常结束。
void main() {
  Future<_Ready> open(
    TestTimelineTransport transport, {
    StudioTimelineBaseline? initial,
    StudioTimelineChannel? channel,
  }) async {
    final owner = channel ?? timelineChannel(transport);
    owner.start();
    final connection = TestTimelineConnection(initial: initial ?? baseline(3));
    transport.opens.single.complete(connection);
    await owner.ready;
    // 基线 ACK 是发布后的微任务：等队列收束再开始脚本化后续帧。
    await pumpEventQueue();
    return (channel: owner, connection: connection);
  }

  Future<Object> nextFailure(
    StudioTimelineChannel channel,
    TestTimelineConnection connection,
    StudioTimelineUpdate? update,
  ) async {
    final failed = channel.state.waitFor(
      (state) => state is ChatFailed<StudioTimelineFrame>,
    );
    connection.emit(update);
    return ((await failed) as ChatFailed<StudioTimelineFrame>).error;
  }

  test('patch 必须从已交付版本继续', () async {
    final transport = TestTimelineTransport();
    final ready = await open(transport);
    expect(
      await nextFailure(ready.channel, ready.connection, patch(9, 10)),
      isA<TimelineContinuityError>(),
    );
    await ready.channel.close();
  });

  test('patch 版本必须前进', () async {
    final transport = TestTimelineTransport();
    final ready = await open(transport);
    expect(
      await nextFailure(ready.channel, ready.connection, patch(3, 3)),
      isA<TimelineContinuityError>(),
    );
    await ready.channel.close();
  });

  test('跨订阅身份的 patch 不能被当作连续增量', () async {
    final transport = TestTimelineTransport();
    final ready = await open(transport);
    expect(
      await nextFailure(
        ready.channel,
        ready.connection,
        patch(3, 4, subscriptionId: 'other'),
      ),
      isA<TimelineContinuityError>(),
    );
    await ready.channel.close();
  });

  test('同 item 的 expectedRevision 不匹配即重同步', () async {
    final transport = TestTimelineTransport();
    final ready = await open(
      transport,
      initial: baseline(3, items: [timelineItem(7, id: 'stable')]),
    );
    expect(
      await nextFailure(
        ready.channel,
        ready.connection,
        patch(
          3,
          4,
          changes: [
            StudioTimelineUpdateItem(
              itemId: 'stable',
              expectedRevision: 6,
              revision: 8,
              omittedBytes: 0,
              saved: false,
              lifecycle: StudioTimelineLifecycle.streaming,
              fields: const [],
            ),
          ],
        ),
      ),
      isA<TimelineContinuityError>(),
    );
    await ready.channel.close();
  });

  test('同 revision 的预览补齐经生产 channel 与真实 applier 生效', () async {
    final transport = TestTimelineTransport();
    // 预览：正文 abcd（省略 4 字节），canonical revision 3。
    final preview = ThreadItemView(
      id: 'stable',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 7,
      revision: 3,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      bodyOmittedUnits: 4,
      // 预览尚未保存；权威帧的 saved 不得在展示侧凭空回退。
      saved: false,
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: 'abcd',
        attachments: const [],
        lifecycle: const StreamingThreadContentView(),
      ),
    );
    final ready = await open(
      transport,
      initial: baseline(
        3,
        items: [
          StudioTimelineItem(
            item: preview,
            saved: false,
            lifecycle: StudioTimelineLifecycle.streaming,
            omittedBytes: 4,
            details: const [],
          ),
        ],
      ),
    );
    final attempt = ready.channel.currentAttemptId;
    final delivered = ready.channel.state.waitFor(
      (state) => state.snapshot is StudioTimelinePatchFrame,
    );
    // core 允许预览被权威完整正文在同 revision 补齐：差量可以是 Append。
    ready.connection.emit(
      patch(
        3,
        4,
        changes: [
          StudioTimelineUpdateItem(
            itemId: 'stable',
            expectedRevision: 3,
            revision: 3,
            omittedBytes: 0,
            saved: false,
            lifecycle: StudioTimelineLifecycle.streaming,
            fields: const [
              StudioFieldUpdateView(
                field: ThreadTextFieldView(),
                change: AppendThreadFieldChangeView('efgh'),
                totalBytes: 8,
                previewBytes: 8,
              ),
            ],
          ),
        ],
      ),
    );
    final frame = (await delivered).snapshot! as StudioTimelinePatchFrame;
    // 只是尾部版本前进，不是重连：同一 attempt、没有连接关闭。
    expect(ready.channel.currentAttemptId, same(attempt));
    expect(ready.connection.closeCalls, 0);
    expect(frame.patch.from, 3);
    expect(frame.patch.to, 4);
    final change = frame.patch.changes.single as StudioTimelineUpdateItem;
    expect(change.expectedRevision, 3);
    expect(change.revision, 3);
    // 真实 applier：内容补齐、省略归零，身份/顺序不变。
    final applied = preview.applyFieldUpdates(
      fields: [
        for (final update in change.fields)
          ThreadFieldUpdateView(field: update.field, change: update.change),
      ],
      expectedRevision: change.expectedRevision,
      revision: change.revision,
      omittedUnits: change.omittedBytes,
      saved: change.saved,
      terminal: change.lifecycle == StudioTimelineLifecycle.terminal,
    )!;
    final text = applied.state as ThreadTextItemStateView;
    expect(text.text, 'abcdefgh');
    expect(applied.bodyOmittedUnits, 0);
    expect(applied.revision, 3);
    expect(applied.id, 'stable');
    expect(applied.ordinal, 7);
    expect(change.fields.single.totalBytes, 8);
    expect(change.fields.single.previewBytes, 8);
    await ready.channel.close();
  });

  test('终态身份接受可靠权威的更高 revision 修订，但不回退终态', () async {
    final transport = TestTimelineTransport();
    final terminalItem = ThreadItemView(
      id: 'stable',
      threadId: 'thread',
      turnId: 'turn-a',
      ordinal: 7,
      revision: 5,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      executionTerminal: true,
      saved: true,
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: 'abc',
        attachments: const [],
        lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
      ),
    );
    final ready = await open(
      transport,
      initial: baseline(
        3,
        items: [
          StudioTimelineItem(
            item: terminalItem,
            saved: true,
            lifecycle: StudioTimelineLifecycle.terminal,
            omittedBytes: 0,
            details: const [],
          ),
        ],
      ),
    );
    final delivered = ready.channel.state.waitFor(
      (state) => state.snapshot is StudioTimelinePatchFrame,
    );
    // 可靠权威 terminal 修订：仍然终态，正文扩展，Turn 关联重新绑定（Turn 不是 identity）。
    ready.connection.emit(
      patch(
        3,
        4,
        changes: [
          StudioTimelineUpdateItem(
            itemId: 'stable',
            expectedRevision: 5,
            revision: 6,
            omittedBytes: 0,
            saved: false,
            lifecycle: StudioTimelineLifecycle.terminal,
            itemShell: terminalItem.copyWith(turnId: 'turn-b', revision: 6),
            fields: const [
              StudioFieldUpdateView(
                field: ThreadTextFieldView(),
                change: AppendThreadFieldChangeView('def'),
                totalBytes: 6,
                previewBytes: 6,
              ),
            ],
          ),
        ],
      ),
    );
    final frame = (await delivered).snapshot! as StudioTimelinePatchFrame;
    final change = frame.patch.changes.single as StudioTimelineUpdateItem;
    final applied = terminalItem.applyFieldUpdates(
      fields: [
        for (final update in change.fields)
          ThreadFieldUpdateView(field: update.field, change: update.change),
      ],
      expectedRevision: change.expectedRevision,
      revision: change.revision,
      omittedUnits: change.omittedBytes,
      saved: change.saved,
      terminal: true,
      itemShell: change.itemShell,
    )!;
    expect((applied.state as ThreadTextItemStateView).text, 'abcdef');
    expect(applied.revision, 6);
    expect(applied.executionTerminal, isTrue);
    expect(applied.turnId, 'turn-b');
    expect(applied.saved, isFalse, reason: '新 revision 的保存水位独立推进');

    // 同一 revision 的保存确认随后合法到达。
    final confirm = applied.applyFieldUpdates(
      fields: const [],
      expectedRevision: 6,
      revision: 6,
      omittedUnits: 0,
      saved: true,
      terminal: true,
    )!;
    expect(confirm.saved, isTrue);
    expect(confirm.revision, 6);
    await ready.channel.close();
  });

  test('终态回退成 streaming、错 expectedRev 与版本倒退仍被拒', () async {
    final terminalItem = ThreadItemView(
      id: 'stable',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 7,
      revision: 5,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      executionTerminal: true,
      saved: true,
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: 'abc',
        attachments: const [],
        lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
      ),
    );
    // terminal -> streaming。
    expect(
      terminalItem.applyFieldUpdates(
        fields: const [],
        expectedRevision: 5,
        revision: 6,
        omittedUnits: 0,
        saved: false,
        terminal: false,
      ),
      isNull,
    );
    // expected revision 不匹配。
    expect(
      terminalItem.applyFieldUpdates(
        fields: const [],
        expectedRevision: 4,
        revision: 6,
        omittedUnits: 0,
        saved: false,
        terminal: true,
      ),
      isNull,
    );
    // 版本倒退。
    expect(
      terminalItem.applyFieldUpdates(
        fields: const [],
        expectedRevision: 5,
        revision: 4,
        omittedUnits: 0,
        saved: false,
        terminal: true,
      ),
      isNull,
    );
    // 同 revision 回退已保存事实 / 省略量回升。
    expect(
      terminalItem.applyFieldUpdates(
        fields: const [],
        expectedRevision: 5,
        revision: 5,
        omittedUnits: 0,
        saved: false,
        terminal: true,
      ),
      isNull,
    );
    final previewed = terminalItem.copyWith(bodyOmittedUnits: 1);
    expect(
      previewed.applyFieldUpdates(
        fields: const [],
        expectedRevision: 5,
        revision: 5,
        omittedUnits: 4,
        saved: true,
        terminal: true,
      ),
      isNull,
    );
  });

  test('同 revision 的保存确认是合法更新', () async {
    final transport = TestTimelineTransport();
    final ready = await open(
      transport,
      initial: baseline(3, items: [timelineItem(7, id: 'stable')]),
    );
    final delivered = ready.channel.state.waitFor(
      (state) => state.snapshot is StudioTimelinePatchFrame,
    );
    // 保存确认不伪造正文 revision：expected == 已知 7，revision 仍前进到 8 但字段全部
    // Unchanged；这里是「仅版本推进」的合法形状。
    ready.connection.emit(
      patch(
        3,
        4,
        changes: [
          StudioTimelineUpdateItem(
            itemId: 'stable',
            expectedRevision: 7,
            revision: 8,
            omittedBytes: 0,
            saved: true,
            lifecycle: StudioTimelineLifecycle.streaming,
            fields: const [
              StudioFieldUpdateView(
                field: ThreadTextFieldView(),
                change: UnchangedThreadFieldChangeView(),
                totalBytes: 4,
                previewBytes: 4,
              ),
            ],
          ),
        ],
      ),
    );
    final frame = (await delivered).snapshot! as StudioTimelinePatchFrame;
    final change = frame.patch.changes.single as StudioTimelineUpdateItem;
    expect(change.saved, isTrue);
    expect(change.fields.single.totalBytes, 4);
    await ready.channel.close();
  });

  test('真实 remove 即使不在连续性副本里也必须交付', () async {
    final transport = TestTimelineTransport();
    final ready = await open(
      transport,
      initial: baseline(3, items: [timelineItem(1, id: 'kept')]),
    );
    final delivered = ready.channel.state.waitFor(
      (state) => state.snapshot is StudioTimelinePatchFrame,
    );
    // 该身份从未出现在本连接的基线里（消费者可能通过页查询加载过它）。
    ready.connection.emit(
      patch(3, 4, changes: const [StudioTimelineRemove('paged-only')]),
    );
    final frame = (await delivered).snapshot! as StudioTimelinePatchFrame;
    final change = frame.patch.changes.single as StudioTimelineRemove;
    expect(change.itemId, 'paged-only');
    await ready.channel.close();
  });

  test('同连接重同步保留订阅身份并交付新基线', () async {
    final transport = TestTimelineTransport();
    final ready = await open(transport);
    final delivered = ready.channel.state.waitFor(
      (state) =>
          state.snapshot is StudioTimelineBaselineFrame &&
          (state.snapshot! as StudioTimelineBaselineFrame).isResync,
    );
    ready.connection.emit(
      StudioTimelineResync(
        subscriptionId: 'sub',
        reason: StudioTimelineResyncReason.lagging,
        baseline: baseline(11, items: [timelineItem(11, id: 'fresh')]),
      ),
    );
    final frame = (await delivered).snapshot! as StudioTimelineBaselineFrame;
    expect(frame.baseline.version, 11);
    expect(frame.baseline.items.single.id, 'fresh');
    expect(frame.resyncReason, StudioTimelineResyncReason.lagging);
    // 重同步后的补丁以新基线版本为 from。
    final next = ready.channel.state.waitFor(
      (state) => state.snapshot is StudioTimelinePatchFrame,
    );
    ready.connection.emit(
      patch(11, 12, changes: [StudioTimelineAdd(timelineItem(1, id: 'added'))]),
    );
    final patchFrame = (await next).snapshot! as StudioTimelinePatchFrame;
    expect(patchFrame.patch.from, 11);
    expect(patchFrame.patch.to, 12);
    await ready.channel.close();
  });

  test('新基线不能替换旧订阅身份', () async {
    final transport = TestTimelineTransport();
    final ready = await open(transport);
    expect(
      await nextFailure(
        ready.channel,
        ready.connection,
        StudioTimelineResync(
          subscriptionId: 'sub',
          reason: StudioTimelineResyncReason.unavailable,
          baseline: baseline(2, subscriptionId: 'other'),
        ),
      ),
      isA<TimelineContinuityError>(),
    );
    await ready.channel.close();
  });

  test('空批次也推进交付版本', () async {
    final transport = TestTimelineTransport();
    final ready = await open(transport);
    final delivered = ready.channel.state.waitFor(
      (state) => state.snapshot is StudioTimelinePatchFrame,
    );
    ready.connection.emit(patch(3, 4));
    final frame = (await delivered).snapshot! as StudioTimelinePatchFrame;
    expect(frame.patch.changes, isEmpty);
    expect(frame.patch.to, 4);
    await ready.channel.close();
  });

  test('EOF 不是正常结束，错误不会被吞成失败以外的形态', () async {
    final transport = TestTimelineTransport();
    final ready = await open(transport);
    expect(
      await nextFailure(ready.channel, ready.connection, null),
      isA<TimelineStreamEnded>(),
    );
    await ready.channel.close();
  });

  test('transport 抛出的错误保持原样到达观察者', () async {
    final transport = TestTimelineTransport();
    final ready = await open(transport);
    final failed = ready.channel.state.waitFor(
      (state) => state is ChatFailed<StudioTimelineFrame>,
    );
    final error = StateError('bridge failure');
    ready.connection.emitStreamError(error);
    final state = (await failed) as ChatFailed<StudioTimelineFrame>;
    expect(state.error, same(error));
    await ready.channel.close();
  });

  test('消费 gate 前 ACK 不发生，成功后才确认投送序号', () async {
    final transport = TestTimelineTransport();
    final channel = timelineChannel(transport);
    final frames = <StudioTimelineFrame>[];
    final gate = Completer<void>();
    channel.attachConsumer((frame) async {
      frames.add(frame);
      await gate.future;
    });
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(connection);
    await channel.ready;
    await pumpEventQueue();
    // 基线已交付消费者，但 gate 未放行：不 ACK。
    expect(frames.single, isA<StudioTimelineBaselineFrame>());
    expect(connection.acks, isEmpty);
    gate.complete();
    await pumpEventQueue();
    expect(connection.acks, [1]);
    await channel.close();
  });

  test('消费者错误不 ACK 且不自动重试，typed cause 保留', () async {
    final transport = TestTimelineTransport();
    final channel = timelineChannel(transport);
    final failure = StateError('controller write failed');
    channel.attachConsumer((frame) async {
      throw failure;
    });
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(connection);
    final failed = channel.state.waitFor(
      (state) => state is ChatFailed<StudioTimelineFrame>,
    );
    final state = (await failed) as ChatFailed<StudioTimelineFrame>;
    expect(state.error, same(failure));
    expect(connection.acks, isEmpty);
    // 消费者错误不进入观察重试：没有第二次 open。
    await pumpEventQueue();
    expect(transport.opens, hasLength(1));
    await channel.close();
    expect(connection.closeCalls, 1);
  });

  test('第二个活动消费者是 typed Conflict，不覆盖原回调', () async {
    final transport = TestTimelineTransport();
    final channel = timelineChannel(transport);
    final first = channel.attachConsumer((_) {});
    expect(
      () => channel.attachConsumer((_) {}),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.conflict,
        ),
      ),
    );
    // 旧 lease 仍活动；关闭后可重新登记。
    first.requestClose();
    final second = channel.attachConsumer((_) {});
    second.requestClose();
  });

  test('同步 Ready 观察者重绑不会把旧 attempt 正文交给新消费者', () async {
    final transport = TestTimelineTransport();
    final channel = StudioTimelineChannel(
      threadId: 'thread',
      transport: transport,
    );
    final frames = <StudioTimelineFrame>[];
    TimelineConsumerLease? lease;
    final observation = channel.state.watch((state) {
      // LatestValue.publish 同步调用观察者：attach 在 Ready 发布内重入。
      if (state is ChatReady<StudioTimelineFrame> && lease == null) {
        lease = channel.attachConsumer(frames.add);
      }
    });
    addTearDown(() async {
      observation.cancel();
      for (final opening in transport.opens) {
        if (!opening.isCompleted) {
          opening.complete(
            TestTimelineConnection(
              initial: baseline(2, subscriptionId: 'new-attempt'),
            ),
          );
        }
      }
      final closing = channel.close();
      lease?.requestClose();
      await closing;
    });

    channel.start();
    final first = TestTimelineConnection(
      initial: baseline(1, subscriptionId: 'old-attempt'),
    );
    transport.opens.single.complete(first);
    await first.subscribed.future;
    await pumpEventQueue();

    expect(
      transport.opens,
      hasLength(2),
      reason: '重入 attach 必须退役已在消费的 attempt 并刷新',
    );
    expect(
      frames,
      isEmpty,
      reason: '新消费者必须等待自己的新 opening 基线，不能收到退役 attempt 的正文',
    );
  });

  test('镜像监听者同步关闭后，本帧不给 closing handle ACK', () async {
    final transport = TestTimelineTransport();
    final channel = StudioTimelineChannel(
      threadId: 'thread',
      transport: transport,
    );
    final observation = channel.state.watch((state) {
      if (state is ChatReady<StudioTimelineFrame>) {
        unawaited(channel.close());
      }
    });
    addTearDown(observation.cancel);
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(1));
    transport.opens.single.complete(connection);
    await channel.state.waitFor(
      (state) => state is ChatClosed<StudioTimelineFrame>,
    );
    await pumpEventQueue();
    // 关闭在镜像发布内同步发生：返回后的正文/ACK 准入必须重新核对 attempt。
    expect(connection.acks, isEmpty, reason: 'closing handle 不再收到 ACK');
    expect(connection.requestCloseCalls, greaterThan(0));
  });

  test('镜像监听者同步 setDemand(false) 后，本帧不给已暂停 handle ACK', () async {
    final transport = TestTimelineTransport();
    final channel = StudioTimelineChannel(
      threadId: 'thread',
      transport: transport,
    );
    final observation = channel.state.watch((state) {
      if (state is ChatReady<StudioTimelineFrame>) {
        channel.setDemand(false);
      }
    });
    addTearDown(observation.cancel);
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(1));
    transport.opens.single.complete(connection);
    await pumpEventQueue();
    expect(connection.acks, isEmpty, reason: 'demand 已在发布内同步移除，本帧不能继续 ACK');
    await channel.close();
  });

  test('首基线未被消费时 attach 承接同一 opening，不重复 open', () async {
    final transport = TestTimelineTransport();
    final channel = timelineChannel(transport);
    final frames = <StudioTimelineFrame>[];
    channel.start();
    // open 已登记但尚未完成：attach 不制造第二个 open，也不另造平行句柄。
    channel.attachConsumer(frames.add);
    expect(transport.opens, hasLength(1));
    final connection = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(connection);
    await channel.ready;
    await pumpEventQueue();
    // 消费者直接收到该 opening 的首个基线，并按序确认。
    expect(frames, hasLength(1));
    expect(frames.single, isA<StudioTimelineBaselineFrame>());
    expect(connection.acks, [1]);
    expect(transport.opens, hasLength(1));
    await channel.close();
  });

  test('非 retryable typed 失败不进入观察重试：没有第二次 open', () async {
    final transport = TestTimelineTransport();
    final channel = StudioTimelineChannel(
      threadId: 'thread',
      transport: transport,
      retryPolicy: const RetryPolicy(delays: [Duration.zero]),
    );
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(connection);
    await channel.ready;
    await pumpEventQueue();
    final failed = channel.state.waitFor(
      (state) => state is ChatFailed<StudioTimelineFrame>,
    );
    connection.emitFailure(
      const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'native rejected the observation',
        retryable: false,
        correlationId: 'nonretryable-regression',
      ),
    );
    final state = (await failed) as ChatFailed<StudioTimelineFrame>;
    expect(
      (state.error as StudioFailure).code,
      StudioFailureCode.invalidArgument,
    );
    expect(
      state.snapshot,
      isA<StudioTimelineBaselineFrame>(),
      reason: 'last-known 保留',
    );
    // Duration.zero 重试若被错误调度会立即 open：等待真实 timer 轮转后仍只有一次。
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();
    expect(
      transport.opens,
      hasLength(1),
      reason: '非 retryable typed 失败绝不自动循环（错误矩阵）',
    );
    await channel.close();
  });

  test('closing/closed 拒绝新 consumer lease：Cancelled 优先于 Conflict', () async {
    final transport = TestTimelineTransport();
    final channel = timelineChannel(transport);
    channel.start();
    final connection = TestTimelineConnection(initial: baseline(3));
    transport.opens.single.complete(connection);
    // opening 阶段（首基线未消费）attach 不触发刷新；关闭准入仍然优先。
    final active = channel.attachConsumer((_) {});
    final closing = channel.close();
    expect(
      () => channel.attachConsumer((_) {}),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
      reason: 'closing 中拒绝新 lease',
    );
    await closing;
    expect(
      () => channel.attachConsumer((_) {}),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
      reason: 'closed 后拒绝新 lease',
    );
    await active.close();
  });

  test('后续消费者回调在途时 retryCleanup 不释放许可，gate 放行后才 Clean', () async {
    final transport = TestTimelineTransport();
    final channel = timelineChannel(transport);
    final releaseSecond = Completer<void>();
    var deliveries = 0;

    channel.start();
    final connection = TestTimelineConnection(initial: baseline(1));
    transport.opens.single.complete(connection);
    channel.attachConsumer((frame) async {
      deliveries++;
      // 首帧回调立即完成；第二帧回调挂起，模拟真实 controller 写入屏障。
      if (deliveries == 2) await releaseSecond.future;
    });
    await channel.ready;
    await pumpEventQueue();
    expect(connection.acks, [1]);

    connection.emit(patch(1, 2));
    await pumpEventQueue();
    // 第二帧回调在途：ACK 未发生，首个 handoff 已完成并让位。
    expect(connection.acks, [1]);

    // requestClose 同步抛出（port 不保证不抛）：close 同步退役路径把它记为
    // cleanupError，真实 join 仍继续。close 等待任务时短暂超时，attempt 留存。
    connection.requestCloseFailure = const StudioFailure(
      code: StudioFailureCode.internal,
      message: 'request close rejected',
      retryable: false,
      correlationId: 'b4-request-close-throws',
    );
    final closing = channel.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 5)),
    );
    await closing;
    expect(connection.requestCloseCalls, greaterThan(0));

    // 外部只重试原生收束：后续（非首个）消费者回调仍在途时不得释放许可。
    final retrying = channel.retryCleanup();
    await pumpEventQueue();
    expect(
      channel.ownedAttemptCount,
      greaterThan(0),
      reason: '在途消费者回调真实结束前，chatHandle 许可仍由原 attempt 持有',
    );

    releaseSecond.complete();
    final retryReport = await retrying;
    expect(channel.ownedAttemptCount, 0, reason: '回调收束且 join Clean 后释放');
    expect(
      (await closing).unresolved,
      isNotEmpty,
      reason: 'deadline 超时时在途回调尚未收束，close 报告保留 unresolved',
    );
    expect(retryReport.unresolved, isEmpty);
  });

  test('已有 demand 时重绑消费者强制新 attempt 与新 baseline', () async {
    final transport = TestTimelineTransport();
    final channel = timelineChannel(transport);
    channel.start();
    final first = TestTimelineConnection(
      initial: baseline(3, subscriptionId: 'sub-1'),
    );
    transport.opens.single.complete(first);
    await channel.ready;
    await pumpEventQueue();
    expect(first.acks, [1]);

    final frames = <StudioTimelineFrame>[];
    channel.attachConsumer(frames.add);
    // attach 时当前 attempt 已交付基线：必须刷新为新订阅。
    await channel.state.waitFor(
      (state) => state is ChatOpening<StudioTimelineFrame>,
    );
    final second = TestTimelineConnection(
      initial: baseline(5, subscriptionId: 'sub-2'),
    );
    transport.opens[1].complete(second);
    await channel.ready;
    await pumpEventQueue();
    expect(frames.single, isA<StudioTimelineBaselineFrame>());
    expect(
      (frames.single as StudioTimelineBaselineFrame).baseline.subscriptionId,
      'sub-2',
    );
    expect(second.acks, [1]);
    await channel.close();
    await first.closeCompleted.future;
  });

  test('暂停 latest 观察不影响正文消费者顺序', () async {
    final transport = TestTimelineTransport();
    final channel = timelineChannel(transport);
    final received = <int>[];
    channel.attachConsumer((frame) {
      if (frame is StudioTimelinePatchFrame) received.add(frame.patch.to);
    });
    channel.start();
    final connection = TestTimelineConnection(
      initial: baseline(3, items: [timelineItem(1, id: 'kept')]),
    );
    transport.opens.single.complete(connection);
    await channel.ready;
    final stateObservation = channel.state.watch((_) {});
    stateObservation.pause();
    connection.emit(patch(3, 4, changes: const []));
    connection.emit(patch(4, 5, changes: const []));
    connection.emit(patch(5, 6, changes: const []));
    await channel.state.waitFor(
      (state) => state.snapshot is StudioTimelinePatchFrame,
    );
    await pumpEventQueue();
    expect(received, [4, 5, 6]);
    stateObservation.cancel();
    await channel.close();
  });
}
