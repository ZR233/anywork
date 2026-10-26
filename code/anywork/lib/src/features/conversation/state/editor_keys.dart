import 'package:anywork_client/conversation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'editor_keys.freezed.dart';

@freezed
sealed class ComposerKey with _$ComposerKey {
  const factory ComposerKey.start({required String projectId}) =
      StartComposerKey;
  const factory ComposerKey.thread({required String threadId}) =
      ThreadComposerKey;
}

@freezed
abstract class InteractionEditorKey with _$InteractionEditorKey {
  const InteractionEditorKey._();
  const factory InteractionEditorKey({
    /// The Session owning the bounded interaction index, not the target child.
    required String threadId,
    required String runtimeEpoch,
    required int incarnation,
    required int sourceGeneration,
    required String interactionId,
    required int revision,
    String? targetThreadId,
    InteractionReadRef? hostedReference,
    ThreadFacetStamp? hostedOrigin,
  }) = _InteractionEditorKey;

  String get target => targetThreadId ?? threadId;
  bool get isHosted => target != threadId;
}
