import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_state.dart';
import '../domain/directory_values.dart';
import '../domain/workspace_repository.dart';
import 'agent_directory_mirror.dart';
import 'agent_directory_reads.dart';
import 'directory_collection.dart';
import 'directory_read_pins.dart';
import 'project_directory_mirror.dart';
import 'project_directory_reads.dart';
import 'thread_directory_owner.dart';
import 'workspace_port.dart';
import 'workspace_directory_capture.dart';

/// Workspace's directory resources only. Selection/commands compose this owner;
/// metadata and queries never construct a Conversation Session or ensure work.
final class WorkspaceDirectories {
  WorkspaceDirectories(this.port, ResourceBudget budget, this.operations) : lifetime = ResourceLifetime(budget) {
    projects = ProjectDirectoryMirror(port, lifetime);
    agents = AgentDirectoryMirror(port, lifetime);
    final pins = DirectoryReadPins(port, lifetime);
    projects.adopted = pins.projectAdopted;
    agents.adopted = pins.agentAdopted;
    projectReads = ProjectDirectoryReads(projects, pins, lifetime);
    agentReads = AgentDirectoryReads(agents, pins, lifetime);
  }
  final WorkspacePort port;
  final OperationRecorder operations;
  final ResourceLifetime lifetime;
  late final ProjectDirectoryMirror projects;
  late final AgentDirectoryMirror agents;
  late final ProjectDirectoryReads projectReads;
  late final AgentDirectoryReads agentReads;
  final Set<WorkspaceThreadDirectory> _threads = Set.identity();
  bool _publishersClosed = false;

  /// An explicit source demand, never called by the cold Repository factory.
  /// Independent feed admission failures remain observable and owned.
  void start() { projects.start(); agents.start(); }

  WorkspaceThreadDirectory openScope(ThreadDirectoryScope scope) {
    lifetime.admit();
    final owner = WorkspaceThreadDirectory(port: port, budget: lifetime.budget, operations: operations, scope: scope);
    _threads.add(owner);
    owner.released = () => _threads.remove(owner);
    return owner;
  }

  ThreadDirectoryQuery query(DirectoryQuery query) => openScope(ThreadDirectoryScope.query(query: query)).asQuery(query);
  ThreadMetadata metadata(String id) => openScope(ThreadDirectoryScope.thread(threadId: id)).asMetadata(id);

  WorkspaceDirectoryCapture captureOwned() => WorkspaceDirectoryCapture(List.of(_threads), lifetime.nextAttempt());

  Future<ProjectRecord> readProject(String id) => projectReads.lookup(id).then((value) => value.value);

  Future<T> withThread<T>(String id, Future<T> Function(WorkspaceThreadDirectory, WorkspaceThreadRecord) action) {
    lifetime.admit();
    final owner = openScope(ThreadDirectoryScope.thread(threadId: id));
    return lifetime.run('workspace-thread-command-scope', () async {
      try { return await action(owner, (await owner.reads.lookup(id)).value); }
      finally { await owner.close(); }
    });
  }

  Future<WorkspaceThreadRecord> readThread(String id) {
    lifetime.admit();
    final owner = openScope(ThreadDirectoryScope.thread(threadId: id));
    return lifetime.run('workspace-read-thread', () async {
      try { return (await owner.reads.lookup(id)).value; }
      finally {
        final report = await owner.close();
        if (report.complete) _threads.remove(owner);
      }
    });
  }

  /// Native query ordering, not Sidebar/search/pin cache or Dart updatedAt sort.
  Future<WorkspaceThreadRecord?> firstRoot(String projectId) {
    lifetime.admit();
    final query = DirectoryQuery(projectId: projectId, search: null, archived: false, filter: DirectoryFilter.all);
    final owner = openScope(ThreadDirectoryScope.query(query: query, includePinned: false));
    return lifetime.run('workspace-first-root', () async {
      try {
        await owner.pages.load(limit: 1);
        final binding = owner.mirror.current;
        final visible = owner.mirror.source.value.threads;
        if (binding == null || visible is! CurrentCollectionMirror<WorkspaceThreadRecord> ||
            visible.window.origin != binding.origin || visible.window.reference != binding.collection) {
          throw const StudioFailure(code: StudioFailureCode.superseded, message: 'The original default-root query moved.',
            retryable: true, correlationId: 'workspace');
        }
        if (visible.window.reference.total == 0) return null;
        if (visible.window.entries.isEmpty) throw resourceProtocol('The nonempty root query returned no first member.');
        final ref = visible.window.entries.first;
        final row = visible.window.rows[ref.entry];
        if (row is! ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef> || row.current.reference != ref ||
            row.current.origin != binding.origin) throw directoryRootUnavailable;
        return row.current.value;
      } finally {
        final report = await owner.close();
        if (report.complete) _threads.remove(owner);
      }
    });
  }

