import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:test/test.dart';

import 'support/conversation_fixture.dart';
import 'support/drafts_workspace_fixture.dart';
import 'support/workspace_selection_fixture.dart';

const _cold = WorkspaceSelection(
  projectId: 'project',
  threadId: 'cold-child',
  needsOpen: true,
);

WorkspaceSelectionFixture _fixture() {
  final fixture = WorkspaceSelectionFixture();
  addTearDown(() async {
    expect((await fixture.close()).unresolved, isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });
  return fixture;
}

Matcher _failure(StudioFailureCode code) =>
    isA<StudioFailure>().having((error) => error.code, 'code', code);

void main() {
  test('unarchive changes visibility only and cannot open/select or grant execution on a preserved worktree', () async {
    final fixture = _fixture();
    fixture.workspace.restoreSelection(_cold);
    final selection = fixture.workspace.state.value.selection;
    final ticket = fixture.workspace.restoreThread('archived-root');
    final call = await fixture.directory.native.restoreOpened(0);
    call.reply.complete(fixtureThread('archived-root').copyWith(
      workspaceMode: ThreadWorkspaceMode.worktree, workspacePath: '/preserved-or-missing'));
    final result = await ticket.result;
    expect(result, isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>());
    expect((result as AcknowledgedCommandResult<WorkspaceSelectionResult>).value.selection, selection);
    expect(fixture.workspace.state.value.selection, selection);
    expect(fixture.conversations.repository.active.value, isNull);
    expect(fixture.directory.activations, isEmpty);
    expect(fixture.directory.threadOpens.values, isEmpty);
    expect(fixture.directory.projectOpens.values, isEmpty);
    expect(fixture.conversations.context.metadataRequests, isEmpty);
    expect(fixture.conversations.facets.execution, isEmpty);
    expect(fixture.conversations.timeline.requests, isEmpty);
  });
  test('cold restoration is synchronous and pure; only explicit open reads the original target', () async {
    final fixture = _fixture();
    final workspace = fixture.workspace;
    final publications = <WorkspaceState>[];
    final observation = workspace.state.watch(publications.add);
    addTearDown(observation.cancel);
    final WorkspaceSelectionResult restored = workspace.restoreSelection(
      _cold.copyWith(needsOpen: false),
    );
    expect(
      restored.selection,
      _cold,
      reason: 'Restoring a Thread never treats the input as already opened',
    );
    expect(restored.disposition, SelectionDisposition.selected);
    expect(publications, [
      WorkspaceState(
        selection: _cold,
        selectionGeneration: restored.intent.generation,
        sealed: false,
      ),
    ]);
    expect(fixture.directory.native.threads, isEmpty);
    expect(fixture.directory.native.projects, isEmpty);
    expect(fixture.directory.native.restores, isEmpty);
    expect(fixture.directory.activations, isEmpty);
    expect(
      fixture.conversations.operations.observations.records.value,
      isEmpty,
      reason:
          'Pure restoration has neither a command ticket nor a commit receipt',
    );

    await fixture.establishAccess();
    final opening = workspace.openSelectedThread(_cold.threadId!);
    final material = await fixture.directory.threadBaseline(
      0,
      fixtureThread('cold-child', parentThreadId: 'root'),
    );
    await material.entityEntered.future;
    final result = await opening.result;
    expect(
      result,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
      reason: result is RejectedCommandResult<WorkspaceSelectionResult>
          ? '${result.error.code}: ${result.error.message}'
          : null,
    );
    final opened =
        (result as AcknowledgedCommandResult<WorkspaceSelectionResult>).value;
    expect(opened.selection, _cold.copyWith(needsOpen: false));
    expect(workspace.state.value.selection, opened.selection);
    expect(opened.intent.generation, greaterThan(restored.intent.generation));
    expect(
      fixture.directory.native.threads.first.scope,
      ThreadDirectoryScope.thread(threadId: _cold.threadId!),
    );
    expect(
      opening.state.value.receipt,
      isNull,
      reason: 'A metadata read does not invent a native commit',
    );
    expect(fixture.directory.native.restores, isEmpty);
    expect(fixture.directory.activations, isEmpty);
  });

  test('restoration revokes an entered user-navigation metadata read before it can adopt', () async {
    final fixture = _fixture();
    await fixture.establishAccess();
    final workspace = fixture.workspace;
    final oldRecord = fixtureThread('older');
    final reply = Completer<ThreadDirectoryEntityRead>();
    final pending = workspace.selectThread(oldRecord.id);
    final material = await fixture.directory.threadBaseline(
      0,
      oldRecord,
      entityReply: reply,
    );
    await material.entityEntered.future;
    final before = workspace.state.value.selectionGeneration;
    final records = fixture.conversations.operations.observations.records.value;

    final restored = workspace.restoreSelection(_cold);
    expect(restored.intent.generation, greaterThan(before));
    final frozen = workspace.state.value;
    expect(
      fixture.conversations.operations.observations.records.value,
      records,
    );
    expect(
      fixture.directory.native.threads,
      hasLength(1),
      reason: 'Restoration cannot start another metadata scope',
    );
    reply.complete(
      ThreadDirectoryEntityRead(
        reference: const ProductEntityRef(entry: 5, revision: 1),
        value: draftThreadRead(oldRecord),
      ),
    );
    final settled =
        await pending.result
            as AcknowledgedCommandResult<WorkspaceSelectionResult>;
    expect(settled.value.disposition, SelectionDisposition.superseded);
    expect(workspace.state.value, frozen);
    expect(workspace.state.value.selection.needsOpen, isTrue);
    expect(
      fixture.directory.native.threads,
      hasLength(1),
      reason: 'Obsolete navigation cannot bind its selected read',
    );
  });

  test('restoring the same cold target advances generation and revokes an entered explicit open', () async {
    final fixture = _fixture();
    await fixture.establishAccess();
    final workspace = fixture.workspace;
    workspace.restoreSelection(_cold);
    final reply = Completer<ThreadDirectoryEntityRead>();
    final record = fixtureThread('cold-child', parentThreadId: 'root');
    final opening = workspace.openSelectedThread(record.id);
    final material = await fixture.directory.threadBaseline(
      0,
      record,
      entityReply: reply,
    );
    await material.entityEntered.future;
    final before = workspace.state.value.selectionGeneration;

    final restored = workspace.restoreSelection(_cold);
    expect(restored.disposition, SelectionDisposition.unchanged);
    expect(restored.intent.generation, greaterThan(before));
    final frozen = workspace.state.value;
    reply.complete(
      ThreadDirectoryEntityRead(
        reference: const ProductEntityRef(entry: 5, revision: 1),
        value: draftThreadRead(record),
      ),
    );
    final result =
        await opening.result
            as AcknowledgedCommandResult<WorkspaceSelectionResult>;
    expect(result.value.disposition, SelectionDisposition.superseded);
    expect(workspace.state.value, frozen);
    expect(workspace.state.value.selection.needsOpen, isTrue);
  });

  test(
    'cold selection cannot take an already-open Project or agent shortcut',
    () async {
      final fixture = _fixture();
      final workspace = fixture.workspace;
      workspace.restoreSelection(_cold);
      // Recovery has deliberately not been read. A real Project selection must
      // reject that unknown access, not acknowledge the cold target as opened.
      final project = await workspace.selectProject(_cold.projectId!).result;
      expect(
        project,
        isA<RejectedCommandResult<WorkspaceSelectionResult>>().having(
          (result) => result.error.code,
          'code',
          StudioFailureCode.unavailable,
        ),
      );
      final agent = await workspace.selectAgentThread(_cold.threadId!).result;
      expect(
        agent,
        isA<RejectedCommandResult<WorkspaceSelectionResult>>().having(
          (result) => result.error.code,
          'code',
          StudioFailureCode.invalidArgument,
        ),
        reason: 'Cold selection has no opened root metadata to authorize an agent menu',
      );
      expect(workspace.state.value.selection, _cold);
      expect(fixture.directory.native.threads, isEmpty);
      expect(fixture.directory.native.projects, isEmpty);
      expect(fixture.directory.activations, isEmpty);
    },
  );

  test('restoration validates combinations and refuses sealed or closing owners without changing selection', () async {
    final fixture = _fixture();
    final workspace = fixture.workspace;
    final original = workspace.state.value;
    for (final invalid in [
      const _UncheckedSelection(
        projectId: null,
        threadId: 'orphan',
        needsOpen: false,
      ),
      const _UncheckedSelection(
        projectId: 'project',
        threadId: null,
        needsOpen: true,
      ),
    ]) {
      expect(
        () => workspace.restoreSelection(invalid),
        throwsA(_failure(StudioFailureCode.invalidArgument)),
      );
      expect(workspace.state.value, original);
    }
    // Non-Thread combinations remain valid but cannot be marked pending-open.
    final project = workspace.restoreSelection(
      const WorkspaceSelection(
        projectId: 'project',
        threadId: null,
        needsOpen: false,
      ),
    );
    expect(
      project.selection,
      const WorkspaceSelection(
        projectId: 'project',
        threadId: null,
        needsOpen: false,
      ),
    );
    expect(fixture.directory.native.projects, isEmpty);
    workspace.seal();
    final sealed = workspace.state.value;
    expect(
      () => workspace.restoreSelection(_cold),
      throwsA(_failure(StudioFailureCode.cancelled)),
    );
    final closing = workspace.close();
    expect(
      () => workspace.restoreSelection(_cold),
      throwsA(_failure(StudioFailureCode.cancelled)),
    );
    expect((await closing).complete, isTrue);
    expect(workspace.state.value, sealed);
    expect(
      fixture.conversations.operations.observations.records.value,
      isEmpty,
    );
    expect(fixture.directory.native.threads, isEmpty);
    expect(fixture.directory.native.projects, isEmpty);
  });
}

/// Represents invalid release-mode input without depending on Freezed's debug
/// asserts. The public Repository must enforce the combinations at runtime.
final class _UncheckedSelection implements WorkspaceSelection {
  const _UncheckedSelection({
    required this.projectId,
    required this.threadId,
    required this.needsOpen,
  });
  @override
  final String? projectId;
  @override
  final String? threadId;
  @override
  final bool needsOpen;
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
