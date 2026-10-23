import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/statistics_state.dart';
import '../domain/statistics_values.dart';
import 'account_read_fields.dart';
import 'statistics_collection_mirror.dart';
import 'statistics_frames.dart';
import 'statistics_pages.dart';
import 'statistics_port.dart';
import 'statistics_reader.dart';

final class StatisticsSummariesMirror extends StatisticsCollectionMirror<PerformanceSummary, PerformanceSummariesHeader, PerformanceSummariesReadRef, PerformanceSummariesReadConnection, PerformanceSummariesFrame, SummaryIdentityRefs> {
  StatisticsSummariesMirror(this.port, ResourceLifetime lifetime, StatisticsReader reader)
    : source = ResourceSource(StatisticsSummaryState(projection: const ProductProjection(stamp: null, header: null, sync: ResourceSyncState(phase: ResourceSyncPhase.idle, error: null, retryExhausted: false)), summaries: const CollectionMirror.unavailable(lastKnown: null)), lifetime.budget, 'statistics:summaries:observer'), super(lifetime, ProductResource.performanceSummaries, 'statistics:summaries') {
    pages = StatisticsPages(owner: 'statistics:summaries-page', host: this, entries: (scope, offset, limit) async {
      final page = await scope.entries(offset: offset, limit: limit); return (collection: page.collection, offset: page.offset, items: page.items, nextOffset: page.nextOffset);
    }, materialize: (scope, origin, reference, previous, refs) async {
      final entity = await scope.entity(reference); if (entity.reference != reference) throw accountDataProtocol('A summary entity returned another reference.');
      return reader.summary(origin, scope, entity.value, previous: previous, previousRefs: refs);
    });
    lifetime.onSeal(source.seal);
  }
  final StatisticsPort port;
  final ResourceSource<StatisticsSummaryState> source;
  @override
  late final StatisticsPages<PerformanceSummary, PerformanceSummariesReadRef, PerformanceSummariesReadConnection, SummaryIdentityRefs> pages;
  @override
  ProductProjection<PerformanceSummariesHeader> get projection => source.value.projection;
  @override
  CollectionMirror<PerformanceSummary> get mirror => source.value.summaries;
  @override
  PerformanceSummariesReadRef reference(PerformanceSummariesHeader header) => header.reference;
  @override
  void validateHeader(PerformanceSummariesHeader header) { if (header.revision < 0) throw accountDataProtocol('A summary source has an invalid revision.'); }
  @override
  void replace(ProductProjection<PerformanceSummariesHeader> projection, CollectionMirror<PerformanceSummary> mirror) => source.publish(StatisticsSummaryState(projection: projection, summaries: mirror));
  @override
  void publish(CollectionMirror<PerformanceSummary> value) => source.publish(source.value.copyWith(summaries: value));
  @override
  Future<void> waitFor(bool Function(ProductProjection<PerformanceSummariesHeader>) predicate) async { await source.waitFor((value) => predicate(value.projection)); }
  @override
  Future<FeedConnection<PerformanceSummariesFrame>> openFeed() => port.openPerformanceSummaries();
  @override
  int? sequence(PerformanceSummariesFrame frame) => frame is PerformanceSummariesData ? frame.deliverySequence : null;
  @override
  Future<int?> apply(PerformanceSummariesFrame frame, ProductFeedOwner<PerformanceSummariesFrame> feed) async {
    switch (frame) {
      case PerformanceSummariesData(:final deliverySequence, :final event):
        switch (event) {
          case PerformanceSummariesBaselineEvent(:final identity, :final stamp, :final value): baseline(identity, stamp, value.header, value.collection, feed);
          case PerformanceSummariesChangeEvent(:final stamp, :final baseRevision, :final value): change(stamp, baseRevision, value.header, value.baseCollectionRevision, value.collection, value.upserted, value.removedEntries);
        }
        return deliverySequence;
      case PerformanceSummariesResyncRequired(:final identity): control(identity, feed); resyncInBackground();
      case PerformanceSummariesFeedFailure(:final identity, :final error): control(identity, feed); failed(feed, error);
      case PerformanceSummariesClosed(:final identity, :final reason): control(identity, feed); closed(feed, reason);
    }
    return null;
  }
  @override
  Future<PerformanceSummariesReadConnection> openRead(PerformanceSummariesReadRef reference, ProductReadOrigin origin) => port.openPerformanceSummariesRead(reference, origin: origin);
  @override
  void requestReadClose(PerformanceSummariesReadConnection scope) => scope.requestClose();
  @override
  Future<FeedCloseReport> closeRead(PerformanceSummariesReadConnection scope, bool retry) => retry ? scope.retryClose() : scope.close();
}

