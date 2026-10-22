part of 'studio_api.dart';

const WorkflowDefinition _demoTaskWorkflow = WorkflowDefinition(
  title: '任务流程',
  goal: '完成任务并交付可验证结果',
  initialStateId: 'implement',
  states: [
    WorkflowState(
      id: 'implement',
      title: '实现',
      instructions: '完成用户请求并验证结果。',
      completionCriteria: ['实现完成', '验证通过'],
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowState(
      id: 'done',
      title: '完成',
      instructions: '汇总结果并结束任务。',
      completionCriteria: ['结果已交付'],
      kind: WorkflowStateKind.finalState,
    ),
  ],
  transitions: [
    WorkflowTransition(
      sourceStateId: 'implement',
      targetStateId: 'done',
      guard: '实现完成且验证通过',
    ),
  ],
);

class DemoStudioTransport extends StudioTransport
    implements PersistenceQueueReader {
  @override
  Future<RecoveryStateSnapshot> retryRecovery() async => _demoRecoveryState();

  DemoStudioTransport({
    this.lspActivityLoop = false,
    this._accountCatalog = demoAccountCatalogFixture,
  });

  /// 目录分页窗口的页大小；Driver 模式填充大量历史会话以验收触底加载。
  static const int directoryPageSize = 20;

  final AccountCatalogView _accountCatalog;

  /// 是否周期推进 demo LSP 索引活动；GUI demo 构建开启，测试默认关闭保持确定性。
  final bool lspActivityLoop;

  /// 每 topic 的 typed fanout 接收者：receiver 先登记其 sink，再取得该 topic 基线；
  /// 无关领域不进入该 receiver 的缓冲。发布只走已登记 sink，不做全局 mixed bus。
  final Map<ProductTopic, Set<void Function(ProductTopicEventPayload)>>
  _topicSinks = {};
  final String _ownerEpoch = 'demo:${newStudioCorrelationId()}';
  int _productEventSequence = 0;
  int _threadDirectoryRevision = 0;
  int _agentProfilesRevision = 0;
  final _threadEvents = StreamController<ThreadStreamFrame>.broadcast();
  final _shutdownEvents = StreamController<StudioShutdownProgress>.broadcast();

  /// 内容变更信号：条目变化时唤醒在途的 `next()`，正文只经内容连接交付。
  final Map<String, int> _chatChangeSeq = {};
  final Map<String, List<Completer<void>>> _chatWaiters = {};

  /// 每个 Thread 的内存条目：正文不属于 Thread 状态，只由内容连接按页/尾部交付。
  final Map<String, List<ThreadItemView>> _threadItems = {};

  /// 每个 Thread 自己的内容版本；与 Thread 状态 revision、持久化水位无关。
  final Map<String, int> _contentVersions = {};
  Timer? _lspActivityTimer;
  final Map<String, ThreadWorkspace> _workspaces = {};
  final Map<String, int> _promptGenerations = {};
  final Map<String, ThreadModeId> _threadModes = {};
  int _threadModeCatalogRevision = 1;
  final Set<String> _readOnlyModeIds = {'mode.simple', 'mode.task'};
  final Map<String, ModeDocument> _modeDocuments = {
    'mode.simple': const ModeDocument(
      definition: ModeDefinition(
        id: 'mode.simple',
        displayName: '简洁',
        description: '直接对话',
        order: 0,
        prompt: '直接回答用户请求。',
      ),
    ),
    'mode.task': const ModeDocument(
      definition: ModeDefinition(
        id: 'mode.task',
        displayName: '任务',
        description: '通过工作流完成任务',
        order: 1,
        prompt: '按工作流推进任务并确认阶段完成。',
        workflow: _demoTaskWorkflow,
      ),
    ),
  };
  final Map<String, AttachmentDraftView> _attachmentDrafts = {};
  final Set<String> _archivedProjectIds = {};
  final Map<String, String> _projectNames = {};
  final Set<String> _archivedThreadIds = {};
  final Map<String, ({PendingInteraction interaction, Object resolution})>
  _resolvedInteractions = {};
  final List<StudioThread> _createdRootThreads = [];
  final List<StudioThread> _pageFillThreads = [];
  final List<SshServer> _sshServers = [
    const SshServer(
      alias: 'arm-dev',
      hostName: '192.168.100.12',
      port: 22,
      username: 'root',
      managed: true,
    ),
    const SshServer(
      alias: 'handwritten',
      hostName: '203.0.113.10',
      port: 2222,
      username: 'deploy',
      managed: false,
    ),
  ];

  /// Driver 模式注入的历史会话数量；普通 demo 为 0。
  int get directoryPageFillCount => 0;

  List<AccountSettingsView>? _accounts;
  String? _defaultAccountId;
  List<ModeModelRouteView>? _modeRoutes;
  List<RoleSettingsView>? _roles;
  InstructionsSettingsView _instructions = const InstructionsSettingsView();
  SkillsSettingsView _skills = const SkillsSettingsView();
  GeneralSettingsView _general = const GeneralSettingsView();
  WebSearchSettingsView _webSearch = const WebSearchSettingsView(
    effectiveMode: 'disabled',
    availability: 'available',
    accountId: 'openai',
    modelId: 'gpt-5',
  );
  DeepSeekWebSearchSettingsView _deepSeekWebSearch =
      const DeepSeekWebSearchSettingsView(
        effectiveEnabled: true,
        configuredFetchEnabled: true,
        effectiveFetchEnabled: true,
        availability: 'available',
        accountId: 'deepseek-primary',
      );
  PermissionMode _permissionMode = PermissionMode.requestApproval;
  int _turnSequence = 0;
  int _threadSequence = 0;
  int _settingsRevision = 1;
  int _attachmentSequence = 0;
  int _skillsRevision = 1;
  int _accountUsageRevision = 1;
  final Map<String, AccountUsageView> _accountUsages = {};
  List<AcpAccountSettingsView> _acpAccounts = const [];
  final DemoAcpAuth _demoAcpAuth = DemoAcpAuth();
  int _mcpRevision = 0;
  int _lspRevision = 0;
  int? _lspActivityPercentage = 40;
  int _projectDirectoryRevision = 1;
  final Set<String> _disabledSystemAgents = <String>{};
  final Map<String, AgentProfileView> _userAgentProfiles = {};
  final List<StudioProject> _openedRemoteProjects = [];
  String? _selectedProjectId;
  String? _selectedThreadId;
  DateTime? _fixtureNow;
  int _botsRevision = 0;
  final List<BotSnapshot> _bots = [];
  BotRegistrationAttempt? _registration;
  final List<BotPendingCredentialOperation> _pendingCredentialOps = [];
  final Map<String, List<BotConversation>> _botConversations = {};
  final Map<String, List<BotMessage>> _botMessages = {};
  final Map<String, BotConversationThreadBinding> _botBindings = {};

  Duration get promptStartDelay => const Duration(milliseconds: 120);

  Duration get promptActivityDelay => const Duration(milliseconds: 350);

  Duration get promptToolDelay => const Duration(milliseconds: 500);

  /// 模拟关机每个阶段的停留时长。
  Duration get shutdownPhaseDelay => const Duration(milliseconds: 80);

  /// demo LSP 索引活动每个步进的停留时长。
  Duration get lspActivityStepDelay => const Duration(seconds: 2);

  @override
  Stream<StudioShutdownProgress> subscribeShutdownProgress() {
    return _shutdownEvents.stream;
  }

  @override
  Future<void> beginRuntimeExit({required int remainingMs}) async {
    // demo 无 native runtime owner：与 public StudioTransport 契约一致，早期封闭是无副作用的
    // no-op。真正的早期封闭由 FrbStudioTransport 调 native `begin_runtime_exit`；这里不声称任何
    // raw demo 结果验证过 Rust。
  }

  @override
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    List<StudioShutdownIssue> externalIssues = const [],
    StudioExitIntent intent = StudioExitIntent.exit,
  }) async {
    for (final phase in StudioShutdownPhase.values) {
      if (shutdownPhaseDelay > Duration.zero) {
        await Future<void>.delayed(shutdownPhaseDelay);
      }
      if (phase == StudioShutdownPhase.flushingPersistence) {
        _emitShutdownProgress(
          const FlushingPersistenceProgress(pendingCommits: 3),
        );
        if (shutdownPhaseDelay > Duration.zero) {
          await Future<void>.delayed(shutdownPhaseDelay);
        }
        _emitShutdownProgress(
          const FlushingPersistenceProgress(pendingCommits: 0),
        );
        continue;
      }
      _emitShutdownProgress(_demoShutdownProgress(phase));
    }
    await _shutdownEvents.close();
    // Demo 的确定性结局：所有阶段成功且持久化已排空。外部（Dart）取消 issue 是本次关闭
    // 的最终成功前置条件，只要存在就如实为 Degraded，绝不伪 Clean。
    if (externalIssues.isEmpty) {
      return const StudioExitReport(
        shutdown: StudioShutdownReport(
          outcome: StudioShutdownOutcome.clean,
          issues: [],
          persistence: DrainedStudioPendingPersistence(),
        ),
      );
    }
    return StudioExitReport(
      shutdown: StudioShutdownReport(
        outcome: StudioShutdownOutcome.degraded,
        issues: externalIssues,
        persistence: const DrainedStudioPendingPersistence(),
      ),
    );
  }

  void _emitShutdownProgress(StudioShutdownProgress progress) {
    _shutdownEvents.add(progress);
  }

  StudioShutdownProgress _demoShutdownProgress(StudioShutdownPhase phase) {
    return switch (phase) {
      StudioShutdownPhase.stoppingSubscriptions =>
        const StoppingSubscriptionsProgress(),
      StudioShutdownPhase.cancellingTurns => const CancellingTurnsProgress(),
      StudioShutdownPhase.flushingPersistence =>
        const FlushingPersistenceProgress(pendingCommits: 0),
      StudioShutdownPhase.stoppingAgents => const StoppingAgentsProgress(),
      StudioShutdownPhase.stoppingMcp => const StoppingMcpProgress(),
      StudioShutdownPhase.stoppingLsp => const StoppingLspProgress(),
      StudioShutdownPhase.stopped => const StoppedProgress(),
    };
  }

  @override
  Future<StudioBootstrap> readBootstrap() async {
    // Bootstrap only assembles independently versioned owner snapshots. Normal
    // commands and topic baselines query their own domain directly.
    final projects = _demoProjectDirectory();
    final threads = _demoThreadDirectory();
    final selectedProjectId =
        projects.values
            .where((project) => project.id == _selectedProjectId)
            .firstOrNull
            ?.id ??
        projects.values.firstOrNull?.id;
    final selectedThreadId = _sortedDirectoryThreads()
        .where(
          (thread) =>
              thread.id == _selectedThreadId &&
              thread.projectId == selectedProjectId,
        )
        .firstOrNull
        ?.id;
    return StudioBootstrap(
      ownerEpoch: _ownerEpoch,
      projectDirectory: projects,
      threadDirectory: threads,
      agentDirectory: _demoAgentDirectory(),
      settingsState: _demoSettingsState(),
      recoveryState: _demoRecoveryState(),
      mcpState: _demoMcpState(),
      lspState: _demoLspState(),
      skillsByProject: {
        for (final project in projects.values)
          project.id: _demoSkillsState(project.id, _skillsRevision),
      },
      threadModeCatalog: _demoThreadModeCatalog(),
      accountUsageState: _demoAccountUsageState(),
      modelPerformance: _demoModelPerformance(_fixtureTime),
      updaterState: _demoUpdaterState(),
      persistenceState: _demoPersistenceState(),
      persistenceQueueState: _demoPersistenceQueueState(),
      agentProfilesState: readAgentProfilesStateSync(),
      sessionCostsByRoot: {
        for (final root in _sortedDirectoryThreads().where(
          (thread) => thread.isRoot,
        ))
          root.id: _demoSessionCosts(root.id),
      },
      selectedProjectId: selectedProjectId,
      selectedThreadId: selectedThreadId,
    );
  }

  DateTime get _fixtureTime => _fixtureNow ??= DateTime.now();

  ThreadModeCatalogView _demoThreadModeCatalog() {
    final documents = _modeDocuments.values.toList()
      ..sort((left, right) {
        final byOrder = left.definition.order.compareTo(right.definition.order);
        return byOrder != 0
            ? byOrder
            : left.definition.id.compareTo(right.definition.id);
      });
    return ThreadModeCatalogView(
      revision: _threadModeCatalogRevision,
      modes: [
        for (final document in documents)
          ThreadModeDescriptorView(
            id: document.definition.id,
            displayName: document.definition.displayName,
            description: document.definition.description,
            order: document.definition.order,
            hasWorkflow: document.definition.workflow != null,
            readOnly: _readOnlyModeIds.contains(document.definition.id),
          ),
      ],
    );
  }

  ProjectDirectoryState _demoProjectDirectory() {
    final fixture = _ensureWorkspaceFixture();
    final projects = [fixture.project, ..._openedRemoteProjects]
        .where((project) => !_archivedProjectIds.contains(project.id))
        .map(
          (project) => StudioProject(
            id: project.id,
            name: _projectNames[project.id] ?? project.name,
            path: project.path,
            sshAlias: project.sshAlias,
          ),
        )
        .toList();
    return ProjectDirectoryState.fromState(
      state: _demoReadyResource(_projectDirectoryRevision, projects),
    );
  }

  ThreadDirectoryWindow _demoThreadDirectory() {
    final directory = _sortedDirectoryThreads();
    return ThreadDirectoryWindow(
      threads: directory.take(directoryPageSize).toList(),
      nextCursor: directory.length > directoryPageSize
          ? _demoDirectoryCursor(directoryPageSize - 1)
          : null,
      hasMore: directory.length > directoryPageSize,
      revision: _threadDirectoryRevision,
    );
  }

  ThreadDirectoryPage _demoDirectoryPage() {
    final window = _demoThreadDirectory();
    return ThreadDirectoryPage(
      threads: window.threads,
      nextCursor: window.nextCursor,
      revision: window.revision,
    );
  }

  AgentDirectoryState _demoAgentDirectory() =>
      AgentDirectoryState.fromState(state: _demoInitialResource());

  RecoveryStateSnapshot _demoRecoveryState() =>
      RecoveryStateSnapshot.fromState(state: _demoInitialResource());

  AccountSettingsView _demoDefaultAccount() {
    final template = _accountCatalog.templates.first;
    return template
        .createAccount(
          template.id,
          _accountCatalog.modelsFor(template.modelCatalogId),
        )
        .copyWith(hasBearerToken: true, status: 'ready', updatedAt: 'Loaded');
  }

  SettingsStateSnapshot _demoSettingsState() {
    final defaultAccount = _demoDefaultAccount();
    final defaultModel = defaultAccount.models
        .where((model) => model.modelId == defaultAccount.defaultModelId)
        .firstOrNull;
    final effort = defaultModel?.defaultReasoningEffort;
    final resolvedEffort = effort?.isNotEmpty == true
        ? effort!
        : defaultModel?.reasoningEfforts.firstOrNull ?? '';
    return _settingsSnapshot(
      accounts: _accounts ?? [defaultAccount],
      modeRoutes:
          _modeRoutes ??
          [
            for (final mode in [ThreadModeId.simple, ThreadModeId.task])
              ModeModelRouteView(
                modeId: mode,
                accountId: defaultAccount.id,
                modelId: defaultAccount.defaultModelId,
                effort: resolvedEffort,
              ),
          ],
      roles:
          _roles ??
          [
            for (final role in const [
              'explorer',
              'executor',
              'worktree_executor',
              'reviewer',
            ])
              RoleSettingsView(
                key: role,
                accountId: defaultAccount.id,
                modelId: defaultAccount.defaultModelId,
                effort: resolvedEffort,
              ),
          ],
    );
  }

  AccountUsageStateSnapshot _demoAccountUsageState() {
    final accounts = _accounts ?? [_demoDefaultAccount()];
    final usages = [
      for (final account in accounts)
        _accountUsages[account.id] ?? _demoAccountUsage(account),
    ];
    return AccountUsageStateSnapshot.fromState(
      state: _demoReadyResource(
        _accountUsageRevision,
        AccountUsageStateData(configFingerprint: 'demo', usages: usages),
      ),
    );
  }

  SessionCostsStateView _demoSessionCosts(String rootThreadId) =>
      SessionCostsStateView(
        rootThreadId: rootThreadId,
        revision: rootThreadId == 'thread-main' || rootThreadId == 'thread-alt'
            ? 1
            : 0,
        updatedAt: _fixtureTime,
        cost: switch (rootThreadId) {
          'thread-main' => const SessionCostView(
            rootThreadId: 'thread-main',
            estimatedCosts: [
              RuntimeCostView(currency: 'CNY', amount: 0.14),
              RuntimeCostView(currency: 'USD', amount: 0.02),
            ],
            hasUnpricedUsage: false,
          ),
          'thread-alt' => const SessionCostView(
            rootThreadId: 'thread-alt',
            estimatedCosts: [],
            hasUnpricedUsage: true,
          ),
          _ => null,
        },
      );

  UpdaterStateSnapshot _demoUpdaterState() => UpdaterStateSnapshot.idle(
    revision: 0,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  PersistenceStateSnapshot _demoPersistenceState() =>
      const PersistenceStateSnapshot.ready();

  PersistenceQueueStateView _demoPersistenceQueueState() =>
      const PersistenceQueueStateView(
        revision: 0,
        queue: PersistenceQueueSnapshot.empty(),
      );

  ThreadWorkspace _demoWorkspace(String threadId) {
    _ensureWorkspaceFixture();
    final workspace = _workspaces[threadId];
    if (workspace == null) throw StateError('unknown demo thread $threadId');
    return workspace;
  }

  SettingsStateSnapshot _settingsSnapshot({
    required List<AccountSettingsView> accounts,
    required List<ModeModelRouteView> modeRoutes,
    required List<RoleSettingsView> roles,
  }) {
    return SettingsStateSnapshot.fromState(
      state: _demoReadyResource(
        _settingsRevision,
        SettingsStateData(
          accounts: accounts,
          acpAccounts: _acpAccounts,
          defaultAccountId: _defaultAccountId ?? accounts.firstOrNull?.id,
          modeModelRoutes: modeRoutes,
          roles: roles,
          instructions: _instructions,
          skills: _skills,
          general: _general,
          webSearch: _webSearch,
          deepSeekWebSearch: _deepSeekWebSearch,
          permissionMode: _permissionMode,
        ),
      ),
    );
  }

  ModeModelRouteView _demoModeRoute(ThreadModeId mode) {
    final saved =
        _modeRoutes?.where((route) => route.modeId == mode).firstOrNull ??
        _modeRoutes
            ?.where((route) => route.modeId == ThreadModeId.simple)
            .firstOrNull;
    if (saved != null) return saved;
    final template = _accountCatalog.templates.first;
    final models = _accountCatalog.modelsFor(template.modelCatalogId);
    final model =
        models
            .where(
              (candidate) => candidate.modelId == template.suggestedModelId,
            )
            .firstOrNull ??
        models.first;
    return ModeModelRouteView(
      modeId: mode,
      accountId: template.id,
      modelId: model.modelId,
      effort: model.defaultReasoningEffort.isNotEmpty
          ? model.defaultReasoningEffort
          : model.reasoningEfforts.firstOrNull ?? '',
    );
  }

  ModelPerformanceSnapshotView _demoModelPerformance(DateTime now) {
    // 顶层身份是 (accountId, 配置 modelId)；同一账号模型的强度细分留在组内。
    const deepseek = ModelPerformanceSummaryView(
      accountId: 'deepseek-primary',
      accountDisplayName: 'DeepSeek',
      modelId: 'deepseek-flash',
      sampleCount: 2,
      completionTokens: 300,
      totalTtftMillis: 760,
      ttftSampleCount: 2,
      totalResponseMillis: 2760,
      tokensPerSecond: 300 * 1000 / 2760,
      averageTtftMillis: 380,
      averageResponseMillis: 1380,
      effortBreakdowns: [
        ModelPerformanceEffortSummaryView(
          effort: 'high',
          sampleCount: 1,
          completionTokens: 150,
          totalTtftMillis: 410,
          ttftSampleCount: 1,
          totalResponseMillis: 1410,
          tokensPerSecond: 150 * 1000 / 1410,
          averageTtftMillis: 410,
          averageResponseMillis: 1410,
        ),
        ModelPerformanceEffortSummaryView(
          effort: 'none',
          sampleCount: 1,
          completionTokens: 150,
          totalTtftMillis: 350,
          ttftSampleCount: 1,
          totalResponseMillis: 1350,
          tokensPerSecond: 150 * 1000 / 1350,
          averageTtftMillis: 350,
          averageResponseMillis: 1350,
        ),
      ],
    );
    const openai = ModelPerformanceSummaryView(
      accountId: 'openai-work',
      accountDisplayName: 'OpenAI Work',
      modelId: 'gpt-5.6-codex',
      sampleCount: 1,
      completionTokens: 216,
      totalTtftMillis: 620,
      ttftSampleCount: 1,
      totalResponseMillis: 3120,
      tokensPerSecond: 216 * 1000 / 3120,
      averageTtftMillis: 620,
      averageResponseMillis: 3120,
      effortBreakdowns: [
        ModelPerformanceEffortSummaryView(
          effort: null,
          sampleCount: 1,
          completionTokens: 216,
          totalTtftMillis: 620,
          ttftSampleCount: 1,
          totalResponseMillis: 3120,
          tokensPerSecond: 216 * 1000 / 3120,
          averageTtftMillis: 620,
          averageResponseMillis: 3120,
        ),
      ],
    );
    return ModelPerformanceSnapshotView(
      revision: 3,
      updatedAt: now,
      summaries: const [deepseek, openai],
      history: [
        ModelPerformanceSampleView(
          completedAt: now.subtract(const Duration(seconds: 12)),
          accountId: openai.accountId,
          accountDisplayName: openai.accountDisplayName,
          modelId: openai.modelId,
          sentModel: openai.modelId,
          reportedModel: openai.modelId,
          modelMatchState: ModelMatchState.matched,
          completionTokens: 216,
          ttftMillis: 620,
          decodeMillis: 2500,
          totalResponseMillis: 3120,
          tokensPerSecond: 216 * 1000 / 3120,
        ),
        ModelPerformanceSampleView(
          completedAt: now.subtract(const Duration(seconds: 34)),
          accountId: deepseek.accountId,
          accountDisplayName: deepseek.accountDisplayName,
          modelId: deepseek.modelId,
          sentModel: 'deepseek-flash-0724',
          reportedModel: 'deepseek-flash',
          modelMatchState: ModelMatchState.mismatched,
          effort: 'high',
          completionTokens: 150,
          ttftMillis: 410,
          decodeMillis: 1000,
          totalResponseMillis: 1410,
          tokensPerSecond: 150 * 1000 / 1410,
        ),
        ModelPerformanceSampleView(
          completedAt: now.subtract(const Duration(minutes: 2)),
          accountId: deepseek.accountId,
          accountDisplayName: deepseek.accountDisplayName,
          modelId: deepseek.modelId,
          sentModel: deepseek.modelId,
          modelMatchState: ModelMatchState.unreported,
          effort: 'none',
          completionTokens: 150,
          ttftMillis: 350,
          decodeMillis: 1000,
          totalResponseMillis: 1350,
          tokensPerSecond: 150 * 1000 / 1350,
        ),
        // 旧记录没有配置模型证据：保持历史身份未知，不从当前目录补写。
        ModelPerformanceSampleView(
          completedAt: now.subtract(const Duration(minutes: 8)),
          accountId: 'legacy-account',
          accountDisplayName: 'Legacy account',
          sentModel: 'legacy-alias-model',
          modelMatchState: ModelMatchState.legacyUnknown,
          completionTokens: 90,
          ttftMillis: 500,
          decodeMillis: 900,
          totalResponseMillis: 1400,
          tokensPerSecond: 90 * 1000 / 1400,
        ),
      ],
    );
  }

  ({StudioProject project, List<StudioThread> threads})
  _ensureWorkspaceFixture() {
    final now = _fixtureNow ??= DateTime.now();
    const project = StudioProject(
      id: 'project-local',
      name: 'pure-lang',
      path: r'C:\Projects\pure-lang',
    );
    final rootMode = _threadModes['thread-main'] ?? ThreadModeId.simple;
    final reviewerMode = _threadModes['thread-reviewer'] ?? ThreadModeId.simple;
    final alternateMode = _threadModes['thread-alt'] ?? ThreadModeId.simple;
    final root = StudioThread(
      id: 'thread-main',
      projectId: project.id,
      title: 'Flutter + FRB 重构',
      mode: rootMode,
      role: 'planner',
      createdAt: now.subtract(const Duration(minutes: 10)),
      updatedAt: now,
      lastUserMessageAt: now,
      agentPath: 'root',
      workspacePath: project.path,
    );
    final reviewer = StudioThread(
      id: 'thread-reviewer',
      projectId: project.id,
      title: 'Driver reviewer',
      mode: reviewerMode,
      createdAt: now.subtract(const Duration(minutes: 7)),
      updatedAt: now.subtract(const Duration(minutes: 7)),
      parentThreadId: root.id,
      rootThreadId: root.id,
      agentPath: 'root/reviewer',
      role: 'reviewer',
      status: ThreadStatusView.waitingInteraction,
      workspacePath: project.path,
    );
    final alternate = StudioThread(
      id: 'thread-alt',
      projectId: project.id,
      title: 'Riverpod selector audit',
      mode: alternateMode,
      role: 'planner',
      createdAt: now.subtract(const Duration(minutes: 3)),
      updatedAt: now.subtract(const Duration(minutes: 3)),
      agentPath: 'root-alt',
      workspacePath: project.path,
    );
    _workspaces.putIfAbsent(root.id, () => _rootWorkspace(root, now));
    _workspaces.putIfAbsent(
      reviewer.id,
      () => _singleMessageWorkspace(
        reviewer,
        'Driver agent workspace selected.',
        'reviewer/model',
        now.subtract(const Duration(minutes: 6)),
      ),
    );
    _workspaces.putIfAbsent(
      alternate.id,
      () => _singleMessageWorkspace(
        alternate,
        'Riverpod selector boundary is isolated.',
        'future-model',
        now.subtract(const Duration(minutes: 2)),
      ),
    );
    _workspaces[root.id] = _workspaces[root.id]!.copyWith(thread: root);
    _workspaces[reviewer.id] = _workspaces[reviewer.id]!.copyWith(
      thread: reviewer,
    );
    _workspaces[alternate.id] = _workspaces[alternate.id]!.copyWith(
      thread: alternate,
    );
    final threads = [root, reviewer, alternate, ..._createdRootThreads]
        .where(
          (thread) =>
              !_archivedThreadIds.contains(thread.id) &&
              !_archivedThreadIds.contains(thread.effectiveRootThreadId),
        )
        .toList();
    for (final thread in _createdRootThreads) {
      _workspaces.putIfAbsent(
        thread.id,
        () => ThreadWorkspace(
          thread: thread,
          revision: 0,
          interactions: const [],
          runtime: _emptyRuntimeView(),
        ),
      );
    }
    _ensurePageFillThreads(project.id, project.path, now);
    return (project: project, threads: threads);
  }

  /// Driver 模式的历史会话填充：保证触底分页有足够数据。
  void _ensurePageFillThreads(
    String projectId,
    String projectPath,
    DateTime now,
  ) {
    if (directoryPageFillCount <= 0 || _pageFillThreads.isNotEmpty) {
      return;
    }
    for (var index = 0; index < directoryPageFillCount; index++) {
      final updated = now.subtract(Duration(minutes: 30 + index * 17));
      final thread = StudioThread(
        id: 'thread-page-$index',
        projectId: projectId,
        title: '历史会话 ${index + 1}',
        mode: ThreadModeId.simple,
        role: 'planner',
        createdAt: updated,
        updatedAt: updated,
        agentPath: 'root-page-$index',
        workspacePath: projectPath,
      );
      _pageFillThreads.add(thread);
      _workspaces.putIfAbsent(
        thread.id,
        () => ThreadWorkspace(
          thread: thread,
          revision: 0,
          interactions: const [],
          runtime: _emptyRuntimeView(),
        ),
      );
    }
  }

  /// 目录完整排序视图（最近用户消息时间倒序、id 倒序），分页窗口的模拟数据源。
  List<StudioThread> _sortedDirectoryThreads() {
    final fixture = _ensureWorkspaceFixture();
    final threads =
        [
              ...fixture.threads,
              ..._pageFillThreads.where(
                (thread) => !_archivedThreadIds.contains(thread.id),
              ),
            ]
            .where((thread) => !_archivedProjectIds.contains(thread.projectId))
            .toList()
          ..sort(StudioThread.compareDirectoryOrder);
    return threads;
  }

  @override
  Future<ThreadDirectoryPage> queryThreads(
    DirectoryQuery query, {
    String? cursor,
    int limit = 50,
  }) async {
    final projects = _demoProjectDirectory().values;
    final all = <String, StudioThread>{
      for (final thread in [
        ..._workspaces.values.map((w) => w.thread),
        ..._createdRootThreads,
        ..._pageFillThreads,
      ])
        thread.id: thread.copyWith(
          archived: _archivedThreadIds.contains(thread.effectiveRootThreadId),
        ),
    };
    final rows =
        all.values.where((thread) => query.matches(thread, projects)).toList()
          ..sort(StudioThread.compareDirectoryOrder);
    final offset = cursor == null ? 0 : int.parse(cursor);
    return ThreadDirectoryPage(
      threads: rows.skip(offset).take(limit).toList(),
      nextCursor: offset + limit < rows.length ? '${offset + limit}' : null,
      revision: _threadDirectoryRevision,
    );
  }

  @override
  Future<StudioThread> restoreThread(String threadId) async {
    _archivedThreadIds.remove(threadId);
    final restored = _sortedDirectoryThreads().firstWhere(
      (thread) => thread.id == threadId,
    );
    _emitThreadDirectoryUpdate(restored);
    return restored;
  }

  String _demoDirectoryCursor(int lastIndex) => 'demo:$lastIndex';

  @override
  Future<ThreadDirectoryPage> listThreadsPage({
    String? cursor,
    int limit = 50,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final directory = _sortedDirectoryThreads();
    final lastIndex = cursor == null
        ? -1
        : int.tryParse(cursor.replaceFirst('demo:', '')) ?? -1;
    final page = directory
        .skip(lastIndex + 1)
        .take(limit.clamp(1, 100))
        .toList();
    final nextLastIndex = lastIndex + page.length;
    return ThreadDirectoryPage(
      threads: page,
      nextCursor: nextLastIndex < directory.length - 1
          ? _demoDirectoryCursor(nextLastIndex)
          : null,
      revision: _threadDirectoryRevision,
    );
  }

  ThreadWorkspace _rootWorkspace(StudioThread thread, DateTime now) {
    final route = _demoModeRoute(thread.mode);
    final userCreatedAt = now.subtract(const Duration(minutes: 9));
    final agentCreatedAt = now.subtract(const Duration(minutes: 8));
    _threadItems[thread.id] = List.unmodifiable([
      _messageItem(
        id: 'turn-demo:user',
        threadId: thread.id,
        turnId: 'turn-demo',
        ordinal: 0,
        kind: ThreadItemKind.userMessage,
        text:
            '用 Flutter 重构 anywork。\n\n'
            '- timeline 要像 Web 版一样即时渲染 Markdown\n'
            '- streaming 中的代码块和表格不要抖动',
        createdAt: userCreatedAt,
      ),
      ThreadItemView(
        id: 'turn-demo:reasoning',
        threadId: thread.id,
        turnId: 'turn-demo',
        ordinal: 1,
        revision: 0,
        createdAt: agentCreatedAt,
        updatedAt: agentCreatedAt,
        state: ThreadThinkingItemStateView(
          summary: const ['## 判断\n\nUI 只消费当前 Thread 的高频通知。'],
          content: const [],
          lifecycle: CompletedThreadContentView(agentCreatedAt),
        ),
      ),
      ThreadItemView(
        id: 'turn-demo:tool',
        threadId: thread.id,
        turnId: 'turn-demo',
        ordinal: 2,
        revision: 0,
        createdAt: agentCreatedAt,
        updatedAt: agentCreatedAt,
        state: ThreadToolItemStateView(
          invocation: const ThreadToolInvocationView(
            toolCallId: 'turn-demo:tool-call',
            name: 'cargo test -p pl-studio-bridge',
            arguments: '',
          ),
          lifecycle: SucceededThreadToolView(
            agentCreatedAt,
            const ThreadToolOutputView(
              result: '1 passed; bridge envelope uses typed payload.',
              attachments: [],
              outputArtifacts: [],
            ),
          ),
        ),
      ),
      _messageItem(
        id: 'turn-demo:final',
        threadId: thread.id,
        turnId: 'turn-demo',
        ordinal: 4,
        kind: ThreadItemKind.agentMessage,
        channel: AgentMessageChannel.finalAnswer,
        text:
            '### Streaming Markdown preview\n\n'
            '正文、**加粗**、`inline code` 和链接都按 GFM 渲染。',
        createdAt: agentCreatedAt,
      ),
    ]);
    return ThreadWorkspace(
      thread: thread,
      revision: 1,
      interactions: const [],
      runtime: ThreadRuntimeView(
        modelId: 'planner/local-responses',
        modelRoute: ThreadModelRouteView(
          accountId: route.accountId,
          modelId: route.modelId,
          effort: route.effort,
          revision: 1,
          available: true,
        ),
        contextTokens: 18342,
        contextWindow: 96000,
        maxContextWindow: 128000,
        autoCompactLimit: 86400,
        totalTokens: 26320,
        promptTokens: 22160,
        completionTokens: 4160,
        cachedPromptTokens: 8860,
        cacheWriteTokens: 1240,
        reasoningTokens: 1520,
        inferenceCount: 6,
        cacheUsage: CacheUsageView(
          inputTokens: 22160,
          cacheReadTokens: 8860,
          hitRate: 0.4,
        ),
        estimatedCosts: [
          RuntimeCostView(currency: 'CNY', amount: 0.13),
          RuntimeCostView(currency: 'USD', amount: 0.02),
        ],
        estimatedCacheSavings: [RuntimeCostView(currency: 'CNY', amount: 0.05)],
        costLabel: '￥0.13 + \$0.02',
        activeSkills: ['flutter-apply-architecture-best-practices'],
        activeMcpServers: ['dart'],
        activeLspServers: ['rust-analyzer'],
        turnCompletionTokens: 150,
        turnResponseMillis: 1000,
      ),
    );
  }

  ThreadWorkspace _singleMessageWorkspace(
    StudioThread thread,
    String text,
    String modelId,
    DateTime createdAt,
  ) {
    _threadItems[thread.id] = List.unmodifiable([
      _messageItem(
        id: '${thread.id}:final',
        threadId: thread.id,
        turnId: '${thread.id}:turn',
        ordinal: 0,
        kind: ThreadItemKind.agentMessage,
        channel: AgentMessageChannel.finalAnswer,
        text: text,
        createdAt: createdAt,
      ),
    ]);
    return ThreadWorkspace(
      thread: thread,
      revision: 1,
      interactions: const [],
      runtime: ThreadRuntimeView(
        modelId: modelId,
        modelRoute: ThreadModelRouteView(
          accountId: _demoModeRoute(thread.mode).accountId,
          modelId: modelId,
          effort: null,
          revision: 1,
          available: true,
        ),
        contextTokens: 320,
        contextWindow: 128000,
        maxContextWindow: 128000,
        totalTokens: 512,
        estimatedCosts: const [RuntimeCostView(currency: 'CNY', amount: 0.01)],
        costLabel: '￥0.01',
        activeSkills: const [],
        activeMcpServers: const ['dart'],
        activeLspServers: const [],
        turnCompletionTokens: 216,
        turnResponseMillis: 2500,
      ),
    );
  }

  @override
  Future<AccountCatalogView> loadAccountCatalog() async => _accountCatalog;

  @override
  Future<AcpAccountCatalogView> loadAcpAccountCatalog() async =>
      demoAcpAccountCatalogFixture;

  AcpAccountSettingsView _demoAcpAccount(String accountId) {
    final account = _acpAccounts
        .where((candidate) => candidate.accountId == accountId)
        .firstOrNull;
    if (account == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'ACP account is unavailable: $accountId',
        retryable: false,
        correlationId: 'demo-acp',
      );
    }
    return account;
  }

  AcpAuthCommandReply _demoAcpReply(
    OperationId operationId,
    AcpAuthSnapshotView snapshot, {
    CommitDisposition disposition = CommitDisposition.applied,
  }) {
    _publishProductPayload(AcpAuthStateChangedPayload(snapshot));
    return AcpAuthCommandReply(
      receipt: _demoReceipt(
        operationId,
        changed: disposition == CommitDisposition.applied,
        targets: [_demoStamp('acp-auth', snapshot.revision)],
        effect: EffectPoint.immediate,
      ),
      snapshot: snapshot,
    );
  }

  @override
  Future<SettingsCommandReply> saveAcpAccount(
    int expectedSettingsRevision,
    AcpAccountUpdateView account, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    if (account.accountId.trim().isEmpty ||
        account.name.trim().isEmpty ||
        account.program.trim().isEmpty) {
      throw StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'ACP account requires an id, a name and a program',
        retryable: false,
        correlationId: 'demo-acp',
      );
    }
    final previous = _acpAccounts
        .where((candidate) => candidate.accountId == account.accountId)
        .firstOrNull;
    final identityChanged =
        previous == null ||
        previous.program != account.program ||
        previous.provider != account.provider ||
        !_sameDemoArgs(previous.args, account.args);
    final saved = AcpAccountSettingsView(
      accountId: account.accountId,
      name: account.name,
      provider: account.provider,
      program: account.program,
      args: account.args,
      connectionRevision: identityChanged
          ? (previous?.connectionRevision ?? 0) + 1
          : previous.connectionRevision,
    );
    _acpAccounts = [
      for (final candidate in _acpAccounts)
        if (candidate.accountId != saved.accountId) candidate,
      saved,
    ];
    _demoAcpAuth.retain(saved);
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> removeAcpAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    _acpAccounts = [
      for (final account in _acpAccounts)
        if (account.accountId != accountId) account,
    ];
    _demoAcpAuth.forget(accountId);
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<AcpAuthSnapshotView> readAcpAuthState() async => _demoAcpAuth.snapshot;

  @override
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  }) async {
    final account = _demoAcpAccount(accountId);
    if (account.connectionRevision != expectedConnectionRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'ACP connection identity changed for $accountId',
        retryable: false,
        correlationId: 'demo-acp',
      );
    }
    final snapshot = switch (action) {
      AcpCheckActionView() => _demoAcpAuth.check(account),
      AcpAuthenticateActionView(:final methodId) => _demoAcpAuth.authenticate(
        account,
        methodId,
      ),
    };
    return _demoAcpReply(operationId, snapshot);
  }

  @override
  Future<AcpAuthCommandReply> cancelAcpAuth({
    required OperationId operationId,
    required String accountId,
    required OperationId targetOperationId,
  }) async {
    final account = _demoAcpAccount(accountId);
    final snapshot = _demoAcpAuth.cancel(account, targetOperationId.value);
    return _demoAcpReply(operationId, snapshot);
  }

  @override
  Future<AgentProfilesStateView> readAgentProfilesState() async =>
      readAgentProfilesStateSync();

  @override
  Future<List<AgentProfileView>> readAgentProfiles() async =>
      _demoAgentProfilesSync();

  @override
  Future<SettingsCommandReply> setSystemAgentEnabled({
    required OperationId operationId,
    required int expectedSettingsRevision,
    required String profileId,
    required bool enabled,
  }) async {
    if (![
      'explorer',
      'executor',
      'worktree_executor',
      'reviewer',
    ].contains(profileId)) {
      throw ArgumentError.value(
        profileId,
        'profileId',
        'not a system subagent',
      );
    }
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final changed = _disabledSystemAgents.contains(profileId) == enabled;
    if (enabled) {
      _disabledSystemAgents.remove(profileId);
    } else {
      _disabledSystemAgents.add(profileId);
    }
    _settingsRevision += 1;
    _emitAgentProfilesUpdate();
    return _demoSettingsReply(operationId, before, changed: changed);
  }

  @override
  Future<SettingsCommandReply> saveUserAgentProfile(
    int expectedSettingsRevision,
    AgentProfileDraft draft, {
    required OperationId operationId,
  }) async {
    if ([
      'planner',
      'explorer',
      'executor',
      'worktree_executor',
      'reviewer',
    ].contains(draft.id)) {
      throw ArgumentError.value(draft.id, 'id', 'reserved agent identifier');
    }
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final previous = _userAgentProfiles[draft.id];
    _userAgentProfiles[draft.id] = AgentProfileView(
      id: draft.id,
      displayName: draft.displayName,
      description: draft.description,
      whenToUse: draft.whenToUse,
      systemInstructions: draft.systemInstructions,
      accountId: draft.accountId,
      modelId: draft.modelId,
      effort: draft.effort,
      source: '~/.anywork/agents/${draft.id}.toml',
      revision: 'demo-user-${draft.id}',
      contentHash: 'demo-user-${draft.id}',
      system: false,
      enabled: draft.enabled,
      workspaceMode: draft.workspaceMode,
    );
    _settingsRevision += 1;
    _emitAgentProfilesUpdate();
    return _demoSettingsReply(
      operationId,
      before,
      changed: previous != _userAgentProfiles[draft.id],
    );
  }

  @override
  Future<void> cleanupPreservedWorktree({
    required String ownerKind,
    required String ownerThreadId,
    required int expectedLeaseRevision,
  }) async {
    if (ownerKind != WorktreeOwnerKind.session.id &&
        ownerKind != WorktreeOwnerKind.child.id) {
      throw ArgumentError.value(
        ownerKind,
        'ownerKind',
        'must be session or child',
      );
    }
  }

  @override
  Future<StudioProject> renameProject(String projectId, String name) async {
    final project = _demoProjectDirectory().values.firstWhere(
      (project) => project.id == projectId,
    );
    _projectNames[projectId] = name;
    _projectDirectoryRevision++;
    _publishProductPayload(
      ProjectDirectoryChangedPayload(_demoProjectDirectory()),
    );
    return StudioProject(
      id: project.id,
      name: name,
      path: project.path,
      sshAlias: project.sshAlias,
    );
  }

  @override
  Future<StudioProject> openProject(String path) async {
    if (_archivedProjectIds.remove('project-local')) {
      _projectDirectoryRevision += 1;
      _publishProductPayload(
        ProjectDirectoryChangedPayload(_demoProjectDirectory()),
      );
    }
    return _demoProjectDirectory().values.first;
  }

  @override
  Future<List<SshServer>> listSshServers() async => List.of(_sshServers);

  @override
  Future<SshServer> saveSshServer(SaveSshServerCommand command) async {
    final existing = _sshServers
        .where((item) => item.alias == command.alias)
        .firstOrNull;
    final hasPassword = switch (command.password.action) {
      SshPasswordAction.preserve => existing?.hasPassword ?? false,
      SshPasswordAction.replace => true,
      SshPasswordAction.clear => false,
    };
    final server = SshServer(
      alias: command.alias,
      hostName: command.hostName,
      port: command.port,
      username: command.username,
      identityFile: command.identityFile,
      managed: true,
      hasPassword: hasPassword,
    );
    _sshServers.removeWhere((item) => item.alias == server.alias);
    _sshServers.add(server);
    return server;
  }

  @override
  Future<void> deleteSshServer(String alias) async {
    _sshServers.removeWhere((server) => server.alias == alias);
  }

  @override
  Future<SshConnectionView> authenticateSshServer(
    AuthenticateSshServerCommand command,
  ) async {
    final index = _sshServers.indexWhere((item) => item.alias == command.alias);
    if (index != -1 && command.rememberPassword) {
      final current = _sshServers[index];
      _sshServers[index] = SshServer(
        alias: current.alias,
        hostName: current.hostName,
        port: current.port,
        username: current.username,
        identityFile: current.identityFile,
        managed: current.managed,
        hasPassword: true,
      );
    }
    return testSshConnection(command.alias);
  }

  @override
  Future<SshConnectionView> testSshConnection(String alias) async {
    return SshConnectionView(
      alias: alias,
      state: 'ready',
      helperVersion: '0.1.0',
      architecture: 'aarch64',
    );
  }

  @override
  Future<SshConnectionView> reconnectSshServer(String alias) =>
      testSshConnection(alias);

  @override
  Future<RemoteDirectoryListing> browseRemoteDirectories(
    String alias, {
    String? path,
    String? cursor,
  }) async {
    final current = path ?? '/home';
    return RemoteDirectoryListing(
      path: current,
      parent: current == '/' ? null : '/',
      entries: const [
        RemoteDirectoryEntry(name: 'projects', path: '/home/projects'),
        RemoteDirectoryEntry(name: 'workspace', path: '/workspace'),
      ],
    );
  }

  @override
  Future<void> closeRemoteDirectory(String alias, String cursor) async {}

  @override
  Future<StudioProject> openRemoteProject(String alias, String path) async {
    final project = StudioProject(
      id: 'project-remote',
      name: path.split('/').last,
      path: path,
      sshAlias: alias,
    );
    final existingIndex = _openedRemoteProjects.indexWhere(
      (candidate) => candidate.id == project.id,
    );
    if (existingIndex < 0) {
      _openedRemoteProjects.add(project);
      _projectDirectoryRevision += 1;
    } else {
      final existing = _openedRemoteProjects[existingIndex];
      if (existing.name != project.name ||
          existing.path != project.path ||
          existing.sshAlias != project.sshAlias) {
        _openedRemoteProjects[existingIndex] = project;
        _projectDirectoryRevision += 1;
      }
    }
    _publishProductPayload(
      ProjectDirectoryChangedPayload(_demoProjectDirectory()),
    );
    return project;
  }

  @override
  Future<void> activateProject(String projectId) async {
    if (!_demoProjectDirectory().values.any(
      (project) => project.id == projectId,
    )) {
      throw StateError('unknown demo project $projectId');
    }
    _selectedProjectId = projectId;
  }

  @override
  Stream<NewThreadStartEvent> startNewThread(
    String projectId,
    StudioPromptInput input,
    ThreadModeId mode, {
    required ModeModelRouteView route,
    String? workspaceMode,
  }) async* {
    try {
      final projects = _demoProjectDirectory().values;
      if (!projects.any((project) => project.id == projectId)) {
        throw StateError('unknown demo project $projectId');
      }
      if (input.text.trim().isEmpty && input.attachmentDraftIds.isEmpty) {
        throw ArgumentError.value(input.text, 'text', 'empty');
      }
      final requestedWorkspaceMode = switch (workspaceMode?.trim()) {
        null || '' || 'local' => ThreadWorkspaceMode.local,
        'worktree' => ThreadWorkspaceMode.worktree,
        final other => throw ArgumentError.value(
          other,
          'workspaceMode',
          'must be local or worktree',
        ),
      };
      yield NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: projectId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.checkingProject,
        ),
      );
      final now = DateTime.now();
      final provisionalTitle = _demoProvisionalThreadTitle(input.text);
      final threadId = 'thread-created-${++_threadSequence}';
      final projectPath = projects
          .firstWhere((project) => project.id == projectId)
          .path;
      yield NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: projectId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.preparingWorkspace,
        ),
      );
      final thread = StudioThread(
        id: threadId,
        projectId: projectId,
        title: provisionalTitle,
        mode: mode,
        role: 'planner',
        createdAt: now,
        updatedAt: now,
        workspaceMode: requestedWorkspaceMode,
        workspacePath: requestedWorkspaceMode == ThreadWorkspaceMode.worktree
            ? _demoWorktreePath(projectPath, threadId)
            : projectPath,
      );
      yield NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: projectId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.initializingSession,
          workspacePath: thread.workspacePath,
        ),
      );
      _createdRootThreads.add(thread);
      _ensureWorkspaceFixture();
      _selectedThreadId = thread.id;
      final workspace = _workspaces[thread.id]!;
      _workspaces[thread.id] = workspace.copyWith(
        runtime: workspace.runtime.copyWith(
          modelId: route.modelId,
          modelRoute: ThreadModelRouteView(
            accountId: route.accountId,
            modelId: route.modelId,
            effort: route.effort,
            revision: 1,
            available: true,
          ),
        ),
      );
      yield NewThreadStartProgress(
        ThreadPreparationProgress(
          projectId: projectId,
          inputId: input.inputId,
          stage: ThreadPreparationStage.submittingPrompt,
          workspacePath: thread.workspacePath,
        ),
      );
      final receipt = await _submitPrompt(thread.id, input);
      if (input.text.trim().isNotEmpty) {
        unawaited(_completeDemoThreadTitle(thread.id, provisionalTitle));
      }
      yield NewThreadStartSucceeded(
        StartNewThreadResult(thread: thread, receipt: receipt),
      );
    } catch (error) {
      yield NewThreadStartFailed(
        StudioFailure(
          code: error is ArgumentError
              ? StudioFailureCode.invalidArgument
              : StudioFailureCode.internal,
          message: error.toString(),
          retryable: false,
          correlationId: newStudioCorrelationId(),
        ),
      );
    }
  }

  @override
  Future<RenameThreadCommandReply> renameThread(
    String threadId,
    String title, {
    required OperationId operationId,
  }) async {
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.runes.length > 80) {
      throw ArgumentError.value(title, 'title', 'must be 1–80 characters');
    }
    final index = _createdRootThreads.indexWhere(
      (thread) => thread.id == threadId,
    );
    if (index < 0) throw StateError('unknown demo root Thread $threadId');
    final changed = _createdRootThreads[index].title != normalized;
    final renamed = _createdRootThreads[index].copyWith(
      title: normalized,
      updatedAt: DateTime.now(),
    );
    _createdRootThreads[index] = renamed;
    if (_workspaces[threadId] case final workspace?) {
      _workspaces[threadId] = workspace.copyWith(thread: renamed);
    }
    _emitThreadDirectoryUpdate(renamed);
    return RenameThreadCommandReply(
      thread: renamed,
      receipt: _demoReceipt(
        operationId,
        changed: changed,
        targets: [_demoStamp('thread-directory', _threadDirectoryRevision)],
        effect: EffectPoint.immediate,
      ),
    );
  }

  Future<void> _completeDemoThreadTitle(
    String threadId,
    String provisionalTitle,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final index = _createdRootThreads.indexWhere(
      (thread) => thread.id == threadId,
    );
    if (index < 0 || _archivedThreadIds.contains(threadId)) return;
    final current = _createdRootThreads[index];
    if (current.title != provisionalTitle) return;
    final renamed = current.copyWith(
      title: 'Demo generated session',
      updatedAt: DateTime.now(),
    );
    _createdRootThreads[index] = renamed;
    if (_workspaces[threadId] case final workspace?) {
      _workspaces[threadId] = workspace.copyWith(thread: renamed);
    }
    _emitThreadDirectoryUpdate(renamed);
  }

  /// 记录一次已受理的模拟用户消息：推进目录的最近用户消息时间并广播增量。
  void _advanceDemoLastUserMessage(String threadId, DateTime acceptedAt) {
    StudioThread? updated;
    for (var index = 0; index < _createdRootThreads.length; index++) {
      if (_createdRootThreads[index].id == threadId) {
        updated = _createdRootThreads[index] = _createdRootThreads[index]
            .copyWith(lastUserMessageAt: acceptedAt, updatedAt: acceptedAt);
      }
    }
    for (var index = 0; index < _pageFillThreads.length; index++) {
      if (_pageFillThreads[index].id == threadId) {
        updated = _pageFillThreads[index] = _pageFillThreads[index].copyWith(
          lastUserMessageAt: acceptedAt,
          updatedAt: acceptedAt,
        );
      }
    }
    final workspace = _workspaces[threadId];
    if (workspace != null && workspace.thread.id == threadId) {
      final thread = workspace.thread.copyWith(
        lastUserMessageAt: acceptedAt,
        updatedAt: acceptedAt,
      );
      _workspaces[threadId] = workspace.copyWith(thread: thread);
      updated = thread;
    }
    if (updated != null) {
      _emitThreadDirectoryUpdate(updated);
    }
  }

  /// settings 写入的 canonical 事实同时经 topic 交付。
  ///
  /// 真实侧每次 `publish_settings_state` 都发布 `SettingsConfigStateChanged` 与
  /// `ModelCatalogStateChanged`，只让命令返回快照会让仅依赖 topic 的观察者停在旧值，
  /// demo 因此与真实 bridge 语义分叉（design/25 §25.10）。
  SettingsStateSnapshot _settingsWriteResult() {
    final state = _demoSettingsState();
    _publishProductPayload(SettingsConfigStateChangedPayload(state));
    _publishProductPayload(ModelCatalogStateChangedPayload(state));
    return state;
  }

  ResourceStamp _demoStamp(String key, int revision) => ResourceStamp(
    resourceKey: key,
    ownerEpoch: _ownerEpoch,
    revision: revision,
  );

  StudioCommandReceipt _demoReceipt(
    OperationId operationId, {
    required bool changed,
    required List<ResourceStamp> targets,
    required EffectPoint effect,
    bool? effective,
    bool requiresIdentityObservation = false,
  }) => StudioCommandReceipt(
    operationId: operationId,
    disposition: changed
        ? CommitDisposition.applied
        : CommitDisposition.noChange,
    targets: targets,
    effect: effect,
    effective: effective ?? effect == EffectPoint.immediate,
    requiresIdentityObservation: requiresIdentityObservation,
    // Demo has no native persistence and cannot acknowledge durability.
    durable: false,
  );

  SettingsCommandReply _demoSettingsReply(
    OperationId operationId,
    SettingsStateSnapshot before, {
    bool? changed,
    EffectPoint effect = EffectPoint.futureSession,
  }) {
    final snapshot = _settingsWriteResult();
    return SettingsCommandReply(
      snapshot: snapshot,
      receipt: _demoReceipt(
        operationId,
        changed:
            changed ??
            !_sameDemoFacts(
              _demoSettingsFacts(before),
              _demoSettingsFacts(snapshot),
            ),
        targets: [_demoStamp('settings', snapshot.revision)],
        effect: effect,
      ),
    );
  }

  EffectPoint _demoFieldEffect(SettingsFieldCommand command) =>
      switch (command) {
        GeneralFollowActiveTurnCommand() ||
        GeneralCompactTimelineCommand() ||
        GeneralSidebarWidthCommand() ||
        GeneralPinnedThreadIdsCommand() ||
        GeneralPinnedProjectIdsCommand() => EffectPoint.immediate,
        _ => EffectPoint.futureSession,
      };

  // Compare canonical business values, excluding resource clocks and diagnostics.
  // This is a value comparison of the one demo owner, not a second state store.
  List<Object?> _demoSettingsFacts(SettingsStateSnapshot s) => [
    s.defaultAccountId,
    s.permissionMode,
    {
      for (final account in s.acpAccounts)
        account.accountId: [
          account.name,
          account.provider.wire,
          account.program,
          account.args,
          account.connectionRevision,
        ],
    },
    {
      for (final p in s.accounts)
        p.id: [
          p.name,
          p.templateId,
          p.protocol,
          p.baseUrl,
          p.bearerToken,
          p.hasBearerToken,
          p.defaultModelId,
          p.pricingEnabled,
          [
            for (final m in p.customModels)
              [
                m.modelId,
                m.displayName,
                m.wireApi,
                m.contextWindow,
                m.maxOutputTokens,
              ],
          ],
          p.modelConnectionModes,
          {
            for (final e in p.autoCompactLimits.entries)
              e.key: e.value.overrideLimit,
          },
        ],
    },
    {
      for (final route in s.modeModelRoutes)
        route.modeId.id: [route.accountId, route.modelId, route.effort],
    },
    {
      for (final role in s.roles)
        role.key: [role.accountId, role.modelId, role.effort],
    },
    {
      for (final server in s.mcpServers)
        server.id: [server.transport, server.endpoint],
    },
    [
      s.instructions.baseOverride,
      s.instructions.developer,
      s.instructions.user,
      s.instructions.projectDocMaxBytes,
      s.instructions.projectDocFallbackFilenames,
    ],
    [
      s.skills.enabled,
      s.skills.autoLearn,
      s.skills.systemEnabled,
      s.skills.projectDir,
      s.skills.userDir,
      s.skills.externalDirs,
      s.skills.disabled,
      s.skills.autoLearnMinToolCalls,
    ],
    [
      s.general.followActiveTurn,
      s.general.compactTimeline,
      s.general.sidebarWidth,
      s.general.pinnedThreadIds,
      s.general.pinnedProjectIds,
    ],
    [
      s.webSearch.configuredMode,
      s.webSearch.contextSize,
      s.webSearch.allowedDomains,
      s.webSearch.country,
      s.webSearch.region,
      s.webSearch.city,
      s.webSearch.timezone,
    ],
    [
      s.deepSeekWebSearch.configuredEnabled,
      s.deepSeekWebSearch.configuredFetchEnabled,
    ],
  ];

  bool _sameDemoFacts(Object? left, Object? right) {
    if (left is List && right is List) {
      return left.length == right.length &&
          [
            for (var i = 0; i < left.length; i++)
              _sameDemoFacts(left[i], right[i]),
          ].every((value) => value);
    }
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) =>
                right.containsKey(key) && _sameDemoFacts(left[key], right[key]),
          );
    }
    return left == right;
  }

  void _emitThreadDirectoryUpdate(StudioThread thread) {
    _threadDirectoryRevision += 1;
    _publishProductPayload(
      ThreadDirectoryChangedPayload(
        revision: _threadDirectoryRevision,
        upserted: [thread],
        removed: const [],
      ),
    );
  }

  /// 配置级 Profiles 变化同样发布 typed topic 事实（保存命令返回 Settings snapshot，
  /// 但 Profiles 目录自身是独立资源；订阅者按 revision 前进）。
  void _emitAgentProfilesUpdate() {
    _agentProfilesRevision += 1;
    _publishProductPayload(
      AgentProfilesStateChangedPayload(readAgentProfilesStateSync()),
    );
  }

  AgentProfilesStateView readAgentProfilesStateSync() {
    return AgentProfilesStateView(
      state: ReadyObservedResource(
        revision: _agentProfilesRevision,
        updatedAt: 0,
        lastCheckedAt: null,
        value: AgentProfilesDataView(
          profiles: _demoAgentProfilesSync(),
          diagnostics: const [],
        ),
      ),
    );
  }

  List<AgentProfileView> _demoAgentProfilesSync() {
    return [
      AgentProfileView(
        id: 'explorer',
        displayName: 'Explorer',
        description: '只读探索代码、文档和现场事实。',
        whenToUse: '需要定位边界、依赖或验证事实时。',
        systemInstructions: '优先收集事实并引用文件与命令。',
        accountId: 'demo',
        modelId: 'demo',
        effort: 'medium',
        source: 'studio-builtin',
        revision: 'studio-system-agent-v1',
        contentHash: 'demo-explorer',
        system: true,
        enabled: !_disabledSystemAgents.contains('explorer'),
        workspaceMode: AgentWorkspaceMode.unrestricted,
      ),
      AgentProfileView(
        id: 'executor',
        displayName: 'Executor',
        description: '在项目目录内实施边界明确的修改。',
        whenToUse: '需要限制 糊来帮内置文件写工具的修改目录时。',
        systemInstructions: '遵守冻结的 writablePaths。',
        accountId: 'demo',
        modelId: 'demo',
        effort: 'medium',
        source: 'studio-builtin',
        revision: 'studio-system-agent-v2',
        contentHash: 'demo-executor',
        system: true,
        enabled: !_disabledSystemAgents.contains('executor'),
        workspaceMode: AgentWorkspaceMode.directory,
      ),
      AgentProfileView(
        id: 'worktree_executor',
        displayName: 'Worktree Executor',
        description: '在独立 Git worktree 内实施修改。',
        whenToUse: '需要物理隔离并显式整合 commit 时。',
        systemInstructions: '只修改分配的 worktree，不自动整合。',
        accountId: 'demo',
        modelId: 'demo',
        effort: 'medium',
        source: 'studio-builtin',
        revision: 'studio-system-agent-v2',
        contentHash: 'demo-worktree-executor',
        system: true,
        enabled: !_disabledSystemAgents.contains('worktree_executor'),
        workspaceMode: AgentWorkspaceMode.worktree,
      ),
      AgentProfileView(
        id: 'reviewer',
        displayName: 'Reviewer',
        description: '独立审查实现和验证证据。',
        whenToUse: '需要复核实现质量时。',
        systemInstructions: '只读审查并报告具体证据。',
        accountId: 'demo',
        modelId: 'demo',
        effort: 'medium',
        source: 'studio-builtin',
        revision: 'studio-system-agent-v2',
        contentHash: 'demo-reviewer',
        system: true,
        enabled: !_disabledSystemAgents.contains('reviewer'),
        workspaceMode: AgentWorkspaceMode.unrestricted,
      ),
      ..._userAgentProfiles.values,
    ];
  }

  @override
  Future<ArchiveThreadCommandReply> archiveThread(
    String threadId, {
    required OperationId operationId,
  }) async {
    final thread = _sortedDirectoryThreads()
        .where((candidate) => candidate.id == threadId)
        .firstOrNull;
    if (thread == null || !thread.isRoot) {
      throw StateError('only a root Thread can be archived');
    }
    // 归档前先结束会话树的活动工作：中断正在运行的 Turn，再归档。
    final activeTurn = _workspaces[threadId]?.activeTurn;
    if (activeTurn != null && activeTurn.state.isBusy) {
      _interruptDemoTurn(threadId, activeTurn.turnId);
    }
    final roots = _sortedDirectoryThreads()
        .where((candidate) => candidate.isRoot)
        .toList();
    final index = roots.indexWhere((candidate) => candidate.id == threadId);
    if (index < 0) throw StateError('unknown demo root Thread $threadId');
    final nextRoot = index + 1 < roots.length
        ? roots[index + 1]
        : index > 0
        ? roots[index - 1]
        : null;
    final removedThreadIds = <String>{
      threadId,
      for (final candidate in _ensureWorkspaceFixture().threads)
        if (candidate.effectiveRootThreadId == threadId) candidate.id,
    }.toList();
    _archivedThreadIds.add(threadId);
    if (_selectedThreadId == threadId) _selectedThreadId = nextRoot?.id;
    _threadDirectoryRevision += 1;
    _publishProductPayload(
      ThreadDirectoryChangedPayload(
        revision: _threadDirectoryRevision,
        upserted: const [],
        removed: removedThreadIds,
      ),
    );
    return ArchiveThreadCommandReply(
      result: ArchiveThreadResult(
        archivedRootId: threadId,
        removedThreadIds: removedThreadIds,
        nextRoot: nextRoot,
      ),
      receipt: _demoReceipt(
        operationId,
        changed: true,
        targets: [_demoStamp('thread-directory', _threadDirectoryRevision)],
        effect: EffectPoint.immediate,
      ),
    );
  }

  @override
  Future<void> archiveProject(String projectId) async {
    if (projectId == 'project-local' && _archivedProjectIds.add(projectId)) {
      _projectDirectoryRevision += 1;
      final removed = _workspaces.values
          .where((workspace) => workspace.thread.projectId == projectId)
          .map((workspace) => workspace.thread.id)
          .toList();
      _threadDirectoryRevision += 1;
      _publishProductPayload(
        ProjectDirectoryChangedPayload(_demoProjectDirectory()),
      );
      _publishProductPayload(
        ThreadDirectoryChangedPayload(
          revision: _threadDirectoryRevision,
          upserted: const [],
          removed: removed,
        ),
      );
    }
  }

  @override
  Future<PersistenceStateSnapshot> retryPersistence() async =>
      const PersistenceStateSnapshot.ready();

  @override
  Future<PersistenceQueueSnapshot> retryThreadHistory(
    String threadId,
    int faultGeneration,
  ) async => const PersistenceQueueSnapshot.empty();

  /// demo 是纯内存实现，没有存储故障闩：显式继续同样是空的 canonical 观测。
  @override
  Future<PersistenceQueueSnapshot> resumeThreadHistory(
    String threadId,
    int faultGeneration,
  ) async => const PersistenceQueueSnapshot.empty();

  /// demo 是纯内存实现，没有异步持久化队列，因此队列压力恒为空的 canonical 观测。
  @override
  Future<PersistenceQueueStateView> readPersistenceQueueState() async =>
      const PersistenceQueueStateView(
        revision: 0,
        queue: PersistenceQueueSnapshot.empty(),
      );

  @override
  Future<PersistenceQueueSnapshot> readPersistenceQueue() async =>
      const PersistenceQueueSnapshot.empty();

  /// Demo counterpart of the production field mutation endpoint.
  ///
  /// The demo must obey the same contract as the Bridge: one command changes
  /// one canonical field/resource and never reconstructs a sibling settings
  /// object from a stale page snapshot.
  @override
  Future<SettingsCommandReply> applySettingsField(
    int expectedSettingsRevision,
    SettingsFieldCommand command, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final settings = before;
    switch (command) {
      case InstructionBaseOverrideCommand(:final value):
        _instructions = _instructions.copyWith(baseOverride: value);
      case InstructionDeveloperCommand(:final value):
        _instructions = _instructions.copyWith(developer: value);
      case InstructionUserCommand(:final value):
        _instructions = _instructions.copyWith(user: value);
      case ProjectDocMaxBytesCommand(:final value):
        _instructions = _instructions.copyWith(projectDocMaxBytes: value);
      case ProjectDocFallbackFilenamesCommand(:final value):
        _instructions = _instructions.copyWith(
          projectDocFallbackFilenames: value,
        );
      case SkillsEnabledCommand(:final value):
        _skills = _skills.copyWith(enabled: value);
      case SkillsAutoLearnCommand(:final value):
        _skills = _skills.copyWith(autoLearn: value);
      case SkillsSystemEnabledCommand(:final value):
        _skills = _skills.copyWith(systemEnabled: value);
      case SkillsProjectDirCommand(:final value):
        _skills = _skills.copyWith(projectDir: value);
      case SkillsUserDirCommand(:final value):
        _skills = _skills.copyWith(userDir: value);
      case SkillsExternalDirsCommand(:final value):
        _skills = _skills.copyWith(externalDirs: value);
      case SkillsDisabledCommand(:final value):
        _skills = _skills.copyWith(disabled: value);
      case SkillsAutoLearnMinToolCallsCommand(:final value):
        _skills = _skills.copyWith(autoLearnMinToolCalls: value);
      case McpServerEnabledCommand():
      case McpServerTransportCommand():
      case McpServerEndpointCommand():
        // The demo fixture has no configurable MCP entries. Keep the command
        // observable through the same revision/resource boundary as Bridge.
        _mcpRevision += 1;
        _publishProductPayload(McpStateChangedPayload(_demoMcpState()));
      case GeneralFollowActiveTurnCommand(:final value):
        _general = _general.copyWith(followActiveTurn: value);
      case GeneralCompactTimelineCommand(:final value):
        _general = _general.copyWith(compactTimeline: value);
      case GeneralSidebarWidthCommand(:final value):
        _general = _general.copyWith(sidebarWidth: value ?? 336);
      case GeneralPinnedThreadIdsCommand(:final value):
        _general = _general.copyWith(pinnedThreadIds: value);
      case GeneralPinnedProjectIdsCommand(:final value):
        _general = _general.copyWith(pinnedProjectIds: value);
      case WebSearchModeCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: value,
          contextSize: _webSearch.contextSize,
          allowedDomains: _webSearch.allowedDomains,
          country: _webSearch.country,
          region: _webSearch.region,
          city: _webSearch.city,
          timezone: _webSearch.timezone,
        );
      case WebSearchContextSizeCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: value,
          allowedDomains: _webSearch.allowedDomains,
          country: _webSearch.country,
          region: _webSearch.region,
          city: _webSearch.city,
          timezone: _webSearch.timezone,
        );
      case WebSearchAllowedDomainsCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: _webSearch.contextSize,
          allowedDomains: value,
          country: _webSearch.country,
          region: _webSearch.region,
          city: _webSearch.city,
          timezone: _webSearch.timezone,
        );
      case WebSearchCountryCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: _webSearch.contextSize,
          allowedDomains: _webSearch.allowedDomains,
          country: value,
          region: _webSearch.region,
          city: _webSearch.city,
          timezone: _webSearch.timezone,
        );
      case WebSearchRegionCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: _webSearch.contextSize,
          allowedDomains: _webSearch.allowedDomains,
          country: _webSearch.country,
          region: value,
          city: _webSearch.city,
          timezone: _webSearch.timezone,
        );
      case WebSearchCityCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: _webSearch.contextSize,
          allowedDomains: _webSearch.allowedDomains,
          country: _webSearch.country,
          region: _webSearch.region,
          city: value,
          timezone: _webSearch.timezone,
        );
      case WebSearchTimezoneCommand(:final value):
        _webSearch = _webSearch.withConfiguredValues(
          configuredMode: _webSearch.configuredMode,
          contextSize: _webSearch.contextSize,
          allowedDomains: _webSearch.allowedDomains,
          country: _webSearch.country,
          region: _webSearch.region,
          city: _webSearch.city,
          timezone: value,
        );
      case DeepSeekWebSearchEnabledCommand(:final value):
        _deepSeekWebSearch = _deepSeekWebSearch.withConfiguredEnabled(value);
      case DeepSeekWebFetchEnabledCommand(:final value):
        _deepSeekWebSearch = _deepSeekWebSearch.withConfiguredFetchEnabled(
          value,
        );
      case ModeModelCommand(:final modeId, :final accountId, :final modelId):
        final mode = ThreadModeId.fromId(modeId);
        final selected = _findDemoModel(settings.accounts, accountId, modelId);
        final previous = settings.modeModelRoutes
            .where((route) => route.modeId == mode)
            .firstOrNull;
        final effort =
            previous != null &&
                previous.accountId == accountId &&
                previous.modelId == modelId
            ? previous.effort
            : selected.defaultReasoningEffort.isNotEmpty
            ? selected.defaultReasoningEffort
            : selected.reasoningEfforts.firstOrNull ?? '';
        _modeRoutes = [
          for (final route in settings.modeModelRoutes)
            if (route.modeId != mode) route,
          ModeModelRouteView(
            modeId: mode,
            accountId: accountId,
            modelId: modelId,
            effort: effort,
          ),
        ];
      case ModeReasoningEffortCommand(:final modeId, :final effort):
        final mode = ThreadModeId.fromId(modeId);
        final previous = settings.modeModelRoutes
            .where((route) => route.modeId == mode)
            .firstOrNull;
        final route = previous ?? _demoModeRoute(mode);
        final selected = _findDemoModel(
          settings.accounts,
          route.accountId,
          route.modelId,
        );
        final resolvedEffort =
            effort != null && selected.reasoningEfforts.contains(effort)
            ? effort
            : selected.defaultReasoningEffort.isNotEmpty
            ? selected.defaultReasoningEffort
            : selected.reasoningEfforts.firstOrNull ?? '';
        _modeRoutes = [
          for (final candidate in settings.modeModelRoutes)
            if (candidate.modeId != mode) candidate,
          ModeModelRouteView(
            modeId: mode,
            accountId: route.accountId,
            modelId: route.modelId,
            effort: resolvedEffort,
          ),
        ];
      case RoleModelCommand(:final role, :final accountId, :final modelId):
        final selected = _findDemoModel(settings.accounts, accountId, modelId);
        final previous = settings.roles
            .where((candidate) => candidate.key == role)
            .firstOrNull;
        final effort =
            previous != null &&
                previous.accountId == accountId &&
                previous.modelId == modelId
            ? previous.effort
            : selected.defaultReasoningEffort.isNotEmpty
            ? selected.defaultReasoningEffort
            : selected.reasoningEfforts.firstOrNull ?? '';
        final next = RoleSettingsView(
          key: role,
          accountId: accountId,
          modelId: modelId,
          effort: effort,
        );
        _roles = [
          for (final candidate in settings.roles)
            if (candidate.key != role) candidate,
          next,
        ];
      case RoleReasoningEffortCommand(:final role, :final effort):
        final previous = settings.roles
            .where((candidate) => candidate.key == role)
            .firstOrNull;
        if (previous == null) {
          throw StateError('unknown demo Agent role: $role');
        }
        final selected = _findDemoModel(
          settings.accounts,
          previous.accountId,
          previous.modelId,
        );
        final resolvedEffort =
            effort != null && selected.reasoningEfforts.contains(effort)
            ? effort
            : selected.defaultReasoningEffort.isNotEmpty
            ? selected.defaultReasoningEffort
            : selected.reasoningEfforts.firstOrNull ?? '';
        _roles = [
          for (final candidate in settings.roles)
            candidate.key == role
                ? RoleSettingsView(
                    key: candidate.key,
                    accountId: candidate.accountId,
                    modelId: candidate.modelId,
                    effort: resolvedEffort,
                  )
                : candidate,
        ];
    }
    _settingsRevision += 1;
    return _demoSettingsReply(
      operationId,
      before,
      effect: _demoFieldEffect(command),
    );
  }

  @override
  Future<ThreadModelRouteCommandReply> setThreadModelRoute({
    required OperationId operationId,
    required String threadId,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
    required String accountId,
    required String modelId,
    String? effort,
  }) async {
    final current = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final thread = _sortedDirectoryThreads()
        .where((candidate) => candidate.id == threadId)
        .firstOrNull;
    final workspace = _workspaces[threadId];
    if (thread == null || !thread.isRoot || workspace == null) {
      throw StateError('unknown root demo thread $threadId');
    }
    final previousRoute = workspace.runtime.modelRoute;
    if (previousRoute == null) {
      throw StateError('demo thread has no saved model route');
    }
    if (previousRoute.revision != expectedModelRouteRevision) {
      throw StateError('model route revision conflict');
    }
    final selected = current.accounts
        .firstWhere((account) => account.id == accountId)
        .models
        .firstWhere((candidate) => candidate.modelId == modelId);
    final selectedEffort = selected.reasoningEfforts.contains(effort)
        ? effort
        : selected.reasoningEfforts.firstOrNull ?? '';
    _modeRoutes = [
      for (final route in current.modeModelRoutes)
        if (route.modeId != thread.mode) route,
      ModeModelRouteView(
        modeId: thread.mode,
        accountId: accountId,
        modelId: modelId,
        effort: selectedEffort ?? '',
      ),
    ];
    _settingsRevision += 1;
    final runtime = workspace.runtime.copyWith(
      modelRoute: ThreadModelRouteView(
        accountId: accountId,
        modelId: modelId,
        effort: selectedEffort,
        revision: previousRoute.revision + 1,
        available: true,
      ),
    );
    _workspaces[threadId] = workspace.copyWith(runtime: runtime);
    // 与生产一致：route 变更作为 Thread 运行时状态流事实交付（revision 单调）。
    // 只写内存 workspace 会让选择器在乐观值被清除后回落到旧 canonical route。
    _emitThreadUpdate(
      threadId,
      ThreadRuntimeUpdate(runtime: runtime, todo: workspace.todo),
    );
    final settings = _settingsWriteResult();
    return ThreadModelRouteCommandReply(
      receipt: _demoReceipt(
        operationId,
        changed:
            previousRoute.accountId != accountId ||
            previousRoute.modelId != modelId ||
            previousRoute.effort != selectedEffort ||
            !_sameDemoFacts(
              _demoSettingsFacts(current),
              _demoSettingsFacts(settings),
            ),
        targets: [
          _demoStamp('thread-route:$threadId', runtime.modelRoute!.revision),
          _demoStamp('settings', settings.revision),
        ],
        effect: EffectPoint.nextTurn,
      ),
      runtime: runtime,
      settings: settings,
      modeDefaultSaved: true,
      warning: null,
    );
  }

  @override
  Future<void> compactThread(String threadId) async {
    throw UnsupportedError('Manual compaction requires the native runtime');
  }

  @override
  Future<ThreadModeCommandReply> setThreadMode({
    required OperationId operationId,
    required String threadId,
    required ThreadModeId mode,
  }) async {
    final thread = _sortedDirectoryThreads()
        .where((candidate) => candidate.id == threadId)
        .firstOrNull;
    if (thread == null) {
      throw StateError('unknown demo thread $threadId');
    }
    if (!thread.isRoot) {
      throw StateError('only a root Thread can change mode');
    }
    if (thread.status != ThreadStatusView.idle) {
      throw StateError(
        'thread mode cannot change while the Thread is running or has pending input',
      );
    }
    final workflow = _workspaces[threadId]?.runtime.workflow;
    if (workflow?.isActive ?? false) {
      throw StateError('thread mode cannot change while a workflow is active');
    }
    _threadModes[threadId] = mode;
    final workspace = _workspaces[threadId];
    if (workspace != null) {
      final settings = _demoSettingsState();
      final route =
          settings.modeModelRoutes
              .where((candidate) => candidate.modeId == mode)
              .firstOrNull ??
          settings.modeModelRoutes
              .where((candidate) => candidate.modeId == ThreadModeId.simple)
              .firstOrNull;
      final thread = workspace.thread;
      final updatedThread = thread.copyWith(
        mode: mode,
        role: thread.isRoot ? 'planner' : thread.role,
      );
      // 与生产一致：mode 变更同时交付两条 canonical 事实。
      //
      // 其一，运行时事实：native `set_thread_mode` 经 reconfigure 改写 mode 默认
      // route 扩展并发布 Thread 帧。demo 若只改内存 workspace 而不出这一帧，客户端
      // 的 threadSession 就只能在显式重读下看到新 route，验收无法发现帧丢失。
      _emitThreadUpdate(
        threadId,
        ThreadRuntimeUpdate(
          runtime: route == null
              ? workspace.runtime
              : workspace.runtime.copyWith(
                  modelRoute: ThreadModelRouteView(
                    accountId: route.accountId,
                    modelId: route.modelId,
                    effort: route.effort,
                    revision: (workspace.runtime.modelRoute?.revision ?? 0) + 1,
                    available: true,
                  ),
                ),
          todo: workspace.todo,
        ),
      );
      _workspaces[threadId] = _workspaces[threadId]!.copyWith(
        thread: updatedThread,
      );
      // 其二，目录事实：mode 由目录增量交付（目录 revision 前进）。不推进目录水位
      // 会让客户端的目录基线门与目录事件都看不到这次变更。
      _emitThreadDirectoryUpdate(updatedThread);
    }
    return ThreadModeCommandReply(
      receipt: _demoReceipt(
        operationId,
        changed: true,
        targets: [
          _demoStamp('thread-state:$threadId', _workspaces[threadId]!.revision),
          _demoStamp('thread-directory', _threadDirectoryRevision),
        ],
        effect: EffectPoint.immediate,
      ),
    );
  }

  @override
  Future<ModeDefinitionSnapshot> readThreadModeDefinition(String modeId) async {
    final document = _modeDocuments[modeId];
    if (document == null) {
      throw _demoModeFailure(
        StudioFailureCode.notFound,
        'Unknown demo mode $modeId',
        retryable: false,
      );
    }
    return ModeDefinitionSnapshot(
      revision: _threadModeCatalogRevision,
      document: document,
      readOnly: _readOnlyModeIds.contains(modeId),
    );
  }

  @override
  Future<ModeDefinitionCommandReply> saveThreadModeDefinition(
    ModeDocument document, {
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    final modeId = document.definition.id;
    if (_readOnlyModeIds.contains(modeId)) {
      throw _demoModeFailure(
        StudioFailureCode.permissionDenied,
        'Built-in mode $modeId is read-only',
        retryable: false,
      );
    }
    if (expectedRevision != _threadModeCatalogRevision) {
      throw _demoModeFailure(
        StudioFailureCode.staleRevision,
        'Mode catalog revision changed',
        retryable: true,
      );
    }
    _modeDocuments[modeId] = document;
    _emitModeCatalogUpdate();
    return _demoModeCommandReply(
      operationId,
      definition: ModeDefinitionSnapshot(
        revision: _threadModeCatalogRevision,
        document: document,
        readOnly: false,
      ),
    );
  }

  @override
  Future<ModeDefinitionCommandReply> deleteThreadModeDefinition(
    String modeId, {
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    if (_readOnlyModeIds.contains(modeId)) {
      throw _demoModeFailure(
        StudioFailureCode.permissionDenied,
        'Built-in mode $modeId is read-only',
        retryable: false,
      );
    }
    if (expectedRevision != _threadModeCatalogRevision) {
      throw _demoModeFailure(
        StudioFailureCode.staleRevision,
        'Mode catalog revision changed',
        retryable: true,
      );
    }
    if (_modeDocuments.remove(modeId) == null) {
      throw _demoModeFailure(
        StudioFailureCode.notFound,
        'Unknown demo mode $modeId',
        retryable: false,
      );
    }
    _emitModeCatalogUpdate();
    return _demoModeCommandReply(operationId);
  }

  @override
  Future<ModeDefinitionCommandReply> reloadThreadModeDefinitions({
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    if (expectedRevision != _threadModeCatalogRevision) {
      throw _demoModeFailure(
        StudioFailureCode.staleRevision,
        'Mode catalog revision changed',
        retryable: true,
      );
    }
    _emitModeCatalogUpdate();
    return _demoModeCommandReply(operationId);
  }

  @override
  Future<ModeValidationResult> validateThreadModeDefinition(String json) async {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      return ModeValidationResult(
        issues: [
          ModeValidationIssue(
            code: 'json.invalid',
            path: r'$',
            message: error.message,
          ),
        ],
      );
    }
    if (decoded is! Map<Object?, Object?>) {
      return const ModeValidationResult(
        issues: [
          ModeValidationIssue(
            code: 'json.invalid',
            path: r'$',
            message: 'The Mode document must be a JSON object',
          ),
        ],
      );
    }
    final ModeDocument document;
    try {
      document = ModeDocument.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      return ModeValidationResult(
        issues: [
          ModeValidationIssue(
            code: 'json.invalid',
            path: r'$',
            message: error.toString(),
          ),
        ],
      );
    }
    final issues = <ModeValidationIssue>[];
    final workflow = document.definition.workflow;
    if (workflow != null) {
      final ids = <String>{};
      for (final state in workflow.states) {
        if (!ids.add(state.id)) {
          issues.add(
            ModeValidationIssue(
              code: 'workflow.duplicateState',
              path: 'workflow.states.${state.id}',
              message: 'Workflow state ${state.id} is duplicated',
            ),
          );
        }
      }
      if (!ids.contains(workflow.initialStateId)) {
        issues.add(
          ModeValidationIssue(
            code: 'workflow.unknownInitialState',
            path: 'workflow.initialStateId',
            message: 'Initial state ${workflow.initialStateId} does not exist',
          ),
        );
      }
      for (final transition in workflow.transitions) {
        if (!ids.contains(transition.sourceStateId) ||
            !ids.contains(transition.targetStateId)) {
          issues.add(
            ModeValidationIssue(
              code: 'workflow.unknownTransitionState',
              path: 'workflow.transitions',
              message:
                  'Transition ${transition.sourceStateId} -> '
                  '${transition.targetStateId} references an unknown state',
            ),
          );
        }
      }
    }
    return ModeValidationResult(
      document: issues.isEmpty ? document : null,
      issues: issues,
    );
  }

  @override
  Future<String> threadModeDefinitionSchema() async => jsonEncode({
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'title': 'Anywork Thread Mode',
    'type': 'object',
    'required': ['id', 'displayName', 'description', 'order', 'prompt'],
    'properties': {
      'id': {'type': 'string', 'pattern': r'^mode\.[a-z0-9_-]+$'},
      'displayName': {'type': 'string'},
      'description': {'type': 'string'},
      'order': {'type': 'integer', 'minimum': 0},
      'prompt': {'type': 'string'},
      'workflow': {
        'type': ['object', 'null'],
      },
      'editor': {'type': 'object'},
    },
  });

  @override
  Future<WorkflowPreviewSnapshot> previewThreadModeWorkflow(
    WorkflowPreviewRequest request,
  ) async => _demoWorkflowPreview(request);

  void _emitModeCatalogUpdate() {
    _threadModeCatalogRevision += 1;
    _publishProductPayload(
      ThreadModeCatalogChangedPayload(_demoThreadModeCatalog()),
    );
  }

  ModeDefinitionCommandReply _demoModeCommandReply(
    OperationId operationId, {
    ModeDefinitionSnapshot? definition,
  }) => ModeDefinitionCommandReply(
    catalog: _demoThreadModeCatalog(),
    definition: definition,
    receipt: _demoReceipt(
      operationId,
      changed: true,
      targets: [_demoStamp('thread-mode-catalog', _threadModeCatalogRevision)],
      effect: EffectPoint.nextTurn,
    ),
  );

  StudioFailure _demoModeFailure(
    StudioFailureCode code,
    String message, {
    required bool retryable,
  }) => StudioFailure(
    code: code,
    message: message,
    retryable: retryable,
    correlationId: 'demo-mode-${newStudioCorrelationId()}',
  );

  WorkflowPreviewSnapshot _demoWorkflowPreview(WorkflowPreviewRequest request) {
    final workflow = request.document.definition.workflow;
    if (workflow == null) {
      return WorkflowPreviewSnapshot(
        accepted: false,
        message: 'This Mode has no workflow',
        path: request.path,
        terminal: false,
      );
    }
    final states = {for (final state in workflow.states) state.id: state};
    if (!states.containsKey(workflow.initialStateId)) {
      return WorkflowPreviewSnapshot(
        accepted: false,
        message: 'Initial state ${workflow.initialStateId} does not exist',
        path: request.path,
        terminal: false,
      );
    }
    final path = request.path.isEmpty
        ? <String>[workflow.initialStateId]
        : List<String>.of(request.path);
    for (final stateId in path) {
      if (!states.containsKey(stateId)) {
        return WorkflowPreviewSnapshot(
          accepted: false,
          message: 'Unknown state $stateId',
          path: path,
          terminal: false,
        );
      }
    }
    final target = request.targetStateId;
    if (target != null && target != path.last) {
      final planned = _demoTransitionPath(
        workflow,
        from: path.last,
        to: target,
      );
      if (planned == null) {
        return WorkflowPreviewSnapshot(
          accepted: false,
          message: 'No transition path reaches $target',
          currentState: states[path.last],
          path: path,
          terminal: states[path.last]!.kind == WorkflowStateKind.finalState,
        );
      }
      path.addAll(planned);
    }
    final current = states[path.last]!;
    return WorkflowPreviewSnapshot(
      accepted: true,
      message: 'Workflow preview reached ${current.title}',
      currentState: current,
      transitions: [
        for (final transition in workflow.transitions)
          if (transition.sourceStateId == current.id) transition,
      ],
      path: path,
      terminal: current.kind == WorkflowStateKind.finalState,
    );
  }

  List<String>? _demoTransitionPath(
    WorkflowDefinition workflow, {
    required String from,
    required String to,
  }) {
    final queue = <List<String>>[
      [from],
    ];
    final visited = <String>{from};
    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      final current = path.last;
      for (final transition in workflow.transitions) {
        if (transition.sourceStateId != current) continue;
        final next = transition.targetStateId;
        if (!visited.add(next)) continue;
        final candidate = [...path, next];
        if (next == to) return candidate.skip(1).toList();
        queue.add(candidate);
      }
    }
    return null;
  }

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    if (lspActivityLoop && topic == const LspTopic()) {
      _startLspActivityLoop();
    }
    var detached = false;
    var baselineEmitted = false;
    final pending = <ProductTopicEventPayload>[];
    late final StreamController<ProductTopicFrame> controller;
    late final void Function(ProductTopicEventPayload) sink;

    void detach() {
      if (detached) return;
      detached = true;
      final sinks = _topicSinks[topic];
      if (sinks != null) {
        sinks.remove(sink);
        if (sinks.isEmpty) _topicSinks.remove(topic);
      }
    }

    void receive(ProductTopicEventPayload payload) {
      if (detached) return;
      if (!baselineEmitted) {
        // 基线尚未交付：本 topic 事件先缓冲，保证先基线后增量（无关领域不进入本 receiver）。
        pending.add(payload);
        return;
      }
      _emitProductFrame(controller, topic, payload);
    }

    sink = receive;

    controller = StreamController<ProductTopicFrame>(
      onListen: () async {
        // receiver 先登记，再取得 canonical 基线：期间本 topic 的事件不丢。
        (_topicSinks[topic] ??= <void Function(ProductTopicEventPayload)>{})
            .add(receive);
        try {
          final baseline = await _demoTopicBaseline(topic);
          if (detached) return;
          baselineEmitted = true;
          controller.add(baseline);
          for (final payload in pending) {
            _emitProductFrame(controller, topic, payload);
          }
          pending.clear();
        } catch (error, stackTrace) {
          if (!detached) {
            controller.addError(error, stackTrace);
          }
        }
      },
      onCancel: () async {
        detach();
      },
    );
    return controller.stream;
  }

  /// 把一个 owner 事实发布给该 topic 的已登记 receiver；无接收者时不缓冲。
  void _publishProductPayload(ProductTopicEventPayload payload) {
    final sinks = _topicSinks[payload.topic];
    if (sinks == null || sinks.isEmpty) return;
    for (final sink in List.of(sinks)) {
      sink(payload);
    }
  }

  /// 把 payload 包装成 typed Data 帧交付给 receiver。
  void _emitProductFrame(
    StreamController<ProductTopicFrame> controller,
    ProductTopic topic,
    ProductTopicEventPayload payload,
  ) {
    _productEventSequence += 1;
    controller.add(
      ProductTopicDataFrame(
        topic: topic,
        event: ProductTopicEventEnvelope(
          eventId: 'demo-${_productEventSequence.toString().padLeft(6, '0')}',
          sequence: BigInt.from(_productEventSequence),
          createdAt: DateTime.now(),
          payload: payload,
        ),
      ),
    );
  }

  /// Demo 基线从当前内存事实派生；与生产路径一致按领域 revision 表达。
  Future<ProductTopicBaselineFrame> _demoTopicBaseline(
    ProductTopic topic,
  ) async {
    final ProductTopicBaselineState baseline = switch (topic) {
      ProjectDirectoryTopic() => ProjectDirectoryBaseline(
        _demoProjectDirectory(),
      ),
      ThreadDirectoryTopic() => ThreadDirectoryBaseline(_demoDirectoryPage()),
      AgentDirectoryTopic() => AgentDirectoryBaseline(_demoAgentDirectory()),
      SettingsConfigTopic() => SettingsConfigBaseline(_demoSettingsState()),
      ModelCatalogTopic() => ModelCatalogBaseline(_demoSettingsState()),
      RecoveryTopic() => RecoveryBaseline(_demoRecoveryState()),
      McpTopic() => McpBaseline(_demoMcpState()),
      LspTopic() => LspBaseline(_demoLspState()),
      SkillsTopic(:final projectId) => SkillsBaseline(
        _demoSkillsState(projectId, _skillsRevision),
      ),
      ThreadModeCatalogTopic() => ThreadModeCatalogBaseline(
        _demoThreadModeCatalog(),
      ),
      AccountUsageTopic() => AccountUsageBaseline(_demoAccountUsageState()),
      ModelPerformanceTopic() => ModelPerformanceBaseline(
        _demoModelPerformance(_fixtureTime),
      ),
      SessionCostsTopic(:final rootThreadId) => SessionCostsBaseline(
        _demoSessionCosts(rootThreadId),
      ),
      UpdaterTopic() => UpdaterBaseline(_demoUpdaterState()),
      PersistenceTopic() => PersistenceBaseline(_demoPersistenceState()),
      PersistenceQueueTopic() => PersistenceQueueBaseline(
        _demoPersistenceQueueState(),
      ),
      AgentProfilesTopic() => AgentProfilesBaseline(
        readAgentProfilesStateSync(),
      ),
      AcpAuthTopic() => AcpAuthBaseline(_demoAcpAuth.snapshot),
      BotsTopic() => BotsBaseline(_demoBotsState()),
    };
    final revision = switch (baseline) {
      ProjectDirectoryBaseline(:final state) => state.revision,
      ThreadDirectoryBaseline(:final page) => page.revision,
      AgentDirectoryBaseline(:final state) => state.revision,
      SettingsConfigBaseline(:final state) => state.revision,
      ModelCatalogBaseline(:final state) => state.modelCatalogRevision,
      RecoveryBaseline(:final state) => state.revision,
      McpBaseline(:final state) => state.revision,
      LspBaseline(:final state) => state.revision,
      SkillsBaseline(:final state) => state.revision,
      ThreadModeCatalogBaseline(:final state) => state.revision,
      AccountUsageBaseline(:final state) => state.revision,
      ModelPerformanceBaseline(:final state) => state.revision,
      SessionCostsBaseline(:final state) => state.revision,
      UpdaterBaseline(:final state) => state.revision,
      PersistenceBaseline(:final state) => state.revision,
      PersistenceQueueBaseline(:final state) => state.revision,
      AgentProfilesBaseline(:final state) => state.revision,
      AcpAuthBaseline(:final state) => state.revision,
      BotsBaseline(:final state) => state.revision,
    };
    return ProductTopicBaselineFrame(
      topic: topic,
      revision: revision,
      state: baseline,
    );
  }

  /// 周期发布 LSP 索引活动状态：40→55→70→85→100 后回到 idle，再循环。
  /// 每步递增 revision，保证 reducer 的 meta.isNewerThan 校验通过。
  void _startLspActivityLoop() {
    if (_lspActivityTimer != null) return;
    const cycle = [40, 55, 70, 85, 100, null];
    var index = 0;
    _lspActivityTimer = Timer.periodic(lspActivityStepDelay, (_) {
      _lspRevision += 1;
      final percentage = cycle[index];
      _lspActivityPercentage = percentage;
      _publishProductPayload(LspStateChangedPayload(_demoLspState()));
      index = (index + 1) % cycle.length;
    });
  }

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) {
    StreamSubscription<ThreadStreamFrame>? observation;
    late final StreamController<ThreadStreamFrame> controller;
    controller = StreamController<ThreadStreamFrame>(
      onListen: () {
        // Register before taking the current value, so no update can fall
        // between the baseline and observing future owner notifications.
        observation = _threadEvents.stream
            .where(
              (frame) => switch (frame) {
                ThreadSnapshotFrame(:final workspace) =>
                  workspace.thread.id == threadId,
                ThreadNotificationFrame(threadId: final id) => id == threadId,
                ThreadResyncRequiredFrame(threadId: final id) => id == threadId,
              },
            )
            .listen(controller.add, onError: controller.addError);
        try {
          controller.add(
            ThreadSnapshotFrame(
              workspace: _snapshotOf(_demoWorkspace(threadId)),
            ),
          );
        } catch (error, stack) {
          controller.addError(error, stack);
        }
      },
      onCancel: () => observation?.cancel(),
    );
    return controller.stream;
  }

  /// Thread 首帧只暴露当前状态：正文由内容连接的分页/尾部交付。
  ThreadWorkspace _snapshotOf(ThreadWorkspace workspace) {
    return workspace.copyWith(latestTurn: null);
  }

  /// 内容连接：正文（含流式）只经它交给 UI，与状态流相互独立。
  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) async {
    if (!_workspaces.containsKey(threadId)) {
      throw StateError('unknown demo thread $threadId');
    }
    final connection = _DemoTimelineConnection(this, threadId);
    final factory = _timelineFactory;
    // 工厂拿到的是真实连接：注入者只包装故障点，不会再次回到 openTimeline。
    return factory == null ? connection : factory(threadId, connection);
  }

  /// 测试专用：包装内容连接，用于故障注入（首帧失败、增量失败、EOF、慢打开）。
  ///
  /// 收到的是 demo 的真实连接，只替换故障点；状态流、目录与正文事实仍是 demo 的实现，
  /// 因此注入的是生命周期交错而不是另一套业务状态。
  Future<StudioTimelineConnection> Function(
    String threadId,
    StudioTimelineConnection connection,
  )?
  _timelineFactory;

  @visibleForTesting
  set timelineFactory(
    Future<StudioTimelineConnection> Function(
      String threadId,
      StudioTimelineConnection connection,
    )?
    factory,
  ) {
    _timelineFactory = factory;
  }

  /// 测试夹具：把 demo 的 canonical 内存条目写成给定内容。
  ///
  /// 真实运行时这些条目由脚本化的 prompt 流程写入；这里只准备内存条目，内容仍然只经
  /// [openTimeline] 的连接（有界尾部 + 页 + 详情）交付，不绕过内容契约。
  @visibleForTesting
  void seedTimelineItems(String threadId, Iterable<ThreadItemView> items) {
    for (final item in items) {
      _upsertChatItem(threadId, item);
    }
  }

  /// 测试夹具：撤下一条 demo canonical 条目（真实 `Remove` 的环境准备）。
  ///
  /// 与 [seedTimelineItems] 同一环境准备 seam：只改 demo 的 canonical 内存条目与通知，
  /// 发布仍只经 [openTimeline] 的连接，不新增业务删除 API。
  @visibleForTesting
  void retractTimelineItem(String threadId, String itemId) {
    final items = [...?_threadItems[threadId]];
    final index = items.indexWhere((item) => item.id == itemId);
    if (index < 0) return;
    items.removeAt(index);
    _threadItems[threadId] = items;
    _notifyItemsChanged(threadId);
    _lastItemChange[threadId] = _DemoItemChange(
      version: _contentVersionOf(threadId),
      itemId: itemId,
      removed: true,
    );
  }

  /// 最近一次内容变更的 typed 事实：身份 + 该条目的预览值（或删除）。
  _DemoItemChange? _lastItemChangeOf(String threadId) =>
      _lastItemChange[threadId];

  final Map<String, _DemoItemChange> _lastItemChange = {};

  /// 按活动身份读取完整详情。demo 没有独立的正文投影，活动本身即为可用事实。
  @override
  Future<ThreadActivityDetail> readThreadActivityDetail(
    String threadId,
    String activityId,
  ) async {
    final workspace = _workspaces[threadId];
    if (workspace == null) {
      throw StateError('unknown demo thread $threadId');
    }
    final activity = workspace.activity;
    if (activity == null) {
      return EndedThreadActivityDetail(
        threadId: threadId,
        activityId: activityId,
      );
    }
    if (activity.identity != activityId) {
      return SupersededThreadActivityDetail(
        activity: activity,
        requestedActivityId: activityId,
      );
    }
    return CurrentThreadActivityDetail(activity: activity);
  }

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) => _submitPrompt(
    threadId,
    input,
    expectedModelRouteRevision: expectedModelRouteRevision,
  );

  @override
  Future<List<AttachmentDraftView>> admitAttachmentDrafts(
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  ) async {
    return [
      for (final source in sources)
        _demoAttachmentDraft(source, ++_attachmentSequence),
    ].map((draft) {
      _attachmentDrafts[draft.id] = draft;
      return draft;
    }).toList();
  }

  @override
  Future<bool> removeAttachmentDraft(String draftId) async =>
      _attachmentDrafts.remove(draftId) != null;

  @override
  Future<Uint8List> readAttachmentDraft(String draftId) async {
    if (!_attachmentDrafts.containsKey(draftId)) {
      throw StateError('unknown demo attachment draft');
    }
    return Uint8List(0);
  }

  @override
  Future<Uint8List> readThreadAttachment(
    String threadId,
    String attachmentId,
  ) async => Uint8List(0);

  Future<SubmitPromptReceipt> _submitPrompt(
    String threadId,
    StudioPromptInput input, {
    int? expectedModelRouteRevision,
  }) async {
    final trimmed = input.text.trim();
    if (trimmed.isEmpty && input.attachmentDraftIds.isEmpty) {
      throw ArgumentError.value(input.text, 'text', 'empty');
    }
    final workspace = _workspaces[threadId];
    if (workspace == null) throw StateError('unknown demo thread $threadId');
    final route = workspace.runtime.modelRoute;
    if (expectedModelRouteRevision != null &&
        route?.revision != expectedModelRouteRevision) {
      throw const StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'The Thread model route changed before input admission',
        retryable: false,
        correlationId: 'demo-prompt-route-conflict',
      );
    }
    if (route == null || !route.available) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'The Thread model route is unavailable',
        retryable: false,
        correlationId: 'demo-prompt-route-unavailable',
      );
    }
    final activeTurn = workspace.activeTurn;
    if (activeTurn != null && activeTurn.state.isBusy) {
      _interruptDemoTurn(threadId, activeTurn.turnId);
    }
    // No await separates the route CAS and admission. Demo follows the Thread
    // route, rather than re-reading role defaults after the user's intent.
    _emitThreadUpdate(
      threadId,
      ThreadRuntimeUpdate(
        runtime: workspace.runtime.copyWith(modelId: route.modelId),
        todo: null,
      ),
    );
    final generation = _promptGenerations.update(
      threadId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final turnId = 'demo-turn-${++_turnSequence}';
    final now = DateTime.now();
    final receipt = SubmitPromptReceipt(
      threadId: threadId,
      inputId: input.inputId,
      cursor: workspace.revision + 1,
    );
    // 模拟服务同样只在成功受理后推进最近用户消息时间；拒绝路径在上方抛出、不推进。
    _advanceDemoLastUserMessage(threadId, now);
    _upsertChatItem(
      threadId,
      _messageItem(
        id: input.inputId,
        threadId: threadId,
        turnId: turnId,
        ordinal: _nextOrdinal(threadId),
        kind: ThreadItemKind.userMessage,
        text: trimmed,
        createdAt: now,
        attachments: [
          for (final id in input.attachmentDraftIds)
            if (_attachmentDrafts[id] case final draft?)
              ThreadAttachmentView(
                id: draft.id,
                modality: draft.modality,
                mediaType: draft.mediaType,
                filename: draft.filename,
                width: draft.width,
                height: draft.height,
                byteSize: draft.byteSize,
              ),
        ],
      ),
    );
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          inputId: input.inputId,
          threadId: threadId,
          revision: 0,
          state: RunningStudioTurnState(
            startedAt: now.millisecondsSinceEpoch ~/ 1000,
            activity: StudioTurnActivity.thinking,
          ),
          updatedAt: now,
        ),
      ),
    );
    // 脚本化活动：提交后进入“思考中”（等待 API / 开始 reasoning）。
    _emitActivity(
      threadId,
      turnId: turnId,
      inputId: input.inputId,
      kind: ThreadActivityKind.thinking,
    );
    unawaited(
      _completePrompt(
        threadId: threadId,
        turnId: turnId,
        trimmedPrompt: trimmed,
        generation: generation,
        startedAt: now,
      ),
    );
    return receipt;
  }

  Future<void> _completePrompt({
    required String threadId,
    required String turnId,
    required String trimmedPrompt,
    required int generation,
    required DateTime startedAt,
  }) async {
    await Future<void>.delayed(promptStartDelay);
    if (_promptGenerations[threadId] != generation) return;
    final reasoningId = '$turnId:reasoning';
    const reasoningSummary =
        '## Inspecting the request\n\nChecking the live ThreadItem projection.';
    const reasoningContent =
        'The account is folding summary and raw reasoning independently.';
    _upsertChatItem(
      threadId,
      ThreadItemView(
        id: reasoningId,
        threadId: threadId,
        turnId: turnId,
        ordinal: _nextOrdinal(threadId),
        revision: 0,
        createdAt: startedAt,
        updatedAt: startedAt,
        state: const ThreadThinkingItemStateView(
          summary: [],
          content: [],
          lifecycle: StreamingThreadContentView(),
        ),
      ),
    );
    await Future<void>.delayed(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: reasoningId,
      revision: 1,
      field: const ThreadThinkingSummaryFieldView(0),
      text: '## Inspecting',
    );
    await Future<void>.delayed(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: reasoningId,
      revision: 2,
      field: const ThreadThinkingSummaryFieldView(0),
      text: ' the request\n\nChecking the live ThreadItem projection.',
    );
    _appendChatContent(
      threadId,
      itemId: reasoningId,
      revision: 3,
      field: const ThreadThinkingContentFieldView(0),
      text: reasoningContent,
    );
    // 脚本化活动：reasoning 已有内容时显示“思考中”+最新非空逻辑行。
    _emitActivity(
      threadId,
      turnId: turnId,
      inputId: null,
      kind: ThreadActivityKind.thinking,
      summary: 'Checking the live ThreadItem projection.',
    );
    final liveReasoning = _itemsOf(threadId)
        .firstWhere((item) => item.id == reasoningId);
    final reasoningCompletedAt = DateTime.now();
    _upsertChatItem(
      threadId,
      liveReasoning.copyWith(
        revision: 4,
        updatedAt: reasoningCompletedAt,
        state: ThreadThinkingItemStateView(
          summary: const [reasoningSummary],
          content: const [reasoningContent],
          lifecycle: CompletedThreadContentView(reasoningCompletedAt),
        ),
      ),
    );
    final commentaryId = '$turnId:commentary';
    _upsertChatItem(
      threadId,
      ThreadItemView(
        id: commentaryId,
        threadId: threadId,
        turnId: turnId,
        ordinal: _nextOrdinal(threadId),
        revision: 0,
        createdAt: startedAt,
        updatedAt: startedAt,
        state: const ThreadTextItemStateView(
          channel: ThreadTextChannel.commentary,
          text: '',
          attachments: [],
          lifecycle: StreamingThreadContentView(),
        ),
      ),
    );
    _appendChatContent(
      threadId,
      itemId: commentaryId,
      revision: 1,
      field: const ThreadTextFieldView(),
      text: '正在逐段核对 Timeline',
    );
    await Future<void>.delayed(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: commentaryId,
      revision: 2,
      field: const ThreadTextFieldView(),
      text: ' 的 typed delta。',
    );
    final commentaryCompletedAt = DateTime.now();
    final liveCommentary = _itemsOf(threadId)
        .firstWhere((item) => item.id == commentaryId);
    _upsertChatItem(
      threadId,
      liveCommentary.copyWith(
        revision: 3,
        updatedAt: commentaryCompletedAt,
        state: ThreadTextItemStateView(
          channel: ThreadTextChannel.commentary,
          text: '正在逐段核对 Timeline 的 typed delta。',
          attachments: const [],
          lifecycle: CompletedThreadContentView(commentaryCompletedAt),
        ),
      ),
    );
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          threadId: threadId,
          revision: 1,
          state: RunningStudioTurnState(
            startedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            activity: StudioTurnActivity.runningTool,
          ),
          updatedAt: DateTime.now(),
        ),
      ),
    );
    // 脚本化活动：工具前台显示“执行中”+完整命令行预览。
    _emitActivity(
      threadId,
      turnId: turnId,
      inputId: null,
      kind: ThreadActivityKind.runningTool,
      summary: 'cargo test -p pl-model --test provider_wire',
    );
    final toolId = '$turnId:tool';
    _upsertChatItem(
      threadId,
      ThreadItemView(
        id: toolId,
        threadId: threadId,
        turnId: turnId,
        ordinal: _nextOrdinal(threadId),
        revision: 0,
        createdAt: startedAt,
        updatedAt: startedAt,
        state: ThreadToolItemStateView(
          invocation: ThreadToolInvocationView(
            toolCallId: '$turnId:tool-call',
            name: 'exec',
            arguments: '',
          ),
          lifecycle: const StartedThreadToolView(),
        ),
      ),
    );
    _appendChatContent(
      threadId,
      itemId: toolId,
      revision: 1,
      field: const ThreadToolArgumentsFieldView(),
      text: '{"command":"cargo test -p pl-model ',
    );
    await Future<void>.delayed(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: toolId,
      revision: 2,
      field: const ThreadToolArgumentsFieldView(),
      text: '--test provider_wire"}',
    );
    final streamedTool = _itemsOf(threadId)
        .firstWhere((item) => item.id == toolId);
    final streamedToolState = streamedTool.state as ThreadToolItemStateView;
    _upsertChatItem(
      threadId,
      streamedTool.copyWith(
        revision: 3,
        updatedAt: DateTime.now(),
        state: ThreadToolItemStateView(
          invocation: streamedToolState.invocation,
          lifecycle: const RunningThreadToolView(''),
        ),
      ),
    );
    _appendChatContent(
      threadId,
      itemId: toolId,
      revision: 4,
      field: const ThreadToolResultFieldView(),
      text: 'running widget tests...\n',
    );
    await Future<void>.delayed(promptToolDelay);
    if (_promptGenerations[threadId] != generation) return;
    _appendChatContent(
      threadId,
      itemId: toolId,
      revision: 5,
      field: const ThreadToolResultFieldView(),
      text: '[stderr] analyzer warnings: 0\n',
    );
    final runningTool = _itemsOf(threadId)
        .firstWhere((item) => item.id == toolId);
    final runningToolState = runningTool.state as ThreadToolItemStateView;
    final toolCompletedAt = DateTime.now();
    _upsertChatItem(
      threadId,
      runningTool.copyWith(
        revision: 6,
        updatedAt: toolCompletedAt,
        state: ThreadToolItemStateView(
          invocation: runningToolState.invocation,
          lifecycle: SucceededThreadToolView(
            toolCompletedAt,
            const ThreadToolOutputView(
              result:
                  'running widget tests...\n'
                  '[stderr] analyzer warnings: 0\n'
                  'All widget tests passed.',
              attachments: [],
              outputArtifacts: [],
            ),
          ),
        ),
      ),
    );
    final finalId = '$turnId:final';
    _upsertChatItem(
      threadId,
      ThreadItemView(
        id: finalId,
        threadId: threadId,
        turnId: turnId,
        ordinal: _nextOrdinal(threadId),
        revision: 0,
        createdAt: startedAt,
        updatedAt: startedAt,
        state: const ThreadTextItemStateView(
          channel: ThreadTextChannel.finalAnswer,
          text: '',
          attachments: [],
          lifecycle: StreamingThreadContentView(),
        ),
      ),
    );
    _appendChatContent(
      threadId,
      itemId: finalId,
      revision: 1,
      field: const ThreadTextFieldView(),
      text: 'Demo response for: **$trimmedPrompt**',
    );
    await Future<void>.delayed(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    const finalSuffix = '\n\n- reasoning、tool output 与 Plan 都直接来自 typed delta';
    _appendChatContent(
      threadId,
      itemId: finalId,
      revision: 2,
      field: const ThreadTextFieldView(),
      text: finalSuffix,
    );
    final finalCompletedAt = DateTime.now();
    final liveFinal = _itemsOf(threadId)
        .firstWhere((item) => item.id == finalId);
    _upsertChatItem(
      threadId,
      liveFinal.copyWith(
        revision: 3,
        updatedAt: finalCompletedAt,
        state: ThreadTextItemStateView(
          channel: ThreadTextChannel.finalAnswer,
          text: 'Demo response for: **$trimmedPrompt**$finalSuffix',
          attachments: const [],
          lifecycle: CompletedThreadContentView(finalCompletedAt),
        ),
      ),
    );
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          threadId: threadId,
          revision: 2,
          state: CompletedStudioTurnState(
            startedAt: null,
            completedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            completion: StudioTurnCompletion.normal,
          ),
          updatedAt: DateTime.now(),
        ),
      ),
    );
    // Turn 结束：清空当前活动。
    _clearActivity(threadId);
  }

  @override
  Future<InterruptTurnCommandReply> interruptTurn(
    String threadId,
    String turnId, {
    required OperationId operationId,
  }) async {
    final interrupted = _interruptDemoTurn(threadId, turnId);
    return InterruptTurnCommandReply(
      threadId: threadId,
      turnId: turnId,
      interrupted: interrupted,
      receipt: _demoReceipt(
        operationId,
        changed: interrupted,
        targets: const [],
        effect: EffectPoint.immediate,
        effective: false,
        requiresIdentityObservation: true,
      ),
    );
  }

  bool _interruptDemoTurn(String threadId, String turnId) {
    final active = _workspaces[threadId]?.activeTurn;
    if (active == null || !active.state.isBusy) return false;
    if (active.turnId != turnId) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Expected Turn does not match the active Turn',
        retryable: false,
        correlationId: 'demo-interrupt-turn-identity',
      );
    }
    _promptGenerations.update(
      threadId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          threadId: threadId,
          revision: 2,
          state: CancelledStudioTurnState(
            startedAt: null,
            requestedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            completedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            cause: const UserRequestedTurnCancellation(),
          ),
          updatedAt: DateTime.now(),
        ),
      ),
    );
    // 打断结束 Turn：清空当前活动。
    _clearActivity(threadId);
    return true;
  }

  @override
  Future<InteractionCommandReply> respondInteraction(
    String interactionId,
    InteractionResolutionCommand resolution, {
    required OperationId operationId,
  }) async {
    _ensureWorkspaceFixture();
    final facts = switch (resolution) {
      UserInputResolutionCommand(:final answers) => <Object?>[
        'user-input',
        {
          for (final answer in answers)
            answer.questionId: List<String>.of(answer.answers),
        },
      ],
      ToolApprovalResolutionCommand(:final decision, :final reason) =>
        <Object?>['tool-approval', decision, reason],
    };
    final previous = _resolvedInteractions[interactionId];
    if (previous != null) {
      if (!_sameDemoFacts(previous.resolution, facts)) {
        throw const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'Interaction already has a different terminal resolution',
          retryable: false,
          correlationId: 'demo-interaction-conflict',
        );
      }
      return InteractionCommandReply(
        interaction: previous.interaction,
        receipt: _demoReceipt(
          operationId,
          changed: false,
          targets: const [],
          effect: EffectPoint.immediate,
          requiresIdentityObservation: true,
        ),
      );
    }
    final interaction = [
      for (final workspace in _workspaces.values) ...workspace.interactions,
    ].where((item) => item.id == interactionId).firstOrNull;
    if (interaction == null) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Interaction is unavailable',
        retryable: false,
        correlationId: 'demo-interaction-not-found',
      );
    }
    _resolvedInteractions[interactionId] = (
      interaction: interaction,
      resolution: facts,
    );
    // Bound terminal receipts without inventing a new active interaction owner.
    while (_resolvedInteractions.length > 128) {
      _resolvedInteractions.remove(_resolvedInteractions.keys.first);
    }
    _emitThreadUpdate(
      interaction.threadId,
      ThreadInteractionUpdate(interaction: interaction, pending: false),
    );
    if (interaction.kind == InteractionKind.userInput) {
      _advanceDemoLastUserMessage(interaction.threadId, DateTime.now());
    }
    return InteractionCommandReply(
      interaction: interaction,
      receipt: _demoReceipt(
        operationId,
        changed: true,
        targets: const [],
        effect: EffectPoint.immediate,
        requiresIdentityObservation: true,
      ),
    );
  }

  @override
  Future<SettingsCommandReply> saveRuntimePermissionMode(
    int expectedSettingsRevision,
    PermissionMode mode, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    _permissionMode = mode;
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> saveAccount(
    int expectedSettingsRevision,
    AccountCommand command, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final current = before;
    final converted = _providersFromCommands(
      [command],
      previous: current.accounts,
      catalog: _accountCatalog,
    );
    _accounts = [
      for (final account in current.accounts)
        if (account.id != command.id) account,
      ...converted,
    ];
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> setDefaultAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    if (!before.accounts.any((account) => account.id == accountId)) {
      throw StateError('Account is unavailable: $accountId');
    }
    _defaultAccountId = accountId;
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsCommandReply> removeAccountModel(
    int expectedSettingsRevision,
    String accountId,
    String modelId,
  ) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    if (modelId.trim().isEmpty) {
      throw StateError('Account modelId must not be empty');
    }
    final accounts = [
      for (final account in before.accounts)
        if (account.id == accountId)
          _demoRemoveManualModel(account, modelId)
        else
          account,
    ];
    if (!accounts.any((account) => account.id == accountId)) {
      throw StateError('unknown demo account: $accountId');
    }
    _accounts = accounts;
    _settingsRevision += 1;
    return _demoSettingsReply(
      OperationId('remove-account-modelId:$accountId:$modelId'),
      before,
    );
  }

  @override
  Future<SettingsCommandReply> removeAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
    String? replacementAccountId,
  }) async {
    final before = _demoSettingsState();
    _checkSettingsRevision(expectedSettingsRevision);
    final current = before;
    if (current.accounts.length <= 1) {
      throw StateError('At least one account is required');
    }
    final replacement =
        replacementAccountId ??
        current.accounts.firstWhere((account) => account.id != accountId).id;
    if (!current.accounts.any((account) => account.id == replacement)) {
      throw StateError('Replacement account is unavailable: $replacement');
    }
    _accounts = [
      for (final account in current.accounts)
        if (account.id != accountId) account,
    ];
    _defaultAccountId = _defaultAccountId == accountId
        ? replacement
        : _defaultAccountId;
    _settingsRevision += 1;
    return _demoSettingsReply(operationId, before);
  }

  @override
  Future<SettingsStateSnapshot> readSettingsState() async =>
      _demoSettingsState();

  @override
  Future<AccountUsageStateSnapshot> checkAccountUsage(String accountId) async {
    final accounts = _accounts ?? [_demoDefaultAccount()];
    final account = accounts.where((item) => item.id == accountId).firstOrNull;
    if (account != null) {
      _accountUsages[accountId] = _demoAccountUsage(account);
    } else {
      _accountUsages.remove(accountId);
    }
    _accountUsageRevision += 1;
    final state = _demoAccountUsageState();
    _publishProductPayload(AccountUsageStateChangedPayload(state));
    return state;
  }

  @override
  Future<SkillsStateSnapshot> readSkillsState(String projectId) async {
    return _archivedProjectIds.contains(projectId)
        ? _demoSkillsState(projectId, 0, skills: const [])
        : _demoSkillsState(projectId, _skillsRevision);
  }

  @override
  Future<SkillsStateSnapshot> discoverSkills(String projectId) async {
    _skillsRevision += 1;
    final state = await readSkillsState(projectId);
    _publishProductPayload(SkillsStateChangedPayload(state));
    return state;
  }

  @override
  Future<SkillSearchResultView> searchSkills(
    String projectId,
    String query, {
    int limit = 50,
  }) async {
    final snapshot = await readSkillsState(projectId);
    final normalizedQuery = query.trim().toLowerCase();
    final allMatches = snapshot.summaries
        .where(
          (skill) =>
              skill.name.toLowerCase().contains(normalizedQuery) ||
              skill.description.toLowerCase().contains(normalizedQuery),
        )
        .toList();
    return SkillSearchResultView(
      projectId: projectId,
      catalogRevision: snapshot.catalogRevision,
      matches: allMatches.take(limit).toList(),
      truncated: allMatches.length > limit,
    );
  }

  @override
  Future<McpStateSnapshot> readMcpState() async => _demoMcpState();

  @override
  Future<McpStateSnapshot> resetMcpServer(String serverId) async {
    _mcpRevision += 1;
    return _mcpWriteResult();
  }

  @override
  Future<McpStateSnapshot> resetAllMcp() async {
    _mcpRevision += 1;
    return _mcpWriteResult();
  }

  @override
  Future<LspStateSnapshot> readLspState() async => _demoLspState();

  @override
  Future<LspStateSnapshot> probeLspServer(String projectId) async {
    _lspRevision += 1;
    return _lspWriteResult();
  }

  @override
  Future<LspStateSnapshot> repairLspServer(
    String projectId,
    String serverId,
  ) async {
    _lspRevision += 1;
    return _lspWriteResult();
  }

  @override
  Future<LspStateSnapshot> resetLspServer(
    String projectId,
    String serverId,
  ) async {
    _lspRevision += 1;
    return _lspWriteResult();
  }

  @override
  Future<LspStateSnapshot> resetLspWorkspace(String projectId) async {
    _lspRevision += 1;
    return _lspWriteResult();
  }

  BotsStateSnapshot _demoBotsState() {
    return BotsStateSnapshot(
      revision: _botsRevision,
      updatedAt: 0,
      bots: List<BotSnapshot>.unmodifiable(_bots),
      registration: _registration,
      pendingCredentialOperations:
          List<BotPendingCredentialOperation>.unmodifiable(
            _pendingCredentialOps,
          ),
    );
  }

  BotsStateSnapshot _botsWriteResult() {
    _botsRevision += 1;
    final state = _demoBotsState();
    _publishProductPayload(BotsStateChangedPayload(state));
    return state;
  }

  BotsCommandReply _botsReply(
    OperationId operationId, {
    required bool changed,
  }) {
    final snapshot = _botsWriteResult();
    return BotsCommandReply(
      snapshot: snapshot,
      receipt: _demoReceipt(
        operationId,
        changed: changed,
        targets: [_demoStamp('bots', snapshot.revision)],
        effect: EffectPoint.immediate,
      ),
      stamp: _demoStamp('bots', snapshot.revision),
    );
  }

  BotSnapshot? _findBot(String id) {
    for (final bot in _bots) {
      if (bot.id == id) return bot;
    }
    return null;
  }

  void _replaceBot(BotSnapshot next) {
    final index = _bots.indexWhere((bot) => bot.id == next.id);
    if (index < 0) {
      _bots.add(next);
    } else {
      _bots[index] = next;
    }
  }

  @override
  Future<BotsStateSnapshot> readBots() async => _demoBotsState();

  @override
  Future<BotsCommandReply> saveBot(SaveBotRequest request) async {
    final existing = request.botId == null ? null : _findBot(request.botId!);
    if (existing != null &&
        existing.configRevision != request.expectedConfigRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Bot config revision conflict',
        retryable: true,
        correlationId: request.operationId,
      );
    }
    final id = request.botId ?? 'bot-${_bots.length + 1}';
    final credential = switch (request.secret) {
      BotSecretReplace() => BotCredentialAvailability.stored,
      BotSecretClear() => BotCredentialAvailability.missing,
      BotSecretPreserve() =>
        existing?.credential ?? BotCredentialAvailability.missing,
    };
    _replaceBot(
      BotSnapshot(
        id: id,
        name: request.name,
        projectId: request.projectId,
        appId: request.appId,
        platform: BotPlatform.feishuChina,
        enabled: request.enabled,
        toolsEnabled: request.toolsEnabled,
        configRevision: (existing?.configRevision ?? 0) + 1,
        trustedOpenIds: existing?.trustedOpenIds ?? const [],
        trustedChatIds: existing?.trustedChatIds ?? const [],
        connection: existing?.connection ?? const BotConnectionDisabled(),
        credential: credential,
        pairing: existing?.pairing ?? const [],
        canChangeProject: existing?.canChangeProject ?? true,
        canChangeAppId: existing?.canChangeAppId ?? true,
        createdAt: existing?.createdAt ?? 0,
        updatedAt: 1,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> startBotRegistration(
    StartBotRegistrationRequest request,
  ) async {
    final attemptId = 'attempt-${request.operationId}';
    _registration = BotRegistrationAttempt(
      attemptId: attemptId,
      name: request.name,
      projectId: request.projectId,
      status: BotRegistrationWaiting(
        attemptId: attemptId,
        verificationUrl: 'https://accounts.feishu.cn/demo-registration',
        expiresAt: 1,
        intervalSeconds: 5,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> cancelBotRegistration(
    CancelBotRegistrationRequest request,
  ) async {
    final current = _registration;
    if (current != null && current.status is BotRegistrationCommitting) {
      throw StudioFailure(
        code: StudioFailureCode.busy,
        message: 'Registration is committing',
        retryable: false,
        correlationId: request.operationId,
      );
    }
    if (current != null && current.attemptId == request.attemptId) {
      _registration = BotRegistrationAttempt(
        attemptId: current.attemptId,
        name: current.name,
        projectId: current.projectId,
        status: BotRegistrationCancelled(attemptId: current.attemptId),
        completedBotId: current.completedBotId,
      );
    }
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> setBotEnabled(SetBotEnabledRequest request) async {
    final existing = _findBot(request.botId);
    if (existing == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Bot not found',
        retryable: false,
        correlationId: request.operationId,
      );
    }
    if (existing.configRevision != request.expectedConfigRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Bot config revision conflict',
        retryable: true,
        correlationId: request.operationId,
      );
    }
    _replaceBot(
      BotSnapshot(
        id: existing.id,
        name: existing.name,
        projectId: existing.projectId,
        appId: existing.appId,
        platform: existing.platform,
        enabled: request.enabled,
        toolsEnabled: existing.toolsEnabled,
        configRevision: existing.configRevision + 1,
        trustedOpenIds: existing.trustedOpenIds,
        trustedChatIds: existing.trustedChatIds,
        connection: request.enabled
            ? const BotConnectionConnected()
            : const BotConnectionDisabled(),
        credential: existing.credential,
        credentialOperation: existing.credentialOperation,
        pairing: existing.pairing,
        diagnostic: existing.diagnostic,
        canChangeProject: existing.canChangeProject,
        canChangeAppId: existing.canChangeAppId,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt + 1,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> retryBotConnection(
    RetryBotConnectionRequest request,
  ) async {
    final existing = _findBot(request.botId);
    if (existing == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Bot not found',
        retryable: false,
        correlationId: request.operationId,
      );
    }
    _replaceBot(
      BotSnapshot(
        id: existing.id,
        name: existing.name,
        projectId: existing.projectId,
        appId: existing.appId,
        platform: existing.platform,
        enabled: existing.enabled,
        toolsEnabled: existing.toolsEnabled,
        configRevision: existing.configRevision,
        trustedOpenIds: existing.trustedOpenIds,
        trustedChatIds: existing.trustedChatIds,
        connection: existing.enabled
            ? const BotConnectionConnected()
            : const BotConnectionDisabled(),
        credential: existing.credential,
        credentialOperation: existing.credentialOperation,
        pairing: existing.pairing,
        diagnostic: existing.diagnostic,
        canChangeProject: existing.canChangeProject,
        canChangeAppId: existing.canChangeAppId,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt + 1,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> setBotTrustedUser(
    SetBotTrustedUserRequest request,
  ) async {
    final existing = _findBot(request.botId);
    if (existing == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Bot not found',
        retryable: false,
        correlationId: request.operationId,
      );
    }
    if (existing.configRevision != request.expectedConfigRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Bot config revision conflict',
        retryable: true,
        correlationId: request.operationId,
      );
    }
    final trusted = [...existing.trustedOpenIds];
    if (request.trusted) {
      if (!trusted.contains(request.openId)) trusted.add(request.openId);
    } else {
      trusted.remove(request.openId);
    }
    _replaceBot(
      BotSnapshot(
        id: existing.id,
        name: existing.name,
        projectId: existing.projectId,
        appId: existing.appId,
        platform: existing.platform,
        enabled: existing.enabled,
        toolsEnabled: existing.toolsEnabled,
        configRevision: existing.configRevision + 1,
        trustedOpenIds: List<String>.unmodifiable(trusted),
        trustedChatIds: existing.trustedChatIds,
        connection: existing.connection,
        credential: existing.credential,
        credentialOperation: existing.credentialOperation,
        pairing: [
          for (final item in existing.pairing)
            if (item.openId != request.openId) item,
        ],
        diagnostic: existing.diagnostic,
        canChangeProject: existing.canChangeProject,
        canChangeAppId: existing.canChangeAppId,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt + 1,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotsCommandReply> setBotTrustedChat(
    SetBotTrustedChatRequest request,
  ) async {
    final existing = _findBot(request.botId);
    if (existing == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'Bot not found',
        retryable: false,
        correlationId: request.operationId,
      );
    }
    if (existing.configRevision != request.expectedConfigRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Bot config revision conflict',
        retryable: true,
        correlationId: request.operationId,
      );
    }
    final trusted = [...existing.trustedChatIds];
    if (request.trusted) {
      if (!trusted.contains(request.chatId)) trusted.add(request.chatId);
    } else {
      trusted.remove(request.chatId);
    }
    _replaceBot(
      BotSnapshot(
        id: existing.id,
        name: existing.name,
        projectId: existing.projectId,
        appId: existing.appId,
        platform: existing.platform,
        enabled: existing.enabled,
        toolsEnabled: existing.toolsEnabled,
        configRevision: existing.configRevision + 1,
        trustedOpenIds: existing.trustedOpenIds,
        trustedChatIds: List<String>.unmodifiable(trusted),
        connection: existing.connection,
        credential: existing.credential,
        credentialOperation: existing.credentialOperation,
        pairing: existing.pairing,
        diagnostic: existing.diagnostic,
        canChangeProject: existing.canChangeProject,
        canChangeAppId: existing.canChangeAppId,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt + 1,
      ),
    );
    return _botsReply(OperationId(request.operationId), changed: true);
  }

  @override
  Future<BotConversationPage> listBotConversations(
    ListBotConversationsRequest request,
  ) async {
    final conversations = _botConversations[request.botId] ?? const [];
    return BotConversationPage(
      botId: request.botId,
      conversations: conversations,
    );
  }

  @override
  Future<BotMessagePage> readBotMessages(ReadBotMessagesRequest request) async {
    final key = '${request.botId}/${request.chatId}';
    return BotMessagePage(
      botId: request.botId,
      chatId: request.chatId,
      messages: _botMessages[key] ?? const [],
    );
  }

  @override
  Future<BotSendResult> sendBotMessage(SendBotMessageRequest request) async {
    return BotSendResult(
      operationId: request.operationId,
      botId: request.botId,
      chatId: request.chatId,
      status: BotSendStatus.succeeded,
      segments: [BotSendSegment(index: 0, status: BotSendStatus.succeeded)],
      receipt: _demoReceipt(
        OperationId(request.operationId),
        changed: true,
        targets: const [],
        effect: EffectPoint.immediate,
      ),
    );
  }

  @override
  Future<BotConversationThreadReply> createBotConversationThread(
    CreateBotConversationThreadRequest request,
  ) async {
    final key = '${request.botId}/${request.chatId}';
    final existing = _botBindings[key];
    if (existing != null &&
        existing.revision != request.expectedBindingRevision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'Bot binding revision conflict',
        retryable: true,
        correlationId: request.operationId,
      );
    }
    final binding = BotConversationThreadBinding(
      botId: request.botId,
      chatId: request.chatId,
      projectId: _findBot(request.botId)?.projectId ?? '',
      threadId: existing?.threadId ?? 'thread-bot-${request.chatId}',
      revision: (existing?.revision ?? 0) + 1,
      state: BotConversationThreadState.bound,
    );
    _botBindings[key] = binding;
    return BotConversationThreadReply(
      binding: binding,
      receipt: _demoReceipt(
        OperationId(request.operationId),
        changed: true,
        targets: const [],
        effect: EffectPoint.immediate,
      ),
    );
  }

  McpStateSnapshot _mcpWriteResult() {
    final state = _demoMcpState();
    _publishProductPayload(McpStateChangedPayload(state));
    return state;
  }

  LspStateSnapshot _lspWriteResult() {
    _lspActivityPercentage = 40;
    final state = _demoLspState();
    _publishProductPayload(LspStateChangedPayload(state));
    return state;
  }

  McpStateSnapshot _demoMcpState() {
    return McpStateSnapshot.fromState(
      state: _demoReadyResource(_mcpRevision, const McpStateData()),
    );
  }

  LspStateSnapshot _demoLspState() {
    final percentage = _lspActivityPercentage;
    if (percentage == null) {
      return LspStateSnapshot.fromState(
        state: _demoReadyResource(_lspRevision, const LspStateData()),
      );
    }
    return LspStateSnapshot.fromState(
      state: _demoReadyResource(
        _lspRevision,
        LspStateData(
          activeServers: const ['rust-analyzer'],
          servers: [
            LspServerStateView(
              id: 'rust-analyzer',
              displayName: 'rust-analyzer',
              state: LspAvailableState(
                checkedAt: 0,
                diagnosticCount: 0,
                activity: LspIndexingActivity(
                  title: 'Roots Scanned',
                  message: '${(408 * percentage / 100).round()}/408',
                  percentage: percentage,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _checkSettingsRevision(int expected) {
    if (expected != _settingsRevision) {
      throw StateError(
        'settings revision conflict: expected $expected, actual $_settingsRevision',
      );
    }
  }

  AccountSettingsView _demoRemoveManualModel(
    AccountSettingsView account,
    String modelId,
  ) {
    final target = account.models
        .where((model) => model.modelId == modelId)
        .firstOrNull;
    if (target == null || target.origin != ModelOrigin.manual) {
      throw StateError('unknown demo manual modelId: ${account.id} / $modelId');
    }
    final models = [
      for (final model in account.models)
        if (model.modelId != modelId) model,
    ];
    final connections = {...account.modelConnectionModes}..remove(modelId);
    final limits = {...account.autoCompactLimits}..remove(modelId);
    return account.copyWith(
      models: models,
      modelConnectionModes: connections,
      autoCompactLimits: limits,
      modelCount: '${models.length}',
      usageLabel: models.isEmpty
          ? account.defaultModelId
          : '${models.length} models',
    );
  }

  AccountModelView _findDemoModel(
    List<AccountSettingsView> accounts,
    String accountId,
    String modelId,
  ) {
    final account = accounts.where((item) => item.id == accountId).firstOrNull;
    if (account == null) {
      throw StateError('unknown demo account: $accountId');
    }
    final selected = account.models
        .where((candidate) => candidate.modelId == modelId)
        .firstOrNull;
    if (selected == null) {
      throw StateError('unknown demo modelId: $accountId / $modelId');
    }
    return selected;
  }

  /// 通知某 Thread 的内容连接：条目发生真实变化（正文只由内容尾部交给消费方）。
  void _notifyItemsChanged(String threadId) {
    // 每次内容变化推进该 Thread 自己的内容版本；Thread 状态 revision 不受影响。
    _contentVersions[threadId] = _contentVersionOf(threadId) + 1;
    _chatChangeSeq[threadId] = (_chatChangeSeq[threadId] ?? 0) + 1;
    final waiters = _chatWaiters.remove(threadId);
    if (waiters == null) return;
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Future<void> _awaitItemsChanged(String threadId, int from) async {
    while ((_chatChangeSeq[threadId] ?? 0) == from) {
      final waiter = Completer<void>();
      (_chatWaiters[threadId] ??= []).add(waiter);
      await waiter.future;
    }
  }

  /// demo 模拟一次 Thread 状态更新。
  ///
  /// 状态流只承载 Turn / 活动 / 交互 / 运行时——与生产投影同一契约；**条目与正文不在
  /// 这里**，它们写进内存条目，并由 Timeline 内容连接（`openTimeline` →
  /// `_DemoTimelineConnection`）按同一有界尾部契约交付。
  void _emitThreadUpdate(String threadId, ThreadWorkspaceUpdate update) {
    final workspace = _workspaces[threadId];
    if (workspace == null) return;
    final revision = workspace.revision + 1;
    // Turn revisions share the Thread event sequence, just like the native projector.
    if (update case ThreadTurnUpdate(:final turn)) {
      update = ThreadTurnUpdate(
        StudioTurnView(
          turnId: turn.turnId,
          inputId: turn.inputId ?? workspace.activeTurn?.inputId,
          threadId: threadId,
          revision: revision,
          state: turn.state,
          updatedAt: turn.updatedAt,
        ),
      );
    }
    final ThreadWorkspace updated = switch (update) {
      ThreadTurnUpdate(:final turn) => workspace.copyWith(
        revision: revision,
        activeTurn: turn.state.isBusy ? turn : null,
      ),
      // 活动与生产一样只从 typed 活动事实进入状态。
      ThreadActivityUpdate(:final activity) => workspace.copyWith(
        revision: revision,
        activity: activity,
      ),
      ThreadRuntimeUpdate(:final runtime, :final todo) => workspace.copyWith(
        revision: revision,
        runtime: runtime,
        todo: todo,
      ),
      // 存储状态与生产一样只从 typed 事实进入状态。
      ThreadStorageUpdate(:final storage) => workspace.copyWith(
        revision: revision,
        storage: storage,
      ),
      ThreadInteractionUpdate(:final interaction, :final pending) =>
        _demoUpdateInteraction(workspace, revision, interaction, pending),
    };
    _workspaces[threadId] = updated;
    _threadEvents.add(
      ThreadNotificationFrame(
        threadId: threadId,
        revision: revision,
        update: update,
      ),
    );
    if (update case ThreadTurnUpdate(:final turn)) {
      final id = 'turn:${turn.turnId.length}:${turn.turnId}';
      final previous = _threadItems[threadId]
          ?.where((item) => item.id == id)
          .firstOrNull;
      _upsertChatItem(
        threadId,
        ThreadItemView(
          id: id,
          threadId: threadId,
          turnId: turn.turnId,
          ordinal: previous?.ordinal ?? _nextOrdinal(threadId),
          revision: turn.revision,
          createdAt: previous?.createdAt ?? turn.updatedAt,
          updatedAt: turn.updatedAt,
          state: ThreadTurnItemStateView(turn.state, inputId: turn.inputId),
        ),
      );
    }
  }

  /// 把一条条目写入内存内容：条目只属于内容连接，不推进线程状态水位。
  void _upsertChatItem(String threadId, ThreadItemView item) {
    if (!_workspaces.containsKey(threadId)) return;
    // demo 的内存条目没有独立的执行终态事件：状态进入终态即视为内容终态。
    final entry = item.executionTerminal
        ? item
        : item.copyWith(executionTerminal: item.isTerminal);
    final items = [...?_threadItems[threadId]];
    final index = items.indexWhere((existing) => existing.id == entry.id);
    if (index < 0) {
      items.add(entry);
    } else {
      items[index] = entry;
    }
    items.sort(_compareThreadItems);
    _threadItems[threadId] = items;
    _notifyItemsChanged(threadId);
    // 通知携带本次 typed 变更的身份与预览值：内容连接无需扫描全历史就能表达差量。
    _lastItemChange[threadId] = _DemoItemChange(
      version: _contentVersionOf(threadId),
      itemId: entry.id,
      item: entry,
    );
  }

  List<ThreadItemView> _itemsOf(String threadId) =>
      _threadItems[threadId] ?? const <ThreadItemView>[];

  int _contentVersionOf(String threadId) => _contentVersions[threadId] ?? 0;

  /// 应用一帧 typed `UpdateItem` 字段变化，与 `BridgeViewChange::UpdateItem` 同形状：
  /// 按字段身份落到条目的 domain 字段，本地基线必须等于当前 revision；条目缺失、
  /// revision 不连续或已终态接受流式变化时丢弃（真实链路会重建权威窗口）。
  void _applyChatFieldUpdates(
    String threadId, {
    required String itemId,
    required int revision,
    required List<ThreadFieldUpdateView> fields,
  }) {
    if (!_workspaces.containsKey(threadId)) return;
    final items = [...?_threadItems[threadId]];
    final index = items.indexWhere((item) => item.id == itemId);
    if (index < 0) return;
    final current = items[index];
    final next = current.applyFieldUpdates(
      fields: fields,
      expectedRevision: current.revision,
      revision: revision,
      omittedUnits: current.bodyOmittedUnits,
      saved: current.saved,
      terminal: current.executionTerminal,
    );
    if (next == null) return;
    items[index] = next;
    _threadItems[threadId] = items;
    _notifyItemsChanged(threadId);
    _lastItemChange[threadId] = _DemoItemChange(
      version: _contentVersionOf(threadId),
      itemId: next.id,
      item: next,
    );
  }

  /// 单字段 append 的便捷入口（demo 脚本只追加正文）。
  void _appendChatContent(
    String threadId, {
    required String itemId,
    required int revision,
    required ThreadContentFieldView field,
    required String text,
  }) {
    _applyChatFieldUpdates(
      threadId,
      itemId: itemId,
      revision: revision,
      fields: [
        ThreadFieldUpdateView(
          field: field,
          change: AppendThreadFieldChangeView(text),
        ),
      ],
    );
  }

  /// demo 脚本化的当前活动：作为 typed `ActivityChanged` 状态走状态流。
  void _emitActivity(
    String threadId, {
    required String turnId,
    required String? inputId,
    required ThreadActivityKind kind,
    String summary = '',
  }) {
    _emitThreadUpdate(
      threadId,
      ThreadActivityUpdate(
        activity: ThreadActivityView(
          threadId: threadId,
          identity: 'activity:$turnId:${kind.name}',
          revision: 0,
          turnId: turnId,
          inputId: inputId,
          kind: kind,
          summary: summary,
        ),
      ),
    );
  }

  /// Turn 结束或打断：清空当前活动（`activity == null`）。
  void _clearActivity(String threadId) {
    _emitThreadUpdate(threadId, const ThreadActivityUpdate(activity: null));
  }

  int _nextOrdinal(String threadId) {
    final items = _itemsOf(threadId);
    return items.isEmpty
        ? 0
        : items
                  .map((item) => item.ordinal)
                  .reduce((left, right) => left > right ? left : right) +
              1;
  }
}

/// 一次内容变更的 typed 事实：推送它的身份、新预览值或“已删除”。
///
/// 这就是 demo 的“producer 通知”：内容连接不需要为每次交付重建全历史版本表。
final class _DemoItemChange {
  const _DemoItemChange({
    required this.version,
    required this.itemId,
    this.item,
    this.removed = false,
  });

  final int version;
  final String itemId;
  final ThreadItemView? item;
  final bool removed;
}

/// 一条已封顶预览：预览条目、逐字段账目、合成后的省略字节数与本次保守计量总量
/// （不可缩结构 + 实际保留正文）。
typedef _DemoPreview = ({
  ThreadItemView item,
  List<StudioTimelineDetailRef> details,
  int omitted,
  int accountedBytes,
});

/// 一条**已成功计量**的分页条目：完整 canonical 条目与它的有界预览。
final class _DemoStagedItem {
  const _DemoStagedItem(this.full, this.preview);

  final ThreadItemView full;
  final _DemoPreview preview;
}

/// 一次页/基线查询的暂存结果。
///
/// 预览与计量全部成功后才由连接提交到自己的连续性副本：中途 `Overloaded` 不会留下
/// 半清空的副本，也不会推进已交付水位（design/26 §预算计量边界）。
final class _DemoPageStage {
  const _DemoPageStage({
    required this.items,
    required this.before,
    required this.hasOlder,
  });

  /// 按 canonical 顺序升序排列，最早一条是 `before` 指向的边界。
  final List<_DemoStagedItem> items;
  final String? before;
  final bool hasOlder;
}

/// 单条预览无法容纳不可省略事实时的 typed 失败。
///
/// 结构、稳定身份与权威判别标记都不允许截断或删除，因此只能明确报告资源限制；
/// 这不是 EOF，也不是可重试的瞬时压力（design/26 §预算计量边界）。
StudioFailure _timelineBudgetExceeded() => const StudioFailure(
  code: StudioFailureCode.overloaded,
  message: 'The timeline item cannot fit the preview budget',
  retryable: false,
  correlationId: 'demo-timeline-item-overloaded',
);

/// 单条条目的预览字节额度：正文（含问答、推理、原始记录）共享一份，工具参数/结果从中
/// 各取至多 4 KiB。额度耗尽只会让对应预览变空，不会让字段消失。
final class _PreviewBudget {
  _PreviewBudget(this.remaining);
  int remaining;

  /// 申请 [max] 字节额度并返回实际交付的预览：**只按实际保留的 UTF-8 字节计费**，
  /// 短字段用不完的额度留给后续字段（design/26 §26.5）。
  String cap(String text, int max) {
    if (remaining <= 0 || max <= 0) return '';
    final granted = max < remaining ? max : remaining;
    final bytes = utf8.encode(text);
    if (bytes.length <= granted) {
      remaining -= bytes.length;
      return text;
    }
    var end = granted;
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
      end -= 1;
    }
    if (end == 0) return '';
    remaining -= end;
    return utf8.decode(bytes.sublist(0, end));
  }

  /// 为小的固定判别标记预留字节：判别事实优先于自由正文。
  ///
  /// 预留是硬约束：额度不足时直接报告资源限制，绝不静默回落到 0 之后又把标记原样
  /// 交付成超预算内容（design/26 §预算计量边界）。
  void reserve(int bytes) {
    if (bytes <= 0) return;
    if (bytes > remaining) throw _timelineBudgetExceeded();
    remaining -= bytes;
  }
}

/// demo 的内容连接：正文完全来自内存条目，变化由 [_DemoTimelineConnection.next] 唤醒。
///
/// 交付形状与原生连接一致：首帧是**一致基线**，之后按身份交付 `Add`/`UpdateItem`/`Remove`
/// 差量；无法用差量表达的条目变化退回显式 `Resync`，绝不在客户端的基线之外伪造窗口。
/// 页与详情是自包含查询：预览按产品预算封顶（正文 32 KiB，工具参数/结果各 4 KiB，
/// 判别标记优先），详情按 UTF-8 边界切块并给出绑定 Thread/item/field/revision 的不透明
/// continuation，让客户端走真实的多块路径。
class _DemoTimelineConnection implements StudioTimelineConnection {
  _DemoTimelineConnection(this._api, this._threadId)
    : _subscriptionId = 'demo-${newStudioCorrelationId()}';

  static const int _pageSize = 32;
  static const int _continuityLimit = 100;

  /// 单条预览总量上限（不可缩结构 + 实际保留正文）。
  static const int _itemPreviewLimitBytes = 256 * 1024;

  /// 一次页/基线查询的总量上限；按最新端累计，提前截页时保留真实更早游标。
  static const int _pageLimitBytes = 2 * 1024 * 1024;

  /// 连续性副本的总量上限；与条数上限同时生效。
  static const int _continuityLimitBytes = 8 * 1024 * 1024;

  /// 详情块的默认大小与硬上界：默认 64 KiB，显式允许 4..262144 字节（design/26 §26.2）。
  static const int _defaultDetailBytes = 64 * 1024;
  static const int _maxDetailBytes = 256 * 1024;

  final DemoStudioTransport _api;
  final String _threadId;
  final String _subscriptionId;

  /// 已交付给消费者的**预览**条目（≤ [_continuityLimit] 条）：本连接自己的连续性副本。
  final Map<String, ThreadItemView> _delivered = {};

  /// 已交付条目的逐字段预览账目（只有长度数字，不含正文）。
  final Map<String, List<StudioTimelineDetailRef>> _deliveredDetails = {};

  /// 已交付预览的保守计量（结构 + 保留正文）：连续性副本只用这份数字账目，
  /// 不额外保存整页正文或第二份正文模型。
  final Map<String, int> _deliveredBytes = {};

  /// 因有界副本滑出而不再持有的身份（有界）：它们的后续事实变化无法用差量表达。
  final Set<String> _evicted = {};
  bool _evictedOverflow = false;

  /// 已交付范围的最早/最新 canonical 键；范围只随交付单调外扩。
  (int, String)? _floor;
  (int, String)? _ceiling;

  int? _deliveredVersion;
  bool _firstFrameConsumed = false;
  bool _closed = false;

  List<ThreadItemView> get _items => _api._itemsOf(_threadId);
  int get _version => _api._contentVersionOf(_threadId);

  static (int, String) _keyOf(ThreadItemView item) => (item.ordinal, item.id);

  static int _compareKeys((int, String) left, (int, String) right) {
    final byOrdinal = left.$1.compareTo(right.$1);
    return byOrdinal != 0 ? byOrdinal : left.$2.compareTo(right.$2);
  }

  @override
  Future<StudioTimelineBaseline> initial() async {
    // 关闭优先于首帧状态：关闭后的调用一律是 typed Cancelled，不是裸 StateError。
    if (_closed) throw _cancelled();
    if (_firstFrameConsumed) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The timeline first frame was already delivered',
        retryable: false,
        correlationId: 'demo-timeline-initial-consumed',
      );
    }
    _firstFrameConsumed = true;
    return _baseline();
  }

  StudioTimelineBaseline _baseline() {
    final version = _version;
    // 先完整计量再提交：候选失败（例如中途 Overloaded）不半发布连接副本。
    final stage = _stagePage(_items, _pageSize);
    _commit(stage, version);
    return StudioTimelineBaseline(
      subscriptionId: _subscriptionId,
      version: version,
      items: List.unmodifiable([
        for (final entry in stage.items)
          _timelineItem(entry.full, entry.preview),
      ]),
      before: stage.before,
      hasOlder: stage.hasOlder,
    );
  }

  /// 用一次已成功计量的页替换本连接的连续性副本。
  ///
  /// 页预算（2 MiB）不超过副本预算（8 MiB），因此提交后无需立即淘汰。
  void _commit(_DemoPageStage stage, int version) {
    _delivered.clear();
    _deliveredDetails.clear();
    _deliveredBytes.clear();
    for (final entry in stage.items) {
      _delivered[entry.full.id] = entry.preview.item;
      _deliveredDetails[entry.full.id] = entry.preview.details;
      _deliveredBytes[entry.full.id] = entry.preview.accountedBytes;
    }
    _deliveredVersion = version;
    _evicted.clear();
    _evictedOverflow = false;
    _floor = stage.items.isEmpty ? null : _keyOf(stage.items.first.full);
    _ceiling = stage.items.isEmpty ? null : _keyOf(stage.items.last.full);
  }

  @override
  Future<StudioTimelineUpdate?> next() async {
    while (true) {
      if (_closed) throw _cancelled();
      if (_deliveredVersion == null) {
        // 首帧尚未移交：与公共契约一致用 typed Conflict，不给 demo 另立例外。
        throw const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'The timeline first frame has not been consumed yet',
          retryable: false,
          correlationId: 'demo-timeline-next-before-initial',
        );
      }
      final seen = _api._chatChangeSeq[_threadId] ?? 0;
      await _api._awaitItemsChanged(_threadId, seen);
      // 关闭先拒绝新调用并取消，取消优先于任何「正常结束」。
      if (_closed) throw _cancelled();
      final delivered = _deliveredVersion!;
      final version = _version;
      if (version <= delivered) continue;
      // 只有通知里能证明的**单次连续变化**才用差量表达；跨过的多次变化无法证明，
      // 直接给出最新小页基线（design/26 §26.8）。
      final change = _api._lastItemChangeOf(_threadId);
      final single =
          version == delivered + 1 &&
              change != null &&
              change.version == version
          ? change
          : null;
      final expressed = single == null ? null : _express(single);
      if (expressed == null) {
        return StudioTimelineResync(
          subscriptionId: _subscriptionId,
          reason: StudioTimelineResyncReason.lagging,
          baseline: _baseline(),
        );
      }
      _deliveredVersion = version;
      return StudioTimelinePatch(
        subscriptionId: _subscriptionId,
        from: delivered,
        to: version,
        changes: List.unmodifiable(expressed),
        priority: StudioTimelinePriority.coalesced,
      );
    }
  }

  /// 把通知里的单次变化表达成 typed 差量；null 表示无法证明连续。
  List<StudioTimelineChange>? _express(_DemoItemChange change) {
    final id = change.itemId;
    if (change.removed) {
      // 真实删除按身份自包含：即使从未交付或已滑出副本也照常交付，
      // 接收者本来没有该身份时为空操作。
      _delivered.remove(id);
      _deliveredDetails.remove(id);
      _deliveredBytes.remove(id);
      _evicted.remove(id);
      return [StudioTimelineRemove(id)];
    }
    final item = change.item;
    if (item == null) return null;
    final previous = _delivered[id];
    if (previous != null) {
      final preview = _previewOf(item);
      final update = _itemUpdate(
        previous,
        _deliveredDetails[id]!,
        preview,
        item,
      );
      if (update == null) return null;
      final changed =
          update.fields.isNotEmpty ||
          update.expectedRevision != update.revision ||
          previous.saved != preview.item.saved ||
          previous.executionTerminal != preview.item.executionTerminal ||
          update.itemShell != null;
      _delivered[id] = preview.item;
      _deliveredDetails[id] = preview.details;
      // 更新后的总量与正文账目原子同步：只留数字，不留第二份正文。
      _deliveredBytes[id] = preview.accountedBytes;
      _prune(id);
      return changed ? [update] : const [];
    }
    final key = _keyOf(item);
    final floor = _floor;
    if (floor != null && _compareKeys(key, floor) < 0) {
      // 更早且从未交付：不插入、不缓存正文；后续页读取当时的权威值。
      // 但它若曾在本连接副本里被淘汰，这次事实变化就无法证明 → 显式重同步。
      if (_evicted.contains(id) || _evictedOverflow) return null;
      return const [];
    }
    final ceiling = _ceiling;
    if (ceiling != null && _compareKeys(key, ceiling) <= 0) {
      // 落在已交付范围内部的**新**身份：无法证明与本连接连续。
      return null;
    }
    final preview = _previewOf(item);
    _delivered[id] = preview.item;
    _deliveredDetails[id] = preview.details;
    _deliveredBytes[id] = preview.accountedBytes;
    _ceiling = key;
    _prune(id);
    return [StudioTimelineAdd(_timelineItem(item, preview))];
  }

  /// 有界副本：同时受 [_continuityLimit] 条与 [_continuityLimitBytes] 字节约束，
  /// 只保留最新的已交付预览；淘汰不是删除通知（design/26 §26.8）。
  void _prune(String newest) {
    while (_delivered.length > _continuityLimit ||
        _deliveredBytesTotal() > _continuityLimitBytes) {
      if (_delivered.length <= 1) break;
      final oldest = _delivered.keys
          .where((id) => id != newest)
          .reduce(
            (left, right) =>
                _compareKeys(
                      _keyOf(_delivered[left]!),
                      _keyOf(_delivered[right]!),
                    ) <=
                    0
                ? left
                : right,
          );
      _delivered.remove(oldest);
      _deliveredDetails.remove(oldest);
      _deliveredBytes.remove(oldest);
      if (_evicted.length >= _continuityLimit) {
        _evicted.remove(_evicted.first);
        _evictedOverflow = true;
      }
      _evicted.add(oldest);
    }
    if (_delivered.isEmpty) return;
    _floor = _delivered.values
        .map(_keyOf)
        .reduce((left, right) => _compareKeys(left, right) <= 0 ? left : right);
    _ceiling = _delivered.values
        .map(_keyOf)
        .reduce((left, right) => _compareKeys(left, right) >= 0 ? left : right);
  }

  /// 已交付预览的保守计量总量（只有数字账目，不扫描正文）。
  int _deliveredBytesTotal() {
    var total = 0;
    for (final bytes in _deliveredBytes.values) {
      total += bytes;
    }
    return total;
  }

  StudioFailure _cancelled() => const StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'The timeline connection is closed',
    retryable: false,
    correlationId: 'demo-timeline-cancelled',
  );

  /// 产品预览预算（design/26 §26.5）：正文预览 32 KiB，工具参数/结果各 4 KiB。
  static const int _bodyPreviewBytes = 32 * 1024;
  static const int _toolPreviewBytes = 4 * 1024;

  StudioTimelineItem _timelineItem(ThreadItemView full, _DemoPreview preview) {
    return StudioTimelineItem(
      item: preview.item,
      saved: full.saved,
      lifecycle: full.executionTerminal
          ? StudioTimelineLifecycle.terminal
          : StudioTimelineLifecycle.streaming,
      omittedBytes: preview.omitted,
      details: preview.details,
    );
  }

  /// 条目预览值：只交付**有界预览**，完整正文留在 canonical 条目里由详情读取。
  ///
  /// 逐字段账目由这一对（完整正文、预览正文）的 UTF-8 字节差直接算出，不用某个输入
  /// 声明的整体省略量代替合成结果（design/26 §26.7）。
  ///
  /// 单条总量是「不可缩结构 + 实际保留正文」：结构先占额度，剩余额度再由正文取
  /// [_bodyPreviewBytes] 与「单条上限减结构」的交集。结构自身已经超限时报告 typed
  /// `Overloaded`，不删字段、不截身份，也不回退到完整载荷（design/26 §预算计量边界）。
  _DemoPreview _previewOf(ThreadItemView item) {
    final full = _fieldsOf(item);
    final structure = _structureBytes(item, full);
    if (structure > _itemPreviewLimitBytes) throw _timelineBudgetExceeded();
    final room = _itemPreviewLimitBytes - structure;
    final budget = _PreviewBudget(
      room < _bodyPreviewBytes ? room : _bodyPreviewBytes,
    );
    final capped = _withCappedFields(item, budget);
    final preview = _fieldsOf(capped);
    final details = <StudioTimelineDetailRef>[
      for (final entry in full.entries)
        StudioTimelineDetailRef(
          field: entry.key,
          revision: item.revision,
          totalBytes: _byteLength(entry.value),
          previewBytes: _byteLength(preview[entry.key] ?? ''),
        ),
    ];
    var omitted = 0;
    var kept = 0;
    for (final ref in details) {
      omitted += ref.totalBytes - ref.previewBytes;
      kept += ref.previewBytes;
    }
    return (
      item: capped.copyWith(bodyOmittedUnits: omitted),
      details: List.unmodifiable(details),
      omitted: omitted,
      accountedBytes: structure + kept,
    );
  }

  /// 以最新端为起点累计同一总量，按条数与页字节预算提前截页。
  ///
  /// 截页后的 `before` 是**实际交付的最早条目**，`hasOlder` 只看是否真的还有更早条目：
  /// 不把预算截页伪装成 EOF，也不让游标越过被截掉的条目（design/26 §26.2）。
  /// 只计量本次候选范围，不为分页预热历史。
  _DemoPageStage _stagePage(List<ThreadItemView> older, int limit) {
    final staged = <_DemoStagedItem>[];
    var total = 0;
    for (
      var index = older.length - 1;
      index >= 0 && staged.length < limit;
      index--
    ) {
      final item = older[index];
      final preview = _previewOf(item);
      if (staged.isNotEmpty &&
          total + preview.accountedBytes > _pageLimitBytes) {
        break;
      }
      total += preview.accountedBytes;
      staged.add(_DemoStagedItem(item, preview));
    }
    final items = List<_DemoStagedItem>.unmodifiable(staged.reversed);
    final oldest = items.isEmpty ? null : items.first.full;
    return _DemoPageStage(
      items: items,
      before: oldest == null ? null : _cursor(oldest.ordinal),
      hasOlder: _hasOlderThan(oldest?.ordinal),
    );
  }

  // ---- 保守结构计量（design/26 §预算计量边界） ----
  //
  // demo 没有 core 的 `meta` 编码，这里按自身 typed 表示做确定性的资源准入估算：
  // 实际静态字符串的 UTF-8 字节 + 各 typed 容器/字段声明的固定壳。它不是 FRB wire
  // 长度，也不等于分配器 heap 或 RSS；两个宿主的估算无需逐字节相等，但单条 256 KiB、
  // 页 2 MiB、连续性副本 8 MiB 的口径与错误分类必须相同。
  //
  // 固定系数只需要覆盖 typed 容器的结构性成本（长度头、槽位、判别与引用），取整数值；
  // 它们属于实现细节，不成为 wire 或持久化字段。

  /// 条目固定壳：ordinal/revision/时间戳/枚举/标记等不可缩元数据。
  static const int _itemShellBytes = 128;

  /// 每个字符串的长度头与槽位。
  static const int _stringSlotBytes = 8;

  /// 每个内容字段的身份 + total/preview 声明 + 详情引用槽位。
  static const int _contentFieldSlotBytes = 24;

  /// 列表/载荷/分块/选项/答案等容器元素的固定成本。
  static const int _containerSlotBytes = 16;

  /// 附件条目的 id/mediaType/filename 头与尺寸字段。
  static const int _attachmentSlotBytes = 24;

  int _stringBytes(String? value) =>
      value == null ? 0 : _stringSlotBytes + _byteLength(value);

  /// 一条条目的不可缩结构成本。
  ///
  /// 覆盖 `ThreadItemStateView` 的全部封闭分支：稳定身份（item/Thread/Turn、工具调用、
  /// 推理、技能、文件路径、问答问题 id 与答案身份）与生命周期错误原因都原样交付，
  /// 因此完整计入；字段**声明**（含空正文、空选项、空分块、空载荷）按字段槽位计费，
  /// 不因为正文为空就免费。
  int _structureBytes(
    ThreadItemView item,
    Map<ThreadContentFieldView, String> fields,
  ) {
    var total = _itemShellBytes;
    total += _stringBytes(item.id);
    total += _stringBytes(item.threadId);
    total += _stringBytes(item.turnId);
    total += fields.length * _contentFieldSlotBytes;
    switch (item.state) {
      case ThreadTextItemStateView(:final attachments, :final lifecycle):
        total += _attachmentBytes(attachments);
        total += _contentLifecycleBytes(lifecycle);
      case ThreadThinkingItemStateView(
        :final summary,
        :final content,
        :final lifecycle,
      ):
        total += (summary.length + content.length) * _containerSlotBytes;
        total += _contentLifecycleBytes(lifecycle);
      case ThreadSkillItemStateView(
        :final name,
        :final source,
        :final providerId,
        :final resourceBase,
        :final cause,
      ):
        total += _stringBytes(name);
        total += _stringBytes(source);
        total += _stringBytes(providerId);
        total += _stringBytes(resourceBase.value);
        total += _stringBytes(cause.id);
      case ThreadToolItemStateView(
        :final invocation,
        :final lifecycle,
        :final userInput,
        :final wait,
      ):
        total += _stringBytes(invocation.toolCallId);
        total += _stringBytes(invocation.callId);
        total += _stringBytes(invocation.providerItemId);
        total += _stringBytes(invocation.name);
        total += _stringBytes(invocation.workingDirectory);
        total += _stringBytes(invocation.taskId);
        total += _toolLifecycleBytes(lifecycle);
        total += _userInputBytes(userInput);
        total += _waitBytes(wait);
      case ThreadAgentItemStateView(:final identity, :final lifecycle):
        total += _stringBytes(identity.id);
        total += _stringBytes(identity.path);
        total += _stringBytes(identity.parentPath);
        total += _stringBytes(identity.role);
        total += _stringBytes(identity.task);
        total += switch (lifecycle) {
          SucceededThreadAgentView(:final summary) => _stringBytes(summary),
          DeniedThreadAgentView(:final reason) => _stringBytes(reason),
          CancelledThreadAgentView(:final reason) => _stringBytes(reason),
          FailedThreadAgentView(:final error) => _stringBytes(error),
          QueuedThreadAgentView() || RunningThreadAgentView() => 0,
        };
      case ThreadTurnItemStateView(:final state, :final inputId):
        total += _stringBytes(inputId);
        total += _turnStateBytes(state);
      case ThreadInferenceItemStateView(
        :final inferenceId,
        :final model,
        :final lifecycle,
      ):
        total += _stringBytes(inferenceId);
        total += _stringBytes(model);
        total += switch (lifecycle) {
          FailedThreadInferenceView(:final error) => _stringBytes(error),
          CancelledThreadInferenceView(:final reason) => _stringBytes(reason),
          RunningThreadInferenceView() || CompletedThreadInferenceView() => 0,
        };
      case ThreadRawItemStateView(:final payloads, :final notice):
        // `notice` 是 canonical 静态原文，不是可裁的正文域：完整计入不可缩结构，
        // 不裁空、不挪成动态字段，也不改变它的详情契约。
        total += _stringBytes(notice);
        for (final payload in payloads) {
          total += _stringBytes(payload.format);
        }
      case ThreadFileItemStateView(:final path, :final mediaType):
        total += _stringBytes(path);
        total += _stringBytes(mediaType);
      case ThreadContextCompactionItemStateView():
        break;
    }
    return total;
  }

  int _contentLifecycleBytes(ThreadContentLifecycleView lifecycle) =>
      switch (lifecycle) {
        FailedThreadContentView(:final error) => _stringBytes(error),
        CancelledThreadContentView(:final reason) => _stringBytes(reason),
        StreamingThreadContentView() || CompletedThreadContentView() => 0,
      };

  /// Turn 状态的不可缩原文。
  ///
  /// [StudioTurnState.reason] 是派生串（失败 message / 取消原因 / 预算种类），而失败分类的
  /// `category`/`providerKind`/`code` 与预算回滚的 [RolloverFailed.error] 都是**任意
  /// String**，它们原样随条目交付，固定壳覆盖不了，必须按实际字节计入。`reason` 已经包含
  /// 失败 `message` 与 `CoalescedTurnCancellation.targetTurnId` 的派生串，因此这两处不重复
  /// 计费；其余原文一个都不省略。
  int _turnStateBytes(StudioTurnState state) {
    var total = _stringBytes(state.reason);
    total += switch (state) {
      FailedStudioTurnState(:final failure) =>
        _stringBytes(failure.category) +
            _stringBytes(failure.providerKind) +
            _stringBytes(failure.code),
      BudgetLimitedStudioTurnState(:final rollover) => switch (rollover) {
        RolloverFailed(:final error) => _stringBytes(error),
        RolloverNotAttempted() || RolloverSucceeded() => 0,
      },
      QueuedStudioTurnState() ||
      RunningStudioTurnState() ||
      CompletedStudioTurnState() ||
      CancelledStudioTurnState() => 0,
    };
    return total;
  }

  int _attachmentBytes(List<ThreadAttachmentView> attachments) {
    var total = 0;
    for (final attachment in attachments) {
      total += _attachmentSlotBytes;
      total += _stringBytes(attachment.id);
      total += _stringBytes(attachment.mediaType);
      total += _stringBytes(attachment.filename);
    }
    return total;
  }

  int _toolLifecycleBytes(ThreadToolLifecycleView lifecycle) =>
      switch (lifecycle) {
        InterruptedThreadToolView(:final reason) => _stringBytes(reason),
        DeniedThreadToolView(:final reason) => _stringBytes(reason),
        CancelledThreadToolView(:final reason) => _stringBytes(reason),
        FailedThreadToolView(:final failure, :final output) =>
          _stringBytes(failure.message) + _toolOutputBytes(output),
        SucceededThreadToolView(:final output) => _toolOutputBytes(output),
        QueuedThreadToolView() ||
        CancellingThreadToolView() ||
        StartedThreadToolView() ||
        StreamingThreadToolView() ||
        AwaitingApprovalThreadToolView() ||
        ApprovedThreadToolView() ||
        RunningThreadToolView() => 0,
      };

  int _toolOutputBytes(ThreadToolOutputView? output) {
    if (output == null) return 0;
    // 预览里的产物数组恒为空：名字/路径等原文属于独立的 `toolOutputArtifacts` 字段
    // （已有字段声明 + 详情引用）与详情读取。计量只针对**实际保留的预览表示**，
    // 因此这里是一个空数组的固定壳，不随原始元素数增长，也不能把已经移出预览的
    // 动态原文误判成不可缩结构。
    return _attachmentBytes(output.attachments) + _containerSlotBytes;
  }

  /// 问答投影的结构成本：交互与问题身份、选项容器、答案身份与答案容器。
  ///
  /// 空选项与空答案仍然各有容器与字段声明成本，因此不会被当免费内容；
  /// 这里也不为字段数量设 hardcap，成本始终按结构字节计。
  ///
  /// 没有对应问题的答案值（`questionId` 找不到匹配问题）不属于任何可寻址内容域：它既
  /// 不会成为内容字段，也无法按字段读详情，只能原样随预览交付，因此按实际字节计入
  /// 不可缩结构，不能让固定壳替任意 String 免单。有匹配问题的答案值仍只经该字段的
  /// 正文额度、total 与详情引用计费，不在这里重复计。
  int _waitBytes(ThreadWaitPresentationView? wait) {
    if (wait == null) return 0;
    var total = _containerSlotBytes;
    switch (wait.intent) {
      case ThreadWaitEventsIntentView(:final targets):
        for (final target in targets) {
          total += _stringBytes(target.taskId);
          total += _stringBytes(target.toolName);
          total += _stringBytes(target.summary);
        }
      case ThreadWaitTimerIntentView():
        total += _containerSlotBytes;
    }
    return total;
  }

  int _userInputBytes(ThreadToolUserInputView? userInput) {
    if (userInput == null) return 0;
    var total = _containerSlotBytes + _stringBytes(userInput.interactionId);
    for (final question in userInput.questions) {
      total += _containerSlotBytes;
      total += _stringBytes(question.id);
      total += question.options.length * _containerSlotBytes;
    }
    for (final answer in userInput.answers) {
      total += _containerSlotBytes;
      total += _stringBytes(answer.questionId);
      total += answer.answers.length * _containerSlotBytes;
      if (userInput.questionIndex(answer.questionId) == null) {
        for (final value in answer.answers) {
          total += _stringBytes(value);
        }
      }
    }
    return total;
  }

  /// 按产品预览预算截断各内容字段；完整正文仍留在 demo 的 canonical 条目里。
  ///
  /// 正文（含问答与原始记录）共享 32 KiB；工具参数与结果各最多 4 KiB，且都从同一份额度里
  /// 取。字段**存在性**与结构（chunk 身份、问答位置、判别字段）不因没额度而消失：
  /// 只留下空预览占位 + 真实 total，正文按需读详情（design/26 §26.5）。
  ThreadItemView _withCappedFields(ThreadItemView item, _PreviewBudget budget) {
    switch (item.state) {
      case ThreadTextItemStateView(
        :final channel,
        :final text,
        :final attachments,
        :final lifecycle,
      ):
        return item.copyWith(
          state: ThreadTextItemStateView(
            channel: channel,
            text: budget.cap(text, _bodyPreviewBytes),
            attachments: attachments,
            lifecycle: lifecycle,
          ),
        );
      case ThreadThinkingItemStateView(
        :final summary,
        :final content,
        :final lifecycle,
        :final summaryChunkBase,
        :final contentChunkBase,
      ):
        return item.copyWith(
          state: ThreadThinkingItemStateView(
            summary: _cappedChunks(summary, budget),
            content: _cappedChunks(content, budget),
            lifecycle: lifecycle,
            summaryChunkBase: summaryChunkBase,
            contentChunkBase: contentChunkBase,
          ),
        );
      case ThreadToolItemStateView(
        :final invocation,
        :final lifecycle,
        :final userInput,
        :final wait,
      ):
        return item.copyWith(
          state: ThreadToolItemStateView(
            invocation: invocation.withArguments(
              budget.cap(invocation.arguments, _toolPreviewBytes),
            ),
            lifecycle: _cappedToolLifecycle(lifecycle, budget),
            userInput: _cappedUserInput(userInput, budget),
            wait: wait,
          ),
        );
      case ThreadRawItemStateView(
        :final payloads,
        :final notice,
        :final recordedAt,
      ):
        return item.copyWith(
          state: ThreadRawItemStateView(
            [
              for (final payload in payloads)
                // 每段都是独立的稳定身份：没额度时保留空预览占位，不丢段。
                RawHistoryPayload(
                  payload.format,
                  payload.version,
                  budget.cap(payload.content, _bodyPreviewBytes),
                ),
            ],
            notice,
            recordedAt,
          ),
        );
      default:
        return item;
    }
  }

  /// 问答正文（含计划确认在公开 typed 字段里的反馈）与普通正文共享同一份预算。
  ///
  /// 计划确认的**后端权威决定标记**是判别事实：先为这些小的固定标记预留字节，再按剩余
  /// 预算裁剪自由正文，避免长正文把批准/请求修改标记挤掉而降级成普通“已回答”
  /// （design/26 §26.5）。标记字节仍计入该字段的总量与详情引用，不隐藏反馈。
  ThreadToolUserInputView? _cappedUserInput(
    ThreadToolUserInputView? userInput,
    _PreviewBudget budget,
  ) {
    if (userInput == null) return null;
    for (final answer in userInput.answers) {
      for (final value in answer.answers) {
        if (value == agentSessionPlanApproveAnswer ||
            value == agentSessionPlanReviseAnswer) {
          budget.reserve(_byteLength(value));
        }
      }
    }
    var capped = userInput;
    for (var index = 0; index < userInput.questions.length; index++) {
      capped = capped
          .withText(
            index,
            const ThreadUserInputHeaderFieldPartView(),
            budget.cap(userInput.headerText(index), _bodyPreviewBytes),
          )
          .withText(
            index,
            const ThreadUserInputQuestionFieldPartView(),
            budget.cap(userInput.questionText(index), _bodyPreviewBytes),
          );
      final options = userInput.questions[index].options.length;
      for (var option = 0; option < options; option++) {
        capped = capped
            .withText(
              index,
              ThreadUserInputOptionLabelFieldPartView(option),
              budget.cap(
                userInput.optionLabel(index, option),
                _bodyPreviewBytes,
              ),
            )
            .withText(
              index,
              ThreadUserInputOptionDescriptionFieldPartView(option),
              budget.cap(
                userInput.optionDescription(index, option),
                _bodyPreviewBytes,
              ),
            );
      }
    }
    for (final answer in userInput.answers) {
      final index = userInput.questionIndex(answer.questionId);
      if (index == null) continue;
      for (var value = 0; value < answer.answers.length; value++) {
        final text = userInput.answerText(index, value);
        // 判别标记原样交付（已预留额度），自由反馈仍受剩余预算约束。
        final keepVerbatim =
            text == agentSessionPlanApproveAnswer ||
            text == agentSessionPlanReviseAnswer;
        capped = capped.withText(
          index,
          ThreadUserInputAnswerFieldPartView(value),
          keepVerbatim ? text : budget.cap(text, _bodyPreviewBytes),
        );
      }
    }
    return capped;
  }

  ThreadToolLifecycleView _cappedToolLifecycle(
    ThreadToolLifecycleView lifecycle,
    _PreviewBudget budget,
  ) {
    return switch (lifecycle) {
      RunningThreadToolView(:final streamedOutput) => RunningThreadToolView(
        budget.cap(streamedOutput, _toolPreviewBytes),
      ),
      CancellingThreadToolView(:final streamedOutput) =>
        CancellingThreadToolView(budget.cap(streamedOutput, _toolPreviewBytes)),
      SucceededThreadToolView(:final completedAt, :final output) =>
        SucceededThreadToolView(completedAt, _cappedToolOutput(output, budget)),
      FailedThreadToolView(:final failedAt, :final failure, :final output) =>
        FailedThreadToolView(
          failedAt,
          failure,
          output == null ? null : _cappedToolOutput(output, budget),
        ),
      _ => lifecycle,
    };
  }

  ThreadToolOutputView _cappedToolOutput(
    ThreadToolOutputView output,
    _PreviewBudget budget,
  ) => ThreadToolOutputView(
    result: budget.cap(output.result, _toolPreviewBytes),
    attachments: output.attachments,
    // 产物正文是独立内容字段：预览数组可以为空，完整原文只经详情读取。
    outputArtifacts: const [],
    exitCode: output.exitCode,
  );

  /// 分块预览：**每个 canonical chunk 都保留**（顺序即身份），只把没额度的块截成空串。
  /// 这样字段存在性不会因为预算耗尽而变成“被删除”。
  List<String> _cappedChunks(List<String> chunks, _PreviewBudget budget) => [
    for (final chunk in chunks) budget.cap(chunk, _bodyPreviewBytes),
  ];

  StudioTimelineUpdateItem? _itemUpdate(
    ThreadItemView previous,
    List<StudioTimelineDetailRef> previousDetails,
    _DemoPreview next,
    ThreadItemView full,
  ) {
    final fields = _fieldUpdates(previous, previousDetails, next, full);
    if (fields == null) return null;
    return StudioTimelineUpdateItem(
      itemId: full.id,
      expectedRevision: previous.revision,
      revision: full.revision,
      omittedBytes: next.omitted,
      saved: full.saved,
      lifecycle: full.executionTerminal
          ? StudioTimelineLifecycle.terminal
          : StudioTimelineLifecycle.streaming,
      itemShell:
          previous.state.runtimeType != next.item.state.runtimeType ||
              previous.updatedAt != full.updatedAt ||
              previous.isTerminal != full.isTerminal
          ? next.item
          : null,
      fields: fields,
    );
  }

  /// 两个**已封顶预览**之间的 typed 字段变化；完整正文只用来提供字段总字节数。
  ///
  /// 字段**存在性**由完整 canonical 字段集合决定（不以裁剪后的预览是否有字符串判定）：
  /// 没额度的字段以空预览 + 真实 total 交付，只有 canonical 字段真的消失才发 `Remove`。
  /// 字段身份直接用 SDK 的值语义（判别分支 + 逻辑索引）。
  List<StudioFieldUpdateView>? _fieldUpdates(
    ThreadItemView previous,
    List<StudioTimelineDetailRef> previousDetails,
    _DemoPreview next,
    ThreadItemView full,
  ) {
    final previousFields = _fieldsOf(previous);
    final fullFields = _fieldsOf(full);
    final previewFields = _fieldsOf(next.item);
    final previousTotals = {
      for (final ref in previousDetails) ref.field: ref.totalBytes,
    };
    final changes = <StudioFieldUpdateView>[];
    for (final entry in fullFields.entries) {
      final field = entry.key;
      final previewText = previewFields[field] ?? '';
      final total = _byteLength(entry.value);
      final previewBytes = _byteLength(previewText);
      final previousText = previousFields[field];
      final previousTotal = previousTotals[field] ?? 0;
      if (previousText != null &&
          previewBytes < _byteLength(previousText) &&
          total >= previousTotal) {
        // 原文没有变短却把预览挤短：这是预算重新分配，无法用连续差量证明 → 显式重同步。
        return null;
      }
      if (previousText == null) {
        // 新字段：即使预览为空也要建立该字段（空预览占位 + 真实 total），不能当成缺失。
        changes.add(
          StudioFieldUpdateView(
            field: field,
            change: AppendThreadFieldChangeView(previewText),
            totalBytes: total,
            previewBytes: previewBytes,
          ),
        );
        continue;
      }
      if (previousText == previewText) {
        // 预览已封顶而正文继续增长：仍要推进逐字段元数据（与生产 producer 同形状）。
        if (previousTotal != total) {
          changes.add(
            StudioFieldUpdateView(
              field: field,
              change: const UnchangedThreadFieldChangeView(),
              totalBytes: total,
              previewBytes: previewBytes,
            ),
          );
        }
        continue;
      }
      changes.add(
        StudioFieldUpdateView(
          field: field,
          change: previewText.startsWith(previousText)
              ? AppendThreadFieldChangeView(
                  previewText.substring(previousText.length),
                )
              : ReplaceThreadFieldChangeView(previewText),
          totalBytes: total,
          previewBytes: previewBytes,
        ),
      );
    }
    for (final entry in previousFields.entries) {
      // 只有 canonical 字段真的消失才是 Remove。
      if (fullFields.containsKey(entry.key)) continue;
      changes.add(
        StudioFieldUpdateView(
          field: entry.key,
          change: const RemoveThreadFieldChangeView(),
          totalBytes: 0,
          previewBytes: 0,
        ),
      );
    }
    return changes;
  }

  /// 工具生命周期里的结果正文（与 `tool.result` 字段对应）。
  String _toolResultText(ThreadToolLifecycleView lifecycle) {
    return switch (lifecycle) {
      RunningThreadToolView(:final streamedOutput) => streamedOutput,
      CancellingThreadToolView(:final streamedOutput) => streamedOutput,
      SucceededThreadToolView(:final output) => output.result,
      FailedThreadToolView(:final output) => output?.result ?? '',
      _ => '',
    };
  }

  /// 工具产物正文（与 `toolOutputArtifacts` 字段对应）：只在 canonical 边界编码。
  String _toolArtifactsText(ThreadToolLifecycleView lifecycle) {
    final output = switch (lifecycle) {
      SucceededThreadToolView(:final output) => output,
      FailedThreadToolView(:final output) => output,
      _ => null,
    };
    if (output == null || output.outputArtifacts.isEmpty) return '';
    return jsonEncode(output.outputArtifacts);
  }

  /// 无状态历史页：`before` 是绑定 Thread 的不透明顺序边界。
  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) async {
    if (_closed) throw _cancelled();
    final size = limit ?? _pageSize;
    if (size < 1 || size > 100) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Timeline page limit must be within 1..100',
        retryable: false,
        correlationId: 'demo-timeline-page-limit',
      );
    }
    final items = _items;
    final boundary = before == null ? null : _ordinalFromCursor(before);
    final older = boundary == null
        ? items
        : items
              .where((item) => item.ordinal < boundary)
              .toList(growable: false);
    // 页是自包含查询：与首帧/重同步基线使用同一份总量与截页规则。
    final stage = _stagePage(older, size);
    return StudioTimelinePage(
      items: List.unmodifiable([
        for (final entry in stage.items)
          _timelineItem(entry.full, entry.preview),
      ]),
      before: stage.before,
      hasOlder: stage.hasOlder,
    );
  }

  /// 按 item/field/revision 读取完整正文；continuation 是不透明的 UTF-8 字节游标。
  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) async {
    if (_closed) throw _cancelled();
    final maxBytes = query.maxBytes ?? _defaultDetailBytes;
    if (maxBytes < _minDetailBytes || maxBytes > _maxDetailBytes) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Timeline detail block size must be within 4..262144 bytes',
        retryable: false,
        correlationId: 'demo-timeline-detail-block',
      );
    }
    final item = _items.where((entry) => entry.id == itemId).firstOrNull;
    if (item == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'The timeline item is no longer available',
        retryable: false,
        correlationId: 'demo-timeline-detail-not-found',
      );
    }
    if (item.revision != query.revision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'The timeline item revision changed',
        retryable: false,
        correlationId: 'demo-timeline-detail-stale',
      );
    }
    final body = _fieldText(item, query.field);
    if (body == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'The timeline field is not available',
        retryable: false,
        correlationId: 'demo-timeline-detail-field',
      );
    }
    final bytes = utf8.encode(body);
    var start = 0;
    final continuation = query.continuation;
    if (continuation != null) {
      final parsed = _parseDetailContinuation(continuation);
      // continuation 绑定 Thread、item、字段与 revision：跨 scope 复用一律拒绝。
      if (parsed.threadId != _threadId ||
          parsed.itemId != itemId ||
          parsed.field != query.field) {
        throw _invalidDetailCursor();
      }
      if (parsed.revision != query.revision) {
        throw const StudioFailure(
          code: StudioFailureCode.staleRevision,
          message: 'The timeline detail cursor belongs to another revision',
          retryable: false,
          correlationId: 'demo-timeline-detail-cursor-revision',
        );
      }
      if (parsed.offset > bytes.length) throw _invalidDetailCursor();
      // offset 必须落在合法 UTF-8 起始字节上：落在续字节上会让后续 decode 泄 FormatException。
      if (parsed.offset < bytes.length &&
          (bytes[parsed.offset] & 0xC0) == 0x80) {
        throw _invalidDetailCursor();
      }
      start = parsed.offset;
    }
    var end = start + maxBytes;
    if (end > bytes.length) end = bytes.length;
    if (end < bytes.length) {
      // 只在合法 UTF-8 边界切块：不跨多字节字符（maxBytes ≥ 4 保证至少推进一个码点）。
      while (end > start && (bytes[end] & 0xC0) == 0x80) {
        end -= 1;
      }
      if (end == start) throw _invalidDetailCursor();
    }
    final String text;
    try {
      text = utf8.decode(bytes.sublist(start, end));
    } on FormatException {
      // 任何损坏的游标/边界都统一成 typed invalidArgument，不把解码异常泄给上层。
      throw _invalidDetailCursor();
    }
    return StudioTimelineDetailChunk(
      itemId: item.id,
      field: query.field,
      revision: item.revision,
      text: text,
      totalBytes: bytes.length,
      continuation: end < bytes.length
          ? _detailContinuationToken(
              itemId: item.id,
              field: query.field,
              revision: item.revision,
              offset: end,
            )
          : null,
    );
  }

  static const int _minDetailBytes = 4;

  StudioFailure _invalidDetailCursor() => const StudioFailure(
    code: StudioFailureCode.invalidArgument,
    message: 'The timeline detail cursor is invalid',
    retryable: false,
    correlationId: 'demo-timeline-detail-cursor',
  );

  /// 不透明 continuation：版本化 JSON + base64url，绑定 Thread/item/field/revision 与
  /// 合法 UTF-8 字节偏移。字段用一个私有 typed 编码表达（Dart record 不是 JSON 可直接
  /// 编码的对象，也不能拿 `toString` 当稳定 codec）。
  String _detailContinuationToken({
    required String itemId,
    required ThreadContentFieldView field,
    required int revision,
    required int offset,
  }) {
    final payload = <String, Object?>{
      'v': 1,
      't': _threadId,
      'i': itemId,
      'f': _fieldToWire(field),
      'r': revision,
      'o': offset,
    };
    return base64Url.encode(utf8.encode(jsonEncode(payload)));
  }

  ({
    String threadId,
    String itemId,
    ThreadContentFieldView field,
    int revision,
    int offset,
  })
  _parseDetailContinuation(String token) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(base64Url.decode(token)));
    } catch (_) {
      throw _invalidDetailCursor();
    }
    if (decoded is! Map<String, Object?>) throw _invalidDetailCursor();
    final version = decoded['v'];
    final threadId = decoded['t'];
    final itemId = decoded['i'];
    final revision = decoded['r'];
    final offset = decoded['o'];
    final field = _fieldFromWire(decoded['f']);
    if (version != 1 ||
        threadId is! String ||
        itemId is! String ||
        revision is! int ||
        offset is! int ||
        revision < 0 ||
        offset < 0 ||
        field == null) {
      throw _invalidDetailCursor();
    }
    return (
      threadId: threadId,
      itemId: itemId,
      field: field,
      revision: revision,
      offset: offset,
    );
  }

  Map<String, Object?> _fieldToWire(ThreadContentFieldView field) =>
      switch (field) {
        ThreadTextFieldView() => {'k': 'text'},
        ThreadThinkingSummaryFieldView(:final chunkIndex) => {
          'k': 'summary',
          'i': chunkIndex,
        },
        ThreadThinkingContentFieldView(:final chunkIndex) => {
          'k': 'content',
          'i': chunkIndex,
        },
        ThreadToolArgumentsFieldView() => {'k': 'args'},
        ThreadToolResultFieldView() => {'k': 'result'},
        ThreadToolOutputArtifactsFieldView() => {'k': 'artifacts'},
        ThreadRawPayloadFieldView(:final payloadIndex) => {
          'k': 'raw',
          'i': payloadIndex,
        },
        ThreadToolUserInputFieldView(:final questionIndex, :final part) => {
          'k': 'input',
          'q': questionIndex,
          'p': _partToWire(part),
        },
      };

  Map<String, Object?> _partToWire(ThreadUserInputFieldPartView part) =>
      switch (part) {
        ThreadUserInputHeaderFieldPartView() => {'k': 'header'},
        ThreadUserInputQuestionFieldPartView() => {'k': 'question'},
        ThreadUserInputAnswerFieldPartView(:final answerIndex) => {
          'k': 'answer',
          'i': answerIndex,
        },
        ThreadUserInputOptionLabelFieldPartView(:final optionIndex) => {
          'k': 'label',
          'i': optionIndex,
        },
        ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex) => {
          'k': 'description',
          'i': optionIndex,
        },
      };

  ThreadContentFieldView? _fieldFromWire(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final index = value['i'];
    switch (value['k']) {
      case 'text':
        return const ThreadTextFieldView();
      case 'summary':
        return index is int ? ThreadThinkingSummaryFieldView(index) : null;
      case 'content':
        return index is int ? ThreadThinkingContentFieldView(index) : null;
      case 'args':
        return const ThreadToolArgumentsFieldView();
      case 'result':
        return const ThreadToolResultFieldView();
      case 'artifacts':
        return const ThreadToolOutputArtifactsFieldView();
      case 'raw':
        return index is int ? ThreadRawPayloadFieldView(index) : null;
      case 'input':
        final questionIndex = value['q'];
        final part = _partFromWire(value['p']);
        if (questionIndex is! int || part == null) return null;
        return ThreadToolUserInputFieldView(
          questionIndex: questionIndex,
          part: part,
        );
      default:
        return null;
    }
  }

  ThreadUserInputFieldPartView? _partFromWire(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final index = value['i'];
    switch (value['k']) {
      case 'header':
        return const ThreadUserInputHeaderFieldPartView();
      case 'question':
        return const ThreadUserInputQuestionFieldPartView();
      case 'answer':
        return index is int ? ThreadUserInputAnswerFieldPartView(index) : null;
      case 'label':
        return index is int
            ? ThreadUserInputOptionLabelFieldPartView(index)
            : null;
      case 'description':
        return index is int
            ? ThreadUserInputOptionDescriptionFieldPartView(index)
            : null;
      default:
        return null;
    }
  }

  /// 字段身份 → 完整正文（demo 只有这些 typed 字段域）。
  String? _fieldText(ThreadItemView item, ThreadContentFieldView field) {
    return _fieldsOf(item)[field];
  }

  Map<ThreadContentFieldView, String> _fieldsOf(ThreadItemView item) {
    final fields = <ThreadContentFieldView, String>{};
    switch (item.state) {
      case ThreadTextItemStateView(:final text):
        fields[const ThreadTextFieldView()] = text;
      case ThreadThinkingItemStateView(
        :final summary,
        :final content,
        :final summaryChunkBase,
        :final contentChunkBase,
      ):
        for (var index = 0; index < summary.length; index++) {
          fields[ThreadThinkingSummaryFieldView(summaryChunkBase + index)] =
              summary[index];
        }
        for (var index = 0; index < content.length; index++) {
          fields[ThreadThinkingContentFieldView(contentChunkBase + index)] =
              content[index];
        }
      case ThreadToolItemStateView(
        :final invocation,
        :final lifecycle,
        :final userInput,
        wait: _,
      ):
        fields[const ThreadToolArgumentsFieldView()] = invocation.arguments;
        fields[const ThreadToolResultFieldView()] = _toolResultText(lifecycle);
        fields[const ThreadToolOutputArtifactsFieldView()] = _toolArtifactsText(
          lifecycle,
        );
        if (userInput != null) {
          for (var index = 0; index < userInput.questions.length; index++) {
            fields[ThreadToolUserInputFieldView(
              questionIndex: index,
              part: const ThreadUserInputHeaderFieldPartView(),
            )] = userInput.headerText(
              index,
            );
            fields[ThreadToolUserInputFieldView(
              questionIndex: index,
              part: const ThreadUserInputQuestionFieldPartView(),
            )] = userInput.questionText(
              index,
            );
            final options = userInput.questions[index].options.length;
            for (var option = 0; option < options; option++) {
              fields[ThreadToolUserInputFieldView(
                questionIndex: index,
                part: ThreadUserInputOptionLabelFieldPartView(option),
              )] = userInput.optionLabel(
                index,
                option,
              );
              fields[ThreadToolUserInputFieldView(
                questionIndex: index,
                part: ThreadUserInputOptionDescriptionFieldPartView(option),
              )] = userInput.optionDescription(
                index,
                option,
              );
            }
          }
          for (final answer in userInput.answers) {
            final questionIndex = userInput.questionIndex(answer.questionId);
            if (questionIndex == null) continue;
            for (var value = 0; value < answer.answers.length; value++) {
              fields[ThreadToolUserInputFieldView(
                    questionIndex: questionIndex,
                    part: ThreadUserInputAnswerFieldPartView(value),
                  )] =
                  answer.answers[value];
            }
          }
        }
      case ThreadRawItemStateView(:final payloads):
        for (var index = 0; index < payloads.length; index++) {
          fields[ThreadRawPayloadFieldView(index)] = payloads[index].content;
        }
      default:
        break;
    }
    return fields;
  }

  bool _hasOlderThan(int? ordinal) {
    if (ordinal == null) return false;
    return _items.any((item) => item.ordinal < ordinal);
  }

  String _cursor(int ordinal) =>
      'dtl1.${base64Url.encode(utf8.encode(_threadId))}.$ordinal';

  int _ordinalFromCursor(String token) {
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != 'dtl1') {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'The timeline page cursor is invalid',
        retryable: false,
        correlationId: 'demo-timeline-page-cursor',
      );
    }
    String threadId;
    try {
      threadId = utf8.decode(base64Url.decode(parts[1]));
    } catch (_) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'The timeline page cursor is invalid',
        retryable: false,
        correlationId: 'demo-timeline-page-cursor',
      );
    }
    final ordinal = int.tryParse(parts[2]);
    if (threadId != _threadId || ordinal == null || ordinal < 0) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'The timeline page cursor is invalid',
        retryable: false,
        correlationId: 'demo-timeline-page-cursor',
      );
    }
    return ordinal;
  }

  int _byteLength(String value) => utf8.encode(value).length;

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    // 关闭即释放正文与数字账目：连接不再持有任何预览副本。
    _delivered.clear();
    _deliveredDetails.clear();
    _deliveredBytes.clear();
    _evicted.clear();
    _floor = null;
    _ceiling = null;
    // 与原生连接对齐：close 必须打断挂起的 next 等待，否则内容泵永久泄漏。
    _api._notifyItemsChanged(_threadId);
  }

  @override
  Future<void> close() async {
    requestClose();
  }
}

