import 'dart:async';
import 'dart:math';

import '../contracts/stamps.dart';
import '../observation/latest_value.dart';
import 'client_close_budget.dart';
import 'client_resource.dart';
import 'close_report.dart';

enum _ResourceState { opening, active, closing, failedClose, closed }

/// Owns child scopes, observations, leases and asynchronous resource cleanup.
///
/// An application or independent SDK caller owns its root and injects children
/// into consumers. Closing a child never closes its parent. The root retains
/// failed and pending resources until their actual cleanup is acknowledged.
final class ClientScope {
  /// Creates an independent lifecycle root labelled by [owner].
  ClientScope({required String owner})
    : _owner = owner,
      _root = _RootIndex(),
      _parent = null;

  ClientScope._(this._owner, this._parent) : _root = _parent!._root;

  final String _owner;
  final _RootIndex _root;
  final ClientScope? _parent;
  final Set<ClientScope> _children = {};
  final Set<_Entry> _entries = {};
  final Set<_ScopedObservation> _observations = {};
  bool _closeRequested = false;

  late final List<String> _path = List.unmodifiable([
    ...?_parent?._path,
    _owner,
  ]);

  /// Creates a child whose lifetime is bounded by this scope.
  ///
  /// Throws [ClientResourceClosed] after this scope has requested closure.
  ClientScope child(String owner) {
    _checkOpen();
    final child = ClientScope._(owner, this);
    _children.add(child);
    return child;
  }

  /// Registers and starts creation of a resource owned by this scope.
  ///
  /// The entry is registered before [create] is called, including when the
  /// factory completes synchronously or reenters closure. A late result remains
  /// owned and is closed rather than delivered. [consume] joins before the
  /// resource's close acknowledgement; [onFailure] reports business failures.
  ///
  /// Adapters may pass an existing [identity] within the same root. A proxy
  /// delegates to the single actual owner; a duplicate actual owner is rejected.
  ClientAcquisition<R> open<R extends ClientResource>(
    String owner,
    Future<R> Function(ClientOperation operation) create, {
    ClientResourceId? identity,
    ClientOwnership ownership = ClientOwnership.owned,
    Future<void> Function(R resource, ClientOperation operation)? consume,
    void Function(Object error, StackTrace stack)? onFailure,
  }) {
    _checkOpen();
    final entry = _ResourceEntry<R>(
      this,
      owner,
      identity ?? _root.allocateResource(),
      ownership,
      consume,
      onFailure,
    );
    _root.register(entry);
    _entries.add(entry);
    _root.inheritCloseRequest(entry);
    entry.create(create);
    return entry;
  }

  /// Registers a consumer demand before synchronously calling [acquire].
  ///
  /// Reentrant closure and synchronous acquisition failure cannot orphan the
  /// lease entry. The scope retains cleanup failures for [retryCleanup].
  T acquireLease<T extends ClientLease>(String owner, T Function() acquire) {
    _checkOpen();
    final entry = _LeaseEntry<T>(this, owner, _root.allocate());
    _entries.add(entry);
    try {
      final lease = acquire();
      entry.attach(lease);
      return lease;
    } catch (_) {
      entry.abandon();
      rethrow;
    }
  }

  /// Registers a synchronous observation for cancellation with this scope.
  Observation observe(Observation observation) {
    _checkOpen();
    final entry = _ScopedObservation(this, _root.allocate(), observation);
    _observations.add(entry);
    return entry;
  }

  /// Seals this subtree and synchronously requests all its resources to stop.
  ///
  /// All independent requests are issued before waiting for cleanup; an error
  /// in one observation or callback cannot prevent notifying other resources.
  void requestClose() {
    final scopes = _subtree();
    // Seal the entire subtree before any external cancellation can reenter it.
    for (final scope in scopes) {
      scope._closeRequested = true;
    }
    final entries = [for (final scope in scopes) ...scope._entries];
    final observations = [for (final scope in scopes) ...scope._observations];
    for (final entry in entries) {
      entry.markCloseRequested();
    }
    for (final observation in observations) {
      if (observation.failure == null) observation.cancel();
    }
    for (final entry in entries) {
      entry.notifyClose();
    }
    for (final entry in entries) {
      entry.startClose();
    }
    for (final scope in scopes.reversed) {
      scope._prune();
    }
  }

