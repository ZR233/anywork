import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import '../frb/studio_api.dart';
import '../repositories/studio_api_provider.dart';
import '../stores/domain_sync.dart';
import '../stores/canonical_clock.dart';
import '../stores/lsp_store.dart';
import '../stores/mcp_store.dart';
import '../stores/mode_catalog_store.dart';
import '../stores/model_performance_store.dart';
import '../stores/persistence_store.dart';
import '../stores/project_store.dart';
import '../stores/provider_usage_store.dart';
import '../stores/recovery_store.dart';
import '../stores/session_costs_store.dart';
import '../stores/settings_store.dart';
import '../stores/skills_store.dart';
import '../stores/snapshot_fanout.dart';
import '../stores/thread_directory_store.dart';
import '../stores/updater_store.dart';
import 'product_topic_registry.dart';
import 'thread_stream_gate.dart';

export 'product_topic_registry.dart'
    show
        BridgeSettingsScopeKind,
        BridgeTopicLease,
        BridgeTopicLeaseBundle,
        bridgeSettingsScopeTopics,
        bridgeShellTopics;
export 'thread_stream_gate.dart' show ThreadStreamWatermark;

part 'studio_bridge.g.dart';

/// 全 app 唯一的 topic / thread 流消费点。
///
/// 帧在进入 store reduce 之前按领域水位拒收。Lagged、failure、closed 只把对应
/// store 标成局部重同步，不覆盖 last-known canonical。租约归零即取消订阅；
/// 重建先取消旧句柄，再接收新的 Baseline / snapshot。
@Riverpod(keepAlive: true)
StudioBridge studioBridge(Ref ref) {
  final bridge = StudioBridge(ref, ref.watch(studioBridgeDataSourceProvider));
  ref.onDispose(() {
    unawaited(bridge.dispose());
  });
  return bridge;
}

class StudioBridge {
  StudioBridge(this._ref, StudioBridgeDataSource api) : _api = api {
    _topics = BridgeTopicRegistry(
      api,
      onFrame: _onTopicFrame,
      onTopicConnection: _onTopicConnection,
    );
  }

  final Ref _ref;
  final StudioBridgeDataSource _api;
  late final BridgeTopicRegistry _topics;
  final Map<String, _ThreadPipe> _threads = {};
  var _disposed = false;

  BridgeTopicLease acquireTopic(ProductTopic topic) => _topics.acquire(topic);

  BridgeTopicLeaseBundle acquireTopics(Iterable<ProductTopic> topics) =>
      _topics.acquireBundle(topics);

  /// Shell 常驻目录、公共配置与诊断摘要。调用方持有返回的 bundle，离开时释放。
  BridgeTopicLeaseBundle acquireShellBundle() =>
      _topics.acquireBundle(bridgeShellTopics);

  /// 设置页作用域的统一租约入口，替代按页面复制的样板 provider。
  BridgeTopicLeaseBundle acquireSettingsScope(
    BridgeSettingsScopeKind kind,
    String? projectId,
  ) => _topics.acquireBundle(bridgeSettingsScopeTopics(kind, projectId));

  BridgeTopicLease acquirePersistenceQueue() =>
      _topics.acquire(const PersistenceQueueTopic());

  BridgeTopicLease acquireSessionCosts(String rootThreadId) =>
      _topics.acquire(SessionCostsTopic(rootThreadId: rootThreadId));

  void retryTopic(ProductTopic topic) => _topics.retry(topic);

