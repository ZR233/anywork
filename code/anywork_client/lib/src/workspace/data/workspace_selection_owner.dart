import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_values.dart';
import '../domain/directory_state.dart';
import '../domain/selection.dart';
import 'workspace_access.dart';
import 'workspace_commands.dart';
import 'workspace_directories.dart';
import 'workspace_open.dart';
import 'workspace_selection_port.dart';
import 'thread_directory_owner.dart';

/// The sole selection publisher, including D1's post-creation adoption.
final class WorkspaceSelectionOwner implements WorkspaceSubmissionSelection {
  WorkspaceSelectionOwner(this.directories, this.commands, this.access)
      : source = ResourceSource(const WorkspaceState(selection: WorkspaceSelection(
          projectId: null, threadId: null, needsOpen: false), selectionGeneration: 0, sealed: false),
          directories.lifetime.budget, 'workspace-selection') {
    directories.lifetime.onSeal(() {
      source.publish(source.value.copyWith(sealed: true)); source.seal();
    });
    _projectsObservation = directories.projects.source.watch((_) => _checkProject());
    directories.projects.removed = (origin, ids) {
      final frozen = source.value;
      if (ids.contains(frozen.selection.projectId) && directories.projects.source.value.projection.stamp?.origin == origin) {
        _ordinaryRemoval(frozen, project: true);
      }
    };
    directories.lifetime.onSeal(() { _projectsObservation.cancel(); _threadObservation?.cancel(); });
  }
  final WorkspaceDirectories directories;
  final WorkspaceCommands commands;
  final WorkspaceAccess access;
  final ResourceSource<WorkspaceState> source;
  late final WorkspaceOpen opening = WorkspaceOpen(directories, this, commands);
  final Set<WorkspaceIntentStamp> _pending = Set.identity();
  ({String projectId, String threadId, String rootId})? _root;
  ({String projectId, int generation})? _submission;
  bool _publisherClosed = false;
  late final Observation _projectsObservation;
  Observation? _threadObservation;
  WorkspaceThreadDirectory? _selectedRead;
  WorkspaceState? _selectedReadState;
  String? _projectSeen;
  ({int intent, int generation, String id, ProductReadOrigin? origin, ProjectDirectoryReadRef? reference})? _projectKey;
  ({WorkspaceState frozen, bool project, Future<void> work})? _removal;

  String? selectedRootFor(WorkspaceState frozen) => frozen.selection.projectId == _root?.projectId &&
    frozen.selection.threadId == _root?.threadId ? _root?.rootId : null;

  bool _sameSelection(WorkspaceState frozen) => !directories.lifetime.sealed &&
    source.value.selectionGeneration == frozen.selectionGeneration && source.value.selection == frozen.selection;

  bool _sameProject(WorkspaceState frozen, String id) => !directories.lifetime.sealed &&
    source.value.selectionGeneration == frozen.selectionGeneration && source.value.selection.projectId == id;

  void _retire(WorkspaceThreadDirectory owner) {
    if (directories.lifetime.sealed) { owner.requestClose(); return; }
    directories.lifetime.run('workspace-selection-read-retire', () async {
      // Publish the new selection before cancellation can synchronously reenter.
      await Future<void>.value(); await owner.close();
    }).then<void>((_) {}, onError: (Object error, StackTrace stack) {
      directories.lifetime.lastCause = error; directories.lifetime.lastStack = stack;
    });
  }

  void _bindSelected(WorkspaceState frozen) {
    if (_selectedReadState?.selection.projectId != frozen.selection.projectId) { _projectSeen = null; _projectKey = null; }
    final old = _selectedRead;
    final id = frozen.selection.threadId;
    final existing = old?.mirror.scope;
    final next = id == null ? null : existing is SingleThreadDirectoryScope && existing.threadId == id &&
      old != null && !old.lifetime.sealed && _selectedReadState == frozen ? old :
      directories.openScope(ThreadDirectoryScope.thread(threadId: id));
    Observation? observation;
    try {
      if (next != null) observation = next.mirror.source.watch((_) => _checkThread(next, frozen));
    } catch (_) { if (next != null && !identical(next, old)) _retire(next); rethrow; }
    _threadObservation?.cancel(); _threadObservation = observation; _selectedRead = next; _selectedReadState = frozen;
    if (next != null) next.mirror.removed = (origin, entries) {
      if (entries.isNotEmpty && next.mirror.source.value.projection.stamp?.origin == origin &&
          identical(_selectedRead, next) && _sameSelection(frozen) && !commands.holdsRemoval(frozen)) {
        _ordinaryRemoval(frozen, project: false);
      }
    };
    if (old != null && !identical(old, next)) _retire(old);
  }

