import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import 'recovery_index.dart';
import 'recovery_mirror.dart';
import 'recovery_port.dart';

typedef _SourceReadKey = ({
  int generation,
  ProductReadOrigin? origin,
  ProductSourceStatusRef? reference,
});

final class RecoverySourceReads {
  RecoverySourceReads(this.port, this.mirror, this.lifetime);
  final RecoveryPort port;
  final RecoveryMirror mirror;
  final ResourceLifetime lifetime;
  final Map<
    ({ProductReadOrigin origin, ProductSourceStatusRef reference}),
    PinnedReadOwner<ProductSourceStatusReadConnection>
  >
  _scopes = {};
  final Map<_SourceReadKey, Future<void>> _jobs = {};

  void adopted(RecoveryBinding binding) {
    for (final entry in List.of(_scopes.entries)) {
      if (entry.key.origin != binding.origin ||
          entry.key.reference != binding.header.source.status) {
        entry.value.retire();
        if (identical(_scopes[entry.key], entry.value))
          _scopes.remove(entry.key);
      }
    }
  }

  Future<void> load() {
    final demand = mirror.capture();
    final frozen = demand.binding;
    final key = (
      generation: demand.generation,
      origin: frozen?.origin,
      reference: frozen?.header.source.status,
    );
    if (_jobs[key] case final pending?) return pending;
    if (frozen != null) {
      final value = mirror.source.value.sourceStatus;
      if (value
              is ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef> &&
          value.current.origin == frozen.origin &&
          value.current.reference == frozen.header.source.status)
        return Future.value();
    }
    final done = Completer<void>();
    _jobs[key] = done.future;
    final keys = <_SourceReadKey>{key};
    void removeAliases() {
      for (final key in keys) {
        if (identical(_jobs[key], done.future)) unawaited(_jobs.remove(key));
      }
    }

    RecoveryBinding? binding;
    Future<void>? joined;
    unawaited(
      Future<void>.sync(
        () => lifetime.run('recovery-source-read', () async {
          lifetime.admit();
          await mirror.ready(
            demand,
            bind: (current) {
              final canonical = (
                generation: current.generation,
                origin: current.origin,
                reference: current.header.source.status,
              );
              final pending = _jobs[canonical];
              if (pending != null && !identical(pending, done.future)) {
                joined = pending;
                return;
              }
              _jobs[canonical] = done.future;
              keys.add(canonical);
              binding = current;
            },
          );
          if (joined case final pending?) {
            await pending;
            return;
          }
          final current = binding!;
          final expected = current.header.source.brief;
          final target = (
            origin: current.origin,
            reference: current.header.source.status,
          );
          mirror.check(current);
          if (mirror.current!.header.source.status != target.reference)
            throw recoverySuperseded;
          final known = mirror.source.value.sourceStatus;
          if (known
                  is ReadyReadValue<
                    ProductSourceStatus,
                    ProductSourceStatusRef
                  > &&
              known.current.origin == target.origin &&
              known.current.reference == target.reference)
            return;
          mirror.source.publish(
            mirror.source.value.copyWith(
              sourceStatus: ReadValue.loading(
                origin: target.origin,
                reference: target.reference,
                previous: recoveryPrevious(mirror.source.value.sourceStatus),
              ),
            ),
          );
          final prior = _scopes[target];
          final scope = prior != null && prior.accepting
              ? prior
              : PinnedReadOwner<ProductSourceStatusReadConnection>(
                  lifetime: lifetime,
                  owner: 'recovery-source-pin',
                  open: () => port.openSourceStatus(
                    target.reference,
                    origin: target.origin,
                  ),
                  request: (value) => value.requestClose(),
                  closeNative: (value) => value.close(),
                  retryNative: (value) => value.retryClose(),
                );
          _scopes[target] = scope;
          try {
            final value = await scope.use(
              (connection) => materializeProductSourceStatus(
                connection,
                expected: expected,
              ),
            );
            mirror.check(current);
            if (mirror.current!.header.source.status != target.reference)
              throw recoverySuperseded;
            mirror.source.publish(
              mirror.source.value.copyWith(
                sourceStatus: ReadValue.ready(
                  current: Materialized(
                    origin: target.origin,
                    reference: target.reference,
                    value: value,
                  ),
                ),
              ),
            );
          } finally {
            final latest = mirror.current;
            if (!scope.accepting ||
                latest == null ||
                latest.origin != target.origin ||
                latest.header.source.status != target.reference) {
              scope.retire();
              if (identical(_scopes[target], scope)) _scopes.remove(target);
            }
          }
        }),
      ).then<void>(
        (_) {
          removeAliases();
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          removeAliases();
          final original = binding;
          final current = mirror.current;
          final known = mirror.source.value.sourceStatus;
          final materialized =
              known
                  is ReadyReadValue<
                    ProductSourceStatus,
                    ProductSourceStatusRef
                  > &&
              known.current.origin == original?.origin &&
              known.current.reference == original?.header.source.status;
          if (!lifetime.sealed &&
              original != null &&
              current != null &&
              original.generation == current.generation &&
              original.origin == current.origin &&
              original.header.source.status == current.header.source.status &&
              !materialized) {
            mirror.source.publish(
              mirror.source.value.copyWith(
                sourceStatus: ReadValue.failed(
                  origin: original.origin,
                  reference: original.header.source.status,
                  error: resourceFailure(error),
                  previous: recoveryPrevious(mirror.source.value.sourceStatus),
                ),
              ),
            );
          }
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    return done.future;
  }
}
