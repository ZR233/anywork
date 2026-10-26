import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/directory_values.dart';
import '../domain/directory_state.dart';
import '../domain/agent_directory_queries.dart';
import '../domain/selection.dart';
import 'workspace_access.dart';
import 'workspace_commands.dart';
import 'workspace_directories.dart';
import 'workspace_open.dart';
import 'workspace_selection_port.dart';
import 'thread_directory_owner.dart';
import 'directory_collection.dart' show directorySuperseded;

/// The sole selection publisher, including D1's post-creation adoption.
final class WorkspaceSelectionOwner implements WorkspaceSubmissionSelection {
  WorkspaceSelectionOwner(this.directories, this.commands, this.access)
    : source = ResourceSource(
        const WorkspaceState(
          selection: WorkspaceSelection(
            projectId: null,
            threadId: null,
            needsOpen: false,
          ),
          selectionGeneration: 0,
          sealed: false,
        ),
        directories.lifetime.budget,
        'workspace-selection',
      ) {
    directories.lifetime.onSeal(() {
      source.publish(source.value.copyWith(sealed: true));
      source.seal();
    });
    _projectsObservation = directories.projects.source.watch(
      (_) => _checkProject(),
    );
    directories.projects.removed = (origin, ids) {
      final frozen = source.value;
      if (ids.contains(frozen.selection.projectId) &&
          directories.projects.source.value.projection.stamp?.origin ==
              origin) {
        _ordinaryRemoval(frozen, project: true);
      }
    };
    directories.lifetime.onSeal(() {
      _projectsObservation.cancel();
      _threadObservation?.cancel();
    });
  }
  final WorkspaceDirectories directories;
  final WorkspaceCommands commands;
  final WorkspaceAccess access;
  final ResourceSource<WorkspaceState> source;
  late final WorkspaceOpen opening = WorkspaceOpen(directories, this, commands);
  // Admission invalidates older work immediately. The public generation is
  // published only together with that intent's resolved selection.
  int _generation = 0;
  final Set<WorkspaceIntentStamp> _pending = Set.identity();
  ({String projectId, String threadId, String rootId})? _root;
  ({String projectId, int generation})? _submission;
  bool _publisherClosed = false;
  late final Observation _projectsObservation;
  Observation? _threadObservation;
  WorkspaceThreadDirectory? _selectedRead;
  WorkspaceState? _selectedReadState;
  String? _projectSeen;
  ({
    int intent,
    int generation,
    String id,
    ProductReadOrigin? origin,
    ProjectDirectoryReadRef? reference,
  })?
  _projectKey;
  ({WorkspaceState frozen, bool project, Future<void> work})? _removal;

  String? selectedRootFor(WorkspaceState frozen) =>
      frozen.selection.projectId == _root?.projectId &&
          frozen.selection.threadId == _root?.threadId
      ? _root?.rootId
      : null;

  bool _sameSelection(WorkspaceState frozen) =>
      !directories.lifetime.sealed &&
      _generation == frozen.selectionGeneration &&
      source.value.selectionGeneration == frozen.selectionGeneration &&
      source.value.selection == frozen.selection;

  bool _sameProject(WorkspaceState frozen, String id) =>
      !directories.lifetime.sealed &&
      _generation == frozen.selectionGeneration &&
      source.value.selectionGeneration == frozen.selectionGeneration &&
      source.value.selection.projectId == id;