  void _checkThread(WorkspaceThreadDirectory owner, WorkspaceState frozen) {
    if (!identical(_selectedRead, owner) || !_sameSelection(frozen) || commands.holdsRemoval(frozen)) return;
    final state = owner.mirror.source.value;
    final value = state.threads;
    if (state.projection.sync.phase != ResourceSyncPhase.ready || value is! CurrentCollectionMirror<WorkspaceThreadRecord> ||
        value.window.origin != state.projection.stamp?.origin) return;
    for (final row in value.window.rows.values) {
      if (row is ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef> && row.current.origin == value.window.origin &&
          row.current.value.id == frozen.selection.threadId && row.current.value.archived) {
        _ordinaryRemoval(frozen, project: false); return;
      }
    }
  }

  void _checkProject() {
    final frozen = source.value;
    final id = frozen.selection.projectId;
    if (directories.lifetime.sealed || id == null || commands.holdsRemoval(frozen)) return;
    final binding = directories.projects.current;
    if (binding == null && directories.projects.source.value.projection.sync.phase != ResourceSyncPhase.idle) return;
    final key = (intent: frozen.selectionGeneration, generation: directories.projects.generation, id: id,
      origin: binding?.origin, reference: binding?.header.reference);
    if (_projectKey == key) return;
    _projectKey = key;
    directories.lifetime.run('workspace-selected-project-membership', () async {
      final exists = await directories.projectExists(id);
      if (_projectKey != key || !_sameProject(frozen, id)) return;
      if (exists) { _projectSeen = id; }
      // A newly opened project's add may still be queued behind an older
      // baseline. Absence alone cannot invalidate a target never seen there.
      else if (_projectSeen == id && !commands.holdsRemoval(source.value)) _ordinaryRemoval(frozen, project: true);
    }).then<void>((_) {}, onError: (Object error, StackTrace stack) {
      directories.lifetime.lastCause = error; directories.lifetime.lastStack = stack;
    });
  }

  void _ordinaryRemoval(WorkspaceState frozen, {required bool project}) {
    final matches = project ? _sameProject(frozen, frozen.selection.projectId!) : _sameSelection(frozen);
    final pending = _removal;
    if (!matches || commands.holdsRemoval(source.value) || pending?.frozen == frozen && (pending!.project || !project)) return;
    final work = directories.lifetime.run('workspace-explicit-removal', () async {
      await Future<void>.value();
      if ((project ? !_sameProject(frozen, frozen.selection.projectId!) : !_sameSelection(frozen)) ||
          commands.holdsRemoval(source.value)) return;
      if (project) { await afterProjectRemoval(frozen, frozen.selection.projectId!); }
      else {
        final root = await directories.firstRoot(frozen.selection.projectId!);
        if (!_sameSelection(frozen) || commands.holdsRemoval(frozen)) return;
        adopt(WorkspaceIntentStamp(generation: frozen.selectionGeneration), WorkspaceSelection(
          projectId: frozen.selection.projectId, threadId: root?.id, needsOpen: false), thread: root);
      }
    });
    _removal = (frozen: frozen, project: project, work: work);
    work.then<void>((_) { if (identical(_removal?.work, work)) _removal = null; }, onError: (Object error, StackTrace stack) {
      directories.lifetime.lastCause = error; directories.lifetime.lastStack = stack;
      if (identical(_removal?.work, work)) _removal = null;
    });
  }

  Future<void> afterProjectRemoval(WorkspaceState frozen, String id) async {
    if (!_sameProject(frozen, id) || frozen.selection.projectId != id) return;
    final next = await directories.firstProjectAfterRemoval(id);
    if (!_sameProject(frozen, id)) return;
    adopt(WorkspaceIntentStamp(generation: frozen.selectionGeneration), WorkspaceSelection(
      projectId: next?.id, threadId: null, needsOpen: false));
  }

  void afterThreadArchive(WorkspaceState frozen, ArchiveThreadResult result) {
    if (directories.lifetime.sealed || source.value.selectionGeneration != frozen.selectionGeneration ||
        source.value.selection.projectId != frozen.selection.projectId ||
        !result.removedThreadIds.contains(source.value.selection.threadId)) return;
    final next = result.nextRoot;
    adopt(WorkspaceIntentStamp(generation: frozen.selectionGeneration), WorkspaceSelection(
      projectId: frozen.selection.projectId, threadId: next?.id, needsOpen: false), thread: next);
  }

  bool current(WorkspaceIntentStamp intent) => !directories.lifetime.sealed && source.value.selectionGeneration == intent.generation;

