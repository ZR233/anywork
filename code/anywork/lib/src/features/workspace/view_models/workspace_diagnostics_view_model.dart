import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/workspace_diagnostics_state.dart';
import '../state/workspace_view_state.dart';

part 'workspace_diagnostics_view_model.g.dart';

@Riverpod(keepAlive: true)
class WorkspaceDiagnosticsViewModel extends _$WorkspaceDiagnosticsViewModel {
  bool _alive = true;
  int _intent = 0;
  final List<Observation> _observations = [];
  final Map<String, Observation> _operations = {};
  final Map<String, Future<void>> _reads = {};
  final Map<String, Object?> _readTargets = {};
  final Map<String, ({Object? target, Future<void> Function() read})> _readAgain = {};
  ConversationSession? _storageSession;
  Observation? _storageObservation;
  int _storageBinding = 0;
  bool _initializing = false;
  int _bindingGeneration = 0;

  @override
  FutureOr<WorkspaceDiagnosticsState> build() {
    _alive = true;
    _initializing = true;
    ref.onDispose(_disposeBindings);
    try {
      final initial = _initialize();
      _initializing = false;
      return initial;
    } catch (error, stack) {
      _disposeBindings();
      Error.throwWithStackTrace(error, stack);
    }
  }

  WorkspaceDiagnosticsState _initialize() {
    final recoveryOwner = ref.watch(recoveryRepositoryProvider);
    final recovery = recoveryOwner.state.watchLatest((value) {
      if (!_alive || _initializing) return;
      final previous = state.requireValue.recovery;
      state = AsyncData(state.requireValue.copyWith(recovery: value));
      if (previous.projection.header?.reference != value.projection.header?.reference) {
        unawaited(loadRecoveryIssues());
      }
      if (previous.projection.header?.source.status != value.projection.header?.source.status) {
        unawaited(_readRecoverySource());
      }
    });
    _observations.add(recovery.observation);
    final owner = ref.watch(persistenceRepositoryProvider);
    final persistence = owner.state.watchLatest((value) {
      if (!_alive || _initializing) return;
      final previous = state.requireValue.persistence;
      state = AsyncData(state.requireValue.copyWith(persistence: value));
      if (previous.projection.header?.reference != value.projection.header?.reference &&
          value.projection.header?.state is! ReadyPersistenceBrief &&
          value.projection.header?.state is! FlushingPersistenceBrief) {
        unawaited(_read('persistence-value', owner.loadValue,
          target: (value.projection.stamp?.origin, value.projection.header?.reference)));
      }
    });
    _observations.add(persistence.observation);
    final queue = owner.queue.watchLatest((value) {
      if (!_alive || _initializing) return;
      final previous = state.requireValue.queue;
      state = AsyncData(state.requireValue.copyWith(queue: value));
      if (previous.projection.header?.reference != value.projection.header?.reference &&
          value.projection.header?.hasLastError == true) {
        unawaited(_read('queue-last-error', owner.loadQueueLastError,
          target: (value.projection.stamp?.origin, value.projection.header?.reference)));
      }
      if (state.requireValue.queueExpanded &&
          previous.projection.header?.reference != value.projection.header?.reference) {
        unawaited(readQueue());
      }
    });
    _observations.add(queue.observation);
    final conversations = ref.watch(conversationRepositoryProvider);
    final active = conversations.active.watchLatest(_bindStorage);
    _observations.add(active.observation);
    final initialStorage = _attachStorage(conversations.active.value);
    final generation = _bindingGeneration;
    scheduleMicrotask(() {
      if (!_alive || generation != _bindingGeneration) return;
      unawaited(loadRecoveryIssues());
      unawaited(_readRecoverySource());
      unawaited(_read('persistence-value', owner.loadValue));
      unawaited(_read('queue-page', owner.loadQueuePage));
    });
    return WorkspaceDiagnosticsState(
      recovery: recoveryOwner.state.value, persistence: owner.state.value,
      queue: owner.queue.value, actions: const {}, readErrors: const {},
      storageTarget: initialStorage, queueExpanded: false,
      dismissedRecoveryIssues: const {},
    );
  }

