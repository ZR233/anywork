// 产品 topic 租约与重连的唯一实现。引用计数归零后取消订阅，重建先等旧句柄关闭。

import 'dart:async';

import 'dart:developer' show log;

import '../../../lifecycle.dart';
import '../../../models.dart';
import '../../../studio_ports.dart';

/// Shell 常驻产品 topics：导航目录、公共配置与诊断 summary。
///
/// 这些领域在 Shell 生命周期内持续可见（侧栏、横幅、更新入口），由 controller
/// 在 bootstrap 完成后一次性持有；其余 topics 只随可见页面/面板按需租用。
const List<ProductTopic> bridgeShellTopics = [
  ProjectDirectoryTopic(),
  AgentDirectoryTopic(),
  SettingsConfigTopic(),
  RecoveryTopic(),
  PersistenceTopic(),
  UpdaterTopic(),
  ThreadModeCatalogTopic(),
];

/// 设置页可见 tab 的按需 topic 作用域。
///
/// MCP、LSP、项目 Skills、配置级 Profiles 与 Bots 不合并为含糊的 `services`
/// 作用域；账号用量与 ACP 由各自领域持有需求，不经过此通用设置入口。
/// 隐藏 tab 不持有租约，只保留 UI 状态。Skills 始终携带当前 project identity。
enum BridgeSettingsScopeKind { agents, mcp, lsp, skills, bots }

/// 该设置作用域需要的 topics。
///
/// [selectedProjectId] 为空（或空白）时 Skills 作用域没有可用 topic，返回空列表；
/// 其余作用域与项目无关。
List<ProductTopic> bridgeSettingsScopeTopics(
  BridgeSettingsScopeKind kind,
  String? selectedProjectId,
) {
  switch (kind) {
    case BridgeSettingsScopeKind.agents:
      return const [AgentProfilesTopic()];
    case BridgeSettingsScopeKind.mcp:
      return const [McpCatalogTopic()];
    case BridgeSettingsScopeKind.lsp:
      return const [LspTopic()];
    case BridgeSettingsScopeKind.skills:
      final workspaceId = selectedProjectId?.trim();
      return workspaceId == null || workspaceId.isEmpty
          ? const []
          : [SkillsTopic(workspaceId: workspaceId)];
    case BridgeSettingsScopeKind.bots:
      return const [BotsTopic()];
  }
}

/// A Client-owned topic demand. Releasing a lease never discards failed cleanup.
abstract interface class BridgeTopicLease implements ClientLease {
  ProductTopic get topic;
}

class BridgeTopicLeaseBundle implements ClientLease {
  BridgeTopicLeaseBundle._(this._leases);
  final List<_Lease> _leases;
  Future<void>? _releasing;
  List<ClientResourceId>? _retirementResourceIds;

  List<ProductTopic> get topics =>
      List.unmodifiable([for (final lease in _leases) lease.topic]);

  @override
  List<ClientResourceId> get retirementResourceIds =>
      _retirementResourceIds ?? const [];

  @override
  Future<void> release() {
    if (_releasing case final pending?) return pending;
    final completion = Completer<void>();
    final result = _releasing = completion.future;
    // Withdraw every demand and freeze the whole bundle before any stop
    // callback can synchronously reenter a scope's lease adapter.
    final releases = [for (final lease in _leases) lease._prepareRelease()];
    _retirementResourceIds ??= List.unmodifiable({
      for (final lease in _leases) ...lease.retirementResourceIds,
    });
    for (final release in releases) release.start?.call();
    completion.complete(
      Future.wait(releases.map((release) => release.future)).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_releasing, result)) _releasing = null;
          Error.throwWithStackTrace(error, stack);
        },
      ),
    );
    return result;
  }
}

final class BridgeTopicClosedError implements Exception {
  const BridgeTopicClosedError();
  @override
  String toString() => 'product topic subscription closed';
}

final class BridgeTopicCleanupBlocked implements Exception {
  const BridgeTopicCleanupBlocked(this.topic, this.cause);
  final ProductTopic topic;
  final Object cause;
  @override
  String toString() =>
      'Product topic cleanup blocked: ${describeBridgeProductTopic(topic)} ($cause)';
}

typedef _TopicSource = ({
  ClientAcquisition<ProductTopicObservation> acquisition,
  int epoch,
});

final class _TopicSubscription {
  _TopicSubscription(this.topic, this.registry);

  final ProductTopic topic;
  final BridgeTopicRegistry registry;
  int refs = 0;
  // Only the business source identity lives here. The scope owns creation,
  // consumer completion and the cached close result, including failed ACKs.
  _TopicSource? _source;
  Future<void> _ops = Future.value();
  int _sourceEpoch = 0;
  int _reconnectAttempts = 0;
  bool _exhausted = false;
  bool _rebuildInFlight = false;
  bool _rebuildRequested = false;
  Timer? _retryTimer;
  Timer? _stabilityTimer;
  Object? _lastError;
  ProductTopicConnectionStateView? _connection;

