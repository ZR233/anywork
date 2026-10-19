import '../../../models.dart';
import '../../../studio_ports.dart';
import '../anywork_client.dart';
import '../stores/domain_sync.dart';
import '../stores/canonical_clock.dart';
import '../../lifecycle/resource_budget.dart';
import 'product_topic_registry.dart';

class StudioChannels {
  StudioChannels(this._client, StudioTransport api) {
    _topics = BridgeTopicRegistry(
      api,
      budget: _client.budget,
      onFrame: _onTopicFrame,
      onTopicConnection: _onTopicConnection,
    );
  }

  final AnyworkClient _client;
  late final BridgeTopicRegistry _topics;
  var _disposed = false;

  BridgeTopicLease acquireTopic(ProductTopic topic) {
    _prepareReadModel(topic);
    return _topics.acquire(topic);
  }

  BridgeTopicLeaseBundle acquireTopics(Iterable<ProductTopic> topics) {
    final requested = List<ProductTopic>.of(topics);
    for (final topic in requested) _prepareReadModel(topic);
    return _topics.acquireBundle(requested);
  }

  void _prepareReadModel(ProductTopic topic) {
    if (_disposed) throw StateError('StudioChannels is disposed');
    // Scoped mirrors belong to explicit topic demand, before connection
    // callbacks or frames. Observers only borrow the installed owner.
    switch (topic) {
      case SkillsTopic(:final projectId):
        _client.skills(projectId);
      case SessionCostsTopic(:final rootThreadId):
        _client.sessionCosts(rootThreadId);
      default:
        break;
    }
  }

  /// Shell 常驻目录、公共配置与诊断摘要。调用方持有返回的 bundle，离开时释放。
  BridgeTopicLeaseBundle acquireShellBundle() =>
      acquireTopics(bridgeShellTopics);

  /// 设置页作用域的统一租约入口，替代按页面复制的样板 account。
  BridgeTopicLeaseBundle acquireSettingsScope(
    BridgeSettingsScopeKind kind,
    String? projectId,
  ) => acquireTopics(bridgeSettingsScopeTopics(kind, projectId));

  BridgeTopicLease acquirePersistenceQueue() =>
      acquireTopic(const PersistenceQueueTopic());

  BridgeTopicLease acquireSessionCosts(String rootThreadId) =>
      acquireTopic(SessionCostsTopic(rootThreadId: rootThreadId));

  void retryTopic(ProductTopic topic) => _topics.retry(topic);

  /// 当前活动 topic 的引用计数。只读委托，不改变租约或订阅语义。
  Map<String, int> activeTopicRefCountViews() =>
      _topics.activeTopicRefCountViews();

