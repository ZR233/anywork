import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

/// Workspace-local query joins; the actual complete work belongs to D0.run.
final class DirectoryReadJobs<K, T> {
  DirectoryReadJobs(this.lifetime, this.label);
  final ResourceLifetime lifetime;
  final String label;
  final Map<K, Future<T>> _jobs = {};

  Future<T> run(K key, Future<T> Function(Future<T>? Function(K) bind) action) {
    lifetime.admit();
    if (_jobs[key] case final pending?) return pending;
    final done = Completer<T>(); _jobs[key] = done.future;
    final keys = <K>{key};
    Future<T>? bind(K canonical) {
      final pending = _jobs[canonical];
      if (pending != null && !identical(pending, done.future)) return pending;
      keys.add(canonical); _jobs[canonical] = done.future; return null;
    }
    void remove() {
      for (final key in keys) { if (identical(_jobs[key], done.future)) _jobs.remove(key); }
    }
    Future<T>.sync(() => lifetime.run(label, () => action(bind))).then<void>((value) {
      remove(); done.complete(value);
    }, onError: (Object error, StackTrace stack) { remove(); done.completeError(resourceFailure(error), stack); });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return done.future;
  }
}
