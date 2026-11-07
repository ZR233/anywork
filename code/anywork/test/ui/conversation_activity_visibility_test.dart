import 'package:anywork/src/features/conversation/timeline/view_models/conversation_activity_view_model.dart';
import 'package:anywork/src/features/conversation/timeline/state/conversation_activity_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

CurrentProjection _current() => CurrentProjection(
  sourceEffectSeq: 1,
  logicalStatus: ThreadStatusView.running,
  executionPresent: true,
  active: const CurrentActivityHead(
    id: 'activity',
    kind: ThreadActivityKind.thinking,
    summary: '思考中',
    toolCount: 0,
    backgroundToolCount: 0,
  ),
  sources: const [],
  items: const [],
  atoms: const [],
  previews: const [],
  collections: const [],
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

ConversationActivityState? _project(List<PendingInteraction> interactions) =>
    projectConversationActivityState(
      current: _current(),
      storage: null,
      interactions: interactions,
    );

void main() {
  test('plan confirmation hides the entire status bar while current remains present', () {
    final state = _project([
      _userInput(
        id: 'plan',
        questionId: agentSessionPlanConfirmationQuestionId,
      ),
    ]);

    expect(state, isNull);
  });

  test('ordinary user questions also hide current activity until resolved', () {
    final state = _project([
      _userInput(id: 'question', questionId: 'ordinary-question'),
    ]);

    expect(state, isNull);
  });

  test('resolved interaction restores the real current activity', () {
    final state = _project(const []);

    expect(state, isNotNull);
    expect(state!.current, isNotNull);
    expect(state.view.kind, ConversationActivityKind.thinking);
  });

  test('tool approval keeps the existing activity projection', () {
    final state = _project([
      _userInput(id: 'question', questionId: 'ordinary-question'),
      _toolApproval(),
    ]);

    expect(state, isNotNull);
    expect(state!.current, isNotNull);
    expect(state.view.kind, ConversationActivityKind.thinking);
  });
}
