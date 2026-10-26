import '../domain/closing.dart';
import '../domain/failures.dart';
import 'resource_budget.dart';

const resourceCancelled = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The resource owner is sealed.',
  retryable: false,
  correlationId: 'resources',
);

StudioFailure resourceFailure(Object error) => switch (error) {
  StudioFailure() => error,
  ResourceBudgetExceeded() => error.failure,
  _ => const StudioFailure(
    code: StudioFailureCode.internal,
    message: 'The resource operation failed.',
    retryable: false,
    correlationId: 'resources',
  ),
};

StudioFailure resourceProtocol(String message) => StudioFailure(
  code: StudioFailureCode.protocol,
  message: message,
  retryable: false,
  correlationId: 'resources',
);

FeedCloseIssue resourcePendingIssue(String code) => FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'resources',
    code: code,
    message: 'The registered resource work is still in progress.',
    retryable: true,
    correlationId: 'resources',
  ),
  recovery: CleanupRecovery.awaitCompletion,
);

FeedCloseIssue resourceCleanupIssue(Object error, CleanupRecovery recovery) {
  final failure = resourceFailure(error);
  return FeedCloseIssue(
    diagnostic: StudioShutdownIssue(
      stage: 'resources',
      code: failure.code.name,
      message: failure.message,
      retryable: failure.retryable,
      correlationId: failure.correlationId,
    ),
    recovery: recovery,
  );
}
