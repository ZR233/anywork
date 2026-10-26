import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/types/error.dart' as native;
import 'adapter_failure.dart';
import 'exact_numbers.dart';

/// Generated exceptions stop at this boundary. No detailsJson, message parsing
/// or raw exception rendering is used to infer a domain category.
StudioFailure bridgeFailure(Object error) => switch (error) {
  StudioFailure() => error,
  native.BridgeError() => StudioFailure(
    code: _code(error.code),
    message: error.message,
    retryable: error.retryable,
    correlationId: error.correlationId,
    details: error.details == null ? null : _details(error.details!),
  ),
  _ => adapterFailure(error, operation: 'bridge-call'),
};

Future<T> bridgeQuery<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(bridgeFailure(error), stack);
  }
}

StudioFailureCode _code(native.BridgeErrorCode code) => switch (code) {
  native.BridgeErrorCode.notInitialized => StudioFailureCode.notInitialized,
  native.BridgeErrorCode.runtimeStopped => StudioFailureCode.runtimeStopped,
  native.BridgeErrorCode.instanceBusy => StudioFailureCode.instanceBusy,
  native.BridgeErrorCode.invalidArgument => StudioFailureCode.invalidArgument,
  native.BridgeErrorCode.notFound => StudioFailureCode.notFound,
  native.BridgeErrorCode.busy => StudioFailureCode.busy,
  native.BridgeErrorCode.conflict => StudioFailureCode.conflict,
  native.BridgeErrorCode.staleRevision => StudioFailureCode.staleRevision,
  native.BridgeErrorCode.superseded => StudioFailureCode.superseded,
  native.BridgeErrorCode.permissionDenied => StudioFailureCode.permissionDenied,
  native.BridgeErrorCode.cancelled => StudioFailureCode.cancelled,
  native.BridgeErrorCode.cancellationTooLate =>
    StudioFailureCode.cancellationTooLate,
  native.BridgeErrorCode.overloaded => StudioFailureCode.overloaded,
  native.BridgeErrorCode.unavailable => StudioFailureCode.unavailable,
  native.BridgeErrorCode.protocol => StudioFailureCode.protocol,
  native.BridgeErrorCode.storage => StudioFailureCode.storage,
  native.BridgeErrorCode.update => StudioFailureCode.update,
  native.BridgeErrorCode.internal => StudioFailureCode.internal,
};

StudioFailureDetails _details(
  native.BridgeErrorDetails details,
) => switch (details) {
  native.BridgeErrorDetails_Startup(:final step, :final kind) =>
    StudioFailureDetails.startup(
      step: step,
      kind: switch (kind) {
        native.BridgeStartupFailureKind.modeDefinitions =>
          StartupFailureKind.modeDefinitions,
        native.BridgeStartupFailureKind.migration =>
          StartupFailureKind.migration,
        native.BridgeStartupFailureKind.persistentData =>
          StartupFailureKind.persistentData,
        native.BridgeStartupFailureKind.environment =>
          StartupFailureKind.environment,
        native.BridgeStartupFailureKind.cancelled =>
          StartupFailureKind.cancelled,
        native.BridgeStartupFailureKind.internal => StartupFailureKind.internal,
      },
    ),
  native.BridgeErrorDetails_Revision(:final expected, :final actual) =>
    StudioFailureDetails.revision(
      expected: exactU64(expected, 'expected revision'),
      actual: exactU64(actual, 'actual revision'),
    ),
  native.BridgeErrorDetails_SshAuthentication(:final passwordOffered) =>
    StudioFailureDetails.sshAuthentication(passwordOffered: passwordOffered),
  native.BridgeErrorDetails_Reason(:final reason) =>
    StudioFailureDetails.reason(reason: reason),
  native.BridgeErrorDetails_Control(:final reason, :final facts) =>
    StudioFailureDetails.control(reason: reason, facts: _controlFacts(facts)),
  native.BridgeErrorDetails_Identity(:final identity) =>
    StudioFailureDetails.identity(identity: identity),
  native.BridgeErrorDetails_TimelineRevision(
    :final itemId,
    :final field,
    :final revision,
  ) =>
    StudioFailureDetails.timelineRevision(
      itemId: itemId,
      field: field,
      revision: exactU64(revision, 'timeline revision'),
    ),
  native.BridgeErrorDetails_Validation(:final issues) =>
    StudioFailureDetails.validation(
      issues: List.unmodifiable([
        for (final issue in issues)
          ValidationIssue(
            code: issue.code,
            path: issue.path,
            message: issue.message,
          ),
      ]),
    ),
  native.BridgeErrorDetails_Thread(:final threadId) =>
    StudioFailureDetails.thread(threadId: threadId),
  native.BridgeErrorDetails_ResourceLimit(:final resource, :final capacity) =>
    StudioFailureDetails.resourceLimit(
      resource: resource,
      capacity: exactU64(capacity, 'resource capacity'),
    ),
  native.BridgeErrorDetails_Bot(
    :final code,
    :final platformCode,
    :final guidance,
  ) =>
    StudioFailureDetails.bot(
      code: code,
      platformCode: platformCode,
      guidance: guidance,
    ),
  native.BridgeErrorDetails_CatalogRevision(:final revision) =>
    StudioFailureDetails.catalogRevision(
      revision: exactU64(revision, 'catalog revision'),
    ),
};

