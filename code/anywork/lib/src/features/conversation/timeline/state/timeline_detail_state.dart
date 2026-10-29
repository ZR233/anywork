import 'package:freezed_annotation/freezed_annotation.dart';

part 'timeline_detail_state.freezed.dart';

@freezed
abstract class TimelineDetailState with _$TimelineDetailState {
  const factory TimelineDetailState({
    @Default('') String text,
    @Default(false) bool loading,
    @Default(false) bool complete,
    @Default(false) bool terminal,
    Object? error,
  }) = _TimelineDetailState;
}
