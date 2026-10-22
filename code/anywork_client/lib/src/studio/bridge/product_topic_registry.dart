// 产品 topic 租约与重连的唯一实现。引用计数归零后取消订阅，重建先等旧句柄关闭。

import 'dart:async';

import 'dart:developer' show log;

import '../../../models.dart';
import '../../../studio_ports.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';

/// Shell 常驻产品 topics：导航目录、公共配置与诊断 summary。
///
/// 这些领域在 Shell 生命周期内持续可见（侧栏、横幅、更新入口），由 controller
/// 在 bootstrap 完成后一次性持有；其余 topics 只随可见页面/面板按需租用。
const List<ProductTopic> bridgeShellTopics = [
  ProjectDirectoryTopic(),
  ThreadDirectoryTopic(),
  AgentDirectoryTopic(),
  SettingsConfigTopic(),
  ModelCatalogTopic(),
  RecoveryTopic(),
  PersistenceTopic(),
  UpdaterTopic(),
  ThreadModeCatalogTopic(),
];

/// 设置页可见 tab 的按需 topic 作用域。
///
/// 每个 tab 是独立职责：MCP、LSP、项目 Skills、Provider usage、模型性能、
/// 配置级 Profiles 不合并为一个含糊的 `services` 作用域；隐藏 tab 不持有租约，
/// 只保留 UI 状态。Skills 作用域始终携带当前 project identity。
enum BridgeSettingsScopeKind {
  statistics,
  agents,
  mcp,
  lsp,
  skills,
  usage,
  acp,
}

/// 该设置作用域需要的 topics。
///
/// [selectedProjectId] 为空（或空白）时 Skills 作用域没有可用 topic，返回空列表；
/// 其余作用域与项目无关。
List<ProductTopic> bridgeSettingsScopeTopics(
  BridgeSettingsScopeKind kind,
  String? selectedProjectId,
) {
  switch (kind) {
    case BridgeSettingsScopeKind.statistics:
      return const [ModelPerformanceTopic()];
    case BridgeSettingsScopeKind.agents:
      return const [AgentProfilesTopic()];
    case BridgeSettingsScopeKind.mcp:
      return const [McpTopic()];
    case BridgeSettingsScopeKind.lsp:
      return const [LspTopic()];
    case BridgeSettingsScopeKind.skills:
      final projectId = selectedProjectId?.trim();
      return projectId == null || projectId.isEmpty
          ? const []
          : [SkillsTopic(projectId: projectId)];
    case BridgeSettingsScopeKind.usage:
      return const [AccountUsageTopic()];
    case BridgeSettingsScopeKind.acp:
      // Accounts 页可见时只租用认证观察；进入页面不启动检查。
      return const [AcpAuthTopic()];
  }
}

/// A Client-owned topic demand. Releasing a lease never discards failed cleanup.
abstract interface class BridgeTopicLease {
  ProductTopic get topic;
  Future<void> release();
}

class BridgeTopicLeaseBundle {
  BridgeTopicLeaseBundle._(this._leases);
  final List<BridgeTopicLease> _leases;
  Future<void>? _releasing;

  List<ProductTopic> get topics =>
      List.unmodifiable([for (final lease in _leases) lease.topic]);

  Future<void> release() =>
      _releasing ??= Future.wait([for (final lease in _leases) lease.release()])
          .then<void>((_) {});
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

final class _TopicSubscription {
  _TopicSubscription(this.topic, this.registry, this.id, this.permit);

  final ProductTopic topic;
  final BridgeTopicRegistry registry;
  final int id;
  final ResourcePermit permit;
  int refs = 0;
  // This owner serializes and joins cancel; failures keep this exact handle.
  // ignore: cancel_subscriptions
  StreamSubscription<ProductTopicFrame>? _underlying;
  Future<void> _ops = Future.value();
  Future<void>? _closeTask;
  int _sourceEpoch = 0;
  int _reconnectAttempts = 0;
  bool _exhausted = false;
  bool _retiring = false;
  bool _rebuildInFlight = false;
  bool _rebuildRequested = false;
  Timer? _retryTimer;
  Timer? _stabilityTimer;
  Object? cleanupFailure;
  Object? _lastError;
  ProductTopicConnectionStateView? _connection;

  static const _baseRetryDelay = Duration(milliseconds: 250);
  static const _maxRetryDelay = Duration(seconds: 5);
  static const _maxReconnectAttempts = 5;
  static const _stableWindow = Duration(seconds: 10);

