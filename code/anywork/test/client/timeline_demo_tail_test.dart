import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/conversation_fixtures.dart';
import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<DemoStudioTransport> demo(Iterable<ConversationItem> items) async {
    final transport = DemoStudioTransport();
    await transport.readBootstrap();
    final query = await transport.openConversationFeed('thread-main');
    final seeded = await query.page(limit: 100);
    await query.close();
    for (final item in seeded.items) {
      transport.retractConversationItem('thread-main', item.id);
    }
    transport.seedConversationItems('thread-main', items);
    return transport;
  }

  Future<ConversationProbe> probe(DemoStudioTransport transport) async {
    final value = ConversationProbe(
      await transport.openConversationFeed('thread-main'),
    );
    addTearDown(value.close);
    return value;
  }

  final overload = isA<StudioFailure>().having(
    (f) => f.code,
    'code',
    StudioFailureCode.overloaded,
  );
  final invalid = isA<StudioFailure>().having(
    (f) => f.code,
    'code',
    StudioFailureCode.invalidArgument,
  );
  final cancelled = isA<StudioFailure>().having(
    (f) => f.code,
    'code',
    StudioFailureCode.cancelled,
  );

  test('首帧只交付最新 32 条并给出真实更早边界；两个订阅各自持有身份', () async {
    final transport = await demo([
      for (var i = 0; i < 45; i++)
        conversationFixture(id: 'item-$i', ordinal: i),
    ]);
    final a = await probe(transport);
    final b = await probe(transport);
    final first = await a.baseline();
    final second = await b.baseline();
    expect(first.items, hasLength(32));
    expect(first.items.first.header.ordinal, 13);
    expect(first.items.last.header.ordinal, 44);
    expect(first.hasOlder, isTrue);
    expect(first.before, isNotNull);
    expect(first.subscriptionId, isNot(second.subscriptionId));
    expect(first.subscriptionId, a.feed.subscriptionId);
    expect(second.subscriptionId, b.feed.subscriptionId);
    final older = await a.feed.page(before: first.before);
    expect(older.items, hasLength(13));
    expect(older.hasOlder, isFalse);
    expect(older.before, isNull, reason: '历史起点不再声明后继分页游标');
    // 相同 EOF 规则也适用于流内首屏，不能让 SDK 在状态帧之后退役该 feed。
    final short = await demo([conversationFixture()]);
    final shortProbe = await probe(short);
    final shortBaseline = await shortProbe.baseline();
    expect(shortBaseline.items, hasLength(1));
    expect(shortBaseline.hasOlder, isFalse);
    expect(shortBaseline.before, isNull);
  });

  test('独立双 credit 满时停止外发，ACK 释放后显式 Resync；一个慢订阅不阻塞另一个', () async {
    final transport = await demo([conversationFixture()]);
    final slow = await transport.openConversationFeed('thread-main');
    final frames = <ConversationFrame>[];
    final firstTwo = Completer<void>();
    final resumed = Completer<void>();
    final subscription = slow.events.listen((frame) {
      frames.add(frame);
      if (frames.length == 2) firstTwo.complete();
      if (frames.length == 3) resumed.complete();
    });
    addTearDown(() async {
      await slow.close();
      await subscription.cancel();
    });
    await firstTwo.future;
    final fast = await probe(transport);
    await fast.baseline();
    transport.seedConversationItems('thread-main', [
      conversationFixture(id: 'next', ordinal: 2),
    ]);
    final patch = await fast.update() as ConversationPatch;
    expect(patch.changes.single, isA<ConversationAdd>());
    await Future<void>.delayed(Duration.zero);
    expect(frames, hasLength(2));
    await slow.acknowledge(1);
    await resumed.future;
    expect(frames.map((f) => f.deliverySequence), [1, 2, 3]);
    final resync =
        (frames.last.event as ConversationUpdateEvent).update
            as ConversationResync;
    expect(resync.baseline.items.map((i) => i.id), ['item', 'next']);
    await slow.acknowledge(1); // old ACK is idempotent
    await expectLater(slow.acknowledge(4), throwsA(invalid));
  });

  test('关闭终帧不等 ACK；空闲、满 credit 与未启动 events 的取消均真实收束', () async {
    for (final mode in ['unstarted', 'idle', 'credit']) {
      final transport = await demo([conversationFixture()]);
      final feed = await transport.openConversationFeed('thread-main');
      final frames = <ConversationFrame>[];
      final terminal = Completer<void>();
      StreamSubscription<ConversationFrame>? subscription;
      if (mode != 'unstarted') {
        final initial = Completer<void>();
        subscription = feed.events.listen((frame) {
          frames.add(frame);
          if (frames.length == 2) initial.complete();
          if (frame.event is ConversationClosedEvent) terminal.complete();
        });
        await initial.future;
        if (mode == 'idle') await feed.acknowledge(2);
      }
      feed.requestClose();
      await feed.close();
      await feed.close();
      if (subscription != null) await terminal.future;
      await subscription?.cancel();
      if (mode != 'unstarted') {
        expect(frames.last.event, isA<ConversationClosedEvent>());
        expect(frames.last.deliverySequence, 2);
        expect(
          frames.where((f) => f.event is ConversationClosedEvent),
          hasLength(1),
        );
      }
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
      transport.seedConversationItems('thread-main', [
        conversationFixture(id: 'after', ordinal: 3),
      ]);
      final fresh = await probe(transport);
      expect((await fresh.baseline()).items.last.id, 'after');
    }
  });

  test('第二 consumer 被拒；零 demand 的事实仍保存而不会生成外发帧', () async {
    final transport = await demo([conversationFixture()]);
    final feed = await transport.openConversationFeed('thread-main');
    transport.seedConversationItems('thread-main', [
      conversationFixture(id: 'before-listen', ordinal: 2),
    ]);
    final p = ConversationProbe(feed);
    addTearDown(p.close);
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
    expect((await p.baseline()).items.last.id, 'before-listen');
  });

  test('未监听句柄从open起受管，shutdown关闭借出stream及迟到factory且不建立demand', () async {
    final transport = await demo([conversationFixture()]);
    final unclaimed = await transport.openConversationFeed('thread-main');
    final borrowed = await transport.openConversationFeed('thread-main');
    final stream = borrowed.events; // 借出但尚未 listen。
    final release = Completer<void>();
    transport.conversationFeedFactory = (_, inner) async {
      await release.future;
      return inner;
    };
    final lateOpen = transport
        .openConversationFeed('thread-main')
        .then<Object>((feed) => feed, onError: (Object error) => error);
    transport.sealForShutdown();
    final joined = transport.cancelDartSubscriptions(budgetMs: 5000);
    for (final feed in [unclaimed, borrowed]) {
      await expectLater(feed.page(), throwsA(cancelled));
      await expectLater(feed.acknowledge(0), throwsA(cancelled));
      await expectLater(
        feed.readDetail(
          itemId: 'item',
          query: const ConversationDetailQuery(
            field: ThreadTextFieldView(),
            revision: 1,
          ),
        ),
        throwsA(cancelled),
      );
    }
    expect(() => unclaimed.events, throwsA(cancelled));
    final frames = <ConversationFrame>[];
    await stream.forEach(frames.add);
    expect(frames, isEmpty, reason: 'shutdown后迟到listen不得物化状态或内容基线');
    release.complete();
    expect(await lateOpen, cancelled);
    expect(await joined, isEmpty);
    await unclaimed.close();
    await unclaimed.close();
    await borrowed.close();

    // 普通 factory 已返回的 wrapper 也必须受管，inner 成功不代表 wrapper joined。
    final normal = await demo([conversationFixture()]);
    normal.conversationFeedFactory = (_, inner) async =>
        _CloseFaultFeed(inner: inner);
    final returned =
        await normal.openConversationFeed('thread-main') as _CloseFaultFeed;
    normal.sealForShutdown();
    final firstCleanup = normal.cancelDartSubscriptions(budgetMs: 5000);
    final concurrentCleanup = normal.cancelDartSubscriptions(budgetMs: 5000);
    for (final issues in await Future.wait([firstCleanup, concurrentCleanup])) {
      expect(issues.any((issue) => issue.stage == 'demo-conversation'), isTrue);
    }
    expect(returned.closeCalls, 1);
    expect(returned.joined.isCompleted, isFalse);
    expect(
      identical(returned.inner.close(), returned.inner.close()),
      isTrue,
      reason: 'inner原关闭future被幂等复用，不重复启动producer cleanup',
    );
    returned.failClose = false;
    expect(await normal.cancelDartSubscriptions(budgetMs: 5000), isEmpty);
    expect(returned.closeCalls, 2);
    expect(returned.joined.isCompleted, isTrue);
    expect(returned.initialCalls, 0);
    expect(await normal.cancelDartSubscriptions(budgetMs: 5000), isEmpty);
    expect(returned.closeCalls, 2, reason: '成功join后不再保留wrapper关闭责任');

    // 迟到 factory 的关闭失败也必须保留 owner，下一次 cleanup 才能真实重试。
    final retrying = await demo([conversationFixture()]);
    final gate = Completer<void>();
    late _CloseFaultFeed fault;
    retrying.conversationFeedFactory = (_, inner) async {
      fault = _CloseFaultFeed(inner: inner);
      await gate.future;
      return fault;
    };
    final rejected = retrying
        .openConversationFeed('thread-main')
        .then<Object>((feed) => feed, onError: (Object error) => error);
    retrying.sealForShutdown();
    final firstJoin = retrying.cancelDartSubscriptions(budgetMs: 5000);
    gate.complete();
    expect(await rejected, isA<StateError>());
    expect(
      (await firstJoin).any((issue) => issue.stage == 'demo-conversation'),
      isTrue,
    );
    expect(fault.joined.isCompleted, isFalse);
    fault.failClose = false;
    expect(await retrying.cancelDartSubscriptions(budgetMs: 5000), isEmpty);
    expect(fault.joined.isCompleted, isTrue);
    expect(fault.closeCalls, 2);
    expect(fault.initialCalls, 0);
  });

  test('连续 Add、字段追加、同版本保存与 Remove 均保持独立版本及原文', () async {
    final transport = await demo([
      conversationFixture(
        saved: false,
        revision: 1,
        fields: {const ThreadTextFieldView(): 'a\n'},
      ),
    ]);
    final p = await probe(transport);
    final baseline = await p.baseline();
    transport.seedConversationItems('thread-main', [
      conversationFixture(
        saved: false,
        revision: 2,
        fields: {const ThreadTextFieldView(): 'a\nb\n'},
      ),
    ]);
    final update = await p.update() as ConversationPatch;
    final item = update.changes.single as ConversationUpdateItem;
    expect(update.from, baseline.version);
    expect(update.to, baseline.version + 1);
    expect(item.expectedRevision, 1);
    expect(item.revision, 2);
    expect(
      (item.fields.single.change as AppendThreadFieldChangeView).text,
      'b\n',
    );
    expect(item.fields.single.totalBytes, 4);
    transport.seedConversationItems('thread-main', [
      conversationFixture(
        saved: true,
        revision: 2,
        fields: {const ThreadTextFieldView(): 'a\nb\n'},
      ),
    ]);
    final saved =
        (await p.update() as ConversationPatch).changes.single
            as ConversationUpdateItem;
    expect(saved.expectedRevision, 2);
    expect(saved.revision, 2);
    expect(saved.saved, isTrue);
    expect(saved.fields, isEmpty);
    transport.retractConversationItem('thread-main', 'item');
    expect(
      ((await p.update() as ConversationPatch).changes.single
              as ConversationRemove)
          .itemId,
      'item',
    );
  });

  test('已交付范围内部的新身份 Resync，更早未交付身份不插入，真实删除仍自包含', () async {
    final transport = await demo([
      conversationFixture(id: 'a', ordinal: 10),
      conversationFixture(id: 'z', ordinal: 20),
    ]);
    final p = await probe(transport);
    await p.baseline();
    transport.seedConversationItems('thread-main', [
      conversationFixture(id: 'older', ordinal: 1),
    ]);
    expect((await p.update() as ConversationPatch).changes, isEmpty);
    transport.seedConversationItems('thread-main', [
      conversationFixture(id: 'inside', ordinal: 15),
    ]);
    final resync = await p.update() as ConversationResync;
    expect(resync.reason, ConversationResyncReason.lagging);
    expect(resync.baseline.items.map((i) => i.id), [
      'older',
      'a',
      'inside',
      'z',
    ]);
    transport.retractConversationItem('thread-main', 'older');
    expect(
      ((await p.update() as ConversationPatch).changes.single
              as ConversationRemove)
          .itemId,
      'older',
    );
    // Remove 不得收缩已覆盖区间，否则 B15 会被误当作早于剩余 Z20 的冷历史。
    for (final sameOrdinal in [false, true]) {
      final scoped = await demo([
        conversationFixture(id: 'A', ordinal: 10),
        conversationFixture(id: 'Z', ordinal: sameOrdinal ? 10 : 20),
      ]);
      final consumer = await probe(scoped);
      final baseline = await consumer.baseline();
      scoped.retractConversationItem('thread-main', 'A');
      final removed = await consumer.update() as ConversationPatch;
      expect(removed.from, baseline.version);
      expect(removed.to, baseline.version + 1);
      expect((removed.changes.single as ConversationRemove).itemId, 'A');
      scoped.seedConversationItems('thread-main', [
        conversationFixture(id: 'B', ordinal: sameOrdinal ? 10 : 15),
      ]);
      final inserted = await consumer.update() as ConversationResync;
      expect(inserted.baseline.version, removed.to + 1);
      expect(inserted.baseline.items.map((item) => item.id), ['B', 'Z']);
    }
  });

  test('超过 100 条连续更新只淘汰预览而不生成 Remove，被淘汰身份更新显式 Resync', () async {
    final transport = await demo([
      conversationFixture(id: 'first', ordinal: 0),
    ]);
    final p = await probe(transport);
    await p.baseline();
    for (var i = 1; i <= 110; i++) {
      transport.seedConversationItems('thread-main', [
        conversationFixture(id: 'item-$i', ordinal: i),
      ]);
      final patch = await p.update() as ConversationPatch;
      expect(patch.changes.single, isA<ConversationAdd>());
    }
    transport.seedConversationItems('thread-main', [
      conversationFixture(id: 'first', ordinal: 0, revision: 2),
    ]);
    expect(await p.update(), isA<ConversationResync>());
    transport.retractConversationItem('thread-main', 'first');
    expect(
      ((await p.update() as ConversationPatch).changes.single
              as ConversationRemove)
          .itemId,
      'first',
    );
  });

  test('预览正文 32KiB、工具参数结果各4KiB；正文原文与静态 descriptor 均保真', () async {
    final body = '猫\n' * 30000;
    final transport = await demo([
      conversationFixture(
        id: 'text',
        ordinal: 1,
        fields: {const ThreadTextFieldView(): body},
      ),
      conversationFixture(
        id: 'tool',
        ordinal: 2,
        descriptor: const ConversationToolDescriptor(
          invocation: ConversationToolInvocation(
            toolCallId: 'call',
            name: 'exec',
          ),
          state: ConversationToolRunning(),
        ),
        fields: {
          const ThreadToolArgumentsFieldView(): 'x' * 9000,
          const ThreadToolResultFieldView(): 'y' * 9000,
          const ThreadToolOutputArtifactsFieldView(): body,
        },
      ),
    ]);
    final p = await probe(transport);
    final baseline = await p.baseline();
    final text = baseline.items.first;
    final tool = baseline.items.last;
    expect(text.fields.single.previewBytes, lessThanOrEqualTo(32 * 1024));
    expect(text.fields.single.totalBytes, utf8.encode(body).length);
    expect(text.fields.single.text.endsWith('\n'), isTrue);
    expect(
      tool.fieldFor(const ThreadToolArgumentsFieldView())!.previewBytes,
      4096,
    );
    expect(
      tool.fieldFor(const ThreadToolResultFieldView())!.previewBytes,
      4096,
    );
    expect(
      tool.fields.fold(0, (n, f) => n + f.previewBytes),
      lessThanOrEqualTo(32 * 1024),
    );
    expect(
      (tool.descriptor as ConversationToolDescriptor).invocation.toolCallId,
      'call',
    );
    final chunks = <String>[];
    String? token;
    do {
      final chunk = await p.feed.readDetail(
        itemId: 'text',
        query: ConversationDetailQuery(
          field: const ThreadTextFieldView(),
          revision: 1,
          continuation: token,
        ),
      );
      chunks.add(chunk.text);
      token = chunk.continuation;
    } while (token != null);
    expect(chunks.first.length, isNot(0));
    expect(utf8.encode(chunks.first).length, 65536);
    expect(chunks.join(), body);
  });

  test('问答 secret/选项 None 与0/答案 redacted count 保真；短空字段不丢身份', () async {
    final descriptor = ConversationToolDescriptor(
      invocation: ConversationToolInvocation(
        toolCallId: 'call',
        name: 'request_user_input',
      ),
      state: ConversationToolSucceeded(
        completedAt: _constantDate,
        output: ConversationToolOutputDescriptor(attachments: []),
      ),
      userInput: ConversationUserInputDescriptor(
        interactionId: 'input',
        questions: [
          ConversationQuestionDescriptor(
            id: 'secret',
            isOther: false,
            isSecret: true,
          ),
          ConversationQuestionDescriptor(
            id: 'empty',
            isOther: true,
            isSecret: false,
            optionCount: 0,
          ),
        ],
        state: ConversationUserInputResolved(
          answers: [
            ConversationAnswerDescriptor(
              questionId: 'secret',
              answerCount: 1,
              redacted: true,
            ),
          ],
        ),
      ),
    );
    const header = ThreadToolUserInputFieldView(
      questionIndex: 0,
      part: ThreadUserInputHeaderFieldPartView(),
    );
    const answer = ThreadToolUserInputFieldView(
      questionIndex: 0,
      part: ThreadUserInputAnswerFieldPartView(0),
    );
    final transport = await demo([
      conversationFixture(
        descriptor: descriptor,
        fields: {header: '', answer: '[REDACTED]'},
      ),
    ]);
    final p = await probe(transport);
    final item = (await p.baseline()).items.single;
    final tool = item.descriptor as ConversationToolDescriptor;
    expect(tool.userInput!.questions.first.optionCount, isNull);
    expect(tool.userInput!.questions.last.optionCount, 0);
    expect(tool.userInput!.questions.first.isSecret, isTrue);
    expect(
      (tool.userInput!.state as ConversationUserInputResolved)
          .answers
          .single
          .redacted,
      isTrue,
    );
    expect(item.fields, hasLength(2));
    expect(item.fieldFor(header)!.text, '');
    expect(item.fieldFor(answer)!.text, '[REDACTED]');
    expect(item.omittedBytes, 0);
  });

  test('分块字段额度耗尽保留身份与详情；只有事实删除才发 Remove', () async {
    final transport = await demo([
      conversationFixture(
        descriptor: const ConversationThinkingDescriptor(
          lifecycle: StreamingThreadContentView(),
        ),
        fields: {
          const ThreadThinkingSummaryFieldView(0): 'a' * 40000,
          const ThreadThinkingContentFieldView(0): '正文',
        },
      ),
    ]);
    final p = await probe(transport);
    final item = (await p.baseline()).items.single;
    expect(item.fields, hasLength(2));
    expect(item.fields.last.text, '');
    expect(item.fields.last.totalBytes, 6);
    final full = await p.feed.readDetail(
      itemId: 'item',
      query: const ConversationDetailQuery(
        field: ThreadThinkingContentFieldView(0),
        revision: 1,
      ),
    );
    expect(full.text, '正文');
    transport.seedConversationItems('thread-main', [
      conversationFixture(
        revision: 2,
        descriptor: const ConversationThinkingDescriptor(
          lifecycle: StreamingThreadContentView(),
        ),
        fields: {const ThreadThinkingSummaryFieldView(0): 'a' * 40000},
      ),
    ]);
    final change =
        (await p.update() as ConversationPatch).changes.single
            as ConversationUpdateItem;
    expect(change.fields.single.field, const ThreadThinkingContentFieldView(0));
    expect(change.fields.single.change, isA<RemoveThreadFieldChangeView>());
  });

  test('预算重新分配使预览回退则Resync；更高修订的原文缩短则合法Replace', () async {
    final transport = await demo([
      conversationFixture(
        fields: {
          const ThreadThinkingSummaryFieldView(0): 'a',
          const ThreadThinkingContentFieldView(0): 'b' * 20000,
        },
      ),
    ]);
    final p = await probe(transport);
    await p.baseline();
    transport.seedConversationItems('thread-main', [
      conversationFixture(
        revision: 2,
        fields: {
          const ThreadThinkingSummaryFieldView(0): 'a' * 32000,
          const ThreadThinkingContentFieldView(0): 'b' * 20000,
        },
      ),
    ]);
    expect(await p.update(), isA<ConversationResync>());
    transport.seedConversationItems('thread-main', [
      conversationFixture(
        revision: 3,
        fields: {
          const ThreadThinkingSummaryFieldView(0): 'a',
          const ThreadThinkingContentFieldView(0): 'b',
        },
      ),
    ]);
    final patch = await p.update() as ConversationPatch;
    final update = patch.changes.single as ConversationUpdateItem;
    expect(
      update.fields.any((f) => f.change is ReplaceThreadFieldChangeView),
      isTrue,
    );
  });

  test('结构挤占正文但不裁静态原文；空字段声明与Raw.notice超限均明确Overloaded', () async {
    for (final item in [
      conversationFixture(
        descriptor: const ConversationThinkingDescriptor(
          lifecycle: StreamingThreadContentView(),
        ),
        fields: {
          for (var i = 0; i < 8000; i++) ThreadThinkingSummaryFieldView(i): '',
        },
      ),
      conversationFixture(
        descriptor: ConversationRawDescriptor(
          origin: ThreadRawItemOrigin.stored,
          payloads: const [],
          notice: 'n' * 270000,
          recordedAt: DateTime.now(),
        ),
        fields: const {},
      ),
    ]) {
      final transport = await demo([item]);
      final feed = await transport.openConversationFeed('thread-main');
      await expectLater(feed.page(), throwsA(overload));
      await feed.close();
    }
    final notice = 'n' * (245 * 1024);
    final transport = await demo([
      conversationFixture(
        descriptor: ConversationRawDescriptor(
          origin: ThreadRawItemOrigin.runtimeControl,
          payloads: const [
            ConversationRawPayloadDescriptor(format: 'json', version: 1),
          ],
          notice: notice,
          recordedAt: DateTime.now(),
        ),
        fields: {const ThreadRawPayloadFieldView(0): 'x' * 50000},
      ),
    ]);
    final p = await probe(transport);
    final item = (await p.baseline()).items.single;
    expect((item.descriptor as ConversationRawDescriptor).notice, notice);
    expect(item.fields.single.previewBytes, lessThan(32 * 1024));
    expect(item.fields.single.totalBytes, 50000);
    expect(
      (await p.feed.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          field: ThreadRawPayloadFieldView(0),
          revision: 1,
        ),
      )).text,
      'x' * 50000,
    );
  });

  test('页2MiB与连续性8MiB预算均生效，提前截页不会伪造EOF或跳过同ordinal身份', () async {
    ConversationItem large(int i) => conversationFixture(
      id: 'item-${i.toString().padLeft(3, '0')}',
      ordinal: i ~/ 2,
      descriptor: ConversationRawDescriptor(
        origin: ThreadRawItemOrigin.stored,
        payloads: const [],
        notice: 'n' * 200000,
        recordedAt: DateTime.now(),
      ),
      fields: const {},
    );
    final transport = await demo([for (var i = 0; i < 45; i++) large(i)]);
    final p = await probe(transport);
    final first = await p.baseline();
    expect(first.items.length, lessThan(32));
    expect(first.hasOlder, isTrue);
    final seen = first.items.map((i) => i.id).toSet();
    var token = first.before;
    var older = first.hasOlder;
    while (older) {
      final page = await p.feed.page(before: token, limit: 100);
      expect(page.items, isNotEmpty);
      for (final item in page.items) {
        expect(seen.add(item.id), isTrue);
      }
      token = page.before;
      older = page.hasOlder;
    }
    expect(seen, hasLength(45));
    for (var i = 45; i < 95; i++) {
      transport.seedConversationItems('thread-main', [large(i)]);
      expect(
        (await p.update() as ConversationPatch).changes.single,
        isA<ConversationAdd>(),
      );
    }
    transport.seedConversationItems('thread-main', [
      conversationFixture(
        id: first.items.first.id,
        ordinal: first.items.first.header.ordinal,
        revision: 2,
      ),
    ]);
    expect(await p.update(), isA<ConversationResync>());
  });

  test('详情token绑定Thread/item/field/revision与UTF8边界，参数化字段完整重组', () async {
    const field = ThreadToolUserInputFieldView(
      questionIndex: 2,
      part: ThreadUserInputOptionDescriptionFieldPartView(3),
    );
    const otherField = ThreadToolUserInputFieldView(
      questionIndex: 2,
      part: ThreadUserInputOptionDescriptionFieldPartView(2),
    );
    final body = '中文🐱\n' * 100;
    ConversationItem detailed({
      String id = 'item',
      String threadId = 'thread-main',
      int ordinal = 1,
      int revision = 1,
    }) => conversationFixture(
      id: id,
      threadId: threadId,
      ordinal: ordinal,
      revision: revision,
      descriptor: const ConversationToolDescriptor(
        invocation: ConversationToolInvocation(
          toolCallId: 'input',
          name: 'request_user_input',
        ),
        state: ConversationToolRunning(),
        userInput: ConversationUserInputDescriptor(
          interactionId: 'input',
          questions: [
            ConversationQuestionDescriptor(
              id: 'q0',
              isOther: false,
              isSecret: false,
              optionCount: 0,
            ),
            ConversationQuestionDescriptor(
              id: 'q1',
              isOther: false,
              isSecret: false,
              optionCount: 0,
            ),
            ConversationQuestionDescriptor(
              id: 'q2',
              isOther: false,
              isSecret: false,
              optionCount: 4,
            ),
          ],
          state: ConversationUserInputPending(),
        ),
      ),
      fields: {field: body, otherField: body},
    );
    final transport = await demo([
      detailed(),
      detailed(id: 'other', ordinal: 2),
    ]);
    transport.seedConversationItems('thread-alt', [
      detailed(threadId: 'thread-alt'),
    ]);
    final p = await probe(transport);
    await p.baseline();
    final first = await p.feed.readDetail(
      itemId: 'item',
      query: const ConversationDetailQuery(
        field: field,
        revision: 1,
        maxBytes: 7,
      ),
    );
    expect(utf8.encode(first.text).length, lessThanOrEqualTo(7));
    expect(first.continuation, isNotNull);
    final alt = await transport.openConversationFeed('thread-alt');
    addTearDown(alt.close);
    // 相同 itemId/revision/字段和正文在两个 Thread 中都真实存在。
    expect(
      (await alt.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          field: field,
          revision: 1,
          maxBytes: 7,
        ),
      )).text,
      first.text,
    );
    await expectLater(
      alt.readDetail(
        itemId: 'item',
        query: ConversationDetailQuery(
          field: field,
          revision: 1,
          continuation: first.continuation,
        ),
      ),
      throwsA(invalid),
    );
    await expectLater(
      p.feed.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          field: otherField,
          revision: 1,
          maxBytes: 7,
        ),
      ),
      completion(
        isA<ConversationDetailChunk>().having(
          (chunk) => chunk.text,
          'existing field text',
          first.text,
        ),
      ),
    );
    await expectLater(
      p.feed.readDetail(
        itemId: 'other',
        query: ConversationDetailQuery(
          field: field,
          revision: 1,
          continuation: first.continuation,
        ),
      ),
      throwsA(invalid),
    );
    await expectLater(
      p.feed.readDetail(
        itemId: 'item',
        query: ConversationDetailQuery(
          field: otherField,
          revision: 1,
          continuation: first.continuation,
        ),
      ),
      throwsA(invalid),
    );
    var text = first.text;
    var token = first.continuation;
    while (token != null) {
      final chunk = await p.feed.readDetail(
        itemId: 'item',
        query: ConversationDetailQuery(
          field: field,
          revision: 1,
          maxBytes: 7,
          continuation: token,
        ),
      );
      text += chunk.text;
      token = chunk.continuation;
    }
    expect(text, body);
    final encoded = first.continuation!;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(encoded)),
    ) as Map<String, dynamic>;
    // A corrupted cursor is rejected by the same production continuation decoder.
    payload['o'] = 1;
    final malformed = base64Url.encode(utf8.encode(jsonEncode(payload)));
    await expectLater(
      p.feed.readDetail(
        itemId: 'item',
        query: ConversationDetailQuery(
          field: field,
          revision: 1,
          continuation: malformed,
        ),
      ),
      throwsA(invalid),
    );
    transport.seedConversationItems('thread-main', [detailed(revision: 2)]);
    await expectLater(
      p.feed.readDetail(
        itemId: 'item',
        query: ConversationDetailQuery(
          field: field,
          revision: 1,
          continuation: first.continuation,
        ),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (f) => f.code,
          'code',
          StudioFailureCode.staleRevision,
        ),
      ),
    );
    await expectLater(
      p.feed.readDetail(
        itemId: 'item',
        query: ConversationDetailQuery(
          field: field,
          revision: 2,
          continuation: first.continuation,
        ),
      ),
      throwsA(invalid),
      reason: '当前revision真实存在，旧token不得跨revision重用',
    );
  });

  test('页/详情非法limit和块大小均分类InvalidArgument，失败终帧不占credit', () async {
    final transport = await demo([conversationFixture()]);
    final p = await probe(transport);
    await p.baseline();
    for (final limit in [0, 101]) {
      await expectLater(p.feed.page(limit: limit), throwsA(invalid));
    }
    for (final size in [0, 3, 262145]) {
      await expectLater(
        p.feed.readDetail(
          itemId: 'item',
          query: ConversationDetailQuery(
            field: const ThreadTextFieldView(),
            revision: 1,
            maxBytes: size,
          ),
        ),
        throwsA(invalid),
      );
    }
    final owned = <int>[];
    for (final revision in [2, 3]) {
      transport.seedConversationItems('thread-main', [
        conversationFixture(revision: revision),
      ]);
      final frame = await p.next();
      expect(frame.event, isA<ConversationUpdateEvent>());
      owned.add(frame.deliverySequence);
    }
    transport.seedConversationItems('thread-main', [
      conversationFixture(
        revision: 4,
        descriptor: ConversationRawDescriptor(
          origin: ThreadRawItemOrigin.stored,
          payloads: const [],
          notice: 'n' * 270000,
          recordedAt: DateTime.now(),
        ),
        fields: const {},
      ),
    ]);
    // credit 满时只记 dirty，不编码正文。释放一份后物化发现超限，
    // 失败终帧本身不再获取 credit，也不等待另一份 ACK。
    await p.feed.acknowledge(owned.first);
    final failure = await p.next();
    expect(failure.event, isA<ConversationFailureEvent>());
    expect(failure.deliverySequence, owned.last);
    expect((failure.event as ConversationFailureEvent).failure, overload);
    await expectLater(
      p.feed.page(),
      throwsA(
        isA<StudioFailure>().having(
          (f) => f.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    transport.seedConversationItems('thread-main', [
      conversationFixture(revision: 5),
    ]);
    final replacement = await probe(transport);
    expect(replacement.feed.subscriptionId, isNot(p.feed.subscriptionId));
    expect((await replacement.baseline()).items.single.revision, 5);
  });
  test('计划真实决定标记在正文预算耗尽时仍完整交付，反馈原文不被改写', () async {
    const answer = ThreadToolUserInputFieldView(
      questionIndex: 0,
      part: ThreadUserInputAnswerFieldPartView(0),
    );
    const question = ThreadToolUserInputFieldView(
      questionIndex: 0,
      part: ThreadUserInputQuestionFieldPartView(),
    );
    for (final decision in [
      agentSessionPlanApproveAnswer,
      agentSessionPlanReviseAnswer,
    ]) {
      final descriptor = ConversationToolDescriptor(
        invocation: const ConversationToolInvocation(
          toolCallId: 'plan',
          name: 'plan_submit',
        ),
        state: ConversationToolSucceeded(
          completedAt: _constantDate,
          output: const ConversationToolOutputDescriptor(attachments: []),
        ),
        userInput: const ConversationUserInputDescriptor(
          interactionId: 'plan-input',
          questions: [
            ConversationQuestionDescriptor(
              id: agentSessionPlanConfirmationQuestionId,
              isOther: false,
              isSecret: false,
              optionCount: 2,
            ),
          ],
          state: ConversationUserInputResolved(
            answers: [
              ConversationAnswerDescriptor(
                questionId: agentSessionPlanConfirmationQuestionId,
                answerCount: 1,
                redacted: false,
              ),
            ],
          ),
        ),
      );
      final transport = await demo([
        conversationFixture(
          descriptor: descriptor,
          fields: {question: '正文' * 40000, answer: decision},
        ),
      ]);
      final p = await probe(transport);
      final item = (await p.baseline()).items.single;
      expect(item.fieldFor(answer)!.text, decision);
      expect(
        item.fields.fold(0, (n, f) => n + f.previewBytes),
        lessThanOrEqualTo(32 * 1024),
      );
      expect(
        item.planReceipt!.decision,
        decision == agentSessionPlanApproveAnswer
            ? PlanConfirmationDecisionView.approved
            : PlanConfirmationDecisionView.revisionRequested,
      );
      final full = await p.feed.readDetail(
        itemId: 'item',
        query: const ConversationDetailQuery(
          field: question,
          revision: 1,
          maxBytes: 256 * 1024,
        ),
      );
      expect(full.text, '正文' * 40000);
    }
  });

  test('产物数组仅截取字段预览，完整JSON原文经详情逐字节保留', () async {
    final body = jsonEncode([
      for (var i = 0; i < 20000; i++) {'index': i, 'value': '猫'},
    ]);
    const field = ThreadToolOutputArtifactsFieldView();
    final transport = await demo([
      conversationFixture(
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'artifacts',
            name: 'exec',
          ),
          state: ConversationToolSucceeded(
            completedAt: _constantDate,
            output: const ConversationToolOutputDescriptor(attachments: []),
          ),
        ),
        fields: {field: body},
      ),
    ]);
    final p = await probe(transport);
    final item = (await p.baseline()).items.single;
    expect(item.fieldFor(field)!.previewBytes, lessThanOrEqualTo(32 * 1024));
    expect(item.fieldFor(field)!.totalBytes, utf8.encode(body).length);
    expect(body.startsWith(item.fieldFor(field)!.text), isTrue);
    final full = StringBuffer();
    String? continuation;
    do {
      final chunk = await p.feed.readDetail(
        itemId: item.id,
        query: ConversationDetailQuery(
          field: field,
          revision: item.revision,
          continuation: continuation,
        ),
      );
      expect(utf8.encode(chunk.text).length, lessThanOrEqualTo(64 * 1024));
      full.write(chunk.text);
      continuation = chunk.continuation;
    } while (continuation != null);
    expect(full.toString(), body);
  });

  test('Turn失败分类与rollover错误均计入静态结构，首帧和页明确Overloaded', () async {
    final part = 'x' * (100 * 1024);
    for (final state in <StudioTurnState>[
      FailedStudioTurnState(
        startedAt: 1,
        completedAt: 2,
        failure: StudioTurnFailureView(
          category: part,
          providerKind: part,
          code: part,
          httpStatus: 500,
          message: 'boom',
          retryable: true,
          retryAfterMs: 1000,
        ),
      ),
      BudgetLimitedStudioTurnState(
        startedAt: 1,
        completedAt: 2,
        limit: const StudioTurnBudgetLimit(
          kind: StudioTurnBudgetLimitKind.modelStep,
          usage: StudioTurnBudgetUsage(
            modelSteps: 1,
            toolCalls: 0,
            waitCalls: 0,
            elapsedMs: 1,
          ),
        ),
        rollover: RolloverFailed(error: 'y' * (300 * 1024)),
      ),
    ]) {
      final transport = await demo([
        conversationFixture(
          descriptor: ConversationTurnDescriptor(
            ThreadTurnItemStateView(state),
          ),
          fields: const {},
        ),
      ]);
      final query = await transport.openConversationFeed('thread-main');
      await expectLater(query.page(), throwsA(overload));
      await query.close();
      final p = await probe(transport);
      final stateFrame = await p.next();
      expect(stateFrame.event, isA<ConversationStateEvent>());
      final failed = await p.next();
      expect(failed.event, isA<ConversationFailureEvent>());
      expect((failed.event as ConversationFailureEvent).failure, overload);
      expect(failed.deliverySequence, stateFrame.deliverySequence);
    }
  });

  test('未匹配问题的答案descriptor保留身份与计数，并计入不可缩结构', () async {
    ConversationItem ask(String orphanId) => conversationFixture(
      descriptor: ConversationToolDescriptor(
        invocation: const ConversationToolInvocation(
          toolCallId: 'ask',
          name: 'ask',
        ),
        state: const ConversationToolRunning(),
        userInput: ConversationUserInputDescriptor(
          interactionId: 'ask-input',
          questions: const [
            ConversationQuestionDescriptor(
              id: 'q1',
              isOther: false,
              isSecret: false,
              optionCount: 0,
            ),
          ],
          state: ConversationUserInputResolved(
            answers: [
              const ConversationAnswerDescriptor(
                questionId: 'q1',
                answerCount: 1,
                redacted: false,
              ),
              ConversationAnswerDescriptor(
                questionId: orphanId,
                answerCount: 3,
                redacted: true,
              ),
            ],
          ),
        ),
      ),
      fields: {
        const ThreadToolUserInputFieldView(
          questionIndex: 0,
          part: ThreadUserInputAnswerFieldPartView(0),
        ): 'yes',
      },
    );
    final transport = await demo([ask('orphan-q')]);
    final p = await probe(transport);
    final item = (await p.baseline()).items.single;
    final input = (item.descriptor as ConversationToolDescriptor).userInput!;
    final answers = (input.state as ConversationUserInputResolved).answers;
    expect(answers.last.questionId, 'orphan-q');
    expect(answers.last.answerCount, 3);
    expect(answers.last.redacted, isTrue);
    expect(item.fields, hasLength(1), reason: '未知答案不制造可寻址正文域');
    final oversized = await demo([ask('q' * (300 * 1024))]);
    final query = await oversized.openConversationFeed('thread-main');
    await expectLater(query.page(), throwsA(overload));
    await query.close();
  });

  test('取消Dart监听同步撤销idle或满credit feed，不关闭其他消费者或Demo事实', () async {
    for (final idle in [false, true]) {
      final transport = await demo([conversationFixture()]);
      final feed = await transport.openConversationFeed('thread-main');
      final ready = Completer<void>();
      var count = 0;
      final subscription = feed.events.listen((_) {
        if (++count == 2) ready.complete();
      });
      await ready.future;
      if (idle) await feed.acknowledge(2);
      await subscription.cancel();
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
      final next = await probe(transport);
      expect((await next.baseline()).items.single.id, 'item');
    }
  });
}

// DateTime cannot be const; tool success above uses this shared deterministic value.
final _constantDate = DateTime.fromMillisecondsSinceEpoch(1700000000000);

final class _CloseFaultFeed extends RecordingConversationFeed {
  _CloseFaultFeed({required super.inner});
  bool failClose = true;

  @override
  Future<void> close() async {
    if (!failClose) return super.close();
    closeCalls++;
    await inner.close();
    throw StateError('late Demo factory close failed');
  }
}