final class StatisticsHistoryMirror extends StatisticsCollectionMirror<PerformanceSample, PerformanceHistoryHeader, PerformanceHistoryReadRef, PerformanceHistoryReadConnection, PerformanceHistoryFrame, SampleIdentityRefs> {
  StatisticsHistoryMirror(this.port, ResourceLifetime lifetime, StatisticsReader reader)
    : source = ResourceSource(StatisticsHistoryState(projection: const ProductProjection(stamp: null, header: null, sync: ResourceSyncState(phase: ResourceSyncPhase.idle, error: null, retryExhausted: false)), samples: const CollectionMirror.unavailable(lastKnown: null)), lifetime.budget, 'statistics:history:observer'), super(lifetime, ProductResource.performanceHistory, 'statistics:history') {
    pages = StatisticsPages(owner: 'statistics:history-page', host: this, entries: (scope, offset, limit) async {
      final page = await scope.entries(offset: offset, limit: limit); return (collection: page.collection, offset: page.offset, items: page.items, nextOffset: page.nextOffset);
    }, materialize: (scope, origin, reference, previous, refs) async {
      final entity = await scope.entity(reference); if (entity.reference != reference) throw accountDataProtocol('A history entity returned another reference.');
      return reader.sample(origin, entity.value, previous: previous, previousRefs: refs);
    });
    lifetime.onSeal(source.seal);
  }
  final StatisticsPort port;
  final ResourceSource<StatisticsHistoryState> source;
  @override
  late final StatisticsPages<PerformanceSample, PerformanceHistoryReadRef, PerformanceHistoryReadConnection, SampleIdentityRefs> pages;
  @override
  ProductProjection<PerformanceHistoryHeader> get projection => source.value.projection;
  @override
  CollectionMirror<PerformanceSample> get mirror => source.value.samples;
  @override
  PerformanceHistoryReadRef reference(PerformanceHistoryHeader header) => header.reference;
  @override
  void validateHeader(PerformanceHistoryHeader header) { if (header.revision < 0) throw accountDataProtocol('A history source has an invalid revision.'); }
  @override
  void replace(ProductProjection<PerformanceHistoryHeader> projection, CollectionMirror<PerformanceSample> mirror) => source.publish(StatisticsHistoryState(projection: projection, samples: mirror));
  @override
  void publish(CollectionMirror<PerformanceSample> value) => source.publish(source.value.copyWith(samples: value));
  @override
  Future<void> waitFor(bool Function(ProductProjection<PerformanceHistoryHeader>) predicate) async { await source.waitFor((value) => predicate(value.projection)); }
  @override
  Future<FeedConnection<PerformanceHistoryFrame>> openFeed() => port.openPerformanceHistory();
  @override
  int? sequence(PerformanceHistoryFrame frame) => frame is PerformanceHistoryData ? frame.deliverySequence : null;
  @override
  Future<int?> apply(PerformanceHistoryFrame frame, ProductFeedOwner<PerformanceHistoryFrame> feed) async {
    switch (frame) {
      case PerformanceHistoryData(:final deliverySequence, :final event):
        switch (event) {
          case PerformanceHistoryBaselineEvent(:final identity, :final stamp, :final value): baseline(identity, stamp, value.header, value.collection, feed);
          case PerformanceHistoryChangeEvent(:final stamp, :final baseRevision, :final value): change(stamp, baseRevision, value.header, value.baseCollectionRevision, value.collection, value.upserted, value.removedEntries);
        }
        return deliverySequence;
      case PerformanceHistoryResyncRequired(:final identity): control(identity, feed); resyncInBackground();
      case PerformanceHistoryFeedFailure(:final identity, :final error): control(identity, feed); failed(feed, error);
      case PerformanceHistoryClosed(:final identity, :final reason): control(identity, feed); closed(feed, reason);
    }
    return null;
  }
  @override
  Future<PerformanceHistoryReadConnection> openRead(PerformanceHistoryReadRef reference, ProductReadOrigin origin) => port.openPerformanceHistoryRead(reference, origin: origin);
  @override
  void requestReadClose(PerformanceHistoryReadConnection scope) => scope.requestClose();
  @override
  Future<FeedCloseReport> closeRead(PerformanceHistoryReadConnection scope, bool retry) => retry ? scope.retryClose() : scope.close();
}
