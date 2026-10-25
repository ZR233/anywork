import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/delegation_model_values.dart';
import 'delegation_model_port.dart';
import 'delegation_model_reader.dart';
import 'models_port.dart';

/// Only pending reads coalesce. A new explicit query captures a fresh native
/// local-reference window, even if its original sources credential did not
/// change. The native pairing scope remains a required transport capability.
final class ModelsDetails {
  ModelsDetails(this.port, this.lifetime);
  final ModelsPort port;
  final ResourceLifetime lifetime;
  final Map<DelegationModelReadTarget, Future<DelegationModelDetail>> _pending =
      {};

  Future<DelegationModelDetail> read(DelegationModelReadTarget target) {
    lifetime.admit();
    final pending = _pending[target];
    if (pending != null) return pending;
    final done = Completer<DelegationModelDetail>();
    _pending[target] = done.future;
    unawaited(
      Future<DelegationModelDetail>.sync(
        () => lifetime.run('models:exact-model-reference', () async {
          final pin = PinnedReadOwner<DelegationModelReadConnection>(
            lifetime: lifetime,
            owner: 'models:exact-model-reference-read',
            open: () => port.openDelegationModelRead(target),
            request: (scope) => scope.requestClose(),
            closeNative: (scope) => _close(scope, retry: false),
            retryNative: (scope) => _close(scope, retry: true),
          );
          try {
            final value = await pin.use(
              (scope) => readDelegationModel(scope, target),
            );
            if (lifetime.sealed) throw resourceCancelled;
            return value;
          } finally {
            // Retiring never discards an unresolved handle or assumes its open /
            // admitted calls / native close have already joined. Lifetime keeps it.
            pin.retire();
          }
        }),
      ).then(
        (value) {
          unawaited(_pending.remove(target));
          done.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          unawaited(_pending.remove(target));
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    return done.future;
  }

  Future<FeedCloseReport> _close(
    DelegationModelReadConnection scope, {
    required bool retry,
  }) async {
    final report = await (retry ? scope.retryClose() : scope.close());
    final scopeId = scope.scopeId;
    if (scopeId.isEmpty || report.feedId != scopeId) {
      throw resourceProtocol(
        'The exact-model close report belongs to another scope.',
      );
    }
    return report;
  }
}
