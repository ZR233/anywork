import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/statistics.dart' as native;
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../product_read_owner.dart';
import '../statistics_references.dart';
import 'read_values.dart';

/// These are three distinct native scopes, not lookups against current IDs.
final class FrbPerformanceSummaryIdentityReadConnection
    implements PerformanceSummaryIdentityReadConnection {
  FrbPerformanceSummaryIdentityReadConnection(
    PerformanceSummaryIdentityRef reference,
    ProductReadOrigin origin,
  ) {
    _owner =
        ProductReadOwner<native.BridgePerformanceSummaryIdentityReadConnection>(
          resource: 'performance-summary-identity-read',
          origin: origin,
          version: ProductReadVersion.value(
            entry: reference.entry,
            revision: reference.revision,
          ),
          open: () => native.openSummaryIdentity(
            reference: summaryIdentityRefToBridge(reference),
            origin: productOriginToBridge(origin),
          ),
          identity: (handle) => handle.identity(),
          requestClose: (handle) => handle.requestClose(),
          close: (handle) async =>
              feedCloseReportFromBridge(await handle.close()),
          retryClose: (handle) async =>
              feedCloseReportFromBridge(await handle.retryClose()),
          dispose: (handle) => handle.dispose(),
        );
  }

  late final ProductReadOwner<
    native.BridgePerformanceSummaryIdentityReadConnection
  >
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<PerformanceSummaryIdentityRead> header() => _owner.query(
    (handle) async => summaryIdentityReadFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'summary identity text field'),
              offset: nativeU64(offset, 'summary identity UTF-8 offset'),
              maxBytes: maxBytes,
            ),
          ),
          fieldId,
          offset,
          maxBytes,
        );
      });
  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}

final class FrbPerformanceEffortIdentityReadConnection
    implements PerformanceEffortIdentityReadConnection {
  FrbPerformanceEffortIdentityReadConnection(
    PerformanceEffortIdentityRef reference,
    ProductReadOrigin origin,
  ) {
    _owner =
        ProductReadOwner<native.BridgePerformanceEffortIdentityReadConnection>(
          resource: 'performance-effort-identity-read',
          origin: origin,
          version: ProductReadVersion.value(
            entry: reference.entry,
            revision: reference.revision,
          ),
          open: () => native.openEffortIdentity(
            reference: effortIdentityRefToBridge(reference),
            origin: productOriginToBridge(origin),
          ),
          identity: (handle) => handle.identity(),
          requestClose: (handle) => handle.requestClose(),
          close: (handle) async =>
              feedCloseReportFromBridge(await handle.close()),
          retryClose: (handle) async =>
              feedCloseReportFromBridge(await handle.retryClose()),
          dispose: (handle) => handle.dispose(),
        );
  }

  late final ProductReadOwner<
    native.BridgePerformanceEffortIdentityReadConnection
  >
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<PerformanceEffortIdentityRead> header() => _owner.query(
    (handle) async => effortIdentityReadFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'effort identity text field'),
              offset: nativeU64(offset, 'effort identity UTF-8 offset'),
              maxBytes: maxBytes,
            ),
          ),
          fieldId,
          offset,
          maxBytes,
        );
      });
  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}

final class FrbPerformanceSampleIdentityReadConnection
    implements PerformanceSampleIdentityReadConnection {
  FrbPerformanceSampleIdentityReadConnection(
    PerformanceSampleIdentityRef reference,
    ProductReadOrigin origin,
  ) {
    _owner =
        ProductReadOwner<native.BridgePerformanceSampleIdentityReadConnection>(
          resource: 'performance-sample-identity-read',
          origin: origin,
          version: ProductReadVersion.value(
            entry: reference.entry,
            revision: reference.revision,
          ),
          open: () => native.openSampleIdentity(
            reference: sampleIdentityRefToBridge(reference),
            origin: productOriginToBridge(origin),
          ),
          identity: (handle) => handle.identity(),
          requestClose: (handle) => handle.requestClose(),
          close: (handle) async =>
              feedCloseReportFromBridge(await handle.close()),
          retryClose: (handle) async =>
              feedCloseReportFromBridge(await handle.retryClose()),
          dispose: (handle) => handle.dispose(),
        );
  }

  late final ProductReadOwner<
    native.BridgePerformanceSampleIdentityReadConnection
  >
  _owner;
  Future<void> get opened => _owner.ready.then<void>((_) {});
  @override
  Future<PerformanceSampleIdentityRead> header() => _owner.query(
    (handle) async => sampleIdentityReadFromBridge(await handle.header()),
  );
  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _owner.query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'sample identity text field'),
              offset: nativeU64(offset, 'sample identity UTF-8 offset'),
              maxBytes: maxBytes,
            ),
          ),
          fieldId,
          offset,
          maxBytes,
        );
      });
  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
