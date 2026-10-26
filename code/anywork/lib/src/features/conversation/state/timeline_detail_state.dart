import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'timeline_detail_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class TimelineDetailKey with _$TimelineDetailKey {
  const factory TimelineDetailKey({
    required String threadId,
    required int displayGeneration,
    required String itemId,
    required ThreadContentFieldView field,
    required int revision,
  }) = _TimelineDetailKey;
}

@Freezed(toStringOverride: false)
abstract class TimelineDetailViewState with _$TimelineDetailViewState {
  const factory TimelineDetailViewState({
    required TimelineDetailKey key,
    @Default('') String text,
    @Default(0) int loadedBytes,
    int? totalBytes,
    String? continuation,
    @Default(false) bool loading,
    @Default(false) bool complete,
    @Default(false) bool closing,
    StudioFailure? error,
  }) = _TimelineDetailViewState;
}
