import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'timeline_view_state.freezed.dart';

enum TimelineDisplayMode { live, history }

@Freezed(toStringOverride: false)
abstract class TimelineViewState with _$TimelineViewState {
  const factory TimelineViewState({
    required String threadId,
    @Default(0) int generation,
    @Default(TimelineDisplayMode.live) TimelineDisplayMode displayMode,
    @Default(TimelineConnectionPhase.idle)
    TimelineConnectionPhase connectionPhase,
    StudioFailure? connectionError,
    String? olderCursor,
    @Default(false) bool hasOlder,
    @Default(false) bool olderLoading,
    StudioFailure? olderError,
    @Default(false) bool hasNewOutput,
    @Default(false) bool preparingLive,
    @Default(false) bool ready,
  }) = _TimelineViewState;
}