  WorkspaceIntentStamp reserve() {
    directories.lifetime.admit();
    return WorkspaceIntentStamp(generation: source.value.selectionGeneration + 1);
  }

  void publishIntent(WorkspaceIntentStamp intent) {
    directories.lifetime.admit();
    _pending.add(intent);
    if (intent.generation > source.value.selectionGeneration) source.publish(source.value.copyWith(selectionGeneration: intent.generation));
  }

  void settleIntent(WorkspaceIntentStamp intent, {bool unknown = false}) { if (!unknown) _pending.remove(intent); }

  WorkspaceSelectionResult superseded(WorkspaceIntentStamp intent) => WorkspaceSelectionResult(
    intent: intent, selection: source.value.selection, disposition: SelectionDisposition.superseded);

  WorkspaceSelectionResult adopt(WorkspaceIntentStamp intent, WorkspaceSelection selection, {WorkspaceThreadRecord? thread}) {
    if (!current(intent)) return superseded(intent);
    if (thread != null && (thread.id != selection.threadId || thread.projectId != selection.projectId)) {
      throw resourceProtocol('Selection metadata belongs to another original target.');
    }
    final same = source.value.selection == selection;
    final next = source.value.copyWith(selection: selection);
    _bindSelected(next);
    _root = thread == null ? null : (projectId: thread.projectId, threadId: thread.id,
      rootId: thread.isRoot ? thread.id : thread.rootThreadId);
    if (!same) source.publish(source.value.copyWith(selection: selection));
    if (_selectedRead case final owner?) _checkThread(owner, next);
    _checkProject();
    return WorkspaceSelectionResult(intent: intent, selection: selection,
      disposition: same ? SelectionDisposition.unchanged : SelectionDisposition.selected);
  }

  OperationTicket<WorkspaceSelectionResult> _intent(String label, bool already,
      Future<WorkspaceSelectionResult> Function(WorkspaceIntentStamp, WorkspaceCommandScope<WorkspaceSelectionResult>) action,
      {WorkspaceWriteKey? key}) {
    directories.lifetime.admit();
    final noop = already && _pending.isEmpty && !commands.selectionPending;
    final intent = noop ? WorkspaceIntentStamp(generation: source.value.selectionGeneration) : reserve();
    return commands.run(label: label, key: key, selection: true,
      registered: () { if (!noop) publishIntent(intent); else _pending.add(intent); },
      finished: () => settleIntent(intent), action: (scope) async {
        if (!current(intent)) return superseded(intent);
        if (noop) return WorkspaceSelectionResult(intent: intent, selection: source.value.selection,
          disposition: SelectionDisposition.unchanged);
        return await action(intent, scope);
      });
  }

  Future<WorkspaceSelectionResult> defaultProject(String id, WorkspaceIntentStamp intent) async {
    if (!current(intent)) return superseded(intent);
    final root = await directories.firstRoot(id);
    if (!current(intent)) return superseded(intent);
    access.project(id);
    return adopt(intent, WorkspaceSelection(projectId: id, threadId: root?.id, needsOpen: false), thread: root);
  }

  OperationTicket<WorkspaceSelectionResult> selectProject(String id) => _intent('workspace-select-project',
    source.value.selection.projectId == id, (intent, scope) async {
      access.project(id);
      final project = await directories.readProject(id);
      if (project.id != id) throw resourceProtocol('Project selection read another target.');
      if (!current(intent)) return superseded(intent);
      access.project(id);
      await scope.invoke(() => directories.port.activateProject(id)); scope.confirm();
      return await defaultProject(id, intent);
    }, key: (kind: WorkspaceWriteKind.project, id: id, path: null));

  OperationTicket<WorkspaceSelectionResult> selectThread(String id) => _intent('workspace-select-thread',
    source.value.selection.threadId == id && !source.value.selection.needsOpen, (intent, scope) async {
      final thread = await directories.readThread(id);
      if (!current(intent)) return superseded(intent);
      _threadAllowed(thread); access.thread(id);
      return adopt(intent, WorkspaceSelection(projectId: thread.projectId, threadId: id, needsOpen: false), thread: thread);
    });

  OperationTicket<WorkspaceSelectionResult> selectAgentThread(String id) {
    directories.lifetime.admit();
    final originalRoot = _root;
    return _intent('workspace-select-agent', source.value.selection.threadId == id, (intent, scope) async {
      if (originalRoot == null) throw _noRoot;
      final thread = await directories.readThread(id);
      if (!current(intent)) return superseded(intent);
      final rootId = thread.isRoot ? thread.id : thread.rootThreadId;
      if (rootId != originalRoot.rootId || thread.projectId != originalRoot.projectId) throw _noRoot;
      _threadAllowed(thread); access.thread(id);
      return adopt(intent, WorkspaceSelection(projectId: thread.projectId, threadId: id, needsOpen: false), thread: thread);
    });
  }

