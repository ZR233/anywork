import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';

/// Read-only Recovery input; never creates another owner or assumes that an
/// unloaded issue page proves absence. Native repeats its actual admission.
final class WorkspaceAccess {
  WorkspaceAccess(this.recovery);
  final ReadonlyLatestValue<RecoveryState> recovery;

  void project(String id) => _check(RecoveryScope.project, id);
  void thread(String id) => _check(RecoveryScope.thread, id);

  void _check(RecoveryScope scope, String id) {
    final state = recovery.value;
    final issues = state.issues;
    final projection = state.projection;
    final source = state.sourceStatus;
    if (projection.sync.phase != ResourceSyncPhase.ready ||
        projection.header?.reference == null ||
        projection.header?.source.brief is! ReadyObservedBrief ||
        source
            is! ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef> ||
        source.current.origin != projection.stamp?.origin ||
        source.current.reference != projection.header?.source.status ||
        source.current.value is! ReadyProductSourceStatus ||
        issues is! CurrentCollectionMirror<RecoveryIssue> ||
        !issues.window.complete ||
        issues.window.loading ||
        issues.window.error != null ||
        issues.window.continuation is! EndCollectionContinuation ||
        issues.window.origin != projection.stamp?.origin ||
        issues.window.entries.length != issues.window.reference.total)
      throw _unknown;
    for (final ref in issues.window.entries) {
      final row = issues.window.rows[ref.entry];
      if (row is! ReadyReadValue<RecoveryIssue, ProductEntityRef> ||
          row.current.origin != issues.window.origin ||
          row.current.reference != ref)
        throw _unknown;
      final issue = row.current.value;
      if (issue.blocksAccess &&
          issue.scope == scope &&
          (scope == RecoveryScope.project
              ? issue.projectId == id
              : issue.threadId == id)) {
        throw StudioFailure(
          code: StudioFailureCode.unavailable,
          message: issue.message,
          retryable: issue.canRetry,
          correlationId: 'workspace-recovery',
          details: StudioFailureDetails.identity(identity: issue.id),
        );
      }
    }
  }

  static const _unknown = StudioFailure(
    code: StudioFailureCode.unavailable,
    message: 'Recovery access for the original Workspace target is not known.',
    retryable: true,
    correlationId: 'workspace',
  );
}
