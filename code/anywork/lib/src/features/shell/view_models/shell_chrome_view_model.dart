import 'dart:async';

import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/shell_chrome_state.dart';

part 'shell_chrome_view_model.g.dart';

/// Chrome owns only read demands. It cannot select/open a Thread, stop a Turn,
/// submit a draft, save preferences, or close an application-owned Session.
@riverpod
class ShellChromeViewModel extends _$ShellChromeViewModel {
  late WorkspaceRepository _workspace;
  late ConfigurationRepository _configuration;
  late SessionCostsRepository _sessionCosts;
  late ConversationRepository _conversations;
  final List<Observation> _observations = [];
  final Map<String, Object> _reads = {};
  final Map<String, Object?> _attempts = {};
  final Map<String, StudioFailure> _failures = {};
  _RootBorrow? _root;
  Object? _lifetime;
  Object? _queued;
  ProjectRecord? _project;
  Object? _projectTarget;

  @override
  FutureOr<ShellChromeState> build() {
    final lifetime = Object();
    _lifetime = lifetime;
    _workspace = ref.watch(workspaceRepositoryProvider);
    _configuration = ref.watch(configurationRepositoryProvider);
    _sessionCosts = ref.watch(sessionCostsRepositoryProvider);
    _conversations = ref.watch(conversationRepositoryProvider);
    ref.onDispose(() => _dispose(lifetime));
    try {
      _watch(_workspace.state, lifetime);
      _watch(_workspace.projects, lifetime);
      _watch(_workspace.agents, lifetime);
      _watch(_configuration.state, lifetime);
      _watch(_conversations.active, lifetime);
      final initial = _snapshot(null);
      _schedule(lifetime);
      return initial;
    } catch (error, stack) {
      _dispose(lifetime);
      Error.throwWithStackTrace(error, stack);
    }
  }

  bool _current(Object lifetime) => identical(_lifetime, lifetime);

  void _watch<T>(ReadonlyLatestValue<T> source, Object lifetime) {
    final watched = source.watchLatest((_) => _schedule(lifetime));
    if (_current(lifetime)) {
      _observations.add(watched.observation);
    } else {
      _cleanup(watched.observation.cancel);
    }
  }

  void _schedule(Object lifetime) {
    if (!_current(lifetime) || identical(_queued, lifetime)) return;
    _queued = lifetime;
    scheduleMicrotask(() {
      if (!_current(lifetime)) return;
      _queued = null;
      _reconcile(lifetime);
    });
  }

  void _reconcile(Object lifetime) {
    if (!_current(lifetime)) return;
    final workspace = _workspace.state.value;
    final directory = _directory(workspace);
    final previous = state.asData?.value;
    // A reconnect may keep the previously proven root for display, but cannot
    // use that last-known identity to resolve a different selection.
    if (_root != null && !_root!.belongsTo(workspace)) _releaseRoot();
    final rootId = directory.rootId;
    if (directory.current && rootId != _root?.id) {
      _releaseRoot();
      if (rootId != null && !workspace.sealed) {
        final projection = _workspace.agents.value.projection;
        final target = (
          workspace.selectionGeneration,
          rootId,
          projection.stamp?.origin,
          projection.header?.reference,
        );
        if (_attempts['root-borrow'] != target) {
          _attempts['root-borrow'] = target;
          try {
            _bindRoot(rootId, workspace, lifetime);
          } on StudioFailure catch (error) {
            if (_current(lifetime)) _failures['root:$rootId'] = error;
          }
        }
      }
    }
    if (!_current(lifetime)) return;
    final projectKey = 'project:${workspace.selection.projectId}';
    for (final key
        in _attempts.keys
            .where((key) => key.startsWith('project:') && key != projectKey)
            .toList()) {
      _attempts.remove(key);
      _reads.remove(key);
      _failures.remove(key);
    }
    state = AsyncData(_snapshot(previous));
    if (workspace.sealed) return;

    final agents = _workspace.agents.value;
    if (workspace.selection.threadId != null && !directory.current) {
      _ensureRead(lifetime, 'agents', (
        agents.projection.stamp?.origin,
        agents.projection.header?.reference,
      ), _workspace.loadAgents);
    }
    final projectId = workspace.selection.projectId;
    if (projectId != null) {
      final target = _projectReadTarget(workspace);
      _ensureRead(lifetime, 'project:$projectId', target, () async {
        final project = await _workspace.readProject(projectId);
        if (!_current(lifetime) ||
            target != _projectReadTarget(_workspace.state.value)) {
          return;
        }
        _project = project;
        _projectTarget = target;
      });
    }
    final root = _root;
    if (root != null && root.belongsTo(workspace) && directory.current) {
      final metadata = root.metadata.state.value;
      _ensureRead(lifetime, 'root:${root.id}', (
        root,
        metadata.projection.stamp?.origin,
        metadata.projection.header?.reference,
      ), root.metadata.retry);
      _bindCosts(root, lifetime);
      final costsQuery = root.costs;
      if (costsQuery != null) {
        final costs = costsQuery.state.value;
        _ensureRead(lifetime, 'costs:${root.id}', (
          root,
          costs.projection.stamp?.origin,
          costs.projection.header?.reference,
        ), costsQuery.load);
      }
    }
    if (workspace.selection.threadId == null) {
      final configuration = _configuration.state.value;
      _ensureRead(
        lifetime,
        'defaults',
        (
          configuration.projection.stamp?.origin,
          configuration.projection.header?.reference,
        ),
        () async {
          await _configuration.loadDelegationSettings();
        },
      );
    }
  }