  OperationTicket<WorkspaceSelectionResult> beginNewThread(String projectId) => _intent('workspace-new-thread',
    source.value.selection.projectId == projectId && source.value.selection.threadId == null, (intent, scope) async {
      access.project(projectId); await directories.readProject(projectId);
      if (!current(intent)) return superseded(intent);
      access.project(projectId);
      return adopt(intent, WorkspaceSelection(projectId: projectId, threadId: null, needsOpen: false));
    });

  OperationTicket<WorkspaceSelectionResult> openSelectedThread(String id) {
    directories.lifetime.admit();
    final selection = source.value.selection;
    final intent = WorkspaceIntentStamp(generation: source.value.selectionGeneration);
    return commands.run(label: 'workspace-open-selected', selection: true, action: (scope) async {
      if (!current(intent)) return superseded(intent);
      if (selection.threadId != id || !selection.needsOpen) return WorkspaceSelectionResult(
        intent: intent, selection: source.value.selection, disposition: SelectionDisposition.unchanged);
      final thread = await directories.readThread(id);
      if (!current(intent) || source.value.selection != selection) return superseded(intent);
      if (thread.projectId != selection.projectId) throw resourceProtocol('The original selected Thread changed Project.');
      _threadAllowed(thread); access.thread(id);
      return adopt(intent, selection.copyWith(needsOpen: false), thread: thread);
    });
  }

  OperationTicket<WorkspaceSelectionResult> restoreThread(String id) => _intent('workspace-restore-thread', false,
    (intent, scope) async {
      final thread = await scope.invoke(() => directories.port.restoreThread(id)); scope.confirm();
      if (thread.id != id || !thread.isRoot || thread.archived) throw resourceProtocol('Restore returned another or still archived root.');
      return adopt(intent, WorkspaceSelection(projectId: thread.projectId, threadId: id, needsOpen: false), thread: thread);
    }, key: (kind: WorkspaceWriteKind.thread, id: id, path: null));

  void _threadAllowed(WorkspaceThreadRecord thread) {
    if (thread.archived) throw const StudioFailure(code: StudioFailureCode.invalidArgument,
      message: 'Restore the archived Thread explicitly before selecting it.', retryable: false, correlationId: 'workspace');
  }

  @override
  WorkspaceIntentStamp capture(String projectId) {
    directories.lifetime.admit();
    final state = source.value;
    if (_pending.isNotEmpty || commands.selectionPending || state.selection.projectId != projectId || state.selection.threadId != null || state.selection.needsOpen) {
      throw const StudioFailure(code: StudioFailureCode.conflict,
        message: 'The original Project start selection is no longer available.', retryable: false, correlationId: 'workspace');
    }
    _submission = (projectId: projectId, generation: state.selectionGeneration);
    return WorkspaceIntentStamp(generation: state.selectionGeneration);
  }

  @override
  bool adoptCreatedThread(WorkspaceThreadRecord thread, WorkspaceIntentStamp expected) {
    final original = _submission;
    final state = source.value;
    if (!current(expected) || original == null || original.generation != expected.generation ||
        thread.projectId != original.projectId || state.selection.projectId != original.projectId ||
        state.selection.threadId != null || state.selection.needsOpen) return false;
    try { adopt(expected, WorkspaceSelection(projectId: thread.projectId, threadId: thread.id, needsOpen: false), thread: thread); }
    on StudioFailure catch (error, stack) {
      directories.lifetime.lastCause = error; directories.lifetime.lastStack = stack; return false;
    }
    return true;
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    directories.seal();
    final reports = await Future.wait([directories.close(deadline: deadline, retry: retry), commands.close(deadline: deadline, retry: retry)]);
    // A reentrant seal may observe an admitted work before its synchronous
    // capture handoff. After joining, snapshot that same map again rather than
    // losing a late retention or keeping an obsolete pending snapshot.
    final report = CloseReport(unresolved: [...reports.first.unresolved, ...commands.unresolved, ...opening.unresolved]);
    if (report.complete && !_publisherClosed) { source.close(); _publisherClosed = true; }
    return report;
  }

  static const _noRoot = StudioFailure(code: StudioFailureCode.invalidArgument,
    message: 'The requested agent does not belong to the original selected root.', retryable: false, correlationId: 'workspace');
}
