import 'dart:async';
import 'dart:typed_data';

import '../../anywork_client.dart';
import '../../models.dart';
import '../../studio_ports.dart';
import 'bridge/studio_channels.dart';
import 'bridge/product_topic_registry.dart';
import 'commands/directory_commands.dart';
import 'commands/account_usage_queries.dart';
import 'commands/model_detail_queries.dart';
import 'commands/bots_commands.dart';
import 'commands/bots_queries.dart';
import 'commands/settings_commands.dart';
import 'commands/acp_commands.dart';
import 'commands/acp_install_commands.dart';
import 'commands/thread_commands.dart';
import 'commands/command_lane.dart';
import 'drafts/attachment_drafts.dart';
import 'drafts/composer_draft_owner.dart';
import 'drafts/start_session_draft_owner.dart';
import 'mode_editor_owner.dart';
import 'agent_directory_queries.dart';
import 'thread_session.dart';
import 'thread_session_state.dart';
import 'stores/project_store.dart';
import 'stores/settings_store.dart';
import 'stores/selection_store.dart';
import 'stores/thread_directory_store.dart';
import 'stores/mcp_store.dart';
import 'stores/lsp_store.dart';
import 'stores/mode_catalog_store.dart';
import 'stores/account_usage_store.dart';
import 'stores/acp_auth_store.dart';
import 'stores/acp_install_store.dart';
import 'stores/recovery_store.dart';
import 'stores/session_costs_store.dart';
import 'stores/skills_store.dart';
import 'stores/updater_store.dart';
import 'stores/persistence_store.dart';
import 'stores/bots_store.dart';
import 'stores/bots_send_store.dart';
import 'stores/child_interaction_store.dart';
import 'update_client.dart';
import 'stores/domain_sync.dart' show typedCommandFailure;

/// Application-instance owner. Providers borrow read models; navigation and exit
/// change resource demand explicitly. No state is shared with another client.
class AnyworkClient {
  AnyworkClient({
    required this.transport,
    required this.clientId,
    ResourceBudget? budget,
    Future<String?> Function(Uint8List)? clipboardImageStager,
    Future<void> Function(String)? clipboardImageCleanup,
    StudioUpdateApi? updateApi,
    bool updatesEnabled = false,
    int Function()? threadCommandsClock,
  }) : budget = budget ?? ResourceBudget() {
    mutations = MutationBoard(clientId: clientId, budget: this.budget);
    modeEditor = ModeEditorOwner(this);
    channels = StudioChannels(this, transport);
    directoryCommands = DirectoryCommands(this);
    accountUsageQueries = AccountUsageQueries(this);
    modelDetailQueries = ModelDetailQueries(this);
    settingsCommands = SettingsCommands(this);
    acpCommands = AcpCommands(this);
    acpInstallCommands = AcpInstallCommands(this);
    botsCommands = BotsCommands(this);
    botsQueries = BotsQueries(this);
    // Test seam: the wall clock used to record command start facts.
    threadCommands = ThreadCommands(this, nowMs: threadCommandsClock);
    remote = RemoteActions(transport);
    attachments = AttachmentDraftsOwner(
      this,
      clipboardImageStager: clipboardImageStager,
      clipboardImageCleanup: clipboardImageCleanup,
    );
    startDraft = StartSessionDraftOwner(this);
    updates = StudioUpdateClient(
      api: updateApi ?? const _DisabledUpdateApi(),
      updater: updater,
      enabled: updatesEnabled,
      budget: this.budget,
    );
    workspace = WorkspaceController(
      onThreadChanged: (id) {
        if (id == null) {
          selection.beginNewThread();
        } else {
          final thread = findThread(id);
          if (thread == null)
            throw StateError('Thread is not in the directory');
          selection.selectThread(projectId: thread.projectId, threadId: id);
        }
      },
    );
    _selectionObservation = selection.source.watch(_selectionChanged);
    _canonicalObservations.addAll([
      settings.source.watch((value) {
        if (value.configLoaded)
          observeResource('settings', value.settingsRevision);
      }),
      threadDirectory.source.watch((value) {
        if (value.loaded)
          observeResource('thread-directory', value.window.revision);
      }),
      modeCatalog.source.watch((value) {
        if (value.loaded)
          observeResource('thread-mode-catalog', value.revision);
      }),
      // ACP 认证回执的 targets 是 `acp-auth`：产品 topic 帧与命令响应进入同一
      // reducer，因此该领域也必须把 canonical 水位登记给 MutationBoard，否则
      // check/login/cancel 受理后永远停在 awaitingObservation。未加载时没有水位，
      // 首帧（含 revision 0）才是有效观察。
      acpAuth.source.watch((value) {
        final snapshot = value.value;
        if (value.loaded && snapshot != null)
          observeResource('acp-auth', snapshot.revision);
      }),
      // 安装回执的 targets 是 `acp-install`：与认证同理由同一 reducer 收敛，
      // 因此该领域也必须把 canonical 水位（含 revision 0）登记给 MutationBoard。
      acpInstall.source.watch((value) {
        final snapshot = value.value;
        if (value.loaded && snapshot != null)
          observeResource('acp-install', snapshot.revision);
      }),
      bots.source.watch((value) {
        if (!value.loaded) return;
        observeResource('bots', value.revision);
        for (final bot in value.value?.bots ?? const <BotSnapshot>[]) {
          observeResource('bot:${bot.id}', bot.configRevision);
        }
      }),
    ]);
  }

