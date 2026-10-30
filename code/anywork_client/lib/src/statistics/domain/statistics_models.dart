import 'dart:convert';
import 'dart:collection';

import '../../models/collection_equality.dart';
import '../../models/usage_diagnostics.dart';

export '../../models/usage_diagnostics.dart'
    show FirstOutputSource, UsageReportStatus, MetricAvailability;

/// Owns its backing storage. Reusing this value never exposes a caller-owned mutable list.
final class StatisticsMaterial<T> extends UnmodifiableListView<T> {
  StatisticsMaterial(Iterable<T> source) : super(List<T>.unmodifiable(source));

  static StatisticsMaterial<T> freeze<T>(Iterable<T> source) =>
      source is StatisticsMaterial<T> ? source : StatisticsMaterial<T>(source);
}

/// Account-scoped configured model identity. Display names and provider aliases are not keys.
final class AccountModelKey {
  const AccountModelKey({required this.accountId, required this.modelId});

  final String accountId;
  final String? modelId;

  /// Stable tuple encoding; a missing historical model remains distinct from any known model.
  String get encoded => jsonEncode(<Object?>[accountId, modelId]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountModelKey &&
          accountId == other.accountId &&
          modelId == other.modelId;

  @override
  int get hashCode => Object.hash(accountId, modelId);
}

/// Effort subgroup within one account/configured-model aggregate.
///
/// A null effort is not the explicit string `none`; output throughput is the existing weighted
/// `sum(output tokens) * 1000 / sum(total response milliseconds)` measure.
final class StatisticsEffortSummary {
  const StatisticsEffortSummary({
    required this.effort,
    required this.sampleCount,
    required this.completionTokens,
    required this.totalTtftMillis,
    required this.ttftSampleCount,
    required this.totalResponseMillis,
    required this.tokensPerSecond,
    required this.averageTtftMillis,
    required this.averageResponseMillis,
  });

  final String? effort;
  final int sampleCount;
  final int completionTokens;
  final int totalTtftMillis;
  final int ttftSampleCount;
  final int totalResponseMillis;
  final double tokensPerSecond;
  final double? averageTtftMillis;
  final double averageResponseMillis;

  String get effortKey => jsonEncode(<Object?>[effort]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatisticsEffortSummary &&
          effort == other.effort &&
          sampleCount == other.sampleCount &&
          completionTokens == other.completionTokens &&
          totalTtftMillis == other.totalTtftMillis &&
          ttftSampleCount == other.ttftSampleCount &&
          totalResponseMillis == other.totalResponseMillis &&
          tokensPerSecond == other.tokensPerSecond &&
          averageTtftMillis == other.averageTtftMillis &&
          averageResponseMillis == other.averageResponseMillis;

  @override
  int get hashCode => Object.hash(
    effort,
    sampleCount,
    completionTokens,
    totalTtftMillis,
    ttftSampleCount,
    totalResponseMillis,
    tokensPerSecond,
    averageTtftMillis,
    averageResponseMillis,
  );
}

/// One top-level aggregate. Its sole identity is account ID plus configured model ID.
final class StatisticsSummary {
  StatisticsSummary({
    required this.accountId,
    required this.accountDisplayName,
    required this.modelId,
    required this.sampleCount,
    required this.completionTokens,
    required this.totalTtftMillis,
    required this.ttftSampleCount,
    required this.totalResponseMillis,
    required this.tokensPerSecond,
    required this.averageTtftMillis,
    required this.averageResponseMillis,
    Iterable<StatisticsEffortSummary> effortBreakdowns = const [],
  }) : effortBreakdowns = List.unmodifiable(effortBreakdowns);

  final String accountId;
  final String accountDisplayName;
  final String modelId;
  final int sampleCount;
  final int completionTokens;
  final int totalTtftMillis;
  final int ttftSampleCount;
  final int totalResponseMillis;
  final double tokensPerSecond;
  final double? averageTtftMillis;
  final double averageResponseMillis;
  final List<StatisticsEffortSummary> effortBreakdowns;

