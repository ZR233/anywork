part of 'studio_shell.dart';

@Preview(
  name: 'Root workspace',
  group: 'Agent Workspace',
  size: Size(1280, 800),
  brightness: Brightness.light,
)
Widget agentWorkspaceRootPreview() {
  return _agentWorkspacePreview(_agentWorkspacePreviewState());
}

@Preview(
  name: 'Child workspace',
  group: 'Agent Workspace',
  size: Size(1280, 800),
  brightness: Brightness.light,
)
Widget agentWorkspaceChildPreview() {
  return _agentWorkspacePreview(_agentWorkspacePreviewState(selectChild: true));
}

@Preview(
  name: 'Child workspace loading',
  group: 'Agent Workspace',
  size: Size(1280, 800),
  brightness: Brightness.light,
)
Widget agentWorkspaceLoadingPreview() {
  return _agentWorkspacePreview(
    _agentWorkspacePreviewState(selectChild: true, childLoading: true),
  );
}

/// Development previews render immutable props and never attach a Client owner.
Widget _agentWorkspacePreview(StudioState state) {
  final workspace = state.selectedAgentWorkspace;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: pureStudioTheme(),
    themeMode: ThemeMode.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => Theme(
      data: pureStudioTheme(locale: Localizations.localeOf(context)),
      child: child ?? const SizedBox(),
    ),
    home: Scaffold(
      body:
          workspace == null ||
              workspace.syncState == AgentWorkspaceSyncState.loading
          ? const Center(child: CircularProgressIndicator())
          : TimelinePreview(threadId: workspace.threadId),
    ),
  );
}

StudioState _agentWorkspacePreviewState({
  bool selectChild = false,
  bool childLoading = false,
}) {
  const project = StudioProject(
    id: 'preview-project',
    name: 'Agent Workspace Preview',
    path: '.',
  );
  final timestamp = DateTime.fromMillisecondsSinceEpoch(1000);
  final root = StudioThread(
    id: 'preview-root',
    projectId: project.id,
    title: 'Main agent workspace',
    mode: ThreadModeId.task,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    createdAt: timestamp,
    updatedAt: timestamp,
    rootThreadId: 'preview-root',
    role: 'planner',
    workspacePath: project.path,
  );
  final child = StudioThread(
    id: 'preview-child',
    projectId: project.id,
    title: 'Reviewer workspace',
    mode: ThreadModeId.task,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    createdAt: timestamp.add(const Duration(seconds: 1)),
    updatedAt: timestamp.add(const Duration(seconds: 1)),
    parentThreadId: root.id,
    rootThreadId: root.id,
    agentPath: 'preview-reviewer',
    role: 'reviewer',
    status: ThreadStatusView.running,
    workspacePath: project.path,
  );
  final selected = selectChild ? child : root;
  final runtime = ThreadRuntimeView(
    modelId: selectChild ? 'reviewer/model' : 'planner/model',
    contextTokens: selectChild ? 4800 : 12800,
    contextWindow: 128000,
    totalTokens: selectChild ? 7200 : 19200,
    costLabel: selectChild ? '￥0.05' : '￥0.16',
    activeSkills: selectChild ? const ['review-skill'] : const ['planning'],
    activeMcpServers: const ['dart'],
    activeLspServers: const ['rust-analyzer'],
  );
  return StudioState(
    projectDirectory: ProjectDirectoryState.fromState(
      state: ReadyObservedResource(
        revision: 1,
        updatedAt: timestamp.millisecondsSinceEpoch ~/ 1000,
        lastCheckedAt: null,
        value: const [project],
      ),
    ),
    threadDirectory: ThreadDirectoryWindow(threads: [root, child]),
    agentDirectory: AgentDirectoryState.fromState(
      state: UninitializedObservedResource(
        updatedAt: timestamp.millisecondsSinceEpoch ~/ 1000,
      ),
    ),
    settingsState: SettingsStateSnapshot.fromState(
      state: ReadyObservedResource(
        revision: 1,
        updatedAt: timestamp.millisecondsSinceEpoch ~/ 1000,
        lastCheckedAt: null,
        value: const SettingsStateData(
          accounts: [
            AccountSettingsView(
              id: 'preview-account',
              templateId: 'openai',
              protocol: 'open_ai',
              name: 'Preview Account',
              baseUrl: '',
              defaultModelId: 'planner/model',
              models: [
                AccountModelView(
                  modelId: 'planner/model',
                  displayName: 'Main agent model',
                  reasoningEfforts: ['high'],
                  wireApi: 'responses',
                  supportedConnectionModes: ['web_socket', 'http'],
                  defaultConnectionMode: 'web_socket',
                  connectionMode: 'web_socket',
                ),
              ],
              status: 'ready',
              usageLabel: '',
            ),
          ],
          roles: [
            RoleSettingsView(
              key: 'planner',
              accountId: 'preview-account',
              modelId: 'planner/model',
              effort: 'high',
            ),
            RoleSettingsView(
              key: 'executor',
              accountId: 'preview-account',
              modelId: 'planner/model',
              effort: 'high',
            ),
          ],
          permissionMode: PermissionMode.requestApproval,
        ),
      ),
    ),
    recoveryState: RecoveryStateSnapshot.fromState(
      state: UninitializedObservedResource(
        updatedAt: timestamp.millisecondsSinceEpoch ~/ 1000,
      ),
    ),
    mcpState: McpStateSnapshot.fromState(
      state: UninitializedObservedResource(
        updatedAt: timestamp.millisecondsSinceEpoch ~/ 1000,
      ),
    ),
    lspState: LspStateSnapshot.fromState(
      state: UninitializedObservedResource(
        updatedAt: timestamp.millisecondsSinceEpoch ~/ 1000,
      ),
    ),
    skillsByProject: const {},
    accountUsageState: AccountUsageStateSnapshot.fromState(
      state: UninitializedObservedResource(
        updatedAt: timestamp.millisecondsSinceEpoch ~/ 1000,
      ),
    ),
    updaterState: UpdaterStateSnapshot.idle(
      revision: 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
    workspacesByThread: childLoading
        ? const {}
        : {
            selected.id: ThreadWorkspace(
              audience: const ThreadAudienceUnavailable(
                reason: ThreadAudienceUnavailableReason.ownershipUnproven,
              ),
              thread: selected,
              revision: 1,
              interactions: const [],
              runtime: runtime,
              activeTurn: !selectChild
                  ? null
                  : StudioTurnView(
                      turnId: '${selected.id}-turn',
                      threadId: selected.id,
                      revision: 1,
                      state: RunningStudioTurnState(
                        startedAt: timestamp.millisecondsSinceEpoch ~/ 1000,
                        activity: StudioTurnActivity.responding,
                      ),
                      updatedAt: timestamp,
                    ),
              todo: const TimelineTodoListUpdate(
                callId: 'preview-todo',
                explanation: 'Workspace checklist',
                items: [
                  TimelineTodoItem(
                    step: 'Keep every panel on one Thread',
                    status: 'inProgress',
                  ),
                ],
              ),
            ),
          },
    workspaceUiByThread: {
      selected.id: WorkspaceUiState(
        syncState: childLoading
            ? AgentWorkspaceSyncState.loading
            : AgentWorkspaceSyncState.ready,
        composer: selectChild
            ? const ComposerThreadState.idle()
            : const ComposerThreadState.idle(
                draft: 'Refine the implementation plan',
              ),
      ),
    },
    selectedProjectId: project.id,
    selectedThreadId: selected.id,
  );
}