  ({
    String? rootId,
    List<AgentDirectoryEntry> agents,
    bool current,
    StudioFailure? error,
  })
  _directory(WorkspaceState workspace) {
    if (workspace.selection.threadId == null) {
      return (rootId: null, agents: const [], current: false, error: null);
    }
    try {
      final directory = _workspace.agents.value;
      final rootId = AgentDirectoryQueries.rootThreadId(
        threadId: workspace.selection.threadId,
        directory: directory,
      );
      final agents = AgentDirectoryQueries.forRoot(
        rootThreadId: rootId,
        directory: directory,
      );
      return (
        rootId: rootId,
        agents: AgentDirectoryQueries.menuOrder(agents),
        current: true,
        error: null,
      );
    } on StudioFailure catch (error) {
      return (rootId: null, agents: const [], current: false, error: error);
    }
  }

  void _bindRoot(String id, WorkspaceState workspace, Object lifetime) {
    final metadata = _workspace.thread(id);
    if (!_current(lifetime)) {
      _closeMetadata(metadata);
      return;
    }
    final observations = <Observation>[];
    final borrowed = _RootBorrow(id, workspace, metadata, observations);
    try {
      _root = borrowed;
      final watched = metadata.state.watchLatest((_) => _schedule(lifetime));
      if (!_current(lifetime) || !identical(_root, borrowed)) {
        _cleanup(watched.observation.cancel);
        return;
      }
      observations.add(watched.observation);
      _failures.remove('root:$id');
    } catch (error, stack) {
      if (identical(_root, borrowed)) _root = null;
      for (final observation in observations) {
        _cleanup(observation.cancel);
      }
      _closeMetadata(metadata);
      Error.throwWithStackTrace(error, stack);
    }
  }

  void _bindCosts(_RootBorrow borrowed, Object lifetime) {
    if (!_current(lifetime) || !identical(_root, borrowed)) return;
    final key = 'cost-borrow:${borrowed.id}';
    if (borrowed.costs != null || identical(_attempts[key], borrowed)) return;
    _attempts[key] = borrowed;
    SessionCostsQuery? query;
    try {
      query = _sessionCosts.costs(borrowed.id);
      if (!_current(lifetime) || !identical(_root, borrowed)) {
        _closeCosts(query);
        return;
      }
      final watched = query.state.watchLatest((_) => _schedule(lifetime));
      if (!_current(lifetime) || !identical(_root, borrowed)) {
        _cleanup(watched.observation.cancel);
        _closeCosts(query);
        return;
      }
      borrowed.costs = query;
      borrowed.observations.add(watched.observation);
      _failures.remove('costs:${borrowed.id}');
    } on StudioFailure catch (error) {
      if (query != null) _closeCosts(query);
      if (_current(lifetime) && identical(_root, borrowed)) {
        _failures['costs:${borrowed.id}'] = error;
      }
    } catch (error, stack) {
      if (query != null) _closeCosts(query);
      Error.throwWithStackTrace(error, stack);
    }
    _schedule(lifetime);
  }

