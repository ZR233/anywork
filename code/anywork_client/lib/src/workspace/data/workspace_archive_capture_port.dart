import 'package:anywork_client/resources.dart' show CloseReport;

import '../domain/directory_values.dart'
    show ProjectRecord, WorkspaceThreadRecord;
import '../domain/selection.dart' show ArchiveThreadResult, WorkspaceState;

/// Composition-only archive capture; never a domain/UI selection writer.
/// Capture is synchronous and freezes actual owned identities, including
/// retiring, unresolved and pending-open responsibilities. It must not create
/// a Session/draft or later replace captured objects by looking up current IDs.
abstract interface class WorkspaceArchiveCapturePort {
  WorkspaceProjectArchiveCapture captureProject(
    String projectId, {
    required WorkspaceState frozenSelection,
  });

  WorkspaceThreadArchiveCapture captureThread(
    String threadId, {
    required WorkspaceState frozenSelection,
  });
}

/// Runtime responsibility for the original capture, not an immutable value.
/// Unknown outcomes retain this capture and the original operation/evidence.
/// Deadlines bound only the current wait, never the underlying cleanup.
abstract interface class WorkspaceArchiveCapture {
  /// Only for proven non-dispatch/rejection: release preparation/borrows without
  /// clearing UI demands, draft contents or operation-owned attachment refs.
  Future<CloseReport> releaseWithoutArchive({DateTime? deadline});

  /// Join original work or retry its recoverable cleanup; never reopen sources,
  /// repeat archive dispatch or infer a missing business result.
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

abstract interface class WorkspaceProjectArchiveCapture
    implements WorkspaceArchiveCapture {
  /// Confirm the original target and captured owners' Project membership.
  /// Unknown membership or failed preparation must prevent native dispatch.
  Future<void> prepare(ProjectRecord originalProject);

  /// Clean only original captured responsibilities after known native success.
  /// The same confirmation shares its cleanup; a different one is Conflict.
  Future<CloseReport> afterArchived(
    ProjectRecord archivedProject, {
    DateTime? deadline,
  });
}

abstract interface class WorkspaceThreadArchiveCapture
    implements WorkspaceArchiveCapture {
  /// Resolve only original metadata responsibilities, without activating an
  /// execution Session or substituting a later owner with the same Thread ID.
  Future<void> prepare(WorkspaceThreadRecord originalRoot);

  /// Intersect the native complete removed IDs with the original captured set.
  /// Preserve newer UI demand generations, draft edits and operation refs.
  /// The same confirmation shares its cleanup; a different one is Conflict.
  Future<CloseReport> afterArchived(
    ArchiveThreadResult result, {
    DateTime? deadline,
  });
}