  final StudioTransport transport;
  final String clientId;
  final ResourceBudget budget;
  late final MutationBoard mutations;
  late final WorkspaceController workspace;
  late final StudioChannels channels;
  late final ModeEditorOwner modeEditor;
  late final DirectoryCommands directoryCommands;
  late final AccountUsageQueries accountUsageQueries;
  late final ModelDetailQueries modelDetailQueries;
  late final SettingsCommands settingsCommands;
  late final AcpCommands acpCommands;
  late final AcpInstallCommands acpInstallCommands;
  late final BotsCommands botsCommands;
  late final BotsQueries botsQueries;
  late final ThreadCommands threadCommands;
  late final RemoteActions remote;
  late final AttachmentDraftsOwner attachments;
  late final StartSessionDraftOwner startDraft;
  late final StudioUpdateClient updates;
  final project = ProjectStore();
  final settings = SettingsStore();
  final selection = SelectionStore();
  final threadDirectory = ThreadDirectoryStore();
  final mcp = McpStore();
  final lsp = LspStore();
  final modeCatalog = ModeCatalogStore();
  final accountUsage = AccountUsageStore();
  final acpAuth = AcpAuthStore();
  final acpInstall = AcpInstallStore();
  final recovery = RecoveryStore();
  final updater = UpdaterStore();
  final persistence = PersistenceStore();
  final bots = BotsStore();
  final botsSends = BotsSendStore();
  final childInteractions = ChildInteractionStore();
  final bootstrapState = LatestValue(const StudioBootstrapState());
  final Map<String, SkillsStore> _skills = {};
  final Map<String, SessionCostsStore> _sessionCosts = {};
  final Map<String, StudioThreadSession> _sessions = {};
  final Map<String, ComposerDraftOwner> _composers = {};
  final Map<String, Future<CloseReport>> _retiring = {};
  final Map<String, UnresolvedResource> _unresolved = {};
  final Map<String, CloseReport> _closeReports = {};
  final Map<String, int> _reportGenerations = {};
  final Map<String, Future<void>> _pendingJoins = {};
  final resourceFailure = LatestValue<UnresolvedResource?>(null);

  final _activeSession = LatestValue<StudioThreadSession?>(null);
  final Map<String, ResourcePermit> _mirrorPermits = {};
  final CommandLane _queries = CommandLane();
  int _querySequence = 0;
  final List<Observation> _canonicalObservations = [];
  String? _runtimeOwnerEpoch;
  late final Observation _selectionObservation;
  BridgeTopicLeaseBundle? _applicationTopics;
  BridgeTopicLeaseBundle? _selectionTopics;
  String? _selectionTopicKey;
  String? _activeThread;
  Future<void>? _bootstrapping;
  Future<CloseReport>? _closing;
  bool _closed = false;

  bool get isClosed => _closed;
  List<UnresolvedResource> get unresolvedResources => List.unmodifiable([
    ..._unresolved.values,
    for (final report in _closeReports.values) ...report.unresolved,
    ...channels.unresolvedResources,
    ...updates.unresolvedResources,
    for (final operation in mutations.operations.where(
      (value) => value.isPending,
    ))
      UnresolvedResource(
        owner: 'operation:${operation.id.value}',
        attemptId: const AttemptId(0),
        reason: operation.error ?? operation.phase,
      ),
  ]);

