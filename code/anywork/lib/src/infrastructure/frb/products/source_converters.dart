import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/products/source.dart' as native;
import '../../../rust/api/studio/types/runtime.dart' as runtime;
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';

ObservedHeader observedHeaderFromBridge(native.BridgeObservedHeader value) => ObservedHeader(
  brief: observedBriefFromBridge(value.brief), status: sourceStatusRefFromBridge(value.status),
);

ObservedBrief observedBriefFromBridge(native.BridgeObservedBrief value) => switch (value) {
  native.BridgeObservedBrief_Uninitialized(:final revision, :final updatedAt) => ObservedBrief.uninitialized(revision: exactU64(revision, 'source revision'), updatedAt: exactI64(updatedAt, 'source updated Unix seconds')),
  native.BridgeObservedBrief_Loading(:final revision, :final startedAt) => ObservedBrief.loading(revision: exactU64(revision, 'source revision'), startedAt: exactI64(startedAt, 'source started Unix seconds')),
  native.BridgeObservedBrief_Ready(:final revision, :final updatedAt, :final lastCheckedAt) => ObservedBrief.ready(revision: exactU64(revision, 'source revision'), updatedAt: exactI64(updatedAt, 'source updated Unix seconds'), lastCheckedAt: nullableI64(lastCheckedAt, 'source checked Unix seconds')),
  native.BridgeObservedBrief_Refreshing(:final revision, :final startedAt, :final lastCheckedAt) => ObservedBrief.refreshing(revision: exactU64(revision, 'source revision'), startedAt: exactI64(startedAt, 'source started Unix seconds'), lastCheckedAt: nullableI64(lastCheckedAt, 'source checked Unix seconds')),
  native.BridgeObservedBrief_Stale(:final revision, :final staleAt, :final lastCheckedAt) => ObservedBrief.stale(revision: exactU64(revision, 'source revision'), staleAt: exactI64(staleAt, 'source stale Unix seconds'), lastCheckedAt: nullableI64(lastCheckedAt, 'source checked Unix seconds')),
  native.BridgeObservedBrief_Degraded(:final revision, :final failedAt, :final lastCheckedAt, :final retryable) => ObservedBrief.degraded(revision: exactU64(revision, 'source revision'), failedAt: exactI64(failedAt, 'source failed Unix seconds'), lastCheckedAt: nullableI64(lastCheckedAt, 'source checked Unix seconds'), retryable: retryable),
  native.BridgeObservedBrief_Failed(:final revision, :final failedAt, :final retryable) => ObservedBrief.failed(revision: exactU64(revision, 'source revision'), failedAt: exactI64(failedAt, 'source failed Unix seconds'), retryable: retryable),
  native.BridgeObservedBrief_Stopped(:final revision, :final stoppedAt) => ObservedBrief.stopped(revision: exactU64(revision, 'source revision'), stoppedAt: exactI64(stoppedAt, 'source stopped Unix seconds')),
};

SourceStateErrorRead sourceErrorReadFromBridge(native.BridgeSourceStateErrorRead value) => SourceStateErrorRead(
  code: readTextFromBridge(value.code), message: readTextFromBridge(value.message), retryable: value.retryable,
);

ProductSourceStatusReadHeader sourceStatusHeaderFromBridge(native.BridgeProductSourceStatusReadHeader value) => switch (value) {
  native.BridgeProductSourceStatusReadHeader_Uninitialized(:final revision, :final updatedAt) => ProductSourceStatusReadHeader.uninitialized(revision: exactU64(revision, 'source revision'), updatedAt: exactI64(updatedAt, 'source updated Unix seconds')),
  native.BridgeProductSourceStatusReadHeader_Loading(:final revision, :final operation, :final operationId, :final startedAt) => ProductSourceStatusReadHeader.loading(revision: exactU64(revision, 'source revision'), operation: _operation(operation), operationId: readTextFromBridge(operationId), startedAt: exactI64(startedAt, 'source started Unix seconds')),
  native.BridgeProductSourceStatusReadHeader_Ready(:final revision, :final updatedAt, :final lastCheckedAt) => ProductSourceStatusReadHeader.ready(revision: exactU64(revision, 'source revision'), updatedAt: exactI64(updatedAt, 'source updated Unix seconds'), lastCheckedAt: nullableI64(lastCheckedAt, 'source checked Unix seconds')),
  native.BridgeProductSourceStatusReadHeader_Refreshing(:final revision, :final operation, :final operationId, :final startedAt, :final lastCheckedAt) => ProductSourceStatusReadHeader.refreshing(revision: exactU64(revision, 'source revision'), operation: _operation(operation), operationId: readTextFromBridge(operationId), startedAt: exactI64(startedAt, 'source started Unix seconds'), lastCheckedAt: nullableI64(lastCheckedAt, 'source checked Unix seconds')),
  native.BridgeProductSourceStatusReadHeader_Stale(:final revision, :final staleAt, :final lastCheckedAt) => ProductSourceStatusReadHeader.stale(revision: exactU64(revision, 'source revision'), staleAt: exactI64(staleAt, 'source stale Unix seconds'), lastCheckedAt: nullableI64(lastCheckedAt, 'source checked Unix seconds')),
  native.BridgeProductSourceStatusReadHeader_Degraded(:final revision, :final failedAt, :final lastCheckedAt, :final operation, :final error) => ProductSourceStatusReadHeader.degraded(revision: exactU64(revision, 'source revision'), failedAt: exactI64(failedAt, 'source failed Unix seconds'), lastCheckedAt: nullableI64(lastCheckedAt, 'source checked Unix seconds'), operation: _operation(operation), error: sourceErrorReadFromBridge(error)),
  native.BridgeProductSourceStatusReadHeader_Failed(:final revision, :final failedAt, :final operation, :final error) => ProductSourceStatusReadHeader.failed(revision: exactU64(revision, 'source revision'), failedAt: exactI64(failedAt, 'source failed Unix seconds'), operation: _operation(operation), error: sourceErrorReadFromBridge(error)),
  native.BridgeProductSourceStatusReadHeader_Stopped(:final revision, :final stoppedAt) => ProductSourceStatusReadHeader.stopped(revision: exactU64(revision, 'source revision'), stoppedAt: exactI64(stoppedAt, 'source stopped Unix seconds')),
};

StateOperation _operation(runtime.BridgeStateOperation value) => switch (value) {
  runtime.BridgeStateOperation.initialize => StateOperation.initialize,
  runtime.BridgeStateOperation.activate => StateOperation.activate,
  runtime.BridgeStateOperation.reload => StateOperation.reload,
  runtime.BridgeStateOperation.reconcile => StateOperation.reconcile,
  runtime.BridgeStateOperation.discover => StateOperation.discover,
  runtime.BridgeStateOperation.check => StateOperation.check,
  runtime.BridgeStateOperation.probe => StateOperation.probe,
  runtime.BridgeStateOperation.repair => StateOperation.repair,
  runtime.BridgeStateOperation.reset => StateOperation.reset,
  runtime.BridgeStateOperation.shutdown => StateOperation.shutdown,
};
