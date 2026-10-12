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

Widget _agentWorkspacePreview(StudioState state) {
  return _AgentWorkspacePreviewScope(
    key: ValueKey(
      'agent-workspace-preview-${state.selectedThreadId}-'
      '${state.selectedAgentWorkspace?.syncState.name}',
    ),
    previewState: state,
  );
}

class _AgentWorkspacePreviewScope extends StatefulWidget {
  const _AgentWorkspacePreviewScope({super.key, required this.previewState});

  final StudioState previewState;

  @override
  State<_AgentWorkspacePreviewScope> createState() =>
      _AgentWorkspacePreviewScopeState();
}

class _AgentWorkspacePreviewScopeState
    extends State<_AgentWorkspacePreviewScope> {
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderContainer(
      overrides: [
        shellComposerWorkspaceProvider.overrideWith(
          (ref) => widget.previewState.selectedAgentWorkspace,
        ),
        shellSelectionProvider.overrideWith(
          (ref) => SelectionStoreState(
            selectedProjectId: widget.previewState.selectedProjectId,
            selectedThreadId: widget.previewState.selectedThreadId,
          ),
        ),
        timelineSessionWindowProvider.overrideWith(
          (ref) => _previewTimelineWindow(widget.previewState),
        ),
        startPageComposerViewProvider.overrideWith(
          (ref) => _previewStartPage(widget.previewState),
        ),
        composerDockViewProvider.overrideWith(
          (ref, threadId) =>
              _previewComposerDock(widget.previewState, threadId),
        ),
        threadCommandsProvider.overrideWith(_PreviewThreadCommands.new),
        statusBarViewProvider.overrideWith((ref) {
          final workspace = widget.previewState.selectedAgentWorkspace;
          if (workspace == null) return null;
          return StatusBarView.fromWorkspace(workspace);
        }),
        conversationActivityInputProvider.overrideWith((ref, threadId) {
          final workspace = widget.previewState.workspacesByThread[threadId];
          if (workspace == null) return null;
          final interaction = widget.previewState.activeInteraction;
          return ConversationActivityInput(
            activity: workspace.activity,
            storage: workspace.storage,
            interaction: interaction != null && interaction.threadId == threadId
                ? interaction
                : null,
          );
        }),
      ],
    );
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: _container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: pureStudioTheme(),
        themeMode: ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AgentWorkspacePane()),
      ),
    );
  }
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
  final item = ThreadItemView(
    id: '${selected.id}-item',
    threadId: selected.id,
    turnId: '${selected.id}-turn',
    ordinal: 0,
    revision: 0,
    createdAt: timestamp,
    updatedAt: timestamp,
    state: ThreadTextItemStateView(
      channel: ThreadTextChannel.finalAnswer,
      text: selectChild
          ? 'Reviewer is checking the workspace boundary.'
          : 'Main agent owns this root workspace and its editable composer.',
      attachments: const [],
      lifecycle: CompletedThreadContentView(timestamp),
    ),
  );
  final runtime = ThreadRuntimeView(
    model: selectChild ? 'reviewer/model' : 'planner/model',
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
          providers: [
            ProviderSettingsView(
              id: 'preview-provider',
              name: 'Preview Provider',
              baseUrl: '',
              defaultModel: 'planner/model',
              models: [
                ProviderModelView(
                  slug: 'planner/model',
                  displayName: 'Main agent model',
                  reasoningEfforts: ['high'],
                  wireProtocol: 'responses',
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
              providerId: 'preview-provider',
              model: 'planner/model',
              effort: 'high',
            ),
            RoleSettingsView(
              key: 'executor',
              providerId: 'preview-provider',
              model: 'planner/model',
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
    providerUsageState: ProviderUsageStateSnapshot.fromState(
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
              thread: selected,
              revision: 1,
              items: [item],
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

/// 预览只喂静态窗口，避免 timelineSessionWindow 按真实选择建流。
TimelineSessionWindow? _previewTimelineWindow(StudioState state) {
  final workspace = state.selectedAgentWorkspace;
  if (workspace == null) return null;
  return TimelineSessionWindow(
    threadId: workspace.threadId,
    rows: workspace.timelineRows,
    turn: workspace.turn,
    history: const ThreadHistoryWindow(),
    isLoadingOlder: false,
    isLoadingNewer: false,
  );
}

StartPageComposerProjection _previewStartPage(StudioState state) {
  final project = state.projects
      .where((item) => item.id == state.selectedProjectId)
      .firstOrNull;
  return StartPageComposerProjection(
    project: project,
    providers: state.providers,
    modeModelRoutes: state.modeModelRoutes,
    permissionMode: state.permissionMode,
    settingsLoaded: true,
    canSubmit: false,
    commands: const <String, CommandStatus>{},
    diagnostics: const [],
    modeCatalog: null,
    sessionDraft: const StartSessionDraft(),
    composer: const ComposerThreadState.idle(),
    targetDiagnostic: null,
  );
}

/// 时间线首帧会派发锚点与正文补齐。覆盖命令 lane，避免预览因此附着会话流。
class _PreviewThreadCommands extends ThreadCommands {
  @override
  ThreadCommandBoard build() => const ThreadCommandBoard();

  @override
  Future<void> loadOlderHistory(String threadId) async {}

  @override
  Future<void> loadNewerHistory(String threadId) async {}

  @override
  Future<void> loadLatestHistory(String threadId) async {}

  @override
  Future<void> extendLatestHistory(String threadId) async {}

  @override
  Future<void> jumpToLatest(String threadId) async {}

  @override
  Future<void> updateTimelineAnchor(
    String threadId,
    TimelineAnchor anchor,
  ) async {}

  @override
  Future<void> ensureItemBodies(
    String threadId,
    Iterable<String> itemIds,
  ) async {}

  @override
  Future<void> loadItemBody(String threadId, String itemId) async {}
}

/// ComposerDock 会 watch 这个 family；不覆盖就会附着 threadSessionStore 并拉起 Bridge。
ComposerDockView _previewComposerDock(StudioState state, String threadId) {
  final selected = state.selectedAgentWorkspace;
  final workspace = selected?.threadId == threadId ? selected : null;
  final thread =
      workspace?.thread ??
      state.threads.where((item) => item.id == threadId).firstOrNull;
  return ComposerDockView(
    thread: thread,
    hasSnapshot: state.workspacesByThread.containsKey(threadId),
    revision: state.workspacesByThread[threadId]?.revision ?? 0,
    composer: workspace?.composer ?? const ComposerThreadState.idle(),
    activeInteraction: workspace?.activeInteraction,
    turn: workspace?.turn,
    modelRoute: workspace?.runtime.modelRoute,
    routePending: false,
    routeFailure: null,
    workflow: null,
    permissionMode: workspace?.permissionMode ?? state.permissionMode,
    providers: workspace?.providers ?? state.providers,
    settingsLoaded: true,
    requiresFunctionCalling: false,
    targetDiagnostic: null,
    additionalDiagnostics: const [],
  );
}