  void _disposeBindings() {
    _alive = false;
    ++_bindingGeneration;
    _storageObservation?.cancel();
    _storageObservation = null;
    _storageSession = null;
    for (final observer in [..._observations, ..._operations.values]) {
      observer.cancel();
    }
    _observations.clear();
    _operations.clear();
    _readAgain.clear();
    _reads.clear();
    _readTargets.clear();
  }

  StoragePanelTarget? _attachStorage(ConversationSession? session) {
    _storageObservation?.cancel();
    _storageObservation = null;
    _storageSession = session;
    final binding = ++_storageBinding;
    if (session == null) return null;
    final captured = session;
    final watched = captured.execution.watchLatest((execution) {
      if (_alive && !_initializing && identical(_storageSession, captured)) {
        final target = StoragePanelTarget(threadId: captured.threadId,
          bindingGeneration: binding, execution: execution);
        final previous = state.requireValue;
        final errors = {...previous.readErrors};
        if (execution.sync.phase == FacetSyncPhase.ready) errors.remove('active-execution');
        state = AsyncData(previous.copyWith(storageTarget: target,
          readErrors: errors,
          queueExpanded: _storageIdentity(previous.storageTarget) == _storageIdentity(target)
              && previous.queueExpanded));
      }
    });
    _storageObservation = watched.observation;
    return StoragePanelTarget(threadId: captured.threadId,
      bindingGeneration: binding, execution: captured.execution.value);
  }

  void _bindStorage(ConversationSession? session) {
    if (!_alive || _initializing || identical(_storageSession, session)) return;
    final target = _attachStorage(session);
    final errors = {...state.requireValue.readErrors}..remove('active-execution');
    state = AsyncData(state.requireValue.copyWith(storageTarget: target,
      queueExpanded: false, readErrors: errors));
  }

  Object _storageIdentity(StoragePanelTarget? target) {
    final storage = target?.execution.value?.storage;
    return (target?.threadId, target?.execution.stamp?.runtimeEpoch,
      target?.execution.stamp?.incarnation, storage?.faultGeneration,
      storage?.execution, storage?.canResume);
  }

  Future<void> loadRecoveryIssues() {
    final projection = state.requireValue.recovery.projection;
    return _read('recovery-issues', ref.read(recoveryRepositoryProvider).loadIssuesPage,
      target: (projection.stamp?.origin, projection.header?.reference));
  }

  Future<void> _readRecoverySource() {
    final projection = state.requireValue.recovery.projection;
    return _read('recovery-source', ref.read(recoveryRepositoryProvider).loadSourceStatus,
      target: (projection.stamp?.origin, projection.header?.source.status));
  }

  Future<void> readQueue() async {
    final owner = ref.read(persistenceRepositoryProvider);
    final projection = state.requireValue.queue.projection;
    final target = (projection.stamp?.origin, projection.header?.reference);
    await Future.wait([
      _read('queue-page', owner.loadQueuePage, target: target),
      _read('queue-last-error', owner.loadQueueLastError, target: target),
    ]);
  }

  void toggleQueueDetails() {
    final expanded = !state.requireValue.queueExpanded;
    state = AsyncData(state.requireValue.copyWith(queueExpanded: expanded));
    if (expanded) unawaited(readQueue());
  }

  void dismissRecoveryIssue(String id) {
    state = AsyncData(state.requireValue.copyWith(dismissedRecoveryIssues: {
      ...state.requireValue.dismissedRecoveryIssues, id,
    }));
  }

  Future<void> retryThreadHistory(StoragePanelTarget frozen) {
    final storage = frozen.execution.value?.storage;
    if (storage == null || frozen.execution.stamp == null ||
        frozen.execution.sync.phase != FacetSyncPhase.ready) return Future<void>.value();
    final owner = ref.read(persistenceRepositoryProvider);
    return _run('retry-history:${frozen.threadId}:${storage.faultGeneration}',
      () => owner.retryThreadHistory(frozen.threadId, storage.faultGeneration));
  }

  Future<void> resumeThreadHistory(StoragePanelTarget frozen) {
    final storage = frozen.execution.value?.storage;
    if (storage == null || !storage.canResume || !storage.resumeRequired ||
        frozen.execution.stamp == null || frozen.execution.sync.phase != FacetSyncPhase.ready) {
      return Future<void>.value();
    }
    final owner = ref.read(persistenceRepositoryProvider);
    return _run('resume-history:${frozen.threadId}:${storage.faultGeneration}',
      () => owner.resumeThreadHistory(frozen.threadId, storage.faultGeneration));
  }

