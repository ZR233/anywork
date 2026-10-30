import 'dart:async';
import 'dart:typed_data';

import '../../accounts_ports.dart';
import '../../model_directory.dart';

import '../../anywork_client.dart';
import '../../models.dart';
import '../../studio_ports.dart';
import '../conversation/data/conversation_repository_impl.dart';
import '../drafts/data/drafts_repository_impl.dart';
import '../drafts/data/drafts_dependencies.dart';
import 'bridge/studio_channels.dart';
import 'bridge/product_topic_registry.dart';
import 'commands/directory_commands.dart';
import 'commands/bots_commands.dart';
import 'commands/bots_queries.dart';
import 'commands/settings_commands.dart';
import 'commands/thread_commands.dart';
import 'commands/command_lane.dart';
import '../modes/domain/mode_editor_owner.dart';
import 'agent_directory_queries.dart';
import 'stores/project_store.dart';
import 'stores/settings_store.dart';
import 'stores/selection_store.dart';
import 'stores/thread_directory_store.dart';
import 'stores/mcp_store.dart';
import 'stores/lsp_store.dart';
import '../modes/domain/mode_catalog_store.dart';
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
    SettingsWriteCoordinator? settingsWrites,
    MutationBoard? mutationBoard,
    AccountDomainResources? accountDomains,
    Future<String?> Function(Uint8List)? clipboardImageStager,
    Future<void> Function(String)? clipboardImageCleanup,
    StudioUpdateApi? updateApi,
    bool updatesEnabled = false,
    int Function()? threadCommandsClock,
  }) : budget = budget ?? ResourceBudget(),
       settingsWrites = settingsWrites ?? SettingsWriteCoordinator(),
       _accountDomains = accountDomains {
    mutations =
        mutationBoard ?? MutationBoard(clientId: clientId, budget: this.budget);
    modeEditor = ModeEditorOwner(this);
    channels = StudioChannels(this, transport);
    directoryCommands = DirectoryCommands(this);
    settingsCommands = SettingsCommands(this);
    botsCommands = BotsCommands(this);
    botsQueries = BotsQueries(this);
    // Test seam: the wall clock used to record command start facts.
    threadCommands = ThreadCommands(
      this,
      childInteractions: _childInteractions,
      nowMs: threadCommandsClock,
    );
    remote = RemoteActions(transport);
    final conversationOwner = ConversationRepositoryImpl(
      transport: transport,
      directory: threadDirectory,
      budget: this.budget,
      onRevision: observeResource,
      onVisibleThreadChanged: _childInteractions.setVisibleHostThread,
    );
    conversations = conversationOwner;
    drafts = DraftsRepositoryImpl(
      DraftsDependencies(
        budget: this.budget,
        mutations: mutations,
        conversations: conversations,
        inputFacts: conversationOwner,
        settings: settings.source,
        project: project.source,
        selection: selection.source,
        recovery: recovery.source,
        modelAccounts: () => modelAccounts,
        threads: () => [
          ...threadDirectory.state.window.threads,
          ...threadDirectory.state.overlayThreads,
        ],
        findThread: findThread,
        threadCommands: threadCommands,
        transport: transport,
      ),
      clipboardImageStager: clipboardImageStager,
      clipboardImageCleanup: clipboardImageCleanup,
    );
    updates = StudioUpdateClient(
      api: updateApi ?? const _DisabledUpdateApi(),
      updater: updater,
      enabled: updatesEnabled,
      budget: this.budget,
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
  final SettingsWriteCoordinator settingsWrites;
  final AccountDomainResources? _accountDomains;
  bool modelCatalogLoaded = false;
  int modelCatalogRevision = 0;

  List<ModelSelectionAccount> get modelAccounts {
    final domains = _accountDomains;
    return domains == null
        ? const []
        : modelSelectionAccounts(
            domains.accounts.state.value,
            domains.models.state.value,
          );
  }

  void acceptSettingsSnapshot(
    SettingsStateSnapshot snapshot, {
    SettingsMergeScope scope = SettingsMergeScope.both,
    SettingsWriteOwner? owner,
  }) {
    final captured = owner ?? settingsWrites.captureOwner();
    settingsWrites.requireOwner(captured);
    final epoch = _runtimeOwnerEpoch;
    settings.merge(snapshot, scope: scope);
    // Read-model publication invokes listeners synchronously. A listener may
    // reconnect, so the remainder still belongs to captured, never to whichever
    // epoch happens to be installed after that notification returns.
    settingsWrites.requireOwner(captured);
    if (scope != SettingsMergeScope.catalogOnly &&
        epoch != null &&
        snapshot.state.value != null) {
      settingsWrites.observe(
        ResourceStamp(
          resourceKey: 'settings',
          ownerEpoch: epoch,
          revision: snapshot.revision,
        ),
      );
    }
    if (scope != SettingsMergeScope.configOnly &&
        epoch != null &&
        snapshot.state.value != null) {
      _accountDomains?.acceptCatalog(snapshot, epoch, owner: captured);
      settingsWrites.requireOwner(captured);
      modelCatalogLoaded = true;
      if (snapshot.modelCatalogRevision > modelCatalogRevision)
        modelCatalogRevision = snapshot.modelCatalogRevision;
    }
  }

  void acceptSettingsReply(
    SettingsCommandReply reply, {
    SettingsWriteOwner? owner,
  }) {
    final captured = owner ?? settingsWrites.captureOwner();
    settingsWrites.requireOwner(captured);
    final epoch = _runtimeOwnerEpoch;
    if (epoch != null &&
        reply.receipt.targets.any(
          (target) =>
              target.resourceKey == 'settings' && target.ownerEpoch != epoch,
        ))
      return;
    final domains = _accountDomains;
    if (domains == null) {
      acceptSettingsSnapshot(reply.snapshot, owner: captured);
    } else {
      domains.acceptReply(reply, owner: captured);
    }
    settingsWrites.requireOwner(captured);
  }

  late final MutationBoard mutations;
  late final StudioChannels channels;
  late final ModeEditorOwner modeEditor;
  late final DirectoryCommands directoryCommands;
  late final SettingsCommands settingsCommands;
  late final BotsCommands botsCommands;
  late final BotsQueries botsQueries;
  late final ThreadCommands threadCommands;
  late final RemoteActions remote;
  late final ConversationRepository conversations;
  late final DraftsRepository drafts;
  late final StudioUpdateClient updates;
  final project = ProjectStore();
  final settings = SettingsStore();
  final selection = SelectionStore();
  final threadDirectory = ThreadDirectoryStore();
  final mcp = McpStore();
  final lsp = LspStore();
  final modeCatalog = ModeCatalogStore();
  final recovery = RecoveryStore();
  final updater = UpdaterStore();
  final persistence = PersistenceStore();
  final bots = BotsStore();
  final botsSends = BotsSendStore();
  final _childInteractions = ChildInteractionStore();
  ChildInteractionsView get childInteractions => _childInteractions;
  final bootstrapState = LatestValue(const StudioBootstrapState());
  final Map<String, SkillsStore> _skills = {};
  final Map<String, SessionCostsStore> _sessionCosts = {};
  final Map<String, UnresolvedResource> _unresolved = {};
  final Map<String, CloseReport> _closeReports = {};
  final Map<String, int> _reportGenerations = {};
  final Map<String, Future<void>> _pendingJoins = {};
  final resourceFailure = LatestValue<UnresolvedResource?>(null);

  final Map<String, ResourcePermit> _mirrorPermits = {};
  final CommandLane _queries = CommandLane();
  int _querySequence = 0;
  final List<Observation> _canonicalObservations = [];
  String? _runtimeOwnerEpoch;
  late final Observation _selectionObservation;
  BridgeTopicLeaseBundle? _applicationTopics;
  BridgeTopicLeaseBundle? _selectionTopics;
  String? _selectionTopicKey;
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

  SkillsStore? existingSkills(String workspaceId) => _skills[workspaceId];
  SessionCostsStore? existingSessionCosts(String rootThreadId) =>
      _sessionCosts[rootThreadId];
  Iterable<SkillsStore> get ownedSkills => List.unmodifiable(_skills.values);
  Iterable<SessionCostsStore> get ownedSessionCosts =>
      List.unmodifiable(_sessionCosts.values);
  List<ProductTopic> get applicationTopics =>
      _applicationTopics?.topics ?? const [];

  SkillsStore skills(String workspaceId) => _skills.putIfAbsent(
    workspaceId,
    () => _mirror('skills:$workspaceId', () => SkillsStore(workspaceId)),
  );
  SessionCostsStore sessionCosts(String rootThreadId) =>
      _sessionCosts.putIfAbsent(
        rootThreadId,
        () => _mirror(
          'costs:$rootThreadId',
          () => SessionCostsStore(rootThreadId),
        ),
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
    if (topic is SkillsTopic && topic.workspaceId == selected.selectedProjectId ||
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
    _applicationTopics = channels.acquireTopics([
      ...bridgeShellTopics,
      const AgentProfilesTopic(),
      const McpTopic(),
      const LspTopic(),
      const PersistenceQueueTopic(),
      const BotsTopic(),
    ]);
  }

  void applyBootstrap(StudioBootstrap snapshot) {
    final changed = _runtimeOwnerEpoch != snapshot.ownerEpoch;
    _runtimeOwnerEpoch = snapshot.ownerEpoch;
    settingsWrites.adoptOwnerEpoch(snapshot.ownerEpoch);
    final owner = settingsWrites.captureOwner();
    final finishOwnerChange = _accountDomains?.prepareOwnerEpoch(
      snapshot.ownerEpoch,
    );
    try {
      if (changed) {
        modelCatalogLoaded = false;
        modelCatalogRevision = 0;
        settings.resetForOwner();
        settingsWrites.requireOwner(owner);
      }
    } finally {
      finishOwnerChange?.call();
    }
    settingsWrites.requireOwner(owner);
    project.applyProjectDirectory(snapshot.projectDirectory);
    project.applyAgentDirectory(snapshot.agentDirectory);
    threadDirectory.applyWindow(snapshot.threadDirectory);
    acceptSettingsSnapshot(
      snapshot.settingsState,
      scope: SettingsMergeScope.configOnly,
      owner: owner,
    );
    final profiles = snapshot.agentProfilesState;
    if (profiles != null) settings.applyAgentProfiles(profiles);
    recovery.apply(snapshot.recoveryState);
    mcp.apply(snapshot.mcpState);
    lsp.apply(snapshot.lspState);
    modeCatalog.apply(snapshot.threadModeCatalog);
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
        workspaceId: snapshot.selectedProjectId,
        threadId: snapshot.selectedThreadId,
        needsOpen: snapshot.selectedThreadId != null,
      );
    }
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
    final workspaceId = next.selectedProjectId;
    final rootId = AgentDirectoryQueries.rootThreadId(
      threadId: next.selectedThreadId,
      agents: project.state.agents?.values ?? const [],
      threads: [
        ...threadDirectory.state.window.threads,
        ...threadDirectory.state.overlayThreads,
      ],
    );
    final topicKey = '$workspaceId/$rootId';
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
          if (workspaceId != null) SkillsTopic(workspaceId: workspaceId),
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
    if (draftId != null) drafts.composer(draftId);
    // Selection is not presentation demand. AppGraph/navigation explicitly
    // invokes conversations.setVisibleThread; settings must pass null.
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
      // A removed identity has no visible conversation demand.
      if (selection.state.selectedThreadId == id)
        conversations.setVisibleThread(null);
    }
    final selected = selection.state.selectedThreadId;
    if (selected == null || !removed.contains(selected)) return;
    final workspaceId = selection.state.selectedProjectId;
    selection.replaceRemovedThread(
      threadDirectory.state.window.threads
          .where((thread) => thread.isRoot && thread.workspaceId == workspaceId)
          .firstOrNull
          ?.id,
    );
  }

  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);

  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    _selectionObservation.cancel();
    _queries.seal();
    // Both domains seal synchronously before independent close joins await.
    final draftWork = drafts.close();
    final conversationWork = conversations.close(deadline: deadline);
    final work = <Future<void>>[
      _joinOwner('drafts', draftWork, deadline),
      _joinOwner('settings-commands', settingsCommands.close(), deadline),
      _joinOwner('directory-commands', directoryCommands.close(), deadline),
      _joinOwner('bots-commands', botsCommands.close(), deadline),
      _joinOwner('bots-queries', botsQueries.close(), deadline),
      _joinOwner('thread-commands', threadCommands.close(), deadline),
      _joinOwner('mode-editor', modeEditor.close(), deadline),
      _joinOwner('remote-commands', remote.close(), deadline),
      _joinOwner('queries', _queries.join(), deadline),
      _joinReport('conversations', conversationWork, deadline),
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
      _joinReport(
        'conversations',
        conversations.retryCleanup(deadline: deadline),
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
      _joinOwner('drafts', drafts.retryCleanup(), deadline),
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
