import '../support/test_app_lifecycle.dart';

import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/interaction_details_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_bar.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_state.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_projection.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_view_model.dart';
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
final _live = CurrentRunSnapshot(
  currentWorkId: null,
  revision: 1,
  layoutRevision: 1,
  readyFrontier: 0,
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

LiveStatusView _observe({
  ThreadActivityView? status = _status,
  CurrentRunSnapshot? live,
  ThreadStorageStateView? storage,
  PendingInteraction? interaction,
  String? activeTurnId = 'turn',
  LiveWindowPagingState outputPaging = const LatestLiveWindow(),
}) => LiveStatusProjection.project(
  threadId: 'thread',
  observation: LiveStatusInputs(
    cut: live == null
        ? const LiveWindowCut.inactive()
        : LiveWindowCut(
            revision: live.revision,
            readyFrontier: live.readyFrontier,
            executionPresent: live.executionPresent,
            attemptId: 1,
            isDisplayActive: true,
          ),
    storage: storage,
    interactions: [?interaction],
    activeTurnId: activeTurnId,
    activity: status,
    latestLive: live,
  ),
  outputPaging: outputPaging,
  timelineWorkPaging: const LatestLiveWindow(),
);

LiveStatusView _project(PendingInteraction? interaction) =>
    _observe(live: _live, interaction: interaction);

void main() {
  test(
    '#364 background activity without activeTurnId owns the current Work',
    () {
      final live = CurrentRunSnapshot(
        currentWorkId: 'background-tail',
        revision: 1,
        layoutRevision: 1,
        readyFrontier: 0,
        executionPresent: true,
        blocks: [
          LiveDisplayBlock(
            id: 'background-tail',
            blockOrder: 1,
            state: DisplayBlockState.open,
            source: const BackgroundResultChatSource(messageId: 'background'),
            body: WorkDisplayBlock(
              timing: displayTiming(),
              members: const DisplayBlockRef(
                databaseId: 'db',
                blockId: 'background-tail',
              ),
            ),
          ),
        ],
      );
      final projected = _observe(
        live: live,
        activeTurnId: null,
        status: const ThreadActivityView(
          threadId: 'thread',
          identity: 'background-tool',
          revision: 1,
          turnId: null,
          kind: ThreadActivityKind.runningTool,
          summary: '后台命令仍在运行',
        ),
      );
      expect(projected.timelineWork.workBlocks, isEmpty);
      final surface = (projected.barState as LiveStatusPresenting).surface;
      expect(surface, isA<LiveStatusWorkSurface>());
      expect(
        (surface as LiveStatusWorkSurface).workBlock.id,
        'background-tail',
      );
      expect(surface.mergedActivity?.summary, '后台命令仍在运行');
      expect(surface.standaloneNotices, isEmpty);
    },
  );

  test(
    '#364 older partial page cannot move or clear the canonical current Work',
    () {
      final latest = CurrentRunSnapshot(
        currentWorkId: 'tail',
        revision: 10,
        layoutRevision: 10,
        readyFrontier: 2,
        executionPresent: true,
        blocks: [
          LiveDisplayBlock(
            id: 'tail',
            blockOrder: 20,
            state: DisplayBlockState.open,
            source: const ForegroundTurnChatSource(turnId: 'older-turn'),
            body: displayWork('tail', 1).body,
          ),
        ],
        older: 'older-page',
      );
      final older = CurrentRunSnapshot(
        currentWorkId: null,
        revision: 10,
        layoutRevision: 10,
        readyFrontier: 2,
        executionPresent: true,
        blocks: [
          LiveDisplayBlock(
            id: 'sealed-prefix',
            blockOrder: 1,
            state: DisplayBlockState.sealed,
            body: displayWork('sealed-prefix', 1).body,
          ),
        ],
        older: 'even-older',
      );
      final selected = _observe(
        live: latest,
        activeTurnId: null,
        outputPaging: ViewingOlderLiveWindow(
          before: 'older-page',
          window: older,
          cut: LiveWindowCut(
            revision: latest.layoutRevision,
            readyFrontier: latest.readyFrontier,
            executionPresent: latest.executionPresent,
            attemptId: 1,
            isDisplayActive: true,
          ),
        ),
      );
      final surface =
          (selected.barState as LiveStatusPresenting).surface
              as LiveStatusWorkSurface;
      expect(surface.workBlock, same(latest.blocks.single));
      expect(surface.mergedActivity?.kind, ConversationActivityKind.thinking);
      expect(surface.workBlock.id, 'tail');
      expect(selected.timelineWork.workBlocks, isEmpty);
      expect(
        (selected.barState as LiveStatusPresenting).paging.olderWindow,
        same(older),
      );
    },
  );

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
    CurrentRunSnapshot window(List<LiveDisplayBlock> blocks) =>
        CurrentRunSnapshot(
          currentWorkId: null,
          revision: 2,
          layoutRevision: 2,
          readyFrontier: 0,
          executionPresent: true,
          blocks: blocks,
        );
    final output = LiveDisplayBlock(
      id: 'text',
      blockOrder: 1,
      state: DisplayBlockState.open,
      body: SingleDisplayBlock(
        visibility: HistorySingleVisibility.content,
        record: DisplayRecord(
          atom: atom,
          contentSource: const CurrentAtomSource(),
        ),
      ),
    );
    const responding = ExecutionLiveNotice(
      ConversationActivityView(
        identity: 'responding',
        kind: ConversationActivityKind.responding,
        turnId: 'turn',
        summary: 'TEXT_A',
      ),
    );
    const thinkingB = ExecutionLiveNotice(
      ConversationActivityView(
        identity: 'thinking-b',
        kind: ConversationActivityKind.thinking,
        turnId: 'turn',
        summary: 'thinking-b',
      ),
    );
    const failure = ExecutionLiveNotice(
      ConversationActivityView(
        identity: 'failed',
        kind: ConversationActivityKind.responding,
        turnId: 'turn',
        errorMessage: '保存失败',
      ),
    );
    expect(
      LiveStatusProjection.hasCurrentOutputRenderer(
        live: window([output]),
        activeTurnId: 'turn',
        notice: responding,
      ),
      isTrue,
    );
    for (final notice in [thinkingB, failure, const UnrestoredLiveNotice()]) {
      expect(
        LiveStatusProjection.hasCurrentOutputRenderer(
          live: window([output]),
          activeTurnId: 'turn',
          notice: notice,
        ),
        isFalse,
      );
    }
    // An absent text in a bounded window does not revoke authoritative activity.
    expect(
      LiveStatusProjection.hasCurrentOutputRenderer(
        live: window([]),
        activeTurnId: 'turn',
        notice: responding,
      ),
      isFalse,
    );
    expect(
      LiveStatusProjection.hasCurrentOutputRenderer(
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
    ('unknown', null, true),
    ('old foreground', const ForegroundTurnChatSource(turnId: 'old'), true),
    (
      'background',
      const BackgroundResultChatSource(messageId: 'background'),
      true,
    ),
    (
      'current foreground',
      const ForegroundTurnChatSource(turnId: 'turn'),
      true,
    ),
  ]) {
    test(
      'current Work absorbs normal activity regardless of diagnostic source: $label',
      () {
        final live = CurrentRunSnapshot(
          currentWorkId: 'opaque-block',
          revision: 3,
          layoutRevision: 3,
          readyFrontier: 0,
          executionPresent: true,
          blocks: [
            LiveDisplayBlock(
              id: 'opaque-block',
              blockOrder: 1,
              state: DisplayBlockState.open,
              source: source,
              body: const WorkDisplayBlock(
                timing: WorkTiming(startedAt: 0, finishedAt: null),
                members: DisplayBlockRef(
                  databaseId: 'db',
                  blockId: 'opaque-block',
                ),
              ),
            ),
          ],
        );
        const status = ThreadActivityView(
          threadId: 'thread',
          identity: 'same-current-notice',
          revision: 3,
          turnId: 'turn',
          kind: ThreadActivityKind.thinking,
          summary: '可靠状态概要',
          thinkingSummary: '有界思考概要',
          thinkingSeconds: 17,
        );
        final notice = ExecutionLiveNotice(
          LiveStatusProjection.mapThreadActivity(status),
        );
        final placement = LiveStatusProjection.mergeableWorkNotice(
          live: live,
          notices: [notice],
        );
        final aggregate = _observe(live: live, status: status);
        expect(placement != null, accepted);
        if (accepted) {
          final matched = placement!;
          expect(matched.blockId, 'opaque-block');
          expect(matched.notice, same(notice));
          expect(matched.notice.view.summary, '可靠状态概要');
          expect(matched.notice.view.thinkingSummary, '有界思考概要');
          final presenting = aggregate.barState as LiveStatusPresenting;
          expect(presenting.surface, isA<LiveStatusWorkSurface>());
          expect(
            (presenting.surface as LiveStatusWorkSurface)
                .mergedActivity
                ?.summary,
            '可靠状态概要',
          );
          expect(presenting.surface.standaloneNotices, isEmpty);
          expect(aggregate.timelineWork.workBlocks, isEmpty);
          final work = live.blocks.single;
          for (final blocked in [
            CurrentRunSnapshot(
              currentWorkId: 'opaque-block',
              revision: 4,
              layoutRevision: 4,
              readyFrontier: 0,
              executionPresent: false,
              blocks: live.blocks,
            ),
            CurrentRunSnapshot(
              currentWorkId: null,
              revision: 4,
              layoutRevision: 4,
              readyFrontier: 0,
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
            CurrentRunSnapshot(
              currentWorkId: null,
              revision: 4,
              layoutRevision: 4,
              readyFrontier: 0,
              executionPresent: true,
              blocks: [work],
            ),
          ]) {
            expect(
              LiveStatusProjection.mergeableWorkNotice(
                live: blocked,
                notices: [notice],
              ),
              isNull,
            );
          }
        } else {
          expect(aggregate.timelineWork.workBlocks.single.id, 'opaque-block');
          final presenting = aggregate.barState as LiveStatusPresenting;
          expect(presenting.surface, isA<LiveStatusNoticeOnlySurface>());
          expect(presenting.surface.standaloneNotices, hasLength(1));
        }
      },
    );
  }

  for (final (label, hasUnfinishedMembers) in [
    ('idle', false),
    ('unfinished', true),
  ]) {
    test('normal notice requires complete continuing open Work: $label', () {
      final live = CurrentRunSnapshot(
        currentWorkId: 'work',
        revision: 4,
        layoutRevision: 4,
        readyFrontier: 0,
        executionPresent: true,
        blocks: [
          LiveDisplayBlock(
            id: 'work',
            blockOrder: 1,
            state: DisplayBlockState.open,
            source: const ForegroundTurnChatSource(turnId: 'turn'),
            hasUnfinishedMembers: hasUnfinishedMembers,
            body: WorkDisplayBlock(
              timing: WorkTiming(startedAt: 0, finishedAt: null),
              members: const DisplayBlockRef(databaseId: 'db', blockId: 'work'),
            ),
          ),
        ],
      );
      for (final kind in [
        ThreadActivityKind.preparing,
        ThreadActivityKind.waitingApi,
        ThreadActivityKind.thinking,
        ThreadActivityKind.runningTool,
        ThreadActivityKind.planning,
      ]) {
        final status = ThreadActivityView(
          threadId: 'thread',
          identity: 'notice',
          revision: 1,
          turnId: 'turn',
          kind: kind,
          summary: '真实 Turn 活动',
        );
        final notice = ExecutionLiveNotice(
          LiveStatusProjection.mapThreadActivity(status),
        );
        final placement = LiveStatusProjection.mergeableWorkNotice(
          live: live,
          notices: [notice],
        );
        final aggregate = _observe(live: live, status: status);
        final presenting = aggregate.barState as LiveStatusPresenting;
        expect(placement, isNotNull, reason: kind.name);
        expect(presenting.effectiveWindow, same(live));
        expect(presenting.surface, isA<LiveStatusWorkSurface>());
        expect(placement!.notice, same(notice));
        expect(presenting.surface.standaloneNotices, isEmpty);
      }
    });
  }

  test('realtime projection preserves the actual thinking phase timing', () {
    final aggregate = _observe(
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
    );
    final presenting = aggregate.barState as LiveStatusPresenting;
    final view = presenting.surface.standaloneNotices
        .whereType<ExecutionLiveNotice>()
        .single
        .view;
    expect(view.thinkingSummary, '核对实时呈现与创建时间');
    expect(view.thinkingSeconds, 17);
  });

  test('closing Work and successor text remain ordered and storage/stop notices coexist', () {
    final live = CurrentRunSnapshot(
      currentWorkId: null,
      revision: 4,
      layoutRevision: 4,
      readyFrontier: 3,
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
            visibility: HistorySingleVisibility.content,
            record: DisplayRecord(
              atom: completionEntry('text', 5, text: '正文').atom,
              contentSource: const CurrentAtomSource(),
            ),
          ),
        ),
      ],
    );
    final projected = _observe(
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
    );
    expect(projected.timelineWork.effectiveWindow, same(live));
    expect(projected.timelineWork.workBlocks.map((b) => b.id), ['work']);
    final presenting = projected.barState as LiveStatusPresenting;
    expect(presenting.effectiveWindow, same(live));
    expect(presenting.surface, isA<LiveStatusStreamingSurface>());
    expect(presenting.surface.blocks.map((block) => block.id), ['text']);
    expect(
      presenting.surface.standaloneNotices.whereType<ExecutionLiveNotice>().map(
        (notice) => notice.view.kind,
      ),
      [
        ConversationActivityKind.stopping,
        ConversationActivityKind.storageBlocked,
      ],
    );
  });

  test(
    'cold all-terminal tail rests; only unfinished cold content is Unrestored',
    () {
      final coldWorkWindow = CurrentRunSnapshot(
        currentWorkId: 'work',
        revision: 4,
        layoutRevision: 4,
        readyFrontier: 3,
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
      final coldWork = _observe(
        live: coldWorkWindow,
        interaction: null,
        storage: null,
        status: _status,
      );
      expect(coldWork.primaryActivity, isNull);
      expect(coldWork.timelineWork.workBlocks, isEmpty);
      final resting = (coldWork.barState as LiveStatusPresenting).surface;
      expect((resting as LiveStatusWorkSurface).workBlock.id, 'work');
      expect(resting.mergedActivity, isNull);
      expect(resting.standaloneNotices, isEmpty);

      final coldSingleWindow = CurrentRunSnapshot(
        currentWorkId: null,
        revision: 5,
        layoutRevision: 5,
        readyFrontier: 3,
        executionPresent: false,
        blocks: [
          LiveDisplayBlock(
            id: 'work',
            blockOrder: 1,
            state: DisplayBlockState.sealed,
            body: coldWorkWindow.blocks.single.body,
          ),
          LiveDisplayBlock(
            id: 'cold-text',
            blockOrder: 2,
            state: DisplayBlockState.open,
            body: SingleDisplayBlock(
              visibility: HistorySingleVisibility.content,
              record: DisplayRecord(
                atom: ChatAtom(
                  id: 'cold-text',
                  source: const ForegroundTurnChatSource(turnId: 'turn'),
                  sourceOrder: 1,
                  kind: ChatAtomKind.text,
                  delivery: ChatDeliveryKind.foreground,
                  lifecycle: const ActiveChatAtom(
                    started: null,
                    status: ChatActiveStatus.running,
                  ),
                  contents: const [],
                ),
                contentSource: const CurrentAtomSource(),
              ),
            ),
          ),
        ],
      );
      final coldSingle = _observe(
        live: coldSingleWindow,
        interaction: null,
        storage: null,
        status: _status,
      );
      final presenting = coldSingle.barState as LiveStatusPresenting;
      expect(presenting.effectiveWindow, same(coldSingleWindow));
      expect(
        presenting.surface.standaloneNotices.single,
        isA<UnrestoredLiveNotice>(),
      );
    },
  );

  test('idle history-only region hides without suppressing the final historical block', () {
    expect(
      _observe(
        live: null,
        interaction: null,
        storage: null,
        status: null,
      ).barState,
      isA<LiveStatusHidden>(),
    );
  });
  test('Plan confirmation masks live bar while preserving activity and work observation', () {
    final work = LiveDisplayBlock(
      id: 'background-work',
      blockOrder: 1,
      state: DisplayBlockState.open,
      source: const ForegroundTurnChatSource(turnId: 'background-turn'),
      body: WorkDisplayBlock(
        timing: displayTiming(),
        members: const DisplayBlockRef(
          databaseId: 'plan-mask',
          blockId: 'background-work',
        ),
      ),
    );
    final live = CurrentRunSnapshot(
      currentWorkId: 'background-work',
      revision: 1,
      layoutRevision: 1,
      readyFrontier: 0,
      executionPresent: true,
      blocks: [work],
    );
    final state = _observe(
      live: live,
      interaction: _userInput(
        id: 'plan',
        questionId: agentSessionPlanConfirmationQuestionId,
      ),
    );

    expect(state.barState, isA<LiveStatusDockMasked>());
    expect((state.barState as LiveStatusDockMasked).interactionId, 'plan');
    expect(state.primaryActivity?.kind, ConversationActivityKind.thinking);
    expect(state.timelineWork.workBlocks, isEmpty);
    final masked = state.barState as LiveStatusDockMasked;
    expect(
      (masked.obscured!.surface as LiveStatusWorkSurface).workBlock,
      same(work),
    );

    final restored = LiveStatusProjection.project(
      threadId: 'thread',
      observation: LiveStatusInputs(
        cut: state.cut,
        interactions: const [],
        activeTurnId: 'turn',
        activity: _status,
        latestLive: live,
      ),
      outputPaging: const LatestLiveWindow(),
      timelineWorkPaging: const LatestLiveWindow(),
    );
    expect(restored.barState, isA<LiveStatusPresenting>());
  });

  for (final turnId in ['turn', 'other-turn']) {
    test(
      'pending plan masks input-wait from $turnId while retaining driver source',
      () {
        final aggregate = _observe(
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
        expect(aggregate.barState, isA<LiveStatusDockMasked>());
        expect(aggregate.barState.showInteractionDetails, isFalse);
        if (turnId != 'turn') {
          expect(aggregate.primaryActivity?.turnId, turnId);
        }
      },
    );
  }

  test('ordinary questions suppress duplicate status text and preserve unfinished operations', () {
    final state = _project(
      _userInput(id: 'question', questionId: 'ordinary-question'),
    );

    expect(state.barState, isA<LiveStatusDockMasked>());
    expect((state.barState as LiveStatusDockMasked).interactionId, 'question');
  });

  test('resolved interaction retains the real activity observation', () {
    final state = _project(null);
    final content = state.barState as LiveStatusPresenting;

    expect(content.effectiveWindow, same(_live));
    expect(
      content.surface.standaloneNotices
          .whereType<ExecutionLiveNotice>()
          .single
          .view
          .kind,
      ConversationActivityKind.thinking,
    );
  });

  test('tool approval keeps the existing activity projection', () {
    final state = _project(_toolApproval());
    final content = state.barState as LiveStatusPresenting;

    expect(content.effectiveWindow, same(_live));
    expect(
      content.surface.standaloneNotices.whereType<ExecutionLiveNotice>().map(
        (notice) => notice.view.kind,
      ),
      [
        ConversationActivityKind.thinking,
        ConversationActivityKind.awaitingApproval,
      ],
    );
  });

  test('pure projection uses local pagination without replacing the canonical current Work', () {
    final first = _observe(live: _live);
    final repeat = _observe(live: _live);
    expect(repeat.barState, first.barState);
    expect(repeat.primaryActivity, first.primaryActivity);
  });
}
