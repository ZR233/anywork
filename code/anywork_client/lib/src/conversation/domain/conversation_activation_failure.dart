import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';

part 'conversation_activation_failure.freezed.dart';

/// A selected demand failed before it obtained a concrete Session borrow.
@Freezed(toStringOverride: false)
abstract class ConversationActivationFailure with _$ConversationActivationFailure {
  const factory ConversationActivationFailure({
    required String threadId,
    required int selectionGeneration,
    required StudioFailure error,
  }) = _ConversationActivationFailure;
}