ThreadItemView _messageItem({
  required String id,
  required String threadId,
  required String turnId,
  required int ordinal,
  required ThreadItemKind kind,
  required String text,
  required DateTime createdAt,
  AgentMessageChannel? channel,
  List<ThreadAttachmentView> attachments = const [],
}) {
  return ThreadItemView(
    id: id,
    threadId: threadId,
    turnId: turnId,
    ordinal: ordinal,
    revision: 0,
    createdAt: createdAt,
    updatedAt: createdAt,
    state: switch (kind) {
      ThreadItemKind.userMessage => ThreadTextItemStateView(
        channel: ThreadTextChannel.user,
        text: text,
        attachments: attachments,
        lifecycle: CompletedThreadContentView(createdAt),
      ),
      ThreadItemKind.parentAgentMessage => ThreadTextItemStateView(
        channel: ThreadTextChannel.parentAgent,
        text: text,
        attachments: attachments,
        lifecycle: CompletedThreadContentView(createdAt),
      ),
      ThreadItemKind.agentMessage => ThreadTextItemStateView(
        channel: channel == AgentMessageChannel.commentary
            ? ThreadTextChannel.commentary
            : ThreadTextChannel.finalAnswer,
        text: text,
        attachments: const [],
        lifecycle: CompletedThreadContentView(createdAt),
      ),
      ThreadItemKind.reasoning ||
      ThreadItemKind.toolCall ||
      ThreadItemKind.agent ||
      ThreadItemKind.turn ||
      ThreadItemKind.inference ||
      ThreadItemKind.skill ||
      ThreadItemKind.file ||
      ThreadItemKind.raw ||
      ThreadItemKind.contextCompaction => throw ArgumentError.value(
        kind,
        'kind',
        'demo message helper only accepts text and plan items',
      ),
    },
  );
}