  bool get isActive =>
      !registry._disposed &&
      !_retiring &&
      refs > 0 &&
      identical(registry._entries[topic], this);

  Future<void> _enqueue(Future<void> Function() operation) {
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

  Future<void> _establish() async {
    if (!isActive) return;
    if (_underlying != null) {
      throw StateError('The prior topic subscription has not joined');
    }
    final epoch = ++_sourceEpoch;
    permit.mark(ResourcePhase.opening);
    _setConnection(
      const ProductTopicConnectionStateView(
        phase: ProductTopicConnectionPhase.connecting,
      ),
    );
    try {
      // listen is installed synchronously in this serialized operation. Even a
      // synchronous callback can only enqueue cleanup after adoption completes.
      _underlying = registry._api
          .subscribeProductTopic(topic)
          .listen(
            (frame) => _onFrame(frame, epoch),
            onError: (Object error, StackTrace stack) =>
                _onTerminated(epoch, error),
            onDone: () => _onTerminated(epoch, const BridgeTopicClosedError()),
            cancelOnError: false,
          );
      if (!isActive || epoch != _sourceEpoch) return;
      permit.mark(ResourcePhase.active);
      _armStabilityWindow(epoch);
    } catch (error) {
      if (!isActive || epoch != _sourceEpoch) return;
      _lastError = error;
      _setConnection(
        ProductTopicConnectionStateView(
          phase: ProductTopicConnectionPhase.reconnecting,
          errorMessage: error.toString(),
        ),
      );
      registry.onFrame(ProductTopicFailureFrame(topic: topic, error: error));
      _scheduleRetry();
    }
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
    if (registry._disposed || refs == 0 || permit.isReleased) return;
    _reconnectAttempts = 0;
    _exhausted = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    if (_retiring) {
      // A failed cancel is retried on the same strong owner and permit.
      await close();
    } else {
      await _recreate();
    }
  }

  Future<void> _recreate() async {
    if (!isActive) return;
    if (_rebuildInFlight) {
      _rebuildRequested = true;
      return;
    }
    _rebuildInFlight = true;
    try {
      await _enqueue(() async {
        await _cancelSource();
        if (isActive) await _establish();
      });
    } finally {
      _rebuildInFlight = false;
      if (_rebuildRequested) {
        _rebuildRequested = false;
        if (isActive) registry._observeBackground(_recreate());
      }
    }
  }

  Future<void> _cancelSource() async {
    ++_sourceEpoch;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    permit.mark(ResourcePhase.retiring);
    final old = _underlying;
    try {
      await old?.cancel();
      // Retain the old subscription until the actual cancel ACK succeeds.
      if (identical(_underlying, old)) _underlying = null;
      cleanupFailure = null;
    } catch (error) {
      cleanupFailure = error;
      _retiring = true;
      _retryTimer?.cancel();
      _retryTimer = null;
      permit.mark(ResourcePhase.unresolved);
      final blocked = BridgeTopicCleanupBlocked(topic, error);
      _setConnection(
        ProductTopicConnectionStateView(
          phase: ProductTopicConnectionPhase.failed,
          errorMessage: blocked.toString(),
        ),
      );
      throw blocked;
    }
  }

  void _setConnection(ProductTopicConnectionStateView view) {
    if (_connection == view) return;
    _connection = view;
    registry.onTopicConnection(topic, view);
  }

  Future<void> close() {
    if (permit.isReleased) return Future.value();
    _retiring = true;
    permit.mark(ResourcePhase.retiring);
    ++_sourceEpoch;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    if (_closeTask case final pending?) {
      return pending.then((_) {
        // The running close may already have adopted a replacement source for
        // reacquired demand. A release at that await boundary retires the new
        // epoch too; joining only the previous cancellation would leak it.
        if (!permit.isReleased && _retiring) return close();
      });
    }
    late final Future<void> task;
    task =
        _enqueue(() async {
          await _cancelSource();
          if (!registry._disposed && refs > 0) {
            // Reacquiring during close adds demand to this owner. Only the real
            // cancel ACK permits opening its next source identity.
            _retiring = false;
            await _establish();
          } else {
            permit.release();
            registry._forget(this);
          }
        }).whenComplete(() {
          if (identical(_closeTask, task)) _closeTask = null;
        });
    _closeTask = task;
    return task;
  }
}

/// Client-owned typed topic registry. One topic has one source owner through
/// opening, retiring and failed cleanup; no replacement can bypass that owner.
class BridgeTopicRegistry {
  BridgeTopicRegistry(
    this._api, {
    required this.onFrame,
    required this.onTopicConnection,
    ResourceBudget? budget,
  }) : budget = budget ?? ResourceBudget();

