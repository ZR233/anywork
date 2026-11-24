import 'package:flutter/foundation.dart';

/// Structured failure metadata decoded from a `turn` or activity outcome.
@immutable
final class TimelineFailureDetails {
  const TimelineFailureDetails({
    this.category,
    this.providerKind,
    this.code,
    this.httpStatus,
    this.message,
    this.retryKind,
    this.retryAfterMs,
    this.durationSeconds,
  });

  final String? category;
  final String? providerKind;
  final String? code;
  final int? httpStatus;
  final String? message;
  final String? retryKind;
  final int? retryAfterMs;
  final int? durationSeconds;

  bool get hasVisibleProviderKind =>
      providerKind != null &&
      providerKind!.isNotEmpty &&
      providerKind != 'unknown';

  bool get isRetryable => retryKind == 'retryable';

  int? get retryAfterSeconds => retryAfterMs == null || retryAfterMs! <= 0
      ? null
      : (retryAfterMs! / 1000).ceil();

  bool get hasTechnicalDetails =>
      (category?.isNotEmpty ?? false) ||
      hasVisibleProviderKind ||
      (code?.isNotEmpty ?? false) ||
      httpStatus != null ||
      (retryKind?.isNotEmpty ?? false) ||
      durationSeconds != null;
}

/// Structured budget-limit metadata decoded from a `budgetLimited` turn outcome.
@immutable
final class TimelineBudgetLimitDetails {
  const TimelineBudgetLimitDetails({
    this.limitKind,
    this.modelSteps,
    this.toolCalls,
    this.waitCalls,
    this.elapsedMs,
    this.rolloverKind,
    this.rolloverError,
    this.durationSeconds,
  });

  final String? limitKind;
  final int? modelSteps;
  final int? toolCalls;
  final int? waitCalls;
  final int? elapsedMs;
  final String? rolloverKind;
  final String? rolloverError;
  final int? durationSeconds;

  int? get effectiveDurationSeconds =>
      durationSeconds ??
      (elapsedMs != null && elapsedMs! >= 0 ? elapsedMs! ~/ 1000 : null);
}

/// Structured cancellation metadata decoded from a `cancelled` or `interrupted` outcome.
@immutable
final class TimelineCancellationDetails {
  const TimelineCancellationDetails({
    this.causeKind,
    this.targetTurnId,
    this.reason,
    this.durationSeconds,
  });

  final String? causeKind;
  final String? targetTurnId;
  final String? reason;
  final int? durationSeconds;
}

/// Tolerant, immutable projection of `turn`, `agent`, `inference`, or `thinking` outcome payloads.
@immutable
final class TimelineOutcomeSummary {
  const TimelineOutcomeSummary({
    this.kind,
    this.failure,
    this.budget,
    this.cancellation,
    this.durationSeconds,
  });

  final String? kind;
  final TimelineFailureDetails? failure;
  final TimelineBudgetLimitDetails? budget;
  final TimelineCancellationDetails? cancellation;
  final int? durationSeconds;

  String? get primaryText =>
      failure?.message ?? cancellation?.reason ?? budget?.rolloverError;

  bool get isTerminalNormal => kind == 'completed' || kind == 'succeeded';

  /// Human-readable single/multi-line summary for tooltips without raw JSON.
  String? get plainDiagnostic {
    if (isTerminalNormal) return null;
    final parts = <String>[];
    final text = primaryText;
    if (text != null && text.isNotEmpty) {
      parts.add(text);
    }
    final tech = <String>[
      if (failure?.code case final code? when code.isNotEmpty) code,
      if (failure?.httpStatus case final status?) 'HTTP $status',
      if (budget?.limitKind case final limit? when limit.isNotEmpty) limit,
      if (cancellation?.causeKind case final cause?
          when cause.isNotEmpty && cause != 'unspecified')
        cause,
    ];
    if (tech.isNotEmpty) {
      parts.add(tech.join(' · '));
    }
    if (parts.isEmpty && kind != null && kind!.isNotEmpty) {
      return kind;
    }
    return parts.isEmpty ? null : parts.join('\n');
  }
}

