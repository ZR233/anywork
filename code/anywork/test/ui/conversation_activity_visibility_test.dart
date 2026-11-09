import 'package:anywork/src/features/conversation/timeline/state/conversation_realtime_presentation.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/display_fixtures.dart';
import '../support/completion_fixtures.dart';

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
}) => PendingInteraction(
  id: id,
  threadId: 'thread',
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

PendingInteraction _toolApproval() => const PendingInteraction(
  id: 'approval',
  threadId: 'thread',
  turnId: 'turn',
  kind: InteractionKind.toolApproval,
  title: '工具审批',
  body: '允许执行工具',
  payload: ToolApprovalInteractionPayload(
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

void main() {
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
          closing: true,
          body: displayWork('work', 4).body,
        ),
        LiveDisplayBlock(
          id: 'text',
          blockOrder: 2,
          closing: false,
          body: SingleDisplayBlock(
            atom: completionEntry('text', 5, text: '正文').atom,
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
          closing: false,
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
  test('Plan confirmation uses its State controls without hiding the actual activity snapshot', () {
    final state = _project(
      _userInput(
        id: 'plan',
        questionId: agentSessionPlanConfirmationQuestionId,
      ),
    );

    expect(state, isA<DockRealtimeRegion>());
    expect((state as DockRealtimeRegion).interactionId, 'plan');
  });

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
