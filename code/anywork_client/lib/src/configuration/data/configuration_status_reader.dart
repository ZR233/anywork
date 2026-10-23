import 'dart:async';

import '../../../resources.dart';
import '../../../resources_ports.dart';
import 'configuration_read_fields.dart';
import 'configuration_reducer.dart';

typedef ConfigurationStatusSnapshot = ({ProductReadOrigin? origin, ObservedHeader? source, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? value});

/// Configuration/Profiles metadata only. The shared lifetime/pin owns native
/// work; the concrete repository remains the sole business-state publisher.
final class ConfigurationStatusReads {
  ConfigurationStatusReads({required this.lifetime, required this.owner, required this.open, required this.current, required this.publish});
  final ResourceLifetime lifetime;
  final String owner;
  final Future<ProductSourceStatusReadConnection> Function(ProductSourceStatusRef, {required ProductReadOrigin origin}) open;
  final ConfigurationStatusSnapshot Function() current;
  final void Function(ReadValue<ProductSourceStatus, ProductSourceStatusRef>) publish;
  final Map<({ProductReadOrigin origin, ProductSourceStatusRef reference}), PinnedReadOwner<ProductSourceStatusReadConnection>> _pins = {};
  final Map<({ProductReadOrigin origin, ProductSourceStatusRef reference}), Future<void>> _loads = {};

  void retireExcept(ProductReadOrigin origin, ProductSourceStatusRef reference) {
    for (final entry in List.of(_pins.entries)) {
      if (entry.key.origin != origin || entry.key.reference != reference) { entry.value.retire(); _pins.remove(entry.key); }
    }
  }

  Future<void> load(ProductReadOrigin origin, ObservedHeader source) {
    lifetime.admit();
    final target = (origin: origin, reference: source.status);
    final known = current().value;
    if (known is ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef> && known.current.origin == origin && known.current.reference == source.status) {
      if (configurationStatusBrief(known.current.value) != source.brief) throw configurationProtocol('The source brief changed without changing its metadata reference.');
      return Future.value();
    }
    final pending = _loads[target]; if (pending != null) return pending;
    final done = Completer<void>(); _loads[target] = done.future;
    lifetime.run(owner, () async {
      if (!_current(target)) throw configurationSuperseded;
      publish(ReadValue.loading(origin: origin, reference: source.status, previous: configurationPrevious(current().value)));
      try {
        final pin = _pins.putIfAbsent(target, () => PinnedReadOwner(lifetime: lifetime, owner: owner, open: () => open(source.status, origin: origin), request: (scope) => scope.requestClose(), closeNative: (scope) => scope.close(), retryNative: (scope) => scope.retryClose()));
        final value = await pin.use(readConfigurationStatus);
        if (configurationStatusBrief(value) != source.brief) throw configurationProtocol('The source metadata disagrees with its original published brief.');
        if (lifetime.sealed) throw resourceCancelled;
        if (!_current(target)) throw configurationSuperseded;
        publish(ReadValue.ready(current: Materialized(origin: origin, reference: source.status, value: value)));
      } catch (error) {
        if (!lifetime.sealed && _current(target)) publish(ReadValue.failed(origin: origin, reference: source.status, error: configurationFailure(error), previous: configurationPrevious(current().value)));
        rethrow;
      }
    }).then((_) { _loads.remove(target); done.complete(); }, onError: (Object error, StackTrace stack) { _loads.remove(target); done.completeError(configurationFailure(error), stack); });
    return done.future;
  }

  bool _current(({ProductReadOrigin origin, ProductSourceStatusRef reference}) target) {
    final snapshot = current(); return snapshot.origin == target.origin && snapshot.source?.status == target.reference;
  }
}

Future<ProductSourceStatus> readConfigurationStatus(ProductSourceStatusReadConnection scope) async {
  final header = await scope.header();
  Future<String> text(ReadText value) => readConfigurationText(value, scope.text);
  Future<SourceStateError> error(SourceStateErrorRead value) async => SourceStateError(code: await text(value.code), message: await text(value.message), retryable: value.retryable);
  return switch (header) {
    UninitializedProductSourceStatusReadHeader(:final revision, :final updatedAt) => ProductSourceStatus.uninitialized(revision: revision, updatedAt: updatedAt),
    LoadingProductSourceStatusReadHeader(:final revision, :final operation, :final operationId, :final startedAt) => ProductSourceStatus.loading(revision: revision, operation: operation, operationId: await text(operationId), startedAt: startedAt),
    ReadyProductSourceStatusReadHeader(:final revision, :final updatedAt, :final lastCheckedAt) => ProductSourceStatus.ready(revision: revision, updatedAt: updatedAt, lastCheckedAt: lastCheckedAt),
    RefreshingProductSourceStatusReadHeader(:final revision, :final operation, :final operationId, :final startedAt, :final lastCheckedAt) => ProductSourceStatus.refreshing(revision: revision, operation: operation, operationId: await text(operationId), startedAt: startedAt, lastCheckedAt: lastCheckedAt),
    StaleProductSourceStatusReadHeader(:final revision, :final staleAt, :final lastCheckedAt) => ProductSourceStatus.stale(revision: revision, staleAt: staleAt, lastCheckedAt: lastCheckedAt),
    DegradedProductSourceStatusReadHeader(:final revision, :final failedAt, :final lastCheckedAt, :final operation, error: final failure) => ProductSourceStatus.degraded(revision: revision, failedAt: failedAt, lastCheckedAt: lastCheckedAt, operation: operation, error: await error(failure)),
    FailedProductSourceStatusReadHeader(:final revision, :final failedAt, :final operation, error: final failure) => ProductSourceStatus.failed(revision: revision, failedAt: failedAt, operation: operation, error: await error(failure)),
    StoppedProductSourceStatusReadHeader(:final revision, :final stoppedAt) => ProductSourceStatus.stopped(revision: revision, stoppedAt: stoppedAt),
  };
}

ObservedBrief configurationStatusBrief(ProductSourceStatus value) => switch (value) {
  UninitializedProductSourceStatus(:final revision, :final updatedAt) => ObservedBrief.uninitialized(revision: revision, updatedAt: updatedAt),
  LoadingProductSourceStatus(:final revision, :final startedAt) => ObservedBrief.loading(revision: revision, startedAt: startedAt),
  ReadyProductSourceStatus(:final revision, :final updatedAt, :final lastCheckedAt) => ObservedBrief.ready(revision: revision, updatedAt: updatedAt, lastCheckedAt: lastCheckedAt),
  RefreshingProductSourceStatus(:final revision, :final startedAt, :final lastCheckedAt) => ObservedBrief.refreshing(revision: revision, startedAt: startedAt, lastCheckedAt: lastCheckedAt),
  StaleProductSourceStatus(:final revision, :final staleAt, :final lastCheckedAt) => ObservedBrief.stale(revision: revision, staleAt: staleAt, lastCheckedAt: lastCheckedAt),
  DegradedProductSourceStatus(:final revision, :final failedAt, :final lastCheckedAt, :final error) => ObservedBrief.degraded(revision: revision, failedAt: failedAt, lastCheckedAt: lastCheckedAt, retryable: error.retryable),
  FailedProductSourceStatus(:final revision, :final failedAt, :final error) => ObservedBrief.failed(revision: revision, failedAt: failedAt, retryable: error.retryable),
  StoppedProductSourceStatus(:final revision, :final stoppedAt) => ObservedBrief.stopped(revision: revision, stoppedAt: stoppedAt),
};
