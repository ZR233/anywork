import 'dart:async';

import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/domain/models/timeline_presentation.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 展示 owner 的缺陷敏感度：每代次新 controller/key、History 冻结、
/// 显式回实时新订阅首帧成功后才换代次、发送准备不改动其他 Thread、
/// 以及关闭所依赖的真实卸载释放（design/26 §26.3、§26.8）。
///
/// 这里用脚本化 transport，只模拟生命周期交错；owner、SDK 内容泵与 stock controller
/// 都是生产实现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StudioTimelineItem text(
    String id,
    int revision, {
    String body = 'body',
    int? ordinal,
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: ordinal ?? revision,
      revision: revision,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: body,
        attachments: const [],
        lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
      ),
    ),
    saved: false,
    lifecycle: StudioTimelineLifecycle.terminal,
    omittedBytes: 0,
    details: const [],
  );

  /// 一条可发送 Thread 的最小 workspace 快照：展示准备与冻结发送只依赖 route 与 thread。
  ThreadWorkspace workspaceFor(String threadId) => ThreadWorkspace(
    thread: _thread(threadId),
    revision: 1,
    interactions: const [],
    runtime: const ThreadRuntimeView(
      modelId: 'alpha',
      contextTokens: 0,
      contextWindow: 100,
      totalTokens: 0,
      costLabel: '',
      activeSkills: [],
      activeMcpServers: [],
      activeLspServers: [],
      modelRoute: ThreadModelRouteView(
        accountId: 'account',
        modelId: 'alpha',
        effort: 'medium',
        revision: 1,
        available: true,
      ),
    ),
  );

  /// 显式顺序、保存与终态事实的条目：用于验证权威 `Add` 的收敛与有序插入。
  StudioTimelineItem item({
    required String id,
    required int revision,
    required int ordinal,
    String body = 'body',
    bool saved = false,
    bool terminal = false,
    int omitted = 0,
    List<StudioTimelineDetailRef> details = const [],
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: ordinal,
      revision: revision,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      bodyOmittedUnits: omitted,
      executionTerminal: terminal,
      saved: saved,
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: body,
        attachments: const [],
        lifecycle: terminal
            ? CompletedThreadContentView(DateTime.utc(2026))
            : const StreamingThreadContentView(),
      ),
    ),
    saved: saved,
    lifecycle: terminal
        ? StudioTimelineLifecycle.terminal
        : StudioTimelineLifecycle.streaming,
    omittedBytes: omitted,
    details: details,
  );

  Future<
    ({
      AnyworkClient client,
      TimelineSessionOwner owner,
      _ScriptedTransport transport,
      _ScriptedConnection connection,
    })
  >
  open({List<StudioTimelineItem>? items, List<StudioThread>? threads}) async {
    final transport = _ScriptedTransport()..baselineItems = items;
    final client = AnyworkClient(transport: transport, clientId: 'owner');
    addTearDown(
      () => client.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    client.selection.markOpened();
    client.threadDirectory.applyBaseline(
      ThreadDirectoryPage(threads: threads ?? [_thread()], revision: 1),
      revision: 1,
    );
    final owner = TimelineSessionOwner(client: client);
    client.workspace.selectThread('thread', projectId: 'project');
    final connection = transport.connections.single;
    await owner.source.waitFor((state) => state?.generation != 0);
    return (
      client: client,
      owner: owner,
      transport: transport,
      connection: connection,
    );
  }

  test(
    'the first baseline becomes exactly one live display generation',
    () async {
      final ready = await open();
      final view = ready.owner.source.value!;
      final lease = ready.owner.lease('thread')!;
      expect(view.mode, TimelineDisplayMode.live);
      expect(view.generation, lease.generation);
      expect(view.connection, TimelineConnectionPhase.ready);
      expect(
        [for (final message in lease.controller.messages) message.id],
        ['a', 'b'],
      );
      expect(ready.connection.initialCalls, 1);
      expect(ready.connection.nextCalls, 1);
    },
  );

  test(
    'history freezes the displayed set and only reports new output',
    () async {
      final ready = await open();
      final lease = ready.owner.lease('thread')!;
      final frozen = [...lease.controller.messages];
      final applied = lease.appliedVersion!;
      await ready.owner.dispatch('thread', const TimelineEnterHistory());
      expect(ready.owner.source.value!.mode, TimelineDisplayMode.history);

      ready.connection.emit(
        StudioTimelinePatch(
          subscriptionId: 'sub',
          from: applied,
          to: applied + 1,
          changes: const [StudioTimelineRemove('a')],
          priority: StudioTimelinePriority.immediate,
        ),
      );
      await ready.owner.source.waitFor((state) => state?.hasNewOutput == true);
      expect(lease.controller.messages, frozen);
      expect(lease.appliedVersion, applied, reason: '冻结水位不随后台输出前进');
    },
  );

  test(
    'explicit return to live waits for a fresh baseline before switching',
    () async {
      final ready = await open();
      final first = ready.owner.lease('thread')!;
      await ready.owner.dispatch('thread', const TimelineEnterHistory());

      ready.transport.holdNextOpen = true;
      final switching = ready.owner.returnToLive('thread');
      await ready.owner.source.waitFor((state) => state!.isPreparingLive);
      expect(
        ready.owner.lease('thread'),
        same(first),
        reason: '新首帧成功前旧 History 必须留在屏幕上',
      );
      expect(ready.owner.source.value!.mode, TimelineDisplayMode.history);

      ready.transport.completeOpen(version: 11);
      await switching;
      final second = ready.owner.lease('thread')!;
      expect(second, isNot(same(first)));
      expect(second.generation, greaterThan(first.generation));
      expect(second.chatKey, isNot(first.chatKey));
      expect(ready.owner.source.value!.mode, TimelineDisplayMode.live);
      expect(ready.owner.source.value!.isPreparingLive, isFalse);
      expect(first.isReleased, isTrue, reason: '未挂载的旧代次直接释放');
    },
  );

  test('send preparation never steals another thread display', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    await ready.owner.prepareSend('other-thread');
    expect(ready.owner.lease('thread'), same(lease));
    expect(ready.owner.source.value!.isPreparingLive, isFalse);
    expect(ready.transport.opens, 1);
  });

  test('a failing live preparation keeps the frozen display and surfaces the error', () async {
    final ready = await open();
    final frozenLease = ready.owner.lease('thread')!;
    await ready.owner.dispatch('thread', const TimelineEnterHistory());
    final failure = StudioFailure(
      code: StudioFailureCode.storage,
      message: 'first frame failed',
      retryable: true,
      correlationId: 'test',
    );
    // 打开与重试都失败：连接最终进入 failed，准备必须以同一 typed 错误收束。
    ready.transport.failOpens = failure;
    final preparing = ready.owner.prepareSend('thread');
    await expectLater(preparing, throwsA(same(failure)));
    ready.transport.failOpens = null;
    expect(ready.owner.lease('thread'), same(frozenLease));
    expect(ready.owner.source.value!.mode, TimelineDisplayMode.history);
    expect(ready.owner.source.value!.isPreparingLive, isFalse);
    expect(ready.owner.source.value!.connectionError, isNotNull);
  });

  test('同 revision 的预览补齐经生产 owner/applier 生效且不换代次', () async {
    final preview = ThreadItemView(
      id: 'preview',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 3,
      revision: 3,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      bodyOmittedUnits: 4,
      saved: false,
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: 'abcd',
        attachments: const [],
        lifecycle: const StreamingThreadContentView(),
      ),
    );
    final ready = await open(
      items: [
        StudioTimelineItem(
          item: preview,
          saved: false,
          lifecycle: StudioTimelineLifecycle.streaming,
          omittedBytes: 4,
          details: [
            StudioTimelineDetailRef(
              field: const ThreadTextFieldView(),
              revision: 3,
              totalBytes: 8,
              previewBytes: 4,
            ),
          ],
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final generation = lease.generation;
    final applied = lease.appliedVersion!;
    final subscription = 'sub-${ready.connection.baselineVersion}';
    final change = StudioTimelineUpdateItem(
      itemId: 'preview',
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
    );
    final manual = timelinePayloadOf(lease.controller.messages.single)!
        .applyUpdate(change);
    expect(
      manual == null
          ? null
          : (manual.item.state as ThreadTextItemStateView).text,
      'abcdefgh',
      reason: '真实 applier 必须接受同 revision 的预览补齐',
    );
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: subscription,
        from: applied,
        to: applied + 1,
        changes: [change],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    final attempt = ready.client.session('thread').timeline.currentAttemptId;
    await _until(() => lease.appliedVersion == applied + 1);
    // 连接没有重连：同一 attempt、仍处于 ready、未请求关闭。
    expect(
      ready.client.session('thread').timeline.state.value,
      isA<ChatReady<StudioTimelineFrame>>(),
    );
    expect(ready.client.session('thread').timeline.currentAttemptId, attempt);
    final payload = timelinePayloadOf(lease.controller.messages.single)!;
    expect((payload.item.state as ThreadTextItemStateView).text, 'abcdefgh');
    expect(payload.item.bodyOmittedUnits, 0);
    expect(payload.id, 'preview');
    expect(payload.item.ordinal, 3);
    expect(
      payload.detailFor(const ThreadTextFieldView())!.previewBytes,
      8,
      reason: '详情引用随该字段本帧提交更新',
    );
    expect(lease.generation, generation, reason: '不重连、不换代次');
    expect(ready.owner.lease('thread'), same(lease));
    expect(ready.connection.closeCalls, 0);
  });

  test('终态条目接受可靠权威的更高 revision 修订并随后保存', () async {
    final terminalItem = ThreadItemView(
      id: 'done',
      threadId: 'thread',
      turnId: 'turn-a',
      ordinal: 4,
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
      items: [
        StudioTimelineItem(
          item: terminalItem,
          saved: true,
          lifecycle: StudioTimelineLifecycle.terminal,
          omittedBytes: 0,
          details: const [],
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    final subscription = 'sub-${ready.connection.baselineVersion}';

    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: subscription,
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineUpdateItem(
            itemId: 'done',
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
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    final updated = timelinePayloadOf(lease.controller.messages.single)!;
    expect((updated.item.state as ThreadTextItemStateView).text, 'abcdef');
    expect(updated.item.revision, 6);
    expect(updated.terminal, isTrue);
    expect(updated.item.turnId, 'turn-b', reason: 'Turn 关联不是 identity');
    expect(updated.saved, isFalse);

    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: subscription,
        from: applied + 1,
        to: applied + 2,
        changes: const [
          StudioTimelineUpdateItem(
            itemId: 'done',
            expectedRevision: 6,
            revision: 6,
            omittedBytes: 0,
            saved: true,
            lifecycle: StudioTimelineLifecycle.terminal,
            fields: [],
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 2);
    final saved = timelinePayloadOf(lease.controller.messages.single)!;
    expect(saved.saved, isTrue);
    expect(saved.item.revision, 6);
  });

  test('终态回退成 streaming 的帧触发显式重同步而不是被应用', () async {
    final terminalItem = ThreadItemView(
      id: 'done',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 4,
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
      items: [
        StudioTimelineItem(
          item: terminalItem,
          saved: true,
          lifecycle: StudioTimelineLifecycle.terminal,
          omittedBytes: 0,
          details: const [],
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: const [
          StudioTimelineUpdateItem(
            itemId: 'done',
            expectedRevision: 5,
            revision: 6,
            omittedBytes: 0,
            saved: false,
            // 已交付身份是终态：回退成 streaming 必须被拒。
            lifecycle: StudioTimelineLifecycle.streaming,
            fields: [],
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    // owner 无法应用该身份 → 显式刷新内容连接（新 attempt），不把错误当成功。
    await _until(() => ready.transport.opens > 1);
    final current = ready.owner.lease('thread')!;
    expect(current, isNot(same(lease)));
    final shown = timelinePayloadOf(current.controller.messages.single)!;
    expect(shown.terminal, isTrue, reason: '非法帧不改变已展示的终态事实');
    expect(shown.id, 'done');
    expect(lease.appliedVersion, applied, reason: '非法帧不推进展示水位');
  });

  test(
    'paging shares one future, prepends older messages and keeps them distinct',
    () async {
      final ready = await open();
      final lease = ready.owner.lease('thread')!;
      final watermark = lease.appliedVersion!;
      final page = Completer<StudioTimelinePage>();
      ready.connection.pageResult = page;
      final loading = ready.owner.loadOlder('thread');
      expect(ready.owner.loadOlder('thread'), same(loading));
      expect(ready.owner.source.value!.isLoadingOlder, isTrue);
      page.complete(
        StudioTimelinePage(
          // 页游标之前的真实边界：ordinal 严格早于已覆盖范围的下界。
          items: [text('older', 1, ordinal: 0), text('a', 2)],
          before: 'tlp1.older',
          hasOlder: true,
        ),
      );
      await loading;
      // 重叠身份 'a' 不重复插入；分页不抬高内容水位。
      expect(
        [for (final message in lease.controller.messages) message.id],
        ['older', 'a', 'b'],
      );
      expect(ready.owner.source.value!.olderCursor, 'tlp1.older');
      expect(ready.owner.source.value!.hasOlder, isTrue);
      expect(lease.appliedVersion, watermark, reason: '分页不抬高冻结展示的内容水位');
    },
  );

  test('a page reply for a retired generation is dropped', () async {
    final ready = await open();
    final first = ready.owner.lease('thread')!;
    final page = Completer<StudioTimelinePage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder('thread');
    expect(ready.owner.source.value!.isLoadingOlder, isTrue);

    // 显式回实时建立新代次：旧代次的页回包不得写新展示。
    ready.transport.holdNextOpen = true;
    final switching = ready.owner.returnToLive('thread');
    await ready.owner.source.waitFor((state) => state!.isPreparingLive);
    page.complete(
      StudioTimelinePage(
        items: [text('stale', 1)],
        before: 'tlp1.stale',
        hasOlder: true,
      ),
    );
    await loading;
    ready.transport.completeOpen(version: 21);
    await switching;
    final second = ready.owner.lease('thread')!;
    expect(second, isNot(same(first)));
    expect(
      [for (final message in second.controller.messages) message.id],
      ['a', 'b'],
      reason: '旧代次的页结果不能前插到新代次',
    );
    await first.released;
    expect(first.isReleased, isTrue);
  });

  test(
    'page failures keep content, close loading and expose a retry',
    () async {
      final ready = await open();
      final lease = ready.owner.lease('thread')!;
      final page = Completer<StudioTimelinePage>();
      ready.connection.pageResult = page;
      final loading = ready.owner.loadOlder('thread');
      page.completeError(
        const StudioFailure(
          code: StudioFailureCode.storage,
          message: 'read failed',
          retryable: true,
          correlationId: 'test',
        ),
      );
      await loading;
      expect(ready.owner.source.value!.isLoadingOlder, isFalse);
      expect(ready.owner.source.value!.olderError, isA<StudioFailure>());
      expect(lease.controller.messages, isNotEmpty);

      final retried = Completer<StudioTimelinePage>();
      ready.connection.pageResult = retried;
      final retrying = ready.owner.retryOlder('thread');
      expect(ready.owner.source.value!.olderError, isNull);
      retried.complete(
        const StudioTimelinePage(items: [], before: null, hasOlder: false),
      );
      await retrying;
      expect(ready.owner.source.value!.hasOlder, isFalse);
    },
  );

  test('已加载身份收到更高 revision 的权威 Add 时原位收敛而不重插', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final loaded = lease.controller.messages.firstWhere(
      (message) => message.id == 'a',
    );
    final operations = <ChatOperation>[];
    final subscription = lease.controller.operationsStream.listen(
      operations.add,
    );
    addTearDown(subscription.cancel);
    var applied = lease.appliedVersion!;
    String subscriptionId() => 'sub-${ready.connection.baselineVersion}';

    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: subscriptionId(),
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            item(
              id: 'a',
              revision: 7,
              ordinal: 1,
              body: 'body-a 已补齐',
              saved: true,
              terminal: true,
            ),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b'],
      reason: '稳定身份与位置：不 remove/reinsert、不追加成最新消息',
    );
    final payload = timelinePayloadOf(lease.controller.messages.first)!;
    expect((payload.item.state as ThreadTextItemStateView).text, 'body-a 已补齐');
    expect(payload.revision, 7);
    expect(payload.saved, isTrue, reason: '更高 revision 采纳它自己的保存事实');
    expect(payload.item.ordinal, 1);
    expect(
      operations.where(
        (operation) =>
            operation.type == ChatOperationType.insert ||
            operation.type == ChatOperationType.insertAll ||
            operation.type == ChatOperationType.remove,
      ),
      isEmpty,
      reason: '已加载身份只能原位 update',
    );
    expect(
      operations
          .where((operation) => operation.type == ChatOperationType.update)
          .single
          .oldMessage,
      same(loaded),
    );

    // 新 revision 的保存水位来自它自己，不从本地旧水位补出来。
    applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: subscriptionId(),
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            item(
              id: 'a',
              revision: 8,
              ordinal: 1,
              body: 'body-a 再次修订',
              saved: false,
              terminal: true,
            ),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    final revised = timelinePayloadOf(lease.controller.messages.first)!;
    expect(revised.revision, 8);
    expect(revised.saved, isFalse, reason: '旧 saved 水位不补到新 revision');
    expect(ready.connection.closeCalls, 0, reason: '不重连、不换代次');
    expect(ready.owner.lease('thread'), same(lease));
  });

  test('更旧 revision 的权威 Add 不覆盖已加载事实', () {
    // 尾部 `Add` 若携带更旧 revision，展示侧保持已加载事实，不 remove 也不回退；
    // 顺序身份被改写时同样是无法证明的事实（必须显式重同步）。
    final loaded = TimelineMessagePayload.fromItem(
      item(id: 'b', revision: 3, ordinal: 2, body: '新正文', saved: true),
    );
    final stale = item(id: 'b', revision: 1, ordinal: 2, body: '过期的旧正文');
    expect(identical(loaded.applyAdd(stale), loaded), isTrue);
    final noChange = loaded.applyAdd(
      item(id: 'b', revision: 3, ordinal: 2, body: '新正文', saved: true),
    );
    expect(noChange, isNotNull);
    expect(noChange!.revision, 3);
    expect(
      (noChange.item.state as ThreadTextItemStateView).text,
      '新正文',
      reason: '已加载事实不被回退',
    );
    expect(
      loaded.applyAdd(item(id: 'b', revision: 4, ordinal: 9, body: '新正文')),
      isNull,
      reason: 'canonical 顺序身份不允许被权威副本改写',
    );
  });

  test('同 revision 的权威 Add 取更完整预览且保存/终态不回退', () async {
    final ready = await open(
      items: [
        item(
          id: 'preview',
          revision: 2,
          ordinal: 2,
          body: 'abcd',
          omitted: 4,
          details: const [
            StudioTimelineDetailRef(
              field: ThreadTextFieldView(),
              revision: 2,
              totalBytes: 8,
              previewBytes: 4,
            ),
          ],
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            item(
              id: 'preview',
              revision: 2,
              ordinal: 2,
              body: 'abcdefgh',
              saved: true,
              terminal: true,
              details: const [
                StudioTimelineDetailRef(
                  field: ThreadTextFieldView(),
                  revision: 2,
                  totalBytes: 8,
                  previewBytes: 8,
                ),
              ],
            ),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    final payload = timelinePayloadOf(lease.controller.messages.single)!;
    expect((payload.item.state as ThreadTextItemStateView).text, 'abcdefgh');
    expect(payload.item.bodyOmittedUnits, 0);
    expect(payload.saved, isTrue);
    expect(payload.terminal, isTrue);
    expect(payload.detailFor(const ThreadTextFieldView())!.previewBytes, 8);
    expect(payload.id, 'preview');
    expect(ready.connection.closeCalls, 0);
  });

  test('同 revision 的权威 Add 无法证明兼容时显式重同步', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            item(id: 'a', revision: 1, ordinal: 1, body: '完全不同的正文'),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => ready.transport.opens == 2);
    final replacement = ready.owner.lease('thread')!;
    expect(replacement, isNot(same(lease)));
    expect(
      [for (final message in replacement.controller.messages) message.id],
      ['a', 'b'],
      reason: '重同步建立新基线，旧代次内容不拼进新代次',
    );
  });

  test('已覆盖范围内的新身份按 canonical 顺序插入', () async {
    final ready = await open(
      items: [
        item(id: 'a', revision: 1, ordinal: 1, body: 'body-a'),
        item(id: 'c', revision: 3, ordinal: 3, body: 'body-c'),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    final operations = <ChatOperation>[];
    final subscription = lease.controller.operationsStream.listen(
      operations.add,
    );
    addTearDown(subscription.cancel);
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            item(id: 'b', revision: 2, ordinal: 2, body: 'body-b'),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b', 'c'],
      reason: '不把已覆盖范围内的新身份追加成最新消息',
    );
    final insert = operations.singleWhere(
      (operation) => operation.type == ChatOperationType.insert,
    );
    expect(insert.index, 1);
    expect(ready.connection.closeCalls, 0);
  });

  test('更早且未覆盖的新身份不插入也不反复重同步', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    var applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            item(id: 'older', revision: 1, ordinal: 0, body: '更早正文'),
          ),
          StudioTimelineUpdateItem(
            itemId: 'older',
            expectedRevision: 1,
            revision: 4,
            omittedBytes: 0,
            saved: false,
            lifecycle: StudioTimelineLifecycle.streaming,
            itemShell: item(
              id: 'older',
              revision: 4,
              ordinal: 0,
              body: '更早正文',
            ).item,
            fields: const [
              StudioFieldUpdateView(
                field: ThreadTextFieldView(),
                change: AppendThreadFieldChangeView(' 继续'),
                totalBytes: 16,
                previewBytes: 16,
              ),
            ],
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b'],
      reason: '分页前缀的更早身份不在尾部提前插入',
    );
    expect(ready.transport.opens, 1, reason: '有意忽略的更早身份不得反复重建代次');
    expect(ready.owner.lease('thread'), same(lease));

    // 后续页读取当时的权威值。
    applied = lease.appliedVersion!;
    final page = Completer<StudioTimelinePage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder('thread');
    page.complete(
      StudioTimelinePage(
        items: [item(id: 'older', revision: 5, ordinal: 0, body: '后续页的权威正文')],
        before: 'tlp1.older',
        hasOlder: false,
      ),
    );
    await loading;
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['older', 'a', 'b'],
    );
    final payload = timelinePayloadOf(lease.controller.messages.first)!;
    expect(payload.revision, 5);
    expect((payload.item.state as ThreadTextItemStateView).text, '后续页的权威正文');
    expect(lease.appliedVersion, applied, reason: '分页不抬高内容水位');
  });

  test('真实删除最早行后覆盖边界仍在，更早身份仍不插入', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: const [StudioTimelineRemove('a'), StudioTimelineRemove('b')],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(lease.controller.messages, isEmpty);

    final watermark = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: watermark,
        to: watermark + 1,
        changes: [
          StudioTimelineAdd(
            item(id: 'deleted-floor', revision: 1, ordinal: 0, body: '更早正文'),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == watermark + 1);
    expect(lease.controller.messages, isEmpty, reason: '删除行不抹掉已覆盖范围的下界');
    expect(ready.transport.opens, 1);

    final page = Completer<StudioTimelinePage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder('thread');
    page.complete(
      StudioTimelinePage(
        items: [
          item(id: 'deleted-floor', revision: 6, ordinal: 0, body: '权威正文'),
        ],
        before: null,
        hasOlder: false,
      ),
    );
    await loading;
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['deleted-floor'],
    );
    expect(timelinePayloadOf(lease.controller.messages.single)!.revision, 6);
  });

  test('新代次从自身空闲分页状态开始，旧页回包不能污染新代次', () async {
    final ready = await open();
    final first = ready.owner.lease('thread')!;
    final page = Completer<StudioTimelinePage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder('thread');
    expect(ready.owner.source.value!.isLoadingOlder, isTrue);

    ready.transport.holdNextOpen = true;
    final switching = ready.owner.returnToLive('thread');
    await ready.owner.source.waitFor((state) => state!.isPreparingLive);
    page.complete(
      StudioTimelinePage(
        items: [text('stale', 1)],
        before: 'tlp1.stale',
        hasOlder: true,
      ),
    );
    await loading;
    ready.transport.completeOpen(version: 21);
    await switching;

    final view = ready.owner.source.value!;
    expect(view.isLoadingOlder, isFalse, reason: '新代次不得继承旧代次的 loading');
    expect(view.olderError, isNull);
    final second = ready.owner.lease('thread')!;
    expect(second, isNot(same(first)));

    // 新代次可以继续分页，并且不被旧代次的迟到回包影响。
    final secondConnection = ready.transport.connections.last;
    final nextPage = Completer<StudioTimelinePage>();
    secondConnection.pageResult = nextPage;
    final loadingSecond = ready.owner.loadOlder('thread');
    expect(ready.owner.source.value!.isLoadingOlder, isTrue);
    nextPage.complete(
      StudioTimelinePage(
        items: [item(id: 'older', revision: 1, ordinal: 0, body: 'body-older')],
        before: 'tlp1.older',
        hasOlder: true,
      ),
    );
    await loadingSecond;
    expect(ready.owner.source.value!.isLoadingOlder, isFalse);
    expect(ready.owner.source.value!.olderCursor, 'tlp1.older');
    expect(
      [for (final message in second.controller.messages) message.id],
      ['older', 'a', 'b'],
    );
  });

  test('同连接重同步基线在 Live 也建立新代次并归零分页状态', () async {
    final ready = await open();
    final first = ready.owner.lease('thread')!;
    final page = Completer<StudioTimelinePage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder('thread');
    expect(ready.owner.source.value!.isLoadingOlder, isTrue);

    ready.connection.emit(
      StudioTimelineResync(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        reason: StudioTimelineResyncReason.lagging,
        baseline: StudioTimelineBaseline(
          subscriptionId: 'sub-${ready.connection.baselineVersion}',
          version: 30,
          items: [
            item(id: 'a', revision: 2, ordinal: 1, body: 'body-a2'),
            item(id: 'b', revision: 3, ordinal: 2, body: 'body-b3'),
          ],
          before: 'tlp1.resync',
          hasOlder: true,
        ),
      ),
    );
    await _until(() => ready.owner.lease('thread') != first);
    page.complete(
      StudioTimelinePage(
        items: [text('stale', 1)],
        before: 'tlp1.stale',
        hasOlder: true,
      ),
    );
    await loading;
    final view = ready.owner.source.value!;
    expect(view.isLoadingOlder, isFalse);
    expect(view.olderError, isNull);
    final second = ready.owner.lease('thread')!;
    expect(second.appliedVersion, 30);
    expect(view.olderCursor, 'tlp1.resync');

    final nextPage = Completer<StudioTimelinePage>();
    ready.connection.pageResult = nextPage;
    final loadingSecond = ready.owner.loadOlder('thread');
    nextPage.complete(
      StudioTimelinePage(
        items: [item(id: 'resync-older', revision: 1, ordinal: 0)],
        before: null,
        hasOlder: false,
      ),
    );
    await loadingSecond;
    expect(
      [for (final message in second.controller.messages) message.id],
      ['resync-older', 'a', 'b'],
    );
  });

  test('页快照漏掉已被忽略的更早身份时显式重同步', () async {
    final ready = await open(
      items: [
        item(id: 'a', revision: 1, ordinal: 5, body: 'body-a'),
        item(id: 'b', revision: 2, ordinal: 6, body: 'body-b'),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    // 尾部先到一条更早的新身份：落在已覆盖范围之外，先忽略（不插入、不缓存正文）。
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            item(id: 'x', revision: 1, ordinal: 4, body: 'body-x'),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b'],
    );

    // 这一页把 ordinal 3 纳入覆盖，[3,5) 里已知存在的 'x' 却没被交付：游标会越过它，
    // 不能静默丢消息，必须显式重同步。
    final page = Completer<StudioTimelinePage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder('thread');
    page.complete(
      StudioTimelinePage(
        items: [item(id: 'y', revision: 1, ordinal: 3, body: 'body-y')],
        before: 'tlp1.y',
        hasOlder: false,
      ),
    );
    await loading;
    await _until(() => ready.transport.opens == 2);
    await _until(() => ready.owner.lease('thread') != lease);
    expect(ready.owner.lease('thread'), isNot(same(lease)));
  });

  test('页快照交付了被忽略的更早身份时正常合并', () async {
    final ready = await open(
      items: [
        item(id: 'a', revision: 1, ordinal: 5, body: 'body-a'),
        item(id: 'b', revision: 2, ordinal: 6, body: 'body-b'),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            item(id: 'x', revision: 1, ordinal: 4, body: 'body-x'),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);

    final page = Completer<StudioTimelinePage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder('thread');
    page.complete(
      StudioTimelinePage(
        items: [
          item(id: 'y', revision: 1, ordinal: 3, body: 'body-y'),
          item(id: 'x', revision: 7, ordinal: 4, body: '页里的权威正文'),
        ],
        before: 'tlp1.y',
        hasOlder: false,
      ),
    );
    await loading;
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['y', 'x', 'a', 'b'],
      reason: '页回包补齐被忽略的身份后按 canonical 顺序前插',
    );
    expect(
      timelinePayloadOf(lease.controller.messages[1])!.revision,
      7,
      reason: '页读取当时的权威值',
    );
    expect(ready.transport.opens, 1);
    expect(ready.owner.lease('thread'), same(lease));
  });

  test('History 下纯保存确认与空批次不制造新输出提示', () async {
    const bodyRef = StudioTimelineDetailRef(
      field: ThreadTextFieldView(),
      revision: 2,
      totalBytes: 6,
      previewBytes: 6,
    );
    final ready = await open(
      items: [
        item(id: 'a', revision: 1, ordinal: 1, body: 'body-a', terminal: true),
        item(
          id: 'b',
          revision: 2,
          ordinal: 2,
          body: 'body-b',
          terminal: true,
          details: const [bodyRef],
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final frozen = [...lease.controller.messages];
    final watermark = lease.appliedVersion!;
    await ready.owner.dispatch('thread', const TimelineEnterHistory());
    expect(ready.owner.source.value!.hasNewOutput, isFalse);

    // 空批次：只是水位推进。
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: watermark,
        to: watermark + 1,
        changes: const [],
        priority: StudioTimelinePriority.coalesced,
      ),
    );
    await _until(() => ready.connection.nextCalls >= 2);
    expect(ready.owner.source.value!.hasNewOutput, isFalse);

    // 纯保存确认：同 revision、字段 Unchanged 且总长未变。
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: watermark + 1,
        to: watermark + 2,
        changes: [
          StudioTimelineUpdateItem(
            itemId: 'b',
            expectedRevision: 2,
            revision: 2,
            omittedBytes: 0,
            saved: true,
            lifecycle: StudioTimelineLifecycle.terminal,
            fields: const [
              StudioFieldUpdateView(
                field: ThreadTextFieldView(),
                change: UnchangedThreadFieldChangeView(),
                totalBytes: 6,
                previewBytes: 6,
              ),
            ],
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => ready.connection.nextCalls >= 3);
    expect(
      ready.owner.source.value!.hasNewOutput,
      isFalse,
      reason: '单独的保存确认不是新内容',
    );
    expect(
      lease.controller.messages,
      frozen,
      reason: 'History 的 Message（含 saved）保持冻结',
    );
    expect(lease.appliedVersion, watermark);

    // 真实字段内容变化仍然提示，展示依旧冻结。
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: watermark + 2,
        to: watermark + 3,
        changes: [
          StudioTimelineUpdateItem(
            itemId: 'b',
            expectedRevision: 2,
            revision: 3,
            omittedBytes: 0,
            saved: true,
            lifecycle: StudioTimelineLifecycle.terminal,
            fields: const [
              StudioFieldUpdateView(
                field: ThreadTextFieldView(),
                change: AppendThreadFieldChangeView(' 继续'),
                totalBytes: 12,
                previewBytes: 12,
              ),
            ],
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await ready.owner.source.waitFor((state) => state!.hasNewOutput);
    expect(lease.controller.messages, frozen);
  });

  test('页查询在途时到达的尾部新身份与页结果按 canonical 顺序合并', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final page = Completer<StudioTimelinePage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder('thread');
    expect(ready.owner.source.value!.isLoadingOlder, isTrue);

    // 页回包之前，尾部先交付一条更新身份（落在已覆盖范围之后）。
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            item(id: 'tail', revision: 4, ordinal: 4, body: 'body-tail'),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b', 'tail'],
    );

    page.complete(
      StudioTimelinePage(
        items: [item(id: 'older', revision: 1, ordinal: 0, body: 'body-older')],
        before: 'tlp1.older',
        hasOlder: false,
      ),
    );
    await loading;
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['older', 'a', 'b', 'tail'],
      reason: '页前插与尾部插入互不覆盖，都保持 canonical 顺序',
    );
    expect(ready.transport.opens, 1, reason: '这条交错可以证明连续，不需要重同步');
    expect(ready.owner.lease('thread'), same(lease));
    expect(ready.owner.source.value!.isLoadingOlder, isFalse);
  });

  test('同 revision 的权威 Add 即使正文相同也应用 Turn 与元数据变化', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    final incoming = item(
      id: 'a',
      revision: 1,
      ordinal: 1,
      body: 'body-a',
      terminal: true,
    );
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            StudioTimelineItem(
              item: incoming.item.copyWith(
                turnId: 'turn-rebound',
                updatedAt: DateTime.utc(2027),
              ),
              saved: incoming.saved,
              lifecycle: incoming.lifecycle,
              omittedBytes: incoming.omittedBytes,
              details: incoming.details,
            ),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b'],
      reason: '稳定身份与位置不变',
    );
    final payload = timelinePayloadOf(lease.controller.messages.first)!;
    expect(payload.item.turnId, 'turn-rebound');
    expect(payload.item.updatedAt, DateTime.utc(2027));
    expect((payload.item.state as ThreadTextItemStateView).text, 'body-a');
  });

  test('更高 revision 的权威 Add 不得把终态退回流式', () async {
    final terminalItem = ThreadItemView(
      id: 'done',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 4,
      revision: 3,
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
      items: [
        StudioTimelineItem(
          item: terminalItem,
          saved: true,
          lifecycle: StudioTimelineLifecycle.terminal,
          omittedBytes: 0,
          details: const [],
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineAdd(
            item(id: 'done', revision: 4, ordinal: 4, body: 'abc 更长的正文'),
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => ready.transport.opens == 2);
    final replacement = ready.owner.lease('thread')!;
    expect(replacement, isNot(same(lease)));
    expect(
      timelinePayloadOf(replacement.controller.messages.single)!.terminal,
      isTrue,
      reason: '显式重同步建立的新基线仍保持终态',
    );
  });

  test('逐字段账目必须与声明省略量一致（Add 与 UpdateItem 同一不变量）', () {
    const textRef = StudioTimelineDetailRef(
      field: ThreadTextFieldView(),
      revision: 1,
      totalBytes: 8,
      previewBytes: 4,
    );
    final current = TimelineMessagePayload.fromItem(
      item(
        id: 'acct',
        revision: 1,
        ordinal: 11,
        body: 'abcd',
        omitted: 4,
        details: const [textRef],
      ),
    );

    StudioTimelineUpdateItem update({required int omitted}) =>
        StudioTimelineUpdateItem(
          itemId: 'acct',
          expectedRevision: 1,
          revision: 2,
          omittedBytes: omitted,
          saved: false,
          lifecycle: StudioTimelineLifecycle.terminal,
          fields: const [
            StudioFieldUpdateView(
              field: ThreadTextFieldView(),
              change: ReplaceThreadFieldChangeView('abce'),
              totalBytes: 8,
              previewBytes: 4,
            ),
          ],
        );
    // 8-4 = 4，声明 3 与逐字段账目矛盾 → 显式重同步。
    expect(current.applyUpdate(update(omitted: 3)), isNull);
    final applied = current.applyUpdate(update(omitted: 4))!;
    expect(applied.omittedBytes, 4);
    expect(applied.detailFor(const ThreadTextFieldView())!.revision, 2);

    // 更高 revision 的权威 Add 走同一账目不变量，不能因为“更新整条”而绕过。
    expect(
      current.applyAdd(
        item(
          id: 'acct',
          revision: 2,
          ordinal: 11,
          body: 'abcdefgh',
          omitted: 3,
          details: const [
            StudioTimelineDetailRef(
              field: ThreadTextFieldView(),
              revision: 2,
              totalBytes: 8,
              previewBytes: 4,
            ),
          ],
        ),
      ),
      isNull,
    );
    expect(
      current.applyAdd(
        item(
          id: 'acct',
          revision: 2,
          ordinal: 11,
          body: 'abcdefgh',
          omitted: 4,
          details: const [
            StudioTimelineDetailRef(
              field: ThreadTextFieldView(),
              revision: 2,
              totalBytes: 8,
              previewBytes: 4,
            ),
          ],
        ),
      ),
      isNotNull,
    );
  });

  test('同 revision 跨字段覆盖方向不同时显式重同步而不是猜账目', () {
    // 两份输入各自更完整一个字段：合成后既不是任一声明，不能静默给错省略量。
    final current = TimelineMessagePayload.fromItem(
      item(
        id: 'mixed',
        revision: 5,
        ordinal: 9,
        body: 'abcd',
        omitted: 4,
        details: const [
          StudioTimelineDetailRef(
            field: ThreadTextFieldView(),
            revision: 5,
            totalBytes: 8,
            previewBytes: 4,
          ),
          StudioTimelineDetailRef(
            field: ThreadToolArgumentsFieldView(),
            revision: 5,
            totalBytes: 8,
            previewBytes: 8,
          ),
        ],
      ),
    );
    final incoming = item(
      id: 'mixed',
      revision: 5,
      ordinal: 9,
      body: 'abcdefgh',
      omitted: 4,
      details: const [
        StudioTimelineDetailRef(
          field: ThreadTextFieldView(),
          revision: 5,
          totalBytes: 8,
          previewBytes: 8,
        ),
        StudioTimelineDetailRef(
          field: ThreadToolArgumentsFieldView(),
          revision: 5,
          totalBytes: 8,
          previewBytes: 4,
        ),
      ],
    );
    expect(current.applyAdd(incoming), isNull, reason: '混合覆盖无法证明合成后的省略量与预算');

    // 逐字段支配时账目与正文一致：省略量归零、详情预览字节同步。
    final dominated = current.applyAdd(
      item(
        id: 'mixed',
        revision: 5,
        ordinal: 9,
        body: 'abcdefgh',
        omitted: 0,
        details: const [
          StudioTimelineDetailRef(
            field: ThreadTextFieldView(),
            revision: 5,
            totalBytes: 8,
            previewBytes: 8,
          ),
          StudioTimelineDetailRef(
            field: ThreadToolArgumentsFieldView(),
            revision: 5,
            totalBytes: 8,
            previewBytes: 8,
          ),
        ],
      ),
    )!;
    expect(dominated.omittedBytes, 0);
    expect(dominated.item.bodyOmittedUnits, 0);
    expect(dominated.detailFor(const ThreadTextFieldView())!.previewBytes, 8);
  });

  test('退役但未释放的代次接受迟到真实挂载，已释放则明确拒绝', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final page = Completer<StudioTimelinePage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder('thread');
    final report = await ready.owner.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 40)),
    );
    expect(report.complete, isFalse);
    // 关闭已发布无展示，但真实旧子树可能还没卸载：迟到挂载必须计入等待。
    lease.bind();
    expect(lease.isMounted, isTrue);
    page.complete(
      const StudioTimelinePage(items: [], before: null, hasOlder: false),
    );
    await loading;
    expect(lease.isReleased, isFalse, reason: '真实子树仍持有控制器');
    await lease.unbind();
    await lease.released;
    expect(lease.isReleased, isTrue);
    expect(lease.bind, throwsStateError);
  });

  test('同 revision 预览被预算挤短时显式重同步而不是静默应用', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    // 同 revision、原文长度不变，但预览字节退回：只能是预算重新分配，无法证明连续。
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineUpdateItem(
            itemId: 'a',
            expectedRevision: 1,
            revision: 1,
            omittedBytes: 3,
            saved: false,
            lifecycle: StudioTimelineLifecycle.terminal,
            fields: const [
              StudioFieldUpdateView(
                field: ThreadTextFieldView(),
                change: UnchangedThreadFieldChangeView(),
                totalBytes: 6,
                previewBytes: 3,
              ),
            ],
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => ready.transport.opens == 2);
    expect(ready.owner.lease('thread'), isNot(same(lease)));
  });

  test('更高 revision 原文确实变短时仍原位权威替换，不误判预算缩减', () async {
    final ready = await open(
      items: [
        item(
          id: 'short',
          revision: 1,
          ordinal: 1,
          body: 'body-short',
          terminal: true,
          details: const [
            StudioTimelineDetailRef(
              field: ThreadTextFieldView(),
              revision: 1,
              totalBytes: 10,
              previewBytes: 10,
            ),
          ],
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineUpdateItem(
            itemId: 'short',
            expectedRevision: 1,
            revision: 2,
            omittedBytes: 0,
            saved: false,
            lifecycle: StudioTimelineLifecycle.terminal,
            fields: const [
              StudioFieldUpdateView(
                field: ThreadTextFieldView(),
                change: ReplaceThreadFieldChangeView('abc'),
                totalBytes: 3,
                previewBytes: 3,
              ),
            ],
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(ready.transport.opens, 1, reason: '权威缩短不能被当成预算缩减拒绝');
    final payload = timelinePayloadOf(lease.controller.messages.single)!;
    expect((payload.item.state as ThreadTextItemStateView).text, 'abc');
    expect(payload.revision, 2);
    expect(payload.detailFor(const ThreadTextFieldView())!.totalBytes, 3);
  });

  test('非 const 解码的同值字段在多帧后仍复用同一条详情引用', () async {
    final thinking = ThreadItemView(
      id: 'reasoning',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 3,
      revision: 5,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      executionTerminal: true,
      state: ThreadThinkingItemStateView(
        summary: const [],
        content: const ['第一段', '第二段'],
        lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
      ),
    );
    final ready = await open(
      items: [
        StudioTimelineItem(
          item: thinking,
          saved: false,
          lifecycle: StudioTimelineLifecycle.terminal,
          omittedBytes: 0,
          details: [
            StudioTimelineDetailRef(
              field: ThreadThinkingContentFieldView(0),
              revision: 5,
              totalBytes: 9,
              previewBytes: 9,
            ),
            StudioTimelineDetailRef(
              field: ThreadThinkingContentFieldView(1),
              revision: 5,
              totalBytes: 9,
              previewBytes: 9,
            ),
          ],
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    var revision = 5;
    for (var round = 0; round < 3; round++) {
      final applied = lease.appliedVersion!;
      ready.connection.emit(
        StudioTimelinePatch(
          subscriptionId: 'sub-${ready.connection.baselineVersion}',
          from: applied,
          to: applied + 1,
          changes: [
            StudioTimelineUpdateItem(
              itemId: 'reasoning',
              expectedRevision: revision,
              revision: revision + 1,
              omittedBytes: 0,
              saved: false,
              lifecycle: StudioTimelineLifecycle.terminal,
              fields: [
                StudioFieldUpdateView(
                  // 真实解码每帧都是新实例。
                  field: ThreadThinkingContentFieldView(0),
                  change: const AppendThreadFieldChangeView('+'),
                  totalBytes: 10 + round,
                  previewBytes: 10 + round,
                ),
              ],
            ),
          ],
          priority: StudioTimelinePriority.immediate,
        ),
      );
      revision += 1;
      await _until(() => lease.appliedVersion == applied + 1);
    }
    final payload = timelinePayloadOf(lease.controller.messages.single)!;
    expect(payload.details.length, 2, reason: '同值字段必须复用同一条详情引用，不能随帧增长');
    final ref0 = payload.detailFor(ThreadThinkingContentFieldView(0))!;
    expect(ref0.revision, 8);
    expect(ref0.totalBytes, 12);
    expect(
      payload.detailFor(ThreadThinkingContentFieldView(1))!.revision,
      8,
      reason: '未变化字段的 ref 也重钉到条目当前 revision（否则它从此读不出）',
    );

    // 真实按需读取：未变化的 chunk 与被更新的 chunk 都必须能用自己的 ref 读到正文。
    final scope = lease.queries!;
    final unchanged = payload.detailFor(ThreadThinkingContentFieldView(1))!;
    final changed = payload.detailFor(ThreadThinkingContentFieldView(0))!;
    final unchangedChunk = await scope.readDetail(
      itemId: 'reasoning',
      query: StudioTimelineDetailQuery(
        field: unchanged.field,
        revision: unchanged.revision,
      ),
    );
    expect(unchangedChunk.revision, 8);
    expect(unchangedChunk.itemId, 'reasoning');
    final changedChunk = await scope.readDetail(
      itemId: 'reasoning',
      query: StudioTimelineDetailQuery(
        field: changed.field,
        revision: changed.revision,
      ),
    );
    expect(changedChunk.revision, 8);

    // 真 Remove 必须真的消失（而不是匹配不上旧键后留在表里）。
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineUpdateItem(
            itemId: 'reasoning',
            expectedRevision: 8,
            revision: 9,
            omittedBytes: 0,
            saved: false,
            lifecycle: StudioTimelineLifecycle.terminal,
            fields: [
              StudioFieldUpdateView(
                field: ThreadThinkingContentFieldView(1),
                change: const RemoveThreadFieldChangeView(),
                totalBytes: 0,
                previewBytes: 0,
              ),
            ],
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    final afterRemoval = timelinePayloadOf(lease.controller.messages.single)!;
    expect(afterRemoval.details.length, 1);
    expect(afterRemoval.detailFor(ThreadThinkingContentFieldView(1)), isNull);
  });

  test('嵌套问答子字段按值语义更新同一条详情引用', () async {
    ThreadItemView ask({required String answer}) => ThreadItemView(
      id: 'ask',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 4,
      revision: 2,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      executionTerminal: true,
      state: ThreadToolItemStateView(
        invocation: const ThreadToolInvocationView(
          toolCallId: 'call-1',
          name: 'ask',
          arguments: '{}',
        ),
        lifecycle: SucceededThreadToolView(
          DateTime.utc(2026),
          const ThreadToolOutputView(
            result: 'ok',
            attachments: [],
            outputArtifacts: [],
          ),
        ),
        userInput: ThreadToolUserInputView(
          interactionId: 'interaction-1',
          questions: const [
            UserQuestionView(
              id: 'q1',
              header: '确认',
              question: '继续吗',
              isOther: false,
              isSecret: false,
              options: [],
            ),
          ],
          state: ResolvedThreadToolUserInputView([
            ThreadUserInputAnswerView(questionId: 'q1', answers: [answer]),
          ]),
        ),
      ),
    );
    final ready = await open(
      items: [
        StudioTimelineItem(
          item: ask(answer: '是'),
          saved: false,
          lifecycle: StudioTimelineLifecycle.terminal,
          omittedBytes: 0,
          details: [
            StudioTimelineDetailRef(
              field: ThreadToolUserInputFieldView(
                questionIndex: 0,
                part: ThreadUserInputAnswerFieldPartView(0),
              ),
              revision: 2,
              totalBytes: 3,
              previewBytes: 3,
            ),
          ],
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      StudioTimelinePatch(
        subscriptionId: 'sub-${ready.connection.baselineVersion}',
        from: applied,
        to: applied + 1,
        changes: [
          StudioTimelineUpdateItem(
            itemId: 'ask',
            expectedRevision: 2,
            revision: 3,
            omittedBytes: 0,
            saved: false,
            lifecycle: StudioTimelineLifecycle.terminal,
            fields: [
              StudioFieldUpdateView(
                field: ThreadToolUserInputFieldView(
                  questionIndex: 0,
                  part: ThreadUserInputAnswerFieldPartView(0),
                ),
                change: const AppendThreadFieldChangeView('，继续'),
                totalBytes: 12,
                previewBytes: 12,
              ),
            ],
          ),
        ],
        priority: StudioTimelinePriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    final payload = timelinePayloadOf(lease.controller.messages.single)!;
    expect(payload.details.length, 1, reason: '同一子字段不能新增一条引用');
    final ref = payload.detailFor(
      ThreadToolUserInputFieldView(
        questionIndex: 0,
        part: ThreadUserInputAnswerFieldPartView(0),
      ),
    )!;
    expect(ref.revision, 3);
    expect(ref.totalBytes, 12);
  });

  test('发送准备期间切换选择不悬挂，仍提交冻结的 A 目标', () async {
    final ready = await open(threads: [_thread(), _thread('other')]);
    final client = ready.client;
    final owner = ready.owner;
    // B 先有可发送的 session 快照，切换后它自己的展示代次不受 A 的准备影响。
    client.session('other').applySnapshot(workspaceFor('other'));
    client.session('thread').applySnapshot(workspaceFor('thread'));
    final composer = client.composer('thread');
    composer.updateDraft('frozen text');

    // A 的展示准备会新建订阅：把它挂起，模拟“首帧未到”期间用户切换选择。
    ready.transport.holdNextOpen = true;
    final submitting = composer.submit(
      beforeSubmit: () => owner.prepareSend('thread'),
    );
    await owner.source.waitFor((state) => state!.isPreparingLive);

    client.workspace.selectThread('other', projectId: 'project');
    await _until(() => owner.lease('other') != null);
    final otherLease = owner.lease('other')!;
    final otherGeneration = otherLease.generation;

    // 前置被 typed 取消，但冻结的发送继续：后端收到的是 A 的冻结 payload 与 route。
    final entered = await ready.transport.promptEntered.future;
    expect(entered.input.text, 'frozen text');
    expect(entered.routeRevision, 1);
    expect(entered.input.inputId, isNotEmpty);

    // A 的迟到首帧不得发布到已经切换后的展示。
    final otherLeaseBefore = owner.lease('other');
    ready.transport.completeOpen(version: 77);
    await Future<void>.delayed(Duration.zero);
    expect(owner.lease('thread'), isNull);
    expect(owner.lease('other'), same(otherLeaseBefore));
    expect(owner.lease('other')!.generation, otherGeneration);

    ready.transport.promptReply.complete(
      SubmitPromptReceipt(
        threadId: 'thread',
        inputId: entered.input.inputId,
        cursor: 7,
      ),
    );
    await submitting;
    expect(composer.state.draft.trim(), isEmpty, reason: '冻结发送正常收束');
    expect(
      composer.state,
      isA<IdleComposerThreadState>(),
      reason: '正常收束，不进入未知结果封存',
    );
  });

  test('普通回实时期间切换选择以 typed 取消结束', () async {
    final ready = await open(threads: [_thread(), _thread('other')]);
    ready.client.session('other');
    ready.transport.holdNextOpen = true;
    final switching = ready.owner.returnToLive('thread');
    await ready.owner.source.waitFor((state) => state!.isPreparingLive);
    ready.client.workspace.selectThread('other', projectId: 'project');
    await expectLater(
      switching,
      throwsA(isA<TimelinePreparationCancelled>()),
      reason: '展示动作因选择变化被 typed 取消，而不是永久 pending',
    );
    expect(ready.owner.source.value!.isPreparingLive, isFalse);
  });

  test('关闭等待真实受理的页查询，native close 已返回也不提前释放', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final budget = ready.client.session('thread').timeline.budget;
    final page = Completer<StudioTimelinePage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder('thread');
    expect(budget.used(ResourceKind.pendingOperation), 1);

    final report = await ready.owner.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 40)),
    );
    expect(report.complete, isFalse, reason: '在途查询仍持有许可');
    expect(lease.isReleased, isFalse);
    expect(budget.used(ResourceKind.pendingOperation), 1);

    page.complete(
      const StudioTimelinePage(items: [], before: null, hasOlder: false),
    );
    await loading;
    await lease.released;
    expect(lease.isReleased, isTrue);
    expect(budget.used(ResourceKind.pendingOperation), 0);
  });

  test('close publishes no display and waits for the real unmount', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    lease.bind();
    final closing = ready.owner.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 30)),
    );
    expect(ready.owner.source.value, isNull);
    expect(ready.owner.close(), same(closing));
    final report = await closing;
    expect(
      report.complete,
      isFalse,
      reason: 'the real subtree still borrows the controller',
    );
    expect(report.unresolved.single.owner, 'timeline-display:thread');
    await lease.unbind();
    expect(lease.isReleased, isTrue);
  });

  test(
    'an unmounted display releases without waiting for widget callbacks',
    () async {
      final ready = await open();
      final lease = ready.owner.lease('thread')!;
      final report = await ready.owner.close(
        deadline: DateTime.now().add(const Duration(seconds: 1)),
      );
      expect(report.complete, isTrue);
      expect(lease.isReleased, isTrue);
    },
  );
}

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not reached before the deadline');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

StudioThread _thread([String id = 'thread']) => StudioThread(
  id: id,
  projectId: 'project',
  title: 'Thread $id',
  mode: ThreadModeId.simple,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/project',
);

final class _ScriptedTransport implements StudioTransport {
  final List<_ScriptedConnection> connections = [];

  /// 非空时所有连接都用它作为首帧条目。
  List<StudioTimelineItem>? baselineItems;
  final List<StreamController<ThreadStreamFrame>> _bindings = [];
  int opens = 0;

  /// 非空时下一次打开保持挂起，用于观察“新订阅已请求但首帧未到”的中间状态。
  bool holdNextOpen = false;

  /// 非空时所有打开都以该错误收束（含重试），用于让内容连接真的失败。
  Object? failOpens;

  /// 冻结提交实际到达后端的输入与 route revision（真实 `submitComposer` 路径）。
  final Completer<({StudioPromptInput input, int routeRevision})>
  promptEntered = Completer();
  final Completer<SubmitPromptReceipt> promptReply = Completer();

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) {
    if (!promptEntered.isCompleted) {
      promptEntered.complete((
        input: input,
        routeRevision: expectedModelRouteRevision,
      ));
    }
    return promptReply.future;
  }

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) {
    final controller = StreamController<ThreadStreamFrame>.broadcast();
    _bindings.add(controller);
    return controller.stream;
  }

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) {
    opens++;
    final failure = failOpens;
    if (failure != null) return Future.error(failure);
    final connection = _ScriptedConnection(baselineItems);
    connections.add(connection);
    if (holdNextOpen) {
      holdNextOpen = false;
    } else {
      connection.opened.complete(connection);
    }
    return connection.opened.future;
  }

  /// 完成最近一次打开的连接首帧。
  void completeOpen({required int version}) {
    final connection = connections.lastWhere(
      (value) => !value.opened.isCompleted,
    );
    connection.opened.complete(connection);
    connection.baselineVersion = version;
  }

  void failOpen(Object error) {
    final connection = connections.lastWhere(
      (value) => !value.opened.isCompleted,
    );
    connection.opened.completeError(error);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused transport capability: ${invocation.memberName}',
  );
}

final class _ScriptedConnection implements StudioTimelineConnection {
  _ScriptedConnection(this.scriptedItems);

  final Completer<StudioTimelineConnection> opened = Completer();
  final List<Completer<StudioTimelineUpdate?>> frames = [];
  Completer<StudioTimelinePage>? pageResult;
  final List<({String itemId, StudioTimelineDetailQuery query})>
  detailRequests = [];

  /// 非空时用它作为首帧条目（用于预览补齐/终态权威修订等真实形状）。
  final List<StudioTimelineItem>? scriptedItems;
  int baselineVersion = 1;
  int initialCalls = 0;
  int nextCalls = 0;
  int closeCalls = 0;
  bool closed = false;

  @override
  Future<StudioTimelineBaseline> initial() async {
    initialCalls++;
    return StudioTimelineBaseline(
      subscriptionId: 'sub-$baselineVersion',
      version: baselineVersion,
      items:
          scriptedItems ??
          [
            for (final entry in [('a', 1), ('b', 2)]) _item(entry.$1, entry.$2),
          ],
      before: 'tlp1.b',
      hasOlder: true,
    );
  }

  @override
  Future<StudioTimelineUpdate?> next() {
    if (closed) return Future.value(null);
    nextCalls++;
    final pending = Completer<StudioTimelineUpdate?>();
    frames.add(pending);
    return pending.future;
  }

  void emit(StudioTimelineUpdate update) {
    if (frames.isEmpty) throw StateError('No pending content read');
    frames.removeAt(0).complete(update);
  }

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) {
    final result = pageResult;
    if (result == null) {
      return Future.value(
        const StudioTimelinePage(items: [], before: null, hasOlder: false),
      );
    }
    return result.future;
  }

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) async {
    detailRequests.add((itemId: itemId, query: query));
    // 只回一段正文；真实链路按 item/field/revision 校验，这里同样按请求的 revision 交付。
    return StudioTimelineDetailChunk(
      itemId: itemId,
      field: query.field,
      revision: query.revision,
      text: 'detail:$itemId',
      totalBytes: 9,
      continuation: null,
    );
  }

  @override
  void requestClose() {
    closed = true;
    for (final pending in frames) {
      if (!pending.isCompleted) pending.complete(null);
    }
    frames.clear();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
  }

  StudioTimelineItem _item(String id, int revision) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: revision,
      revision: revision,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      state: ThreadTextItemStateView(
        channel: ThreadTextChannel.finalAnswer,
        text: 'body-$id',
        attachments: const [],
        lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
      ),
    ),
    saved: false,
    lifecycle: StudioTimelineLifecycle.terminal,
    omittedBytes: 0,
    details: const [],
  );
}
