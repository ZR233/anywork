import 'package:anywork_client/resources.dart';

/// Unstructured runtime errors stay private to their resource owner. In
/// particular, arbitrary exception text may contain credentials or answers.
StudioFailure adapterFailure(Object error, {required String operation}) {
  if (error is StudioFailure) return error;
  return StudioFailure(
    code: StudioFailureCode.protocol,
    message: 'The native $operation did not return a usable typed result',
    retryable: false,
    correlationId: 'adapter-$operation',
  );
}

StudioFailure adapterCancelled(String resource) => StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The $resource resource is closing',
  retryable: false,
  correlationId: 'adapter-$resource-cancelled',
);

StudioFailure adapterProtocol(String operation) => StudioFailure(
  code: StudioFailureCode.protocol,
  message: 'The native $operation violated its typed contract',
  retryable: false,
  correlationId: 'adapter-$operation-protocol',
);

FeedCloseIssue adapterCloseIssue(
  StudioFailure failure, {
  required String stage,
  required CleanupRecovery recovery,
}) => FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: stage,
    code: failure.code.name,
    message: failure.message,
    retryable: failure.retryable,
    correlationId: failure.correlationId,
  ),
  recovery: recovery,
);