  /// None from the exact full Project scope is authoritative absence, unlike a
  /// missing Sidebar row or an unavailable source. No body/error-code guessing.
  Future<bool> projectExists(String id) => lifetime.run('workspace-project-membership', () async {
    final binding = await projects.ready(projects.capture());
    final ref = await projectReads.use(binding, (scope) => scope.lookupProject(id));
    projects.check(binding, exact: true);
    if (ref != null && (ref.entry < 0 || ref.revision < 0)) throw resourceProtocol('Project lookup returned an invalid ref.');
    return ref != null;
  });

  Future<ProjectRecord?> firstProjectAfterRemoval(String removedId) => lifetime.run('workspace-project-successor', () async {
    while (true) {
      final binding = await projects.ready(projects.capture());
      final ref = await projectReads.use(binding, (scope) => scope.lookupProject(removedId));
      projects.check(binding, exact: true);
      if (ref != null) {
        if (ref.entry < 0 || ref.revision < 0) throw resourceProtocol('Project lookup returned an invalid ref.');
        await projects.source.waitFor((state) {
          lifetime.admit();
          if (state.projection.sync.phase == ResourceSyncPhase.failed) throw state.projection.sync.error!;
          final now = projects.current;
          return now != null && (now.origin != binding.origin || now.generation != binding.generation ||
            now.header.reference != binding.header.reference || now.collection != binding.collection);
        });
        continue;
      }
      CollectionWindow<ProjectRecord>? complete;
      while (complete == null) {
        projects.check(binding, exact: true);
        await projectReads.page();
        projects.check(binding, exact: true);
        final value = projects.source.value.projects;
        if (value is CurrentCollectionMirror<ProjectRecord> && value.window.origin == binding.origin &&
            value.window.reference == binding.collection && value.window.complete) complete = value.window;
      }
      ProjectRecord? first;
      for (final entry in complete.entries) {
        final row = complete.rows[entry.entry];
        if (row is! ReadyReadValue<ProjectRecord, ProductEntityRef> || row.current.reference != entry ||
            row.current.origin != binding.origin) throw directoryRootUnavailable;
        final project = row.current.value;
        if (project.id == removedId) throw resourceProtocol('The full Project scope contradicted its absence lookup.');
        if (first == null || project.id.compareTo(first.id) < 0) first = project;
      }
      projects.check(binding, exact: true);
      return first;
    }
  });

  void seal() {
    lifetime.seal();
    for (final owner in List.of(_threads)) { owner.requestClose(); }
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    seal();
    final owners = List.of(_threads);
    final reports = await Future.wait([
      _closeReport(() => lifetime.close(deadline: deadline, retry: retry)),
      for (final owner in owners) _closeReport(() => owner.close(deadline: deadline, retry: retry)),
    ]);
    for (var index = 0; index < owners.length; index++) {
      if (reports[index + 1].complete) _threads.remove(owners[index]);
    }
    final report = CloseReport(unresolved: [for (final value in reports) ...value.unresolved]);
    if (report.complete && !_publishersClosed) {
      projects.source.close(); agents.source.close(); _publishersClosed = true;
    }
    return report;
  }

  Future<CloseReport> _closeReport(Future<CloseReport> Function() close) async {
    try { return await close(); }
    catch (error, stack) {
      lifetime.lastCause = error; lifetime.lastStack = stack;
      return CloseReport(unresolved: [UnresolvedResource(owner: 'workspace-directory-cleanup',
        attemptId: AttemptId(lifetime.nextAttempt()), issues: [resourceCleanupIssue(error, CleanupRecovery.retryClose)])]);
    }
  }

  static const directoryRootUnavailable = StudioFailure(code: StudioFailureCode.unavailable,
    message: 'The first native root has not been materialized.', retryable: true, correlationId: 'workspace');
}