  /// The Client owns product subscriptions independently of page observers.
  Future<CloseReport> dispose({DateTime? deadline}) {
    _disposed = true;
    return _topics.releaseAll(deadline: deadline);
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _topics.retryCleanup(deadline: deadline);

  List<UnresolvedResource> get unresolvedResources =>
      _topics.unresolvedResources;

  void _onTopicConnection(
    ProductTopic topic,
    ProductTopicConnectionStateView? view,
  ) {
    if (_disposed) return;
    _applyTransport(topic, DomainSyncStatus.fromConnection(view));
  }

  void _onTopicFrame(ProductTopicFrame frame) {
    if (_disposed) return;
    switch (frame) {
      case ProductTopicLaggedFrame(:final topic):
        _markResync(topic, error: null, failed: false);
      case ProductTopicFailureFrame(:final topic, :final error):
        _markResync(topic, error: error, failed: false);
      case ProductTopicBaselineFrame() || ProductTopicDataFrame():
        if (_isStale(frame)) return;
        _reduce(frame);
    }
  }

  bool _isStale(ProductTopicFrame frame) {
    final incoming = _incomingRevision(frame);
    final current = _loadedRevision(frame);
    if (incoming == null || current == null) return false;
    if (_isThreadDirectoryDelta(frame)) return incoming < current;
    return incoming <= current;
  }

  bool _isThreadDirectoryDelta(ProductTopicFrame frame) {
    return frame is ProductTopicDataFrame &&
        frame.event.payload is ThreadDirectoryChangedPayload;
  }

  int? _loadedRevision(ProductTopicFrame frame) {
    return switch (_frameTopic(frame)) {
      ProjectDirectoryTopic() => _loaded(
        _client.project.state.projectsLoaded,
        _client.project.state.projectRevision,
      ),
      AgentDirectoryTopic() => _loaded(
        _client.project.state.agentsLoaded,
        _client.project.state.agentRevision,
      ),
      ThreadDirectoryTopic() => _loaded(
        _client.threadDirectory.state.loaded,
        _client.threadDirectory.state.revision,
      ),
      SettingsConfigTopic() => _loaded(
        _client.settings.state.configLoaded,
        _client.settings.state.settingsRevision,
      ),
      ModelCatalogTopic() => _loaded(
        _client.settings.state.catalogLoaded,
        _client.settings.state.modelCatalogRevision,
      ),
      AgentProfilesTopic() => _loaded(
        _client.settings.state.agentProfilesLoaded,
        _client.settings.state.agentProfilesRevision,
      ),
      RecoveryTopic() => _clock(_client.recovery.state),
      McpTopic() => _clock(_client.mcp.state),
      LspTopic() => _clock(_client.lsp.state),
      SkillsTopic(:final projectId) => _clock(
        _client.existingSkills(projectId)?.state,
      ),
      ThreadModeCatalogTopic() => _clock(_client.modeCatalog.state),
      AccountUsageTopic() => _clock(_client.accountUsage.state),
      ModelPerformanceTopic() => _clock(_client.modelPerformance.state),
      SessionCostsTopic(:final rootThreadId) => _clock(
        _client.existingSessionCosts(rootThreadId)?.state,
      ),
      UpdaterTopic() => _clock(_client.updater.state),
      PersistenceTopic() => _loaded(
        _client.persistence.state.stateLoaded,
        _client.persistence.state.stateRevision,
      ),
      PersistenceQueueTopic() => _loaded(
        _client.persistence.state.queueLoaded,
        _client.persistence.state.queueRevision,
      ),
    };
  }

  void _reduce(ProductTopicFrame frame) {
    switch (frame) {
      case ProductTopicBaselineFrame(:final revision, :final state):
        _reduceBaseline(revision, state);
      case ProductTopicDataFrame(:final event):
        _reducePayload(event.payload);
      case ProductTopicLaggedFrame() || ProductTopicFailureFrame():
        break;
    }
  }

  void _reduceBaseline(int revision, ProductTopicBaselineState baseline) {
    switch (baseline) {
      case ProjectDirectoryBaseline(:final state):
        if (_client.project.applyProjectDirectory(state)) {
          _client.reconcileSelectedProject();
        }
      case ThreadDirectoryBaseline(:final page):
        _client.threadDirectory.applyBaseline(page, revision: revision);
      case AgentDirectoryBaseline(:final state):
        _client.project.applyAgentDirectory(state);
      case SettingsConfigBaseline(:final state):
        _client.settings.merge(state, scope: SettingsMergeScope.configOnly);
      case ModelCatalogBaseline(:final state):
        _client.settings.merge(state, scope: SettingsMergeScope.catalogOnly);
      case RecoveryBaseline(:final state):
        _client.recovery.apply(state);
      case McpBaseline(:final state):
        _client.mcp.apply(state);
      case LspBaseline(:final state):
        _client.lsp.apply(state);
      case SkillsBaseline(:final state):
        _client.existingSkills(state.projectId)?.apply(state);
      case ThreadModeCatalogBaseline(:final state):
        _client.modeCatalog.apply(state);
      case AccountUsageBaseline(:final state):
        _client.accountUsage.apply(state);
      case ModelPerformanceBaseline(:final state):
        _client.modelPerformance.apply(state);
      case SessionCostsBaseline(:final state):
        _client.existingSessionCosts(state.rootThreadId)?.apply(state);
      case UpdaterBaseline(:final state):
        _client.updater.apply(state);
      case PersistenceBaseline(:final state):
        _client.persistence.applyState(state);
      case PersistenceQueueBaseline(:final state):
        _client.persistence.applyQueue(state);
      case AgentProfilesBaseline(:final state):
        _client.settings.applyAgentProfiles(state);
    }
  }

  void _reducePayload(ProductTopicEventPayload payload) {
    switch (payload) {
      case ProjectDirectoryChangedPayload(:final state):
        if (_client.project.applyProjectDirectory(state)) {
          _client.reconcileSelectedProject();
        }
      case ThreadDirectoryChangedPayload(
        :final revision,
        :final upserted,
        :final removed,
      ):
        final applied = _client.threadDirectory.applyDelta(
          revision: revision,
          upserted: upserted,
          removed: removed,
        );
        // 目录增量只更新 threadDirectoryStore。removed 会话由 reconcile 释放，
        // 不把目录线程元数据回绑到 threadSession，也不在这里清空其 workspace。
        if (applied) _client.reconcileRemovedThreads(removed.toSet());
      case AgentDirectoryChangedPayload(:final state):
        _client.project.applyAgentDirectory(state);
      case SettingsConfigStateChangedPayload(:final state):
        _client.settings.merge(state, scope: SettingsMergeScope.configOnly);
      case ModelCatalogStateChangedPayload(:final state):
        _client.settings.merge(state, scope: SettingsMergeScope.catalogOnly);
      case RecoveryStateChangedPayload(:final state):
        _client.recovery.apply(state);
      case McpStateChangedPayload(:final state):
        _client.mcp.apply(state);
      case LspStateChangedPayload(:final state):
        _client.lsp.apply(state);
      case SkillsStateChangedPayload(:final state):
        _client.existingSkills(state.projectId)?.apply(state);
      case ThreadModeCatalogChangedPayload(:final state):
        _client.modeCatalog.apply(state);
      case AccountUsageStateChangedPayload(:final state):
        _client.accountUsage.apply(state);
      case ModelPerformanceStateChangedPayload(:final state):
        _client.modelPerformance.apply(state);
      case SessionCostsChangedPayload(:final state):
        _client.existingSessionCosts(state.rootThreadId)?.apply(state);
      case UpdaterStateChangedPayload(:final state):
        _client.updater.apply(state);
      case PersistenceStateChangedPayload(:final state):
        _client.persistence.applyState(state);
      case PersistenceQueueStateChangedPayload(:final state):
        _client.persistence.applyQueue(state);
      case AgentProfilesStateChangedPayload(:final state):
        _client.settings.applyAgentProfiles(state);
    }
  }

  void _applyTransport(ProductTopic topic, DomainSyncStatus sync) {
    switch (topic) {
      case ProjectDirectoryTopic():
        _client.project.applyProjectTransport(sync);
      case AgentDirectoryTopic():
        _client.project.applyAgentTransport(sync);
      case ThreadDirectoryTopic():
        _client.threadDirectory.applyTransport(sync);
      case SettingsConfigTopic():
        _client.settings.applyConfigTransport(sync);
      case ModelCatalogTopic():
        _client.settings.applyCatalogTransport(sync);
      case AgentProfilesTopic():
        _client.settings.applyAgentProfilesTransport(sync);
      case RecoveryTopic():
        _client.recovery.applyTransport(sync);
      case McpTopic():
        _client.mcp.applyTransport(sync);
      case LspTopic():
        _client.lsp.applyTransport(sync);
      case SkillsTopic(:final projectId):
        _client.existingSkills(projectId)?.applyTransport(sync);
      case ThreadModeCatalogTopic():
        _client.modeCatalog.applyTransport(sync);
      case AccountUsageTopic():
        _client.accountUsage.applyTransport(sync);
      case ModelPerformanceTopic():
        _client.modelPerformance.applyTransport(sync);
      case SessionCostsTopic(:final rootThreadId):
        _client.existingSessionCosts(rootThreadId)?.applyTransport(sync);
      case UpdaterTopic():
        _client.updater.applyTransport(sync);
      case PersistenceTopic():
        _client.persistence.applyStateTransport(sync);
      case PersistenceQueueTopic():
        _client.persistence.applyQueueTransport(sync);
    }
  }

  void _markResync(
    ProductTopic topic, {
    required Object? error,
    required bool failed,
  }) {
    _applyTransport(
      topic,
      DomainSyncStatus(
        phase: failed ? DomainSyncPhase.failed : DomainSyncPhase.reconnecting,
        errorMessage: error?.toString(),
      ),
    );
  }
}

int? _loaded(bool loaded, int revision) => loaded ? revision : null;

int? _clock<T>(CanonicalClockState<T>? clock) =>
    clock != null && clock.loaded ? clock.revision : null;

ProductTopic _frameTopic(ProductTopicFrame frame) {
  return switch (frame) {
    ProductTopicBaselineFrame(:final topic) => topic,
    ProductTopicDataFrame(:final topic) => topic,
    ProductTopicLaggedFrame(:final topic) => topic,
    ProductTopicFailureFrame(:final topic) => topic,
  };
}

int? _incomingRevision(ProductTopicFrame frame) {
  return switch (frame) {
    ProductTopicBaselineFrame(
      revision: final frameRevision,
      state: final baseline,
    ) =>
      switch (baseline) {
        ProjectDirectoryBaseline(:final state) => state.revision,
        ThreadDirectoryBaseline() => frameRevision,
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
      },
    ProductTopicDataFrame(:final event) => switch (event.payload) {
      ProjectDirectoryChangedPayload(:final state) => state.revision,
      ThreadDirectoryChangedPayload(:final revision) => revision,
      AgentDirectoryChangedPayload(:final state) => state.revision,
      SettingsConfigStateChangedPayload(:final state) => state.revision,
      ModelCatalogStateChangedPayload(:final state) =>
        state.modelCatalogRevision,
      RecoveryStateChangedPayload(:final state) => state.revision,
      McpStateChangedPayload(:final state) => state.revision,
      LspStateChangedPayload(:final state) => state.revision,
      SkillsStateChangedPayload(:final state) => state.revision,
      ThreadModeCatalogChangedPayload(:final state) => state.revision,
      AccountUsageStateChangedPayload(:final state) => state.revision,
      ModelPerformanceStateChangedPayload(:final state) => state.revision,
      SessionCostsChangedPayload(:final state) => state.revision,
      UpdaterStateChangedPayload(:final state) => state.revision,
      PersistenceStateChangedPayload(:final state) => state.revision,
      PersistenceQueueStateChangedPayload(:final state) => state.revision,
      AgentProfilesStateChangedPayload(:final state) => state.revision,
    },
    ProductTopicLaggedFrame() || ProductTopicFailureFrame() => null,
  };
}
