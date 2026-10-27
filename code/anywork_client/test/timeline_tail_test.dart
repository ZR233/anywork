import 'package:anywork_client/anywork_client.dart';
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
    await connection.nextStarted.future;
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
    final history = frame.baseline;
    expect(history.version, 11);
    expect(history.items.single.id, 'fresh');
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
    ready.connection.emitError(error);
    final state = (await failed) as ChatFailed<StudioTimelineFrame>;
    expect(state.error, same(error));
    await ready.channel.close();
  });
}
