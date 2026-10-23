import 'package:freezed_annotation/freezed_annotation.dart';

part 'thread_content_fields.freezed.dart';

@Freezed(toStringOverride: false)
sealed class ThreadContentFieldView with _$ThreadContentFieldView {
  const factory ThreadContentFieldView.text() = ThreadTextFieldView;
  const factory ThreadContentFieldView.thinkingSummary(int chunkIndex) = ThreadThinkingSummaryFieldView;
  const factory ThreadContentFieldView.thinkingContent(int chunkIndex) = ThreadThinkingContentFieldView;
  const factory ThreadContentFieldView.toolArguments() = ThreadToolArgumentsFieldView;
  const factory ThreadContentFieldView.toolResult() = ThreadToolResultFieldView;
  const factory ThreadContentFieldView.toolOutputArtifacts() = ThreadToolOutputArtifactsFieldView;
  const factory ThreadContentFieldView.rawPayload(int payloadIndex) = ThreadRawPayloadFieldView;
  const factory ThreadContentFieldView.toolUserInput({required int questionIndex,
    required ThreadUserInputFieldPartView part}) = ThreadToolUserInputFieldView;
}

@Freezed(toStringOverride: false)
sealed class ThreadUserInputFieldPartView with _$ThreadUserInputFieldPartView {
  const factory ThreadUserInputFieldPartView.header() = ThreadUserInputHeaderFieldPartView;
  const factory ThreadUserInputFieldPartView.question() = ThreadUserInputQuestionFieldPartView;
  const factory ThreadUserInputFieldPartView.answer(int answerIndex) = ThreadUserInputAnswerFieldPartView;
  const factory ThreadUserInputFieldPartView.optionLabel(int optionIndex) = ThreadUserInputOptionLabelFieldPartView;
  const factory ThreadUserInputFieldPartView.optionDescription(int optionIndex) = ThreadUserInputOptionDescriptionFieldPartView;
}

@Freezed(toStringOverride: false)
sealed class ThreadFieldChangeView with _$ThreadFieldChangeView {
  const factory ThreadFieldChangeView.unchanged() = UnchangedThreadFieldChangeView;
  const factory ThreadFieldChangeView.append(String text) = AppendThreadFieldChangeView;
  const factory ThreadFieldChangeView.replace(String text) = ReplaceThreadFieldChangeView;
  const factory ThreadFieldChangeView.remove() = RemoveThreadFieldChangeView;
}

@Freezed(toStringOverride: false)
abstract class ThreadFieldUpdateView with _$ThreadFieldUpdateView {
  const factory ThreadFieldUpdateView({required ThreadContentFieldView field,
    required ThreadFieldChangeView change}) = _ThreadFieldUpdateView;
}

/// Explicitly opaque native JSON, not a Dart JSON tree or a known-DTO decoder.
@Freezed(toStringOverride: false)
abstract class OpaqueArtifactJson with _$OpaqueArtifactJson {
  const factory OpaqueArtifactJson({required String json}) = _OpaqueArtifactJson;
}