  /// Requests closure and reports resources not settled within [budget].
  ///
  /// The budget limits waiting only. Pending work and failed handles remain
  /// owned; this method joins the existing attempt and does not retry failure.
  Future<CloseReport> close({required ClientCloseBudget budget}) {
    requestClose();
    return _wait(_closingEntries().map((entry) => entry.closeFuture), budget);
  }

  /// Retries failed cleanup within this subtree and reports remaining work.
  ///
  /// A cleanup pass retries each actual identity at most once; proxies and
  /// leases join that result. [budget] limits waiting, not the cleanup itself.
  Future<CloseReport> retryCleanup({required ClientCloseBudget budget}) {
    final entries = _closingEntries();
    final pass = _root.retry(entries);
    for (final scope in _subtree()) {
      for (final observation in List.of(scope._observations)) {
        if (observation.failure != null) observation.cancel();
      }
    }
    return _wait(entries.map(pass.forEntry), budget);
  }

  Future<CloseReport> _wait(
    Iterable<Future<void>> tasks,
    ClientCloseBudget budget,
  ) async {
    final joined = Future.wait(tasks.map(_settled));
    if (!budget.expired) {
      await joined.timeout(budget.remaining, onTimeout: () => <void>[]);
    }
    return _report();
  }

  CloseReport _report() {
    final resources = <UnresolvedResource>[];
    for (final entry in _closingEntries()) {
      resources.addAll(entry.unresolved());
    }
    for (final scope in _subtree()) {
      for (final observation in scope._observations) {
        if (observation.failure != null || observation._cancelling) {
          resources.add(observation.unresolved());
        }
      }
    }
    return CloseReport(unresolved: resources);
  }

  List<ClientScope> _subtree() => [
    this,
    for (final child in List.of(_children)) ...child._subtree(),
  ];

  List<_Entry> _closingEntries() => [
    for (final scope in _subtree())
      for (final entry in scope._entries)
        if (entry.closeRequested) entry,
  ];

  void _checkOpen() {
    if (_closeRequested) throw const ClientResourceClosed();
  }

  void _remove(_Entry entry) {
    _entries.remove(entry);
    _prune();
  }

  void _prune() {
    if (_closeRequested &&
        _entries.isEmpty &&
        _observations.isEmpty &&
        _children.isEmpty) {
      _parent?._children.remove(this);
      _parent?._prune();
    }
  }
}

abstract class _Entry implements ClientOperation {
  _Entry(this.scope, this.owner, this.resourceId);

  final ClientScope scope;
  final String owner;
  @override
  final ClientResourceId resourceId;
  @override
  bool closeRequested = false;
  _ResourceState state = _ResourceState.opening;
  Completer<void>? _result;
  Object? failure;
  StackTrace? failureStack;

  Future<void> get closeFuture => _result!.future;

  void markCloseRequested() {
    if (closeRequested) return;
    closeRequested = true;
    if (state != _ResourceState.closed) state = _ResourceState.closing;
    _newResult();
  }

  void _newResult() {
    _result = Completer<void>();
    _observe(_result!.future);
  }

  void requestClose() {
    markCloseRequested();
    notifyClose();
    startClose();
  }

  Future<void> close() {
    requestClose();
    return closeFuture;
  }

  void notifyClose();
  void startClose();
  Future<void> retryIn(_CleanupPass pass);
  Iterable<UnresolvedResource> unresolved();

  void succeed() {
    state = _ResourceState.closed;
    failure = null;
    failureStack = null;
    if (!(_result?.isCompleted ?? true)) _result!.complete();
    scope._remove(this);
  }

  void fail(Object error, StackTrace stack) {
    state = _ResourceState.failedClose;
    failure = error;
    failureStack = stack;
    _result!.completeError(error, stack);
  }

  void prepareRetry() {
    state = _ResourceState.closing;
    _newResult();
  }

  UnresolvedResource report(
    ClientResourceId identity,
    List<ClientResourceStage> stages, {
    ClientOwnership? ownership,
  }) {
    final unfinished = stages.where((stage) => !stage.complete).toList();
    return UnresolvedResource(
      resourceId: identity,
      owner: owner,
      attemptId: AttemptId(identity.sequence),
      reason:
          unfinished.first.error ??
          StateError('${unfinished.first.phase.name} is still pending'),
      ownership: ownership,
      stages: List.unmodifiable(stages),
    );
  }
}