  ThreadSessionState? sessionState(String threadId) =>
      _sessions[threadId]?.state;
  StudioThreadSession? existingSession(String threadId) => _sessions[threadId];

  /// The selected, admitted Session owner. Reading never admits a resource.
  StudioThreadSession? get activeSession => _activeSession.value;

  /// Atomically observes availability with its current snapshot. The publisher
  /// stays private; an admission retry publishes the owner stored in _sessions.
  LatestWatch<StudioThreadSession?> watchActiveSession(
    void Function(StudioThreadSession?) listener,
  ) => _activeSession.watchLatest(listener);

  /// Resource admission is an explicit workspace action, never an observation.
  void retrySession(String threadId) {
    _ensureOpen();
    final selected = selection.state;
    if (selected.selectedThreadId != threadId ||
        selected.needsOpen ||
        _activeThread != threadId)
      return;
    _selectionChanged(selected);
    try {
      final owner = session(threadId);
      if (owner.isActive) {
        owner.retry();
      } else {
        owner.start();
      }
      _activeSession.publish(owner);
      if (resourceFailure.value?.owner == 'session:$threadId') {
        resourceFailure.publish(null);
      }
    } catch (error) {
      resourceFailure.publish(
        UnresolvedResource(
          owner: 'session:$threadId',
          attemptId: const AttemptId(0),
          reason: error,
        ),
      );
    }
  }

  Iterable<ThreadSessionState> get sessionStates =>
      List.unmodifiable(_sessions.values.map((owner) => owner.state));
  ComposerThreadState? composerState(String threadId) =>
      _composers[threadId]?.state;
  ComposerDraftOwner? existingComposer(String threadId) => _composers[threadId];
  SkillsStore? existingSkills(String projectId) => _skills[projectId];
  SessionCostsStore? existingSessionCosts(String rootThreadId) =>
      _sessionCosts[rootThreadId];
  Iterable<SkillsStore> get ownedSkills => List.unmodifiable(_skills.values);
  Iterable<SessionCostsStore> get ownedSessionCosts =>
      List.unmodifiable(_sessionCosts.values);
  List<ComposerDraftOwner> projectComposers(String projectId) =>
      List.unmodifiable([
        for (final entry in _composers.entries)
          if ((_sessions[entry.key]?.state.workspace?.thread.projectId ??
                  findThread(entry.key)?.projectId) ==
              projectId)
            entry.value,
      ]);
  Future<void> discardProjectDrafts(
    String projectId,
    List<ComposerDraftOwner> owners,
  ) async {
    await Future.wait<void>([
      startDraft.discardProject(projectId),
      for (final owner in owners)
        () async {
          await owner.discard();
          await owner.close();
          if (identical(_composers[owner.threadId], owner))
            _composers.remove(owner.threadId);
        }(),
    ]);
  }

  List<ProductTopic> get applicationTopics =>
      _applicationTopics?.topics ?? const [];

  SkillsStore skills(String projectId) => _skills.putIfAbsent(
    projectId,
    () => _mirror('skills:$projectId', () => SkillsStore(projectId)),
  );
  SessionCostsStore sessionCosts(String rootThreadId) =>
      _sessionCosts.putIfAbsent(
        rootThreadId,
        () => _mirror(
          'costs:$rootThreadId',
          () => SessionCostsStore(rootThreadId),
        ),
      );
  ComposerDraftOwner composer(String threadId) {
    final existing = _composers[threadId];
    if (existing != null) return existing;
    _ensureOpen();
    return _composers.putIfAbsent(
      threadId,
      () => ComposerDraftOwner(this, threadId),
    );
  }

  StudioThreadSession session(String threadId) => _sessions.putIfAbsent(
    threadId,
    () => _mirror('session:$threadId', () {
      final owner = StudioThreadSession(
        threadId,
        transport: transport,
        directory: threadDirectory,
        budget: budget,
      );
      _canonicalObservations.add(
        owner.source.watch((value) {
          if (value.hasSnapshot)
            observeResource('thread-state:$threadId', value.revision);
          final route = value.runtime?.modelRoute;
          if (route != null)
            observeResource('thread-route:$threadId', route.revision);
        }),
      );
      return owner;
    }),
  );

