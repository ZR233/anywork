import 'package:anywork_client/studio_client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'conversation_realtime_presentation.dart';

export 'conversation_realtime_presentation.dart';
part 'conversation_activity_state.freezed.dart';

/// The activity component's read-only projection. This value owns no reader,
/// subscription or copy of the timeline's completed messages.
@freezed
abstract class ConversationActivityState with _$ConversationActivityState {
  const factory ConversationActivityState({
    required ConversationActivityView? view,
    required ConversationRealtimeRegion region,
  }) = _ConversationActivityState;
}