  late final AccountModelKey identity = AccountModelKey(
    accountId: accountId,
    modelId: modelId,
  );
  late final String filterKey = identity.encoded;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatisticsSummary &&
          accountId == other.accountId &&
          accountDisplayName == other.accountDisplayName &&
          modelId == other.modelId &&
          sampleCount == other.sampleCount &&
          completionTokens == other.completionTokens &&
          totalTtftMillis == other.totalTtftMillis &&
          ttftSampleCount == other.ttftSampleCount &&
          totalResponseMillis == other.totalResponseMillis &&
          tokensPerSecond == other.tokensPerSecond &&
          averageTtftMillis == other.averageTtftMillis &&
          averageResponseMillis == other.averageResponseMillis &&
          listEquals(effortBreakdowns, other.effortBreakdowns);

  @override
  int get hashCode => Object.hash(
    accountId,
    accountDisplayName,
    modelId,
    sampleCount,
    completionTokens,
    totalTtftMillis,
    ttftSampleCount,
    totalResponseMillis,
    tokensPerSecond,
    averageTtftMillis,
    averageResponseMillis,
    Object.hashAll(effortBreakdowns),
  );
}

enum StatisticsModelMatchState {
  matched,
  mismatched,
  unreported,
  legacyUnknown,
}

/// Frozen history diagnostics. Unknown configured model IDs remain null and are never repaired
/// from current catalog contents or sent/reported aliases.
final class StatisticsSample {
  StatisticsSample({
    required this.threadId,
    required this.callId,
    required this.purpose,
    required this.firstOutputSource,
    required this.usageStatus,
    required this.ttftAvailability,
    required this.throughputAvailability,
    required this.completedAt,
    required this.accountId,
    required this.accountDisplayName,
    required this.modelId,
    required this.sentModel,
    required this.reportedModel,
    required this.modelMatchState,
    required this.effort,
    required this.completionTokens,
    required this.ttftMillis,
    required this.decodeMillis,
    required this.totalResponseMillis,
    required this.tokensPerSecond,
  });

  final String threadId;
  final String callId;
  final String? purpose;
  final FirstOutputSource firstOutputSource;
  final UsageReportStatus usageStatus;
  final MetricAvailability ttftAvailability;
  final MetricAvailability throughputAvailability;
  (String, String) get callIdentity => (threadId, callId);
  late final String callKey = jsonEncode(<Object>[threadId, callId]);

  final DateTime completedAt;
  final String accountId;
  final String accountDisplayName;
  final String? modelId;
  final String? sentModel;
  final String? reportedModel;
  final StatisticsModelMatchState modelMatchState;
  final String? effort;
  final int? completionTokens;
  final int? ttftMillis;
  final int? decodeMillis;
  final int? totalResponseMillis;
  final double? tokensPerSecond;

