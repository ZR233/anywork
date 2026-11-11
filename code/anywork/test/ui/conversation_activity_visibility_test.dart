import 'dart:async';

import 'package:anywork/src/features/conversation/timeline/state/conversation_realtime_presentation.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_activity_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/interaction_details_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_viewport.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/display_fixtures.dart';
import '../support/completion_fixtures.dart';
import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_statistics_feed.dart';

const _status = ThreadActivityView(
  threadId: 'thread',
  identity: 'activity',
  revision: 1,
  turnId: 'turn',
  kind: ThreadActivityKind.thinking,
  summary: '思考中',
);
final _live = LiveDisplayWindow(
  revision: 1,
  historyThrough: 0,
  executionPresent: true,
  blocks: const [],
);

PendingInteraction _userInput({
  required String id,
  required String questionId,
  String threadId = 'thread',
}) => PendingInteraction(
  id: id,
  threadId: threadId,
  turnId: 'turn',
  kind: InteractionKind.userInput,
  title: '待回答',
  body: '请作出决定',
  payload: UserInputInteractionPayload(
    questions: [
      UserQuestionView(
        id: questionId,
        header: '问题',
        question: '请作出决定',
        isOther: false,
        isSecret: false,
        options: const [],
      ),
    ],
  ),
);

PendingInteraction _toolApproval({String threadId = 'thread'}) =>
    PendingInteraction(
      id: 'approval',
      threadId: threadId,
      turnId: 'turn',
      kind: InteractionKind.toolApproval,
      title: '工具审批',
      body: '允许执行工具',
      payload: const ToolApprovalInteractionPayload(
        toolName: 'exec',
        arguments: {'command': 'echo approval'},
        workingDirectory: '',
      ),
    );

ConversationRealtimeRegion _project(PendingInteraction? interaction) =>
    projectConversationRealtime(
      status: _status,
      live: _live,
      storage: null,
      interaction: interaction,
    );

// The scripted boundary supplies only a typed member page. The real SDK,
// Timeline lease, connectors and renderers own admission and display lifecycle.
final class _PlanVisibilityTransport extends RecordingDemoTransport {
  late ChatAtom waitAtom;
  LiveDisplayWindow? olderPage;
  final olderReads = <({String before, ReadDemand demand})>[];
  final members = <_PlanVisibilityMembers>[];

  @override
  Future<TimelineFeed> openTimelineFeed(
    String threadId, {
    required ReadDemand demand,
  }) async => _PlanVisibilityFeed(
    inner: await super.openTimelineFeed(threadId, demand: demand),
    transport: this,
  );
}

final class _PlanVisibilityFeed extends RecordingTimelineFeed {
  _PlanVisibilityFeed({required super.inner, required this.transport});
  final _PlanVisibilityTransport transport;

  @override
  Future<LiveDisplayWindow> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) {
    final page = transport.olderPage;
    if (page == null) {
      return super.loadLiveOlder(before: before, demand: demand);
    }
    transport.olderReads.add((before: before, demand: demand));
    return Future.value(page);
  }

  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) {
    if (reference.blockId != 'plan-work') {
      return super.openDisplayMembers(
        reference: reference,
        window: window,
        demand: demand,
      );
    }
    final handle = _PlanVisibilityMembers(
      DisplayMemberPage(
        block: reference,
        revision: 1,
        sealed: false,
        entries: [
          DisplayMemberHead(
            memberKey: 'wait-row',
            memberOrder: 1,
            record: DisplayRecord(
              atom: transport.waitAtom,
              contentSource: const CurrentAtom(),
            ),
          ),
        ],
      ),
    );
    transport.members.add(handle);
    return Future.value(handle);
  }
}

final class _PlanVisibilityMembers implements DisplayMembers {
  _PlanVisibilityMembers(this.first);
  DisplayMemberPage? first;
  Completer<DisplayMemberPage?>? pending;
  bool stopping = false;
  bool closed = false;

  @override
  Future<DisplayMemberPage?> next() {
    if (stopping) return Future.value(null);
    final page = first;
    first = null;
    if (page != null) return Future.value(page);
    return (pending = Completer<DisplayMemberPage?>()).future;
  }

  @override
  void requestClose() {
    stopping = true;
    pending?.complete(null);
    pending = null;
  }