TimelineOutcomeSummary parseTimelineOutcome(Object? rawOutcome) {
  final outcome = _asMap(rawOutcome);
  if (outcome == null) return const TimelineOutcomeSummary();
  final kind = _nonEmptyString(outcome['kind']);
  final data = _asMap(outcome['data']);
  final durationSeconds = _durationSeconds(
    data?['startedAt'],
    data?['completedAt'],
  );

  if (kind == 'budgetLimited') {
    final limit = _asMap(data?['limit']);
    final usage = _asMap(limit?['usage']);
    final rollover = _asMap(data?['rollover']);
    final rolloverData = _asMap(rollover?['data']);
    final budget = TimelineBudgetLimitDetails(
      limitKind: _nonEmptyString(limit?['kind']),
      modelSteps: _asInt(usage?['modelSteps']),
      toolCalls: _asInt(usage?['toolCalls']),
      waitCalls: _asInt(usage?['waitCalls']),
      elapsedMs: _asInt(usage?['elapsedMs']),
      rolloverKind: _nonEmptyString(rollover?['kind']),
      rolloverError: _nonEmptyString(rolloverData?['error']),
      durationSeconds: durationSeconds,
    );
    return TimelineOutcomeSummary(
      kind: kind,
      budget: budget,
      durationSeconds: budget.effectiveDurationSeconds,
    );
  }

  if (kind == 'cancelled' || kind == 'interrupted') {
    final cause = _asMap(data?['cause']);
    final causeData = _asMap(cause?['data']);
    final reason =
        _nonEmptyString(data?['reason']) ??
        _nonEmptyString(data?['message']) ??
        _nonEmptyString(data?['error']);
    final cancellation = TimelineCancellationDetails(
      causeKind: _nonEmptyString(cause?['kind']),
      targetTurnId: _nonEmptyString(causeData?['targetTurnId']),
      reason: reason,
      durationSeconds: durationSeconds,
    );
    return TimelineOutcomeSummary(
      kind: kind,
      cancellation: cancellation,
      durationSeconds: durationSeconds,
    );
  }

  final nestedFailure = _asMap(data?['failure']);
  if (kind == 'failed' || kind == 'denied' || nestedFailure != null) {
    final retry = _asMap(nestedFailure?['retry']);
    final message =
        _nonEmptyString(nestedFailure?['message']) ??
        _nonEmptyString(data?['message']) ??
        _nonEmptyString(data?['error']) ??
        _nonEmptyString(data?['reason']);
    final failure = TimelineFailureDetails(
      category: _nonEmptyString(nestedFailure?['category']),
      providerKind: _nonEmptyString(nestedFailure?['providerKind']),
      code: _nonEmptyString(nestedFailure?['code']),
      httpStatus: _asInt(nestedFailure?['httpStatus']),
      message: message,
      retryKind: _nonEmptyString(retry?['kind']),
      retryAfterMs: _asInt(retry?['retryAfterMs']),
      durationSeconds: durationSeconds,
    );
    return TimelineOutcomeSummary(
      kind: kind,
      failure: failure,
      durationSeconds: durationSeconds,
    );
  }

  final genericText =
      _nonEmptyString(data?['message']) ??
      _nonEmptyString(data?['error']) ??
      _nonEmptyString(data?['reason']);
  return TimelineOutcomeSummary(
    kind: kind,
    failure: genericText == null
        ? null
        : TimelineFailureDetails(
            message: genericText,
            durationSeconds: durationSeconds,
          ),
    durationSeconds: durationSeconds,
  );
}

Map<String, Object?>? _asMap(Object? value) =>
    value is Map<String, Object?> ? value : null;

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _asInt(Object? value) => value is int ? value : null;

int? _durationSeconds(Object? rawStartedAt, Object? rawCompletedAt) {
  if (rawStartedAt is! int || rawCompletedAt is! int) return null;
  final diff = rawCompletedAt - rawStartedAt;
  return diff < 0 ? null : diff;
}