  Object _projectReadTarget(WorkspaceState workspace) => (
    workspace.selectionGeneration,
    workspace.selection.projectId,
    _workspace.projects.value.projection.stamp,
    _workspace.projects.value.projection.header?.reference,
  );

  ShellChromeState _snapshot(ShellChromeState? previous) {
    final workspace = _workspace.state.value;
    final sameSelection =
        previous?.workspace.selectionGeneration ==
            workspace.selectionGeneration &&
        previous?.workspace.selection == workspace.selection;
    final directory = _directory(workspace);
    final borrowed = _root;
    final matching =
        borrowed != null &&
            borrowed.belongsTo(workspace) &&
            (!directory.current || borrowed.id == directory.rootId)
        ? borrowed
        : null;
    final rootId = directory.current ? directory.rootId : matching?.id;
    final metadata = matching?.metadata.state.value;
    final material = metadata?.value;
    final candidate = _present(material);
    final root = candidate?.id == rootId && candidate?.isRoot == true
        ? candidate
        : null;
    final configuration = _configuration.state.value;
    final delegation = configuration.delegation;
    final projectId = workspace.selection.projectId;
    final projectCurrent =
        projectId != null &&
        _project?.id == projectId &&
        _projectTarget == _projectReadTarget(workspace) &&
        _workspace.projects.value.projection.sync.phase ==
            ResourceSyncPhase.ready;
    final project = projectCurrent
        ? _project
        : sameSelection
        ? previous?.project
        : null;
    final costs = matching?.costs?.state.value;
    final errors = <String, StudioFailure>{
      for (final entry in _failures.entries)
        if (entry.key == 'agents' ||
            entry.key == 'defaults' ||
            entry.key == 'project:$projectId' ||
            entry.key == 'root:$rootId' ||
            entry.key == 'costs:$rootId')
          entry.key: entry.value,
      'agent-directory': ?directory.error,
      'agent-source': ?_workspace.agents.value.projection.sync.error,
      'project-source': ?_workspace.projects.value.projection.sync.error,
      'configuration-source': ?configuration.projection.sync.error,
      if (configuration.delegation case FailedReadValue(:final error))
        'delegation': error,
      'root-source': ?metadata?.projection.sync.error,
      if (metadata?.value case FailedReadValue(:final error))
        'root-value': error,
      'root-read': ?metadata?.readError,
      'cost-source': ?costs?.projection.sync.error,
      if (costs?.cost case FailedReadValue(:final error)) 'cost-value': error,
    };
    return ShellChromeState(
      workspace: workspace,
      activeThreadId: _conversations.active.value?.threadId,
      rootThreadId: rootId,
      project: project,
      root: root,
      projectCurrent: projectCurrent,
      rootCurrent:
          directory.current &&
          root != null &&
          metadata?.projection.sync.phase == ResourceSyncPhase.ready &&
          material is ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef> &&
          material.current.origin == metadata?.projection.stamp?.origin,
      directoryCurrent: directory.current,
      configurationCurrent:
          configuration.projection.sync.phase == ResourceSyncPhase.ready &&
          delegation
              is ReadyReadValue<DelegationSettings, ConfigurationReadRef> &&
          delegation.current.origin == configuration.projection.stamp?.origin &&
          delegation.current.reference ==
              configuration.projection.header?.reference,
      agents: directory.current
          ? directory.agents
          : sameSelection
          ? previous?.agents ?? const []
          : const [],
      delegationDefaults: configuration.delegation,
      costs: costs,
      reading: _reads.keys.toSet(),
      failures: errors,
    );
  }

  T? _present<T, R>(ReadValue<T, R>? value) => switch (value) {
    ReadyReadValue<T, R>(:final current) => current.value,
    LoadingReadValue<T, R>(:final previous) ||
    FailedReadValue<T, R>(:final previous) => previous?.value,
    _ => null,
  };