final class _ResourceEntry<R extends ClientResource> extends _Entry
    implements ClientAcquisition<R> {
  _ResourceEntry(
    super.scope,
    super.owner,
    super.resourceId,
    this.ownership,
    this._consume,
    this._onFailure,
  ) {
    _observe(_ready!.future);
  }

  final ClientOwnership ownership;
  Future<void> Function(R, ClientOperation)? _consume;
  void Function(Object, StackTrace)? _onFailure;
  Completer<R>? _ready = Completer<R>();
  Future<R>? _opening;
  Future<void>? _consumer;
  Future<void>? _cleanup;
  final Completer<void> _created = Completer<void>();
  final Completer<void> _consumerDone = Completer<void>();
  R? _resource;
  bool _consumerStarted = false;
  bool _readyHasResource = false;
  bool _workStarted = false;
  bool _notified = false;
  Object? _requestFailure;
  StackTrace? _requestFailureStack;

  @override
  Future<R> get ready {
    if (_ready case final ready?) return ready.future;
    final closed = Future<R>.error(const ClientResourceClosed());
    _observe(closed);
    return closed;
  }

  void create(Future<R> Function(ClientOperation) factory) {
    final created = Future<R>.sync(() => factory(this));
    _opening = created;
    _observe(
      created.then<void>(
        (resource) {
          _opening = null;
          _accept(resource);
        },
        onError: (Object error, StackTrace stack) {
          _opening = null;
          _created.complete();
          _consumerDone.complete();
          if (!(_ready?.isCompleted ?? true)) {
            _ready!.completeError(error, stack);
          }
          _businessFailure(error, stack);
          requestClose();
        },
      ),
    );
  }

  void _accept(R resource) {
    // Take ownership before consulting an adapter getter or invoking callbacks.
    _resource = resource;
    _created.complete();
    try {
      if (resource.resourceId != resourceId) {
        throw StateError('The factory returned a different resource identity');
      }
    } catch (error, stack) {
      _consumerDone.complete();
      if (!(_ready?.isCompleted ?? true)) {
        _ready!.completeError(error, stack);
      }
      _businessFailure(error, stack);
      requestClose();
      return;
    }
    if (closeRequested) {
      _consumerDone.complete();
      notifyClose();
      startClose();
      return;
    }
    state = _ResourceState.active;
    _readyHasResource = true;
    _ready!.complete(resource);
    final consume = _consume;
    _consume = null;
    if (consume == null) {
      _consumerDone.complete();
      return;
    }
    _consumerStarted = true;
    final consumer = Future<void>.sync(() => consume(resource, this));
    _consumer = consumer;
    _observe(
      consumer.then<void>(
        (_) {
          _consumer = null;
          _consumerDone.complete();
        },
        onError: (Object error, StackTrace stack) {
          _consumer = null;
          _consumerDone.complete();
          _businessFailure(error, stack);
          requestClose();
        },
      ),
    );
  }

  void _businessFailure(Object error, StackTrace stack) {
    markCloseRequested();
    // The primary failure is still delivered by ready/the business callback.
    // A throwing callback is not a native cleanup failure and cannot drop owner.
    try {
      _onFailure?.call(error, stack);
    } catch (_) {
      // Cleanup is unconditional, including when the domain callback throws.
    }
  }

  @override
  void markCloseRequested() {
    super.markCloseRequested();
    if (!(_ready?.isCompleted ?? true)) {
      _ready!.completeError(const ClientResourceClosed());
    }
  }

  @override
  void notifyClose() {
    final resource = _resource;
    if (!closeRequested || _notified) return;
    if (resource == null) {
      if (ownership == ClientOwnership.proxy) {
        scope._root._identities[resourceId]?.owned?.requestClose();
      }
      return;
    }
    _notified = true;
    try {
      resource.requestClose();
      _requestFailure = null;
      _requestFailureStack = null;
    } catch (error, stack) {
      _requestFailure = error;
      _requestFailureStack = stack;
    }
  }

  @override
  void startClose() {
    if (!closeRequested || _workStarted || state == _ResourceState.closed) {
      return;
    }
    _workStarted = true;
    _observe(_runClose());
  }

  Future<void> _runClose({bool retry = false, _CleanupPass? pass}) async {
    try {
      await _created.future;
      await _consumerDone.future;
      final resource = _resource;
      if (resource != null) {
        if (retry && ownership == ClientOwnership.proxy) {
          await pass!.forOwner(resourceId);
        }
        final cleanup = retry ? resource.retryClose() : resource.close();
        _cleanup = cleanup;
        await cleanup;
        _cleanup = null;
      } else if (ownership == ClientOwnership.proxy) {
        // A failed SDK factory may have no PortProxy while its adapter still
        // owns a partially created resource under this identity.
        final owner = scope._root._identities[resourceId]?.owned;
        if (owner != null) {
          final cleanup = retry ? pass!.forOwner(resourceId) : owner.close();
          _cleanup = cleanup;
          await cleanup;
          _cleanup = null;
        }
      }
      _resource = null;
      // A completed ready Future contains R; do not retain it in the entry/ACK.
      if (_readyHasResource) _ready = null;
      _consume = null;
      _onFailure = null;
      _requestFailure = null;
      _requestFailureStack = null;
      scope._root.closed(this);
      succeed();
    } catch (error, stack) {
      _cleanup = null;
      fail(error, stack);
    }
  }

  @override
  Future<void> retryClose() {
    scope._root.retry([this]);
    return closeFuture;
  }

  @override
  Future<void> retryIn(_CleanupPass pass) {
    if (!closeRequested) return close();
    final retry = state == _ResourceState.failedClose;
    if (retry) prepareRetry();
    if (_requestFailure != null) {
      _notified = false;
      notifyClose();
    }
    if (retry) _observe(_runClose(retry: true, pass: pass));
    return closeFuture;
  }

  List<ClientResourceStage> stages() => [
    if (_opening != null || !_created.isCompleted)
      ClientResourceStage(
        owner: owner,
        phase: ClientClosePhase.opening,
        ownership: ownership,
        scopePath: scope._path,
        pending: true,
      ),
    if (_consumer != null || (_consumerStarted && !_consumerDone.isCompleted))
      ClientResourceStage(
        owner: owner,
        phase: ClientClosePhase.consumer,
        ownership: ownership,
        scopePath: scope._path,
        pending: true,
      ),
    if (_requestFailure != null)
      ClientResourceStage(
        owner: owner,
        phase: ClientClosePhase.closeRequest,
        ownership: ownership,
        scopePath: scope._path,
        error: _requestFailure,
        stackTrace: _requestFailureStack,
      ),
    ClientResourceStage(
      owner: owner,
      phase: ClientClosePhase.close,
      ownership: ownership,
      scopePath: scope._path,
      pending: _cleanup != null || state != _ResourceState.failedClose,
      error: failure,
      stackTrace: failureStack,
    ),
  ];

  @override
  Iterable<UnresolvedResource> unresolved() sync* {
    if (state == _ResourceState.closed) return;
    yield report(resourceId, stages(), ownership: ownership);
    if (ownership == ClientOwnership.proxy) {
      yield* scope._root.ownerReport(resourceId);
    }
  }
}

