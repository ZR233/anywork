import 'dart:async';

import '../../lifecycle/resource_budget.dart';
import '../../observation/latest_value.dart';
import '../../studio/stores/thread_directory_store.dart';
import '../../../conversation_ports.dart';
import '../domain/conversation_repository.dart';
import '../domain/conversation_state.dart';
import 'conversation_session_impl.dart';
import 'input_turn_facts.dart';

final class ConversationRepositoryImpl
    implements ConversationRepository, InputTurnFacts {
  ConversationRepositoryImpl({
    required this.transport,
    required this.directory,
    required this.budget,
    required this.onRevision,
    this.onVisibleThreadChanged,
  });
  final ConversationTransport transport;
  final ThreadDirectoryStore directory;
  final ResourceBudget budget;
  final void Function(String key, int revision) onRevision;
  final void Function(String?)? onVisibleThreadChanged;
  final Map<String, ConversationSessionImpl> _sessions = {};
  final Map<String, ResourcePermit> _permits = {};
  final Map<String, Observation> _observations = {};
  // Every exact retirement Future remains owned, including A -> B -> A.
  final Set<Future<CloseReport>> _retiring = {};
  // `retire()` 同步栈的重入护栏：retire 的同步发布会重入
  // setVisibleThread/close；护栏只覆盖这次同步栈本身，同步部分（demand 置
  // false）完成后立即让位。同 owner 新 attempt 的下一次退休是独立责任，
  // 各自的共享 future 由 `_retiring` 持有到真实终态。
  final Set<ConversationSessionImpl> _retiringOwners = {};
  final Map<String, CloseReport> _reports = {};
  final LatestValue<String?> _visibleThreadId = LatestValue(null);
  String? _visibleThread;
  String? _requestedVisibleThread;
  bool _drainingVisibility = false;
  bool _closed = false;
  Future<CloseReport>? _closing;
  late final InputFactRegistry _inputFacts = InputFactRegistry(
    budget,
    seed: (inputId, onFact) {
      for (final session in List.of(_sessions.values)) {
        session.seedInputFacts(inputId, onFact);
      }
    },
  );

  @override
  Observation watchInputFacts({
    required String inputId,
    String? expectedThreadId,
    required void Function(InputTurnFact) onFact,
  }) {
    if (_closed) throw StateError('Conversation repository is closed');
    return _inputFacts.watchInputFacts(
      inputId: inputId,
      expectedThreadId: expectedThreadId,
      onFact: onFact,
    );
  }

  @override
  ConversationSession session(String threadId) {
    final existing = _sessions[threadId];
    if (existing != null) return existing;
    if (_closed) throw StateError('Conversation repository is closed');
    final permit = budget.acquire(
      ResourceKind.readModel,
      owner: 'conversation:$threadId',
    );
    try {
      final owner = ConversationSessionImpl(
        threadId,
        transport: transport,
        directory: directory,
        budget: budget,
        inputFacts: _inputFacts,
      );
      _sessions[threadId] = owner;
      _permits[threadId] = permit;
      _observations[threadId] = owner.source.watch((value) {
        if (value.hasSnapshot)
          onRevision('thread-state:$threadId', value.revision);
        final route = value.runtime?.modelRoute;
        if (route != null) onRevision('thread-route:$threadId', route.revision);
      });
      return owner;
    } catch (_) {
      permit.release();
      rethrow;
    }
  }

  @override
  ConversationSession? existingSession(String threadId) => _sessions[threadId];
  @override
  ThreadSessionState? sessionState(String threadId) =>
      _sessions[threadId]?.state;
  @override
  Iterable<ThreadSessionState> get sessionStates =>
      List.unmodifiable(_sessions.values.map((owner) => owner.state));
  @override
  ValueObservation<String?> get visibleThreadId => _visibleThreadId;

  @override
  void setVisibleThread(String? threadId) {
    if (_closed) {
      if (threadId != null)
        throw StateError('Conversation repository is closed');
      return;
    }
    _requestedVisibleThread = threadId;
    // 同步撤销在调用返回前生效：嵌套请求只负责撤掉不再被请求的实际活跃
    // demand；新目标的创建、可见信号与激活仍由唯一的外层 drain 串行进行。
    if (_drainingVisibility) {
      // 嵌套调用发生在 ChatOpening 等回调内：立即撤掉旧目标的活跃 demand，
      // 使其 isActive 同步变 false，随后的 transport open/ACK 不再受理；
      // 外层 drain 会在回调返回后重读最新请求继续串行创建与激活。
      _revokeObsoleteDemand();
      return;
    }
    _drainingVisibility = true;
    try {
      while (!_closed) {
        _revokeObsoleteDemand();
        final target = _requestedVisibleThread;
        if (target == null) {
          if (_visibleThread == null) break;
          _visibleThread = null;
          // Withdraw the previous ready mirror before any reentrant transition.
          if (_visibleThreadId.value != null) _visibleThreadId.publish(null);
          // Reentrant navigation only registers intent until this departure
          // retires its obsolete demand.
          if (!_closed) onVisibleThreadChanged?.call(null);
          _revokeObsoleteDemand();
          continue;
        }
        if (_visibleThread != target) {
          _visibleThread = target;
          if (_visibleThreadId.value != null) _visibleThreadId.publish(null);
          if (!_closed) onVisibleThreadChanged?.call(target);
          // The pre-transition withdrawal above already retired every obsolete
          // active demand; re-read the request after the reentrant callback.
          _revokeObsoleteDemand();
          continue;
        }
        // Same identity. The drain is complete only when the target's actual
        // demand is satisfied: an A -> B -> A cascade may have revoked A
        // synchronously, and returning to the same identity must recover it
        // with ONE new attempt instead of resurrecting the retired one.
        if (_demandSatisfied(target)) break;
        if (!_closed && _requestedVisibleThread == target) {
          // Borrowing the mirror alone never admits a native feed.
          session(target);
          if (!_closed && _requestedVisibleThread == target) {
            _visibleThreadId.publish(target);
            if (!_closed && _requestedVisibleThread == target) {
              _sessions[target]!.setVisible(true);
            }
          }
        }
        // 同步 ChatOpening 回调可能再次改变请求或撤销目标 demand；循环重读。
      }
    } finally {
      _drainingVisibility = false;
    }
  }

  bool _demandSatisfied(String threadId) {
    final owner = _sessions[threadId];
    return owner != null && owner.isActive;
  }

  /// 撤销所有不再是最新请求的实际活跃 demand；不为查询创建冷会话。
  ///
  /// 不用 `_visibleThread` 猜测哪条 demand 活跃：它可能已预改为目标。遍历既
  /// 有 session 的快照，对确已存在、isActive 且 id != 最新请求的 owner 发起
  /// 精确退休；retire 的同步发布会把 demand 置 false，使进行中的 ChatOpening
  /// 级联在 transport open 之前失效。
  void _revokeObsoleteDemand() {
    for (final owner in List.of(_sessions.values)) {
      if (_closed) return;
      if (owner.threadId == _requestedVisibleThread || !owner.isActive) {
        continue;
      }
      _retireOwner(owner);
    }
  }

  /// 退休一个 owner：先登记重入护栏，再调用可能同步重入的 `retire()`。
  ///
  /// 护栏只覆盖 `retire()` 的同步栈：retire 的同步部分已把 demand 置
  /// false，同步栈结束（含同步抛出）立即移除，同 owner 的新 attempt 仍可
  /// 再次退休。每次真实退休的共享 future 在调用前登记进 `_retiring`，
  /// close 在 retire 内部同步重入时已能看到同一责任；同步失败同样接入
  /// 共享 completer，由 `_retainRetirement` 的错误路径收束，不产生无听众
  /// 的派生错误。
  void _retireOwner(ConversationSessionImpl owner) {
    if (!_retiringOwners.add(owner)) return;
    final shared = Completer<CloseReport>();
    _retainRetirement(shared.future);
    Future<CloseReport> task;
    try {
      task = owner.retire();
    } catch (error, stackTrace) {
      _retiringOwners.remove(owner);
      shared.completeError(error, stackTrace);
      rethrow;
    }
    _retiringOwners.remove(owner);
    unawaited(task.then(shared.complete, onError: shared.completeError));
  }

  void _retainRetirement(Future<CloseReport> task) {
    _retiring.add(task);
    unawaited(
      task.then(
        (_) {
          _retiring.remove(task);
        },
        onError: (Object _, StackTrace _) {
          // The session still owns the failed native cleanup and its permit.
          _retiring.remove(task);
        },
      ),
    );
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) {
    final existing = _closing;
    if (existing != null) return existing;
    final completion = Completer<CloseReport>();
    _closing = completion.future;
    completion.complete(Future<CloseReport>.sync(() => _close(deadline)));
    return completion.future;
  }

  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    _requestedVisibleThread = null;
    final hadVisibleThread = _visibleThread != null;
    _visibleThread = null;
    if (_visibleThreadId.value != null) _visibleThreadId.publish(null);
    if (hadVisibleThread) onVisibleThreadChanged?.call(null);
    final tasks = {
      for (final entry in _sessions.entries)
        entry.key: entry.value.close(deadline: deadline),
    };
    for (final entry in tasks.entries) _reports[entry.key] = await entry.value;
    _releaseResolved();
    return CloseReport(
      unresolved: [for (final r in _reports.values) ...r.unresolved],
    );
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    final tasks = {
      for (final entry in _sessions.entries)
        entry.key: entry.value.retryCleanup(deadline: deadline),
    };
    for (final entry in tasks.entries) _reports[entry.key] = await entry.value;
    _releaseResolved();
    return CloseReport(
      unresolved: [for (final r in _reports.values) ...r.unresolved],
    );
  }

  void _releaseResolved() {
    if (!_closed) return;
    for (final id in _sessions.keys) {
      if (_reports[id]?.unresolved.isNotEmpty ?? true) continue;
      _observations.remove(id)?.cancel();
      _permits.remove(id)?.release();
    }
  }
}
