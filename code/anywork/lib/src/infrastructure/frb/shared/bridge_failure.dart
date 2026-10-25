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