  void observeResource(String key, int revision) {
    final epoch = _runtimeOwnerEpoch;
    if (epoch == null) return;
    mutations.observe(
      ResourceStamp(resourceKey: key, ownerEpoch: epoch, revision: revision),
    );
  }

  T _mirror<T>(String owner, T Function() create) {
    _ensureOpen();
    final permit = budget.acquire(ResourceKind.readModel, owner: owner);
    try {
      final value = create();
      _mirrorPermits[owner] = permit;
      return value;
    } catch (_) {
      permit.release();
      rethrow;
    }
  }

  void retryResource(ProductTopic topic) {
    _ensureOpen();
    final selected = selection.state;
    final selectedRoot = findThread(selected.selectedThreadId ?? '')
        ?.effectiveRootThreadId;
    if (topic is SkillsTopic && topic.projectId == selected.selectedProjectId ||
        topic is SessionCostsTopic && topic.rootThreadId == selectedRoot) {
      // Admission may have failed before a topic owner existed. Retry logical
      // demand here rather than asking an observer to create that owner.
      _selectionChanged(selected);
    }
    channels.retryTopic(topic);
  }

  Future<ThreadActivityDetail> readThreadActivityDetail(
    String threadId,
    String identity,
  ) => _query(
    'activity:$threadId:$identity',
    () => transport.readThreadActivityDetail(threadId, identity),
  );

  Future<Uint8List> readAttachmentBytes(String threadId, String attachmentId) =>
      _query(
        'attachment:$threadId:$attachmentId',
        () => transport.readThreadAttachment(threadId, attachmentId),
      );

  Future<T> _query<T>(String target, Future<T> Function() read) async {
    _ensureOpen();
    final permit = budget.acquire(
      ResourceKind.pendingOperation,
      owner: 'query:${++_querySequence}:$target',
    );
    try {
      return await _queries.run(read);
    } finally {
      permit.release();
    }
  }