AttachmentDraftView _demoAttachmentDraft(
  AttachmentDraftSource source,
  int sequence,
) {
  final filename = switch (source) {
    LocalFileAttachmentDraftSource(:final path) =>
      path.replaceAll('\\', '/').split('/').last,
    RemoteUrlAttachmentDraftSource(:final url, :final filename) =>
      filename ?? Uri.parse(url).pathSegments.last,
  };
  final extension = filename.split('.').last.toLowerCase();
  final modality = switch (extension) {
    'png' || 'jpg' || 'jpeg' || 'webp' => AttachmentModalityView.image,
    'mp4' || 'mov' || 'webm' || 'mkv' => AttachmentModalityView.video,
    _ => AttachmentModalityView.file,
  };
  return AttachmentDraftView(
    id: 'demo-attachment-$sequence',
    modality: modality,
    mediaType: switch (modality) {
      AttachmentModalityView.image => 'image/png',
      AttachmentModalityView.video => 'video/mp4',
      AttachmentModalityView.file => 'application/octet-stream',
    },
    filename: filename,
    byteSize: 0,
  );
}

ThreadWorkspace _demoUpdateInteraction(
  ThreadWorkspace workspace,
  int revision,
  PendingInteraction interaction,
  bool pending,
) {
  final interactions = [...workspace.interactions];
  final index = interactions.indexWhere((item) => item.id == interaction.id);
  if (!pending) {
    if (index >= 0) interactions.removeAt(index);
  } else if (index < 0) {
    interactions.add(interaction);
  } else {
    interactions[index] = interaction;
  }
  return workspace.copyWith(revision: revision, interactions: interactions);
}

