import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'startup_view_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class StartupViewState with _$StartupViewState {
  const factory StartupViewState({
    required StartupState startup,
    required bool retryPending,
    required StudioFailure? bootstrapError,
    required StartupRecovery? recovery,
    required bool recoveryDismissed,
    required bool recoveryLoading,
    required StudioFailure? recoveryError,
    required StartupActiveTurnPage? activeTurns,
    required bool activeTurnsLoading,
    required StudioFailure? activeTurnsError,
  }) = _StartupViewState;
}
