import 'package:anywork_client/models.dart';

import '../../rust/api/studio/types/thread_stream.dart' as frb;

UsageReportStatus usageReportStatusFromFrb(frb.BridgeUsageReportStatus value) =>
    switch (value) {
      frb.BridgeUsageReportStatus.legacyUnknown =>
        UsageReportStatus.legacyUnknown,
      frb.BridgeUsageReportStatus.missing => UsageReportStatus.missing,
      frb.BridgeUsageReportStatus.partial => UsageReportStatus.partial,
      frb.BridgeUsageReportStatus.reported => UsageReportStatus.reported,
      frb.BridgeUsageReportStatus.invalid => UsageReportStatus.invalid,
    };

UsageTerminalStatus usageTerminalStatusFromFrb(
  frb.BridgeUsageTerminalStatus value,
) => switch (value) {
  frb.BridgeUsageTerminalStatus.succeeded => UsageTerminalStatus.succeeded,
  frb.BridgeUsageTerminalStatus.rejected => UsageTerminalStatus.rejected,
  frb.BridgeUsageTerminalStatus.cancelled => UsageTerminalStatus.cancelled,
  frb.BridgeUsageTerminalStatus.failed => UsageTerminalStatus.failed,
  frb.BridgeUsageTerminalStatus.interrupted => UsageTerminalStatus.interrupted,
};

UsageCounterField usageCounterFieldFromFrb(frb.BridgeUsageCounterField value) =>
    switch (value) {
      frb.BridgeUsageCounterField.input => UsageCounterField.input,
      frb.BridgeUsageCounterField.output => UsageCounterField.output,
      frb.BridgeUsageCounterField.cacheRead => UsageCounterField.cacheRead,
      frb.BridgeUsageCounterField.cacheWrite => UsageCounterField.cacheWrite,
      frb.BridgeUsageCounterField.reasoning => UsageCounterField.reasoning,
      frb.BridgeUsageCounterField.total => UsageCounterField.total,
      frb.BridgeUsageCounterField.inferenceCount =>
        UsageCounterField.inferenceCount,
      frb.BridgeUsageCounterField.cachePair => UsageCounterField.cachePair,
      frb.BridgeUsageCounterField.throughputPair =>
        UsageCounterField.throughputPair,
    };

UsageGapReason usageGapReasonFromFrb(frb.BridgeUsageGapReason value) =>
    switch (value) {
      frb.BridgeUsageGapReason.unreported => UsageGapReason.unreported,
      frb.BridgeUsageGapReason.inconsistent => UsageGapReason.inconsistent,
      frb.BridgeUsageGapReason.overflow => UsageGapReason.overflow,
    };

MetricAvailability metricAvailabilityFromFrb(
  frb.BridgeMetricAvailability value,
) => switch (value) {
  frb.BridgeMetricAvailability.available => MetricAvailability.available,
  frb.BridgeMetricAvailability.notCollected => MetricAvailability.notCollected,
  frb.BridgeMetricAvailability.noVisibleOutput =>
    MetricAvailability.noVisibleOutput,
  frb.BridgeMetricAvailability.missingOutput =>
    MetricAvailability.missingOutput,
  frb.BridgeMetricAvailability.zeroOutput => MetricAvailability.zeroOutput,
  frb.BridgeMetricAvailability.invalidUsage => MetricAvailability.invalidUsage,
  frb.BridgeMetricAvailability.invalidTiming =>
    MetricAvailability.invalidTiming,
  frb.BridgeMetricAvailability.legacyUnknown =>
    MetricAvailability.legacyUnknown,
};

FirstOutputSource firstOutputSourceFromFrb(frb.BridgeFirstOutputSource value) =>
    switch (value) {
      frb.BridgeFirstOutputSource.unobserved => FirstOutputSource.unobserved,
      frb.BridgeFirstOutputSource.incremental => FirstOutputSource.incremental,
      frb.BridgeFirstOutputSource.completedToolInput =>
        FirstOutputSource.completedToolInput,
      frb.BridgeFirstOutputSource.legacyUnknown =>
        FirstOutputSource.legacyUnknown,
    };

UsageGapIssue usageGapIssueFromFrb(frb.BridgeUsageGapIssue value) =>
    UsageGapIssue(
      field: usageCounterFieldFromFrb(value.field),
      reason: usageGapReasonFromFrb(value.reason),
    );

UsageCallSnapshot usageCallSnapshotFromFrb(frb.BridgeUsageCallSnapshot value) =>
    UsageCallSnapshot(
      threadId: value.threadId,
      callId: value.callId,
      turnId: value.turnId,
      effectSequence: value.effectSequence.toInt(),
      observedAt: value.observedAt.toInt(),
      purpose: value.purpose,
      outcome: usageTerminalStatusFromFrb(value.outcome),
      status: usageReportStatusFromFrb(value.status),
      usage: usageReportFromFrb(value.usage),
      issues: value.issues.map(usageGapIssueFromFrb),
    );

UsageOutcomeCountSnapshot usageOutcomeCountSnapshotFromFrb(
  frb.BridgeUsageOutcomeCountSnapshot value,
) => UsageOutcomeCountSnapshot(
  outcome: usageTerminalStatusFromFrb(value.outcome),
  calls: value.calls.toInt(),
  incompleteCalls: value.incompleteCalls.toInt(),
);

UsagePurposeCountSnapshot usagePurposeCountSnapshotFromFrb(
  frb.BridgeUsagePurposeCountSnapshot value,
) => UsagePurposeCountSnapshot(
  purpose: value.purpose,
  calls: value.calls.toInt(),
  incompleteCalls: value.incompleteCalls.toInt(),
);

UsageIssueCountSnapshot usageIssueCountSnapshotFromFrb(
  frb.BridgeUsageIssueCountSnapshot value,
) => UsageIssueCountSnapshot(
  issue: usageGapIssueFromFrb(value.issue),
  calls: value.calls.toInt(),
);

ThreadUsageDiagnostics threadUsageDiagnosticsFromFrb(
  frb.BridgeThreadUsageDiagnostics value,
) => ThreadUsageDiagnostics(
  incompleteCalls: value.incompleteCalls.toInt(),
  missingCalls: value.missingCalls.toInt(),
  partialCalls: value.partialCalls.toInt(),
  invalidCalls: value.invalidCalls.toInt(),
  overflowCalls: value.overflowCalls.toInt(),
  byOutcome: value.byOutcome.map(usageOutcomeCountSnapshotFromFrb),
  byPurpose: value.byPurpose.map(usagePurposeCountSnapshotFromFrb),
  otherPurposeCalls: value.otherPurposeCalls.toInt(),
  byIssue: value.byIssue.map(usageIssueCountSnapshotFromFrb),
  recentGaps: value.recentGaps.map(usageCallSnapshotFromFrb),
  latestCall: value.latestCall == null
      ? null
      : usageCallSnapshotFromFrb(value.latestCall!),
  legacyUnknown: value.legacyUnknown,
  countsOverflowed: value.countsOverflowed,
);

UsageReport usageReportFromFrb(frb.BridgeUsageReport value) => UsageReport(
  inputTokens: value.inputTokens?.toInt(),
  outputTokens: value.outputTokens?.toInt(),
  cacheReadTokens: value.cacheReadTokens?.toInt(),
  cacheWriteTokens: value.cacheWriteTokens?.toInt(),
  reasoningTokens: value.reasoningTokens?.toInt(),
  totalTokens: value.totalTokens?.toInt(),
);