  void _retire(WorkspaceThreadDirectory owner) {
    if (directories.lifetime.sealed) {
      owner.requestClose();
      return;
    }
    unawaited(
      directories.lifetime
          .run('workspace-selection-read-retire', () async {
            // Publish the new selection before cancellation can synchronously reenter.
            await Future<void>.value();
            await owner.close();
          })
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              directories.lifetime.lastCause = error;
              directories.lifetime.lastStack = stack;
            },
          ),
    );
  }

  void _bindSelected(WorkspaceState frozen) {
    if (_selectedReadState?.selection.projectId != frozen.selection.projectId) {
      _projectSeen = null;
      _projectKey = null;
    }
    final old = _selectedRead;
    final id = frozen.selection.needsOpen ? null : frozen.selection.threadId;
    final existing = old?.mirror.scope;
    final next = id == null
        ? null
        : existing is SingleThreadDirectoryScope &&
              existing.threadId == id &&
              old != null &&
              !old.lifetime.sealed &&
              _selectedReadState == frozen
        ? old
        : directories.openScope(ThreadDirectoryScope.thread(threadId: id));
    Observation? observation;
    try {
      if (next != null)
        observation = next.mirror.source.watch(
          (_) => _checkThread(next, frozen),
        );
    } catch (_) {
      if (next != null && !identical(next, old)) _retire(next);
      rethrow;
    }
    _threadObservation?.cancel();
    _threadObservation = observation;
    _selectedRead = next;
    _selectedReadState = frozen;
    if (next != null)
      next.mirror.removed = (origin, entries) {
        if (entries.isNotEmpty &&
            next.mirror.source.value.projection.stamp?.origin == origin &&
            identical(_selectedRead, next) &&
            _sameSelection(frozen) &&
            !commands.holdsRemoval(frozen)) {
          _ordinaryRemoval(frozen, project: false);
        }
      };
    if (old != null && !identical(old, next)) _retire(old);
  }

  void _checkThread(WorkspaceThreadDirectory owner, WorkspaceState frozen) {
    if (!identical(_selectedRead, owner) ||
        !_sameSelection(frozen) ||
        commands.holdsRemoval(frozen))
      return;
    final state = owner.mirror.source.value;
    final value = state.threads;
    if (state.projection.sync.phase != ResourceSyncPhase.ready ||
        value is! CurrentCollectionMirror<WorkspaceThreadRecord> ||
        value.window.origin != state.projection.stamp?.origin)
      return;
    for (final row in value.window.rows.values) {
      if (row is ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef> &&
          row.current.origin == value.window.origin &&
          row.current.value.id == frozen.selection.threadId &&
          row.current.value.archived) {
        _ordinaryRemoval(frozen, project: false);
        return;
      }
    }
  }

  void _checkProject() {
    final frozen = source.value;
    final id = frozen.selection.projectId;
    if (directories.lifetime.sealed ||
        frozen.selection.needsOpen ||
        id == null ||
        commands.holdsRemoval(frozen))
      return;
    final binding = directories.projects.current;
    if (binding == null &&
        directories.projects.source.value.projection.sync.phase !=
            ResourceSyncPhase.idle)
      return;
    final key = (
      intent: frozen.selectionGeneration,
      generation: directories.projects.generation,
      id: id,
      origin: binding?.origin,
      reference: binding?.header.reference,
    );
    if (_projectKey == key) return;
    _projectKey = key;
    unawaited(
      directories.lifetime
          .run('workspace-selected-project-membership', () async {
            final exists = await directories.projectExists(id);
            if (_projectKey != key || !_sameProject(frozen, id)) return;
            if (exists) {
              _projectSeen = id;
            }
            // A newly opened project's add may still be queued behind an older
            // baseline. Absence alone cannot invalidate a target never seen there.
            else if (_projectSeen == id && !commands.holdsRemoval(source.value))
              _ordinaryRemoval(frozen, project: true);
          })
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              directories.lifetime.lastCause = error;
              directories.lifetime.lastStack = stack;
            },
          ),
    );
  }

  void _ordinaryRemoval(WorkspaceState frozen, {required bool project}) {
    if (frozen.selection.needsOpen) return;
    final matches = project
        ? _sameProject(frozen, frozen.selection.projectId!)
        : _sameSelection(frozen);
    final pending = _removal;
    if (!matches ||
        commands.holdsRemoval(source.value) ||
        pending?.frozen == frozen && (pending!.project || !project))
      return;
    final work = directories.lifetime.run(
      'workspace-explicit-removal',
      () async {
        await Future<void>.value();
        if ((project
                ? !_sameProject(frozen, frozen.selection.projectId!)
                : !_sameSelection(frozen)) ||
            commands.holdsRemoval(source.value))
          return;
        if (project) {
          await afterProjectRemoval(frozen, frozen.selection.projectId!);
        } else {
          final root = await directories.firstRoot(frozen.selection.projectId!);
          if (!_sameSelection(frozen) || commands.holdsRemoval(frozen)) return;
          adopt(
            WorkspaceIntentStamp(generation: frozen.selectionGeneration),
            WorkspaceSelection(
              projectId: frozen.selection.projectId,
              threadId: root?.id,
              needsOpen: false,
            ),
            thread: root,
          );
        }
      },
    );
    _removal = (frozen: frozen, project: project, work: work);
    unawaited(
      work.then<void>(
        (_) {
          if (identical(_removal?.work, work)) _removal = null;
        },
        onError: (Object error, StackTrace stack) {
          directories.lifetime.lastCause = error;
          directories.lifetime.lastStack = stack;
          if (identical(_removal?.work, work)) _removal = null;
        },
      ),
    );
  }

  Future<void> afterProjectRemoval(WorkspaceState frozen, String id) async {
    if (!_sameProject(frozen, id) || frozen.selection.projectId != id) return;
    final next = await directories.firstProjectAfterRemoval(id);
    if (!_sameProject(frozen, id)) return;
    adopt(
      WorkspaceIntentStamp(generation: frozen.selectionGeneration),
      WorkspaceSelection(projectId: next?.id, threadId: null, needsOpen: false),
    );
  }

  void afterThreadArchive(WorkspaceState frozen, ArchiveThreadResult result) {
    if (directories.lifetime.sealed ||
        _generation != frozen.selectionGeneration ||
        source.value.selectionGeneration != frozen.selectionGeneration ||
        source.value.selection.projectId != frozen.selection.projectId ||
        !result.removedThreadIds.contains(source.value.selection.threadId))
      return;
    final next = result.nextRoot;
    adopt(
      WorkspaceIntentStamp(generation: frozen.selectionGeneration),
      WorkspaceSelection(
        projectId: frozen.selection.projectId,
        threadId: next?.id,
        needsOpen: false,
      ),
      thread: next,
    );
  }

  bool current(WorkspaceIntentStamp intent) =>
      !directories.lifetime.sealed && _generation == intent.generation;

  WorkspaceIntentStamp reserve() {
    directories.lifetime.admit();
    return WorkspaceIntentStamp(generation: ++_generation);
  }

  void publishIntent(WorkspaceIntentStamp intent) {
    directories.lifetime.admit();
    // Register pending work only. Publishing the previous selection here would
    // consume the generation before adopt resolves its final target.
    _pending.add(intent);
  }

  void settleIntent(WorkspaceIntentStamp intent, {bool unknown = false}) {
    if (unknown) return;
    _pending.remove(intent);
    if (!current(intent) ||
        source.value.selectionGeneration >= intent.generation)
      return;
    // A rejected/no-change intent resolves to the retained selection. Publish
    // it once at settlement, never speculatively before its result is known.
    final next = source.value.copyWith(selectionGeneration: intent.generation);
    _bindSelected(next);
    source.publish(next);
    if (_selectedRead case final owner?) _checkThread(owner, next);
    _checkProject();
  }

  WorkspaceSelectionResult superseded(WorkspaceIntentStamp intent) =>
      WorkspaceSelectionResult(
        intent: intent,
        selection: source.value.selection,
        disposition: SelectionDisposition.superseded,
      );

  WorkspaceSelectionResult adopt(
    WorkspaceIntentStamp intent,
    WorkspaceSelection selection, {
    WorkspaceThreadRecord? thread,
  }) {
    if (!current(intent)) return superseded(intent);
    if (thread != null &&
        (thread.id != selection.threadId ||
            thread.projectId != selection.projectId)) {
      throw resourceProtocol(
        'Selection metadata belongs to another original target.',
      );
    }
    final same = source.value.selection == selection;
    // Automatic fallback and post-creation adoption start from a captured
    // published selection. A changed target needs its own fresh generation.
    final adopted =
        !same && source.value.selectionGeneration == intent.generation
        ? reserve()
        : intent;
    final next = source.value.copyWith(
      selection: selection,
      selectionGeneration: adopted.generation,
    );
    _bindSelected(next);
    _root = thread == null
        ? null
        : (
            projectId: thread.projectId,
            threadId: thread.id,
            rootId: thread.isRoot ? thread.id : thread.rootThreadId,
          );
    if (source.value != next) source.publish(next);
    if (_selectedRead case final owner?) _checkThread(owner, next);
    _checkProject();
    return WorkspaceSelectionResult(
      intent: adopted,
      selection: selection,
      disposition: same
          ? SelectionDisposition.unchanged
          : SelectionDisposition.selected,
    );
  }

  OperationTicket<WorkspaceSelectionResult> _intent(
    String label,
    bool already,
    Future<WorkspaceSelectionResult> Function(
      WorkspaceIntentStamp,
      WorkspaceCommandScope<WorkspaceSelectionResult>,
    )
    action, {
    WorkspaceWriteKey? key,
  }) {
    directories.lifetime.admit();
    final noop =
        already &&
        _pending.isEmpty &&
        !commands.selectionPending &&
        _generation == source.value.selectionGeneration;
    final intent = noop
        ? WorkspaceIntentStamp(generation: source.value.selectionGeneration)
        : reserve();
    return commands.run(
      label: label,
      key: key,
      selection: true,
      registered: () {
        if (!noop)
          publishIntent(intent);
        else
          _pending.add(intent);
      },
      finished: () => settleIntent(intent),
      action: (scope) async {
        if (!current(intent)) return superseded(intent);
        if (noop)
          return WorkspaceSelectionResult(
            intent: intent,
            selection: source.value.selection,
            disposition: SelectionDisposition.unchanged,
          );
        try {
          return await action(intent, scope);
        } catch (_) {
          // Only obsolete pure reads are suppressed. Actual writes/Unknown
          // must still settle their original operation evidence.
          if (!current(intent) && !scope.dispatched && !scope.confirmed)
            return superseded(intent);
          rethrow;
        }
      },
    );
  }

  Future<WorkspaceSelectionResult> defaultProject(
    String id,
    WorkspaceIntentStamp intent,
  ) async {
    if (!current(intent)) return superseded(intent);
    final root = await directories.firstRoot(id);
    if (!current(intent)) return superseded(intent);
    access.project(id);
    return adopt(
      intent,
      WorkspaceSelection(projectId: id, threadId: root?.id, needsOpen: false),
      thread: root,
    );
  }

  OperationTicket<WorkspaceSelectionResult> selectProject(String id) => _intent(
    'workspace-select-project',
    source.value.selection.projectId == id && !source.value.selection.needsOpen,
    (intent, scope) async {
      access.project(id);
      final project = await directories.readProject(id);
      if (project.id != id)
        throw resourceProtocol('Project selection read another target.');
      if (!current(intent)) return superseded(intent);
      access.project(id);
      await scope.invoke(() => directories.port.activateProject(id));
      scope.confirm();
      return await defaultProject(id, intent);
    },
    key: (kind: WorkspaceWriteKind.project, id: id, path: null),
  );

  OperationTicket<WorkspaceSelectionResult> selectThread(String id) => _intent(
    'workspace-select-thread',
    source.value.selection.threadId == id && !source.value.selection.needsOpen,
    (intent, scope) async {
      final thread = await directories.readThread(id);
      if (!current(intent)) return superseded(intent);
      _threadAllowed(thread);
      access.thread(id);
      return adopt(
        intent,
        WorkspaceSelection(
          projectId: thread.projectId,
          threadId: id,
          needsOpen: false,
        ),
        thread: thread,
      );
    },
  );

  WorkspaceSelectionResult restoreSelection(WorkspaceSelection selection) {
    directories.lifetime.admit();
    // Freezed's asserts are debug-only; keep the public admission typed in
    // release builds too. Restoration cannot prove metadata membership yet.
    if (selection.threadId != null && selection.projectId == null ||
        selection.needsOpen && selection.threadId == null) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'A selected Thread requires a Project; pending-open requires a Thread.',
        retryable: false,
        correlationId: 'workspace',
      );
    }
    final restored = selection.copyWith(needsOpen: selection.threadId != null);
    final same = source.value.selection == restored;
    final intent = reserve();
    final next = source.value.copyWith(
      selection: restored,
      selectionGeneration: intent.generation,
    );
    // Do not use adopt: it checks membership and binds metadata for opened
    // targets. This only releases the previous borrow; pending-open binds none.
    _bindSelected(next);
    _root = null;
    _submission = null;
    _projectSeen = null;
    _projectKey = null;
    // One atomic publication invalidates old work without briefly reopening
    // the previous target under the new generation. No command is recorded.
    source.publish(next);
    if (!current(intent)) return superseded(intent);
    return WorkspaceSelectionResult(
      intent: intent,
      selection: restored,
      disposition: same
          ? SelectionDisposition.unchanged
          : SelectionDisposition.selected,
    );
  }

  OperationTicket<WorkspaceSelectionResult> selectAgentThread(String id) {
    directories.lifetime.admit();
    final originalSelection = source.value.selection;
    final originalRoot = _root;
    final originalBinding = _selectedRead;
    var membership = directories.agents.current;
    bool ownsPosition() =>
        originalRoot != null &&
        originalSelection.projectId == originalRoot.projectId &&
        originalSelection.threadId == originalRoot.threadId &&
        source.value.selection == originalSelection &&
        _root == originalRoot &&
        identical(_selectedRead, originalBinding) &&
        (originalBinding == null || !originalBinding.lifetime.sealed);
    bool ownsMembership() {
      final original = membership;
      final current = directories.agents.current;
      return original != null &&
          current != null &&
          current.generation == original.generation &&
          current.origin == original.origin &&
          current.header.reference == original.header.reference &&
          current.collection == original.collection;
    }

    return _intent(
      'workspace-select-agent',
      originalSelection.threadId == id && !originalSelection.needsOpen,
      (intent, scope) async {
        if (originalRoot == null) throw _noRoot;
        if (!current(intent) ||
            !ownsPosition() ||
            membership != null && !ownsMembership())
          return superseded(intent);
        try {
          await directories.agentReads.complete();
        } catch (error) {
          if (!current(intent) ||
              !ownsPosition() ||
              membership != null && !ownsMembership())
            return superseded(intent);
          // ready() revokes its original, still-unbound demand with this exact
          // local read signal. Do not infer supersession from arbitrary codes or
          // hide a current storage/permission failure or closing cancellation.
          if (membership == null && identical(error, directorySuperseded))
            return superseded(intent);
          rethrow;
        }
        if (!current(intent) ||
            !ownsPosition() ||
            membership != null && !ownsMembership())
          return superseded(intent);
        // A previously unopened directory can bind its first complete native
        // capture here. complete() already rejects replacement of that demand.
        membership ??= directories.agents.current;
        if (!ownsMembership()) return superseded(intent);
        bool member() => AgentDirectoryQueries.forRoot(
          rootThreadId: originalRoot.rootId,
          directory: directories.agents.source.value,
        ).any((agent) => agent.threadId == id);
        if (!member()) throw _noRoot;
        bool ownsRead() {
          if (!current(intent) || !ownsPosition() || !ownsMembership())
            return false;
          // Origin/header equality alone cannot prove actual membership. Missing
          // or no-longer-complete rows also revoke this old read's publication.
          try {
            return member();
          } on StudioFailure {
            return false;
          }
        }

        final WorkspaceThreadRecord thread;
        try {
          thread = await directories.readThread(id);
        } catch (_) {
          if (!ownsRead()) return superseded(intent);
          rethrow;
        }
        if (!ownsRead()) return superseded(intent);
        final rootId = thread.isRoot ? thread.id : thread.rootThreadId;
        if (thread.id != id ||
            rootId != originalRoot.rootId ||
            thread.projectId != originalRoot.projectId) {
          throw resourceProtocol(
            'Selected agent metadata did not match its original Thread, Project or root.',
          );
        }
        _threadAllowed(thread);
        access.thread(id);
        if (!ownsRead()) return superseded(intent);
        return adopt(
          intent,
          WorkspaceSelection(
            projectId: thread.projectId,
            threadId: id,
            needsOpen: false,
          ),
          thread: thread,
        );
      },
    );
  }

  OperationTicket<WorkspaceSelectionResult> beginNewThread(String projectId) =>
      _intent(
        'workspace-new-thread',
        source.value.selection.projectId == projectId &&
            source.value.selection.threadId == null,
        (intent, scope) async {
          access.project(projectId);
          await directories.readProject(projectId);
          if (!current(intent)) return superseded(intent);
          access.project(projectId);
          if (source.value.selection.projectId != projectId) {
            await scope.invoke(
              () => directories.port.activateProject(projectId),
            );
            scope.confirm();
            if (!current(intent)) return superseded(intent);
          }
          return adopt(
            intent,
            WorkspaceSelection(
              projectId: projectId,
              threadId: null,
              needsOpen: false,
            ),
          );
        },
      );

  OperationTicket<WorkspaceSelectionResult> openSelectedThread(String id) {
    directories.lifetime.admit();
    final selection = source.value.selection;
    return _intent(
      'workspace-open-selected',
      selection.threadId == id && !selection.needsOpen,
      (intent, scope) async {
        if (!current(intent)) return superseded(intent);
        if (selection.threadId != id || !selection.needsOpen)
          return WorkspaceSelectionResult(
            intent: intent,
            selection: source.value.selection,
            disposition: SelectionDisposition.unchanged,
          );
        final thread = await directories.readThread(id);
        if (!current(intent) || source.value.selection != selection)
          return superseded(intent);
        if (thread.projectId != selection.projectId)
          throw resourceProtocol(
            'The original selected Thread changed Project.',
          );
        _threadAllowed(thread);
        access.thread(id);
        return adopt(
          intent,
          selection.copyWith(needsOpen: false),
          thread: thread,
        );
      },
    );
  }

  OperationTicket<WorkspaceSelectionResult> restoreThread(String id) =>
      _intent('workspace-restore-thread', false, (intent, scope) async {
        final thread = await scope.invoke(
          () => directories.port.restoreThread(id),
        );
        scope.confirm();
        if (thread.id != id || !thread.isRoot || thread.archived)
          throw resourceProtocol(
            'Restore returned another or still archived root.',
          );
        // Unarchive changes directory visibility only. It is not an open,
        // worktree recreation or a fresh permission to execute this Thread.
        return WorkspaceSelectionResult(
          intent: intent,
          selection: source.value.selection,
          disposition: SelectionDisposition.unchanged,
        );
      }, key: (kind: WorkspaceWriteKind.thread, id: id, path: null));

  void _threadAllowed(WorkspaceThreadRecord thread) {
    if (thread.archived)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Restore the archived Thread explicitly before selecting it.',
        retryable: false,
        correlationId: 'workspace',
      );
  }

  @override
  WorkspaceIntentStamp capture(String projectId) {
    directories.lifetime.admit();
    final state = source.value;
    // Creation shares the latest navigation boundary instead of excluding it:
    // the stamp is the published generation, so any older queued navigation or
    // cold read retires at its own receipt and any newer one simply prevents
    // the post-creation adoption below. Nothing here publishes a selection.
    if (state.selection.projectId != projectId || state.selection.needsOpen) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The original Project start selection is no longer available.',
        retryable: false,
        correlationId: 'workspace',
      );
    }
    // Creation reserves the latest navigation boundary itself: an older queued
    // navigation or cold read retires at its own receipt, and a newer intent
    // prevents post-creation adoption without publishing a selection here.
    final intent = reserve();
    _submission = (projectId: projectId, generation: intent.generation);
    return intent;
  }

  @override
  bool adoptCreatedThread(
    WorkspaceThreadRecord thread,
    WorkspaceIntentStamp expected,
  ) {
    final original = _submission;
    final state = source.value;
    if (!current(expected) ||
        original == null ||
        original.generation != expected.generation ||
        thread.projectId != original.projectId ||
        state.selection.projectId != original.projectId ||
        state.selection.threadId != null ||
        state.selection.needsOpen)
      return false;
    try {
      adopt(
        expected,
        WorkspaceSelection(
          projectId: thread.projectId,
          threadId: thread.id,
          needsOpen: false,
        ),
        thread: thread,
      );
    } on StudioFailure catch (error, stack) {
      directories.lifetime.lastCause = error;
      directories.lifetime.lastStack = stack;
      return false;
    }
    return true;
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    directories.seal();
    final reports = await Future.wait([
      directories.close(deadline: deadline, retry: retry),
      commands.close(deadline: deadline, retry: retry),
    ]);
    // A reentrant seal may observe an admitted work before its synchronous
    // capture handoff. After joining, snapshot that same map again rather than
    // losing a late retention or keeping an obsolete pending snapshot.
    final report = CloseReport(
      unresolved: [
        ...reports.first.unresolved,
        ...commands.unresolved,
        ...opening.unresolved,
      ],
    );
    if (report.complete && !_publisherClosed) {
      source.close();
      _publisherClosed = true;
    }
    return report;
  }

  static const _noRoot = StudioFailure(
    code: StudioFailureCode.invalidArgument,
    message:
        'The requested agent does not belong to the original selected root.',
    retryable: false,
    correlationId: 'workspace',
  );
}
