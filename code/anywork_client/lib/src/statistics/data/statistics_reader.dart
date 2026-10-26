import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/statistics_values.dart';
import 'statistics_port.dart';
import 'statistics_read_fields.dart';
import 'statistics_reads.dart';

/// Identity references of one materialized row. They are reuse hints for a
/// later material of the same origin, never a permanent identity cache.
typedef SummaryIdentityRefs = ({
  ProductReadOrigin origin,
  PerformanceSummaryIdentityRef identity,
  List<PerformanceEffortIdentityRef> efforts,
});
typedef SampleIdentityRefs = ({
  ProductReadOrigin origin,
  PerformanceSampleIdentityRef identity,
});
typedef SummaryMaterial = ({
  PerformanceSummary value,
  SummaryIdentityRefs refs,
});
typedef SampleMaterial = ({PerformanceSample value, SampleIdentityRefs refs});

/// Materializes one statistics entity inside its original pinned read scope.
/// It owns no resource: the caller's attempt lifetime owns every identity pin.
final class StatisticsReader {
  StatisticsReader(this.port, this.lifetime);

  final StatisticsPort port;
  final ResourceLifetime lifetime;

  Future<SummaryMaterial> summary(
    ProductReadOrigin origin,
    PerformanceSummariesReadConnection scope,
    PerformanceSummaryRead read, {
    Map<PerformanceSummaryIdentityRef, PerformanceSummaryIdentity> identities =
        const {},
    Map<PerformanceEffortIdentityRef, PerformanceEffortIdentity> efforts =
        const {},
  }) async {
    final identity =
        identities[read.identity] ??
        await summaryIdentity(origin, read.identity);
    final effortReads = await readStatisticsList<PerformanceEffortRead>(
      read.effortBreakdowns,
      (offset) async {
        final page = await scope.effortBreakdowns(
          read.effortBreakdowns.listId,
          offset: offset,
          limit: statisticsPageLimit,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    final values = <PerformanceEffort>[];
    final refs = <PerformanceEffortIdentityRef>[];
    for (final effort in effortReads) {
      values.add(
        PerformanceEffort(
          identity:
              efforts[effort.identity] ??
              await effortIdentity(origin, effort.identity),
          counters: effort.counters,
        ),
      );
      refs.add(effort.identity);
    }
    return (
      value: PerformanceSummary(
        identity: identity,
        counters: read.counters,
        effortBreakdowns: List.unmodifiable(values),
      ),
      refs: (
        origin: origin,
        identity: read.identity,
        efforts: List<PerformanceEffortIdentityRef>.unmodifiable(refs),
      ),
    );
  }

  Future<SampleMaterial> sample(
    ProductReadOrigin origin,
    PerformanceSampleRead read, {
    Map<PerformanceSampleIdentityRef, PerformanceSampleIdentity> identities =
        const {},
  }) async {
    final identity =
        identities[read.identity] ??
        await sampleIdentity(origin, read.identity);
    return (
      value: PerformanceSample(identity: identity, counters: read.counters),
      refs: (origin: origin, identity: read.identity),
    );
  }

  Future<PerformanceSummaryIdentity> summaryIdentity(
    ProductReadOrigin origin,
    PerformanceSummaryIdentityRef reference,
  ) => _identity(
    _summaries,
    (origin: origin, reference: reference),
    () => PinnedReadOwner<PerformanceSummaryIdentityReadConnection>(
      lifetime: lifetime,
      owner: 'statistics:summary-identity',
      open: () => port.openSummaryIdentity(reference, origin: origin),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    ),
    (scope) async {
      final value = await scope.header();
      Future<String> text(ReadText value) =>
          readStatisticsText(value, scope.text);
      return PerformanceSummaryIdentity(
        accountId: await text(value.accountId),
        accountDisplayName: await text(value.accountDisplayName),
        modelId: await text(value.modelId),
      );
    },
  );

  Future<PerformanceEffortIdentity> effortIdentity(
    ProductReadOrigin origin,
    PerformanceEffortIdentityRef reference,
  ) => _identity(
    _efforts,
    (origin: origin, reference: reference),
    () => PinnedReadOwner<PerformanceEffortIdentityReadConnection>(
      lifetime: lifetime,
      owner: 'statistics:effort-identity',
      open: () => port.openEffortIdentity(reference, origin: origin),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    ),
    (scope) async {
      final value = await scope.header();
      return PerformanceEffortIdentity(
        effort: value.effort == null
            ? null
            : await readStatisticsText(value.effort!, scope.text),
      );
    },
  );

  Future<PerformanceSampleIdentity> sampleIdentity(
    ProductReadOrigin origin,
    PerformanceSampleIdentityRef reference,
  ) => _identity(
    _samples,
    (origin: origin, reference: reference),
    () => PinnedReadOwner<PerformanceSampleIdentityReadConnection>(
      lifetime: lifetime,
      owner: 'statistics:sample-identity',
      open: () => port.openSampleIdentity(reference, origin: origin),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    ),
    (scope) async {
      final value = await scope.header();
      Future<String> text(ReadText value) =>
          readStatisticsText(value, scope.text);
      Future<String?> optional(ReadText? value) async =>
          value == null ? null : await text(value);
      // Null/legacyUnknown is historical truth, not a request to resolve the
      // current catalog or to choose a replacement model.
      return PerformanceSampleIdentity(
        accountId: await text(value.accountId),
        accountDisplayName: await text(value.accountDisplayName),
        modelId: await optional(value.modelId),
        sentModel: await optional(value.sentModel),
        reportedModel: await optional(value.reportedModel),
        modelMatchState: value.modelMatchState,
        effort: await optional(value.effort),
      );
    },
  );

  final Map<
    ({ProductReadOrigin origin, PerformanceSummaryIdentityRef reference}),
    Future<PerformanceSummaryIdentity>
  >
  _summaries = {};
  final Map<
    ({ProductReadOrigin origin, PerformanceEffortIdentityRef reference}),
    Future<PerformanceEffortIdentity>
  >
  _efforts = {};
  final Map<
    ({ProductReadOrigin origin, PerformanceSampleIdentityRef reference}),
    Future<PerformanceSampleIdentity>
  >
  _samples = {};

  Future<V> _identity<K, C, V>(
    Map<K, Future<V>> pending,
    K key,
    PinnedReadOwner<C> Function() open,
    Future<V> Function(C) read,
  ) {
    lifetime.admit();
    final existing = pending[key];
    if (existing != null) return existing;
    final done = Completer<V>();
    pending[key] = done.future;
    unawaited(
      Future<V>.sync(() async {
        final pin = open();
        try {
          return await pin.use(read);
        } finally {
          pin.retire();
        }
      }).then(
        (value) {
          unawaited(pending.remove(key));
          done.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          unawaited(pending.remove(key));
          done.completeError(statisticsFailure(error), stack);
        },
      ),
    );
    return done.future;
  }
}