/// Deterministic demo fixture exposed only by the dedicated Driver build.
class DriverDemoStudioTransport extends DemoStudioTransport {
  DriverDemoStudioTransport({super.lspActivityLoop});

  bool _retiredPlannerScenario = false;
  int _fixtureScenarioRevision = 0;
  int _appliedFixtureScenarioRevision = -1;

  void prepareRetiredPlannerScenario() {
    prepareSessionLifecycleScenario();
    _retiredPlannerScenario = true;
    _selectedThreadId = 'thread-main';
  }

  @override
  ({StudioProject project, List<StudioThread> threads})
  _ensureWorkspaceFixture() {
    final fixture = super._ensureWorkspaceFixture();
    if (_appliedFixtureScenarioRevision != _fixtureScenarioRevision) {
      _workspaces.update('thread-main', _driverWorkspaceFixture);
      _resolvedInteractions.clear();
      _appliedFixtureScenarioRevision = _fixtureScenarioRevision;
    }
    if (!_retiredPlannerScenario) return fixture;
    final threads = [
      for (final thread in fixture.threads)
        if (thread.id == 'thread-reviewer')
          thread.copyWith(role: 'planner', status: ThreadStatusView.idle)
        else
          thread,
    ];
    final retired = threads.singleWhere(
      (thread) => thread.id == 'thread-reviewer',
    );
    _workspaces[retired.id] = _workspaces[retired.id]!.copyWith(
      thread: retired,
      interactions: const [],
    );
    return (project: fixture.project, threads: threads);
  }

