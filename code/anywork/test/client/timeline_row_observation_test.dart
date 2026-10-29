import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_detail_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';

import 'dart:async';
import 'dart:typed_data';

import 'support/recording_demo_transport.dart';
import 'support/pump_client_future.dart';

import 'support/conversation_fixtures.dart';

// Canonical item → 唯一 typed Message 的适配契约。
//
// 旧实现观察的是窗口行投影（`TimelineRow`、窗口 epoch、锚点与双向分页回执）；这些能力已
// 按 design/26 删除，算法覆盖由展示 lease/owner 的测试承担
// （test/client/timeline_display_lease_test.dart、timeline_session_owner_test.dart）。
// 这里保留仍然成立且只有适配层能证明的部分：每条 canonical item 恰好一条 Message、身份与
// 作者来自条目自身、typed 载荷的保存/终态/省略账目与逐字段详情引用，以及原位更新的身份
// 稳定性；另外验证公开展示状态确实只携带元数据。
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/plan_confirmation_ownership.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_entry.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final timestamp = DateTime.utc(2026, 1, 2, 3, 4, 5);

  ConversationItem textItem(
    String id, {
    int ordinal = 1,
    int revision = 1,
    String body = '正文',
    ThreadTextChannel channel = ThreadTextChannel.finalAnswer,
    bool saved = false,
    bool terminal = false,
    String? turnId = 'turn',
    DateTime? updatedAt,
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: turnId ?? '',
    ordinal: ordinal,
    revision: revision,
    createdAt: timestamp,
    updatedAt: updatedAt ?? timestamp,
    saved: saved,
    lifecycle: terminal
        ? ConversationLifecycle.terminal
        : ConversationLifecycle.streaming,
    descriptor: ConversationTextDescriptor(
      channel: channel,
      attachments: const [],
      lifecycle: terminal
          ? CompletedThreadContentView(timestamp)
          : const StreamingThreadContentView(),
    ),
    fields: {const ThreadTextFieldView(): body},
  );

  ConversationItem toolItem(
    String id, {
    int ordinal = 2,
    int revision = 3,
    String arguments = '{"command":"cargo test"}',
    String result = 'ok',
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal,
    revision: revision,
    createdAt: timestamp,
    updatedAt: timestamp,
    saved: true,
    lifecycle: ConversationLifecycle.terminal,
    descriptor: ConversationToolDescriptor(
      invocation: ConversationToolInvocation(
        toolCallId: 'call-1',
        callId: 'call-1',
        name: 'exec_command',
      ),
      state: ConversationToolSucceeded(
        completedAt: timestamp,
        output: ConversationToolOutputDescriptor(attachments: const []),
      ),
    ),
    fields: {
      const ThreadToolArgumentsFieldView(): arguments,
      const ThreadToolResultFieldView(): result,
    },
  );

  group('canonical item → Flyer 原生 Message 与唯一 entry', () {
    test('多附件产生原生消息但只有一个业务 entry，空 Turn 身份合法', () async {
      const attachments = [
        ThreadAttachmentView(
          id: 'image-a',
          modality: AttachmentModalityView.image,
          mediaType: 'image/png',
          byteSize: 8,
        ),
        ThreadAttachmentView(
          id: 'image-b',
          modality: AttachmentModalityView.image,
          mediaType: 'image/png',
          byteSize: 9,
        ),
        ThreadAttachmentView(
          id: 'file',
          modality: AttachmentModalityView.file,
          mediaType: 'text/plain',
          byteSize: 10,
        ),
      ];
      final chat = InMemoryChatController();
      final resources = TimelineImageResources(threadId: 'thread');
      final messages = TimelineMessageController(
        chat,
        generation: 1,
        imageResources: resources,
      );
      addTearDown(() async {
        resources.retire();
        messages.dispose();
        resources.release();
        chat.dispose();
      });
      messages.add(
        conversationFixture(
          id: 'media',
          threadId: 'thread',
          turnId: '',
          descriptor: ConversationTextDescriptor(
            channel: ThreadTextChannel.user,
            attachments: attachments,
            lifecycle: CompletedThreadContentView(timestamp),
          ),
          fields: {const ThreadTextFieldView(): '正文'},
        ),
      );
      final entry = messages.ownerOf('media')!;
      expect(messages.length, 1);
      expect(chat.messages, hasLength(4));
      expect(chat.messages.whereType<ImageMessage>(), hasLength(2));
      expect(chat.messages.whereType<FileMessage>(), hasLength(1));
      expect(
        chat.messages.where((message) => message.id == entry.id),
        hasLength(1),
      );
      expect(chat.messages.map(timelineEntryOf).toSet(), {entry});
      expect(entry.first.header.turnId, isEmpty);
      expect(identical(messages.item('media'), entry.first), isTrue);

      // 真实共享资源由 raw item 引用维护，不由 derived ImageMessage 计数。
      ConversationItem sharedItem(String id) => conversationFixture(
        id: id,
        threadId: 'thread',
        descriptor: ConversationTextDescriptor(
          channel: ThreadTextChannel.user,
          attachments: [attachments.first],
          lifecycle: CompletedThreadContentView(timestamp),
        ),
      );
      messages.add(sharedItem('peer'));
      expect(messages.length, 2);
      expect(chat.messages, hasLength(6));
      expect(
        chat.messages.whereType<ImageMessage>().map((message) => message.id),
        containsAll(['media:attachment:image-a', 'peer:attachment:image-a']),
      );
      final transport = _ImageReadTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'shared-image-read',
      );
      addTearDown(() {
        resources.retire();
        return client.close();
      });
      Future<Uint8List> read() =>
          client.readAttachmentBytes('thread', 'image-a');
      final shared = resources.borrow('image-a');
      expect(resources.borrow('image-a'), same(shared));
      final first = shared.load(read);
      final peer = shared.load(read);
      expect(identical(first, peer), isTrue);
      final failed = isA<StudioFailure>().having(
        (failure) => failure.correlationId,
        'correlationId',
        'shared-image-failure',
      );
      await Future.wait([
        expectLater(first, throwsA(failed)),
        expectLater(peer, throwsA(failed)),
      ]);
      expect(transport.reads, [('thread', 'image-a')]);

      Future<Uint8List>? leftRetry;
      Future<Uint8List>? rightRetry;
      void leftChanged() => leftRetry = shared.load(read);
      void rightChanged() => rightRetry = shared.load(read);
      shared.addListener(leftChanged);
      shared.addListener(rightChanged);
      transport.fail = false;
      shared.retry(read); // 一次 retry 同时通知两个真实 resource consumer。
      expect(leftRetry, isNotNull);
      expect(identical(leftRetry, rightRetry), isTrue);
      expect(await leftRetry!, orderedEquals(_ImageReadTransport.bytes));
      expect(await rightRetry!, orderedEquals(_ImageReadTransport.bytes));
      expect(transport.reads, hasLength(2), reason: '两个consumer共享一次额外授权读取');
      expect(
        identical(shared.load(read), leftRetry),
        isTrue,
        reason: '再次借用成功缩略图/原图bytes不触发新读取',
      );

      messages.remove('media');
      expect(resources.borrow('image-a'), same(shared));
      expect(identical(shared.load(read), leftRetry), isTrue);
      expect(transport.reads, hasLength(2));
      shared.removeListener(leftChanged);
      shared.removeListener(rightChanged);
      messages.remove('peer');
      expect(() => resources.borrow('image-a'), throwsStateError);
      expect(shared.owns(leftRetry!), isFalse);
      messages.add(sharedItem('later'));
      final replacement = resources.borrow('image-a');
      expect(replacement, isNot(same(shared)));
      expect(
        await replacement.load(read),
        orderedEquals(_ImageReadTransport.bytes),
      );
      expect(transport.reads, hasLength(3), reason: '最后raw引用释放后重新加入同附件必须新读');
    });
    test('每条条目有唯一主 Message，身份来自条目而不是索引', () {
      final chat = InMemoryChatController();
      final resources = TimelineImageResources(threadId: 'thread');
      final messages = TimelineMessageController(
        chat,
        generation: 1,
        imageResources: resources,
      );
      addTearDown(() async {
        resources.retire();
        messages.dispose();
        resources.release();
        chat.dispose();
      });
      messages.add(textItem('item-a', ordinal: 1));
      messages.add(textItem('item-b', ordinal: 2, terminal: true));
      expect(chat.messages.map((message) => message.id), ['item-a', 'item-b']);
      expect(chat.messages.first, isA<TextStreamMessage>());
      expect(chat.messages.last, isA<TextMessage>());
      expect(chat.messages.first.createdAt, timestamp);
      final entry = timelineEntryOf(chat.messages.first)!;
      messages.replace('item-a', textItem('item-a', ordinal: 1));
      expect(chat.messages, hasLength(2));
      expect(timelineEntryOf(chat.messages.first), same(entry));
      expect(identical(entry.first, messages.item('item-a')), isTrue);
      expect(entry.first.revision, 1);
    });

    test('作者身份只区分读者与助手，父代理输入属于读者', () {
      expect(
        timelineAuthor(textItem('u', channel: ThreadTextChannel.user)),
        'user',
      );
      expect(
        timelineAuthor(textItem('p', channel: ThreadTextChannel.parentAgent)),
        'user',
      );
      expect(
        timelineAuthor(textItem('c', channel: ThreadTextChannel.commentary)),
        'assistant',
      );
      expect(timelineAuthor(toolItem('t')), 'assistant');
    });

    test('保存与终态互相独立，省略账目来自条目本身', () {
      final chat = InMemoryChatController();
      final resources = TimelineImageResources(threadId: 'thread');
      final messages = TimelineMessageController(
        chat,
        generation: 1,
        imageResources: resources,
      );
      addTearDown(() async {
        resources.retire();
        messages.dispose();
        resources.release();
        chat.dispose();
      });
      messages.add(textItem('saved-but-streaming', saved: true));
      final payload = timelineEntryOf(chat.messages.single)!.first;
      expect(payload.saved, isTrue);
      expect(payload.terminal, isFalse);
      expect(payload.omittedBytes, 0);
      messages.add(
        textItem('terminal', ordinal: 2, terminal: true, saved: false),
      );
      final terminal = timelineEntryOf(chat.messages.last)!.first;
      expect(terminal.terminal, isTrue);
      expect(terminal.saved, isFalse);
    });

    test('逐字段详情引用按值语义查找，不依赖对象实例', () {
      final chat = InMemoryChatController();
      final resources = TimelineImageResources(threadId: 'thread');
      final messages = TimelineMessageController(
        chat,
        generation: 1,
        imageResources: resources,
      );
      addTearDown(() async {
        resources.retire();
        messages.dispose();
        resources.release();
        chat.dispose();
      });
      messages.add(
        conversationCopyFixture(
          toolItem('detail', revision: 4),
          fields: {const ThreadToolArgumentsFieldView(): 'a' * 32},
          totalBytes: {const ThreadToolArgumentsFieldView(): 40},
        ),
      );
      final payload = timelineEntryOf(chat.messages.single)!.first;
      final ref = payload.detailFor(const ThreadToolArgumentsFieldView());
      expect(ref, isNotNull);
      expect(ref!.revision, 4);
      expect(ref.truncated, isTrue);
      expect(payload.omittedBytes, 8);
      expect(payload.detailFor(const ThreadToolResultFieldView()), isNull);
    });

    test('预览被省略时仍保留按需读取入口，不把省略当成原文不存在', () {
      final chat = InMemoryChatController();
      final resources = TimelineImageResources(threadId: 'thread');
      final messages = TimelineMessageController(
        chat,
        generation: 1,
        imageResources: resources,
      );
      addTearDown(() async {
        resources.retire();
        messages.dispose();
        resources.release();
        chat.dispose();
      });
      messages.add(
        conversationCopyFixture(
          textItem('truncated', body: '预览'),
          totalBytes: {const ThreadTextFieldView(): 106},
        ),
      );
      final message = chat.messages.single;
      expect(message, isA<TextStreamMessage>());
      expect(message.metadata, isNotEmpty);
      final payload = timelineEntryOf(message)!.first;
      expect(payload.omittedBytes, 100);
      expect(payload.fieldFor(const ThreadTextFieldView())!.previewBytes, 6);
      expect(payload.detailFor(const ThreadTextFieldView())!.truncated, isTrue);
      expect(timelineText(payload), '预览');
    });

    test('工具条目的 typed 事实来自条目自身，不解析摘要字符串', () {
      final chat = InMemoryChatController();
      final resources = TimelineImageResources(threadId: 'thread');
      final messages = TimelineMessageController(
        chat,
        generation: 1,
        imageResources: resources,
      );
      addTearDown(() async {
        resources.retire();
        messages.dispose();
        resources.release();
        chat.dispose();
      });
      messages.add(toolItem('tool-1'));
      final payload = timelineEntryOf(chat.messages.single)!.first;
      expect(payload.descriptor, isA<ConversationToolDescriptor>());
      final tool = payload.descriptor as ConversationToolDescriptor;
      expect(tool.invocation.name, 'exec_command');
      expect(payload.fieldFor(const ThreadToolResultFieldView())!.text, 'ok');
      expect(
        payload.fieldFor(const ThreadToolArgumentsFieldView())!.text,
        contains('cargo test'),
      );
    });
  });

  group('原位更新保持身份', () {
    test('同身份、更高 revision 的字段提交原地生效并前进保存/终态', () {
      final chat = InMemoryChatController();
      final resources = TimelineImageResources(threadId: 'thread');
      final messages = TimelineMessageController(
        chat,
        generation: 1,
        imageResources: resources,
      );
      addTearDown(() async {
        resources.retire();
        messages.dispose();
        resources.release();
        chat.dispose();
      });
      final content = conversationContentFixture();
      final current = textItem('live', body: '前半');
      messages.add(current);
      final entry = timelineEntryOf(chat.messages.single)!;
      final next = content.reduceItem(
        current,
        const ConversationUpdateItem(
          itemId: 'live',
          expectedRevision: 1,
          revision: 2,
          saved: true,
          lifecycle: ConversationLifecycle.terminal,
          fields: [
            ConversationFieldUpdate(
              field: ThreadTextFieldView(),
              change: AppendThreadFieldChangeView(' 后半'),
              totalBytes: 13,
              previewBytes: 13,
            ),
          ],
        ),
      );
      messages.replace('live', next);
      expect(chat.messages.single.id, current.id, reason: '身份必须保持，不移除后重插');
      expect(timelineEntryOf(chat.messages.single), same(entry));
      expect(chat.messages.single, isA<TextMessage>());
      expect(entry.first.revision, 2);
      expect(entry.first.saved, isTrue);
      expect(entry.first.terminal, isTrue);
      expect(timelineText(entry.first), '前半 后半');
    });

    test('revision 不连续的更新被拒绝，交给显式重同步', () {
      final content = conversationContentFixture();
      expect(
        () => content.reduceItem(
          textItem('live', revision: 2),
          const ConversationUpdateItem(
            itemId: 'live',
            expectedRevision: 1,
            revision: 3,
            saved: false,
            lifecycle: ConversationLifecycle.streaming,
            fields: [
              ConversationFieldUpdate(
                field: ThreadTextFieldView(),
                change: AppendThreadFieldChangeView('x'),
                totalBytes: 1,
                previewBytes: 1,
              ),
            ],
          ),
        ),
        throwsA(isA<ConversationContinuityError>()),
      );
    });

    test('逐字段字节账目与实际预览矛盾时拒绝该帧', () {
      final content = conversationContentFixture();
      final current = conversationCopyFixture(
        textItem('accounting', body: 'ab'),
        totalBytes: {const ThreadTextFieldView(): 6},
      );
      expect(current.omittedBytes, 4);
      expect(
        () => content.reduceItem(
          current,
          const ConversationUpdateItem(
            itemId: 'accounting',
            expectedRevision: 1,
            revision: 1,
            saved: false,
            lifecycle: ConversationLifecycle.streaming,
            fields: [
              ConversationFieldUpdate(
                field: ThreadTextFieldView(),
                change: UnchangedThreadFieldChangeView(),
                totalBytes: 6,
                previewBytes: 3,
              ),
            ],
          ),
        ),
        throwsA(isA<ConversationContinuityError>()),
      );
      expect(current.omittedBytes, 4, reason: '拒绝不改写原事实；整体省略量由有效字段派生');
    });
  });

  // ---- 原门禁承接：QA 回执 / 计划回执 / 窄窗布局（真实 lease + stock controller） ----

  ConversationItem toolItemWithInput(
    ConversationInputFixture history, {
    String id = 'qa',
    int revision = 1,
    String toolName = 'ask_user',
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: 1,
    revision: revision,
    createdAt: timestamp,
    updatedAt: timestamp,
    saved: true,
    lifecycle: ConversationLifecycle.streaming,
    descriptor: ConversationToolDescriptor(
      invocation: ConversationToolInvocation(
        toolCallId: 'call',
        callId: 'call',
        name: toolName,
      ),
      userInput: (history).descriptor,
      state: ConversationToolRunning(),
    ),
    fields: {const ThreadToolArgumentsFieldView(): '{}', ...(history).fields},
  );

  UserQuestionView question({
    String id = 'q1',
    String header = 'Pick one',
    String text = 'Which option should the agent use?',
  }) => UserQuestionView(
    id: id,
    header: header,
    question: text,
    isOther: false,
    isSecret: false,
    options: const [
      UserQuestionOptionView(label: 'A', description: 'first option'),
    ],
  );

  TimelineDisplayLease leaseWith(WidgetTester tester, ConversationItem item) {
    final lease = TimelineDisplayLease(
      threadId: 'thread',
      generation: 1,
      content: conversationContentFixture(threadId: 'thread', tester: tester),
    );
    lease.adoptBaseline(
      ConversationBaseline(
        subscriptionId: 'test',
        version: 0,
        items: [item],
        before: null,
        hasOlder: false,
      ),
    );
    return lease;
  }

  Future<void> unmountTimeline(
    WidgetTester tester,
    TimelineDisplayLease lease,
  ) async {
    if (lease.isReleased) return;
    final close = find.byKey(StudioDriverKeys.timelineDetailClose);
    if (close.evaluate().isNotEmpty) {
      await tester.tap(close);
      await pumpClientUntil(
        tester,
        () => find
            .byKey(StudioDriverKeys.timelineDetailDialog)
            .evaluate()
            .isEmpty,
        'timeline detail actual close',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      lease.retire(),
      'row timeline stock operations done',
    );
    expect(lease.isReleased, isTrue, reason: '卸载后等待真实 stock operations done');
  }

  Future<void> pumpTimeline(
    WidgetTester tester,
    TimelineDisplayLease lease, {
    Size size = const Size(900, 700),
  }) async {
    final client = AnyworkClient(
      transport: RecordingDemoTransport(),
      clientId: 'row-media',
    );
    addTearDown(() async {
      final report = await pumpClientFuture(
        tester,
        client.close(),
        'row media client teardown close',
      );
      expect(report.complete, isTrue, reason: '图片读取客户端必须真实关闭');
    });
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => unmountTimeline(tester, lease));
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            final threadId = lease.threadId;
            Future<Uint8List> readAttachment(String id) =>
                client.readAttachmentBytes(threadId, id);
            void detail(String itemId, ThreadContentFieldView field) {
              if (lease.isRetired || !context.mounted) return;
              unawaited(
                openTimelineDetail(
                  context,
                  lease: lease,
                  itemId: itemId,
                  field: field,
                ).catchError((Object error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                }),
              );
            }

            return Scaffold(
              body: TimelineView(
                threadId: 'thread',
                view: TimelineSessionViewState(
                  threadId: 'thread',
                  generation: lease.generation,
                  mode: TimelineDisplayMode.live,
                  connection: TimelineConnectionPhase.ready,
                  connectionError: null,
                  olderCursor: null,
                  hasOlder: false,
                  isLoadingOlder: false,
                  olderError: null,
                  hasNewOutput: false,
                  isPreparingLive: false,
                ),
                onLoadOlder: () async {},
                onRetryOlder: () async {},
                onReturnLive: () async {},
                onEnterHistory: () {},
                onRetryConnection: () async {},
                controls: lease,
                onDetail: detail,
                onLink: (_) {},
                isSafeLink: (_) => false,
                imageBuilder: (_, message, index) => TimelineImageConnector(
                  message: message,
                  index: index,
                  item: timelineEntryOf(message)!.first,
                  resources: lease.imageResources,
                  readBytes: () => readAttachment(
                    (message.metadata!['attachment'] as ThreadAttachmentView)
                        .id,
                  ),
                  isActive: () => !lease.isRetired,
                  onDetail: detail,
                ),
                remoteImageBuilder: (_, _) => const SizedBox.shrink(),
                pendingPlanInteractionId: 'plan-1',
                groupMediaBuilder: (item) => TimelineGroupMediaConnector(
                  item: item,
                  resources: lease.imageResources,
                  readAttachment: readAttachment,
                  isActive: () => !lease.isRetired,
                  onDetail: detail,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('原门禁承接：普通问答回执', () {
    testWidgets('独立成行、默认折叠，原位更新后保留用户展开', (tester) async {
      final history = conversationInputFixture(
        interactionId: 'interaction-1',
        questions: [question()],
        state: ConversationUserInputResolved(
          answers: [
            ConversationAnswerDescriptor(
              questionId: 'q1',
              answerCount: (['A']).length,
              redacted: false,
            ),
          ],
        ),
        answers: {
          'q1': ['A'],
        },
      );
      final lease = leaseWith(tester, toolItemWithInput(history));
      await pumpTimeline(tester, lease);

      // 独立回执行（不并入其它 message），默认折叠：详情未构建。
      expect(
        find.byKey(StudioDriverKeys.timelineUserInput('qa')),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputDetails('qa')),
        findsNothing,
      );

      await tester.tap(find.byKey(StudioDriverKeys.timelineUserInput('qa')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputQuestion('qa', 0)),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputAnswer('qa', 0)),
        findsOneWidget,
      );

      // 同身份原位更新（工具参数替换）：不重插消息，也不收起用户已展开的回执。
      final applied = lease.applyPatch(
        const ConversationPatch(
          subscriptionId: 'test',
          from: 0,
          to: 1,
          priority: ConversationPriority.coalesced,
          changes: [
            ConversationUpdateItem(
              itemId: 'qa',
              expectedRevision: 1,
              revision: 2,

              saved: true,
              lifecycle: ConversationLifecycle.streaming,
              fields: [
                ConversationFieldUpdate(
                  field: ThreadToolArgumentsFieldView(),
                  change: ReplaceThreadFieldChangeView('{"command":"x"}'),
                  totalBytes: 15,
                  previewBytes: 15,
                ),
              ],
            ),
          ],
        ),
      );
      expect(applied, isTrue);
      await tester.pumpAndSettle();
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputQuestion('qa', 0)),
        findsOneWidget,
        reason: '原位更新不得收起用户主动展开的回执',
      );
      expect(lease.itemOf('qa')!.revision, 2);
    });
  });

  group('原门禁承接：计划回执', () {
    ConversationInputFixture planHistory(
      ConversationUserInputState state, {
      List<String> answers = const [],
    }) => conversationInputFixture(
      interactionId: 'plan-1',
      questions: [
        question(
          id: agentSessionPlanConfirmationQuestionId,
          header: 'Plan',
          text: '# Plan title\n\n- step one',
        ),
      ],
      state: state,
      answers: {agentSessionPlanConfirmationQuestionId: answers},
    );

    testWidgets('待确认时不出第二张历史卡', (tester) async {
      final lease = leaseWith(
        tester,
        toolItemWithInput(
          planHistory(const ConversationUserInputPending()),
          toolName: planSubmitToolName,
        ),
      );
      await pumpTimeline(tester, lease);
      expect(
        find.byKey(StudioDriverKeys.timelinePlanReceipt('qa')),
        findsNothing,
      );
      expect(
        find.byKey(StudioDriverKeys.timelineUserInput('qa')),
        findsNothing,
      );
    });

    testWidgets('回答后显示权威决定与原始反馈', (tester) async {
      final lease = leaseWith(
        tester,
        toolItemWithInput(
          planHistory(
            ConversationUserInputResolved(
              answers: [
                ConversationAnswerDescriptor(
                  questionId: agentSessionPlanConfirmationQuestionId,
                  answerCount: ([
                    agentSessionPlanReviseAnswer,
                    '请补充回滚步骤',
                  ]).length,
                  redacted: false,
                ),
              ],
            ),
            answers: [agentSessionPlanReviseAnswer, '请补充回滚步骤'],
          ),
          toolName: planSubmitToolName,
        ),
      );
      await pumpTimeline(tester, lease);
      final receipt = find.byKey(StudioDriverKeys.timelinePlanReceipt('qa'));
      expect(receipt, findsOneWidget);
      await tester.tap(receipt);
      await tester.pumpAndSettle();
      expect(find.text('请补充回滚步骤'), findsOneWidget);
    });
  });

  group('旧历史：普通问答复用保留问题 ID', () {
    /// 旧普通问答工具曾把问题 ID 写成保留的 `plan_confirmation`：历史原样只读，
    /// 归属只看工具条目自己的权威名称，不能按问题 ID 或标题改判成计划。
    ConversationInputFixture legacyHistory(
      ConversationUserInputState state, {
      List<String> answers = const [],
    }) => conversationInputFixture(
      interactionId: 'legacy-1',
      questions: [
        question(
          id: agentSessionPlanConfirmationQuestionId,
          header: 'Plan',
          text: '# Plan title\n\n- step one',
        ),
      ],
      state: state,
      answers: {agentSessionPlanConfirmationQuestionId: answers},
    );

    testWidgets('已回答的普通问答仍渲染普通只读回执', (tester) async {
      final lease = leaseWith(
        tester,
        toolItemWithInput(
          legacyHistory(
            ConversationUserInputResolved(
              answers: [
                ConversationAnswerDescriptor(
                  questionId: agentSessionPlanConfirmationQuestionId,
                  answerCount: ([agentSessionPlanApproveAnswer]).length,
                  redacted: false,
                ),
              ],
            ),
            answers: [agentSessionPlanApproveAnswer],
          ),
        ),
      );
      await pumpTimeline(tester, lease);
      expect(
        find.byKey(StudioDriverKeys.timelinePlanReceipt('qa')),
        findsNothing,
        reason: '普通工具历史不得冒充计划回执',
      );
      final receipt = find.byKey(StudioDriverKeys.timelineUserInput('qa'));
      expect(receipt, findsOneWidget, reason: '普通问答必须可见');
      await tester.tap(receipt);
      await tester.pumpAndSettle();
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputQuestion('qa', 0)),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputAnswer('qa', 0)),
        findsOneWidget,
      );
    });

    testWidgets('待决的普通问答不被隐藏，也不出现计划卡', (tester) async {
      final lease = leaseWith(
        tester,
        toolItemWithInput(legacyHistory(const ConversationUserInputPending())),
      );
      await pumpTimeline(tester, lease);
      expect(
        find.byKey(StudioDriverKeys.timelineUserInput('qa')),
        findsOneWidget,
        reason: '旧普通待决问答不能因为 ID 相同就被当成待确认计划而隐藏',
      );
      expect(
        find.byKey(StudioDriverKeys.timelinePlanReceipt('qa')),
        findsNothing,
      );
    });

    testWidgets('标题含 Plan 但普通问题 ID 不被改判', (tester) async {
      final lease = leaseWith(
        tester,
        toolItemWithInput(
          conversationInputFixture(
            interactionId: 'titled-1',
            questions: [
              question(
                id: 'q1',
                header: 'Plan review',
                text: '# Plan title\n\n- step one',
              ),
            ],
            state: ConversationUserInputResolved(
              answers: [
                ConversationAnswerDescriptor(
                  questionId: 'q1',
                  answerCount: (['A']).length,
                  redacted: false,
                ),
              ],
            ),
            answers: {
              'q1': ['A'],
            },
          ),
        ),
      );
      await pumpTimeline(tester, lease);
      expect(
        find.byKey(StudioDriverKeys.timelinePlanReceipt('qa')),
        findsNothing,
        reason: '计划语义不能从标题文案推断',
      );
      expect(
        find.byKey(StudioDriverKeys.timelineUserInput('qa')),
        findsOneWidget,
      );
    });
  });

  group('原门禁承接：窄窗问答布局', () {
    testWidgets('窄窗展开问题与答案不溢出', (tester) async {
      final history = conversationInputFixture(
        interactionId: 'interaction-narrow',
        questions: [
          question(
            text: 'Which option should the agent use for this long question?',
          ),
        ],
        state: ConversationUserInputResolved(
          answers: [
            ConversationAnswerDescriptor(
              questionId: 'q1',
              answerCount: (['A']).length,
              redacted: false,
            ),
          ],
        ),
        answers: {
          'q1': ['A'],
        },
      );
      final lease = leaseWith(tester, toolItemWithInput(history));
      await pumpTimeline(tester, lease, size: const Size(360, 640));
      await tester.tap(find.byKey(StudioDriverKeys.timelineUserInput('qa')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputQuestion('qa', 0)),
        findsOneWidget,
      );
    });
  });
}

/// 只替换授权读取端的环境响应；共享attempt/ref账本由真实展示资源owner维护。
final class _ImageReadTransport extends RecordingDemoTransport {
  static final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
  final List<(String, String)> reads = [];
  bool fail = true;

  @override
  Future<Uint8List> readThreadAttachment(
    String threadId,
    String attachmentId,
  ) async {
    reads.add((threadId, attachmentId));
    if (fail) {
      throw const StudioFailure(
        code: StudioFailureCode.internal,
        message: 'Image bytes are temporarily unavailable',
        retryable: true,
        correlationId: 'shared-image-failure',
      );
    }
    return bytes;
  }
}