  /// 按 threadId 建立有序流。调用方（threadSession store）在无观察者时 release。
  BridgeThreadAttachment attachThread(
    String threadId, {
    required ThreadStreamWatermark Function() readWatermark,
    required void Function() onSubscriptionStarting,
    required void Function(ThreadStreamFrame frame) onFrame,
    required void Function(Object? error) onClosed,
  }) {
    if (_disposed) {
      throw StateError('StudioBridge is disposed');
    }
    final pipe = _ThreadPipe(
      threadId: threadId,
      api: _api,
      readWatermark: readWatermark,
      onSubscriptionStarting: onSubscriptionStarting,
      onFrame: onFrame,
      onClosed: onClosed,
      onForget: () => _threads.remove(threadId),
    );
    _threads[threadId] = pipe;
    pipe.start();
    return pipe;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pipes = List.of(_threads.values);
    _threads.clear();
    await Future.wait([
      _topics.releaseAll(),
      for (final pipe in pipes) pipe.release(),
    ]);
  }

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
        _ref.read(projectStoreProvider).projectsLoaded,
        _ref.read(projectStoreProvider).projectRevision,
      ),
      AgentDirectoryTopic() => _loaded(
        _ref.read(projectStoreProvider).agentsLoaded,
        _ref.read(projectStoreProvider).agentRevision,
      ),
      ThreadDirectoryTopic() => _loaded(
        _ref.read(threadDirectoryStoreProvider).loaded,
        _ref.read(threadDirectoryStoreProvider).revision,
      ),
      SettingsConfigTopic() => _loaded(
        _ref.read(settingsStoreProvider).configLoaded,
        _ref.read(settingsStoreProvider).settingsRevision,
      ),
      ModelCatalogTopic() => _loaded(
        _ref.read(settingsStoreProvider).catalogLoaded,
        _ref.read(settingsStoreProvider).modelCatalogRevision,
      ),
      AgentProfilesTopic() => _loaded(
        _ref.read(settingsStoreProvider).agentProfilesLoaded,
        _ref.read(settingsStoreProvider).agentProfilesRevision,
      ),
      RecoveryTopic() => _clock(_ref.read(recoveryStoreProvider)),
      McpTopic() => _clock(_ref.read(mcpStoreProvider)),
      LspTopic() => _clock(_ref.read(lspStoreProvider)),
      SkillsTopic(:final projectId) => _clock(
        _ref.read(skillsStoreProvider(projectId)),
      ),
      ThreadModeCatalogTopic() => _clock(_ref.read(modeCatalogStoreProvider)),
      ProviderUsageTopic() => _clock(_ref.read(providerUsageStoreProvider)),
      ModelPerformanceTopic() => _clock(
        _ref.read(modelPerformanceStoreProvider),
      ),
      SessionCostsTopic(:final rootThreadId) => _clock(
        _ref.read(sessionCostsStoreProvider(rootThreadId)),
      ),
      UpdaterTopic() => _clock(_ref.read(updaterStoreProvider)),
      PersistenceTopic() => _loaded(
        _ref.read(persistenceStoreProvider).stateLoaded,
        _ref.read(persistenceStoreProvider).stateRevision,
      ),
      PersistenceQueueTopic() => _loaded(
        _ref.read(persistenceStoreProvider).queueLoaded,
        _ref.read(persistenceStoreProvider).queueRevision,
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
        if (_ref
            .read(projectStoreProvider.notifier)
            .applyProjectDirectory(state)) {
          reconcileSelectedProject(_ref);
        }
      case ThreadDirectoryBaseline(:final page):
        _ref
            .read(threadDirectoryStoreProvider.notifier)
            .applyBaseline(page, revision: revision);
      case AgentDirectoryBaseline(:final state):
        _ref.read(projectStoreProvider.notifier).applyAgentDirectory(state);
      case SettingsConfigBaseline(:final state):
        _ref
            .read(settingsStoreProvider.notifier)
            .merge(state, scope: SettingsMergeScope.configOnly);
      case ModelCatalogBaseline(:final state):
        _ref
            .read(settingsStoreProvider.notifier)
            .merge(state, scope: SettingsMergeScope.catalogOnly);
      case RecoveryBaseline(:final state):
        _ref.read(recoveryStoreProvider.notifier).apply(state);
      case McpBaseline(:final state):
        _ref.read(mcpStoreProvider.notifier).apply(state);
      case LspBaseline(:final state):
        _ref.read(lspStoreProvider.notifier).apply(state);
      case SkillsBaseline(:final state):
        _ref.read(skillsStoreProvider(state.projectId).notifier).apply(state);
      case ThreadModeCatalogBaseline(:final state):
        _ref.read(modeCatalogStoreProvider.notifier).apply(state);
      case ProviderUsageBaseline(:final state):
        _ref.read(providerUsageStoreProvider.notifier).apply(state);
      case ModelPerformanceBaseline(:final state):
        _ref.read(modelPerformanceStoreProvider.notifier).apply(state);
      case SessionCostsBaseline(:final state):
        _ref
            .read(sessionCostsStoreProvider(state.rootThreadId).notifier)
            .apply(state);
      case UpdaterBaseline(:final state):
        _ref.read(updaterStoreProvider.notifier).apply(state);
      case PersistenceBaseline(:final state):
        _ref.read(persistenceStoreProvider.notifier).applyState(state);
      case PersistenceQueueBaseline(:final state):
        _ref.read(persistenceStoreProvider.notifier).applyQueue(state);
      case AgentProfilesBaseline(:final state):
        _ref.read(settingsStoreProvider.notifier).applyAgentProfiles(state);
    }
  }

  void _reducePayload(ProductTopicEventPayload payload) {
    switch (payload) {
      case ProjectDirectoryChangedPayload(:final state):
        if (_ref
            .read(projectStoreProvider.notifier)
            .applyProjectDirectory(state)) {
          reconcileSelectedProject(_ref);
        }
      case ThreadDirectoryChangedPayload(
        :final revision,
        :final upserted,
        :final removed,
      ):
        final applied = _ref
            .read(threadDirectoryStoreProvider.notifier)
            .applyDelta(
              revision: revision,
              upserted: upserted,
              removed: removed,
            );
        if (applied) reconcileRemovedThreads(_ref, removed.toSet());
      case AgentDirectoryChangedPayload(:final state):
        _ref.read(projectStoreProvider.notifier).applyAgentDirectory(state);
      case SettingsConfigStateChangedPayload(:final state):
        _ref
            .read(settingsStoreProvider.notifier)
            .merge(state, scope: SettingsMergeScope.configOnly);
      case ModelCatalogStateChangedPayload(:final state):
        _ref
            .read(settingsStoreProvider.notifier)
            .merge(state, scope: SettingsMergeScope.catalogOnly);
      case RecoveryStateChangedPayload(:final state):
        _ref.read(recoveryStoreProvider.notifier).apply(state);
      case McpStateChangedPayload(:final state):
        _ref.read(mcpStoreProvider.notifier).apply(state);
      case LspStateChangedPayload(:final state):
        _ref.read(lspStoreProvider.notifier).apply(state);
      case SkillsStateChangedPayload(:final state):
        _ref.read(skillsStoreProvider(state.projectId).notifier).apply(state);
      case ThreadModeCatalogChangedPayload(:final state):
        _ref.read(modeCatalogStoreProvider.notifier).apply(state);
      case ProviderUsageStateChangedPayload(:final state):
        _ref.read(providerUsageStoreProvider.notifier).apply(state);
      case ModelPerformanceStateChangedPayload(:final state):
        _ref.read(modelPerformanceStoreProvider.notifier).apply(state);
      case SessionCostsChangedPayload(:final state):
        _ref
            .read(sessionCostsStoreProvider(state.rootThreadId).notifier)
            .apply(state);
      case UpdaterStateChangedPayload(:final state):
        _ref.read(updaterStoreProvider.notifier).apply(state);
      case PersistenceStateChangedPayload(:final state):
        _ref.read(persistenceStoreProvider.notifier).applyState(state);
      case PersistenceQueueStateChangedPayload(:final state):
        _ref.read(persistenceStoreProvider.notifier).applyQueue(state);
      case AgentProfilesStateChangedPayload(:final state):
        _ref.read(settingsStoreProvider.notifier).applyAgentProfiles(state);
    }
  }

  void _applyTransport(ProductTopic topic, DomainSyncStatus sync) {
    switch (topic) {
      case ProjectDirectoryTopic():
        _ref.read(projectStoreProvider.notifier).applyProjectTransport(sync);
      case AgentDirectoryTopic():
        _ref.read(projectStoreProvider.notifier).applyAgentTransport(sync);
      case ThreadDirectoryTopic():
        _ref.read(threadDirectoryStoreProvider.notifier).applyTransport(sync);
      case SettingsConfigTopic():
        _ref.read(settingsStoreProvider.notifier).applyConfigTransport(sync);
      case ModelCatalogTopic():
        _ref.read(settingsStoreProvider.notifier).applyCatalogTransport(sync);
      case AgentProfilesTopic():
        _ref
            .read(settingsStoreProvider.notifier)
            .applyAgentProfilesTransport(sync);
      case RecoveryTopic():
        _ref.read(recoveryStoreProvider.notifier).applyTransport(sync);
      case McpTopic():
        _ref.read(mcpStoreProvider.notifier).applyTransport(sync);
      case LspTopic():
        _ref.read(lspStoreProvider.notifier).applyTransport(sync);
      case SkillsTopic(:final projectId):
        _ref.read(skillsStoreProvider(projectId).notifier).applyTransport(sync);
      case ThreadModeCatalogTopic():
        _ref.read(modeCatalogStoreProvider.notifier).applyTransport(sync);
      case ProviderUsageTopic():
        _ref.read(providerUsageStoreProvider.notifier).applyTransport(sync);
      case ModelPerformanceTopic():
        _ref.read(modelPerformanceStoreProvider.notifier).applyTransport(sync);
      case SessionCostsTopic(:final rootThreadId):
        _ref
            .read(sessionCostsStoreProvider(rootThreadId).notifier)
            .applyTransport(sync);
      case UpdaterTopic():
        _ref.read(updaterStoreProvider.notifier).applyTransport(sync);
      case PersistenceTopic():
        _ref.read(persistenceStoreProvider.notifier).applyStateTransport(sync);
      case PersistenceQueueTopic():
        _ref.read(persistenceStoreProvider.notifier).applyQueueTransport(sync);
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

int? _clock<T>(CanonicalClockState<T> clock) =>
    clock.loaded ? clock.revision : null;

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
        ProviderUsageBaseline(:final state) => state.revision,
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
      ProviderUsageStateChangedPayload(:final state) => state.revision,
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

/// 一个 threadId 的流句柄。release 等待底层取消完成。
abstract interface class BridgeThreadAttachment {
  String get threadId;
  Future<void> release();
  Future<void> resubscribe();
}

class _ThreadPipe implements BridgeThreadAttachment {
  _ThreadPipe({
    required this.threadId,
    required this.api,
    required this.readWatermark,
    required this.onSubscriptionStarting,
    required this.onFrame,
    required this.onClosed,
    required this.onForget,
  });

  @override
  final String threadId;
  final StudioBridgeDataSource api;
  final ThreadStreamWatermark Function() readWatermark;
  final void Function() onSubscriptionStarting;
  final void Function(ThreadStreamFrame frame) onFrame;
  final void Function(Object? error) onClosed;
  final void Function() onForget;

  StreamSubscription<ThreadStreamFrame>? _subscription;
  Timer? _retry;
  int _sourceEpoch = 0;
  var _closed = false;
  var _rebuilding = false;

  void start() {
    if (_closed) return;
    onSubscriptionStarting();
    final epoch = ++_sourceEpoch;
    _subscription = api
        .subscribeThread(threadId)
        .listen(
          (frame) => _onFrame(frame, epoch),
          onError: (Object error, StackTrace _) => _onTerminated(epoch, error),
          onDone: () => _onTerminated(epoch, null),
          cancelOnError: true,
        );
  }

  void _onFrame(ThreadStreamFrame frame, int epoch) {
    if (_closed || epoch != _sourceEpoch) return;
    final frameThreadId = switch (frame) {
      ThreadSnapshotFrame(:final workspace) => workspace.thread.id,
      ThreadNotificationFrame(:final threadId) => threadId,
      ThreadResyncRequiredFrame(:final threadId) => threadId,
    };
    if (frameThreadId != threadId) return;
    switch (classifyThreadFrame(readWatermark(), frame)) {
      case ThreadFrameDecision.drop:
        return;
      case ThreadFrameDecision.resync:
        onClosed(null);
        unawaited(resubscribe());
      case ThreadFrameDecision.apply:
        onFrame(frame);
    }
  }

  void _onTerminated(int epoch, Object? error) {
    if (_closed || epoch != _sourceEpoch) return;
    onClosed(error);
    if (error != null) return;
    _retry?.cancel();
    _retry = Timer(const Duration(milliseconds: 150), () {
      unawaited(resubscribe());
    });
  }

  @override
  Future<void> resubscribe() async {
    if (_closed || _rebuilding) return;
    _rebuilding = true;
    try {
      _sourceEpoch += 1;
      _retry?.cancel();
      _retry = null;
      final old = _subscription;
      _subscription = null;
      try {
        await old?.cancel();
      } catch (_) {
        // 旧句柄取消失败不阻止重新接收。
      }
      if (_closed) return;
      start();
    } finally {
      _rebuilding = false;
    }
  }

  @override
  Future<void> release() async {
    if (_closed) return;
    _closed = true;
    _sourceEpoch += 1;
    _retry?.cancel();
    _retry = null;
    final old = _subscription;
    _subscription = null;
    onForget();
    try {
      await old?.cancel();
    } catch (_) {
      // 释放路径不把取消失败升级成会话 canonical 错误。
    }
  }
}
