import 'package:anywork_client/models.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/studio_l10n.dart';

String usageReportStatusLabel(BuildContext context, UsageReportStatus status) =>
    switch (status) {
      UsageReportStatus.legacyUnknown => context.l10n.usageStatusLegacyUnknown,
      UsageReportStatus.missing => context.l10n.usageStatusMissing,
      UsageReportStatus.partial => context.l10n.usageStatusPartial,
      UsageReportStatus.reported => context.l10n.usageStatusReported,
      UsageReportStatus.invalid => context.l10n.usageStatusInvalid,
    };

String firstOutputSourceLabel(BuildContext context, FirstOutputSource source) =>
    switch (source) {
      FirstOutputSource.unobserved => context.l10n.usageSourceUnobserved,
      FirstOutputSource.incremental => context.l10n.usageSourceIncremental,
      FirstOutputSource.completedToolInput =>
        context.l10n.usageSourceCompletedToolInput,
      FirstOutputSource.legacyUnknown => context.l10n.usageSourceLegacyUnknown,
    };

/// Availability is a canonical typed fact, never reclassified from token or timing values.
String metricAvailabilityLabel(
  BuildContext context,
  MetricAvailability availability,
) => switch (availability) {
  MetricAvailability.available => context.l10n.usageMetricAvailable,
  MetricAvailability.notCollected => context.l10n.usageMetricNotCollected,
  MetricAvailability.noVisibleOutput => context.l10n.usageMetricNoVisibleOutput,
  MetricAvailability.missingOutput => context.l10n.usageMetricMissingOutput,
  MetricAvailability.zeroOutput => context.l10n.usageMetricZeroOutput,
  MetricAvailability.invalidUsage => context.l10n.usageMetricInvalidUsage,
  MetricAvailability.invalidTiming => context.l10n.usageMetricInvalidTiming,
  MetricAvailability.legacyUnknown => context.l10n.usageMetricLegacyUnknown,
};

String usageOutcomeLabel(BuildContext context, UsageTerminalStatus outcome) =>
    switch (outcome) {
      UsageTerminalStatus.succeeded => context.l10n.usageOutcomeSucceeded,
      UsageTerminalStatus.rejected => context.l10n.usageOutcomeRejected,
      UsageTerminalStatus.cancelled => context.l10n.usageOutcomeCancelled,
      UsageTerminalStatus.failed => context.l10n.usageOutcomeFailed,
      UsageTerminalStatus.interrupted => context.l10n.usageOutcomeInterrupted,
    };

String usageCounterLabel(BuildContext context, UsageCounterField field) =>
    switch (field) {
      UsageCounterField.input => context.l10n.usageFieldInput,
      UsageCounterField.output => context.l10n.usageFieldOutput,
      UsageCounterField.cacheRead => context.l10n.usageFieldCacheRead,
      UsageCounterField.cacheWrite => context.l10n.usageFieldCacheWrite,
      UsageCounterField.reasoning => context.l10n.usageFieldReasoning,
      UsageCounterField.total => context.l10n.usageFieldTotal,
      UsageCounterField.inferenceCount => context.l10n.usageFieldInferenceCount,
      UsageCounterField.cachePair => context.l10n.usageFieldCachePair,
      UsageCounterField.throughputPair => context.l10n.usageFieldThroughputPair,
    };

String usageGapReasonLabel(BuildContext context, UsageGapReason reason) =>
    switch (reason) {
      UsageGapReason.unreported => context.l10n.usageGapUnreported,
      UsageGapReason.inconsistent => context.l10n.usageGapInconsistent,
      UsageGapReason.overflow => context.l10n.usageGapOverflow,
    };
