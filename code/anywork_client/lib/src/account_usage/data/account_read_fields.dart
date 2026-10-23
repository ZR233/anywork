import 'dart:convert';
import 'dart:math' as math;

import '../../../resources.dart';
import '../../../resources_ports.dart' show ProductSourceStatusReadConnection, ResourceBudgetExceeded;

typedef AccountListPage<T> = ({int listId, int offset, int total, List<T> items, int? nextOffset});

Future<String> readAccountText(ReadText value, Future<TextChunk> Function(int, {int offset, int maxBytes}) read) async {
  if (value case InlineReadText(:final text)) {
    if (utf8.encode(text).length > 4096) throw accountDataProtocol('An inline field exceeds its byte limit.');
    return text;
  }
  final deferred = value as DeferredReadText;
  if (deferred.utf8Bytes < 0) throw accountDataProtocol('A deferred field has an invalid length.');
  final output = StringBuffer(); var offset = 0;
  while (offset < deferred.utf8Bytes) {
    final limit = math.min(65536, deferred.utf8Bytes - offset);
    final chunk = await read(deferred.fieldId, offset: offset, maxBytes: limit);
    final bytes = utf8.encode(chunk.text).length; final end = offset + bytes;
    if (chunk.fieldId != deferred.fieldId || chunk.offset != offset || bytes == 0 || bytes > limit || end < offset || end > deferred.utf8Bytes || chunk.nextOffset != (end == deferred.utf8Bytes ? null : end)) throw accountDataProtocol('A text chunk does not match its pinned field.');
    output.write(chunk.text); offset = end;
  }
  return output.toString();
}

Future<List<T>> readAccountList<T>(TypedListRef reference, Future<AccountListPage<T>> Function(int) read) async {
  if (reference.total < 0) throw accountDataProtocol('A list has an invalid length.');
  final output = <T>[]; var offset = 0;
  while (offset < reference.total) {
    final page = await read(offset); final end = offset + page.items.length;
    if (page.listId != reference.listId || page.offset != offset || page.total != reference.total || page.items.isEmpty || page.items.length > 32 || end < offset || end > reference.total || page.nextOffset != (end == reference.total ? null : end)) throw accountDataProtocol('A list page does not match its pinned field.');
    output.addAll(page.items); offset = end;
  }
  return List.unmodifiable(output);
}

Materialized<T, R>? accountPrevious<T, R>(ReadValue<T, R>? value) => switch (value) {
  ReadyReadValue<T, R>(:final current) => current,
  LoadingReadValue<T, R>(:final previous) || FailedReadValue<T, R>(:final previous) => previous,
  _ => null,
};

StudioFailure accountDataProtocol(String message) => StudioFailure(code: StudioFailureCode.protocol, message: message, retryable: false, correlationId: 'account-data');
StudioFailure accountDataFailure(Object error) => switch (error) {
  StudioFailure() => error,
  ResourceBudgetExceeded() => error.failure,
  _ => const StudioFailure(code: StudioFailureCode.internal, message: 'The account data request failed.', retryable: false, correlationId: 'account-data'),
};
const accountDataSuperseded = StudioFailure(code: StudioFailureCode.superseded, message: 'The original account data source version is no longer current.', retryable: true, correlationId: 'account-data');

Future<ProductSourceStatus> readAccountSourceStatus(ProductSourceStatusReadConnection scope) async {
  final header = await scope.header();
  Future<String> text(ReadText value) => readAccountText(value, scope.text);
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

ObservedBrief accountStatusBrief(ProductSourceStatus value) => switch (value) {
  UninitializedProductSourceStatus(:final revision, :final updatedAt) => ObservedBrief.uninitialized(revision: revision, updatedAt: updatedAt),
  LoadingProductSourceStatus(:final revision, :final startedAt) => ObservedBrief.loading(revision: revision, startedAt: startedAt),
  ReadyProductSourceStatus(:final revision, :final updatedAt, :final lastCheckedAt) => ObservedBrief.ready(revision: revision, updatedAt: updatedAt, lastCheckedAt: lastCheckedAt),
  RefreshingProductSourceStatus(:final revision, :final startedAt, :final lastCheckedAt) => ObservedBrief.refreshing(revision: revision, startedAt: startedAt, lastCheckedAt: lastCheckedAt),
  StaleProductSourceStatus(:final revision, :final staleAt, :final lastCheckedAt) => ObservedBrief.stale(revision: revision, staleAt: staleAt, lastCheckedAt: lastCheckedAt),
  DegradedProductSourceStatus(:final revision, :final failedAt, :final lastCheckedAt, :final error) => ObservedBrief.degraded(revision: revision, failedAt: failedAt, lastCheckedAt: lastCheckedAt, retryable: error.retryable),
  FailedProductSourceStatus(:final revision, :final failedAt, :final error) => ObservedBrief.failed(revision: revision, failedAt: failedAt, retryable: error.retryable),
  StoppedProductSourceStatus(:final revision, :final stoppedAt) => ObservedBrief.stopped(revision: revision, stoppedAt: stoppedAt),
};
