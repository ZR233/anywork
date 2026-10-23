import 'package:freezed_annotation/freezed_annotation.dart';

part 'editor_keys.freezed.dart';

@freezed
sealed class ComposerKey with _$ComposerKey {
  const factory ComposerKey.start({required String projectId}) = StartComposerKey;
  const factory ComposerKey.thread({required String threadId}) = ThreadComposerKey;
}

@freezed
abstract class InteractionEditorKey with _$InteractionEditorKey {
  const factory InteractionEditorKey({
    required String threadId,
    required int incarnation,
    required String interactionId,
    required int revision,
  }) = _InteractionEditorKey;
}
