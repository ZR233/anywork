import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'workspace_header_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class WorkspaceHeaderState with _$WorkspaceHeaderState {
  const factory WorkspaceHeaderState({
    required ThreadMetadataState root,
    required AgentDirectoryState agents,
    AgentDirectoryState? lastReadyAgents,
    required SessionCostsState costs,
    required Set<String> reading,
    required Map<String, StudioFailure> readErrors,
  }) = _WorkspaceHeaderState;
}