  bool _themeScenario = false;
  bool _themePlanScenario = false;

  /// Resets the dedicated Driver fixture without introducing product settings.
  void prepareThemeScenario({bool plan = false}) {
    _fixtureScenarioRevision += 1;
    _themeScenario = true;
    _themePlanScenario = plan;
    _sessionLifecycleScenario = false;
    _fallbackInputScenario = false;
    _persistenceFailureScenario = false;
    _failNextTurn = false;
    _retryNextTurn = false;
    _selectedThreadId = 'thread-main';
  }

  bool _sessionLifecycleScenario = false;
  bool _persistenceFailureScenario = false;
  bool _failNextTurn = false;
  bool _retryNextTurn = false;

  void prepareConnectionRetryScenario() {
    _retryNextTurn = true;
  }

  void preparePersistenceFailureScenario() {
    prepareSessionLifecycleScenario();
    _persistenceFailureScenario = true;
    _failNextTurn = true;
    _selectedThreadId = 'thread-main';
  }

  @override
  Future<void> _completePrompt({
    required String threadId,
    required String turnId,
    required String trimmedPrompt,
    required int generation,
    required DateTime startedAt,
  }) async {
    if (_retryNextTurn) {
      _retryNextTurn = false;
      for (var attempt = 1; attempt <= 5; attempt++) {
        await Future<void>.delayed(promptActivityDelay);
        if (_promptGenerations[threadId] != generation) return;
        final now = DateTime.now();
        _upsertChatItem(
          threadId,
          ThreadItemView(
            id: '$turnId:connection-retry-$attempt',
            threadId: threadId,
            turnId: turnId,
            ordinal: _nextOrdinal(threadId),
            revision: 0,
            createdAt: now,
            updatedAt: now,
            state: ThreadTextItemStateView(
              channel: ThreadTextChannel.commentary,
              text: '连接中断，正在重试（$attempt/5）。',
              attachments: const [],
              lifecycle: CompletedThreadContentView(now),
            ),
          ),
        );
      }
    }
    if (!_failNextTurn) {
      return super._completePrompt(
        threadId: threadId,
        turnId: turnId,
        trimmedPrompt: trimmedPrompt,
        generation: generation,
        startedAt: startedAt,
      );
    }
    _failNextTurn = false;
    await Future<void>.delayed(promptActivityDelay);
    if (_promptGenerations[threadId] != generation) return;
    _emitThreadUpdate(
      threadId,
      ThreadTurnUpdate(
        StudioTurnView(
          turnId: turnId,
          threadId: threadId,
          revision: 1,
          updatedAt: DateTime.now(),
          state: FailedStudioTurnState(
            startedAt: startedAt.millisecondsSinceEpoch ~/ 1000,
            completedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            failure: const StudioTurnFailureView(
              category: 'protocol',
              providerKind: null,
              code: 'turnProtocolProjectionFailed',
              httpStatus: null,
              message: 'Injected turn protocol failure',
              retryable: false,
              retryAfterMs: null,
            ),
          ),
        ),
      ),
    );
    // 注入的 Turn 失败也是终态：清空当前活动。
    _clearActivity(threadId);
  }