  static const _baseRetryDelay = Duration(milliseconds: 250);
  static const _maxRetryDelay = Duration(seconds: 5);
  static const _maxReconnectAttempts = 5;
  static const _stableWindow = Duration(seconds: 10);

  bool get isActive =>
      !registry._disposed &&
      refs > 0 &&
      identical(registry._entries[topic], this);

  Future<void> _enqueue(FutureOr<void> Function() operation) {
    final chained = _ops.then((_) => operation());
    _ops = chained.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _lastError = error;
        log(
          'product_topic_owner_failed topic=$topic error=$error',
          stackTrace: stack,
        );
      },
    );
    return chained;
  }

  Future<void> start() => _enqueue(_establish);

  void _establish() {
    if (!isActive) return;
    if (_source != null) {
      throw StateError('The prior topic subscription has not joined');
    }
    final epoch = ++_sourceEpoch;
    final acquisition = registry._scope.open<ProductTopicObservation>(
      'topic:${describeBridgeProductTopic(topic)}',
      (operation) => registry._api.openProductTopic(
        topic,
        resourceId: operation.resourceId,
      ),
      ownership: ClientOwnership.proxy,
      consume: (port, operation) async {
        if (isActive && epoch == _sourceEpoch) _armStabilityWindow(epoch);
        await for (final frame in port.frames) {
          if (operation.closeRequested) break;
          _onFrame(frame, epoch);
        }
        if (!operation.closeRequested) {
          _onTerminated(epoch, const BridgeTopicClosedError());
        }
      },
      onFailure: (error, stack) => _onTerminated(epoch, error),
    );
    _source = (acquisition: acquisition, epoch: epoch);
    _setConnection(
      const ProductTopicConnectionStateView(
        phase: ProductTopicConnectionPhase.connecting,
      ),
    );
  }

  void _onFrame(ProductTopicFrame frame, int epoch) {
    if (!isActive || epoch != _sourceEpoch) return;
    final frameTopic = switch (frame) {
      ProductTopicBaselineFrame(:final topic) ||
      ProductTopicDataFrame(:final topic) ||
      ProductTopicLaggedFrame(:final topic) ||
      ProductTopicFailureFrame(:final topic) => topic,
    };
    if (frameTopic != topic) return;
    switch (frame) {
      case ProductTopicBaselineFrame() || ProductTopicDataFrame():
        _setConnection(
          const ProductTopicConnectionStateView(
            phase: ProductTopicConnectionPhase.connected,
          ),
        );
      case ProductTopicLaggedFrame():
        _setConnection(
          const ProductTopicConnectionStateView(
            phase: ProductTopicConnectionPhase.reconnecting,
          ),
        );
      case ProductTopicFailureFrame(:final error):
        _lastError = error;
        _setConnection(
          ProductTopicConnectionStateView(
            phase: ProductTopicConnectionPhase.reconnecting,
            errorMessage: error.toString(),
          ),
        );
    }
    // The canonical reducer receives every valid frame exactly once. There is
    // no second transport broadcast buffer owned by paused page observers.
    registry.onFrame(frame);
    if (frame is ProductTopicLaggedFrame) {
      ++_sourceEpoch;
      _retryTimer?.cancel();
      _retryTimer = null;
      registry._observeBackground(_recreate());
    } else if (frame is ProductTopicFailureFrame) {
      ++_sourceEpoch;
      _scheduleRetry();
    }
  }

  void _onTerminated(int epoch, Object error) {
    if (!isActive || epoch != _sourceEpoch) return;
    _lastError = error;
    registry.onFrame(ProductTopicFailureFrame(topic: topic, error: error));
    ++_sourceEpoch;
    _setConnection(
      ProductTopicConnectionStateView(
        phase: ProductTopicConnectionPhase.reconnecting,
        errorMessage: error.toString(),
      ),
    );
    _scheduleRetry();
  }

  void _armStabilityWindow(int epoch) {
    _stabilityTimer?.cancel();
    _stabilityTimer = Timer(_stableWindow, () {
      _stabilityTimer = null;
      if (!isActive || epoch != _sourceEpoch) return;
      _reconnectAttempts = 0;
      _exhausted = false;
    });
  }

  void _scheduleRetry() {
    if (!isActive || _exhausted || _retryTimer != null) return;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _exhausted = true;
      _setConnection(
        ProductTopicConnectionStateView(
          phase: ProductTopicConnectionPhase.failed,
          retryExhausted: true,
          errorMessage: _lastError?.toString(),
        ),
      );
      return;
    }
    final doubled =
        _baseRetryDelay.inMilliseconds * (1 << _reconnectAttempts.clamp(0, 6));
    final delay = Duration(
      milliseconds: doubled > _maxRetryDelay.inMilliseconds
          ? _maxRetryDelay.inMilliseconds
          : doubled,
    );
    _reconnectAttempts++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      registry._observeBackground(_recreate());
    });
  }

  Future<void> retryNow() async {
    if (!isActive) return;
    _reconnectAttempts = 0;
    _exhausted = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    // This is a business reconnect, never a cleanup retry. A failed close
    // continues to return its cached failure until management retries it.
    await _recreate();
  }

  Future<void> _recreate() async {
    if (!isActive) return;
    if (_rebuildInFlight) {
      _rebuildRequested = true;
      return;
    }
    _rebuildInFlight = true;
    final source = _source;
    _invalidate(source);
    try {
      await _enqueue(() async {
        await _closeSource(source);
        _finishRetirement(source);
      });
    } finally {
      _rebuildInFlight = false;
      if (_rebuildRequested) {
        _rebuildRequested = false;
        if (isActive) registry._observeBackground(_recreate());
      }
    }
  }

  void _invalidate(_TopicSource? source) {
    if (source != _source) return;
    if (source?.epoch == _sourceEpoch) ++_sourceEpoch;
    stopTimers();
    source?.acquisition.requestClose();
  }

  void stopTimers() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
  }

  Future<void> _closeSource(_TopicSource? source, {bool retry = false}) async {
    try {
      if (retry) {
        await source?.acquisition.retryClose();
      } else {
        await source?.acquisition.close();
      }
    } catch (error) {
      final blocked = BridgeTopicCleanupBlocked(topic, error);
      if (source == _source) {
        stopTimers();
        _setConnection(
          ProductTopicConnectionStateView(
            phase: ProductTopicConnectionPhase.failed,
            errorMessage: blocked.toString(),
          ),
        );
      }
      throw blocked;
    }
  }

  void _finishRetirement(_TopicSource? source) {
    if (_source != source) return;
    _source = null;
    if (isActive) {
      _establish();
    } else if (refs == 0) {
      registry._forget(this);
    }
  }

  Future<void> retire(_TopicSource? source, {bool retry = false}) {
    _invalidate(source);
    return _enqueue(() async {
      await _closeSource(source, retry: retry);
      _finishRetirement(source);
    });
  }

  void _setConnection(ProductTopicConnectionStateView view) {
    if (_connection == view) return;
    _connection = view;
    registry.onTopicConnection(topic, view);
  }
}

