import 'package:anywork/src/features/conversation/timeline/connectors/timeline_media_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_detail_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';

import 'dart:async';
import 'dart:typed_data';

import 'support/recording_demo_transport.dart';
import 'support/pump_client_future.dart';

import 'support/conversation_fixtures.dart';
import 'support/mapped_conversation_feed.dart';

// 完成原子映射为唯一正文消息；局部观察、typed 字段、省略账目与授权资源
// 使用真实 Flyer/controller 验证。回执展开通过真实 SDK 与 owner 接纳后的 lease 验证。
import 'package:anywork/src/app/theme/material3_theme.dart';
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
    int appendSeq = 1,
    String body = 'body',
    ThreadTextChannel channel = ThreadTextChannel.finalAnswer,
    int? sealedAt,
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    appendSeq: appendSeq,
    sealedAt: sealedAt,
    descriptor: ConversationTextDescriptor(
      channel: channel,
      attachments: const [],
      outcome: ConversationContentCompleted(
        CompletedThreadContentView(timestamp),
      ),
    ),
    fields: {const ThreadTextFieldView(): body},
  );

  ConversationItem toolItem(String id) => conversationFixture(
    id: id,
    threadId: 'thread',
    descriptor: ConversationToolDescriptor(
      invocation: const ConversationToolInvocation(
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
      const ThreadToolArgumentsFieldView(): '{"command":"cargo test"}',
      const ThreadToolResultFieldView(): 'ok',
    },
  );

  group('完成原子与局部展示观察', () {
    test('完成文本只生成一条稳定消息，重复完整载荷不通知其它行', () async {
      final h = _Messages();
      await h.model.initialize([textItem('a'), textItem('b', appendSeq: 2)]);
      final first = h.chat.messages.first;
      final entry = h.model.ownerOf('a')!;
      final member = h.model.memberObservation('a')!;
      var changed = 0;
      member.addListener(() => changed++);
      await h.model.append([
        textItem('b', appendSeq: 2),
        textItem('c', appendSeq: 3),
      ]);
      expect(h.chat.messages, hasLength(3));
      expect(h.chat.messages.first, same(first));
      expect(h.model.ownerOf('a'), same(entry));
      expect(
        h.chat.messages.map((message) => message.id).toSet(),
        hasLength(3),
      );
      expect(
        h.chat.messages.every((message) => message is TextMessage),
        isTrue,
      );
      expect(changed, 0);
    });

    test('作者身份来自频道，父代理输入属于读者', () {
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

    test('seal未知仍为完成文本，只有真实seal生成消息日期', () async {
      final h = _Messages();
      await h.model.initialize([
        textItem('unknown'),
        textItem('known', appendSeq: 2, sealedAt: 1767323045),
      ]);
      expect(h.chat.messages.first, isA<TextMessage>());
      expect(h.chat.messages.first.createdAt, isNull);
      expect(
        h.chat.messages.last.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1767323045000, isUtc: true),
      );
      expect(h.model.item('unknown')!.header.sealedAt, isNull);
    });

    test('逐字段详情按值查找，保留省略字节及完整读取入口', () async {
      final h = _Messages();
      final value = conversationCopyFixture(
        toolItem('detail'),
        fields: {const ThreadToolArgumentsFieldView(): 'a' * 32},
        totalBytes: {const ThreadToolArgumentsFieldView(): 40},
      );
      await h.model.initialize([value]);
      final payload = h.model.item('detail')!;
      final ref = payload.detailFor(const ThreadToolArgumentsFieldView())!;
      expect(ref.field, const ThreadToolArgumentsFieldView());
      expect(ref.totalBytes, 40);
      expect(ref.previewBytes, 32);
      expect(ref.truncated, isTrue);
      expect(payload.omittedBytes, 8);
      expect(payload.detailFor(const ThreadToolResultFieldView()), isNull);
    });

    test('正文预览省略不等于正文不存在，工具事实不解析摘要', () async {
      final h = _Messages();
      final value = conversationCopyFixture(
        textItem('truncated', body: '预览'),
        totalBytes: {const ThreadTextFieldView(): 106},
      );
      await h.model.initialize([value]);
      expect(h.chat.messages.single, isA<TextMessage>());
      expect(value.omittedBytes, 100);
      expect(value.fieldFor(const ThreadTextFieldView())!.previewBytes, 6);
      expect(value.detailFor(const ThreadTextFieldView())!.truncated, isTrue);
      expect(timelineText(value), '预览');
      final tool = toolItem('tool');
      expect(
        (tool.descriptor as ConversationToolDescriptor).invocation.name,
        'exec_command',
      );
      expect(tool.fieldFor(const ThreadToolResultFieldView())!.text, 'ok');
    });

    test('同ID不同载荷拒绝，原消息与局部观察不变', () async {
      final h = _Messages();
      await h.model.initialize([textItem('a')]);
      final message = h.chat.messages.single;
      final member = h.model.memberObservation('a');
      await expectLater(
        h.model.append([textItem('a', body: 'conflict')]),
        throwsStateError,
      );
      expect(h.chat.messages.single, same(message));
      expect(h.model.memberObservation('a'), same(member));
      expect(timelineText(h.model.item('a')!), 'body');
    });

    test('同原子多附件只有一个Message，共享授权读取与重试随展示释放', () async {
      const image = ThreadAttachmentView(
        id: 'image-a',
        modality: AttachmentModalityView.image,
        mediaType: 'image/png',
        byteSize: 8,
      );
      final h = _Messages();
      ConversationItem media(String id, int seq) => conversationFixture(
        id: id,
        threadId: 'thread',
        turnId: null,
        appendSeq: seq,
        descriptor: ConversationTextDescriptor(
          channel: ThreadTextChannel.user,
          attachments: const [
            image,
            ThreadAttachmentView(
              id: 'file',
              modality: AttachmentModalityView.file,
              mediaType: 'text/plain',
              byteSize: 10,
            ),
          ],
          outcome: ConversationContentCompleted(
            CompletedThreadContentView(timestamp),
          ),
        ),
      );
      await h.model.initialize([media('media', 1), media('peer', 2)]);
      expect(h.chat.messages, hasLength(2));
      expect(h.chat.messages.whereType<ImageMessage>(), isEmpty);
      expect(h.chat.messages.whereType<FileMessage>(), isEmpty);
      expect(h.model.item('media')!.header.turnId, isNull);
      expect(timelineAttachments(h.model.item('media')!), hasLength(2));
      final transport = _ImageReadTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'shared-image-read',
      );
      addTearDown(client.close);
      Future<Uint8List> read() =>
          client.readAttachmentBytes('thread', 'image-a');
      final shared = h.images.borrow('image-a');
      expect(h.images.borrow('image-a'), same(shared));
      final first = shared.load(read);
      final peer = shared.load(read);
      expect(peer, same(first));
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
      Future<Uint8List>? left;
      Future<Uint8List>? right;
      void leftChanged() => left = shared.load(read);
      void rightChanged() => right = shared.load(read);
      shared.addListener(leftChanged);
      shared.addListener(rightChanged);
      transport.fail = false;
      shared.retry(read);
      expect(left, isNotNull);
      expect(left, same(right));
      expect(await left!, orderedEquals(_ImageReadTransport.bytes));
      expect(await right!, orderedEquals(_ImageReadTransport.bytes));
      expect(transport.reads, hasLength(2));
      expect(shared.load(read), same(left));
      shared.removeListener(leftChanged);
      shared.removeListener(rightChanged);
      h.model.dispose();
      expect(() => h.images.borrow('image-a'), throwsStateError);
      expect(shared.owns(left!), isFalse);
    });
  });

  // ---- 原门禁承接：QA 回执 / 计划回执 / 窄窗布局（真实 lease + stock controller） ----

  ConversationItem toolItemWithInput(
    ConversationInputFixture history, {
    String id = 'qa',
    String toolName = 'ask_user',
  }) => conversationFixture(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    appendSeq: 1,
    descriptor: ConversationToolDescriptor(
      invocation: ConversationToolInvocation(
        toolCallId: 'call',
        callId: 'call',
        name: toolName,
      ),
      userInput: (history).descriptor,
      state: ConversationToolSucceeded(
        completedAt: timestamp,
        output: ConversationToolOutputDescriptor(attachments: const []),
      ),
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

  final transports = <TimelineDisplayLease, _RowTransport>{};
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

  Future<TimelineDisplayLease> leaseWith(
    WidgetTester tester,
    ConversationItem item,
  ) async {
    final transport = _RowTransport(item);
    final client = AnyworkClient(transport: transport, clientId: 'row-owner');
    final owner = TimelineSessionOwner(client: client);
    client.conversations.setVisibleThread('thread');
    owner.select('thread');
    await pumpClientFuture(
      tester,
      client.conversations.session('thread').content.ready,
      'row owner acceptance',
    );
    final lease = owner.lease('thread')!;
    transports[lease] = transport;
    addTearDown(() async {
      client.conversations.setVisibleThread(null);
      await unmountTimeline(tester, lease);
      expect(
        (await pumpClientFuture(
          tester,
          owner.close(),
          'row owner close',
        )).complete,
        isTrue,
      );
      expect(
        (await pumpClientFuture(
          tester,
          client.close(),
          'row client close',
        )).complete,
        isTrue,
      );
    });
    return lease;
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
    testWidgets('独立成行、默认折叠，追加其它原子保留用户展开', (tester) async {
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
      final lease = await leaseWith(tester, toolItemWithInput(history));
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

      final entry = lease.presentationFor('qa');
      final member = lease.memberObservation('qa');
      transports[lease]!.feed.emit(
        ConversationBatch(
          subscriptionId: 'row',
          timelineEpoch: 'row-epoch',
          fromSeq: 1,
          throughSeq: 2,
          items: [textItem('next', appendSeq: 2)],
        ),
      );
      await pumpClientUntil(
        tester,
        () => lease.completedCursor?.appendSeq == 2,
        'next atom accepted',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputQuestion('qa', 0)),
        findsOneWidget,
        reason: '其它行提交不得收起用户主动展开的回执',
      );
      expect(lease.presentationFor('qa'), same(entry));
      expect(lease.memberObservation('qa'), same(member));
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
      final lease = await leaseWith(
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

    testWidgets('标题含 Plan 但普通问题 ID 不被改判', (tester) async {
      final lease = await leaseWith(
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
      final lease = await leaseWith(tester, toolItemWithInput(history));
      await pumpTimeline(tester, lease, size: const Size(360, 640));
      await tester.tap(find.byKey(StudioDriverKeys.timelineUserInput('qa')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputQuestion('qa', 0)),
        findsOneWidget,
      );
    });

    testWidgets('多题按 questionId 关联，敏感回答永不渲染原文', (tester) async {
      const secret = 'hunter2-secret-token';
      final secretQuestion = UserQuestionView(
        id: 'q2',
        header: 'Secret',
        question: 'Provide the token',
        isOther: true,
        isSecret: true,
        options: const [],
      );
      final secretHistory = conversationInputFixture(
        interactionId: 'interaction-multi',
        questions: [
          question(id: 'q1', header: 'Pick one', text: 'Visible question'),
          secretQuestion,
        ],
        state: ConversationUserInputResolved(
          answers: [
            const ConversationAnswerDescriptor(
              questionId: 'q1',
              answerCount: 1,
              redacted: false,
            ),
            const ConversationAnswerDescriptor(
              questionId: 'q2',
              answerCount: 1,
              redacted: false,
            ),
          ],
        ),
        answers: {
          'q1': ['A'],
          'q2': [secret],
        },
      );
      final lease = await leaseWith(tester, toolItemWithInput(secretHistory));
      await pumpTimeline(tester, lease, size: const Size(360, 640));
      await tester.tap(find.byKey(StudioDriverKeys.timelineUserInput('qa')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputQuestion('qa', 0)),
        findsOneWidget,
      );
      expect(
        find.byKey(StudioDriverKeys.timelineUserInputQuestion('qa', 1)),
        findsOneWidget,
      );
      expect(find.text('A'), findsWidgets);
      expect(find.text(secret), findsNothing);
      expect(find.text('Sensitive answer hidden'), findsOneWidget);
      expect(tester.takeException(), isNull);
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

final class _Messages {
  _Messages() {
    addTearDown(() {
      model.dispose();
      images.retire();
      images.release();
      chat.dispose();
    });
  }
  final chat = InMemoryChatController();
  final images = TimelineImageResources(threadId: 'thread');
  late final model = TimelineMessageController(
    chat,
    generation: 1,
    imageResources: images,
  );
}

final class _RowTransport extends Fake implements StudioTransport {
  _RowTransport(this.item);
  final ConversationItem item;
  late final feed = ScriptedConversationFeed(
    threadId: 'thread',
    subscriptionId: 'row',
    baseline: () => ConversationBaseline(
      subscriptionId: 'row',
      timelineEpoch: 'row-epoch',
      items: [item],
      before: null,
      hasOlder: false,
      completedCursor: const ConversationCompletionCursor(
        timelineEpoch: 'row-epoch',
        appendSeq: 1,
      ),
    ),
  );
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    ConversationCompletionCursor? resumeAfter,
  }) async => feed;
}
