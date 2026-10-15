import 'package:anywork_client/models.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_workspace_view.freezed.dart';

enum AgentComposerMode { editable, runtimeDriven }

@freezed
abstract class AgentWorkspaceView with _$AgentWorkspaceView {
  const AgentWorkspaceView._();

  const factory AgentWorkspaceView({
    required StudioThread thread,
    required StudioThread rootThread,
    required AgentWorkspaceSyncState syncState,
    String? loadError,
    required List<TimelineRow> timelineRows,
    required TimelineTodoListUpdate? todo,
    required ThreadRuntimeView runtime,
    required StudioTurnView? turn,
    StudioTurnView? lastTurn,
    required PendingInteraction? activeInteraction,
    required ComposerThreadState composer,
    required AgentComposerMode composerMode,
    required List<ProviderSettingsView> providers,
    @Default(<ModeModelRouteView>[]) List<ModeModelRouteView> modeModelRoutes,
    required List<RoleSettingsView> roles,
    required List<StudioAgentView> agents,
  }) = _AgentWorkspaceView;

  String get threadId => thread.id;

  bool get isRoot => thread.isRoot;

  bool get isLoading =>
      syncState == AgentWorkspaceSyncState.loading ||
      syncState == AgentWorkspaceSyncState.reconnecting;

  bool get isBusy => turn?.state.isBusy ?? false;
}
