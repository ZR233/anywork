import 'collection_equality.dart';

enum UsageReportStatus { legacyUnknown, missing, partial, reported, invalid }

enum UsageTerminalStatus { succeeded, rejected, cancelled, failed, interrupted }

enum UsageCounterField {
  input,
  output,
  cacheRead,
  cacheWrite,
  reasoning,
  total,
  inferenceCount,
  cachePair,
  throughputPair,
}

enum UsageGapReason { unreported, inconsistent, overflow }

enum MetricAvailability {
  available,
  notCollected,
  noVisibleOutput,
  missingOutput,
  zeroOutput,
  invalidUsage,
  invalidTiming,
  legacyUnknown,
}

enum FirstOutputSource {
  unobserved,
  incremental,
  completedToolInput,
  legacyUnknown,
}

final class UsageGapIssue {
  const UsageGapIssue({required this.field, required this.reason});

  final UsageCounterField field;
  final UsageGapReason reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageGapIssue && field == other.field && reason == other.reason;

  @override
  int get hashCode => Object.hashAll([field, reason]);
}

final class UsageCallSnapshot {
  UsageCallSnapshot({
    required this.threadId,
    required this.callId,
    required this.turnId,
    required this.effectSequence,
    required this.observedAt,
    required this.purpose,
    required this.outcome,
    required this.status,
    required this.usage,
    Iterable<UsageGapIssue> issues = const [],
  }) : issues = List.unmodifiable(issues);

  final String threadId;
  final String callId;
  final String? turnId;
  final int effectSequence;
  final int observedAt;
  final String? purpose;
  final UsageTerminalStatus outcome;
  final UsageReportStatus status;
  final UsageReport usage;
  final List<UsageGapIssue> issues;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageCallSnapshot &&
          threadId == other.threadId &&
          callId == other.callId &&
          turnId == other.turnId &&
          effectSequence == other.effectSequence &&
          observedAt == other.observedAt &&
          purpose == other.purpose &&
          outcome == other.outcome &&
          status == other.status &&
          usage == other.usage &&
          listEquals(issues, other.issues);

  @override
  int get hashCode => Object.hashAll([
    threadId,
    callId,
    turnId,
    effectSequence,
    observedAt,
    purpose,
    outcome,
    status,
    usage,
    Object.hashAll(issues),
  ]);
}

final class UsageOutcomeCountSnapshot {
  const UsageOutcomeCountSnapshot({
    required this.outcome,
    required this.calls,
    required this.incompleteCalls,
  });

  final UsageTerminalStatus outcome;
  final int calls;
  final int incompleteCalls;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageOutcomeCountSnapshot &&
          outcome == other.outcome &&
          calls == other.calls &&
          incompleteCalls == other.incompleteCalls;

  @override
  int get hashCode => Object.hashAll([outcome, calls, incompleteCalls]);
}

final class UsagePurposeCountSnapshot {
  const UsagePurposeCountSnapshot({
    required this.purpose,
    required this.calls,
    required this.incompleteCalls,
  });

  final String? purpose;
  final int calls;
  final int incompleteCalls;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsagePurposeCountSnapshot &&
          purpose == other.purpose &&
          calls == other.calls &&
          incompleteCalls == other.incompleteCalls;

  @override
  int get hashCode => Object.hashAll([purpose, calls, incompleteCalls]);
}

final class UsageIssueCountSnapshot {
  const UsageIssueCountSnapshot({required this.issue, required this.calls});

  final UsageGapIssue issue;
  final int calls;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageIssueCountSnapshot &&
          issue == other.issue &&
          calls == other.calls;

  @override
  int get hashCode => Object.hashAll([issue, calls]);
}

final class ThreadUsageDiagnostics {
  ThreadUsageDiagnostics({
    required this.incompleteCalls,
    required this.missingCalls,
    required this.partialCalls,
    required this.invalidCalls,
    required this.overflowCalls,
    Iterable<UsageOutcomeCountSnapshot> byOutcome = const [],
    Iterable<UsagePurposeCountSnapshot> byPurpose = const [],
    required this.otherPurposeCalls,
    Iterable<UsageIssueCountSnapshot> byIssue = const [],
    Iterable<UsageCallSnapshot> recentGaps = const [],
    required this.latestCall,
    required this.legacyUnknown,
    required this.countsOverflowed,
  }) : byOutcome = List.unmodifiable(byOutcome),
       byPurpose = List.unmodifiable(byPurpose),
       byIssue = List.unmodifiable(byIssue),
       recentGaps = List.unmodifiable(recentGaps);

  const ThreadUsageDiagnostics.empty()
    : incompleteCalls = 0,
      missingCalls = 0,
      partialCalls = 0,
      invalidCalls = 0,
      overflowCalls = 0,
      byOutcome = const [],
      byPurpose = const [],
      otherPurposeCalls = 0,
      byIssue = const [],
      recentGaps = const [],
      latestCall = null,
      legacyUnknown = false,
      countsOverflowed = false;

  final int incompleteCalls;
  final int missingCalls;
  final int partialCalls;
  final int invalidCalls;
  final int overflowCalls;
  final List<UsageOutcomeCountSnapshot> byOutcome;
  final List<UsagePurposeCountSnapshot> byPurpose;
  final int otherPurposeCalls;
  final List<UsageIssueCountSnapshot> byIssue;
  final List<UsageCallSnapshot> recentGaps;
  final UsageCallSnapshot? latestCall;
  final bool legacyUnknown;
  final bool countsOverflowed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThreadUsageDiagnostics &&
          incompleteCalls == other.incompleteCalls &&
          missingCalls == other.missingCalls &&
          partialCalls == other.partialCalls &&
          invalidCalls == other.invalidCalls &&
          overflowCalls == other.overflowCalls &&
          listEquals(byOutcome, other.byOutcome) &&
          listEquals(byPurpose, other.byPurpose) &&
          otherPurposeCalls == other.otherPurposeCalls &&
          listEquals(byIssue, other.byIssue) &&
          listEquals(recentGaps, other.recentGaps) &&
          latestCall == other.latestCall &&
          legacyUnknown == other.legacyUnknown &&
          countsOverflowed == other.countsOverflowed;

  @override
  int get hashCode => Object.hashAll([
    incompleteCalls,
    missingCalls,
    partialCalls,
    invalidCalls,
    overflowCalls,
    Object.hashAll(byOutcome),
    Object.hashAll(byPurpose),
    otherPurposeCalls,
    Object.hashAll(byIssue),
    Object.hashAll(recentGaps),
    latestCall,
    legacyUnknown,
    countsOverflowed,
  ]);
}

final class UsageReport {
  const UsageReport({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.reasoningTokens,
    required this.totalTokens,
  });

  final int? inputTokens;
  final int? outputTokens;
  final int? cacheReadTokens;
  final int? cacheWriteTokens;
  final int? reasoningTokens;
  final int? totalTokens;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageReport &&
          inputTokens == other.inputTokens &&
          outputTokens == other.outputTokens &&
          cacheReadTokens == other.cacheReadTokens &&
          cacheWriteTokens == other.cacheWriteTokens &&
          reasoningTokens == other.reasoningTokens &&
          totalTokens == other.totalTokens;

  @override
  int get hashCode => Object.hashAll([
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheWriteTokens,
    reasoningTokens,
    totalTokens,
  ]);
}
