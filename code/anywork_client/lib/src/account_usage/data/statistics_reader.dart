import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/statistics_state.dart';
import '../domain/statistics_values.dart';
import 'account_read_fields.dart';
import 'statistics_port.dart';
import 'statistics_reads.dart';

/// These associations contain refs only. Identity values are reused from the
/// corresponding canonical/last-known row, never a permanent identity cache.
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

final class StatisticsReader {
  StatisticsReader(this.port, this.lifetime);
  final StatisticsPort port;
  final ResourceLifetime lifetime;
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
      Future<String> text(ReadText value) => readAccountText(value, scope.text);
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
            : await readAccountText(value.effort!, scope.text),
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
      Future<String> text(ReadText value) => readAccountText(value, scope.text);
      Future<String?> optional(ReadText? value) async =>
          value == null ? null : await text(value);
      // Null/LegacyUnknown is historical truth, not a request to resolve today's
      // catalog or to choose a replacement model.
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
          done.completeError(accountDataFailure(error), stack);
        },
      ),
    );
    return done.future;
  }

  Future<SummaryMaterial> summary(
    ProductReadOrigin origin,
    PerformanceSummariesReadConnection scope,
    PerformanceSummaryRead read, {
    PerformanceSummary? previous,
    SummaryIdentityRefs? previousRefs,
  }) async {
    final knownRefs = previousRefs;
    final old = knownRefs?.origin == origin ? previous : null;
    final identity =
        old != null && knownRefs != null && knownRefs.identity == read.identity
        ? old.identity
        : await summaryIdentity(origin, read.identity);
    final efforts = await readAccountList<PerformanceEffortRead>(
      read.effortBreakdowns,
      (offset) async {
        final page = await scope.effortBreakdowns(
          read.effortBreakdowns.listId,
          offset: offset,
          limit: 32,
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
    final oldEfforts =
        <PerformanceEffortIdentityRef, PerformanceEffortIdentity>{};
    if (old != null &&
        knownRefs != null &&
        knownRefs.efforts.length == old.effortBreakdowns.length) {
      for (var index = 0; index < old.effortBreakdowns.length; index++) {
        oldEfforts[knownRefs.efforts[index]] =
            old.effortBreakdowns[index].identity;
      }
    }
    final values = <PerformanceEffort>[];
    for (final effort in efforts) {
      values.add(
        PerformanceEffort(
          identity:
              oldEfforts[effort.identity] ??
              await effortIdentity(origin, effort.identity),
          counters: effort.counters,
        ),
      );
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
        efforts: List<PerformanceEffortIdentityRef>.unmodifiable([
          for (final effort in efforts) effort.identity,
        ]),
      ),
    );
  }

  Future<SampleMaterial> sample(
    ProductReadOrigin origin,
    PerformanceSampleRead read, {
    PerformanceSample? previous,
    SampleIdentityRefs? previousRefs,
  }) async {
    final identity =
        previous != null &&
            previousRefs?.origin == origin &&
            previousRefs!.identity == read.identity
        ? previous.identity
        : await sampleIdentity(origin, read.identity);
    return (
      value: PerformanceSample(identity: identity, counters: read.counters),
      refs: (origin: origin, identity: read.identity),
    );
  }
}

Future<SessionCost?> readSessionCost(
  SessionCostsReadConnection scope,
  String rootThreadId,
) async {
  final read = (await scope.header()).cost;
  if (read == null) return null;
  Future<String> text(ReadText value) => readAccountText(value, scope.text);
  Future<List<RuntimeCost>> amounts(TypedListRef reference) async {
    final values = await readAccountList<RuntimeCostRead>(reference, (
      offset,
    ) async {
      final page = await scope.amounts(
        reference.listId,
        offset: offset,
        limit: 32,
      );
      return (
        listId: page.listId,
        offset: page.offset,
        total: page.total,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    return List.unmodifiable([
      for (final value in values)
        RuntimeCost(currency: await text(value.currency), amount: value.amount),
    ]);
  }

  final root = await text(read.rootThreadId);
  if (root != rootThreadId)
    throw accountDataProtocol(
      'The session cost scope returned another root Thread.',
    );
  final purposes = await readAccountList<PurposeCostRead>(read.purposeCosts, (
    offset,
  ) async {
    final page = await scope.purposes(
      read.purposeCosts.listId,
      offset: offset,
      limit: 32,
    );
    return (
      listId: page.listId,
      offset: page.offset,
      total: page.total,
      items: page.items,
      nextOffset: page.nextOffset,
    );
  });
  return SessionCost(
    rootThreadId: root,
    purposeCosts: List.unmodifiable([
      for (final purpose in purposes)
        PurposeCost(
          purpose: purpose.purpose == null
              ? null
              : await text(purpose.purpose!),
          estimatedCosts: await amounts(purpose.estimatedCosts),
          hasUnpricedUsage: purpose.hasUnpricedUsage,
        ),
    ]),
    estimatedCosts: await amounts(read.estimatedCosts),
    hasUnpricedUsage: read.hasUnpricedUsage,
  );
}
