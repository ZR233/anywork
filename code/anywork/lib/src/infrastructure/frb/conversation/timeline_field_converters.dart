import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/types/chat.dart' as native;

ThreadContentFieldView contentFieldFromBridge(native.BridgeContentField value) => switch (value) {
  native.BridgeContentField_Text() => const ThreadContentFieldView.text(),
  native.BridgeContentField_ThinkingSummary(:final chunkIndex) => ThreadContentFieldView.thinkingSummary(chunkIndex),
  native.BridgeContentField_ThinkingContent(:final chunkIndex) => ThreadContentFieldView.thinkingContent(chunkIndex),
  native.BridgeContentField_ToolArguments() => const ThreadContentFieldView.toolArguments(),
  native.BridgeContentField_ToolResult() => const ThreadContentFieldView.toolResult(),
  native.BridgeContentField_ToolOutputArtifacts() => const ThreadContentFieldView.toolOutputArtifacts(),
  native.BridgeContentField_RawPayload(:final payloadIndex) => ThreadContentFieldView.rawPayload(payloadIndex),
  native.BridgeContentField_ToolUserInput(:final questionIndex, :final part_) => ThreadContentFieldView.toolUserInput(
    questionIndex: questionIndex, part: switch (part_) {
      native.BridgeThreadUserInputFieldPart_Header() => const ThreadUserInputFieldPartView.header(),
      native.BridgeThreadUserInputFieldPart_Question() => const ThreadUserInputFieldPartView.question(),
      native.BridgeThreadUserInputFieldPart_Answer(:final answerIndex) => ThreadUserInputFieldPartView.answer(answerIndex),
      native.BridgeThreadUserInputFieldPart_OptionLabel(:final optionIndex) => ThreadUserInputFieldPartView.optionLabel(optionIndex),
      native.BridgeThreadUserInputFieldPart_OptionDescription(:final optionIndex) => ThreadUserInputFieldPartView.optionDescription(optionIndex),
    },
  ),
};

native.BridgeContentField contentFieldToBridge(ThreadContentFieldView value) => switch (value) {
  ThreadTextFieldView() => const native.BridgeContentField.text(),
  ThreadThinkingSummaryFieldView(:final chunkIndex) => native.BridgeContentField.thinkingSummary(chunkIndex: _index(chunkIndex)),
  ThreadThinkingContentFieldView(:final chunkIndex) => native.BridgeContentField.thinkingContent(chunkIndex: _index(chunkIndex)),
  ThreadToolArgumentsFieldView() => const native.BridgeContentField.toolArguments(),
  ThreadToolResultFieldView() => const native.BridgeContentField.toolResult(),
  ThreadToolOutputArtifactsFieldView() => const native.BridgeContentField.toolOutputArtifacts(),
  ThreadRawPayloadFieldView(:final payloadIndex) => native.BridgeContentField.rawPayload(payloadIndex: _index(payloadIndex)),
  ThreadToolUserInputFieldView(:final questionIndex, :final part) => native.BridgeContentField.toolUserInput(
    questionIndex: _index(questionIndex), part_: switch (part) {
      ThreadUserInputHeaderFieldPartView() => const native.BridgeThreadUserInputFieldPart.header(),
      ThreadUserInputQuestionFieldPartView() => const native.BridgeThreadUserInputFieldPart.question(),
      ThreadUserInputAnswerFieldPartView(:final answerIndex) => native.BridgeThreadUserInputFieldPart.answer(answerIndex: _index(answerIndex)),
      ThreadUserInputOptionLabelFieldPartView(:final optionIndex) => native.BridgeThreadUserInputFieldPart.optionLabel(optionIndex: _index(optionIndex)),
      ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex) => native.BridgeThreadUserInputFieldPart.optionDescription(optionIndex: _index(optionIndex)),
    },
  ),
};

int _index(int value) {
  if (value < 0 || value > 0xffffffff) {
    throw const StudioFailure(code: StudioFailureCode.invalidArgument,
      message: 'A content field index is outside the native range',
      retryable: false, correlationId: 'adapter-content-field-index');
  }
  return value;
}
