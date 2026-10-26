import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'release_notes_state.freezed.dart';

/// Local platform-launch presentation, not an update/download state machine.
@Freezed(toStringOverride: false)
abstract class ReleaseNotesState with _$ReleaseNotesState {
  const factory ReleaseNotesState({
    @Default(false) bool opening,
    StudioFailure? error,
  }) = _ReleaseNotesState;
}
