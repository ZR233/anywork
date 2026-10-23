import 'dart:convert' show utf8;

import '../domain/observed_resource.dart';
import '../domain/product_source.dart';
import '../domain/read_primitives.dart';
import 'product_source_read_connection.dart';
import 'resource_errors.dart' show resourceProtocol;

const _textChunkBytes = 64 * 1024;

/// Reads a field from the caller's original immutable scope. The caller owns
/// work admission, the 64 KiB read callback, cancellation and the scope's join.
Future<String> materializeReadText(ReadText value, {
  required Future<TextChunk> Function(int fieldId, int offset) read,
}) async {
  if (value case InlineReadText(:final text)) return text;
  final ref = value as DeferredReadText;
  if (ref.fieldId < 0 || ref.utf8Bytes < 0) {
    throw resourceProtocol('The text reference has an invalid byte range.');
  }
  final result = StringBuffer();
  var offset = 0;
  while (true) {
    final part = await read(ref.fieldId, offset);
    final bytes = utf8.encode(part.text).length;
    final end = offset + bytes;
    if (part.fieldId != ref.fieldId || part.offset != offset ||
        bytes > _textChunkBytes || end < offset || end > ref.utf8Bytes) {
      throw resourceProtocol('The text reply changed its original byte range.');
    }
    result.write(part.text);
    if (part.nextOffset == null) {
      if (end != ref.utf8Bytes) throw resourceProtocol('The text field is incomplete.');
      return result.toString();
    }
    if (bytes == 0 || part.nextOffset != end || end >= ref.utf8Bytes) {
      throw resourceProtocol('The text does not advance on a UTF-8 boundary.');
    }
    offset = end;
  }
}

ObservedBrief _sourceBrief(ProductSourceStatusReadHeader value) => switch (value) {
  UninitializedProductSourceStatusReadHeader(:final revision, :final updatedAt) =>
    ObservedBrief.uninitialized(revision: revision, updatedAt: updatedAt),
  LoadingProductSourceStatusReadHeader(:final revision, :final startedAt) =>
    ObservedBrief.loading(revision: revision, startedAt: startedAt),
  ReadyProductSourceStatusReadHeader(:final revision, :final updatedAt, :final lastCheckedAt) =>
    ObservedBrief.ready(revision: revision, updatedAt: updatedAt, lastCheckedAt: lastCheckedAt),
  RefreshingProductSourceStatusReadHeader(:final revision, :final startedAt, :final lastCheckedAt) =>
    ObservedBrief.refreshing(revision: revision, startedAt: startedAt, lastCheckedAt: lastCheckedAt),
  StaleProductSourceStatusReadHeader(:final revision, :final staleAt, :final lastCheckedAt) =>
    ObservedBrief.stale(revision: revision, staleAt: staleAt, lastCheckedAt: lastCheckedAt),
  DegradedProductSourceStatusReadHeader(:final revision, :final failedAt,
      :final lastCheckedAt, :final error) =>
    ObservedBrief.degraded(revision: revision, failedAt: failedAt,
      lastCheckedAt: lastCheckedAt, retryable: error.retryable),
  FailedProductSourceStatusReadHeader(:final revision, :final failedAt, :final error) =>
    ObservedBrief.failed(revision: revision, failedAt: failedAt, retryable: error.retryable),
  StoppedProductSourceStatusReadHeader(:final revision, :final stoppedAt) =>
    ObservedBrief.stopped(revision: revision, stoppedAt: stoppedAt),
};

/// Runs inside the caller's original work/scope.use; no scope lifecycle is owned.
Future<ProductSourceStatus> materializeProductSourceStatus(
  ProductSourceStatusReadConnection scope, {
  required ObservedBrief expected,
}) async {
  final header = await scope.header();
  if (_sourceBrief(header) != expected) {
    throw resourceProtocol('The source metadata disagrees with its original brief.');
  }
  Future<String> text(ReadText value) => materializeReadText(value,
    read: (fieldId, offset) => scope.text(fieldId, offset: offset, maxBytes: _textChunkBytes));
  Future<SourceStateError> error(SourceStateErrorRead value) async => SourceStateError(
    code: await text(value.code), message: await text(value.message), retryable: value.retryable);
  return switch (header) {
    UninitializedProductSourceStatusReadHeader(:final revision, :final updatedAt) =>
      ProductSourceStatus.uninitialized(revision: revision, updatedAt: updatedAt),
    LoadingProductSourceStatusReadHeader(:final revision, :final operation,
        :final operationId, :final startedAt) =>
      ProductSourceStatus.loading(revision: revision, operation: operation,
        operationId: await text(operationId), startedAt: startedAt),
    ReadyProductSourceStatusReadHeader(:final revision, :final updatedAt, :final lastCheckedAt) =>
      ProductSourceStatus.ready(revision: revision, updatedAt: updatedAt, lastCheckedAt: lastCheckedAt),
    RefreshingProductSourceStatusReadHeader(:final revision, :final operation,
        :final operationId, :final startedAt, :final lastCheckedAt) =>
      ProductSourceStatus.refreshing(revision: revision, startedAt: startedAt,
        operation: operation, operationId: await text(operationId), lastCheckedAt: lastCheckedAt),
    StaleProductSourceStatusReadHeader(:final revision, :final staleAt, :final lastCheckedAt) =>
      ProductSourceStatus.stale(revision: revision, staleAt: staleAt, lastCheckedAt: lastCheckedAt),
    DegradedProductSourceStatusReadHeader(:final revision, :final failedAt,
        :final lastCheckedAt, :final operation, error: final failure) =>
      ProductSourceStatus.degraded(revision: revision, failedAt: failedAt,
        lastCheckedAt: lastCheckedAt, operation: operation, error: await error(failure)),
    FailedProductSourceStatusReadHeader(:final revision, :final failedAt,
        :final operation, error: final failure) =>
      ProductSourceStatus.failed(revision: revision, failedAt: failedAt,
        operation: operation, error: await error(failure)),
    StoppedProductSourceStatusReadHeader(:final revision, :final stoppedAt) =>
      ProductSourceStatus.stopped(revision: revision, stoppedAt: stoppedAt),
  };
}
