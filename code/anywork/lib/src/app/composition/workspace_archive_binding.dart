import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace_ports.dart';

/// Breaks the construction cycle only. Bind once, before exposing Workspace;
/// every archive captures both original domain capabilities synchronously.
final class WorkspaceArchiveBinding implements WorkspaceArchiveCapturePort {
  List<WorkspaceArchiveCapturePort>? _ports;

  void bind({
    required WorkspaceArchiveCapturePort conversations,
    required WorkspaceArchiveCapturePort drafts,
  }) {
    if (_ports != null) {
      throw StateError('Workspace archive capabilities are already bound.');
    }
    _ports = List.unmodifiable([conversations, drafts]);
  }

  List<WorkspaceArchiveCapturePort> get _bound {
    final ports = _ports;
    if (ports == null) {
      throw StateError(
        'Bind all archive capabilities before admitting Workspace actions.',
      );
    }
    return ports;
  }

  @override
  WorkspaceProjectArchiveCapture captureProject(
    String projectId, {
    required WorkspaceState frozenSelection,
  }) => _ProjectCapture(
    _capture(
      _bound,
      (port) =>
          port.captureProject(projectId, frozenSelection: frozenSelection),
    ),
  );

  @override
  WorkspaceThreadArchiveCapture captureThread(
    String threadId, {
    required WorkspaceState frozenSelection,
  }) => _ThreadCapture(
    _capture(
      _bound,
      (port) => port.captureThread(threadId, frozenSelection: frozenSelection),
    ),
  );
}

/// A failed second capture must not discard the first owner's preparation.
/// Keep it in the same returned responsibility; prepare fails before dispatch
/// and Workspace releases every captured leaf through releaseWithoutArchive.
({List<T> leaves, (Object, StackTrace)? failure}) _capture<T>(
  List<WorkspaceArchiveCapturePort> ports,
  T Function(WorkspaceArchiveCapturePort port) capture,
) {
  final leaves = <T>[];
  (Object, StackTrace)? failure;
  for (final port in ports) {
    try {
      leaves.add(capture(port));
    } on Object catch (error, stack) {
      failure ??= (error, stack);
    }
  }
  return (leaves: List.unmodifiable(leaves), failure: failure);
}

abstract class _Capture<T extends WorkspaceArchiveCapture>
    implements WorkspaceArchiveCapture {
  _Capture(({List<T> leaves, (Object, StackTrace)? failure}) captured)
    : leaves = captured.leaves,
      _failure = captured.failure;

  final List<T> leaves;
  final (Object, StackTrace)? _failure;

  Future<void> prepareLeaves(Future<void> Function(T leaf) prepare) async {
    if (_failure case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
    await Future.wait([
      for (final leaf in leaves) Future<void>.sync(() => prepare(leaf)),
    ]);
  }

  Future<CloseReport> join(Future<CloseReport> Function(T leaf) close) async {
    // Start all independent originals even when one leaf throws synchronously;
    // Future.wait joins all of them before forwarding any original failure.
    final reports = await Future.wait([
      for (final leaf in leaves) Future<CloseReport>.sync(() => close(leaf)),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }

  @override
  Future<CloseReport> releaseWithoutArchive({DateTime? deadline}) =>
      join((leaf) => leaf.releaseWithoutArchive(deadline: deadline));

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      join((leaf) => leaf.retryCleanup(deadline: deadline));
}

final class _ProjectCapture extends _Capture<WorkspaceProjectArchiveCapture>
    implements WorkspaceProjectArchiveCapture {
  _ProjectCapture(super.captured);

  @override
  Future<void> prepare(ProjectRecord originalProject) =>
      prepareLeaves((leaf) => leaf.prepare(originalProject));

  @override
  Future<CloseReport> afterArchived(
    ProjectRecord archivedProject, {
    DateTime? deadline,
  }) => join((leaf) => leaf.afterArchived(archivedProject, deadline: deadline));
}

final class _ThreadCapture extends _Capture<WorkspaceThreadArchiveCapture>
    implements WorkspaceThreadArchiveCapture {
  _ThreadCapture(super.captured);

  @override
  Future<void> prepare(WorkspaceThreadRecord originalRoot) =>
      prepareLeaves((leaf) => leaf.prepare(originalRoot));

  @override
  Future<CloseReport> afterArchived(
    ArchiveThreadResult result, {
    DateTime? deadline,
  }) => join((leaf) => leaf.afterArchived(result, deadline: deadline));
}