/// Client-owned typed topic registry. One topic has one source owner through
/// opening, retiring and failed cleanup; no replacement can bypass that owner.
class BridgeTopicRegistry {
  BridgeTopicRegistry(
    this._api, {
    required ClientScope scope,
    required this.onFrame,
    required this.onTopicConnection,
  }) : _scope = scope;

  final StudioTransport _api;
  final ClientScope _scope;
  final void Function(ProductTopicFrame) onFrame;
  final void Function(ProductTopic, ProductTopicConnectionStateView?)
  onTopicConnection;
  final Map<ProductTopic, _TopicSubscription> _entries = {};
  Future<CloseReport>? _closing;
  bool _disposed = false;

  Map<String, int> activeTopicRefCountViews() => Map.unmodifiable({
    for (final entry in _entries.entries)
      describeBridgeProductTopic(entry.key): entry.value.refs,
  });

  BridgeTopicLease acquire(ProductTopic topic) => _acquire(topic);

  _Lease _acquire(ProductTopic topic) {
    if (_disposed) throw StateError('BridgeTopicRegistry is disposed');
    var entry = _entries[topic];
    if (entry == null) {
      entry = _TopicSubscription(topic, this);
      _entries[topic] = entry;
      entry.refs = 1;
      _observeBackground(entry.start());
    } else {
      entry.refs++;
    }
    return _Lease(entry);
  }

  BridgeTopicLeaseBundle acquireBundle(Iterable<ProductTopic> topics) {
    final leases = <_Lease>[];
    try {
      for (final topic in topics) leases.add(_acquire(topic));
    } catch (_) {
      for (final lease in leases) _observeBackground(lease.release());
      rethrow;
    }
    return BridgeTopicLeaseBundle._(leases);
  }

  void retry(ProductTopic topic) {
    if (_disposed) return;
    final entry = _entries[topic];
    if (entry != null) _observeBackground(entry.retryNow());
  }

