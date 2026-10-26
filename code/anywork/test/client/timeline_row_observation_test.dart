import 'package:anywork/src/features/conversation/state/plan_confirmation_ownership.dart';
// Canonical item → 唯一 typed Message 的适配契约。
//
// 旧实现观察的是窗口行投影（`TimelineRow`、窗口 epoch、锚点与双向分页回执）；这些能力已
// 按 design/26 删除，算法覆盖由展示 lease/owner 的测试承担
// （test/client/timeline_display_lease_test.dart、timeline_session_owner_test.dart）。
// 这里保留仍然成立且只有适配层能证明的部分：每条 canonical item 恰好一条 Message、身份与
// 作者来自条目自身、typed 载荷的保存/终态/省略账目与逐字段详情引用，以及原位更新的身份
// 稳定性；另外验证公开展示状态确实只携带元数据。
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/presentation_item.dart';
import 'package:anywork/src/features/conversation/timeline/presentation_controller.dart';
import 'package:anywork/src/features/conversation/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/views/timeline_group_view.dart';
import 'package:anywork/src/features/conversation/views/timeline_turn_outcome_view.dart';
import 'package:anywork/src/features/conversation/connectors/timeline_row_connector.dart';
import 'package:anywork/src/features/conversation/widgets/activity_row.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/timeline/display_lease.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'support/timeline_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TimelineTestEnvironment environment;
  setUp(() {
    environment = TimelineTestEnvironment(
      timeline: const UnscriptedTimelineTransport(),
    );
  });
  tearDown(() => environment.close());
  final timestamp =
      (DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch ~/ 1000);

  Message project(StudioTimelineItem item) {
    final controller = InMemoryChatController();
    final presentation = TimelinePresentationController(
      controller,
      generation: 1,
    );
    addTearDown(controller.dispose);
    addTearDown(presentation.dispose);
    presentation.add(TimelineMessagePayload.fromItem(item));
    addTearDown(presentation.flushWrites);
    return controller.messages.single;
  }

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
    int? updatedAt,
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
    String name = 'exec_command',
    ThreadToolLifecycleView? lifecycle,
    ThreadWaitPresentationView? wait,
    bool terminal = true,
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
          name: name,
          arguments: arguments,
        ),
        lifecycle: lifecycle ?? SucceededThreadToolView(
          timestamp,
          ThreadToolOutput(
            result: result,
            attachments: const [],
            outputArtifacts: const [],
          ),
        ),
        wait: wait,
      ),
    ),
    saved: true,
    lifecycle: terminal ? StudioTimelineLifecycle.terminal : StudioTimelineLifecycle.streaming,
    omittedBytes: 0,
    details: const [],
  );

  group('canonical item → 唯一 typed Message', () {
    test('每条条目恰好一条 Message，身份来自条目而不是索引', () {
      final first = project(textItem('item-a', ordinal: 1));
      final second = project(textItem('item-b', ordinal: 2));
      expect([first.id, second.id], ['item-a', 'item-b']);
      expect(first, isA<CustomMessage>());
      expect(
        first.createdAt,
        DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true),
      );
      // 同一条目重复转换不改变身份：稳定身份不要求同一个实例。
      final again = project(textItem('item-a', ordinal: 1));
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
        project(textItem('saved-but-streaming', saved: true, terminal: false)),
      )!;
      expect(payload.saved, isTrue);
      expect(payload.terminal, isFalse);
      expect(payload.hasOmittedBody, isFalse);

      final streamingButSavedLater = timelinePayloadOf(
        project(textItem('terminal', terminal: true, saved: false)),
      )!;
      expect(streamingButSavedLater.terminal, isTrue);
      expect(streamingButSavedLater.saved, isFalse);
    });

    test('逐字段详情引用按值语义查找，不依赖对象实例', () {
      final payload = timelinePayloadOf(
        project(
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
      final message = project(item);
      expect((message as CustomMessage).metadata, isNotEmpty);
      final payload = timelinePayloadOf(message)!;
      expect(payload.omittedBytes, 100);
      expect(payload.item.bodyPreviewed, isTrue);
      expect(payload.detailFor(const ThreadTextFieldView())!.truncated, isTrue);
      expect(payload.item.text, '预览');
    });

    test('工具条目的 typed 事实来自条目自身，不解析摘要字符串', () {
      final payload = timelinePayloadOf(project(toolItem('tool-1')))!;
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
      final current = project(textItem('live', body: '前半', terminal: false));
      final next = timelinePayloadOf(current)!.applyUpdate(
        StudioTimelineUpdateItem(
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
              totalBytes: 13,
              previewBytes: 13,
            ),
          ],
        ),
      );
      expect(next, isNotNull);
      expect(next!.id, current.id, reason: '身份必须保持，不移除后重插');
      final payload = next;
      expect(payload.revision, 2);
      expect(payload.saved, isTrue);
      expect(payload.terminal, isTrue);
      expect(payload.item.text, '前半 后半');
    });

    test('revision 不连续的更新被拒绝，交给显式重同步', () {
      final current = project(textItem('live', revision: 2));
      final next = timelinePayloadOf(current)!.applyUpdate(
        StudioTimelineUpdateItem(
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
      final current = project(
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
      final next = timelinePayloadOf(current)!.applyUpdate(
        StudioTimelineUpdateItem(
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
    String toolName = 'ask_user',
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
        invocation: ThreadToolInvocationView(
          toolCallId: 'call',
          callId: 'call',
          name: toolName,
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

  TimelineDisplayLease leaseWith(StudioTimelineItem item) => leaseWithItems([item]);

  TimelineDisplayLease leaseWithItems(List<StudioTimelineItem> items) {
    final lease = TimelineDisplayLease(
      session: environment.conversations.session('thread'),
      generation: 1,
    );
    lease.content.adoptBaseline(
      StudioTimelineBaseline(
        subscriptionId: 'test',
        version: 0,
        items: items,
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
      ProviderScope(
        child: MaterialApp(
          theme: pureStudioTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TimelineView(
              threadId: 'thread',
              state: TimelineViewState(
                threadId: 'thread',
                generation: lease.generation,
                displayMode: TimelineDisplayMode.live,
                connectionPhase: TimelineConnectionPhase.ready,
                connectionError: null,
                olderCursor: null,
                hasOlder: false,
                olderLoading: false,
                olderError: null,
                hasNewOutput: false,
                preparingLive: false,
              ),
              binding: lease.canvas,
              messageBuilder: (context, message) => TimelineRowConnector(
                message: message,
                display: lease.binding,
              ),
              onLoadOlder: () async {},
              onRetryOlder: () async {},
              onReturnLive: () async {},
              onEnterHistory: () {},
              onRetryConnection: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('停止是中性控制结果，真实失败仍可诊断', () {
    testWidgets('完整typed取消原因各自可见且中性，真实Turn失败保留错误表面', (tester) async {
      const cancellations = [
        (TurnCancellationCause.unspecified(), 'Turn cancelled'),
        (TurnCancellationCause.userRequested(), 'Turn stopped'),
        (TurnCancellationCause.runtimeShutdown(), 'Runtime shut down; turn stopped'),
        (TurnCancellationCause.agentClosed(), 'Agent closed; turn stopped'),
        (TurnCancellationCause.interrupted(), 'Turn stopped'),
        (TurnCancellationCause.recovery(), 'Turn stopped during recovery'),
        (TurnCancellationCause.coalesced(targetTurnId: 'next-turn'), 'Turn merged into a later turn'),
      ];
      StudioTimelineItem outcome(String id, int order, TurnState state) => StudioTimelineItem(
        item: ThreadItemView(
          id: id, threadId: 'thread', turnId: 'turn-$order', ordinal: order,
          revision: 1, createdAt: timestamp, updatedAt: timestamp,
          state: ThreadTurnItemStateView(state),
        ),
        saved: false, lifecycle: StudioTimelineLifecycle.terminal,
        omittedBytes: 0, details: const [],
      );
      final lease = leaseWithItems([
        for (var index = 0; index < cancellations.length; index++)
          outcome('stopped-$index', index + 1, TurnState.cancelled(
            startedAt: 1, requestedAt: 2, completedAt: 3,
            cause: cancellations[index].$1,
          )),
        outcome('failed', 8, const TurnState.failed(
          startedAt: 1, completedAt: 3,
          failure: TurnFailure(category: TurnFailureCategory.provider,
            providerKind: ProviderFailureKind.transport, code: 'disconnected', httpStatus: null,
            message: 'Provider disconnected during response', retry: RetryDisposition.permanent()),
        )),
      ]);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await lease.content.flushWrites();
        expect((await lease.close()).complete, isTrue);
      });
      await pumpTimeline(tester, lease, size: const Size(900, 1000));
      for (var index = 0; index < cancellations.length; index++) {
        final surface = find.byWidgetPredicate((widget) => widget is TimelineTurnOutcomeView && widget.itemId == 'stopped-$index');
        expect(surface, findsOneWidget);
        final view = tester.widget<TimelineTurnOutcomeView>(surface);
        expect(view.kind, TimelineTurnOutcomeKind.stopped);
        expect(view.label, cancellations[index].$2);
        final row = tester.widget<TimelineActivityRow>(find.byKey(ValueKey('timeline-turn-outcome:stopped-$index')));
        expect(row.isIssue, isFalse);
        expect(row.active, isFalse);
        expect(row.expandable, isFalse, reason: 'typed终态不补造可展开正文');
        expect(find.descendant(of: surface, matching: find.text(cancellations[index].$2)), findsOneWidget);
        final stopIcon = find.descendant(of: surface, matching: find.byIcon(Icons.stop_circle_outlined));
        expect(stopIcon, findsOneWidget);
        expect(tester.widget<Icon>(stopIcon).color,
          Theme.of(tester.element(surface)).colorScheme.onSurfaceVariant.withValues(alpha: .78));
        expect(find.descendant(of: surface, matching: find.byIcon(Icons.keyboard_arrow_down_rounded)), findsNothing);
        expect(find.descendant(of: surface, matching: find.byIcon(Icons.chevron_right_rounded)), findsNothing);
        expect(find.descendant(of: surface, matching: find.byIcon(Icons.error_outline)), findsNothing);
        expect(lease.content.presentationFor('stopped-$index')!.issueCount, 0);
      }
      final failed = find.byWidgetPredicate((widget) => widget is TimelineTurnOutcomeView && widget.itemId == 'failed');
      expect(tester.widget<TimelineTurnOutcomeView>(failed).kind, TimelineTurnOutcomeKind.failed);
      final failureTextFinder = find.descendant(of: failed,
        matching: find.text('Provider disconnected during response'));
      expect(failureTextFinder, findsOneWidget);
      final failureText = tester.widget<Text>(failureTextFinder);
      expect(failureText.style?.color, Theme.of(tester.element(failed)).colorScheme.error);
      final failureSemantics = tester.widget<Semantics>(find.descendant(of: failed,
        matching: find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.liveRegion == true)));
      expect(failureSemantics.child, same(failureText),
        reason: '保留e3原Semantics直接包错误色Text的失败表面');
      expect(find.descendant(of: failed, matching: find.byType(Container)), findsNothing,
        reason: '真实失败不新增背景卡片');
      expect(find.descendant(of: failed, matching: find.byType(Icon)), findsNothing,
        reason: '真实失败不被新增图标替换或装饰');
      expect(lease.content.presentationFor('failed')!.issueCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('图片组先报真实失败，再报进行中，最后保留中性停止且不展开诊断', (tester) async {
      final lease = leaseWithItems([
        toolItem('image-failed', ordinal: 1, revision: 1, name: 'view_image',
          lifecycle: FailedThreadToolView(timestamp,
            const ThreadToolFailureView(kind: ThreadToolFailureKindView.execution, message: 'Image decode failed'), null)),
        toolItem('image-active', ordinal: 2, revision: 1, name: 'view_image',
          lifecycle: const RunningThreadToolView(''), terminal: false),
        toolItem('image-stopped', ordinal: 3, revision: 1, name: 'view_image',
          lifecycle: CancelledThreadToolView(timestamp, 'Image stopped by user')),
      ]);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await lease.content.flushWrites();
        expect((await lease.close()).complete, isTrue);
      });
      final group = lease.content.presentationFor('image-stopped')!;
      final groupId = group.id;
      final groupSurface = find.byWidgetPredicate((widget) => widget is TimelineGroupView && widget.id == groupId);
      await pumpTimeline(tester, lease);
      expect(groupSurface, findsOneWidget);
      TimelineGroupView rendered() => tester.widget<TimelineGroupView>(groupSurface);
      expect(rendered().label, 'Failed to read image');
      expect(find.descendant(of: groupSurface, matching: find.text('Failed to read image')), findsOneWidget);
      expect(rendered().isIssue, isTrue);
      expect(rendered().active, isTrue);
      expect(group.issueCount, 1);
      expect(group.activeCount, 1);
      expect(find.text('Image stopped by user'), findsNothing);
      expect(group.expanded, isFalse);
      expect(lease.content.applyPatch(StudioTimelinePatch(
        subscriptionId: 'test', from: 0, to: 1, priority: StudioTimelinePriority.immediate,
        changes: [StudioTimelineAdd(toolItem('image-failed', ordinal: 1, revision: 2,
          name: 'view_image'))],
      )), isTrue);
      await tester.pumpAndSettle();
      expect(rendered().label, 'Reading image');
      expect(find.descendant(of: groupSurface, matching: find.text('Reading image')), findsOneWidget);
      expect(rendered().isIssue, isFalse);
      expect(rendered().active, isTrue);
      expect(group.issueCount, 0);
      expect(lease.content.applyPatch(StudioTimelinePatch(
        subscriptionId: 'test', from: 1, to: 2, priority: StudioTimelinePriority.immediate,
        changes: [StudioTimelineAdd(toolItem('image-active', ordinal: 2, revision: 2,
          name: 'view_image', lifecycle: InterruptedThreadToolView(timestamp, 'Image interrupted')))],
      )), isTrue);
      await tester.pumpAndSettle();
      expect(lease.content.presentationFor('image-active'), same(group));
      expect(group.id, groupId);
      expect(group.memberIds, ['image-failed', 'image-active', 'image-stopped']);
      expect(group.activeCount, 0);
      expect(rendered().label, 'Stopped reading image');
      expect(find.descendant(of: groupSurface, matching: find.text('Stopped reading image')), findsOneWidget);
      expect(rendered().isIssue, isFalse);
      expect(rendered().active, isFalse);
      expect(group.expanded, isFalse);
      expect(find.text('Image interrupted'), findsNothing);
      await tester.tap(find.byKey(StudioDriverKeys.timelineActivitySummary(groupId)));
      await tester.pumpAndSettle();
      for (final id in ['image-active', 'image-stopped']) {
        final row = tester.widget<TimelineActivityRow>(find.byKey(StudioDriverKeys.timelineActivitySummary(id)));
        expect(row.icon, Icons.stop_circle_outlined);
        expect(row.isIssue, isFalse);
        expect(row.iconColor, Theme.of(tester.element(find.byType(TimelineGroupView))).colorScheme.onSurfaceVariant);
        expect(group.memberExpanded(id), isFalse);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('工具和等待的取消诊断保原文与中性色，真实失败仍为错误色', (tester) async {
      final cases = [
        ('tool-cancelled', CancelledThreadToolView(timestamp, 'Command cancelled by user'), null, 'Command cancelled by user', false),
        ('tool-interrupted', InterruptedThreadToolView(timestamp, 'Command interrupted'), null, 'Command interrupted', false),
        ('tool-failed', FailedThreadToolView(timestamp,
          const ThreadToolFailureView(kind: ThreadToolFailureKindView.execution, message: 'Command failed'), null), null, 'Command failed', true),
        ('wait-cancelled', CancelledThreadToolView(timestamp, 'Wait cancelled by user'), ThreadWaitState.cancelled, 'Wait cancelled by user', false),
        ('wait-failed', FailedThreadToolView(timestamp,
          const ThreadToolFailureView(kind: ThreadToolFailureKindView.execution, message: 'Wait failed'), null), ThreadWaitState.failed, 'Wait failed', true),
      ];
      for (final (id, lifecycle, waitState, diagnostic, failed) in cases) {
        final lease = leaseWith(toolItem(id, revision: 1, lifecycle: lifecycle,
          wait: waitState == null ? null : ThreadWaitPresentationView(
            intent: const ThreadWaitTimerIntentView(durationMs: 60000), state: waitState,
          ),
        ));
        final group = lease.content.presentationFor(id)!;
        group.setExpanded(true);
        group.setMemberExpanded(id, true);
        try {
          await pumpTimeline(tester, lease);
          final colors = Theme.of(tester.element(find.byType(TimelineGroupView))).colorScheme;
          expect(group.issueCount, failed ? 1 : 0);
          expect(group.activeCount, 0);
          if (waitState != null) {
            final waitRow = tester.widget<TimelineActivityRow>(find.descendant(
              of: find.byKey(ValueKey('wait-expand:$id')), matching: find.byType(TimelineActivityRow),
            ));
            expect(waitRow.active, isFalse);
            expect(waitRow.iconColor, failed ? colors.error : colors.onSurfaceVariant);
            final diagnostics = find.byKey(StudioDriverKeys.waitingDiagnostics(id));
            await tester.ensureVisible(diagnostics);
            await tester.tap(diagnostics);
            await tester.pumpAndSettle();
          }
          final text = tester.widget<Text>(find.text(diagnostic));
          expect(text.style?.color, failed ? colors.error : colors.onSurfaceVariant);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await lease.content.flushWrites();
          expect((await lease.close()).complete, isTrue);
        }
      }
    });
  });

  group('原门禁承接：普通问答回执', () {
    testWidgets('独立成行、默认折叠，原位更新后保留用户展开', (tester) async {
      final history = ThreadToolUserInputView(
        interactionId: 'interaction-1',
        questions: [question()],
        state: ResolvedThreadToolUserInputView([
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
      final applied = lease.content.applyPatch(
        StudioTimelinePatch(
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
      expect(lease.content.payloadOf('qa')!.revision, 2);
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
        toolItemWithInput(
          planHistory(const PendingThreadToolUserInputView()),
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
        toolItemWithInput(
          planHistory(
            ResolvedThreadToolUserInputView([
              ThreadUserInputAnswerView(
                questionId: agentSessionPlanConfirmationQuestionId,
                answers: [agentSessionPlanReviseAnswer, '请补充回滚步骤'],
              ),
            ]),
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
    ThreadToolUserInputView legacyHistory(ThreadToolUserInputStateView state) =>
        ThreadToolUserInputView(
          interactionId: 'legacy-1',
          questions: [
            question(
              id: agentSessionPlanConfirmationQuestionId,
              header: 'Plan',
              text: '# Plan title\n\n- step one',
            ),
          ],
          state: state,
        );

    testWidgets('已回答的普通问答仍渲染普通只读回执', (tester) async {
      final lease = leaseWith(
        toolItemWithInput(
          legacyHistory(
            const ResolvedThreadToolUserInputView([
              ThreadUserInputAnswerView(
                questionId: agentSessionPlanConfirmationQuestionId,
                answers: [agentSessionPlanApproveAnswer],
              ),
            ]),
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
        toolItemWithInput(
          legacyHistory(const PendingThreadToolUserInputView()),
        ),
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
        toolItemWithInput(
          ThreadToolUserInputView(
            interactionId: 'titled-1',
            questions: [
              question(
                id: 'q1',
                header: 'Plan review',
                text: '# Plan title\n\n- step one',
              ),
            ],
            state: const ResolvedThreadToolUserInputView([
              ThreadUserInputAnswerView(questionId: 'q1', answers: ['A']),
            ]),
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
      final history = ThreadToolUserInputView(
        interactionId: 'interaction-narrow',
        questions: [
          question(
            text: 'Which option should the agent use for this long question?',
          ),
        ],
        state: ResolvedThreadToolUserInputView([
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