  void _ensureRead(
    Object lifetime,
    String key,
    Object? target,
    Future<void> Function() action,
  ) {
    if (!_current(lifetime) ||
        _reads.containsKey(key) ||
        _attempts.containsKey(key) && _attempts[key] == target) {
      return;
    }
    _attempts[key] = target;
    final work = Object();
    _reads[key] = work;
    state = AsyncData(_snapshot(state.asData?.value));
    if (!_current(lifetime) || !identical(_reads[key], work)) return;
    unawaited(_performRead(lifetime, key, work, action));
  }

  Future<void> _performRead(
    Object lifetime,
    String key,
    Object work,
    Future<void> Function() action,
  ) async {
    bool current() => _current(lifetime) && identical(_reads[key], work);
    try {
      await action();
      if (current()) _failures.remove(key);
    } on StudioFailure catch (error) {
      if (current()) _failures[key] = error;
    } finally {
      if (current()) {
        _reads.remove(key);
        _schedule(lifetime);
      }
    }
  }

  /// Explicit retry of this rendered context. No source failure replays a
  /// command, and an obsolete notice cannot redirect a read to a new root.
  void retry(ShellChromeState displayed) {
    final lifetime = _lifetime;
    if (lifetime == null ||
        !identical(state.asData?.value, displayed) ||
        displayed.workspace.sealed) {
      return;
    }
    _attempts.removeWhere((key, _) => !_reads.containsKey(key));
    _schedule(lifetime);
  }

  void _releaseRoot() {
    final borrowed = _root;
    _root = null;
    if (borrowed == null) return;
    for (final observation in borrowed.observations) {
      _cleanup(observation.cancel);
    }
    for (final key in [
      'root:${borrowed.id}',
      'costs:${borrowed.id}',
      'cost-borrow:${borrowed.id}',
    ]) {
      _reads.remove(key);
      _attempts.remove(key);
      _failures.remove(key);
    }
    _closeMetadata(borrowed.metadata);
    final costs = borrowed.costs;
    if (costs != null) _closeCosts(costs);
  }

  void _closeMetadata(ThreadMetadata metadata) {
    _cleanup(metadata.requestClose);
    unawaited(
      Future<CloseReport>.sync(metadata.close)
          .then(_closed, onError: _closeError),
    );
  }

  void _closeCosts(SessionCostsQuery costs) {
    _cleanup(costs.requestClose);
    unawaited(
      Future<CloseReport>.sync(costs.close).then(_closed, onError: _closeError),
    );
  }

  void _closed(CloseReport report) {
    if (!report.complete) {
      _closeError(
        StateError('Shell read borrow did not close completely: $report'),
        StackTrace.current,
      );
    }
    // An incomplete borrow remains owned/supervised by its Repository. This
    // observer never calls Repository.close or treats UI disposal as true join.
  }

  void _cleanup(void Function() action) {
    try {
      action();
    } catch (error, stack) {
      _closeError(error, stack);
    }
  }

  void _closeError(Object error, StackTrace stack) {
    final zone = Zone.current;
    scheduleMicrotask(() => zone.handleUncaughtError(error, stack));
  }

  void _dispose(Object lifetime) {
    if (!_current(lifetime)) return;
    _lifetime = null;
    _queued = null;
    final observations = List<Observation>.of(_observations);
    _observations.clear();
    for (final observation in observations) {
      _cleanup(observation.cancel);
    }
    _releaseRoot();
    _reads.clear();
    _attempts.clear();
    _failures.clear();
    _project = null;
    _projectTarget = null;
  }
}

final class _RootBorrow {
  _RootBorrow(this.id, this.selection, this.metadata, this.observations);
  final String id;
  final WorkspaceState selection;
  final ThreadMetadata metadata;
  SessionCostsQuery? costs;
  final List<Observation> observations;

  bool belongsTo(WorkspaceState workspace) =>
      workspace.selectionGeneration == selection.selectionGeneration &&
      workspace.selection == selection.selection;
}
