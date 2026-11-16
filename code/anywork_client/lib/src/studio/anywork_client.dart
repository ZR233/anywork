import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../accounts_ports.dart';
import '../../accounts.dart' show AcpAccountIdentity, AccountDemand;
import '../../acp_sessions.dart';
import '../../model_directory.dart';
import '../../lifecycle.dart';

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
    required ClientScope scope,
    SettingsWriteCoordinator? settingsWrites,
    MutationBoard? mutationBoard,
    AccountDomainResources? accountDomains,
    AcpBusinessPort? acpBusinessPort,
    Future<String?> Function(Uint8List)? clipboardImageStager,
    Future<void> Function(String)? clipboardImageCleanup,
    StudioUpdateApi? updateApi,
    bool updatesEnabled = false,
    int Function()? threadCommandsClock,
  }) : _scope = scope,
       settingsWrites = settingsWrites ?? SettingsWriteCoordinator(),
       _acpSessions = acpBusinessPort == null
           ? null
           : AcpSessionClient(port: acpBusinessPort),
       _accountDomains = accountDomains {
    mutations = mutationBoard ?? MutationBoard(clientId: clientId);
    threadDirectory = ThreadDirectoryStore(
      feed: transport,
      scope: scope.child('thread-directory'),
      onStamp: (stamp) => mutations.observe(stamp),
      onCleanupFailure: resourceFailure.publish,
    );
    modeEditor = ModeEditorOwner(this);
    channels = StudioChannels(
      this,
      transport,
      scope: scope.child('product-topics'),
    );
    directoryCommands = DirectoryCommands(this);
    settingsCommands = SettingsCommands(this);
    botsCommands = BotsCommands(this);
    botsQueries = BotsQueries(this);
    // Test seam: the wall clock used to record command start facts.
    threadCommands = ThreadCommands(this, nowMs: threadCommandsClock);
    remote = RemoteActions(transport);
    final conversationOwner = ConversationRepositoryImpl(
      transport: transport,
      directory: threadDirectory,
      scope: scope.child('conversation'),
      onRevision: observeResource,
    );
    conversations = conversationOwner;
    _scope.observe(
      conversationOwner.visibleThreadId.watch(_onVisibleThreadMirror),
    );
    drafts = DraftsRepositoryImpl(
      DraftsDependencies(
        mutations: mutations,
        conversations: conversations,
        inputFacts: conversationOwner,
        settings: settings.source,
        project: project.source,
        selection: selection.source,
        recovery: recovery.source,
        modelAccounts: () => modelAccounts,
        threadCommands: threadCommands,
        transport: transport,
        acpSessions: _acpSessions,
        directory: threadDirectory,
        accountSummaries: _accountDomains?.accounts.state,
        selectCreatedThread: (workspaceId, threadId) => selection.selectThread(
          workspaceId: workspaceId,
          threadId: threadId,
        ),
        selectionNavigationGeneration: () => selection.navigationGeneration,
      ),
      clipboardImageStager: clipboardImageStager,
      clipboardImageCleanup: clipboardImageCleanup,
    );
    updates = StudioUpdateClient(
      api: updateApi ?? const _DisabledUpdateApi(),
      updater: updater,
      enabled: updatesEnabled,
    );
    _scope.observe(selection.source.watch(_selectionChanged));
    _scope.observe(
      settings.source.watch((value) {
        if (value.configLoaded)
          observeResource('settings', value.settingsRevision);
      }),
    );
    _scope.observe(
      modeCatalog.source.watch((value) {
        if (value.loaded)
          observeResource('thread-mode-catalog', value.revision);
      }),
    );
    _scope.observe(
      bots.source.watch((value) {
        if (!value.loaded) return;
        observeResource('bots', value.revision);
        for (final bot in value.value?.bots ?? const <BotSnapshot>[]) {
          observeResource('bot:${bot.id}', bot.configRevision);
        }
      }),
    );
  }

  final StudioTransport transport;
  final String clientId;
  final ClientScope _scope;
  final SettingsWriteCoordinator settingsWrites;
  final AccountDomainResources? _accountDomains;
  final AcpSessionClient? _acpSessions;

  /// The application-owned ACP business Client, when explicitly assembled.
  ///
  /// Native-only applications need no ACP port. Access without one is explicitly
  /// unsupported, never a successful no-op or a Native command fallback.
  AcpSessionClient get acpSessions =>
      _acpSessions ??
      (throw UnsupportedError('ACP business port is not installed'));

  /// Whether this Client already owns the member's ACP conversation.
  /// Safe for Native-only applications and directory metadata still in flight.
  bool hasAcpConversation(String threadId) =>
      _acpSessions?.conversationForThread(threadId) != null;

  /// Opens the directory's original ACP member, never a replacement session.
  ///
  /// A resident display owner is reused. Cold opens explicitly load history;
  /// callers may instead request resume, which does not promise a transcript.
  Future<AcpConversationSession> openAcpConversation(
    String threadId, {
    bool resume = false,
  }) async {
    _ensureOpen();
    final sessions = acpSessions;
    final resident = sessions.conversationForThread(threadId);
    if (resident != null) return resident;
    final association = await _acpAssociation(threadId);
    return sessions.openConversation(
      OpenAcpSessionRequestView(
        accountId: association.reference.accountId,
        expectedConnectionRevision: association.revision,
        workspaceId: association.row.workspaceId,
        threadId: threadId,
        intent: resume
            ? AcpResumeIntentView(
                AcpRemoteSessionId(association.reference.acpSessionId),
              )
            : AcpLoadIntentView(
                AcpRemoteSessionId(association.reference.acpSessionId),
              ),
      ),
    );
  }

  /// Reads the peer's directory without importing its entries into the product.
  Future<AcpListSessionsResponseView> listAcpConversations(
    String threadId, {
    String? cursor,
  }) async {
    _ensureOpen();
    final owner = acpSessions.conversationForThread(threadId);
    final target = owner?.state.target;
    if (target == null ||
        owner!.state.capabilities?.listSessions != true ||
        !owner.state.ready) {
      throw UnsupportedError('The active ACP service cannot list sessions');
    }
    final association = await _acpAssociation(threadId);
    return acpSessions.list(
      AcpListRequestView(
        target: target,
        request: AcpListSessionsRequestView(
          cwd: association.reference.cwd,
          cursor: cursor,
        ),
      ),
    );
  }

  /// Explicitly opens one external session as a product association.
  ///
  /// Listing never calls this method. The operation is not retried and never
  /// substitutes New for an unsupported Load or Resume.
  Future<AcpConversationSession> openExternalAcpConversation(
    String sourceThreadId,
    AcpRemoteSessionId remoteSessionId, {
    bool resume = false,
    String? cwd,
  }) async {
    final source = acpSessions.conversationForThread(sourceThreadId);
    final capabilities = source?.state.capabilities;
    if (source == null ||
        !source.state.ready ||
        (resume
            ? capabilities?.resumeSession != true
            : capabilities?.loadSession != true)) {
      throw UnsupportedError('The active ACP service cannot open this session');
    }
    final navigation = selection.navigationGeneration;
    final association = await _acpAssociation(sourceThreadId);
    if (cwd != null && cwd != association.reference.cwd) {
      throw UnsupportedError(
        'Open this ACP session from its original workspace',
      );
    }
    final owner = await acpSessions.openConversation(
      OpenAcpSessionRequestView(
        accountId: association.reference.accountId,
        expectedConnectionRevision: association.revision,
        workspaceId: association.row.workspaceId,
        intent: resume
            ? AcpResumeIntentView(remoteSessionId)
            : AcpLoadIntentView(remoteSessionId),
      ),
    );
    final opened = await owner.source.waitFor(
      (state) =>
          (state.ready && !state.openPending) ||
          state.error != null ||
          state.disconnected ||
          state.observationEnded,
    );
    if (!opened.ready || opened.openPending) {
      throw opened.error ?? StateError('The ACP session did not open');
    }
    if (selection.isCurrentNavigation(navigation) &&
        selection.state.selectedThreadId == sourceThreadId) {
      selection.selectThread(
        workspaceId: association.row.workspaceId,
        threadId: opened.target!.threadId,
      );
    }
    return owner;
  }

  Future<
    ({
      SessionDirectoryRow row,
      AcpSessionReferenceView reference,
      BigInt revision,
    })
  >
  _acpAssociation(String threadId) =>
      _queries.run(() => _readAcpAssociation(threadId));

  Future<
    ({
      SessionDirectoryRow row,
      AcpSessionReferenceView reference,
      BigInt revision,
    })
  >
  _readAcpAssociation(String threadId) async {
    _ensureOpen();
    final accounts = _accountDomains?.accounts;
    if (accounts == null) {
      throw UnsupportedError('ACP account directory is not installed');
    }
    final demand = threadDirectory.observeThread(threadId);
    AccountDemand? accountDemand;
    try {
      accountDemand = accounts.observeSummaries();
      final metadata = await _waitForAcpRead(
        demand.state,
        (state) => !state.isLoading || state.error != null || state.closed,
      );
      if (metadata.error case final error?) throw error;
      final row = metadata.frame?.row;
      if (row == null || row.backend is! AcpAgentBackendView) {
        throw StateError('The ACP member is no longer available');
      }
      final reference = (row.backend as AcpAgentBackendView).reference;
      final accountState = await _waitForAcpRead(
        accounts.state,
        (state) => state.loaded || state.failure != null,
      );
      if (accountState.failure case final error?) throw error;
      final account = accountState.account(
        AcpAccountIdentity(reference.accountId),
      );
      final revision = account?.acpConnectionRevision;
      if (revision == null || account?.acpEnabled != true) {
        throw StateError('The ACP service is missing or disabled');
      }
      return (row: row, reference: reference, revision: BigInt.from(revision));
    } finally {
      await Future.wait<void>([
        demand.release(),
        if (accountDemand != null) accountDemand.release(),
      ]);
    }
  }

  Future<T> _waitForAcpRead<T>(
    ValueObservation<T> source,
    bool Function(T) ready,
  ) async {
    _ensureOpen();
    final completion = Completer<T>();
    final observation = _scope.observe(
      source.watch((value) {
        if (ready(value) && !completion.isCompleted) completion.complete(value);
      }),
    );
    try {
      if (ready(source.value)) completion.complete(source.value);
      return await Future.any<T>([
        completion.future,
        _acpReadClosed.future.then<T>((_) {
          throw StateError('The application client closed during ACP open');
        }),
      ]);
    } finally {
      observation.cancel();
    }
  }

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
  late final ThreadDirectoryStore threadDirectory;
  final mcp = McpStore();
  final lsp = LspStore();
  final modeCatalog = ModeCatalogStore();
  final recovery = RecoveryStore();
  final updater = UpdaterStore();
  final persistence = PersistenceStore();
  final bots = BotsStore();
  final botsSends = BotsSendStore();
  final bootstrapState = LatestValue(const StudioBootstrapState());
  final Map<McpScope, McpStore> _mcpCatalogs = {};
  final Map<String, ThreadMcpStore> _threadMcp = {};
  final Map<String, ThreadLspStore> _threadLsp = {};
  final Map<String, SkillsStore> _skills = {};
  final Map<String, SessionCostsStore> _sessionCosts = {};
  final Map<String, ChildInteractionStore> _childInteractions = {};
  final Map<String, UnresolvedResource> _unresolved = {};
  final Map<String, CloseReport> _closeReports = {};
  final Map<String, int> _reportGenerations = {};
  final Map<String, Future<void>> _pendingJoins = {};
  final String _reportScopeId = _newReportScopeId();
  final Map<Object, ClientResourceId> _reportResourceIds = {};
  int _reportResourceSequence = 0;
  final resourceFailure = LatestValue<UnresolvedResource?>(null);

  final CommandLane _queries = CommandLane();
  final Completer<void> _acpReadClosed = Completer<void>();
  String? _runtimeOwnerEpoch;
  BridgeTopicLeaseBundle? _applicationTopics;
  BridgeTopicLeaseBundle? _selectionTopics;
  ClientScope? _selectionTopicResources;
  String? _selectionTopicKey;
  Future<void>? _bootstrapping;
  Future<void>? _bootstrapJoin;
  Future<CloseReport>? _closing;
  bool _closed = false;

  bool get isClosed => _closed;
  List<UnresolvedResource> get unresolvedResources => CloseReport(
    unresolved: [
      ..._unresolved.values,
      for (final report in _closeReports.values) ...report.unresolved,
      ...updates.unresolvedResources,
      for (final operation in mutations.operations.where(
        (value) => value.isPending,
      ))
        _unresolvedResource(
          'operation:${operation.id.value}',
          operation.error ?? operation.phase,
          resourceId: _reportResourceId(operation.id),
          pending: true,
        ),
    ],
  ).unresolved;

  McpStore? existingMcpCatalog(McpScope scope) =>
      scope is HostMcpScope ? mcp : _mcpCatalogs[scope];
  ThreadMcpStore? existingThreadMcp(String threadId) => _threadMcp[threadId];
  ThreadLspStore? existingThreadLsp(String threadId) => _threadLsp[threadId];
  SkillsStore? existingSkills(String workspaceId) => _skills[workspaceId];
  SessionCostsStore? existingSessionCosts(String rootThreadId) =>
      _sessionCosts[rootThreadId];
  ChildInteractionStore? existingChildInteractions(String hostThreadId) =>
      _childInteractions[hostThreadId];
  Iterable<McpStore> get ownedMcpCatalogs =>
      List.unmodifiable(_mcpCatalogs.values);
  Iterable<ThreadMcpStore> get ownedThreadMcp =>
      List.unmodifiable(_threadMcp.values);
  Iterable<ThreadLspStore> get ownedThreadLsp =>
      List.unmodifiable(_threadLsp.values);
  Iterable<SkillsStore> get ownedSkills => List.unmodifiable(_skills.values);
  Iterable<SessionCostsStore> get ownedSessionCosts =>
      List.unmodifiable(_sessionCosts.values);
  Iterable<ChildInteractionStore> get ownedChildInteractions =>
      List.unmodifiable(_childInteractions.values);
  List<ProductTopic> get applicationTopics =>
      _applicationTopics?.topics ?? const [];

  McpStore mcpCatalog(McpScope scope) => scope is HostMcpScope
      ? mcp
      : _mcpCatalogs.putIfAbsent(scope, () => _mirror(() => McpStore(scope)));
  ThreadMcpStore threadMcp(String threadId) => _threadMcp.putIfAbsent(
    threadId,
    () => _mirror(() => ThreadMcpStore(threadId)),
  );
  ThreadLspStore threadLsp(String threadId) => _threadLsp.putIfAbsent(
    threadId,
    () => _mirror(() => ThreadLspStore(threadId)),
  );

  SkillsStore skills(String workspaceId) => _skills.putIfAbsent(
    workspaceId,
    () => _mirror(() => SkillsStore(workspaceId)),
  );
  SessionCostsStore sessionCosts(String rootThreadId) =>
      _sessionCosts.putIfAbsent(
        rootThreadId,
        () => _mirror(() => SessionCostsStore(rootThreadId)),
      );
  ChildInteractionStore childInteractions(String hostThreadId) =>
      _childInteractions.putIfAbsent(
        hostThreadId,
        () => _mirror(() => ChildInteractionStore(hostThreadId)),
      );

  // ---- 根可见子任务待决交互的页面主题需求 ----
  //
  // 当前页面观察与在途 child 决议各自持有必要需求：这里只管理页面份额。可见
  // 镜像在会话 demand 建立后发布，因此这里只借用已存在的会话；主题在当前会话
  // 首帧已准备且宿主是主会话后获取，避免先于根准备把未初始化误当空已决议。
  // 导航离开只释放页面份额，不撤销在途决议的事实观察。
  String? _childInteractionPageHost;
  BridgeTopicLease? _childInteractionPageLease;
  ClientScope? _childInteractionPageResources;
  Observation? _childInteractionPageWatch;
  String? _threadMcpPageThread;
  BridgeTopicLease? _threadMcpPageLease;
  ClientScope? _threadMcpPageResources;

  void _onVisibleThreadMirror(String? threadId) {
    _onThreadMcpVisibleMirror(threadId);
    _onChildInteractionVisibleMirror(threadId);
  }

  void _onThreadMcpVisibleMirror(String? threadId) {
    if (_closed) return;
    if (threadId == _threadMcpPageThread) return;
    _releaseThreadMcpPageDemand();
    if (threadId == null) return;
    _threadMcpPageThread = threadId;
    _acquireThreadMcpPageLease(threadId);
  }

  void _acquireThreadMcpPageLease(String threadId) {
    if (_closed ||
        _threadMcpPageThread != threadId ||
        _threadMcpPageLease != null) {
      return;
    }
    final resourceId = _allocateReportResourceId();
    ClientScope? resources;
    try {
      resources = _scope.child('thread-mcp-page');
      _threadMcpPageResources = resources;
      final lease = resources.acquireLease(
        'thread-mcp-page',
        () => channels.acquireThreadMcp(threadId),
      );
      if (!identical(_threadMcpPageResources, resources)) return;
      _threadMcpPageLease = lease;
      final failure = resourceFailure.value;
      if (failure?.owner == 'thread-mcp-page') {
        resourceFailure.publish(null);
      }
    } catch (error) {
      resources?.requestClose();
      if (identical(_threadMcpPageResources, resources)) {
        _threadMcpPageResources = null;
      }
      resourceFailure.publish(
        _unresolvedResource('thread-mcp-page', error, resourceId: resourceId),
      );
    }
  }

  void _releaseThreadMcpPageDemand() {
    _threadMcpPageThread = null;
    final lease = _threadMcpPageLease;
    _threadMcpPageLease = null;
    final resources = _threadMcpPageResources;
    _threadMcpPageResources = null;
    resources?.requestClose();
    if (lease == null) return;
    _releaseLease('thread-mcp-page', lease);
  }

  void _retryThreadMcpPageDemand(String threadId) {
    if (_closed ||
        _threadMcpPageThread != threadId ||
        _threadMcpPageLease != null) {
      return;
    }
    _acquireThreadMcpPageLease(threadId);
  }

  void _onChildInteractionVisibleMirror(String? threadId) {
    if (_closed) return;
    if (threadId == _childInteractionPageHost &&
        (threadId == null || _childInteractionPageLease != null)) {
      // Same visible host keeps its page share; A -> B -> A re-arms through
      // the null transition instead of duplicating leases.
      return;
    }
    _releaseChildInteractionPageDemand();
    if (threadId == null) return;
    _childInteractionPageHost = threadId;
    _armChildInteractionPageWatch(threadId);
  }

  void _armChildInteractionPageWatch(String hostThreadId) {
    final session = conversations.existingSession(hostThreadId);
    if (session == null) return;
    final source = session.source;
    var settled = false;
    void evaluate(ThreadSessionState state) {
      if (settled || _closed) return;
      final row = state.directoryRow;
      if (row == null) return;
      if (row.isChildRow) {
        // 非宿主页面没有子交互主题需求；不再等待该会话的进一步变化。
        settled = true;
        _childInteractionPageWatch?.cancel();
        _childInteractionPageWatch = null;
        return;
      }
      settled = true;
      _acquireChildInteractionPageLease(hostThreadId);
      _childInteractionPageWatch?.cancel();
      _childInteractionPageWatch = null;
    }

    final watched = source.watchLatest(evaluate);
    _childInteractionPageWatch = _scope.observe(watched.observation);
    evaluate(watched.value);
  }

  void _acquireChildInteractionPageLease(String hostThreadId) {
    if (_closed || _childInteractionPageLease != null) return;
    final resourceId = _allocateReportResourceId();
    ClientScope? resources;
    try {
      resources = _scope.child('child-interactions-page');
      _childInteractionPageResources = resources;
      final lease = resources.acquireLease(
        'child-interactions-page',
        () => channels.acquireChildInteractions(hostThreadId),
      );
      if (identical(_childInteractionPageResources, resources)) {
        _childInteractionPageLease = lease;
      }
    } catch (error) {
      resources?.requestClose();
      if (identical(_childInteractionPageResources, resources)) {
        _childInteractionPageResources = null;
      }
      resourceFailure.publish(
        _unresolvedResource(
          'child-interactions-page',
          error,
          resourceId: resourceId,
        ),
      );
    }
  }

  void _releaseChildInteractionPageDemand() {
    _childInteractionPageWatch?.cancel();
    _childInteractionPageWatch = null;
    _childInteractionPageHost = null;
    final lease = _childInteractionPageLease;
    _childInteractionPageLease = null;
    final resources = _childInteractionPageResources;
    _childInteractionPageResources = null;
    resources?.requestClose();
    if (lease == null) return;
    _releaseLease('child-interactions-page', lease);
  }

  void _retryChildInteractionPageDemand(String hostThreadId) {
    if (_closed || _childInteractionPageHost != hostThreadId) return;
    if (_childInteractionPageLease != null) return;
    _releaseChildInteractionPageDemand();
    _childInteractionPageHost = hostThreadId;
    _armChildInteractionPageWatch(hostThreadId);
  }

  void observeResource(String key, int revision) {
    final epoch = _runtimeOwnerEpoch;
    if (epoch == null) return;
    mutations.observe(
      ResourceStamp(resourceKey: key, ownerEpoch: epoch, revision: revision),
    );
  }

  T _mirror<T>(T Function() create) {
    _ensureOpen();
    return create();
  }

  void retryResource(ProductTopic topic) {
    _ensureOpen();
    final selected = selection.state;
    final selectedSession = threadDirectory
        .observedThread(selected.selectedThreadId ?? '')
        ?.sessionId;
    if (topic is SkillsTopic &&
            topic.workspaceId == selected.selectedProjectId ||
        topic is SessionCostsTopic && topic.rootThreadId == selectedSession) {
      // Admission may have failed before a topic owner existed. Retry logical
      // demand here rather than asking an observer to create that owner.
      _selectionChanged(selected);
    }
    if (topic is ChildInteractionsTopic) {
      // Same admission-failure case: the page share re-arms its own owner.
      _retryChildInteractionPageDemand(topic.hostThreadId);
    }
    if (topic is ThreadMcpTopic &&
        conversations.visibleThreadId.value == topic.threadId &&
        _threadMcpPageLease == null) {
      _retryThreadMcpPageDemand(topic.threadId);
      // A newly admitted page starts its connection once; only an existing lease reconnects.
      return;
    }
    channels.retryTopic(topic);
  }

  Future<Uint8List> readAttachmentBytes(String threadId, String attachmentId) =>
      _query(() => transport.readThreadAttachment(threadId, attachmentId));

  Future<T> _query<T>(Future<T> Function() read) async {
    _ensureOpen();
    return _queries.run(read);
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
    // Register the lifecycle join in the producer's error zone. A Future error
    // cannot cross into the native exit callback's different error zone; only
    // its settled value may cross. Bootstrap callers still receive task's error.
    _bootstrapJoin = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return task;
  }

  Future<void> _bootstrap() async {
    _ensureOpen();
    final snapshot = await transport.readBootstrap();
    if (_closed) return;
    applyBootstrap(snapshot);
    _applicationTopics = _scope.acquireLease(
      'application-topics',
      () => channels.acquireTopics([
        ...bridgeShellTopics,
        const AgentProfilesTopic(),
        const McpCatalogTopic(),
        const LspTopic(),
        const PersistenceQueueTopic(),
        const BotsTopic(),
      ]),
    );
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
    acceptSettingsSnapshot(
      snapshot.settingsState,
      scope: SettingsMergeScope.configOnly,
      owner: owner,
    );
    final profiles = snapshot.agentProfilesState;
    if (profiles != null) settings.applyAgentProfiles(profiles);
    recovery.apply(snapshot.recoveryState);
    mcp.apply(snapshot.mcpCatalog);
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

  /// Synchronous lookup is limited to a Conversation that already owns this
  /// exact ID observation; it never searches a directory-list union.
  StudioThread? findThread(String id) =>
      conversations.sessionState(id)?.workspace?.thread;

  void _selectionChanged(SelectionStoreState next) {
    if (_closed) return;
    final workspaceId = next.selectedProjectId;
    final sessionId = AgentDirectoryQueries.sessionId(
      threadId: next.selectedThreadId,
      agents: project.state.agents?.values ?? const [],
      rows: [
        if (threadDirectory.observedThread(next.selectedThreadId ?? '')
            case final row?)
          row,
      ],
    );
    final topicKey = '$workspaceId/$sessionId';
    if (_selectionTopicKey != topicKey) {
      final previous = _selectionTopics;
      _selectionTopics = null;
      _selectionTopicKey = null;
      final previousResources = _selectionTopicResources;
      _selectionTopicResources = null;
      previousResources?.requestClose();
      if (previous != null) {
        _releaseLease('selection-topics', previous);
      }
      final resourceId = _allocateReportResourceId();
      ClientScope? resources;
      try {
        resources = _scope.child('selection-topics');
        _selectionTopicResources = resources;
        final lease = resources.acquireLease(
          'selection-topics',
          () => channels.acquireTopics([
            if (workspaceId != null) SkillsTopic(workspaceId: workspaceId),
            if (sessionId != null) SessionCostsTopic(rootThreadId: sessionId),
          ]),
        );
        if (!identical(_selectionTopicResources, resources)) return;
        _selectionTopics = lease;
        _selectionTopicKey = topicKey;
        resourceFailure.publish(null);
      } catch (error) {
        resources?.requestClose();
        if (identical(_selectionTopicResources, resources)) {
          _selectionTopicResources = null;
        }
        resourceFailure.publish(
          _unresolvedResource(
            'selection-topics',
            error,
            resourceId: resourceId,
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

  Future<CloseReport> close({required ClientCloseBudget budget}) {
    final existing = _closing;
    if (existing != null) return existing;
    final completion = Completer<CloseReport>();
    _closing = completion.future;
    completion.complete(Future<CloseReport>.sync(() => _close(budget)));
    return completion.future;
  }

  Future<CloseReport> _close(ClientCloseBudget budget) async {
    _closed = true;
    if (!_acpReadClosed.isCompleted) _acpReadClosed.complete();
    _scope.requestClose();
    _releaseThreadMcpPageDemand();
    _releaseChildInteractionPageDemand();
    _queries.seal();
    // Both domains seal synchronously before independent close joins await.
    final draftWork = Future<void>.sync(drafts.close);
    final conversationWork = Future<CloseReport>.sync(
      () => conversations.close(budget: budget),
    );
    final work = <Future<void>>[
      if (_acpSessions case final acp?)
        _joinOwner('acp-observations', Future<void>.sync(acp.dispose), budget),
      _joinOwner('drafts', draftWork, budget),
      _joinOwner(
        'settings-commands',
        Future<void>.sync(settingsCommands.close),
        budget,
      ),
      _joinOwner(
        'directory-commands',
        Future<void>.sync(directoryCommands.close),
        budget,
      ),
      _joinReport(
        'thread-directory',
        Future<CloseReport>.sync(() => threadDirectory.close(budget: budget)),
        budget,
      ),
      _joinOwner(
        'bots-commands',
        Future<void>.sync(botsCommands.close),
        budget,
      ),
      _joinOwner('bots-queries', Future<void>.sync(botsQueries.close), budget),
      _joinOwner(
        'thread-commands',
        Future<void>.sync(threadCommands.close),
        budget,
      ),
      _joinOwner('mode-editor', Future<void>.sync(modeEditor.close), budget),
      _joinOwner('remote-commands', Future<void>.sync(remote.close), budget),
      _joinOwner('queries', Future<void>.sync(_queries.join), budget),
      _joinReport('conversations', conversationWork, budget),
      _joinReport(
        'topics',
        Future<CloseReport>.sync(() => channels.dispose(budget: budget)),
        budget,
      ),
      _joinReport(
        'client-scope',
        Future<CloseReport>.sync(() => _scope.close(budget: budget)),
        budget,
      ),
      _joinReport(
        'updates',
        Future<CloseReport>.sync(() => updates.close(budget: budget)),
        budget,
      ),
      _joinOwner(
        'settings-command-observations',
        Future<void>.sync(settingsCommands.closeObservations),
        budget,
      ),
      _joinOwner(
        'bots-command-observations',
        Future<void>.sync(botsCommands.closeObservations),
        budget,
      ),
      if (_bootstrapJoin case final boot?)
        _joinOwner('bootstrap', boot, budget),
    ];
    await Future.wait(work);
    _applicationTopics = null;
    _selectionTopics = null;
    _releaseMirrorsIfResolved();
    return CloseReport(unresolved: unresolvedResources);
  }

  Future<void> _joinReport(
    String owner,
    Future<CloseReport> task,
    ClientCloseBudget budget,
  ) {
    final generation = (_reportGenerations[owner] ?? 0) + 1;
    _reportGenerations[owner] = generation;
    return _joinOwner(
      owner,
      task.then<void>((report) {
        if (_reportGenerations[owner] == generation)
          _closeReports[owner] = report;
      }),
      budget,
    );
  }

  Future<void> _joinOwner(
    String owner,
    Future<void> task,
    ClientCloseBudget budget,
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
          _unresolved[owner] = _unresolvedResource(
            owner,
            error,
            stackTrace: stack,
          );
        }
      },
    );
    try {
      await settled.timeout(budget.remaining);
    } on TimeoutException catch (error) {
      // The original task and its owner remain held; a late real completion
      // clears this entry through the handler installed above.
      _unresolved[owner] = _unresolvedResource(owner, error, pending: true);
    }
  }

  /// Explicit resource cleanup only. Unknown business writes are never replayed.
  Future<CloseReport> retryCleanup({required ClientCloseBudget budget}) async {
    final pending = Map.of(_pendingJoins);
    // Start the root pass and every independent owner in this synchronous
    // stack, before awaiting any report. Future.sync preserves that eager start
    // while containing a sibling's synchronous throw so the others still run.
    final work = <Future<void>>[
      _joinReport(
        'client-scope',
        Future<CloseReport>.sync(() => _scope.retryCleanup(budget: budget)),
        budget,
      ),
      if (_closed && _acpSessions != null)
        _joinOwner(
          'acp-observations',
          Future<void>.sync(_acpSessions.dispose),
          budget,
        ),
      _joinReport(
        'conversations',
        Future<CloseReport>.sync(
          () => conversations.retryCleanup(budget: budget),
        ),
        budget,
      ),
      _joinReport(
        'topics',
        Future<CloseReport>.sync(() => channels.retryCleanup(budget: budget)),
        budget,
      ),
      _joinReport(
        'thread-directory',
        Future<CloseReport>.sync(
          () => threadDirectory.retryCleanup(budget: budget),
        ),
        budget,
      ),
      if (_closed)
        _joinReport(
          'updates',
          Future<CloseReport>.sync(() => updates.retryCleanup(budget: budget)),
          budget,
        ),
      _joinOwner('drafts', Future<void>.sync(drafts.retryCleanup), budget),
      for (final entry in pending.entries)
        if (identical(_pendingJoins[entry.key], entry.value))
          _joinOwner(entry.key, entry.value, budget),
    ];
    await Future.wait(work);
    _releaseMirrorsIfResolved();
    return CloseReport(unresolved: unresolvedResources);
  }

  ClientResourceId _allocateReportResourceId() =>
      ClientResourceId(_reportScopeId, ++_reportResourceSequence);

  ClientResourceId _reportResourceId(Object key) =>
      _reportResourceIds.putIfAbsent(key, _allocateReportResourceId);

  UnresolvedResource _unresolvedResource(
    String owner,
    Object reason, {
    ClientResourceId? resourceId,
    ClientClosePhase phase = ClientClosePhase.close,
    bool pending = false,
    StackTrace? stackTrace,
  }) {
    final identity = resourceId ?? _reportResourceId(owner);
    return UnresolvedResource(
      resourceId: identity,
      owner: owner,
      attemptId: AttemptId(identity.sequence),
      reason: reason,
      stages: [
        ClientResourceStage(
          owner: owner,
          phase: phase,
          pending: pending,
          error: pending ? null : reason,
          stackTrace: stackTrace,
        ),
      ],
    );
  }

  void _releaseLease(String owner, ClientLease lease) {
    final release = Future<void>.sync(lease.release);
    // Freeze metadata before awaiting: an A -> B -> A navigation must report
    // this old retirement, not whichever source now occupies the same key.
    final identities = List<ClientResourceId>.unmodifiable(
      lease.retirementResourceIds,
    );
    final fallback = identities.isEmpty ? _allocateReportResourceId() : null;
    unawaited(
      release.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          for (final identity
              in identities.isEmpty ? [fallback!] : identities) {
            resourceFailure.publish(
              _unresolvedResource(
                owner,
                error,
                resourceId: identity,
                phase: ClientClosePhase.leaseRelease,
                stackTrace: stack,
              ),
            );
          }
        },
      ),
    );
  }

  void _releaseMirrorsIfResolved() {
    if (!_closed || unresolvedResources.isNotEmpty) return;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('The application client is closed');
  }
}

String _newReportScopeId() {
  final random = Random.secure();
  final nonce = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'client-operations-$nonce';
}

final class _DisabledUpdateApi implements StudioUpdateApi {
  const _DisabledUpdateApi();
  Never _disabled() => throw StateError('Updates are disabled');
  @override
  Future<void> check() async => _disabled();
  @override
  Future<void> startAutomaticUpdate() async => _disabled();
  @override
  Future<void> cancelCurrentPreparation() async {}
  @override
  Future<void> stopAutomaticUpdate() async {}
  @override
  Future<StudioUpdateOperation> startPreparation({
    required int expectedRevision,
    required String version,
  }) async => _disabled();
}