  @override
  Future<PersistenceStateSnapshot> retryPersistence() async {
    _persistenceFailureScenario = false;
    return const PersistenceStateSnapshot(
      revision: 2,
      state: ReadyPersistenceState(pendingCommits: 0),
    );
  }

  bool _fallbackInputScenario = false;
  int _pagingFixtureCount = 42;

  void preparePagingScenario(int count) {
    _fixtureScenarioRevision += 1;
    _sessionLifecycleScenario = false;
    _fallbackInputScenario = false;
    _pagingFixtureCount = count;
    _pageFillThreads.clear();
    _selectedThreadId = null;
  }

  void prepareSessionLifecycleScenario() {
    _fixtureScenarioRevision += 1;
    _themeScenario = false;
    _themePlanScenario = false;
    _sessionLifecycleScenario = true;
    _fallbackInputScenario = false;
    _pageFillThreads.clear();
    _selectedThreadId = null;
  }

  void prepareFallbackInputScenario() {
    _fixtureScenarioRevision += 1;
    _sessionLifecycleScenario = false;
    _fallbackInputScenario = true;
    _pageFillThreads.clear();
    _selectedThreadId = 'thread-main';
  }

  static const _themePlanMarkdown = '''
# Siamese workspace palette

Keep the existing workspace and use cream surfaces with seal-brown actions.

## Implementation

1. Archive the approved concept and document semantic colors.
2. Apply the shared Material theme to all pages and dialogs.
3. Keep blue limited to selected markers and active status icons.

> Normal text stays warm brown and remains readable on every surface.

```dart
final theme = pureStudioTheme();
```

## Acceptance

- [x] Preserve the layout and all existing actions.
- [ ] Verify narrow windows and keyboard focus.
- [ ] Inspect [the design reference](https://example.com/design).
''';

