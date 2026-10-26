import '../../../resources.dart';
import '../../../resources_ports.dart' show ProductSourceStatusReadConnection;
import 'model_reader.dart';

Future<ProductSourceStatus> readModelsSourceStatus(
  ProductSourceStatusReadConnection scope,
) async {
  final header = await scope.header();
  Future<String> text(ReadText value) => readModelText(value, scope.text);
  Future<SourceStateError> error(SourceStateErrorRead value) async =>
      SourceStateError(
        code: await text(value.code),
        message: await text(value.message),
        retryable: value.retryable,
      );
  return switch (header) {
    UninitializedProductSourceStatusReadHeader(
      :final revision,
      :final updatedAt,
    ) =>
      ProductSourceStatus.uninitialized(
        revision: revision,
        updatedAt: updatedAt,
      ),
    LoadingProductSourceStatusReadHeader(
      :final revision,
      :final operation,
      :final operationId,
      :final startedAt,
    ) =>
      ProductSourceStatus.loading(
        revision: revision,
        operation: operation,
        operationId: await text(operationId),
        startedAt: startedAt,
      ),
    ReadyProductSourceStatusReadHeader(
      :final revision,
      :final updatedAt,
      :final lastCheckedAt,
    ) =>
      ProductSourceStatus.ready(
        revision: revision,
        updatedAt: updatedAt,
        lastCheckedAt: lastCheckedAt,
      ),
    RefreshingProductSourceStatusReadHeader(
      :final revision,
      :final operation,
      :final operationId,
      :final startedAt,
      :final lastCheckedAt,
    ) =>
      ProductSourceStatus.refreshing(
        revision: revision,
        operation: operation,
        operationId: await text(operationId),
        startedAt: startedAt,
        lastCheckedAt: lastCheckedAt,
      ),
    StaleProductSourceStatusReadHeader(
      :final revision,
      :final staleAt,
      :final lastCheckedAt,
    ) =>
      ProductSourceStatus.stale(
        revision: revision,
        staleAt: staleAt,
        lastCheckedAt: lastCheckedAt,
      ),
    DegradedProductSourceStatusReadHeader(
      :final revision,
      :final failedAt,
      :final lastCheckedAt,
      :final operation,
      error: final failure,
    ) =>
      ProductSourceStatus.degraded(
        revision: revision,
        failedAt: failedAt,
        lastCheckedAt: lastCheckedAt,
        operation: operation,
        error: await error(failure),
      ),
    FailedProductSourceStatusReadHeader(
      :final revision,
      :final failedAt,
      :final operation,
      error: final failure,
    ) =>
      ProductSourceStatus.failed(
        revision: revision,
        failedAt: failedAt,
        operation: operation,
        error: await error(failure),
      ),
    StoppedProductSourceStatusReadHeader(:final revision, :final stoppedAt) =>
      ProductSourceStatus.stopped(revision: revision, stoppedAt: stoppedAt),
  };
}

ObservedBrief modelsStatusBrief(ProductSourceStatus value) => switch (value) {
  UninitializedProductSourceStatus(:final revision, :final updatedAt) =>
    ObservedBrief.uninitialized(revision: revision, updatedAt: updatedAt),
  LoadingProductSourceStatus(:final revision, :final startedAt) =>
    ObservedBrief.loading(revision: revision, startedAt: startedAt),
  ReadyProductSourceStatus(
    :final revision,
    :final updatedAt,
    :final lastCheckedAt,
  ) =>
    ObservedBrief.ready(
      revision: revision,
      updatedAt: updatedAt,
      lastCheckedAt: lastCheckedAt,
    ),
  RefreshingProductSourceStatus(
    :final revision,
    :final startedAt,
    :final lastCheckedAt,
  ) =>
    ObservedBrief.refreshing(
      revision: revision,
      startedAt: startedAt,
      lastCheckedAt: lastCheckedAt,
    ),
  StaleProductSourceStatus(
    :final revision,
    :final staleAt,
    :final lastCheckedAt,
  ) =>
    ObservedBrief.stale(
      revision: revision,
      staleAt: staleAt,
      lastCheckedAt: lastCheckedAt,
    ),
  DegradedProductSourceStatus(
    :final revision,
    :final failedAt,
    :final lastCheckedAt,
    :final error,
  ) =>
    ObservedBrief.degraded(
      revision: revision,
      failedAt: failedAt,
      lastCheckedAt: lastCheckedAt,
      retryable: error.retryable,
    ),
  FailedProductSourceStatus(:final revision, :final failedAt, :final error) =>
    ObservedBrief.failed(
      revision: revision,
      failedAt: failedAt,
      retryable: error.retryable,
    ),
  StoppedProductSourceStatus(:final revision, :final stoppedAt) =>
    ObservedBrief.stopped(revision: revision, stoppedAt: stoppedAt),
};