  /// Bootstrap has a separate, one-shot capability. Successful commands never
  /// call this path; subsequent baselines arrive through their own owner topic.
  Future<void> bootstrap() {
    _ensureOpen();
    final current = _bootstrapping;
    if (current != null) return current;
    bootstrapState.publish(
      const StudioBootstrapState(phase: StudioBootstrapPhase.loading),
    );
    late final Future<void> task;
    task = _bootstrap().then<void>(
      (_) {
        if (!_closed) {
          bootstrapState.publish(
            const StudioBootstrapState(phase: StudioBootstrapPhase.ready),
          );
        }
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_bootstrapping, task)) _bootstrapping = null;
        if (!_closed) {
          bootstrapState.publish(
            StudioBootstrapState(
              phase: StudioBootstrapPhase.failed,
              failure: typedCommandFailure(
                error,
                correlationId: '$clientId-bootstrap',
              ),
            ),
          );
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _bootstrapping = task;
    return task;
  }

  Future<void> _bootstrap() async {
    _ensureOpen();
    final snapshot = await transport.readBootstrap();
    if (_closed) return;
    applyBootstrap(snapshot);
    final catalog = await transport.loadAccountCatalog();
    if (_closed) return;
    settings.applyAccountCatalog(catalog);
    // ACP 目录是只读默认值：只登记模板与官方安装说明，不启动外部程序。
    final acpCatalog = await transport.loadAcpAccountCatalog();
    if (_closed) return;
    settings.applyAcpAccountCatalog(acpCatalog);
    _applicationTopics = channels.acquireTopics([
      ...bridgeShellTopics,
      const AgentProfilesTopic(),
      // ACP 认证观察属于应用级业务 owner：页面只借用快照，不创建/关闭订阅。
      const AcpAuthTopic(),
      // 安装进度同样属于应用级共享资产：离页只释放自己的观察，不取消下载。
      const AcpInstallTopic(),
      const McpTopic(),
      const LspTopic(),
      const AccountUsageTopic(),
      const PersistenceQueueTopic(),
      const BotsTopic(),
    ]);
  }

  void applyBootstrap(StudioBootstrap snapshot) {
    _runtimeOwnerEpoch = snapshot.ownerEpoch;
    project.applyProjectDirectory(snapshot.projectDirectory);
    project.applyAgentDirectory(snapshot.agentDirectory);
    threadDirectory.applyWindow(snapshot.threadDirectory);
    settings.merge(snapshot.settingsState);
    final profiles = snapshot.agentProfilesState;
    if (profiles != null) settings.applyAgentProfiles(profiles);
    recovery.apply(snapshot.recoveryState);
    mcp.apply(snapshot.mcpState);
    lsp.apply(snapshot.lspState);
    modeCatalog.apply(snapshot.threadModeCatalog);
    accountUsage.apply(snapshot.accountUsageState);
    updater.apply(snapshot.updaterState);
    persistence.applyState(snapshot.persistenceState);
    final queue = snapshot.persistenceQueueState;
    if (queue != null) persistence.applyQueue(queue);
    for (final entry in snapshot.skillsByProject.entries) {
      skills(entry.key).apply(entry.value);
    }
    for (final entry in snapshot.sessionCostsByRoot.entries) {
      sessionCosts(entry.key).apply(entry.value);
    }
    if (selection.state.selectedProjectId == null &&
        selection.state.selectedThreadId == null) {
      selection.restoreStartup(
        projectId: snapshot.selectedProjectId,
        threadId: snapshot.selectedThreadId,
        needsOpen: snapshot.selectedThreadId != null,
      );
    }
  }

  /// 账号面板的 typed 聚合视图：Native 账号与 ACP 接入按各自事实源合并。
  ///
  /// 读取不改变 demand：没有 ACP 目录或认证观察时只是没有对应条目。
  AccountDirectoryView get accountDirectory {
    final current = settings.state;
    return AccountDirectoryView.from(
      nativeAccounts: accountsWithCatalogMetadata(
        current.canonical?.accounts ?? const <AccountSettingsView>[],
        current.accountCatalog,
      ),
      acpAccounts: current.canonical?.acpAccounts ?? const [],
      nativeCatalog: current.accountCatalog,
      acpCatalog: current.acpCatalog,
      auth: acpAuth.state.value ?? const AcpAuthSnapshotView.empty(),
    );
  }

  StudioThread? findThread(String id) {
    for (final thread in [
      ...threadDirectory.state.window.threads,
      ...threadDirectory.state.overlayThreads,
    ]) {
      if (thread.id == id) return thread;
    }
    return null;
  }

  void _selectionChanged(SelectionStoreState next) {
    if (_closed) return;
    final projectId = next.selectedProjectId;
    final rootId = AgentDirectoryQueries.rootThreadId(
      threadId: next.selectedThreadId,
      agents: project.state.agents?.values ?? const [],
      threads: [
        ...threadDirectory.state.window.threads,
        ...threadDirectory.state.overlayThreads,
      ],
    );
    final topicKey = '$projectId/$rootId';
    if (_selectionTopicKey != topicKey) {
      final previous = _selectionTopics;
      _selectionTopics = null;
      _selectionTopicKey = null;
      if (previous != null) {
        // The registry retains the exact handle and permit if cancel fails.
        unawaited(
          previous.release().catchError((Object error) {
            resourceFailure.publish(
              UnresolvedResource(
                owner: 'selection-topics:$topicKey',
                attemptId: const AttemptId(0),
                reason: error,
              ),
            );
          }),
        );
      }
      try {
        _selectionTopics = channels.acquireTopics([
          if (projectId != null) SkillsTopic(projectId: projectId),
          if (rootId != null) SessionCostsTopic(rootThreadId: rootId),
        ]);
        _selectionTopicKey = topicKey;
        resourceFailure.publish(null);
      } catch (error) {
        resourceFailure.publish(
          UnresolvedResource(
            owner: 'selection-topics:$topicKey',
            attemptId: const AttemptId(0),
            reason: error,
          ),
        );
      }
    }
    final draftId = next.selectedThreadId;
    if (draftId != null && !_composers.containsKey(draftId)) {
      try {
        composer(draftId);
        if (resourceFailure.value?.owner == 'composer:$draftId') {
          resourceFailure.publish(null);
        }
      } catch (error) {
        resourceFailure.publish(
          UnresolvedResource(
            owner: 'composer:$draftId',
            attemptId: const AttemptId(0),
            reason: error,
          ),
        );
      }
    }
    final nextId = next.needsOpen ? null : next.selectedThreadId;
    if (_activeThread == nextId) return;
    final old = _activeThread;
    _activeThread = nextId;
    _activeSession.publish(null);
    if (old != null) _retireSession(old);
    if (nextId != null) {
      try {
        final owner = session(nextId);
        owner.start();
        _activeSession.publish(owner);
      } catch (error) {
        resourceFailure.publish(
          UnresolvedResource(
            owner: 'session:$nextId',
            attemptId: const AttemptId(0),
            reason: error,
          ),
        );
      }
    }
  }

  void _retireSession(String id) {
    final owner = _sessions[id];
    if (owner == null) return;
    final retirement = owner.retire();
    final reportOwner = 'session:$id';
    final generation = (_reportGenerations[reportOwner] ?? 0) + 1;
    _reportGenerations[reportOwner] = generation;
    _retiring[id] = retirement;
    unawaited(
      retirement.then(
        (report) {
          if (identical(_retiring[id], retirement)) {
            unawaited(_retiring.remove(id));
            if (_reportGenerations[reportOwner] == generation) {
              _closeReports[reportOwner] = report;
            }
          }
        },
        onError: (Object error, StackTrace stack) {
          if (_reportGenerations[reportOwner] != generation) return;
          _unresolved['session:$id'] = UnresolvedResource(
            owner: 'session:$id',
            attemptId: const AttemptId(0),
            reason: error,
          );
        },
      ),
    );
  }

  void reconcileSelectedProject() {
    final projects = project.state.projects?.values ?? const <StudioProject>[];
    final sorted = [...projects]..sort((a, b) => a.id.compareTo(b.id));
    selection.retainProjects(
      projects.map((value) => value.id).toSet(),
      fallbackProjectId: sorted.firstOrNull?.id,
    );
  }

  void reconcileRemovedThreads(Set<String> removed) {
    for (final id in removed) {
      releaseSession(id);
    }
    final selected = selection.state.selectedThreadId;
    if (selected == null || !removed.contains(selected)) return;
    final projectId = selection.state.selectedProjectId;
    selection.replaceRemovedThread(
      threadDirectory.state.window.threads
          .where((thread) => thread.isRoot && thread.projectId == projectId)
          .firstOrNull
          ?.id,
    );
  }

  void releaseSession(String id) {
    _retireSession(id);
  }

  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);

  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    _activeSession.publish(null);
    _activeSession.close();
    _selectionObservation.cancel();
    _queries.seal();
    attachments.sealAdmissions();
    // All independent owners are sealed and begin closing before the first
    // await. A blocked draft/open cannot consume the other owners' deadline.
    final draftWork = Future.wait<void>([
      startDraft.close(),
      for (final owner in _composers.values) owner.close(),
    ]);
    final work = <Future<void>>[
      _joinOwner('drafts', draftWork, deadline),
      _joinOwner('settings-commands', settingsCommands.close(), deadline),
      _joinOwner('directory-commands', directoryCommands.close(), deadline),
      _joinOwner(
        'account-usage-queries',
        accountUsageQueries.close(),
        deadline,
      ),
      _joinOwner('acp-commands', acpCommands.close(), deadline),
      _joinOwner('acp-install-commands', acpInstallCommands.close(), deadline),
      _joinOwner('model-detail-queries', modelDetailQueries.close(), deadline),
      _joinOwner('bots-commands', botsCommands.close(), deadline),
      _joinOwner('bots-queries', botsQueries.close(), deadline),
      _joinOwner('thread-commands', threadCommands.close(), deadline),
      _joinOwner('mode-editor', modeEditor.close(), deadline),
      _joinOwner('remote-commands', remote.close(), deadline),
      _joinOwner('queries', _queries.join(), deadline),
      for (final entry in _sessions.entries)
        _joinReport(
          'session:${entry.key}',
          entry.value.close(deadline: deadline),
          deadline,
        ),
      _joinReport('topics', channels.dispose(deadline: deadline), deadline),
      _joinReport('updates', updates.close(deadline: deadline), deadline),
      if (_bootstrapping case final boot?)
        _joinOwner(
          'bootstrap',
          boot.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {
              // A failed query has terminated. Its resource handles belong to the
              // transport/topic owners, which are joined separately below.
            },
          ),
          deadline,
        ),
    ];
    Future<void> closeAttachments() async {
      try {
        await draftWork;
      } finally {
        await attachments.close();
      }
    }

    work.add(_joinOwner('attachments', closeAttachments(), deadline));
    await Future.wait(work);
    for (final observation in _canonicalObservations) {
      observation.cancel();
    }
    _canonicalObservations.clear();
    settingsCommands.closeObservations();
    botsCommands.closeObservations();
    _applicationTopics = null;
    _selectionTopics = null;
    _releaseMirrorsIfResolved();
    return CloseReport(unresolved: unresolvedResources);
  }

  Future<void> _joinReport(
    String owner,
    Future<CloseReport> task,
    DateTime? deadline,
  ) {
    final generation = (_reportGenerations[owner] ?? 0) + 1;
    _reportGenerations[owner] = generation;
    return _joinOwner(
      owner,
      task.then<void>((report) {
        if (_reportGenerations[owner] == generation)
          _closeReports[owner] = report;
      }),
      deadline,
    );
  }

  Future<void> _joinOwner(
    String owner,
    Future<void> task,
    DateTime? deadline,
  ) async {
    final previous = _pendingJoins[owner];
    // Cleanup retry cannot replace an earlier still-running native owner.
    final joined = previous == null || identical(previous, task)
        ? task
        : Future.wait<void>([previous, task]).then<void>((_) {});
    _pendingJoins[owner] = joined;
    final settled = joined.then<void>(
      (_) {
        if (identical(_pendingJoins[owner], joined)) {
          unawaited(_pendingJoins.remove(owner));
          _unresolved.remove(owner);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_pendingJoins[owner], joined)) {
          unawaited(_pendingJoins.remove(owner));
          _unresolved[owner] = UnresolvedResource(
            owner: owner,
            attemptId: const AttemptId(0),
            reason: error,
          );
        }
      },
    );
    try {
      final remaining = deadline?.difference(DateTime.now());
      await (remaining == null
          ? settled
          : settled.timeout(remaining.isNegative ? Duration.zero : remaining));
    } on TimeoutException catch (error) {
      // The original task and its owner remain held; a late real completion
      // clears this entry through the handler installed above.
      _unresolved[owner] = UnresolvedResource(
        owner: owner,
        attemptId: const AttemptId(0),
        reason: error,
      );
    }
  }

  /// Explicit resource cleanup only. Unknown business writes are never replayed.
  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    final pending = Map.of(_pendingJoins);
    final work = <Future<void>>[
      for (final entry in _sessions.entries)
        _joinReport(
          'session:${entry.key}',
          entry.value.retryCleanup(deadline: deadline),
          deadline,
        ),
      _joinReport(
        'topics',
        channels.retryCleanup(deadline: deadline),
        deadline,
      ),
      if (_closed)
        _joinReport(
          'updates',
          updates.retryCleanup(deadline: deadline),
          deadline,
        ),
      _joinOwner('attachments', attachments.retryCleanup(), deadline),
      for (final entry in pending.entries)
        if (identical(_pendingJoins[entry.key], entry.value))
          _joinOwner(entry.key, entry.value, deadline),
    ];
    await Future.wait(work);
    _releaseMirrorsIfResolved();
    return CloseReport(unresolved: unresolvedResources);
  }

  void _releaseMirrorsIfResolved() {
    if (!_closed || unresolvedResources.isNotEmpty) return;
    for (final permit in _mirrorPermits.values) {
      permit.release();
    }
    _mirrorPermits.clear();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('The application client is closed');
  }
}

final class _DisabledUpdateApi implements StudioUpdateApi {
  const _DisabledUpdateApi();
  Never _disabled() => throw StateError('Updates are disabled');
  @override
  Future<UpdaterStateSnapshot> read() async => _disabled();
  @override
  Future<UpdaterStateSnapshot> check() async => _disabled();
  @override
  Future<void> startAutomaticUpdate() async => _disabled();
  @override
  Future<void> cancelAutomaticUpdate() async {}
  @override
  Future<StudioUpdateOperation> startPreparation({
    required int expectedRevision,
    required String version,
  }) async => _disabled();
}