  @override
  Duration get promptActivityDelay => const Duration(seconds: 3);

  @override
  Duration get promptToolDelay => const Duration(seconds: 3);

  @override
  Duration get shutdownPhaseDelay => const Duration(milliseconds: 400);

  @override
  Duration get lspActivityStepDelay => const Duration(seconds: 3);

  /// Driver 目录分页验收需要大量历史会话。
  @override
  int get directoryPageFillCount =>
      _sessionLifecycleScenario ? 0 : _pagingFixtureCount;

  @override
  PersistenceStateSnapshot _demoPersistenceState() =>
      _persistenceFailureScenario
      ? const PersistenceStateSnapshot(
          revision: 1,
          state: DegradedPersistenceState(
            pendingCommits: 3,
            oldestPendingRevision: 8,
            firstFailedAt: 1,
            error: ObservedResourceError(
              code: 'storageUnavailable',
              message: 'Injected save failure',
              retryable: true,
            ),
          ),
        )
      : super._demoPersistenceState();

  ThreadWorkspace _driverWorkspaceFixture(ThreadWorkspace workspace) {
    if (_sessionLifecycleScenario) {
      return workspace.copyWith(interactions: const [], todo: null);
    }
    const threadId = 'thread-main';
    return workspace.copyWith(
      todo: _themeScenario
          ? const TimelineTodoListUpdate(
              callId: 'driver-theme-todo',
              explanation: 'Palette acceptance',
              items: [
                TimelineTodoItem(
                  step: 'Archive the approved concept',
                  status: 'completed',
                ),
                TimelineTodoItem(
                  step: 'Apply the shared theme',
                  status: 'inProgress',
                ),
                TimelineTodoItem(
                  step: 'Inspect all interface states',
                  status: 'pending',
                ),
              ],
            )
          : workspace.todo,
      interactions: _themePlanScenario
          ? const [
              PendingInteraction(
                id: 'driver-theme-plan',
                threadId: threadId,
                turnId: 'driver-origin-turn',
                kind: InteractionKind.userInput,
                title: 'Theme implementation plan',
                body: _themePlanMarkdown,
                payload: UserInputInteractionPayload(
                  questions: [
                    UserQuestionView(
                      id: agentSessionPlanConfirmationQuestionId,
                      header: 'Plan',
                      question: _themePlanMarkdown,
                      isOther: true,
                      isSecret: false,
                      options: [
                        UserQuestionOptionView(
                          label: agentSessionPlanApproveAnswer,
                          description: 'Approve this plan.',
                        ),
                        UserQuestionOptionView(
                          label: agentSessionPlanReviseAnswer,
                          description: 'Revise this plan.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ]
          : _fallbackInputScenario
          ? const [
              PendingInteraction(
                id: 'driver-fallback-input',
                threadId: threadId,
                turnId: 'driver-origin-turn',
                kind: InteractionKind.userInput,
                title: 'Continue task',
                body: '请输入“继续”以创建新的任务轮次。',
                payload: UserInputInteractionPayload(questions: []),
              ),
            ]
          : const [
              PendingInteraction(
                id: 'driver-tool',
                threadId: threadId,
                turnId: 'driver-origin-turn',
                kind: InteractionKind.toolApproval,
                title: 'Approve demo tool',
                body: 'Run a deterministic demo command.',
                payload: ToolApprovalInteractionPayload(
                  toolName: 'demo_tool',
                  workingDirectory: r'C:\demo',
                ),
              ),
              PendingInteraction(
                id: 'driver-input',
                threadId: threadId,
                turnId: 'driver-origin-turn',
                kind: InteractionKind.userInput,
                title: 'Demo question',
                body: 'Choose a deterministic answer.',
                payload: UserInputInteractionPayload(
                  questions: [
                    UserQuestionView(
                      id: 'driver-question',
                      header: 'Driver',
                      question: 'Continue?',
                      isOther: false,
                      isSecret: false,
                      options: [],
                    ),
                  ],
                ),
              ),
            ],
    );
  }
}

String _demoProvisionalThreadTitle(String prompt) {
  final normalized = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return 'New Session';
  return normalized.runes.take(80).map(String.fromCharCode).join();
}

/// demo `worktree` 会话地址：与项目目录同级的 `worktrees` 目录，仅供 GUI 验收展示。
String _demoWorktreePath(String projectPath, String threadId) =>
    '${projectPath.replaceAll('\\', '/')}-worktrees/$threadId';

ObservedResource<T> _demoReadyResource<T>(int revision, T value) {
  return ReadyObservedResource(
    revision: revision,
    updatedAt: revision,
    lastCheckedAt: null,
    value: value,
  );
}

ObservedResource<T> _demoInitialResource<T>() =>
    UninitializedObservedResource(updatedAt: 0);

SkillsStateSnapshot _demoSkillsState(
  String projectId,
  int revision, {
  List<String> skills = const [
    'flutter-ui-polish',
    'runtime-review',
    'studio-settings',
  ],
}) {
  return SkillsStateSnapshot.fromState(
    projectId: projectId,
    state: _demoReadyResource(
      revision,
      SkillsStateData(
        configFingerprint: 'demo',
        catalogRevision: revision,
        skills: skills,
        summaries: [
          for (final skill in skills)
            SkillSummaryView(
              name: skill,
              description: switch (skill) {
                'flutter-ui-polish' =>
                  'Polish Flutter layouts, interactions, and visual details.',
                'runtime-review' =>
                  'Review runtime behavior, lifecycle, and concurrency.',
                'studio-settings' =>
                  'Manage Studio accounts, skills, and application settings.',
                _ => 'Installed Studio skill.',
              },
              source: 'demo',
              providerId: 'demo',
              modelInvocable: true,
              userInvocable: true,
              resourceBase: const SkillResourceBaseView(
                SkillResourceBaseKind.opaque,
                'demo',
              ),
            ),
        ],
        warnings: const [],
      ),
    ),
  );
}

/// demo 内的 argv 值比较：顺序与内容都要一致，才可沿用旧连接身份。
bool _sameDemoArgs(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
