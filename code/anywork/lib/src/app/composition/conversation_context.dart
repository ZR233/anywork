import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';

import '../../platform/error_log.dart';

/// Cross-domain, read-only context supplied to D1 by the application root.
/// It never substitutes the current selection, activates a Thread, runs recovery
/// or writes either repository. D1 and Rust retain actual execution admission.
final class WorkspaceConversationContext implements ConversationContextPort {
  const WorkspaceConversationContext({required this.workspace, required this.recovery});

  final WorkspaceRepository workspace;
  final RecoveryRepository recovery;

  @override
  ThreadMetadata openThreadMetadata(String threadId) => workspace.thread(threadId);

  @override
  Future<ConversationRecoveryAccess> readRecoveryAccess(WorkspaceThreadRecord thread) async {
    // One bounded page per explicit attempt. Incomplete coverage stays unknown;
    // it is not permission to scan the entire collection or assume no issues.
    try {
      await Future.wait([recovery.loadIssuesPage(), recovery.loadSourceStatus()]);
    } on StudioFailure catch (error) {
      return ConversationRecoveryAccess.unknown(error: error);
    }
    final current = recovery.state.value;
    final projection = current.projection;
    final source = current.sourceStatus;
    final issues = current.issues;
    if (projection.sync.error case final error?) {
      return ConversationRecoveryAccess.unknown(error: error);
    }
    if (source case FailedReadValue(:final error)) {
      return ConversationRecoveryAccess.unknown(error: error);
    }
    if (projection.sync.phase != ResourceSyncPhase.ready ||
        projection.header?.source.brief is! ReadyObservedBrief ||
        source is! ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef> ||
        source.current.origin != projection.stamp?.origin ||
        source.current.reference != projection.header?.source.status ||
        source.current.value is! ReadyProductSourceStatus ||
        issues is! CurrentCollectionMirror<RecoveryIssue>) {
      return const ConversationRecoveryAccess.unknown();
    }
    final window = issues.window;
    if (window.origin != projection.stamp?.origin) {
      return const ConversationRecoveryAccess.unknown();
    }
    if (window.error case final error?) {
      return ConversationRecoveryAccess.unknown(error: error);
    }
    var fullyRead = window.complete && window.continuation is EndCollectionContinuation &&
        window.entries.length == window.reference.total;
    for (final reference in window.entries) {
      final row = window.rows[reference.entry];
      if (row is! ReadyReadValue<RecoveryIssue, ProductEntityRef> ||
          row.current.origin != window.origin || row.current.reference != reference) {
        fullyRead = false;
        continue;
      }
      final issue = row.current.value;
      // Preserve the former _blocksThread admission, not a new application or
      // project-wide blanket prohibition. Native still checks its real Project
      // and workspace resources when it opens this exact frozen Thread.
      if (issue.scope == RecoveryScope.thread && issue.threadId == thread.id && issue.blocksAccess) {
        final failure = StudioFailure(
          code: StudioFailureCode.unavailable,
          message: issue.message,
          retryable: issue.canRetry,
          correlationId: newStudioCorrelationId(),
          details: StudioFailureDetails.identity(identity: issue.id),
        );
        recordDartError(failure, null, stage: 'conversation-recovery-admission',
          correlationId: failure.correlationId);
        return ConversationRecoveryAccess.blocked(error: failure);
      }
    }
    return fullyRead && !window.loading
        ? const ConversationRecoveryAccess.allowed()
        : const ConversationRecoveryAccess.unknown();
  }
}