  Future<void> retryStorageObservation(StoragePanelTarget frozen) async {
    final captured = _storageSession;
    if (captured == null || frozen.bindingGeneration != _storageBinding ||
        captured.threadId != frozen.threadId) return;
    try {
      await captured.retry(ThreadFacet.execution);
    } on StudioFailure catch (error) {
      if (!_alive || !identical(_storageSession, captured) || frozen.bindingGeneration != _storageBinding) return;
      state = AsyncData(state.requireValue.copyWith(readErrors: {
        ...state.requireValue.readErrors, 'active-execution': error,
      }));
    }
  }

  Future<void> _read(String key, Future<void> Function() read, {Object? target}) {
    if (!_alive) return Future<void>.value();
    final existing = _reads[key];
    if (existing != null) {
      // Only an actual source identity/ref change schedules one latest follow-up;
      // repeated button presses for the same in-flight page share its work.
      if (_readTargets[key] != target) {
        _readAgain[key] = (target: target, read: read);
      } else {
        _readAgain.remove(key); // A→B→A revokes the obsolete queued B read.
    }
      return existing;
    }
    final completion = Completer<void>();
    final task = completion.future;
    _reads[key] = task;
    _readTargets[key] = target;
    final generation = _bindingGeneration;
    unawaited(Future<void>.sync(() => _readOnce(key, read, generation)).then(
      completion.complete, onError: completion.completeError));
    return task.whenComplete(() {
      if (!identical(_reads[key], task)) return;
      _reads.remove(key);
      _readTargets.remove(key);
      final pending = _readAgain.remove(key);
      if (_alive && generation == _bindingGeneration && pending != null) {
        scheduleMicrotask(() {
          if (_alive && generation == _bindingGeneration) {
            unawaited(_read(key, pending.read, target: pending.target));
          }
        });
      }
    });
  }

  Future<void> _readOnce(String key, Future<void> Function() read, int generation) async {
    try {
      await read();
      if (!_alive || generation != _bindingGeneration) return;
      final errors = {...state.requireValue.readErrors}..remove(key);
      state = AsyncData(state.requireValue.copyWith(readErrors: errors));
    } on StudioFailure catch (error) {
      if (_alive && generation == _bindingGeneration) state = AsyncData(state.requireValue.copyWith(readErrors: {
        ...state.requireValue.readErrors, key: error,
      }));
    }
  }

  Future<void> retryRecovery() => _run('recovery', () => ref.read(recoveryRepositoryProvider).retry());
  Future<void> retryPersistence() => _run('persistence', () => ref.read(persistenceRepositoryProvider).retry());

  Future<void> _run<T>(String key, OperationTicket<T> Function() create) async {
    if (state.requireValue.actions[key]?.waiting == true) return;
    final intent = ++_intent;
    _operations.remove(key)?.cancel();
    _publish(key, WorkspaceActionPresentation(
      intent: intent, waiting: true, operation: null, admissionError: null,
    ));
    bool current() => _alive && state.requireValue.actions[key]?.intent == intent;
    try {
      final ticket = create();
      try {
      final watched = ticket.state.watchLatest((operation) {
        if (current()) _publish(key, state.requireValue.actions[key]!.copyWith(operation: operation));
      });
        if (current()) {
      _operations[key] = watched.observation;
          _publish(key, state.requireValue.actions[key]!.copyWith(operation: watched.value));
        } else {
          watched.observation.cancel();
        }
      } on StudioFailure catch (error) {
        if (current()) _publish(key, state.requireValue.actions[key]!.copyWith(
          observationError: error, operation: ticket.state.value));
      }
      await ticket.result;
      if (current()) _publish(key, state.requireValue.actions[key]!.copyWith(waiting: false, operation: ticket.state.value));
    } on StudioFailure catch (error) {
      if (current()) _publish(key, state.requireValue.actions[key]!.copyWith(waiting: false, admissionError: error));
    }
  }

  void _publish(String key, WorkspaceActionPresentation action) {
    state = AsyncData(state.requireValue.copyWith(actions: {...state.requireValue.actions, key: action}));
  }
}
