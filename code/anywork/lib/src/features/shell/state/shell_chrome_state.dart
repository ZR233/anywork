import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'shell_chrome_state.freezed.dart';

/// Presentation of read-only borrows. No Session, query or observation handle
/// crosses this boundary; Workspace remains the only selection owner.
@Freezed(toStringOverride: false)
abstract class ShellChromeState with _$ShellChromeState {
  const ShellChromeState._();

  const factory ShellChromeState({
    required WorkspaceState workspace,
    String? activeThreadId,
    String? rootThreadId,
    ProjectRecord? project,
    WorkspaceThreadRecord? root,
    @Default(false) bool projectCurrent,
    @Default(false) bool rootCurrent,
    @Default(false) bool directoryCurrent,
    @Default(false) bool configurationCurrent,
    @Default([]) List<AgentDirectoryEntry> agents,
    ReadValue<DelegationSettings, ConfigurationReadRef>? delegationDefaults,
    SessionCostsState? costs,
    @Default({}) Set<String> reading,
    @Default({}) Map<String, StudioFailure> failures,
  }) = _ShellChromeState;

  DelegationSettings? get defaultDelegation => switch (delegationDefaults) {
    ReadyReadValue(:final current) => current.value,
    LoadingReadValue(:final previous) ||
    FailedReadValue(:final previous) => previous?.value,
    _ => null,
  };

  SessionCost? get sessionCost => switch (costs?.cost) {
    ReadyReadValue(:final current) => current.value,
    LoadingReadValue(:final previous) ||
    FailedReadValue(:final previous) => previous?.value,
    _ => null,
  };
}

/// The Bots feature supplies this read-only navigation presentation. An absent
/// supplier is explicitly Unknown, never an empty/healthy bot configuration.
@Freezed(toStringOverride: false)
abstract class ShellBotsEntry with _$ShellBotsEntry {
  const factory ShellBotsEntry({
    @Default(false) bool current,
    String? summary,
    StudioFailure? failure,
  }) = _ShellBotsEntry;
}