  @override
  Future<void> close() async {
    requestClose();
    closed = true;
  }
}

void main() {
  test('only a same-turn open current text renderer absorbs responding; special and authoritative notices survive', () {
    final atom = ChatAtom(
      id: 'TEXT_A',
      source: const ForegroundTurnChatSource(turnId: 'turn'),
      sourceOrder: 1,
      kind: ChatAtomKind.text,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const ActiveChatAtom(
        started: null,
        status: ChatActiveStatus.running,
      ),
      contents: const [],
    );
    LiveDisplayWindow window(List<LiveDisplayBlock> blocks) =>
        LiveDisplayWindow(
          revision: 2,
          historyThrough: 0,
          executionPresent: true,
          blocks: blocks,
        );
    final output = LiveDisplayBlock(
      id: 'text',
      blockOrder: 1,
      state: DisplayBlockState.open,
      body: SingleDisplayBlock(
        record: DisplayRecord(atom: atom, contentSource: const CurrentAtom()),
      ),
    );
    const responding = ExecutionRealtimeNotice(
      ConversationActivityView(
        identity: 'responding',
        kind: ConversationActivityKind.responding,
        turnId: 'turn',
        summary: 'TEXT_A',
      ),
    );
    const thinkingB = ExecutionRealtimeNotice(
      ConversationActivityView(
        identity: 'thinking-b',
        kind: ConversationActivityKind.thinking,
        turnId: 'turn',
        summary: 'thinking-b',
      ),
    );
    const failure = ExecutionRealtimeNotice(
      ConversationActivityView(
        identity: 'failed',
        kind: ConversationActivityKind.responding,
        turnId: 'turn',
        errorMessage: '保存失败',
      ),
    );
    expect(
      hasCurrentOutputRenderer(
        live: window([output]),
        activeTurnId: 'turn',
        notice: responding,
      ),
      isTrue,
    );
    for (final notice in [
      thinkingB,
      failure,
      const UnrestoredRealtimeNotice(),
    ]) {
      expect(
        hasCurrentOutputRenderer(
          live: window([output]),
          activeTurnId: 'turn',
          notice: notice,
        ),
        isFalse,
      );
    }
    // An absent text in a bounded window does not revoke authoritative activity.
    expect(
      hasCurrentOutputRenderer(
        live: window([]),
        activeTurnId: 'turn',
        notice: responding,
      ),
      isFalse,
    );
    expect(
      hasCurrentOutputRenderer(
        live: window([
          LiveDisplayBlock(
            id: output.id,
            blockOrder: 1,
            state: DisplayBlockState.sealed,
            body: output.body,
          ),
        ]),
        activeTurnId: 'turn',
        notice: responding,
      ),
      isFalse,
    );
  });
  for (final (label, source, accepted) in <(String, ChatSourceId?, bool)>[
    ('unknown', null, false),
    ('old foreground', const ForegroundTurnChatSource(turnId: 'old'), false),
    (
      'background',
      const BackgroundResultChatSource(messageId: 'background'),
      false,
    ),
    (
      'current foreground',
      const ForegroundTurnChatSource(turnId: 'turn'),
      true,
    ),
  ]) {
    test('normal notice requires same-cut foreground source: $label', () {
      final live = LiveDisplayWindow(
        revision: 3,
        historyThrough: 0,
        executionPresent: true,
        blocks: [
          LiveDisplayBlock(
            id: 'opaque-block',
            blockOrder: 1,
            state: DisplayBlockState.open,
            source: source,
            body: const WorkDisplayBlock(
              summary: WorkSummary(
                total: 1,
                terminal: 0,
                running: 1,
                waiting: 0,
                failed: 0,
                cancelled: 0,
                transferred: 0,
                unavailable: 0,
              ),
              members: DisplayBlockRef(
                databaseId: 'db',
                blockId: 'opaque-block',
              ),
            ),
          ),
        ],
      );
      final region = projectConversationRealtime(
        storage: null,
        interaction: null,
        live: live,
        status: const ThreadActivityView(
          threadId: 'thread',
          identity: 'same-current-notice',
          revision: 3,
          turnId: 'turn',
          kind: ThreadActivityKind.thinking,
          summary: '可靠状态概要',
          thinkingSummary: '有界思考概要',
          thinkingSeconds: 17,
        ),
      ) as ContentRealtimeRegion;
      final placement = currentWorkNotice(
        live: region.live,
        activeTurnId: 'turn',
        notices: region.notices,
      );
      expect(placement != null, accepted);
      if (accepted) {
        final matched = placement!;
        expect(matched.blockId, 'opaque-block');
        expect(matched.notice, same(region.notices.single));
        expect(matched.notice.view.summary, '可靠状态概要');
        expect(matched.notice.view.thinkingSummary, '有界思考概要');
        expect(
          currentWorkNotice(
            live: region.live,
            activeTurnId: 'another-turn',
            notices: region.notices,
          ),
          isNull,
        );
        final work = live.blocks.single;
        for (final blocked in [
          LiveDisplayWindow(
            revision: 4,
            historyThrough: 0,
            executionPresent: false,
            blocks: live.blocks,
          ),
          LiveDisplayWindow(
            revision: 4,
            historyThrough: 0,
            executionPresent: true,
            blocks: [
              LiveDisplayBlock(
                id: work.id,
                blockOrder: work.blockOrder,
                state: DisplayBlockState.sealed,
                source: work.source,
                body: work.body,
              ),
            ],
          ),
          LiveDisplayWindow(
            revision: 4,
            historyThrough: 0,
            executionPresent: true,
            blocks: [
              work,
              LiveDisplayBlock(
                id: 'newer-failed-work',
                blockOrder: 2,
                state: DisplayBlockState.open,
                source: source,
                body: WorkDisplayBlock(
                  summary: const WorkSummary(
                    total: 1,
                    terminal: 1,
                    running: 0,
                    waiting: 0,
                    failed: 1,
                    cancelled: 0,
                    transferred: 0,
                    unavailable: 0,
                  ),
                  members: const DisplayBlockRef(
                    databaseId: 'db',
                    blockId: 'newer-failed-work',
                  ),
                ),
              ),
            ],
          ),
        ]) {
          expect(
            currentWorkNotice(
              live: blocked,
              activeTurnId: 'turn',
              notices: region.notices,
            ),
            isNull,
          );
        }
      }
    });
  }

  for (final (
        label,
        running,
        waiting,
        failed,
        cancelled,
        transferred,
        unavailable,
        accepted,
      )
      in [
        ('clean idle (group-idle)', 0, 0, 0, 0, 0, 0, true),
        ('running', 1, 0, 0, 0, 0, 0, true),
        ('waiting', 0, 1, 0, 0, 0, 0, true),
        ('failed terminal', 0, 0, 1, 0, 0, 0, false),
        ('cancelled terminal', 0, 0, 0, 1, 0, 0, false),
        ('transferred terminal', 0, 0, 0, 0, 1, 0, false),
        ('unavailable running', 1, 0, 0, 0, 0, 1, false),
        ('unavailable waiting', 0, 1, 0, 0, 0, 1, false),
      ]) {
    test('normal notice requires complete non-abnormal open Work: $label', () {
      final live = LiveDisplayWindow(
        revision: 4,
        historyThrough: 0,
        executionPresent: true,
        blocks: [
          LiveDisplayBlock(
            id: 'work',
            blockOrder: 1,
            state: DisplayBlockState.open,
            source: const ForegroundTurnChatSource(turnId: 'turn'),
            body: WorkDisplayBlock(
              summary: WorkSummary(
                total: 2,
                terminal: 2 - running - waiting,
                running: running,
                waiting: waiting,
                failed: failed,
                cancelled: cancelled,
                transferred: transferred,
                unavailable: unavailable,
              ),
              members: const DisplayBlockRef(databaseId: 'db', blockId: 'work'),
            ),
          ),
        ],
      );
      for (final kind in [
        ThreadActivityKind.preparing,
        ThreadActivityKind.thinking,
        ThreadActivityKind.runningTool,
        ThreadActivityKind.planning,
      ]) {
        final region = projectConversationRealtime(
          storage: null,
          interaction: null,
          live: live,
          status: ThreadActivityView(
            threadId: 'thread',
            identity: 'notice',
            revision: 1,
            turnId: 'turn',
            kind: kind,
            summary: '真实 Turn 活动',
          ),
        ) as ContentRealtimeRegion;
        final placement = currentWorkNotice(
          live: region.live,
          activeTurnId: 'turn',
          notices: region.notices,
        );
        expect(placement != null, accepted, reason: kind.name);
        expect(region.live, same(live));
        expect(region.notices, hasLength(1));
        if (accepted) {
          expect(placement!.notice, same(region.notices.single));
        }
      }
    });
  }

  test('realtime projection preserves the actual thinking phase timing', () {
    final region = projectConversationRealtime(
      storage: null,
      interaction: null,
      live: _live,
      status: const ThreadActivityView(
        threadId: 'thread',
        identity: 'thinking-phase',
        revision: 2,
        turnId: 'turn',
        kind: ThreadActivityKind.thinking,
        summary: '思考中',
        thinkingSummary: '核对实时呈现与创建时间',
        thinkingSeconds: 17,
      ),
    ) as ContentRealtimeRegion;
    final view = region.notices
        .whereType<ExecutionRealtimeNotice>()
        .single
        .view;
    expect(view.thinkingSummary, '核对实时呈现与创建时间');
    expect(view.thinkingSeconds, 17);
  });

  test('closing Work and successor text remain ordered and storage/stop notices coexist', () {
    final live = LiveDisplayWindow(
      revision: 4,
      historyThrough: 3,
      executionPresent: true,
      blocks: [
        LiveDisplayBlock(
          id: 'work',
          blockOrder: 1,
          state: DisplayBlockState.sealed,
          body: displayWork('work', 4).body,
        ),
        LiveDisplayBlock(
          id: 'text',
          blockOrder: 2,
          state: DisplayBlockState.open,
          body: SingleDisplayBlock(
            record: DisplayRecord(
              atom: completionEntry('text', 5, text: '正文').atom,
              contentSource: const CurrentAtom(),
            ),
          ),
        ),
      ],
    );
    final projected = projectConversationRealtime(
      live: live,
      interaction: null,
      storage: const ThreadStorageStateView(
        fault: ThreadHistoryFault.writeFailed,
      ),
      status: const ThreadActivityView(
        threadId: 'thread',
        identity: 'stopping',
        revision: 2,
        turnId: 'turn',
        kind: ThreadActivityKind.stopping,
        summary: '停止中',
      ),
    ) as ContentRealtimeRegion;
    expect(projected.live, same(live));
    expect(projected.live!.blocks.map((block) => block.id), ['work', 'text']);
    expect(
      projected.notices.whereType<ExecutionRealtimeNotice>().map(
        (notice) => notice.view.kind,
      ),
      [
        ConversationActivityKind.stopping,
        ConversationActivityKind.storageBlocked,
      ],
    );
  });

  test('cold open retains saved blocks but cannot project thinking or a running timer', () {
    final live = LiveDisplayWindow(
      revision: 4,
      historyThrough: 3,
      executionPresent: false,
      blocks: [
        LiveDisplayBlock(
          id: 'work',
          blockOrder: 1,
          state: DisplayBlockState.open,
          body: displayWork('work', 4).body,
        ),
      ],
    );
    final projected = projectConversationRealtime(
      live: live,
      interaction: null,
      storage: null,
      status: _status,
    ) as ContentRealtimeRegion;
    expect(projected.live, same(live));
    expect(projected.notices.single, isA<UnrestoredRealtimeNotice>());
  });

  test('idle history-only region hides without suppressing the final historical block', () {
    expect(
      projectConversationRealtime(
        live: null,
        interaction: null,
        storage: null,
        status: null,
      ),
      isA<HiddenRealtimeRegion>(),
    );
  });
  for (final olderSource in <DisplayContentSource?>[
    null,
    const CurrentAtom(),
    const CompletedOriginal(completionId: 'older-output-completion'),
  ]) {
    testWidgets(
      'selected plan hides duplicate footer details, not Timeline Work or output; resolution and approval restore details: ${olderSource?.runtimeType ?? 'latest'}',
      (tester) async {
        const threadId = 'thread-main';
        final transport = _PlanVisibilityTransport();
        final graph = AppGraph(
          transport: transport,
          statisticsFeed: const TestStatisticsFeedPort(),
          clientId: 'plan-activity-visibility',
        );
        await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
        await pumpClientFuture(
          tester,
          (graph
                ..timeline.updateReadDemand(chatDemand)
                ..setConversationPageVisible(true))
              .client
              .directoryCommands
              .selectThread(threadId),
          'select thread',
        );
        final session = graph.client.conversations.session(threadId);
        await pumpClientUntil(
          tester,
          () =>
              session.state.hasSnapshot &&
              graph.timeline.lease(threadId)?.live.value != null,
          'initial State and Timeline',
        );
        final lease = graph.timeline.lease(threadId)!;
        final history = lease.controller.messages.toList();
        final generation = lease.generation;
        transport.waitAtom = ChatAtom(
          id: 'wait-atom',
          source: const ForegroundTurnChatSource(turnId: 'background-turn'),
          sourceOrder: 1,
          kind: ChatAtomKind.toolCall,
          delivery: ChatDeliveryKind.foreground,
          lifecycle: const ActiveChatAtom(
            started: null,
            status: ChatActiveStatus.running,
          ),
          tool: const ChatToolIdentity(callId: 'wait-call', name: 'wait'),
          wait: ThreadWaitPresentationView(
            intent: ThreadWaitEventsIntentView(
              targets: const [
                ThreadWaitTargetView(
                  taskId: 'task:timer',
                  toolName: 'sleep',
                  status: ThreadWaitTargetStatusView.running,
                ),
              ],
              timeoutMs: 120000,
            ),
            state: ThreadWaitStateView.waiting,
          ),
          contents: const [],
        );
        final work = LiveDisplayBlock(
          id: 'plan-work',
          blockOrder: 1,
          state: DisplayBlockState.open,
          source: const ForegroundTurnChatSource(turnId: 'background-turn'),
          body: WorkDisplayBlock(
            summary: displaySummary(1, terminal: 0, running: 1),
            members: const DisplayBlockRef(
              databaseId: 'plan-visibility',
              blockId: 'plan-work',
            ),
          ),
        );
        Future<LiveDisplayWindow> publishLive(
          List<LiveDisplayBlock> blocks, {
          bool executionPresent = true,
        }) async {
          final previous = lease.live.value!;
          final live = LiveDisplayWindow(
            revision: previous.revision + 1,
            historyThrough: previous.historyThrough,
            executionPresent: executionPresent,
            blocks: blocks,
            older: olderSource == null ? null : 'older-page',
          );
          transport.timelineFeeds.single.emitTimeline(
            displayBatch(
              const [],
              placement: ChatPlacement.append,
              from: live.historyThrough,
              through: live.historyThrough,
              live: live,
            ),
          );
          await pumpClientUntil(
            tester,
            () => lease.live.value?.revision == live.revision,
            'real Timeline live admission',
          );
          return live;
        }

        final live = await publishLive([work]);
        final plan = _userInput(
          id: 'plan',
          questionId: agentSessionPlanConfirmationQuestionId,
          threadId: threadId,
        );
        final question = _userInput(
          id: 'question',
          questionId: 'ordinary-question',
          threadId: threadId,
        );
        Future<void> publish(
          List<PendingInteraction> interactions, {
          ThreadActivityKind kind = ThreadActivityKind.awaitingInput,
          ThreadStorageStateView? storage,
        }) => pumpClientFuture(
          tester,
          transport.publishWorkspace(
            session.state.workspace!.copyWith(
              interactions: interactions,
              activity: ThreadActivityView(
                threadId: threadId,
                identity: 'plan-state',
                revision: 1,
                turnId: 'turn',
                kind: kind,
                summary: kind.name,
              ),
              storage: storage,
              businessRefs: const ThreadBusinessRefs(
                plan: null,
                interactions: CurrentCollectionRef(
                  databaseId: 'visibility-test',
                  collection: 'interactions',
                  revision: 1,
                ),
              ),
            ),
          ),
          'publish canonical pending interactions',
        );
        await publish([question]);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appGraphProvider.overrideWithValue(graph)],
            child: MaterialApp(
              theme: pureStudioTheme(),
              locale: const Locale('zh'),
              localizationsDelegates: [
                AppLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: Column(
                  children: [
                    Expanded(child: TimelineConnector(threadId: threadId)),
                    ConversationActivityConnector(threadId: threadId),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('completion-run-header:plan-work')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await pumpClientUntil(
          tester,
          () => find.byType(TimelineWaitPanel).evaluate().isNotEmpty,
          'Timeline Work member',
        );
        // Questions occupy the output dock, not the independent Work in Timeline.
        expect(find.byType(TimelineWaitPanel), findsOneWidget);
        expect(find.byType(InteractionDetailsConnector), findsOneWidget);

        final workView = find.byWidgetPredicate(
          (widget) => widget is CompletionRunView && widget.id == 'plan-work',
        );
        final workElement = workView.evaluate().single;
        final originalDetails = find
            .byType(InteractionDetailsConnector)
            .evaluate()
            .single;
        const olderText = '已打开的更早正文在同切面计划确认期间保留';
        final outputView = find.descendant(
          of: find.byType(ConversationActivityConnector),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ConversationCurrentConnector &&
                widget.section == ConversationLiveSection.output,
          ),
        );
        final olderMember = find.byWidgetPredicate(
          (widget) =>
              widget is TimelineMemberAtom &&
              widget.displayId == 'older-output',
        );
        Element? outputElement;
        Element? olderElement;
        DisplayRecord? olderRecord;
        if (olderSource != null) {
          // The admitted latest window remains Work-only. Only the original
          // output renderer owns the explicitly requested older Single.
          await publish(const []);
          await tester.pump();
          final completed = olderSource is CompletedOriginal;
          olderRecord = DisplayRecord(
            contentSource: olderSource,
            atom: ChatAtom(
              id: 'older-output-atom',
              completionItemId: completed ? 'older-output-completion' : null,
              completionSeq: completed ? 1 : null,
              source: const ForegroundTurnChatSource(turnId: 'older-turn'),
              sourceOrder: 1,
              turnId: 'older-turn',
              kind: ChatAtomKind.text,
              delivery: ChatDeliveryKind.foreground,
              lifecycle: completed
                  ? const TerminalChatAtom(
                      started: ChatFactPosition(effectSeq: 1, suborder: 0),
                      ended: ChatFactPosition(effectSeq: 2, suborder: 0),
                      outcome: ChatTerminalOutcome.completed,
                    )
                  : const ActiveChatAtom(
                      started: null,
                      status: ChatActiveStatus.running,
                    ),
              contents: const [],
              payload: chatEnvelope(
                'older-output-envelope',
                type: 'text',
                data: const {'channel': 'commentary'},
                bodies: [inlineBody('body', olderText)],
              ).payload,
            ),
          );
          transport.olderPage = LiveDisplayWindow(
            revision: live.revision,
            historyThrough: live.historyThrough,
            executionPresent: live.executionPresent,
            blocks: [
              LiveDisplayBlock(
                id: 'older-output',
                blockOrder: 0,
                state: completed
                    ? DisplayBlockState.sealed
                    : DisplayBlockState.open,
                source: olderRecord.atom.source,
                body: SingleDisplayBlock(record: olderRecord),
              ),
              work,
            ],
          );
          final olderButton = find.descendant(
            of: find.byType(ConversationActivityConnector),
            matching: find.widgetWithText(TextButton, '更早实时片段'),
          );
          expect(olderButton, findsOneWidget);
          await tester.ensureVisible(olderButton);
          await tester.tap(olderButton);
          await pumpClientUntil(
            tester,
            () =>
                find.text(olderText, findRichText: true).evaluate().isNotEmpty,
            'original output renderer loads older Single',
          );
          expect(transport.olderReads, hasLength(1));
          expect(transport.olderReads.single.before, 'older-page');
          expect(lease.live.value, same(live));
          expect(live.blocks.single.body, isA<WorkDisplayBlock>());
          outputElement = outputView.evaluate().single;
          olderElement = olderMember.evaluate().single;
          expect(
            tester.widget<TimelineMemberAtom>(olderMember).record,
            same(olderRecord),
          );
        }
        await publish([plan]);
        await tester.pump();
        expect(find.byType(InteractionDetailsConnector), findsNothing);
        if (olderSource == null) {
          expect(find.byType(ConversationActivityBar), findsNothing);
          expect(
            tester.getSize(find.byType(ConversationActivityConnector)).height,
            0,
          );
          expect(
            tester.getSize(find.byType(ConversationActivityViewport)).height,
            0,
          );
        } else {
          expect(find.text(olderText, findRichText: true), findsOneWidget);
          expect(outputView.evaluate().single, same(outputElement));
          expect(
            tester.widget<TimelineMemberAtom>(olderMember).record,
            same(olderRecord),
          );
          expect(transport.olderReads, hasLength(1));
          expect(tester.getSize(outputView).height, greaterThan(0));
        }
        expect(originalDetails.mounted, isFalse);
        expect(find.byType(TimelineWaitPanel), findsOneWidget);
        expect(workView.evaluate().single, same(workElement));
        expect(lease.live.value, same(live));
        expect(graph.timeline.lease(threadId), same(lease));
        expect(lease.generation, generation);
        expect(transport.members.single.closed, isFalse);
        expect(lease.controller.messages, orderedEquals(history));

        // Approval and revision commands share this canonical removal boundary.
        // Their command/draft semantics are covered by plan_feedback_lifecycle_test.
        await publish(const []);
        await tester.pump();
        expect(find.byType(TimelineWaitPanel), findsOneWidget);
        expect(workView.evaluate().single, same(workElement));
        expect(lease.live.value, same(live));
        if (olderSource != null) {
          expect(find.text(olderText, findRichText: true), findsOneWidget);
          expect(outputView.evaluate().single, same(outputElement));
          expect(transport.olderReads, hasLength(1));
        }

        await publish([plan]);
        await tester.pump();
        expect(find.byType(InteractionDetailsConnector), findsNothing);
        await publish([plan, _toolApproval(threadId: threadId)]);
        await tester.pump();
        expect(find.byType(TimelineWaitPanel), findsOneWidget);
        expect(find.byType(InteractionDetailsConnector), findsOneWidget);
        expect(
          find.byType(InteractionDetailsConnector).evaluate().single,
          isNot(same(originalDetails)),
        );
        expect(lease.live.value, same(live));
        expect(workView.evaluate().single, same(workElement));
        expect(transport.members, hasLength(1));
        expect(transport.members.single.closed, isFalse);
        expect(lease.controller.messages, orderedEquals(history));
        expect(graph.timeline.lease(threadId), same(lease));
        expect(lease.generation, generation);
        if (olderSource != null) {
          expect(find.text(olderText, findRichText: true), findsOneWidget);
          expect(outputView.evaluate().single, same(outputElement));
          expect(transport.olderReads, hasLength(1));
        }

        final output = LiveDisplayBlock(
          id: 'plan-output',
          blockOrder: 2,
          state: DisplayBlockState.open,
          source: const ForegroundTurnChatSource(turnId: 'turn'),
          body: SingleDisplayBlock(
            record: DisplayRecord(
              contentSource: const CurrentAtom(),
              atom: ChatAtom(
                id: 'output-atom',
                source: const ForegroundTurnChatSource(turnId: 'turn'),
                sourceOrder: 2,
                turnId: 'turn',
                kind: ChatAtomKind.text,
                delivery: ChatDeliveryKind.foreground,
                lifecycle: const ActiveChatAtom(
                  started: null,
                  status: ChatActiveStatus.running,
                ),
                contents: const [],
                payload: chatEnvelope(
                  'output-envelope',
                  type: 'text',
                  data: const {'channel': 'commentary'},
                  bodies: [inlineBody('body', '计划待决期间仍然可见的实际正文')],
                ).payload,
              ),
            ),
          ),
        );
        await publish(
          [plan],
          kind: ThreadActivityKind.stopping,
          storage: const ThreadStorageStateView(
            fault: ThreadHistoryFault.writeFailed,
            lastError: '磁盘写入失败',
          ),
        );
        if (olderSource != null) {
          olderElement = olderMember.evaluate().single;
          expect(olderElement.mounted, isTrue);
          expect(
            tester.widget<TimelineMemberAtom>(olderMember).isActive(),
            isTrue,
          );
        }
        await publishLive([work, output]);
        await tester.pump();
        if (olderSource != null) {
          // A genuine cut change retires the old window. Retaining it across a
          // same-cut State update must not turn into an unconditional keep-alive.
          expect(find.text(olderText, findRichText: true), findsNothing);
          expect(olderElement!.mounted, isFalse);
          expect(transport.olderReads, hasLength(1));
        }
        expect(
          find.text('计划待决期间仍然可见的实际正文', findRichText: true),
          findsOneWidget,
        );
        for (final kind in [
          ConversationActivityKind.stopping,
          ConversationActivityKind.storageBlocked,
        ]) {
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is ConversationActivityStatus &&
                  widget.view.kind == kind,
            ),
            findsOneWidget,
          );
        }
        expect(find.textContaining('磁盘写入失败'), findsOneWidget);
        expect(find.byType(InteractionDetailsConnector), findsNothing);
        expect(workView.evaluate().single, same(workElement));
        expect(lease.controller.messages, orderedEquals(history));

        await publish([plan], kind: ThreadActivityKind.thinking);
        await publishLive([work, output], executionPresent: false);
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(ConversationActivityConnector),
            matching: find.text('上次执行未收束，尚未恢复'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: workView, matching: find.text('上次执行未收束，尚未恢复')),
          findsOneWidget,
        );
        expect(
          find.text('计划待决期间仍然可见的实际正文', findRichText: true),
          findsOneWidget,
        );
        expect(find.byType(InteractionDetailsConnector), findsNothing);
        expect(workView.evaluate().single, same(workElement));
        expect(graph.timeline.lease(threadId), same(lease));
        expect(lease.generation, generation);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpClientFuture(
          tester,
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
          'activity visibility close',
        );
        expect(lease.isRetired, isTrue);
        expect(lease.isReleased, isTrue);
        expect(lease.queryCleanupError, isNull);
        expect(transport.members.single.closed, isTrue);
      },
    );
  }

  test('Plan confirmation uses its State controls without hiding the actual activity snapshot', () {
    final state = _project(
      _userInput(
        id: 'plan',
        questionId: agentSessionPlanConfirmationQuestionId,
      ),
    );

    expect(state, isA<ContentRealtimeRegion>());
    final content = state as ContentRealtimeRegion;
    expect(content.live, same(_live));
    expect(
      content.notices.whereType<ExecutionRealtimeNotice>().single.view.kind,
      ConversationActivityKind.thinking,
    );
  });

  for (final (turnId, replaced) in [('turn', true), ('other-turn', false)]) {
    test(
      'selected plan input-wait replacement retains source qualification: $turnId',
      () {
        final region = projectConversationRealtime(
          storage: null,
          interaction: _userInput(
            id: 'plan',
            questionId: agentSessionPlanConfirmationQuestionId,
          ),
          live: _live,
          status: ThreadActivityView(
            threadId: 'thread',
            identity: 'plan-input-wait',
            revision: 1,
            turnId: turnId,
            kind: ThreadActivityKind.awaitingInput,
            summary: '等待计划确认',
          ),
        );
        if (replaced) {
          expect(region, isA<HiddenRealtimeRegion>());
        } else {
          final content = region as ContentRealtimeRegion;
          expect(
            content.notices
                .whereType<ExecutionRealtimeNotice>()
                .single
                .view
                .turnId,
            turnId,
          );
        }
      },
    );
  }

  test('ordinary questions suppress duplicate status text and preserve unfinished operations', () {
    final state = _project(
      _userInput(id: 'question', questionId: 'ordinary-question'),
    );

    expect(state, isA<DockRealtimeRegion>());
    expect((state as DockRealtimeRegion).interactionId, 'question');
  });

  test('resolved interaction retains the real activity observation', () {
    final state = _project(null) as ContentRealtimeRegion;

    expect(state, isNotNull);
    expect(state.live, same(_live));
    expect(
      state.notices.whereType<ExecutionRealtimeNotice>().single.view.kind,
      ConversationActivityKind.thinking,
    );
  });

  test('tool approval keeps the existing activity projection', () {
    final state = _project(_toolApproval()) as ContentRealtimeRegion;

    expect(state, isNotNull);
    expect(state.live, same(_live));
    expect(
      state.notices.whereType<ExecutionRealtimeNotice>().map(
        (notice) => notice.view.kind,
      ),
      [
        ConversationActivityKind.thinking,
        ConversationActivityKind.awaitingApproval,
      ],
    );
  });
}
