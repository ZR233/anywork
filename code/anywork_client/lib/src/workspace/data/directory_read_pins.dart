import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import 'agent_directory_mirror.dart';
import 'project_directory_mirror.dart';
import 'thread_directory_mirror.dart';
import 'workspace_port.dart';

typedef DirectorySourceTarget = ({
  ProductResource resource,
  ProductReadOrigin origin,
  ProductSourceStatusRef reference,
});

final class DirectoryReadPins {
  DirectoryReadPins(this.port, this.lifetime);
  final WorkspacePort port;
  final ResourceLifetime lifetime;
  final Map<
    ProjectDirectoryReadTarget,
    PinnedReadOwner<ProjectDirectoryReadConnection>
  >
  _projects = {};
  final Map<
    ThreadDirectoryReadTarget,
    PinnedReadOwner<ThreadDirectoryReadConnection>
  >
  _threads = {};
  final Map<
    AgentDirectoryReadTarget,
    PinnedReadOwner<AgentDirectoryReadConnection>
  >
  _agents = {};
  final Map<
    DirectorySourceTarget,
    PinnedReadOwner<ProductSourceStatusReadConnection>
  >
  _sources = {};

  void projectAdopted(ProjectDirectoryBinding value) {
    _retire(
      _projects,
      (key) =>
          key.origin == value.origin && key.reference == value.header.reference,
    );
    _sourceAdopted(
      ProductResource.projectDirectory,
      value.origin,
      value.header.source.status,
    );
  }

  void threadAdopted(ThreadDirectoryBinding value) {
    _retire(
      _threads,
      (key) =>
          key.origin == value.origin && key.reference == value.header.reference,
    );
    _sourceAdopted(
      ProductResource.threadDirectory,
      value.origin,
      value.header.source.status,
    );
  }

  void agentAdopted(AgentDirectoryBinding value) {
    _retire(
      _agents,
      (key) =>
          key.origin == value.origin && key.reference == value.header.reference,
    );
    _sourceAdopted(
      ProductResource.agentDirectory,
      value.origin,
      value.header.source.status,
    );
  }

  void _sourceAdopted(
    ProductResource resource,
    ProductReadOrigin origin,
    ProductSourceStatusRef ref,
  ) {
    for (final entry in List.of(_sources.entries)) {
      if (entry.key.resource == resource &&
          (entry.key.origin != origin || entry.key.reference != ref)) {
        entry.value.retire();
        if (identical(_sources[entry.key], entry.value))
          _sources.remove(entry.key);
      }
    }
  }

  void _retire<K, C>(Map<K, PinnedReadOwner<C>> values, bool Function(K) keep) {
    for (final entry in List.of(values.entries)) {
      if (!keep(entry.key)) {
        entry.value.retire();
        if (identical(values[entry.key], entry.value)) values.remove(entry.key);
      }
    }
  }

  Future<T> project<T>(
    ProjectDirectoryReadTarget target,
    bool Function() keep,
    Future<T> Function(ProjectDirectoryReadConnection) action,
  ) => _use(
    _projects,
    target,
    'project-directory-read',
    () =>
        port.openProjectDirectoryRead(target.reference, origin: target.origin),
    (value) => value.requestClose(),
    (value) => value.close(),
    (value) => value.retryClose(),
    keep,
    action,
  );
  Future<T> thread<T>(
    ThreadDirectoryReadTarget target,
    bool Function() keep,
    Future<T> Function(ThreadDirectoryReadConnection) action,
  ) => _use(
    _threads,
    target,
    'thread-directory-read',
    () => port.openThreadDirectoryRead(target.reference, origin: target.origin),
    (value) => value.requestClose(),
    (value) => value.close(),
    (value) => value.retryClose(),
    keep,
    action,
  );
  Future<T> agent<T>(
    AgentDirectoryReadTarget target,
    bool Function() keep,
    Future<T> Function(AgentDirectoryReadConnection) action,
  ) => _use(
    _agents,
    target,
    'agent-directory-read',
    () => port.openAgentDirectoryRead(target.reference, origin: target.origin),
    (value) => value.requestClose(),
    (value) => value.close(),
    (value) => value.retryClose(),
    keep,
    action,
  );
  Future<ProductSourceStatus> source(
    DirectorySourceTarget target,
    ObservedBrief expected,
    bool Function() keep,
  ) => _use(
    _sources,
    target,
    'directory-source-read',
    () => port.openSourceStatus(target.reference, origin: target.origin),
    (value) => value.requestClose(),
    (value) => value.close(),
    (value) => value.retryClose(),
    keep,
    (scope) => materializeProductSourceStatus(scope, expected: expected),
  );

  Future<T> _use<K, C, T>(
    Map<K, PinnedReadOwner<C>> values,
    K key,
    String label,
    Future<C> Function() open,
    void Function(C) request,
    Future<FeedCloseReport> Function(C) close,
    Future<FeedCloseReport> Function(C) retry,
    bool Function() keep,
    Future<T> Function(C) action,
  ) async {
    lifetime.admit();
    final prior = values[key];
    final PinnedReadOwner<C> pin;
    if (prior != null && prior.accepting) {
      pin = prior;
    } else {
      final registered = Completer<void>();
      pin = PinnedReadOwner<C>(
        lifetime: lifetime,
        owner: label,
        open: () async {
          await registered.future;
          return await open();
        },
        request: request,
        closeNative: close,
        retryNative: retry,
      );
      // Register the cache entry before the port can synchronously demand
      // another field of this same immutable directory scope.
      values[key] = pin;
      registered.complete();
    }
    try {
      return await pin.use(action);
    } finally {
      if (!pin.accepting || !keep()) {
        pin.retire();
        if (identical(values[key], pin)) values.remove(key);
      }
    }
  }
}
