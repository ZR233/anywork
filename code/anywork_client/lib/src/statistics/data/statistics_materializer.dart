import '../../../resources.dart';
import '../domain/statistics_state.dart';
import '../domain/statistics_values.dart';
import 'statistics_material.dart';
import 'statistics_port.dart';
import 'statistics_read_fields.dart';
import 'statistics_reader.dart';

/// Reads one statistics side to completion inside its original pinned scope.
///
/// Every page, entry, effort breakdown and identity text is validated against
/// the captured collection and the pinned list before the material exists, so
/// no partial collection is ever published. Existing page and read budgets are
/// unchanged; there is no additional cap on legitimately published rows.
final class StatisticsMaterializer {
  StatisticsMaterializer(this.reader);

  final StatisticsReader reader;

  Future<StatisticsSummariesMaterial> summaries({
    required PerformanceSummariesReadConnection scope,
    required ProductReadOrigin origin,
    required PerformanceSummariesHeader header,
    required ProductCollectionRef collection,
    StatisticsSummariesMaterial? previous,
  }) async {
    final read = await scope.header();
    if (read.summaries.total != collection.total)
      throw statisticsProtocol(
        'A summary read header disagrees with its original collection.',
      );
    final entries = await _entries(collection, (offset) async {
      final page = await scope.entries(
        offset: offset,
        limit: statisticsPageLimit,
      );
      return (
        collection: page.collection,
        offset: page.offset,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    final identities =
        <PerformanceSummaryIdentityRef, PerformanceSummaryIdentity>{};
    final efforts = <PerformanceEffortIdentityRef, PerformanceEffortIdentity>{};
    final prior = previous;
    if (prior != null) {
      if (prior.origin != origin)
        throw statisticsProtocol(
          'A reused summary material belongs to another authority origin.',
        );
      for (final row in prior.rows ?? const <SummariesRow>[]) {
        identities[row.refs.identity] = row.value.identity;
        final breakdowns = row.value.effortBreakdowns;
        if (breakdowns.length != row.refs.efforts.length)
          throw statisticsProtocol(
            'A reused summary identity reference is incomplete.',
          );
        for (var index = 0; index < breakdowns.length; index++) {
          efforts[row.refs.efforts[index]] = breakdowns[index].identity;
        }
      }
    }
    final values = <PerformanceSummary>[];
    final rows = <SummariesRow>[];
    for (final entry in entries) {
      final entity = await scope.entity(entry);
      if (entity.reference != entry)
        throw statisticsProtocol(
          'A summary entity returned another reference.',
        );
      final material = await reader.summary(
        origin,
        scope,
        entity.value,
        identities: identities,
        efforts: efforts,
      );
      values.add(material.value);
      rows.add(material);
    }
    return StatisticsSummariesMaterial(
      origin: origin,
      reference: header.reference,
      collection: collection,
      header: header,
      values: values,
      rows: rows,
    );
  }

  Future<StatisticsHistoryMaterial> history({
    required PerformanceHistoryReadConnection scope,
    required ProductReadOrigin origin,
    required PerformanceHistoryHeader header,
    required ProductCollectionRef collection,
    StatisticsHistoryMaterial? previous,
  }) async {
    final read = await scope.header();
    if (read.samples.total != collection.total)
      throw statisticsProtocol(
        'A history read header disagrees with its original collection.',
      );
    final entries = await _entries(collection, (offset) async {
      final page = await scope.entries(
        offset: offset,
        limit: statisticsPageLimit,
      );
      return (
        collection: page.collection,
        offset: page.offset,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    final identities =
        <PerformanceSampleIdentityRef, PerformanceSampleIdentity>{};
    final prior = previous;
    if (prior != null) {
      if (prior.origin != origin)
        throw statisticsProtocol(
          'A reused history material belongs to another authority origin.',
        );
      for (final row in prior.rows ?? const <HistoryRow>[])
        identities[row.refs.identity] = row.value.identity;
    }
    final values = <PerformanceSample>[];
    final rows = <HistoryRow>[];
    for (final entry in entries) {
      final entity = await scope.entity(entry);
      if (entity.reference != entry)
        throw statisticsProtocol(
          'A history entity returned another reference.',
        );
      final material = await reader.sample(
        origin,
        entity.value,
        identities: identities,
      );
      values.add(material.value);
      rows.add(material);
    }
    return StatisticsHistoryMaterial(
      origin: origin,
      reference: header.reference,
      collection: collection,
      header: header,
      values: values,
      rows: rows,
    );
  }

  /// Reads the whole original index: continuous offsets, no repeated entry, and
  /// an explicit end only at the captured total.
  Future<List<ProductEntityRef>> _entries(
    ProductCollectionRef collection,
    Future<
      ({
        ProductCollectionRef collection,
        int offset,
        List<ProductEntityRef> items,
        int? nextOffset,
      })
    >
    Function(int offset)
    read,
  ) async {
    final output = <ProductEntityRef>[];
    final seen = <int>{};
    var offset = 0;
    while (offset < collection.total) {
      final page = await read(offset);
      final end = offset + page.items.length;
      if (page.collection != collection ||
          page.offset != offset ||
          page.items.isEmpty ||
          page.items.length > statisticsPageLimit ||
          end < offset ||
          end > collection.total ||
          page.nextOffset != (end == collection.total ? null : end))
        throw statisticsProtocol(
          'A statistics index page does not match its original collection.',
        );
      for (final item in page.items) {
        if (!seen.add(item.entry))
          throw statisticsProtocol('A statistics index repeated an entry.');
        output.add(item);
      }
      offset = end;
    }
    return List.unmodifiable(output);
  }
}
