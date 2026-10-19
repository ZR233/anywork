// Canonical item → 唯一 typed Message 的适配契约。
//
// 旧实现观察的是窗口行投影（`TimelineRow`、窗口 epoch、锚点与双向分页回执）；这些能力已
// 按 design/26 删除，算法覆盖由展示 lease/owner 的测试承担
// （test/client/timeline_display_lease_test.dart、timeline_session_owner_test.dart）。
// 这里保留仍然成立且只有适配层能证明的部分：每条 canonical item 恰好一条 Message、身份与
// 作者来自条目自身、typed 载荷的保存/终态/省略账目与逐字段详情引用，以及原位更新的身份
// 稳定性；另外验证公开展示状态确实只携带元数据。
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/domain/models/timeline_presentation.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
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

  StudioTimelineItem textItem(
    String id, {
    int ordinal = 1,
    int revision = 1,
    String body = '正文',
    ThreadTextChannel channel = ThreadTextChannel.finalAnswer,
    bool saved = false,
    bool terminal = false,
    int omitted = 0,
    List<StudioTimelineDetailRef> details = const [],
    String? turnId = 'turn',
    DateTime? updatedAt,
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: turnId ?? '',
      ordinal: ordinal,
      revision: revision,
      createdAt: timestamp,
      updatedAt: updatedAt ?? timestamp,
      bodyOmittedUnits: omitted,
      executionTerminal: terminal,
      saved: saved,
      state: ThreadTextItemStateView(
        channel: channel,
        text: body,
        attachments: const [],
        lifecycle: terminal
            ? CompletedThreadContentView(timestamp)
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

  StudioTimelineItem toolItem(
    String id, {
    int ordinal = 2,
    int revision = 3,
    String arguments = '{"command":"cargo test"}',
    String result = 'ok',
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: ordinal,
      revision: revision,
      createdAt: timestamp,
      updatedAt: timestamp,
      state: ThreadToolItemStateView(
        invocation: ThreadToolInvocationView(
          toolCallId: 'call-1',
          callId: 'call-1',
          name: 'exec_command',
          arguments: arguments,
        ),
        lifecycle: SucceededThreadToolView(
          timestamp,
          ThreadToolOutputView(
            result: result,
            attachments: const [],
            outputArtifacts: const [],
          ),
        ),
      ),
    ),
    saved: true,
    lifecycle: StudioTimelineLifecycle.terminal,
    omittedBytes: 0,
    details: const [],
  );

  group('canonical item → 唯一 typed Message', () {
    test('每条条目恰好一条 Message，身份来自条目而不是索引', () {
      final first = timelineMessageFor(textItem('item-a', ordinal: 1));
      final second = timelineMessageFor(textItem('item-b', ordinal: 2));
      expect([first.id, second.id], ['item-a', 'item-b']);
      expect(first, isA<CustomMessage>());
      expect(first.createdAt, timestamp);
      // 同一条目重复转换不改变身份：稳定身份不要求同一个实例。
      final again = timelineMessageFor(textItem('item-a', ordinal: 1));
      expect(again.id, first.id);
      expect(timelinePayloadOf(again)!.revision, 1);
    });

    test('作者身份只区分读者与助手，父代理输入属于读者', () {
      expect(
        timelineAuthorId(textItem('u', channel: ThreadTextChannel.user).item),
        'user',
      );
      expect(
        timelineAuthorId(
          textItem('p', channel: ThreadTextChannel.parentAgent).item,
        ),
        'user',
      );
      expect(
        timelineAuthorId(
          textItem('c', channel: ThreadTextChannel.commentary).item,
        ),
        'assistant',
      );
      expect(timelineAuthorId(toolItem('t').item), 'assistant');
    });

    test('保存与终态互相独立，省略账目来自条目本身', () {
      final payload = timelinePayloadOf(
        timelineMessageFor(
          textItem('saved-but-streaming', saved: true, terminal: false),
        ),
      )!;
      expect(payload.saved, isTrue);
      expect(payload.terminal, isFalse);
      expect(payload.hasOmittedBody, isFalse);

      final streamingButSavedLater = timelinePayloadOf(
        timelineMessageFor(textItem('terminal', terminal: true, saved: false)),
      )!;
      expect(streamingButSavedLater.terminal, isTrue);
      expect(streamingButSavedLater.saved, isFalse);
    });

    test('逐字段详情引用按值语义查找，不依赖对象实例', () {
      final payload = timelinePayloadOf(
        timelineMessageFor(
          textItem(
            'detail',
            omitted: 8,
            details: const [
              StudioTimelineDetailRef(
                field: ThreadToolArgumentsFieldView(),
                revision: 4,
                totalBytes: 40,
                previewBytes: 32,
              ),
            ],
          ),
        ),
      )!;
      final ref = payload.detailFor(const ThreadToolArgumentsFieldView());
      expect(ref, isNotNull);
      expect(ref!.revision, 4);
      expect(ref.truncated, isTrue);
      // 从未交付过的字段与“空字段”不同：没有引用。
      expect(payload.detailFor(const ThreadToolResultFieldView()), isNull);
    });

    test('预览被省略时仍保留按需读取入口，不把省略当成原文不存在', () {
      final item = textItem(
        'truncated',
        body: '预览',
        omitted: 100,
        details: const [
          StudioTimelineDetailRef(
            field: ThreadTextFieldView(),
            revision: 1,
            totalBytes: 106,
            previewBytes: 6,
          ),
        ],
      );
      final message = timelineMessageFor(item);
      expect((message as CustomMessage).metadata, isNotEmpty);
      final payload = timelinePayloadOf(message)!;
      expect(payload.omittedBytes, 100);
      expect(payload.item.bodyPreviewed, isTrue);
      expect(payload.detailFor(const ThreadTextFieldView())!.truncated, isTrue);
      expect(payload.item.text, '预览');
    });

    test('工具条目的 typed 事实来自条目自身，不解析摘要字符串', () {
      final payload = timelinePayloadOf(
        timelineMessageFor(toolItem('tool-1')),
      )!;
      final tool = payload.item.tool;
      expect(tool, isNotNull);
      expect(tool!.name, 'exec_command');
      expect(tool.result, 'ok');
      expect(payload.item.kind, ThreadItemKind.toolCall);
      // arguments 只是预览正文，语义由 typed 投影给出。
      expect(tool.arguments, contains('cargo test'));
    });
  });

  group('原位更新保持身份', () {
    test('同身份、更高 revision 的字段提交原地生效并前进保存/终态', () {
      final current = timelineMessageFor(
        textItem('live', body: '前半', terminal: false),
      );
      final next = applyTimelineItemUpdate(
        current,
        const StudioTimelineUpdateItem(
          itemId: 'live',
          expectedRevision: 1,
          revision: 2,
          omittedBytes: 0,
          saved: true,
          lifecycle: StudioTimelineLifecycle.terminal,
          fields: [
            StudioFieldUpdateView(
              field: ThreadTextFieldView(),
              change: AppendThreadFieldChangeView(' 后半'),
              totalBytes: 7,
              previewBytes: 7,
            ),
          ],
        ),
      );
      expect(next, isNotNull);
      expect(next!.id, current.id, reason: '身份必须保持，不移除后重插');
      final payload = timelinePayloadOf(next)!;
      expect(payload.revision, 2);
      expect(payload.saved, isTrue);
      expect(payload.terminal, isTrue);
      expect(payload.item.text, '前半 后半');
    });

    test('revision 不连续的更新被拒绝，交给显式重同步', () {
      final current = timelineMessageFor(textItem('live', revision: 2));
      final next = applyTimelineItemUpdate(
        current,
        const StudioTimelineUpdateItem(
          itemId: 'live',
          expectedRevision: 1,
          revision: 3,
          omittedBytes: 0,
          saved: false,
          lifecycle: StudioTimelineLifecycle.streaming,
          fields: [
            StudioFieldUpdateView(
              field: ThreadTextFieldView(),
              change: AppendThreadFieldChangeView('x'),
              totalBytes: 1,
              previewBytes: 1,
            ),
          ],
        ),
      );
      expect(next, isNull);
    });

    test('声明的整体省略量与逐字段账目矛盾时拒绝该帧', () {
      final current = timelineMessageFor(
        textItem(
          'accounting',
          body: 'ab',
          omitted: 4,
          details: const [
            StudioTimelineDetailRef(
              field: ThreadTextFieldView(),
              revision: 1,
              totalBytes: 6,
              previewBytes: 2,
            ),
          ],
        ),
      );
      final next = applyTimelineItemUpdate(
        current,
        const StudioTimelineUpdateItem(
          itemId: 'accounting',
          expectedRevision: 1,
          revision: 1,
          omittedBytes: 99,
          saved: false,
          lifecycle: StudioTimelineLifecycle.streaming,
          fields: [
            StudioFieldUpdateView(
              field: ThreadTextFieldView(),
              change: UnchangedThreadFieldChangeView(),
              totalBytes: 6,
              previewBytes: 2,
            ),
          ],
        ),
      );
      expect(next, isNull);
    });
  });

  // ---- 原门禁承接：QA 回执 / 计划回执 / 窄窗布局（真实 lease + stock controller） ----

  StudioTimelineItem toolItemWithInput(
    ThreadToolUserInputView history, {
    String id = 'qa',
    int revision = 1,
    List<StudioTimelineDetailRef> details = const [],
  }) => StudioTimelineItem(
    item: ThreadItemView(
      id: id,
      threadId: 'thread',
      turnId: 'turn',
      ordinal: 1,
      revision: revision,
      createdAt: timestamp,
      updatedAt: timestamp,
      saved: true,
      executionTerminal: false,
      state: ThreadToolItemStateView(
        invocation: const ThreadToolInvocationView(
          toolCallId: 'call',
          callId: 'call',
          name: 'ask_user',
          arguments: '{}',
        ),
        lifecycle: const RunningThreadToolView(''),
        userInput: history,
      ),
    ),
    saved: true,
    lifecycle: StudioTimelineLifecycle.streaming,
    omittedBytes: 0,
    details: details,
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

  TimelineDisplayLease leaseWith(StudioTimelineItem item) {
    final lease = TimelineDisplayLease(
      threadId: 'thread',
      generation: 1,
      openQueries: (_) => null,
    );
    lease.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'test',
        version: 0,
        items: [item],
        before: null,
        hasOlder: false,
      ),
    );
    return lease;
  }

  Future<void> pumpTimeline(
    WidgetTester tester,
    TimelineDisplayLease lease, {
    Size size = const Size(900, 700),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
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
            lease: lease,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async {},
            onEnterHistory: () {},
            onRetryConnection: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('原门禁承接：普通问答回执', () {
    testWidgets('独立成行、默认折叠，原位更新后保留用户展开', (tester) async {
      final history = ThreadToolUserInputView(
        interactionId: 'interaction-1',
        questions: [question()],
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(questionId: 'q1', answers: ['A']),
        ]),
      );
      final lease = leaseWith(toolItemWithInput(history));
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
        const StudioTimelinePatch(
          subscriptionId: 'test',
          from: 0,
          to: 1,
          priority: StudioTimelinePriority.coalesced,
          changes: [
            StudioTimelineUpdateItem(
              itemId: 'qa',
              expectedRevision: 1,
              revision: 2,
              omittedBytes: 0,
              saved: true,
              lifecycle: StudioTimelineLifecycle.streaming,
              fields: [
                StudioFieldUpdateView(
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
      expect(lease.payloadOf('qa')!.revision, 2);
    });
  });

  group('原门禁承接：计划回执', () {
    ThreadToolUserInputView planHistory(ThreadToolUserInputStateView state) =>
        ThreadToolUserInputView(
          interactionId: 'plan-1',
          questions: [
            question(
              id: agentSessionPlanConfirmationQuestionId,
              header: 'Plan',
              text: '# Plan title\n\n- step one',
            ),
          ],
          state: state,
        );

    testWidgets('待确认时不出第二张历史卡', (tester) async {
      final lease = leaseWith(
        toolItemWithInput(planHistory(const PendingThreadToolUserInputView())),
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
        toolItemWithInput(
          planHistory(
            const ResolvedThreadToolUserInputView([
              ThreadUserInputAnswerView(
                questionId: agentSessionPlanConfirmationQuestionId,
                answers: [agentSessionPlanReviseAnswer, '请补充回滚步骤'],
              ),
            ]),
          ),
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

  group('原门禁承接：窄窗问答布局', () {
    testWidgets('窄窗展开问题与答案不溢出', (tester) async {
      final history = ThreadToolUserInputView(
        interactionId: 'interaction-narrow',
        questions: [
          question(
            text: 'Which option should the agent use for this long question?',
          ),
        ],
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(questionId: 'q1', answers: ['A']),
        ]),
      );
      final lease = leaseWith(toolItemWithInput(history));
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