final class _LeaseEntry<T extends ClientLease> extends _Entry {
  _LeaseEntry(super.scope, super.owner, super.resourceId);

  T? _lease;
  Future<void>? _releaseTask;
  bool _acquired = false;
  bool _releasing = false;
  bool _captured = false;
  List<ClientResourceId> _retirement = const [];
  Object? _metadataFailure;
  StackTrace? _metadataStack;

  void attach(T lease) {
    _lease = lease;
    _acquired = true;
    if (closeRequested) {
      startClose();
    } else {
      state = _ResourceState.active;
    }
  }

  void abandon() {
    _acquired = true;
    succeed();
  }

  @override
  void notifyClose() {
    // release's synchronous prefix withdraws demand, before any scope wait.
    startClose();
  }

  @override
  void startClose() {
    if (!closeRequested ||
        !_acquired ||
        _releasing ||
        state == _ResourceState.closed) {
      return;
    }
    _release();
  }

  void _release() {
    _releasing = true;
    final lease = _lease!;
    Future<void> released;
    try {
      released = lease.release();
    } catch (error, stack) {
      released = Future<void>.error(error, stack);
    }
    _observe(released);
    _releaseTask = released;
    if (!_captured) {
      _captured = true;
      try {
        _retirement = List.unmodifiable(lease.retirementResourceIds.toSet());
        scope._root.retainLease(this, _retirement);
      } catch (error, stack) {
        _metadataFailure = error;
        _metadataStack = stack;
      }
    }
    _observe(
      released.then<void>(
        (_) {
          _releaseTask = null;
          if (_metadataFailure case final error?) {
            fail(error, _metadataStack!);
            return;
          }
          scope._root.releaseLease(this, _retirement);
          _lease = null;
          succeed();
        },
        onError: (Object error, StackTrace stack) {
          _releaseTask = null;
          fail(error, stack);
        },
      ),
    );
  }

