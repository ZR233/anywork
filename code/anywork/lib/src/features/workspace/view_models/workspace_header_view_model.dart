import 'dart:async';

import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/workspace_header_state.dart';

part 'workspace_header_view_model.g.dart';

/// A visible root's read-only demands. Neither this family key nor the agent
/// page creates a selection, opens execution, or owns a Conversation Session.
@riverpod
class WorkspaceHeaderViewModel extends _$WorkspaceHeaderViewModel {
  final List<Observation> _observations = [];
  final Map<String, _HeaderRead> _reads = {};
  ThreadMetadata? _root;
  SessionCostsQuery? _costs;
  bool _alive = true;
  bool _initializing = false;
  int _bindingGeneration = 0;

  @override
  FutureOr<WorkspaceHeaderState> build(String rootThreadId) {
    _alive = true;
    _initializing = true;
    ref.onDispose(_disposeBindings);
    try {
      final workspace = ref.watch(workspaceRepositoryProvider);
      final sessionCosts = ref.watch(sessionCostsRepositoryProvider);
      final root = workspace.thread(rootThreadId);
      _root = root;
      final rootWatch = root.state.watchLatest((value) {
        if (!_alive || _initializing || !identical(_root, root)) return;
        state = AsyncData(state.requireValue.copyWith(root: value));
      });
      _observations.add(rootWatch.observation);
      final costs = sessionCosts.costs(rootThreadId);
      _costs = costs;
      final costWatch = costs.state.watchLatest((value) {
        if (!_alive || _initializing || !identical(_costs, costs)) return;
        final previous = state.requireValue.costs.projection;
        state = AsyncData(state.requireValue.copyWith(costs: value));
        if ((previous.stamp?.origin, previous.header?.reference) !=
            (
              value.projection.stamp?.origin,
              value.projection.header?.reference,
            )) {
          unawaited(loadCosts());
        }
      });
      _observations.add(costWatch.observation);
      final agentWatch = workspace.agents.watchLatest((value) {
        if (!_alive || _initializing) return;
        final previous = state.requireValue.agents.projection;
        state = AsyncData(state.requireValue.copyWith(agents: value));
        if ((previous.stamp?.origin, previous.header?.source.status) !=
            (
              value.projection.stamp?.origin,
              value.projection.header?.source.status,
            )) {
          unawaited(loadAgentSource());
        }
      });
      _observations.add(agentWatch.observation);
      final initial = WorkspaceHeaderState(
        root: root.state.value,
        agents: workspace.agents.value,
        costs: costs.state.value,
        reading: const {},
        readErrors: const {},
      );
      _initializing = false;
      final generation = _bindingGeneration;
      scheduleMicrotask(() {
        if (!_alive || generation != _bindingGeneration) return;
        unawaited(loadCosts());
        unawaited(loadAgents());
      });
      return initial;
    } catch (error, stack) {
      _disposeBindings();
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> loadCosts() {
    final borrowed = _costs;
    if (borrowed == null || !_alive) return Future<void>.value();
    final projection = state.requireValue.costs.projection;
    return _read('costs', (
      projection.stamp?.origin,
      projection.header?.reference,
    ), borrowed.load);
  }

  Future<void> loadAgents() async {
    if (!_alive) return;
    final workspace = ref.read(workspaceRepositoryProvider);
    // One bounded page per explicit request; no automatic scan for all roots.
    await _read('agents', null, workspace.loadAgentsPage);
    if (_alive) await loadAgentSource();
  }

  Future<void> loadAgentSource() {
    if (!_alive) return Future<void>.value();
    final workspace = ref.read(workspaceRepositoryProvider);
    final projection = state.requireValue.agents.projection;
    return _read('agent-source', (
      projection.stamp?.origin,
      projection.header?.source.status,
    ), workspace.loadAgentSourceStatus);
  }

  Future<void> retryRoot() {
    final borrowed = _root;
    if (borrowed == null || !_alive) return Future<void>.value();
    final projection = state.requireValue.root.projection;
    return _read('root', (
      projection.stamp?.origin,
      projection.header?.reference,
    ), borrowed.retry);
  }

  Future<void> _read(
    String key,
    Object? target,
    Future<void> Function() action,
  ) {
    if (!_alive) return Future<void>.value();
    final existing = _reads[key];
    if (existing != null) {
      // Keep only the newest follow-up target. A→B→A cancels the queued B,
      // while the original registered read remains owned by its Repository.
      existing.again = existing.target == target
          ? null
          : () => _read(key, target, action);
      return existing.completion.future;
    }
    final work = _HeaderRead(target, _bindingGeneration);
    _reads[key] = work; // Admission precedes all external callbacks.
    state = AsyncData(
      state.requireValue.copyWith(
        reading: {...state.requireValue.reading, key},
      ),
    );
    unawaited(_performRead(key, work, action));
    return work.completion.future;
  }

  Future<void> _performRead(
    String key,
    _HeaderRead work,
    Future<void> Function() action,
  ) async {
    Object? unexpected;
    StackTrace? unexpectedStack;
    bool current() =>
        _alive &&
        work.bindingGeneration == _bindingGeneration &&
        identical(_reads[key], work);
    try {
      await action();
      if (current()) {
        final errors = {...state.requireValue.readErrors}..remove(key);
        state = AsyncData(state.requireValue.copyWith(readErrors: errors));
      }
    } on StudioFailure catch (error) {
      if (current()) {
        state = AsyncData(
          state.requireValue.copyWith(
            readErrors: {...state.requireValue.readErrors, key: error},
          ),
        );
      }
    } catch (error, stack) {
      unexpected = error;
      unexpectedStack = stack;
    } finally {
      final wasCurrent = current();
      if (identical(_reads[key], work)) _reads.remove(key);
      if (wasCurrent) {
        final reading = {...state.requireValue.reading}..remove(key);
        state = AsyncData(state.requireValue.copyWith(reading: reading));
      }
      if (unexpected == null) {
        work.completion.complete();
      } else {
        work.completion.completeError(unexpected, unexpectedStack);
      }
      final again = work.again;
      if (wasCurrent && again != null) {
        scheduleMicrotask(() {
          if (_alive && work.bindingGeneration == _bindingGeneration) {
            unawaited(again());
          }
        });
      }
    }
  }

  void _disposeBindings() {
    _alive = false;
    ++_bindingGeneration;
    _reads.clear();
    for (final observation in _observations) {
      observation.cancel();
    }
    _observations.clear();
    final root = _root;
    final costs = _costs;
    _root = null;
    _costs = null;
    // Releasing these UI borrows never closes the actual root Session or
    // drops pending reads. Each Repository retains its unresolved close owner.
    if (root != null) {
      try {
        root.requestClose();
      } catch (error, stack) {
        _closeError(error, stack);
      }
      unawaited(
        Future<CloseReport>.sync(root.close)
            .then<void>((_) {}, onError: _closeError),
      );
    }
    if (costs != null) {
      try {
        costs.requestClose();
      } catch (error, stack) {
        _closeError(error, stack);
      }
      unawaited(
        Future<CloseReport>.sync(costs.close)
            .then<void>((_) {}, onError: _closeError),
      );
    }
  }

  void _closeError(Object error, StackTrace stack) {
    final zone = Zone.current;
    scheduleMicrotask(() => zone.handleUncaughtError(error, stack));
  }
}

final class _HeaderRead {
  _HeaderRead(this.target, this.bindingGeneration);
  final Object? target;
  final int bindingGeneration;
  final Completer<void> completion = Completer<void>();
  Future<void> Function()? again;
}