ControlFailureFacts _controlFacts(
  native.BridgeControlFailureFacts facts,
) => switch (facts) {
  native.BridgeControlFailureFacts_Unspecified() =>
    const ControlFailureFacts.unspecified(),
  native.BridgeControlFailureFacts_ChildThreadAction(
    :final threadId,
    :final action,
    :final parentThreadId,
  ) =>
    ControlFailureFacts.childThreadAction(
      threadId: threadId,
      action: action,
      parentThreadId: parentThreadId,
    ),
  native.BridgeControlFailureFacts_ThreadAction(:final threadId, :final action) =>
    ControlFailureFacts.threadAction(threadId: threadId, action: action),
  native.BridgeControlFailureFacts_ExpectedExecution(
    :final threadId,
    :final expectedExecutionId,
  ) =>
    ControlFailureFacts.expectedExecution(
      threadId: threadId,
      expectedExecutionId: expectedExecutionId,
    ),
  native.BridgeControlFailureFacts_Executing(
    :final threadId,
    :final executionId,
    :final phase,
  ) =>
    ControlFailureFacts.executing(
      threadId: threadId,
      executionId: executionId,
      phase: phase,
    ),
  native.BridgeControlFailureFacts_ExpectedContinuation(
    :final threadId,
    :final expectedContinuationId,
  ) =>
    ControlFailureFacts.expectedContinuation(
      threadId: threadId,
      expectedContinuationId: expectedContinuationId,
    ),
  native.BridgeControlFailureFacts_ContinuationAccepted(
    :final threadId,
    :final operationId,
    :final accepted,
  ) =>
    ControlFailureFacts.continuationAccepted(
      threadId: threadId,
      operationId: operationId,
      accepted: accepted,
    ),
  native.BridgeControlFailureFacts_ContinuationOperation(
    :final threadId,
    :final operationId,
  ) =>
    ControlFailureFacts.continuationOperation(
      threadId: threadId,
      operationId: operationId,
    ),
  native.BridgeControlFailureFacts_ContinuationPointConflict(
    :final threadId,
    :final operationId,
    :final expectedContinuationId,
    :final acceptedContinuationId,
  ) =>
    ControlFailureFacts.continuationPointConflict(
      threadId: threadId,
      operationId: operationId,
      expectedContinuationId: expectedContinuationId,
      acceptedContinuationId: acceptedContinuationId,
    ),
  native.BridgeControlFailureFacts_ContinuationRouteConflict(
    :final threadId,
    :final operationId,
    :final expectedModelRouteRevision,
    :final acceptedModelRouteRevision,
  ) =>
    ControlFailureFacts.continuationRouteConflict(
      threadId: threadId,
      operationId: operationId,
      expectedModelRouteRevision: exactU64(
        expectedModelRouteRevision,
        'expected continuation model route revision',
      ),
      acceptedModelRouteRevision: exactU64(
        acceptedModelRouteRevision,
        'accepted continuation model route revision',
      ),
    ),
  native.BridgeControlFailureFacts_StaleContinuation(
    :final threadId,
    :final expectedContinuationId,
    :final currentContinuationId,
  ) =>
    ControlFailureFacts.staleContinuation(
      threadId: threadId,
      expectedContinuationId: expectedContinuationId,
      currentContinuationId: currentContinuationId,
    ),
  native.BridgeControlFailureFacts_ClaimedContinuation(
    :final threadId,
    :final continuationId,
  ) =>
    ControlFailureFacts.claimedContinuation(
      threadId: threadId,
      continuationId: continuationId,
    ),
  native.BridgeControlFailureFacts_ChildInteraction(
    :final interactionId,
    :final interactionThreadId,
  ) =>
    ControlFailureFacts.childInteraction(
      interactionId: interactionId,
      interactionThreadId: interactionThreadId,
    ),
  native.BridgeControlFailureFacts_InteractionRevision(
    :final interactionId,
    :final expectedRevision,
    :final currentRevision,
  ) =>
    ControlFailureFacts.interactionRevision(
      interactionId: interactionId,
      expectedRevision: exactU64(expectedRevision, 'expected interaction revision'),
      currentRevision: exactU64(currentRevision, 'current interaction revision'),
    ),
  native.BridgeControlFailureFacts_InteractionTerminal(
    :final interactionId,
    :final currentRevision,
  ) =>
    ControlFailureFacts.interactionTerminal(
      interactionId: interactionId,
      currentRevision: exactU64(currentRevision, 'terminal interaction revision'),
    ),
  native.BridgeControlFailureFacts_InteractionOperation(
    :final operationId,
    :final interactionId,
  ) =>
    ControlFailureFacts.interactionOperation(
      operationId: operationId,
      interactionId: interactionId,
    ),
  native.BridgeControlFailureFacts_ChildHost(
    :final hostThreadId,
    :final hostIsChild,
  ) =>
    ControlFailureFacts.childHost(
      hostThreadId: hostThreadId,
      hostIsChild: hostIsChild,
    ),
  native.BridgeControlFailureFacts_InteractionHost(
    :final hostThreadId,
    :final interactionThreadId,
  ) =>
    ControlFailureFacts.interactionHost(
      hostThreadId: hostThreadId,
      interactionThreadId: interactionThreadId,
    ),
  native.BridgeControlFailureFacts_DecisionDurability(
    :final interactionId,
    :final decisionSaved,
  ) =>
    ControlFailureFacts.decisionDurability(
      interactionId: interactionId,
      decisionSaved: decisionSaved,
    ),
  native.BridgeControlFailureFacts_UnreadableDecision(
    :final threadId,
    :final interactionId,
  ) =>
    ControlFailureFacts.unreadableDecision(
      threadId: threadId,
      interactionId: interactionId,
    ),
  native.BridgeControlFailureFacts_DecisionIdentity(
    :final interactionId,
    :final currentRevision,
    :final operationIdentityRecorded,
  ) =>
    ControlFailureFacts.decisionIdentity(
      interactionId: interactionId,
      currentRevision: exactU64(currentRevision, 'decision interaction revision'),
      operationIdentityRecorded: operationIdentityRecorded,
    ),
};