  final StudioTransport _api;
  final ResourceBudget budget;
  final void Function(ProductTopicFrame) onFrame;
  final void Function(ProductTopic, ProductTopicConnectionStateView?)
  onTopicConnection;
  final Map<ProductTopic, _TopicSubscription> _entries = {};
  Future<CloseReport>? _closing;
  bool _disposed = false;
  int _sequence = 0;

  Map<String, int> activeTopicRefCountViews() => Map.unmodifiable({
    for (final entry in _entries.entries)
      describeBridgeProductTopic(entry.key): entry.value.refs,
  });

  List<UnresolvedResource> get unresolvedResources => [
    for (final entry in _entries.values)
      if (entry._retiring || entry.cleanupFailure != null)
        UnresolvedResource(
          owner: 'topic:${describeBridgeProductTopic(entry.topic)}',
          attemptId: AttemptId(entry.id),
          reason:
              entry.cleanupFailure ??
              StateError('Topic cancellation is pending'),
        ),
  ];

  BridgeTopicLease acquire(ProductTopic topic) {
    if (_disposed) throw StateError('BridgeTopicRegistry is disposed');
    var entry = _entries[topic];
    if (entry == null) {
      final permit = budget.acquire(
        ResourceKind.observer,
        owner: 'topic:${describeBridgeProductTopic(topic)}:${_sequence + 1}',
        phase: ResourcePhase.opening,
      );
      entry = _TopicSubscription(topic, this, ++_sequence, permit);
      _entries[topic] = entry;
      entry.refs = 1;
      _observeBackground(entry.start());
    } else {
      entry.refs++;
    }
    return _Lease(entry);
  }

  BridgeTopicLeaseBundle acquireBundle(Iterable<ProductTopic> topics) {
    final leases = <BridgeTopicLease>[];
    try {
      for (final topic in topics) leases.add(acquire(topic));
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
          // Entry ownership, the exact subscription and permit already retain any
          // cleanup failure. The detached caller only records its diagnostic.
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

  Future<CloseReport> releaseAll({DateTime? deadline}) =>
      _closing ??= _releaseAll(deadline);

  Future<CloseReport> _releaseAll(DateTime? deadline) async {
    _disposed = true;
    final entries = List.of(_entries.values);
    for (final entry in entries) entry.refs = 0;
    return _join(entries, deadline);
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) => _join([
    for (final entry in _entries.values)
      if (_disposed || entry._retiring || entry.cleanupFailure != null) entry,
  ], deadline);

  Future<CloseReport> _join(
    List<_TopicSubscription> entries,
    DateTime? deadline,
  ) async {
    final pending = Future.wait([
      for (final entry in entries) _joinEntry(entry),
    ]);
    final remaining = deadline?.difference(DateTime.now());
    if (remaining == null) {
      await pending;
    } else if (remaining > Duration.zero) {
      try {
        await pending.timeout(remaining);
      } on TimeoutException {
        // The same entry/task/permit remains strongly owned beyond the deadline.
      }
    }
    return CloseReport(unresolved: unresolvedResources);
  }

  Future<void> _joinEntry(_TopicSubscription entry) async {
    try {
      await entry.close();
    } catch (error, stack) {
      log(
        'product_topic_cleanup_unresolved topic=${entry.topic} error=$error',
        stackTrace: stack,
      );
    }
  }
}

final class _Lease implements BridgeTopicLease {
  _Lease(this.entry);
  final _TopicSubscription entry;
  Future<void>? _releasing;

  @override
  ProductTopic get topic => entry.topic;
  @override
  Future<void> release() => _releasing ??= _release();

  Future<void> _release() async {
    if (entry.refs > 0) entry.refs--;
    if (entry.refs == 0) await entry.close();
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
    McpTopic() => 'mcp',
    LspTopic() => 'lsp',
    SkillsTopic(:final projectId) => 'skills:$projectId',
    ThreadModeCatalogTopic() => 'threadModeCatalog',
    AccountUsageTopic() => 'accountUsage',
    ModelPerformanceTopic() => 'modelPerformance',
    SessionCostsTopic(:final rootThreadId) => 'sessionCosts:$rootThreadId',
    UpdaterTopic() => 'updater',
    PersistenceTopic() => 'persistence',
    PersistenceQueueTopic() => 'persistenceQueue',
    AgentProfilesTopic() => 'agentProfiles',
    AcpAuthTopic() => 'acpAuth',
  };
}