  late final AccountModelKey identity = AccountModelKey(
    accountId: accountId,
    modelId: modelId,
  );
  late final String filterKey = identity.encoded;
  String get displayModel => modelId ?? sentModel ?? '';
  late final String effortKey = jsonEncode(<Object?>[effort]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatisticsSample &&
          threadId == other.threadId &&
          callId == other.callId &&
          purpose == other.purpose &&
          firstOutputSource == other.firstOutputSource &&
          usageStatus == other.usageStatus &&
          ttftAvailability == other.ttftAvailability &&
          throughputAvailability == other.throughputAvailability &&
          completedAt == other.completedAt &&
          accountId == other.accountId &&
          accountDisplayName == other.accountDisplayName &&
          modelId == other.modelId &&
          sentModel == other.sentModel &&
          reportedModel == other.reportedModel &&
          modelMatchState == other.modelMatchState &&
          effort == other.effort &&
          completionTokens == other.completionTokens &&
          ttftMillis == other.ttftMillis &&
          decodeMillis == other.decodeMillis &&
          totalResponseMillis == other.totalResponseMillis &&
          tokensPerSecond == other.tokensPerSecond;

  @override
  int get hashCode => Object.hashAll([
    threadId,
    callId,
    purpose,
    firstOutputSource,
    usageStatus,
    ttftAvailability,
    throughputAvailability,
    completedAt,
    accountId,
    accountDisplayName,
    modelId,
    sentModel,
    reportedModel,
    modelMatchState,
    effort,
    completionTokens,
    ttftMillis,
    decodeMillis,
    totalResponseMillis,
    tokensPerSecond,
  ]);
}

/// Complete, immutable materialized window from one owner publication.
final class StatisticsSnapshot {
  StatisticsSnapshot({
    required this.ownerEpoch,
    required this.feedId,
    required this.publicationRevision,
    required this.summariesRevision,
    required this.historyRevision,
    required Iterable<StatisticsSummary> summaries,
    required Iterable<StatisticsSample> history,
    required this.statisticsPending,
    required this.statisticsGap,
    required this.readFailed,
  }) : summaries = StatisticsMaterial.freeze(summaries),
       history = StatisticsMaterial.freeze(history);

  final String ownerEpoch;
  final String feedId;
  final int publicationRevision;
  final int summariesRevision;
  final int historyRevision;
  final List<StatisticsSummary> summaries;
  final List<StatisticsSample> history;
  final bool statisticsPending;
  final bool statisticsGap;
  final bool readFailed;

  StatisticsSnapshot withPublication(StatisticsFeedIdentity identity) {
    if (identity.ownerEpoch != ownerEpoch ||
        identity.feedId != feedId ||
        identity.summariesRevision != summariesRevision ||
        identity.historyRevision != historyRevision ||
        identity.summaryCount != summaries.length ||
        identity.historyCount != history.length) {
      throw ArgumentError('Publication does not identify the same materials');
    }
    return StatisticsSnapshot(
      ownerEpoch: identity.ownerEpoch,
      feedId: identity.feedId,
      publicationRevision: identity.publicationRevision,
      summariesRevision: identity.summariesRevision,
      historyRevision: identity.historyRevision,
      summaries: summaries,
      history: history,
      statisticsPending: identity.statisticsPending,
      statisticsGap: identity.statisticsGap,
      readFailed: identity.readFailed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatisticsSnapshot &&
          ownerEpoch == other.ownerEpoch &&
          feedId == other.feedId &&
          publicationRevision == other.publicationRevision &&
          summariesRevision == other.summariesRevision &&
          historyRevision == other.historyRevision &&
          listEquals(summaries, other.summaries) &&
          listEquals(history, other.history) &&
          statisticsPending == other.statisticsPending &&
          statisticsGap == other.statisticsGap &&
          readFailed == other.readFailed;

  @override
  int get hashCode => Object.hash(
    ownerEpoch,
    feedId,
    publicationRevision,
    summariesRevision,
    historyRevision,
    Object.hashAll(summaries),
    Object.hashAll(history),
    statisticsPending,
    statisticsGap,
    readFailed,
  );
}

/// Feed identity and material watermarks are independent version domains.
final class StatisticsFeedIdentity {
  const StatisticsFeedIdentity({
    required this.ownerEpoch,
    required this.feedId,
    required this.deliverySequence,
    required this.publicationRevision,
    required this.summariesRevision,
    required this.historyRevision,
    required this.summaryCount,
    required this.historyCount,
    required this.statisticsPending,
    required this.statisticsGap,
    required this.readFailed,
  });

  final String ownerEpoch;
  final String feedId;
  final int deliverySequence;
  final int publicationRevision;
  final int summariesRevision;
  final int historyRevision;
  final int summaryCount;
  final int historyCount;
  final bool statisticsPending;
  final bool statisticsGap;
  final bool readFailed;
}
