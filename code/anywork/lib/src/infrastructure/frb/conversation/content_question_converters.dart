import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/types/thread_stream/item.dart' as native;
import '../shared/adapter_failure.dart';

ThreadToolUserInputView contentQuestionsFromBridge(native.BridgeThreadUserInput value) => ThreadToolUserInputView(
  interactionId: value.interactionId,
  questions: List.unmodifiable([
    for (final question in value.questions) UserQuestionView(
      id: question.id, header: question.header, question: question.question,
      isOther: question.isOther, isSecret: question.isSecret,
      options: List.unmodifiable([
        for (final option in question.options) UserQuestionOptionView(label: option.label, description: option.description),
      ]),
    ),
  ]),
  state: switch (value.state) {
    native.BridgeThreadUserInputState_Pending() => const ThreadToolUserInputStateView.pending(),
    native.BridgeThreadUserInputState_Cancelled() => const ThreadToolUserInputStateView.cancelled(),
    native.BridgeThreadUserInputState_Resolved(:final answers) => ThreadToolUserInputStateView.resolved(
      List.unmodifiable(answers.map(_answer)),
    ),
  },
);

ThreadUserInputAnswerView _answer(native.BridgeThreadUserInputAnswer value) {
  if (value.redacted && value.answers.isNotEmpty) {
    // Reject a malformed public projection without echoing private answers.
    throw adapterProtocol('redacted-public-answer');
  }
  return ThreadUserInputAnswerView(
    questionId: value.questionId,
    answers: List.unmodifiable(value.answers),
    redacted: value.redacted,
  );
}