  void _observeBackground(Future<void> operation) {
    unawaited(
      operation.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          // The scope retains cleanup responsibility. This caller only records
          // the domain rebuild diagnostic.
          log(
            'product_topic_background_failed error=$error',
            stackTrace: stack,
          );
        },
      ),
    );
  }

  void _forget(_TopicSubscription entry) {
    if (!identical(_entries[entry.topic], entry)) return;
    _entries.remove(entry.topic);
    onTopicConnection(entry.topic, null);
  }

  Future<CloseReport> releaseAll({required ClientCloseBudget budget}) {
    if (_closing case final pending?) return pending;
    final completion = Completer<CloseReport>();
    final closing = _closing = completion.future;
    _disposed = true;
    final entries = List.of(_entries.values);
    for (final entry in entries) {
      entry.refs = 0;
      entry._invalidate(entry._source);
    }
    completion.complete(_scope.close(budget: budget));
    _observeBackground(closing.then(_reconcileRetirements));
    return closing;
  }

  Future<CloseReport> retryCleanup({required ClientCloseBudget budget}) async {
    final report = await _scope.retryCleanup(budget: budget);
    if (_disposed) _closing = Future.value(report);
    _reconcileRetirements(report);
    return report;
  }

  void _reconcileRetirements(CloseReport report) {
    final unresolved = {for (final item in report.unresolved) item.resourceId};
    for (final entry in List.of(_entries.values)) {
      final source = entry._source;
      if (source == null) {
        if (entry.refs == 0) _forget(entry);
      } else if (source.epoch != entry._sourceEpoch &&
          !unresolved.contains(source.acquisition.resourceId)) {
        // Management already performed the retry. Only join its ACK here;
        // never dispatch a second retry through a proxy or lease.
        _observeBackground(entry.retire(source));
      }
    }
  }
}

typedef _LeaseRelease = ({Future<void> future, void Function()? start});

final class _Lease implements BridgeTopicLease {
  _Lease(this.entry);
  final _TopicSubscription entry;
  Future<void>? _releasing;
  bool _released = false;
  _TopicSource? _retirement;
  List<ClientResourceId> _retirementResourceIds = const [];

  @override
  ProductTopic get topic => entry.topic;

  @override
  List<ClientResourceId> get retirementResourceIds => _retirementResourceIds;

  @override
  Future<void> release() {
    final release = _prepareRelease();
    release.start?.call();
    return release.future;
  }

  _LeaseRelease _prepareRelease() {
    if (_releasing case final pending?) return (future: pending, start: null);
    final completion = Completer<void>();
    final result = _releasing = completion.future;
    final retry = _released;
    if (!_released) {
      _released = true;
      if (entry.refs == 0) {
        // The owner already revoked all demand during shutdown. This lease
        // has no authority to capture a source that shutdown is closing.
        completion.complete();
        return (future: result, start: null);
      }
      entry.refs--;
      if (entry.refs == 0) {
        _retirement = entry._source;
        if (_retirement case final source? when !source.acquisition.isClosed) {
          _retirementResourceIds = List.unmodifiable([
            source.acquisition.resourceId,
          ]);
        }
      } else {
        completion.complete();
        return (future: result, start: null);
      }
    }
    return (
      future: result,
      start: () => completion.complete(
        entry
            .retire(_retirement, retry: retry)
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                if (identical(_releasing, result)) _releasing = null;
                Error.throwWithStackTrace(error, stack);
              },
            ),
      ),
    );
  }
}

/// topic 的诊断标签（不含作用域凭据，仅身份描述）。
String describeBridgeProductTopic(ProductTopic topic) {
  return switch (topic) {
    ProjectDirectoryTopic() => 'projectDirectory',
    ThreadDirectoryTopic() => 'threadDirectory',
    AgentDirectoryTopic() => 'agentDirectory',
    SettingsConfigTopic() => 'settingsConfig',
    ModelCatalogTopic() => 'modelCatalog',
    RecoveryTopic() => 'recovery',
    McpCatalogTopic(:final scope) =>
      scope is HostMcpScope ? 'mcpCatalog:host' : 'mcpCatalog:${scope.key}',
    ThreadMcpTopic(:final threadId) => 'threadMcp:$threadId',
    ThreadLspTopic(:final threadId) => 'threadLsp:$threadId',
    LspTopic() => 'lsp',
    SkillsTopic(:final workspaceId) => 'skills:$workspaceId',
    ThreadModeCatalogTopic() => 'threadModeCatalog',
    AccountUsageTopic() => 'accountUsage',
    SessionCostsTopic(:final rootThreadId) => 'sessionCosts:$rootThreadId',
    UpdaterTopic() => 'updater',
    PersistenceTopic() => 'persistence',
    PersistenceQueueTopic() => 'persistenceQueue',
    AgentProfilesTopic() => 'agentProfiles',
    AcpAuthTopic() => 'acpAuth',
    BotsTopic() => 'bots',
    AcpInstallTopic() => 'acpInstall',
    AcpLocalDetectionTopic() => 'acpLocalDetection',
    ChildInteractionsTopic(:final hostThreadId) =>
      'childInteractions:$hostThreadId',
  };
}
