import 'package:anywork/src/features/conversation/timeline/view_models/conversation_activity_view_model.dart';
import 'package:anywork/src/features/conversation/timeline/state/conversation_activity_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _status = ThreadActivityView(
  threadId: 'thread',
  identity: 'activity',
  revision: 1,
  turnId: 'turn',
  kind: ThreadActivityKind.thinking,
  summary: '思考中',
);
final _activity = ActivitySnapshot(
  revision: 1,
  completedThrough: 0,
  executionPresent: true,
  entries: const [],
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
      status: _status,
      activity: _activity,
      storage: null,
      interactions: interactions,
    );

void main() {
  test('Plan confirmation uses its State controls without hiding the actual activity snapshot', () {
    final state = _project([
      _userInput(
        id: 'plan',
        questionId: agentSessionPlanConfirmationQuestionId,
      ),
    ]);

    expect(state?.view, isNull);
    expect(state?.activity, same(_activity));
  });

  test('ordinary questions suppress duplicate status text and preserve unfinished operations', () {
    final state = _project([
      _userInput(id: 'question', questionId: 'ordinary-question'),
    ]);

    expect(state?.view, isNull);
    expect(state?.activity, same(_activity));
  });

  test('resolved interaction retains the real activity observation', () {
    final state = _project(const []);

    expect(state, isNotNull);
    expect(state!.activity, isNotNull);
    expect(state.view!.kind, ConversationActivityKind.thinking);
  });

  test('tool approval keeps the existing activity projection', () {
    final state = _project([
      _userInput(id: 'question', questionId: 'ordinary-question'),
      _toolApproval(),
    ]);

    expect(state, isNotNull);
    expect(state!.activity, isNotNull);
    expect(state.view!.kind, ConversationActivityKind.thinking);
  });
}
