import 'dart:convert';

import '../../models/failure_models.dart';

/// Stable statistics-domain classification independent of transport exception text.
enum StatisticsFailureCategory {
  connection,
  stream,
  closed,
  protocol,
  capacity,
  busy,
  cancelled,
  acknowledgement,
  cleanup,
  resourceBudget,
  unexpected,
}

/// Safe, typed failure state for statistics observation, materialization and cleanup.
///
/// [cause] preserves the original typed failure for a close report without making arbitrary
/// exception text part of the repository's presentation protocol.
final class StatisticsFailure implements Exception {
  const StatisticsFailure({
    required this.category,
    required this.code,
    required this.message,
    required this.retryable,
    this.correlationId,
    this.detailsJson,
    this.cause,
  });

  final StatisticsFailureCategory category;
  final StudioFailureCode code;
  final String message;
  final bool retryable;
  final String? correlationId;
  final String? detailsJson;
  final Object? cause;

  factory StatisticsFailure.fromStudioFailure(
    StudioFailure failure, {
    required StatisticsFailureCategory category,
    Object? cause,
  }) => StatisticsFailure(
    category: category,
    code: failure.code,
    message: failure.message,
    retryable: failure.retryable,
    correlationId: failure.correlationId,
    detailsJson: failure.detailsJson,
    cause: cause ?? failure,
  );

  factory StatisticsFailure.fromObject(
    Object cause, {
    StatisticsFailureCategory category = StatisticsFailureCategory.unexpected,
    StudioFailureCode? code,
    bool? retryable,
    String? message,
  }) {
    if (cause is StatisticsFailure) return cause;
    if (cause is StudioFailure) {
      return StatisticsFailure.fromStudioFailure(cause, category: category);
    }
    return StatisticsFailure.local(
      category: category,
      code: code ?? _defaultCode(category),
      message: message ?? _safeMessage(category),
      retryable: retryable ?? _defaultRetryable(category),
      cause: cause,
    );
  }

  factory StatisticsFailure.local({
    required StatisticsFailureCategory category,
    required StudioFailureCode code,
    required String message,
    required bool retryable,
    String? correlationId,
    Object? details,
    Object? cause,
  }) => StatisticsFailure(
    category: category,
    code: code,
    message: message,
    retryable: retryable,
    correlationId: correlationId ?? _newStatisticsCorrelationId(),
    detailsJson: jsonEncode(<String, Object?>{
      'domain': 'statistics',
      'category': category.name,
      if (details != null) 'details': details,
    }),
    cause: cause,
  );

  factory StatisticsFailure.fromUnknown(
    Object cause, {
    StatisticsFailureCategory category = StatisticsFailureCategory.unexpected,
    bool retryable = true,
  }) => StatisticsFailure.local(
    category: category,
    code: StudioFailureCode.internal,
    message: _safeMessage(category),
    retryable: retryable,
    cause: cause,
  );

  @override
  String toString() =>
      'StatisticsFailure(${category.name}/${code.name}, retryable: $retryable)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatisticsFailure &&
          category == other.category &&
          code == other.code &&
          message == other.message &&
          retryable == other.retryable &&
          correlationId == other.correlationId &&
          detailsJson == other.detailsJson;

  @override
  int get hashCode => Object.hash(
    category,
    code,
    message,
    retryable,
    correlationId,
    detailsJson,
  );
}

int _nextCorrelationSequence = 0;

String _newStatisticsCorrelationId() =>
    'statistics-${DateTime.now().microsecondsSinceEpoch}-${++_nextCorrelationSequence}';

String _safeMessage(StatisticsFailureCategory category) => switch (category) {
  StatisticsFailureCategory.connection => 'Statistics source is unavailable',
  StatisticsFailureCategory.stream => 'Statistics update stream failed',
  StatisticsFailureCategory.closed => 'Statistics feed closed unexpectedly',
  StatisticsFailureCategory.protocol =>
    'Statistics source returned invalid data',
  StatisticsFailureCategory.capacity =>
    'Statistics page exceeds its supported capacity',
  StatisticsFailureCategory.busy => 'Statistics feed is busy',
  StatisticsFailureCategory.cancelled => 'Statistics feed was cancelled',
  StatisticsFailureCategory.acknowledgement =>
    'Statistics delivery acknowledgement failed',
  StatisticsFailureCategory.cleanup =>
    'Statistics resource cleanup is unresolved',
  StatisticsFailureCategory.resourceBudget =>
    'Statistics observer capacity is exhausted',
  StatisticsFailureCategory.unexpected => 'Statistics operation failed',
};

StudioFailureCode _defaultCode(StatisticsFailureCategory category) =>
    switch (category) {
      StatisticsFailureCategory.connection => StudioFailureCode.unavailable,
      StatisticsFailureCategory.stream => StudioFailureCode.unavailable,
      StatisticsFailureCategory.closed => StudioFailureCode.runtimeStopped,
      StatisticsFailureCategory.protocol => StudioFailureCode.protocol,
      StatisticsFailureCategory.capacity => StudioFailureCode.overloaded,
      StatisticsFailureCategory.busy => StudioFailureCode.busy,
      StatisticsFailureCategory.cancelled => StudioFailureCode.cancelled,
      StatisticsFailureCategory.acknowledgement => StudioFailureCode.protocol,
      StatisticsFailureCategory.cleanup => StudioFailureCode.unavailable,
      StatisticsFailureCategory.resourceBudget => StudioFailureCode.overloaded,
      StatisticsFailureCategory.unexpected => StudioFailureCode.internal,
    };

bool _defaultRetryable(StatisticsFailureCategory category) =>
    switch (category) {
      StatisticsFailureCategory.connection ||
      StatisticsFailureCategory.stream ||
      StatisticsFailureCategory.capacity ||
      StatisticsFailureCategory.busy ||
      StatisticsFailureCategory.acknowledgement ||
      StatisticsFailureCategory.cleanup ||
      StatisticsFailureCategory.resourceBudget ||
      StatisticsFailureCategory.unexpected => true,
      StatisticsFailureCategory.closed ||
      StatisticsFailureCategory.protocol ||
      StatisticsFailureCategory.cancelled => false,
    };
