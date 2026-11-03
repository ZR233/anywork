import 'package:anywork_client/models.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_workspace_view.freezed.dart';

enum AgentComposerMode { editable, runtimeDriven }

@freezed
abstract class AgentWorkspaceView with _$AgentWorkspaceView {
  const AgentWorkspaceView._();

  const factory AgentWorkspaceView({
    required SessionDirectoryRow row,
    required SessionDirectoryRow rootRow,
    required AgentWorkspaceSyncState syncState,
    String? loadError,
    required TimelineTodoListUpdate? todo,
    required ThreadRuntimeView runtime,
    ThreadModelRouteView? modelRoute,
    required StudioTurnView? turn,
    StudioTurnView? lastTurn,
    required PendingInteraction? activeInteraction,
    required ComposerThreadState composer,
    required AgentComposerMode composerMode,
    required List<ModelSelectionAccount> accounts,
    @Default(<ModeModelRouteView>[]) List<ModeModelRouteView> modeModelRoutes,
    required List<RoleSettingsView> roles,
    required List<StudioAgentView> agents,
  }) = _AgentWorkspaceView;

  String get threadId => row.threadId;

  /// root/child 只读目录行 `parentAgentId`（issue #280）。
  bool get isRoot => row.isRootRow;

  bool get isLoading =>
      syncState == AgentWorkspaceSyncState.loading ||
      syncState == AgentWorkspaceSyncState.reconnecting;

  bool get isBusy => turn?.state.isBusy ?? false;
}