  @override
  Future<void> retryIn(_CleanupPass pass) {
    if (state != _ResourceState.failedClose) return closeFuture;
    prepareRetry();
    _observe(_retryRelease(pass));
    return closeFuture;
  }

  Future<void> _retryRelease(_CleanupPass pass) async {
    // Start every actual owner before joining any lease. Its release method may
    // call retryClose again; the root pass makes that join the same result.
    await Future.wait(_retirement.map((id) => _settled(pass.forOwner(id))));
    _release();
  }

  @override
  Iterable<UnresolvedResource> unresolved() sync* {
    if (state == _ResourceState.closed) return;
    final stage = ClientResourceStage(
      owner: owner,
      phase: ClientClosePhase.leaseRelease,
      ownership: ClientOwnership.proxy,
      scopePath: scope._path,
      pending: _releaseTask != null || state != _ResourceState.failedClose,
      error: failure,
      stackTrace: failureStack,
    );
    for (final id in _retirement.isEmpty ? [resourceId] : _retirement) {
      yield report(id, [stage], ownership: ClientOwnership.proxy);
      yield* scope._root.ownerReport(id);
    }
  }
}

final class _ScopedObservation implements Observation {
  _ScopedObservation(this.scope, this.identity, this._observation);

  final ClientScope scope;
  final ClientResourceId identity;
  final Observation _observation;
  bool _cancelling = false;
  bool _cancelled = false;
  Object? failure;
  StackTrace? _failureStack;

  @override
  bool get isCancelled => _cancelled || _observation.isCancelled;
  @override
  bool get isPaused => _observation.isPaused;
  @override
  void pause() {
    if (!_cancelled) _observation.pause();
  }

  @override
  void resume() {
    if (!_cancelled) _observation.resume();
  }

  @override
  void cancel() {
    if (_cancelled || _cancelling) return;
    _cancelling = true;
    try {
      _observation.cancel();
      _cancelled = true;
      failure = null;
      _failureStack = null;
      scope._observations.remove(this);
      scope._prune();
    } catch (error, stack) {
      failure = error;
      _failureStack = stack;
    } finally {
      _cancelling = false;
    }
  }

  UnresolvedResource unresolved() => UnresolvedResource(
    resourceId: identity,
    owner: scope._owner,
    attemptId: AttemptId(identity.sequence),
    reason: failure ?? StateError('Observation cancellation is still pending'),
    stages: [
      ClientResourceStage(
        owner: scope._owner,
        phase: ClientClosePhase.observation,
        scopePath: scope._path,
        pending: _cancelling,
        error: failure,
        stackTrace: _failureStack,
      ),
    ],
  );
}

final class _Identity {
  _ResourceEntry<ClientResource>? owned;
  ClientResourceStage? ack;
  final Set<_ResourceEntry<ClientResource>> proxies = {};
  final Set<_Entry> leases = {};
}

