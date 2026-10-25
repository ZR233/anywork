import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_options_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class SessionOptionsState with _$SessionOptionsState {
  const SessionOptionsState._();
  const factory SessionOptionsState({
    @Default(0) int intent,
    @Default(false) bool waiting,
    OperationState? operation,
    StudioFailure? error,
    String? explanation,
  }) = _SessionOptionsState;

  bool get pending => waiting || operation?.isPending == true;
}
