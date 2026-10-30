import 'support/mapped_conversation_feed.dart';
import 'support/conversation_fixtures.dart';

import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_entry.dart';
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

  ConversationItem text(
    String id,
    int revision, {
    String body = 'body',
    int? ordinal,
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal ?? revision,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: false,
    lifecycle: ConversationLifecycle.terminal,
    descriptor: ConversationTextDescriptor(
      channel: ThreadTextChannel.finalAnswer,
      attachments: const [],
      lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
    ),
    fields: {const ThreadTextFieldView(): body},
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
  ConversationItem item({
    required String id,
    required int revision,
    required int ordinal,
    String body = 'body',
    bool saved = false,
    bool terminal = false,
    List<ConversationDetailRef> details = const [],
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: saved,
    lifecycle: terminal
        ? ConversationLifecycle.terminal
        : ConversationLifecycle.streaming,
    descriptor: ConversationTextDescriptor(
      channel: ThreadTextChannel.finalAnswer,
      attachments: const [],
      lifecycle: terminal
          ? CompletedThreadContentView(DateTime.utc(2026))
          : const StreamingThreadContentView(),
    ),
    fields: {const ThreadTextFieldView(): body},
    totalBytes: {for (final ref in details) ref.field: ref.totalBytes},
  );

  Future<
    ({
      AnyworkClient client,
      TimelineSessionOwner owner,
      _ScriptedTransport transport,
      _ScriptedConnection connection,
    })
  >
  open({List<ConversationItem>? items, List<StudioThread>? threads}) async {
    final transport = _ScriptedTransport()
      ..baselineItems = items
      ..workspace = workspaceFor;
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
    addTearDown(owner.close);
    client.selection.selectThread(threadId: 'thread', workspaceId: 'project');
    client.conversations.setVisibleThread('thread');
    owner.select('thread');
    await _until(() => transport.connections.isNotEmpty);
    final connection = transport.connections.single;
    await owner.source.waitFor(
      (state) =>
          state != null &&
          state.generation > 0 &&
          state.connection == TimelineConnectionPhase.ready,
    );
    await _until(
      () => connection.acknowledgements.length == connection.deliveredFrames,
    );
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
      expect(ready.connection.listenCalls, 1);
      await _until(() => ready.connection.acknowledgements.length == 2);
      expect(ready.connection.acknowledgements, [1, 2]);
    },
  );

  for (final status in [ThreadStatusView.closing, ThreadStatusView.closed]) {
    test(
      '${status.name} preserves the complete history display and rejects new execution',
      () async {
        final ready = await open();
        final lease = ready.owner.lease('thread')!;
        final messages = [...lease.controller.messages];
        final draft = ready.client.drafts.composer('thread')
          ..updateDraft('keep closed draft');
        ready.client.threadDirectory.applyWindow(
          ThreadDirectoryWindow(
            threads: [_thread().copyWith(status: status)],
            revision: 2,
          ),
        );
        // Canonical 状态经 typed feed 的 state 帧进入；目录身份与快照同时关闭。
        ready.transport.workspace = (threadId) =>
            workspaceFor(threadId)
                .copyWith(thread: _thread(threadId).copyWith(status: status));
        ready.connection.emitState(
          ThreadSnapshotFrame(
            workspace: workspaceFor('thread')
                .copyWith(thread: _thread().copyWith(status: status)),
          ),
        );
        await _until(
          () =>
              ready.client.conversations
                  .existingSession('thread')
                  ?.state
                  .workspace
                  ?.thread
                  .status ==
              status,
        );

        expect(ready.owner.lease('thread'), same(lease));
        expect(lease.controller.messages, messages);
        expect(lease.queries!.isActive, isTrue);
        await expectLater(
          ready.owner.prepareSend('thread'),
          throwsA(
            isA<StudioFailure>().having(
              (failure) => failure.detailsJson,
              'closed reason',
              contains('threadClosed'),
            ),
          ),
        );
        await expectLater(
          ready.client.threadCommands.submitComposer(
            'thread',
            const StudioPromptInput(
              inputId: 'closed-input',
              text: 'not sent',
              attachmentDraftIds: [],
            ),
            expectedModelRouteRevision: 1,
          ),
          throwsA(
            isA<SubmissionNotSent>().having(
              (failure) => (failure.error as StudioFailure).detailsJson,
              'closed reason',
              contains('threadClosed'),
            ),
          ),
        );
        expect(ready.transport.promptEntered.isCompleted, isFalse);
        expect(draft.state.draft, 'keep closed draft');
        expect(lease.controller.messages, messages);
        await ready.owner.returnToLive('thread');
        expect(
          ready.owner
              .lease('thread')!
              .controller
              .messages
              .map((message) => message.id),
          ['a', 'b'],
        );
      },
    );
  }

  for (final closeConversations in [true, false]) {
    test('synchronous ChatOpening listener '
        '${closeConversations ? 'close' : 'demand withdrawal'} '
        'stops the original start stack', () async {
      final transport = _ScriptedTransport()..workspace = workspaceFor;
      final client = AnyworkClient(
        transport: transport,
        clientId: 'owner-reentry',
      );
      addTearDown(
        () => client.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      client.selection.markOpened();
      client.threadDirectory.applyBaseline(
        ThreadDirectoryPage(threads: [_thread()], revision: 1),
        revision: 1,
      );
      final session = client.conversations.session('thread');
      var stopping = false;
      Future<CloseReport>? stopped;
      final observation = session.content.state.watch((state) {
        if (!stopping && state is ChatOpening<ConversationContentFrame>) {
          stopping = true;
          if (closeConversations) {
            stopped = client.conversations.close();
          } else {
            // 撤需求合同：返回前旧 attempt 必须已失效，不依赖外层 drain。
            client.conversations.setVisibleThread(null);
          }
        }
      });
      addTearDown(() async {
        observation.cancel();
      });
      expect(
        () => client.conversations.setVisibleThread('thread'),
        returnsNormally,
        reason: '首条 ChatOpening 发布期间的重入监听不得卡死启动栈',
      );
      expect(stopping, isTrue);
      await _until(() => session.content.hasDemand == false);
      if (closeConversations) {
        expect((await stopped!).complete, isTrue);
        expect(session.isClosed, isTrue);
        expect(transport.opens, 0);
        expect(client.budget.used(ResourceKind.readModel), 0);
      } else {
        // 合同：撤需求返回即旧 attempt 失效，底层不得再打开 feed。
        // SDK 生产修复由原作者负责；本断言按合同期待（先红后绿）。
        final report = await session.content.joinRetired();
        expect(report.complete, isTrue);
        expect(session.isActive, isFalse);
        expect(transport.connections, isEmpty);
        expect(transport.opens, 0);
      }
      expect(client.budget.used(ResourceKind.chatHandle), 0);
      expect(client.budget.used(ResourceKind.pendingOperation), 0);
    });
  }

  test(
    'history freezes the displayed set and only reports new output',
    () async {
      final ready = await open();
      final lease = ready.owner.lease('thread')!;
      final frozen = [...lease.controller.messages];
      final applied = lease.appliedVersion!;
      await ready.owner.dispatch('thread', const TimelineEnterHistory());
      expect(ready.owner.source.value!.mode, TimelineDisplayMode.history);

      final delivered = ready.connection.deliveredFrames;
      ready.connection.emit(
        ConversationPatch(
          subscriptionId: ready.connection.subscriptionId,
          from: applied,
          to: applied + 1,
          changes: const [ConversationRemove('a')],
          priority: ConversationPriority.immediate,
        ),
      );
      await _until(
        () => ready.connection.acknowledgements.contains(delivered + 1),
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
    ready.transport.holdNextOpen = true;
    final recovering = ready.owner.returnToLive('thread');
    expect(
      ready.owner.source.value!.connectionError,
      isNull,
      reason: '新的 opening 不保留旧错误',
    );
    ready.transport.completeOpen(version: 7);
    await recovering;
    expect(ready.owner.source.value!.connection, TimelineConnectionPhase.ready);
    expect(ready.owner.source.value!.connectionError, isNull);
  });

  test('同 revision 的预览补齐经生产 owner/applier 生效且不换代次', () async {
    final preview = conversationFixture(
      id: 'preview',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 3,
      revision: 3,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      saved: false,
      lifecycle: ConversationLifecycle.streaming,
      descriptor: ConversationTextDescriptor(
        channel: ThreadTextChannel.finalAnswer,
        attachments: const [],
        lifecycle: const StreamingThreadContentView(),
      ),
      fields: {const ThreadTextFieldView(): 'abcd'},
    );
    final ready = await open(
      items: [
        conversationCopyFixture(
          preview,
          saved: false,
          lifecycle: ConversationLifecycle.streaming,
          totalBytes: {
            for (final ref in [
              ConversationDetailRef(
                field: const ThreadTextFieldView(),
                revision: 3,
                totalBytes: 8,
                previewBytes: 4,
              ),
            ])
              ref.field: ref.totalBytes,
          },
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final generation = lease.generation;
    final applied = lease.appliedVersion!;
    final subscription = ready.connection.subscriptionId;
    final change = ConversationUpdateItem(
      itemId: 'preview',
      expectedRevision: 3,
      revision: 3,

      saved: false,
      lifecycle: ConversationLifecycle.streaming,
      fields: const [
        ConversationFieldUpdate(
          field: ThreadTextFieldView(),
          change: AppendThreadFieldChangeView('efgh'),
          totalBytes: 8,
          previewBytes: 8,
        ),
      ],
    );
    final manual = ready.client.conversations
        .session('thread')
        .content
        .reduceItem(lease.itemOf('preview')!, change);
    expect(
      timelineText(manual),
      'abcdefgh',
      reason: '真实 applier 必须接受同 revision 的预览补齐',
    );
    ready.connection.emit(
      ConversationPatch(
        subscriptionId: subscription,
        from: applied,
        to: applied + 1,
        changes: [change],
        priority: ConversationPriority.immediate,
      ),
    );
    final attempt = ready.client.conversations
        .session('thread')
        .content
        .currentAttemptId;
    await _until(() => lease.appliedVersion == applied + 1);
    // 连接没有重连：同一 attempt、仍处于 ready、未请求关闭。
    expect(
      ready.client.conversations.session('thread').content.state.value,
      isA<ChatReady<ConversationContentFrame>>(),
    );
    expect(
      ready.client.conversations.session('thread').content.currentAttemptId,
      attempt,
    );
    final payload = timelineEntryOf(lease.controller.messages.single)!.first;
    expect(timelineText(payload), 'abcdefgh');
    expect(payload.omittedBytes, 0);
    expect(payload.id, 'preview');
    expect(payload.header.ordinal, 3);
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
    final terminalItem = conversationFixture(
      id: 'done',
      threadId: 'thread',
      turnId: 'turn-a',
      ordinal: 4,
      revision: 5,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      saved: true,
      lifecycle: ConversationLifecycle.terminal,
      descriptor: ConversationTextDescriptor(
        channel: ThreadTextChannel.finalAnswer,
        attachments: const [],
        lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
      ),
      fields: {const ThreadTextFieldView(): 'abc'},
    );
    final ready = await open(
      items: [
        conversationCopyFixture(
          terminalItem,
          saved: true,
          lifecycle: ConversationLifecycle.terminal,
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    final subscription = ready.connection.subscriptionId;

    ready.connection.emit(
      ConversationPatch(
        subscriptionId: subscription,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationUpdateItem(
            itemId: 'done',
            expectedRevision: 5,
            revision: 6,

            saved: false,
            lifecycle: ConversationLifecycle.terminal,
            header: conversationCopyFixture(
              terminalItem,
              turnId: 'turn-b',
            ).header,
            descriptor: terminalItem.descriptor,
            fields: const [
              ConversationFieldUpdate(
                field: ThreadTextFieldView(),
                change: AppendThreadFieldChangeView('def'),
                totalBytes: 6,
                previewBytes: 6,
              ),
            ],
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    final updated = timelineEntryOf(lease.controller.messages.single)!.first;
    expect(timelineText(updated), 'abcdef');
    expect(updated.revision, 6);
    expect(updated.terminal, isTrue);
    expect(updated.header.turnId, 'turn-b', reason: 'Turn 关联不是 identity');
    expect(updated.saved, isFalse);

    ready.connection.emit(
      ConversationPatch(
        subscriptionId: subscription,
        from: applied + 1,
        to: applied + 2,
        changes: const [
          ConversationUpdateItem(
            itemId: 'done',
            expectedRevision: 6,
            revision: 6,

            saved: true,
            lifecycle: ConversationLifecycle.terminal,
            fields: [],
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 2);
    final saved = timelineEntryOf(lease.controller.messages.single)!.first;
    expect(saved.saved, isTrue);
    expect(saved.revision, 6);
  });

  test('终态回退成 streaming 的帧触发显式重同步而不是被应用', () async {
    final terminalItem = conversationFixture(
      id: 'done',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 4,
      revision: 5,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      saved: true,
      lifecycle: ConversationLifecycle.terminal,
      descriptor: ConversationTextDescriptor(
        channel: ThreadTextChannel.finalAnswer,
        attachments: const [],
        lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
      ),
      fields: {const ThreadTextFieldView(): 'abc'},
    );
    final ready = await open(
      items: [
        conversationCopyFixture(
          terminalItem,
          saved: true,
          lifecycle: ConversationLifecycle.terminal,
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: const [
          ConversationUpdateItem(
            itemId: 'done',
            expectedRevision: 5,
            revision: 6,

            saved: false,
            // 已交付身份是终态：回退成 streaming 必须被拒。
            lifecycle: ConversationLifecycle.streaming,
            fields: [],
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    // owner 无法应用该身份 → 显式刷新内容连接（新 attempt），不把错误当成功。
    await ready.owner.source
        .waitFor(
          (state) =>
              state != null &&
              state.generation > lease.generation &&
              state.connection == TimelineConnectionPhase.ready,
        )
        .timeout(const Duration(seconds: 5));
    final current = ready.owner.lease('thread')!;
    expect(ready.transport.opens, 2, reason: '非法帧只触发一次真实重同步');
    expect(current, isNot(same(lease)));
    final shown = timelineEntryOf(current.controller.messages.single)!.first;
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
      final page = Completer<ConversationPage>();
      ready.connection.pageResult = page;
      final loading = ready.owner.loadOlder(
        'thread',
        generation: ready.owner.lease('thread')!.generation,
      );
      expect(
        ready.owner.loadOlder(
          'thread',
          generation: ready.owner.lease('thread')!.generation,
        ),
        same(loading),
      );
      expect(ready.owner.source.value!.isLoadingOlder, isTrue);
      page.complete(
        ConversationPage(
          // 页游标之前的真实边界：ordinal 严格早于已覆盖范围的下界。
          items: [text('older', 1, ordinal: 0), text('a', 2, ordinal: 1)],
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
      ready.connection.pageResult = Completer<ConversationPage>()
        ..complete(
          const ConversationPage(items: [], before: null, hasOlder: false),
        );
      await ready.owner.loadOlder(
        'thread',
        generation: ready.owner.lease('thread')!.generation,
      );
      expect(ready.owner.source.value!.hasOlder, isFalse);
      expect(
        ready.owner.source.value!.olderCursor,
        isNull,
        reason: 'EOF 的空游标是权威值',
      );
    },
  );

  test('无进展页先显示连续性错误，Live 新基线后显式重试可继续', () async {
    final ready = await open();
    final first = ready.owner.lease('thread')!;
    final before = ready.owner.source.value!.olderCursor;
    final shown = [...first.controller.messages];
    ready.transport.holdNextOpen = true;
    ready.connection.pageResult = Completer<ConversationPage>()
      ..complete(
        ConversationPage(items: const [], before: before, hasOlder: true),
      );
    await ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    final state = ready.owner.source.value!;
    expect(state.isLoadingOlder, isFalse);
    expect(
      state.olderError,
      isA<StudioFailure>()
          .having((error) => error.code, 'code', StudioFailureCode.protocol)
          .having(
            (error) => error.correlationId,
            'correlationId',
            'timeline-page-continuity',
          ),
    );
    expect(ready.owner.lease('thread'), same(first));
    expect(first.controller.messages, shown, reason: '新基线成功前保留原内容及协议错误');
    await _until(() => ready.transport.connections.length == 2);
    expect(ready.transport.opens, 2);
    expect(ready.connection.pageRequests, [(before: before, limit: 32)]);
    ready.transport.completeOpen(version: 23);
    await ready.owner.source
        .waitFor(
          (state) =>
              state != null &&
              state.generation > first.generation &&
              state.connection == TimelineConnectionPhase.ready,
        )
        .timeout(const Duration(seconds: 5));
    final second = ready.owner.lease('thread')!;
    final current = ready.transport.connections.last;
    final currentBefore = second.olderCursor;
    expect(second, isNot(same(first)));
    expect(second.appliedVersion, 23);
    expect(second.controller.messages.map((message) => message.id), ['a', 'b']);
    await _until(() => ready.connection.closeCalls == 1);
    expect(current.pageRequests, isEmpty);
    current.pageResult = Completer<ConversationPage>()
      ..complete(
        const ConversationPage(items: [], before: null, hasOlder: false),
      );
    await ready.owner.retryOlder('thread', generation: second.generation);
    expect(ready.owner.source.value!.olderError, isNull);
    expect(ready.owner.source.value!.hasOlder, isFalse);
    expect(current.pageRequests, [(before: currentBefore, limit: 32)]);
    expect(ready.connection.pageRequests, hasLength(1));
    expect(ready.transport.opens, 2);
  });

  test('History 连接恢复不复用旧覆盖，显式回实时后新资格可完成分页', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final frozen = [...lease.controller.messages];
    final before = lease.olderCursor;
    final error = StateError('page failed');
    ready.connection.pageResult = Completer<ConversationPage>()
      ..completeError(error);
    await ready.owner.loadOlder('thread', generation: lease.generation);
    expect(ready.owner.source.value!.olderError, same(error));
    await ready.owner.dispatch('thread', const TimelineEnterHistory());
    ready.transport.holdNextOpen = true;
    ready.client.conversations.session('thread').content.refresh();
    await _until(
      () =>
          ready.owner.source.value!.connection != TimelineConnectionPhase.ready,
    );
    await ready.owner.retryOlder('thread', generation: lease.generation);
    expect(ready.owner.source.value!.olderError, same(error));
    expect(ready.owner.source.value!.isLoadingOlder, isFalse);
    await _until(() => ready.transport.connections.length == 2);
    ready.transport.completeOpen(version: 23);
    await _until(
      () =>
          ready.owner.source.value!.connection == TimelineConnectionPhase.ready,
    );
    final background = ready.transport.connections.last;
    expect(ready.owner.lease('thread'), same(lease));
    expect(lease.controller.messages, frozen);
    expect(ready.owner.source.value!.olderError, same(error));
    expect(background.pageRequests, isEmpty);
    // 原 History 资格属于已退役 attempt：拒绝发生在领域准入，不能向新 feed 发旧 cursor。
    ready.transport.holdNextOpen = true;
    await ready.owner.retryOlder('thread', generation: lease.generation);
    expect(
      ready.owner.source.value!.olderError,
      isA<StudioFailure>()
          .having((failure) => failure.code, 'code', StudioFailureCode.protocol)
          .having(
            (failure) => failure.correlationId,
            'correlationId',
            'timeline-page-continuity',
          ),
    );
    expect(ready.owner.source.value!.isLoadingOlder, isFalse);
    expect(ready.owner.lease('thread'), same(lease));
    expect(lease.controller.messages, frozen);
    expect(background.pageRequests, isEmpty);
    final coverageError = ready.owner.source.value!.olderError;
    await _until(() => ready.transport.connections.length == 3);
    expect(ready.transport.opens, 3, reason: '本次资格拒绝只刷新一次，不自动重放旧页');
    ready.transport.completeOpen(version: 24);
    await _until(
      () =>
          ready.owner.source.value!.connection == TimelineConnectionPhase.ready,
    );
    expect(ready.owner.lease('thread'), same(lease));
    expect(lease.controller.messages, frozen);
    expect(ready.owner.source.value!.olderError, same(coverageError));
    expect(ready.transport.connections.last.pageRequests, isEmpty);
    ready.transport.holdNextOpen = true;
    final switching = ready.owner.returnToLive('thread');
    await _until(() => ready.transport.connections.length == 4);
    expect(ready.owner.lease('thread'), same(lease), reason: '显式回实时仍等真实新基线');
    ready.transport.completeOpen(version: 25);
    await switching.timeout(const Duration(seconds: 5));
    final live = ready.owner.lease('thread')!;
    final current = ready.transport.connections.last;
    final liveBefore = live.olderCursor;
    expect(live, isNot(same(lease)));
    expect(live.generation, greaterThan(lease.generation));
    expect(live.appliedVersion, 25);
    expect(ready.owner.source.value!.mode, TimelineDisplayMode.live);
    expect(current.pageRequests, isEmpty);
    current.pageResult = Completer<ConversationPage>()
      ..complete(
        const ConversationPage(items: [], before: null, hasOlder: false),
      );
    await ready.owner.loadOlder('thread', generation: live.generation);
    expect(ready.owner.source.value!.olderError, isNull);
    expect(ready.owner.source.value!.hasOlder, isFalse);
    expect(current.pageRequests, [(before: liveBefore, limit: 32)]);
    expect(ready.connection.pageRequests, [(before: before, limit: 32)]);
    expect(background.pageRequests, isEmpty);
    expect(ready.transport.connections[2].pageRequests, isEmpty);
    expect(ready.transport.opens, 4);
    await _until(
      () => ready.transport.connections
          .take(3)
          .every((feed) => feed.closeCalls == 1),
    );
    expect(current.closeCalls, 0);
  });

  test('History 页无法连接冻结范围时保留内容并显示可重试错误', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    await ready.owner.dispatch('thread', const TimelineEnterHistory());
    ready.transport.holdNextOpen = true;
    ready.connection.pageResult = Completer<ConversationPage>()
      ..complete(
        ConversationPage(
          items: [text('unknown-in-covered-range', 1, ordinal: 2)],
          before: 'tlp1.earlier',
          hasOlder: true,
        ),
      );
    await ready.owner.loadOlder('thread', generation: lease.generation);
    expect(ready.owner.source.value!.olderError, isA<StudioFailure>());
    expect(ready.owner.source.value!.isLoadingOlder, isFalse);
    expect(ready.owner.lease('thread'), same(lease));
    expect(lease.loadedCount, 2);
    ready.transport.completeOpen(version: 25);
    await _until(
      () =>
          ready.owner.source.value!.connection == TimelineConnectionPhase.ready,
    );
    expect(ready.owner.source.value!.olderError, isA<StudioFailure>());
  });

  test('登记观察时消费已经就绪的当前基线', () async {
    final ready = await open();
    final secondOwner = TimelineSessionOwner(client: ready.client)
      ..select('thread');
    addTearDown(secondOwner.close);
    expect(secondOwner.lease('thread'), isNotNull);
    expect(secondOwner.source.value!.generation, greaterThan(0));
    expect(secondOwner.lease('thread')!.loadedCount, 2);
  });

  test('Session 准入失败后重试创建资源，展示重新绑定当前基线', () async {
    final budget = ResourceBudget(
      capacities: {...ResourceBudget().capacities, ResourceKind.readModel: 8},
    );
    final held = [
      for (var i = 0; i < 8; i++)
        budget.acquire(ResourceKind.readModel, owner: 'held-read-model-$i'),
    ];
    final transport = _ScriptedTransport();
    final client = AnyworkClient(
      transport: transport,
      clientId: 'retry-owner',
      budget: budget,
    );
    final owner = TimelineSessionOwner(client: client);
    addTearDown(owner.close);
    addTearDown(() async {
      for (final permit in held) {
        permit.release();
      }
      await owner.close();
      await client.close();
    });
    client.threadDirectory.applyBaseline(
      ThreadDirectoryPage(threads: [_thread()], revision: 1),
      revision: 1,
    );
    expect(
      () => client.conversations.setVisibleThread('thread'),
      throwsA(
        isA<ResourceBudgetExceeded>()
            .having((error) => error.kind, 'kind', ResourceKind.readModel)
            .having((error) => error.capacity, 'capacity', 8),
      ),
    );
    expect(client.conversations.existingSession('thread'), isNull);
    expect(owner.lease('thread'), isNull);
    expect(transport.connections, isEmpty, reason: 'Session 未准入不得建立 feed');
    for (final permit in held) {
      permit.release();
    }
    // 首次准入失败没有创建 Session；清除失败需求后以同一预算重试真实准入。
    client.conversations.setVisibleThread(null);
    client.conversations.setVisibleThread('thread');
    owner.select('thread');
    await _until(() => transport.connections.isNotEmpty);
    await transport.connections.single.opened.future;
    await client.conversations.existingSession('thread')!.content.ready;
    expect(owner.lease('thread'), isNotNull);
    expect(owner.lease('thread')!.loadedCount, 2);
  });

  test('a page reply for a retired generation is dropped', () async {
    final ready = await open();
    final first = ready.owner.lease('thread')!;
    final page = Completer<ConversationPage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    expect(ready.owner.source.value!.isLoadingOlder, isTrue);

    // 显式回实时建立新代次：旧代次的页回包不得写新展示。
    ready.transport.holdNextOpen = true;
    final switching = ready.owner.returnToLive('thread');
    await ready.owner.source.waitFor((state) => state!.isPreparingLive);
    page.complete(
      ConversationPage(
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
    await ready.owner.loadOlder('thread', generation: first.generation);
    await ready.owner.retryOlder('thread', generation: first.generation);
    expect(ready.owner.source.value!.isLoadingOlder, isFalse);
    expect(second.loadedCount, 2, reason: '旧视图的触发也不得向新代次发页');
    await first.released;
    expect(first.isReleased, isTrue);
  });

  test(
    'page failures keep content, close loading and expose a retry',
    () async {
      final ready = await open();
      final lease = ready.owner.lease('thread')!;
      final page = Completer<ConversationPage>();
      ready.connection.pageResult = page;
      final loading = ready.owner.loadOlder(
        'thread',
        generation: ready.owner.lease('thread')!.generation,
      );
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

      final retried = Completer<ConversationPage>();
      ready.connection.pageResult = retried;
      final retrying = ready.owner.retryOlder(
        'thread',
        generation: ready.owner.lease('thread')!.generation,
      );
      expect(ready.owner.source.value!.olderError, isNull);
      retried.complete(
        const ConversationPage(items: [], before: null, hasOlder: false),
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
    String subscriptionId() => ready.connection.subscriptionId;

    ready.connection.emit(
      ConversationPatch(
        subscriptionId: subscriptionId(),
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
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
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b'],
      reason: '稳定身份与位置：不 remove/reinsert、不追加成最新消息',
    );
    final payload = timelineEntryOf(lease.controller.messages.first)!.first;
    expect(timelineText(payload), 'body-a 已补齐');
    expect(payload.revision, 7);
    expect(payload.saved, isTrue, reason: '更高 revision 采纳它自己的保存事实');
    expect(payload.header.ordinal, 1);
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
      ConversationPatch(
        subscriptionId: subscriptionId(),
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
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
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    final revised = timelineEntryOf(lease.controller.messages.first)!.first;
    expect(revised.revision, 8);
    expect(revised.saved, isFalse, reason: '旧 saved 水位不补到新 revision');
    expect(ready.connection.closeCalls, 0, reason: '不重连、不换代次');
    expect(ready.owner.lease('thread'), same(lease));
  });

  test('更旧 revision 的权威 Add 不覆盖已加载事实', () {
    final content = conversationContentFixture();
    final loaded = item(
      id: 'b',
      revision: 3,
      ordinal: 2,
      body: '新正文',
      saved: true,
    );
    final stale = item(id: 'b', revision: 1, ordinal: 2, body: '过期的旧正文');
    expect(content.mergeItem(loaded, stale), same(loaded));
    final noChange = content.mergeItem(
      loaded,
      item(id: 'b', revision: 3, ordinal: 2, body: '新正文', saved: true),
    );
    expect(noChange.revision, 3);
    expect(timelineText(noChange), '新正文', reason: '已加载事实不被回退');
    expect(
      () => content.mergeItem(
        loaded,
        item(id: 'b', revision: 4, ordinal: 9, body: '新正文'),
      ),
      throwsA(isA<ConversationContinuityError>()),
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

          details: const [
            ConversationDetailRef(
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
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
            item(
              id: 'preview',
              revision: 2,
              ordinal: 2,
              body: 'abcdefgh',
              saved: true,
              terminal: true,
              details: const [
                ConversationDetailRef(
                  field: ThreadTextFieldView(),
                  revision: 2,
                  totalBytes: 8,
                  previewBytes: 8,
                ),
              ],
            ),
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    final payload = timelineEntryOf(lease.controller.messages.single)!.first;
    expect(timelineText(payload), 'abcdefgh');
    expect(payload.omittedBytes, 0);
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
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
            item(id: 'a', revision: 1, ordinal: 1, body: '完全不同的正文'),
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await ready.owner.source
        .waitFor(
          (state) =>
              state != null &&
              state.generation > lease.generation &&
              state.connection == TimelineConnectionPhase.ready,
        )
        .timeout(const Duration(seconds: 5));
    final replacement = ready.owner.lease('thread')!;
    expect(ready.transport.opens, 2, reason: '冲突只触发一次真实重同步');
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
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
            item(id: 'b', revision: 2, ordinal: 2, body: 'body-b'),
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b', 'c'],
      reason: '不把已覆盖范围内的新身份追加成最新消息',
    );
    await _until(
      () => operations.any(
        (operation) => operation.type == ChatOperationType.insertAll,
      ),
    );
    final structural = operations
        .where((operation) => operation.type != ChatOperationType.update)
        .toList();
    expect(
      structural,
      hasLength(1),
      reason: '只插入新身份，不 remove/reinsert 已加载消息或替换整个列表',
    );
    final insert = structural.single;
    expect(insert.type, ChatOperationType.insertAll);
    expect(insert.messages, hasLength(1));
    expect(insert.messages!.single.id, 'b');
    expect(insert.index, 1);
    expect(ready.owner.lease('thread'), same(lease));
    expect(ready.transport.opens, 1, reason: 'canonical 顺序插入不重连');
    expect(ready.connection.closeCalls, 0);
  });

  test('更早且未覆盖的新身份不插入也不反复重同步', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    const earlierBody = '更早正文';
    const appended = ' 继续';
    final updatedBytes = utf8.encode('$earlierBody$appended').length;
    var applied = lease.appliedVersion!;
    ready.connection.emit(
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
            item(id: 'older', revision: 1, ordinal: 0, body: earlierBody),
          ),
          ConversationUpdateItem(
            itemId: 'older',
            expectedRevision: 1,
            revision: 4,

            saved: false,
            lifecycle: ConversationLifecycle.streaming,
            header: item(
              id: 'older',
              revision: 4,
              ordinal: 0,
              body: earlierBody,
            ).header,
            fields: [
              ConversationFieldUpdate(
                field: const ThreadTextFieldView(),
                change: const AppendThreadFieldChangeView(appended),
                totalBytes: updatedBytes,
                previewBytes: updatedBytes,
              ),
            ],
          ),
        ],
        priority: ConversationPriority.immediate,
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
    final page = Completer<ConversationPage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    page.complete(
      ConversationPage(
        items: [item(id: 'older', revision: 5, ordinal: 0, body: '后续页的权威正文')],
        before: null,
        hasOlder: false,
      ),
    );
    await loading;
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['older', 'a', 'b'],
    );
    final payload = timelineEntryOf(lease.controller.messages.first)!.first;
    expect(payload.revision, 5);
    expect(timelineText(payload), '后续页的权威正文');
    expect(lease.appliedVersion, applied, reason: '分页不抬高内容水位');
  });

  test('真实删除最早行后覆盖边界仍在，更早身份仍不插入', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: const [ConversationRemove('a'), ConversationRemove('b')],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(lease.controller.messages, isEmpty);

    final watermark = lease.appliedVersion!;
    ready.connection.emit(
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: watermark,
        to: watermark + 1,
        changes: [
          ConversationAdd(
            item(id: 'deleted-floor', revision: 1, ordinal: 0, body: '更早正文'),
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == watermark + 1);
    expect(lease.controller.messages, isEmpty, reason: '删除行不抹掉已覆盖范围的下界');
    expect(ready.transport.opens, 1);

    final page = Completer<ConversationPage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    page.complete(
      ConversationPage(
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
    expect(
      timelineEntryOf(lease.controller.messages.single)!.first.revision,
      6,
    );
  });

  test('新代次从自身空闲分页状态开始，旧页回包不能污染新代次', () async {
    final ready = await open();
    final first = ready.owner.lease('thread')!;
    final page = Completer<ConversationPage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    expect(ready.owner.source.value!.isLoadingOlder, isTrue);

    ready.transport.holdNextOpen = true;
    final switching = ready.owner.returnToLive('thread');
    await ready.owner.source.waitFor((state) => state!.isPreparingLive);
    page.complete(
      ConversationPage(
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
    final nextPage = Completer<ConversationPage>();
    secondConnection.pageResult = nextPage;
    final loadingSecond = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    expect(ready.owner.source.value!.isLoadingOlder, isTrue);
    nextPage.complete(
      ConversationPage(
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
    final page = Completer<ConversationPage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    expect(ready.owner.source.value!.isLoadingOlder, isTrue);

    ready.connection.emit(
      ConversationResync(
        subscriptionId: ready.connection.subscriptionId,
        reason: ConversationResyncReason.lagging,
        baseline: ConversationBaseline(
          subscriptionId: ready.connection.subscriptionId,
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
      ConversationPage(
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

    final nextPage = Completer<ConversationPage>();
    ready.connection.pageResult = nextPage;
    final loadingSecond = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    nextPage.complete(
      ConversationPage(
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
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
            item(id: 'x', revision: 1, ordinal: 4, body: 'body-x'),
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b'],
    );

    // 这一页把 ordinal 3 纳入覆盖，[3,5) 里已知存在的 'x' 却没被交付：游标会越过它，
    // 不能静默丢消息，必须显式重同步。
    final page = Completer<ConversationPage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    page.complete(
      ConversationPage(
        items: [item(id: 'y', revision: 1, ordinal: 3, body: 'body-y')],
        before: null,
        hasOlder: false,
      ),
    );
    await loading;
    await ready.owner.source
        .waitFor(
          (state) =>
              state != null &&
              state.generation > lease.generation &&
              state.connection == TimelineConnectionPhase.ready,
        )
        .timeout(const Duration(seconds: 5));
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
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
            item(id: 'x', revision: 1, ordinal: 4, body: 'body-x'),
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);

    final page = Completer<ConversationPage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    page.complete(
      ConversationPage(
        items: [
          item(id: 'y', revision: 1, ordinal: 3, body: 'body-y'),
          item(id: 'x', revision: 7, ordinal: 4, body: '页里的权威正文'),
        ],
        before: null,
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
      timelineEntryOf(lease.controller.messages[1])!.first.revision,
      7,
      reason: '页读取当时的权威值',
    );
    expect(ready.transport.opens, 1);
    expect(ready.owner.lease('thread'), same(lease));
  });

  test('History 下纯保存确认与空批次不制造新输出提示', () async {
    const bodyRef = ConversationDetailRef(
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
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: watermark,
        to: watermark + 1,
        changes: const [],
        priority: ConversationPriority.coalesced,
      ),
    );
    await _until(() => ready.connection.acknowledgements.length >= 3);
    expect(ready.owner.source.value!.hasNewOutput, isFalse);

    // 纯保存确认：同 revision、字段 Unchanged 且总长未变。
    ready.connection.emit(
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: watermark + 1,
        to: watermark + 2,
        changes: [
          ConversationUpdateItem(
            itemId: 'b',
            expectedRevision: 2,
            revision: 2,

            saved: true,
            lifecycle: ConversationLifecycle.terminal,
            fields: const [
              ConversationFieldUpdate(
                field: ThreadTextFieldView(),
                change: UnchangedThreadFieldChangeView(),
                totalBytes: 6,
                previewBytes: 6,
              ),
            ],
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => ready.connection.acknowledgements.length >= 4);
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
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: watermark + 2,
        to: watermark + 3,
        changes: [
          ConversationUpdateItem(
            itemId: 'b',
            expectedRevision: 2,
            revision: 3,

            saved: true,
            lifecycle: ConversationLifecycle.terminal,
            fields: const [
              ConversationFieldUpdate(
                field: ThreadTextFieldView(),
                change: AppendThreadFieldChangeView(' 继续'),
                totalBytes: 12,
                previewBytes: 12,
              ),
            ],
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await ready.owner.source.waitFor((state) => state!.hasNewOutput);
    expect(lease.controller.messages, frozen);
  });

  test('页查询在途时到达的尾部新身份与页结果按 canonical 顺序合并', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final page = Completer<ConversationPage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    expect(ready.owner.source.value!.isLoadingOlder, isTrue);

    // 页回包之前，尾部先交付一条更新身份（落在已覆盖范围之后）。
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
            item(id: 'tail', revision: 4, ordinal: 4, body: 'body-tail'),
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b', 'tail'],
    );

    page.complete(
      ConversationPage(
        items: [item(id: 'older', revision: 1, ordinal: 0, body: 'body-older')],
        before: null,
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
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
            conversationCopyFixture(
              incoming,
              saved: incoming.saved,
              lifecycle: incoming.lifecycle,
              turnId: 'turn-rebound',
              updatedAt: DateTime.utc(2027),
              totalBytes: {
                for (final ref in incoming.details) ref.field: ref.totalBytes,
              },
            ),
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(
      [for (final message in lease.controller.messages) message.id],
      ['a', 'b'],
      reason: '稳定身份与位置不变',
    );
    final payload = timelineEntryOf(lease.controller.messages.first)!.first;
    expect(payload.header.turnId, 'turn-rebound');
    expect(payload.header.updatedAt, DateTime.utc(2027));
    expect(timelineText(payload), 'body-a');
  });

  test('更高 revision 的权威 Add 不得把终态退回流式', () async {
    final terminalItem = conversationFixture(
      id: 'done',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 4,
      revision: 3,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      saved: true,
      lifecycle: ConversationLifecycle.terminal,
      descriptor: ConversationTextDescriptor(
        channel: ThreadTextChannel.finalAnswer,
        attachments: const [],
        lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
      ),
      fields: {const ThreadTextFieldView(): 'abc'},
    );
    final ready = await open(
      items: [
        conversationCopyFixture(
          terminalItem,
          saved: true,
          lifecycle: ConversationLifecycle.terminal,
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationAdd(
            item(id: 'done', revision: 4, ordinal: 4, body: 'abc 更长的正文'),
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await ready.owner.source
        .waitFor(
          (state) =>
              state != null &&
              state.generation > lease.generation &&
              state.connection == TimelineConnectionPhase.ready,
        )
        .timeout(const Duration(seconds: 5));
    final replacement = ready.owner.lease('thread')!;
    expect(replacement, isNot(same(lease)));
    expect(ready.transport.opens, 2, reason: '终态回退只触发一次真实重同步');
    expect(
      timelineEntryOf(replacement.controller.messages.single)!.first.terminal,
      isTrue,
      reason: '显式重同步建立的新基线仍保持终态',
    );
  });

  test('逐字段字节账目一致，整体省略量由事实派生（Add 与 UpdateItem）', () {
    final content = conversationContentFixture();
    final current = conversationCopyFixture(
      item(id: 'acct', revision: 1, ordinal: 11, body: 'abcd'),
      totalBytes: {const ThreadTextFieldView(): 8},
    );
    ConversationUpdateItem update({required int preview}) =>
        ConversationUpdateItem(
          itemId: 'acct',
          expectedRevision: 1,
          revision: 2,
          saved: false,
          lifecycle: ConversationLifecycle.streaming,
          fields: [
            ConversationFieldUpdate(
              field: const ThreadTextFieldView(),
              change: const ReplaceThreadFieldChangeView('abce'),
              totalBytes: 8,
              previewBytes: preview,
            ),
          ],
        );
    expect(
      () => content.reduceItem(current, update(preview: 3)),
      throwsA(isA<ConversationContinuityError>()),
    );
    final applied = content.reduceItem(current, update(preview: 4));
    expect(applied.omittedBytes, 4);
    expect(applied.detailFor(const ThreadTextFieldView())!.revision, 2);
    final invalid = conversationCopyFixture(
      current,
      revision: 2,
      fields: {const ThreadTextFieldView(): 'abcdefgh'},
      totalBytes: {const ThreadTextFieldView(): 7},
    );
    expect(
      () => content.mergeItem(current, invalid),
      throwsA(isA<ConversationContinuityError>()),
      reason: '权威 Add 同样拒绝实际预览超过 totalBytes',
    );
    final full = content.mergeItem(
      current,
      conversationCopyFixture(
        current,
        revision: 2,
        fields: {const ThreadTextFieldView(): 'abcdefgh'},
        totalBytes: {const ThreadTextFieldView(): 8},
      ),
    );
    expect(full.omittedBytes, 0);
    expect(full.detailFor(const ThreadTextFieldView())!.previewBytes, 8);
  });

  test('同 revision 跨字段互补按各字段合并，冲突正文拒绝而不猜账目', () {
    final content = conversationContentFixture();
    final descriptor = ConversationToolDescriptor(
      invocation: const ConversationToolInvocation(
        toolCallId: 'mixed',
        name: 'exec',
      ),
      state: const ConversationToolRunning(),
    );
    final current = conversationFixture(
      id: 'mixed',
      threadId: 'thread',
      revision: 5,
      descriptor: descriptor,
      lifecycle: ConversationLifecycle.streaming,
      fields: {
        const ThreadToolArgumentsFieldView(): 'abcd',
        const ThreadToolResultFieldView(): 'abcdefgh',
      },
      totalBytes: {
        const ThreadToolArgumentsFieldView(): 8,
        const ThreadToolResultFieldView(): 8,
      },
    );
    final incoming = conversationCopyFixture(
      current,
      fields: {
        const ThreadToolArgumentsFieldView(): 'abcdefgh',
        const ThreadToolResultFieldView(): 'abcd',
      },
    );
    final merged = content.mergeItem(current, incoming);
    expect(merged.omittedBytes, 0);
    expect(
      merged.fieldFor(const ThreadToolArgumentsFieldView())!.text,
      'abcdefgh',
    );
    expect(
      merged.fieldFor(const ThreadToolResultFieldView())!.text,
      'abcdefgh',
    );
    expect(current.omittedBytes, 4, reason: '合并不反写输入快照');
    final conflict = conversationCopyFixture(
      incoming,
      fields: {
        const ThreadToolArgumentsFieldView(): 'abce',
        const ThreadToolResultFieldView(): 'abcd',
      },
    );
    expect(
      () => content.mergeItem(current, conflict),
      throwsA(isA<ConversationContinuityError>()),
      reason: '同一字段不连续则必须交给显式重同步',
    );
    final full = content.mergeItem(
      current,
      conversationCopyFixture(
        current,
        fields: {
          const ThreadToolArgumentsFieldView(): 'abcdefgh',
          const ThreadToolResultFieldView(): 'abcdefgh',
        },
      ),
    );
    expect(full.omittedBytes, 0);
    expect(full.details.every((ref) => !ref.truncated), isTrue);
  });

  test('退役但未释放的代次接受迟到真实挂载，已释放则明确拒绝', () async {
    final ready = await open();
    final lease = ready.owner.lease('thread')!;
    final page = Completer<ConversationPage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    final report = await ready.owner.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 40)),
    );
    expect(report.complete, isFalse);
    // 关闭已发布无展示，但真实旧子树可能还没卸载：迟到挂载必须计入等待。
    lease.bind();
    expect(lease.isMounted, isTrue);
    page.complete(
      const ConversationPage(items: [], before: null, hasOlder: false),
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
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationUpdateItem(
            itemId: 'a',
            expectedRevision: 1,
            revision: 1,

            saved: false,
            lifecycle: ConversationLifecycle.terminal,
            fields: const [
              ConversationFieldUpdate(
                field: ThreadTextFieldView(),
                change: UnchangedThreadFieldChangeView(),
                totalBytes: 6,
                previewBytes: 3,
              ),
            ],
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await ready.owner.source
        .waitFor(
          (state) =>
              state != null &&
              state.generation > lease.generation &&
              state.connection == TimelineConnectionPhase.ready,
        )
        .timeout(const Duration(seconds: 5));
    expect(ready.transport.opens, 2, reason: '预览冲突只触发一次真实重同步');
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
            ConversationDetailRef(
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
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationUpdateItem(
            itemId: 'short',
            expectedRevision: 1,
            revision: 2,

            saved: false,
            lifecycle: ConversationLifecycle.terminal,
            fields: const [
              ConversationFieldUpdate(
                field: ThreadTextFieldView(),
                change: ReplaceThreadFieldChangeView('abc'),
                totalBytes: 3,
                previewBytes: 3,
              ),
            ],
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    expect(ready.transport.opens, 1, reason: '权威缩短不能被当成预算缩减拒绝');
    final payload = timelineEntryOf(lease.controller.messages.single)!.first;
    expect(timelineText(payload), 'abc');
    expect(payload.revision, 2);
    expect(payload.detailFor(const ThreadTextFieldView())!.totalBytes, 3);
  });

  test('非 const 解码的同值字段在多帧后仍复用同一条详情引用', () async {
    final thinking = conversationFixture(
      id: 'reasoning',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 3,
      revision: 5,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      lifecycle: ConversationLifecycle.terminal,
      descriptor: ConversationThinkingDescriptor(
        lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
      ),
      fields: {
        ThreadThinkingContentFieldView(0): '第一段',
        ThreadThinkingContentFieldView(1): '第二段',
      },
    );
    final ready = await open(
      items: [
        conversationCopyFixture(
          thinking,
          saved: false,
          lifecycle: ConversationLifecycle.terminal,
          totalBytes: {
            for (final ref in [
              ConversationDetailRef(
                field: ThreadThinkingContentFieldView(0),
                revision: 5,
                totalBytes: 9,
                previewBytes: 9,
              ),
              ConversationDetailRef(
                field: ThreadThinkingContentFieldView(1),
                revision: 5,
                totalBytes: 9,
                previewBytes: 9,
              ),
            ])
              ref.field: ref.totalBytes,
          },
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    var revision = 5;
    for (var round = 0; round < 3; round++) {
      final applied = lease.appliedVersion!;
      ready.connection.emit(
        ConversationPatch(
          subscriptionId: ready.connection.subscriptionId,
          from: applied,
          to: applied + 1,
          changes: [
            ConversationUpdateItem(
              itemId: 'reasoning',
              expectedRevision: revision,
              revision: revision + 1,

              saved: false,
              lifecycle: ConversationLifecycle.terminal,
              fields: [
                ConversationFieldUpdate(
                  // 真实解码每帧都是新实例。
                  field: ThreadThinkingContentFieldView(0),
                  change: const AppendThreadFieldChangeView('+'),
                  totalBytes: 10 + round,
                  previewBytes: 10 + round,
                ),
              ],
            ),
          ],
          priority: ConversationPriority.immediate,
        ),
      );
      revision += 1;
      await _until(() => lease.appliedVersion == applied + 1);
    }
    final payload = timelineEntryOf(lease.controller.messages.single)!.first;
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
      query: ConversationDetailQuery(
        field: unchanged.field,
        revision: unchanged.revision,
      ),
    );
    expect(unchangedChunk.revision, 8);
    expect(unchangedChunk.itemId, 'reasoning');
    final changedChunk = await scope.readDetail(
      itemId: 'reasoning',
      query: ConversationDetailQuery(
        field: changed.field,
        revision: changed.revision,
      ),
    );
    expect(changedChunk.revision, 8);

    // 真 Remove 必须真的消失（而不是匹配不上旧键后留在表里）。
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationUpdateItem(
            itemId: 'reasoning',
            expectedRevision: 8,
            revision: 9,

            saved: false,
            lifecycle: ConversationLifecycle.terminal,
            fields: [
              ConversationFieldUpdate(
                field: ThreadThinkingContentFieldView(1),
                change: const RemoveThreadFieldChangeView(),
                totalBytes: 0,
                previewBytes: 0,
              ),
            ],
          ),
        ],
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    final afterRemoval = timelineEntryOf(lease.controller.messages.single)!
        .first;
    expect(afterRemoval.details.length, 1);
    expect(afterRemoval.detailFor(ThreadThinkingContentFieldView(1)), isNull);
  });

  test('嵌套问答子字段按值语义更新同一条详情引用', () async {
    ConversationItem ask({required String answer}) => conversationFixture(
      id: 'ask',
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 4,
      revision: 2,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      lifecycle: ConversationLifecycle.terminal,
      descriptor: ConversationToolDescriptor(
        invocation: ConversationToolInvocation(
          toolCallId: 'call-1',
          name: 'ask',
        ),
        userInput: (conversationInputFixture(
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
          state: ConversationUserInputResolved(
            answers: [
              ConversationAnswerDescriptor(
                questionId: 'q1',
                answerCount: ([answer]).length,
                redacted: false,
              ),
            ],
          ),
          answers: {
            'q1': [answer],
          },
        )).descriptor,
        state: ConversationToolSucceeded(
          completedAt: DateTime.utc(2026),
          output: ConversationToolOutputDescriptor(attachments: []),
        ),
      ),
      fields: {
        const ThreadToolArgumentsFieldView(): '{}',
        const ThreadToolResultFieldView(): 'ok',
        ...(conversationInputFixture(
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
          state: ConversationUserInputResolved(
            answers: [
              ConversationAnswerDescriptor(
                questionId: 'q1',
                answerCount: ([answer]).length,
                redacted: false,
              ),
            ],
          ),
          answers: {
            'q1': [answer],
          },
        )).fields,
      },
    );
    final ready = await open(
      items: [
        conversationCopyFixture(
          ask(answer: '是'),
          saved: false,
          lifecycle: ConversationLifecycle.terminal,
          totalBytes: {
            for (final ref in [
              ConversationDetailRef(
                field: ThreadToolUserInputFieldView(
                  questionIndex: 0,
                  part: ThreadUserInputAnswerFieldPartView(0),
                ),
                revision: 2,
                totalBytes: 3,
                previewBytes: 3,
              ),
            ])
              ref.field: ref.totalBytes,
          },
        ),
      ],
    );
    final lease = ready.owner.lease('thread')!;
    final applied = lease.appliedVersion!;
    ready.connection.emit(
      ConversationPatch(
        subscriptionId: ready.connection.subscriptionId,
        from: applied,
        to: applied + 1,
        changes: [
          ConversationUpdateItem(
            itemId: 'ask',
            expectedRevision: 2,
            revision: 3,

            saved: false,
            lifecycle: ConversationLifecycle.terminal,
            fields: [
              ConversationFieldUpdate(
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
        priority: ConversationPriority.immediate,
      ),
    );
    await _until(() => lease.appliedVersion == applied + 1);
    final payload = timelineEntryOf(lease.controller.messages.single)!.first;
    const answerField = ThreadToolUserInputFieldView(
      questionIndex: 0,
      part: ThreadUserInputAnswerFieldPartView(0),
    );
    expect(
      payload.details.where((ref) => ref.field == answerField),
      hasLength(1),
      reason: '同一子字段不能新增一条引用；新 DTO 的其它字段也各自派生详情引用',
    );
    expect(
      payload.fields.map((field) => field.field).toSet().length,
      payload.fields.length,
    );
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
    client.conversations.session('other'); // 镜像不产生需求；B 的状态由它自己的 feed 交付。
    final composer = client.drafts.composer('thread');
    composer.updateDraft('frozen text');

    // A 的展示准备会新建订阅：把它挂起，模拟“首帧未到”期间用户切换选择。
    ready.transport.holdNextOpen = true;
    final submitting = composer.submit(
      beforeSubmit: () => owner.prepareSend('thread'),
    );
    await owner.source.waitFor((state) => state!.isPreparingLive);

    client.selection.selectThread(threadId: 'other', workspaceId: 'project');
    owner.select(null);
    client.conversations.setVisibleThread('other');
    owner.select('other');
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
    ready.client.conversations.session('other');
    ready.transport.holdNextOpen = true;
    final switching = ready.owner.returnToLive('thread');
    await ready.owner.source.waitFor((state) => state!.isPreparingLive);
    ready.client.selection.selectThread(
      threadId: 'other',
      workspaceId: 'project',
    );
    ready.owner.select(null);
    ready.client.conversations.setVisibleThread('other');
    ready.owner.select('other');
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
    final budget = ready.client.budget;
    final page = Completer<ConversationPage>();
    ready.connection.pageResult = page;
    final loading = ready.owner.loadOlder(
      'thread',
      generation: ready.owner.lease('thread')!.generation,
    );
    expect(budget.used(ResourceKind.pendingOperation), 1);

    final report = await ready.owner.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 40)),
    );
    expect(report.complete, isFalse, reason: '在途查询仍持有许可');
    expect(lease.isReleased, isFalse);
    expect(budget.used(ResourceKind.pendingOperation), 1);

    page.complete(
      const ConversationPage(items: [], before: null, hasOlder: false),
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
  workspaceId: 'project',
  title: 'Thread $id',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/project',
);

final class _ScriptedTransport implements StudioTransport {
  final List<_ScriptedConnection> connections = [];

  /// 非空时所有连接都用它作为首帧条目。
  List<ConversationItem>? baselineItems;
  ThreadWorkspace Function(String threadId)? workspace;
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
  Future<ConversationFeed> openConversationFeed(String threadId) {
    opens++;
    final failure = failOpens;
    if (failure != null) return Future.error(failure);
    final connection = _ScriptedConnection(
      threadId,
      baselineItems,
      workspace?.call(threadId),
    );
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

final class _ScriptedConnection extends ScriptedConversationFeed {
  factory _ScriptedConnection(
    String threadId,
    List<ConversationItem>? items,
    ThreadWorkspace? workspace,
  ) {
    late final _ScriptedConnection connection;
    connection = _ScriptedConnection._(
      threadId,
      items,
      () => connection._baseline(),
      workspace,
    );
    return connection;
  }
  _ScriptedConnection._(
    String threadId,
    this.scriptedItems,
    ConversationBaseline Function() baseline,
    ThreadWorkspace? workspace,
  ) : super(
        threadId: threadId,
        subscriptionId: 'scripted-${++_serial}',
        baseline: baseline,
        state: workspace == null
            ? null
            : () => ThreadSnapshotFrame(workspace: workspace),
      );
  static int _serial = 0;
  final Completer<ConversationFeed> opened = Completer();
  Completer<ConversationPage>? pageResult;
  final List<({String? before, int? limit})> pageRequests = [];
  final List<({String itemId, ConversationDetailQuery query})> detailRequests =
      [];
  final List<ConversationItem>? scriptedItems;
  int baselineVersion = 1;
  ConversationBaseline _baseline() => ConversationBaseline(
    subscriptionId: subscriptionId,
    version: baselineVersion,
    items:
        scriptedItems ??
        [
          for (final entry in [('a', 1), ('b', 2)]) _item(entry.$1, entry.$2),
        ],
    before: 'tlp1.b',
    hasOlder: true,
  );

  @override
  Future<ConversationPage> page({String? before, int? limit}) {
    pageRequests.add((before: before, limit: limit));
    final result = pageResult;
    if (result == null) {
      return Future.value(
        const ConversationPage(items: [], before: null, hasOlder: false),
      );
    }
    return result.future;
  }

  @override
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) async {
    detailRequests.add((itemId: itemId, query: query));
    // 只回一段正文；真实链路按 item/field/revision 校验，这里同样按请求的 revision 交付。
    final text = 'detail:$itemId';
    return ConversationDetailChunk(
      itemId: itemId,
      field: query.field,
      revision: query.revision,
      text: text,
      totalBytes: utf8.encode(text).length,
      continuation: null,
    );
  }

  ConversationItem _item(String id, int revision) => conversationFixture(
    id: id,
    threadId: threadId,
    turnId: 'turn',
    ordinal: revision,
    revision: revision,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: false,
    lifecycle: ConversationLifecycle.terminal,
    descriptor: ConversationTextDescriptor(
      channel: ThreadTextChannel.finalAnswer,
      attachments: const [],
      lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
    ),
    fields: {const ThreadTextFieldView(): 'body-$id'},
  );
}