final class _RootIndex {
  _RootIndex() {
    final random = Random.secure();
    _scopeId = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  late final String _scopeId;
  int _sequence = 0;
  final Map<ClientResourceId, _Identity> _identities = {};
  _CleanupPass? _pass;

  ClientResourceId allocate() => ClientResourceId(_scopeId, ++_sequence);

  ClientResourceId allocateResource() {
    final id = allocate();
    // Reserve before registration/factory callbacks. Only a live allocation can
    // be claimed or referenced; missing IDs never need historical tombstones.
    _identities[id] = _Identity();
    return id;
  }

  _Identity _registeredIdentity(ClientResourceId id) {
    if (id.scopeId != _scopeId) {
      throw StateError('The resource identity belongs to a different root');
    }
    final identity = _identities[id];
    if (identity == null) {
      throw StateError('The resource identity is not currently registered');
    }
    return identity;
  }

  void register(_ResourceEntry<ClientResource> entry) {
    final identity = _registeredIdentity(entry.resourceId);
    if (entry.ownership == ClientOwnership.owned) {
      if (identity.owned != null || identity.ack != null) {
        throw StateError('A resource identity already has an actual owner');
      }
      identity.owned = entry;
    } else {
      identity.proxies.add(entry);
    }
  }

  void inheritCloseRequest(_ResourceEntry<ClientResource> entry) {
    if (entry.ownership != ClientOwnership.owned) return;
    final identity = _identities[entry.resourceId]!;
    if (identity.proxies.any((proxy) => proxy.closeRequested) ||
        identity.leases.any((lease) => lease.closeRequested)) {
      entry.requestClose();
    }
  }

  void closed(_ResourceEntry<ClientResource> entry) {
    final identity = _identities[entry.resourceId]!;
    if (entry.ownership == ClientOwnership.owned) {
      identity.owned = null;
      identity.ack = ClientResourceStage(
        owner: entry.owner,
        phase: ClientClosePhase.close,
        ownership: ClientOwnership.owned,
        scopePath: entry.scope._path,
      );
    } else {
      identity.proxies.remove(entry);
    }
    _discardAcknowledged(entry.resourceId, identity);
  }

  void retainLease(_Entry lease, Iterable<ClientResourceId> resources) {
    // Validate every reference before mutating any slot. A lease must not turn a
    // foreign, never-allocated or fully retired ID into a new owner opportunity.
    final identities = resources.map(_registeredIdentity).toList();
    for (final identity in identities) {
      identity.leases.add(lease);
    }
  }

  void releaseLease(_Entry lease, Iterable<ClientResourceId> resources) {
    for (final id in resources) {
      final identity = _identities[id]!;
      identity.leases.remove(lease);
      _discardAcknowledged(id, identity);
    }
  }

  void _discardAcknowledged(ClientResourceId id, _Identity identity) {
    if (identity.owned == null &&
        identity.proxies.isEmpty &&
        identity.leases.isEmpty) {
      _identities.remove(id);
    }
  }

  Iterable<UnresolvedResource> ownerReport(ClientResourceId id) sync* {
    final identity = _identities[id];
    if (identity?.owned case final owner?) {
      yield owner.report(id, owner.stages(), ownership: ClientOwnership.owned);
    } else if (identity?.ack case final ack?) {
      // Included only alongside an unresolved proxy/lease, never as an issue on
      // its own. A native ACK cannot erase a pending consumer stage.
      yield UnresolvedResource(
        resourceId: id,
        owner: ack.owner,
        attemptId: AttemptId(id.sequence),
        reason: StateError('An alias has not finished after the owner ACK'),
        ownership: ClientOwnership.owned,
        stages: [ack],
      );
    }
  }

  _CleanupPass retry(Iterable<_Entry> entries) {
    final pass = _pass ??= _CleanupPass(this);
    for (final entry in entries) {
      unawaited(pass.forEntry(entry));
    }
    pass.finishIfIdle();
    return pass;
  }
}

final class _CleanupPass {
  _CleanupPass(this.root);

  final _RootIndex root;
  final Map<_Entry, Future<void>> _entries = {};
  final Map<ClientResourceId, Future<void>> _owners = {};
  int _pending = 0;

  Future<void> forOwner(ClientResourceId id) {
    if (_owners[id] case final result?) return result;
    final identity = root._identities[id];
    final owner = identity?.owned;
    final result = owner != null
        ? forEntry(owner)
        : identity?.ack != null
        ? Future<void>.value()
        : Future<void>.error(
            StateError('No actual owner is registered for resource $id'),
          );
    _observe(result);
    _owners[id] = result;
    return result;
  }

  Future<void> forEntry(_Entry entry) {
    if (_entries[entry] case final result?) return result;
    // Install the pass slot before retryClose/release can synchronously reenter.
    final joined = Completer<void>();
    final result = joined.future;
    _observe(result);
    _entries[entry] = result;
    _pending++;
    final work = Future<void>.sync(() => entry.retryIn(this));
    _observe(
      work.then<void>(
        (_) {
          _pending--;
          finishIfIdle();
          joined.complete();
        },
        onError: (Object error, StackTrace stack) {
          _pending--;
          finishIfIdle();
          joined.completeError(error, stack);
        },
      ),
    );
    return result;
  }

  void finishIfIdle() {
    if (_pending == 0 && identical(root._pass, this)) root._pass = null;
  }
}

void _observe<T>(Future<T> future) {
  unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
}

Future<void> _settled(Future<void> future) =>
    future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
