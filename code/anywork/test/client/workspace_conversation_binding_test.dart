import 'dart:async';

import 'package:anywork/src/app/composition/workspace_conversation_binding.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/operations_ports.dart' show OperationRegistry;
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../anywork_client/test/support/drafts_workspace_fixture.dart';
import '../../../anywork_client/test/support/workspace_selection_fixture.dart';
import 'support/bootstrap_workspace_fixture.dart';

({
  WorkspaceSelectionFixture selection,
  RecordingConversationDemand demand,
  WorkspaceConversationBinding binding,
})
_fixture() {
  final selection = WorkspaceSelectionFixture();
  final demand = RecordingConversationDemand(
    selection.conversations.demand,
    () => selection.workspace.state.observerCount,
  );
  final binding = WorkspaceConversationBinding(
    workspace: selection.workspace,
    demand: demand,
  );
  addTearDown(() async {
    await binding.close();
    expect((await selection.close()).unresolved, isEmpty);
    expect(selection.budget.usage, isEmpty);
  });
  return (selection: selection, demand: demand, binding: binding);
}

Future<WorkspaceSelectionResult> _openA(
  WorkspaceSelectionFixture fixture,
) async {
  await fixture.establishAccess();
  final selecting = fixture.workspace.selectThread('A');
  final material = await fixture.directory.threadBaseline(
    0,
    fixtureThread('A'),
  );
  await material.entityEntered.future;
  final result = await selecting.result;
  expect(result, isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>());
  return (result as AcknowledgedCommandResult<WorkspaceSelectionResult>).value;
}

void main() {
  test('A to user-selected B forwards only the final selection once per generation without conflict', () async {
    final fixture = _fixture();
    final selection = fixture.selection;
    final openedA = await _openA(selection);
    fixture.binding.start();
    final sessionA = selection.conversations.repository.active.value!;
    expect(sessionA.threadId, 'A');
    final before = fixture.demand.calls.length;
    final reply = Completer<ThreadDirectoryEntityRead>();
    final index = selection.directory.native.threads.length;
    final selecting = selection.workspace.selectThread('B');
    final record = fixtureThread('B');
    final material = await selection.directory.threadBaseline(
      index,
      record,
      entityReply: reply,
    );
    await material.entityEntered.future;
    final whileReading = fixture.demand.calls.skip(before).toList();
    reply.complete(
      ThreadDirectoryEntityRead(
        reference: const ProductEntityRef(entry: 5, revision: 1),
        value: draftThreadRead(record),
      ),
    );
    final result = await selecting.result;

    expect(result, isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>());
    final selected = selection.workspace.state.value;
    expect(
      whileReading,
      isEmpty,
      reason: 'An intent cannot forward A under the generation reserved for B',
    );
    expect(
      selected.selection,
      const WorkspaceSelection(
        projectId: 'project',
        threadId: 'B',
        needsOpen: false,
      ),
    );
    expect(
      selected.selectionGeneration,
      greaterThan(openedA.intent.generation),
    );
    expect(fixture.demand.calls.skip(before), [selectionDelivery(selected)]);
    expect(selection.conversations.repository.active.value?.threadId, 'B');
    expect(
      selection.conversations.repository.active.value,
      isNot(same(sessionA)),
    );
  });

  test('A to cold-restored B forwards once without metadata reads or Session activation', () async {
    final fixture = _fixture();
    final selection = fixture.selection;
    await _openA(selection);
    fixture.binding.start();
    // Join A's real metadata/recovery work before counting subsequent demands.
    final metrics = await selection.conversations.facets.metricsOpened(0);
    await metrics.feed.listened.future;
    expect(selection.conversations.repository.active.value?.threadId, 'A');
    final before = fixture.demand.calls.length;
    final threadReads = selection.directory.native.threads.length;
    final projectReads = selection.directory.native.projects.length;
    final metadataReads = selection.conversations.context.metadataRequests
        .toList();
    final timelineRequests = selection.conversations.timeline.requests.toList();
    final operations =
        selection.conversations.operations.observations.records.value;

    final restored = selection.workspace.restoreSelection(
      const WorkspaceSelection(
        projectId: 'project',
        threadId: 'B',
        needsOpen: false,
      ),
    );

    expect(
      restored.selection,
      const WorkspaceSelection(
        projectId: 'project',
        threadId: 'B',
        needsOpen: true,
      ),
    );
    expect(fixture.demand.calls.skip(before), [
      selectionDelivery(selection.workspace.state.value),
    ]);
    expect(selection.conversations.repository.active.value, isNull);
    expect(selection.conversations.repository.existingSession('B'), isNull);
    expect(selection.conversations.context.metadataRequests, metadataReads);
    expect(selection.conversations.timeline.requests, timelineRequests);
    expect(selection.directory.native.threads, hasLength(threadReads));
    expect(selection.directory.native.projects, hasLength(projectReads));
    expect(selection.directory.native.restores, isEmpty);
    expect(
      selection.conversations.operations.observations.records.value,
      operations,
    );
  });

  test('A to explicitly restored B forwards only the native result once without conflict', () async {
    final budget = ResourceBudget();
    final components = BootstrapWorkspaceFixture(
      budget: budget,
      operations: OperationRegistry(
        clientId: 'binding-restore-test',
        budget: budget,
      ),
    );
    addTearDown(() async {
      expect((await components.close()).unresolved, isEmpty);
      expect(budget.usage, isEmpty);
    });
    final restoreA = components.workspace.restoreThread('A');
    (await components.port.restoreOpened(0)).reply.complete(fixtureThread('A'));
    expect(
      await restoreA.result,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
    );
    components.binding.start();
    expect(components.conversation.active.value?.threadId, 'A');
    final before = components.demand.calls.length;

    final restoreB = components.workspace.restoreThread('B');
    final call = await components.port.restoreOpened(1);
    final whileRestoring = components.demand.calls.skip(before).toList();
    call.reply.complete(fixtureThread('B'));
    expect(
      await restoreB.result,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
    );

    expect(whileRestoring, isEmpty);
    expect(components.workspace.state.value.selection.threadId, 'B');
    expect(components.demand.calls.skip(before), [
      selectionDelivery(components.workspace.state.value),
    ]);
    expect(components.conversation.active.value?.threadId, 'B');
  });

  test('a cold selection revokes an entered older navigation before any late forwarding', () async {
    final fixture = _fixture();
    final selection = fixture.selection;
    await _openA(selection);
    fixture.binding.start();
    final before = fixture.demand.calls.length;
    final reply = Completer<ThreadDirectoryEntityRead>();
    final index = selection.directory.native.threads.length;
    final selecting = selection.workspace.selectThread('older-B');
    final record = fixtureThread('older-B');
    final material = await selection.directory.threadBaseline(
      index,
      record,
      entityReply: reply,
    );
    await material.entityEntered.future;

    final restored = selection.workspace.restoreSelection(
      const WorkspaceSelection(
        projectId: 'project',
        threadId: 'C',
        needsOpen: true,
      ),
    );
    final frozen = selection.workspace.state.value;
    reply.complete(
      ThreadDirectoryEntityRead(
        reference: const ProductEntityRef(entry: 5, revision: 1),
        value: draftThreadRead(record),
      ),
    );
    final result =
        await selecting.result
            as AcknowledgedCommandResult<WorkspaceSelectionResult>;

    expect(result.value.disposition, SelectionDisposition.superseded);
    expect(
      result.value.intent.generation,
      lessThan(restored.intent.generation),
    );
    expect(selection.workspace.state.value, frozen);
    expect(fixture.demand.calls.skip(before), [selectionDelivery(frozen)]);
    expect(selection.conversations.repository.active.value, isNull);
    expect(
      selection.conversations.repository.existingSession('older-B'),
      isNull,
    );
  });

  test('a rejected latest navigation settles A once and cannot revive an older entered read', () async {
    final fixture = _fixture();
    final selection = fixture.selection;
    final openedA = await _openA(selection);
    fixture.binding.start();
    final before = fixture.demand.calls.length;
    final oldReply = Completer<ThreadDirectoryEntityRead>();
    final oldIndex = selection.directory.native.threads.length;
    final oldNavigation = selection.workspace.selectThread('older-B');
    final oldRecord = fixtureThread('older-B');
    final oldMaterial = await selection.directory.threadBaseline(
      oldIndex,
      oldRecord,
      entityReply: oldReply,
    );
    await oldMaterial.entityEntered.future;
    final latestReply = Completer<ThreadDirectoryEntityRead>();
    final latestIndex = selection.directory.native.threads.length;
    final latestNavigation = selection.workspace.selectThread('rejected-C');
    final latestMaterial = await selection.directory.threadBaseline(
      latestIndex,
      fixtureThread('rejected-C'),
      entityReply: latestReply,
    );
    await latestMaterial.entityEntered.future;
    final settledSelection = selection.workspace.state.waitFor(
      (state) => state.selectionGeneration > openedA.intent.generation,
    );
    const failure = StudioFailure(
      code: StudioFailureCode.storage,
      message: 'The latest read failed.',
      retryable: true,
      correlationId: 'latest-selection-read',
    );
    latestReply.completeError(failure);
    expect(
      await latestNavigation.result,
      isA<RejectedCommandResult<WorkspaceSelectionResult>>().having(
        (result) => result.error,
        'error',
        same(failure),
      ),
    );
    final settled = await settledSelection;
    oldReply.complete(
      ThreadDirectoryEntityRead(
        reference: const ProductEntityRef(entry: 5, revision: 1),
        value: draftThreadRead(oldRecord),
      ),
    );
    final oldResult =
        await oldNavigation.result
            as AcknowledgedCommandResult<WorkspaceSelectionResult>;

    expect(oldResult.value.disposition, SelectionDisposition.superseded);
    expect(settled.selection.threadId, 'A');
    expect(selection.workspace.state.value, settled);
    expect(fixture.demand.calls.skip(before), [selectionDelivery(settled)]);
    expect(selection.conversations.repository.active.value?.threadId, 'A');
    expect(
      selection.conversations.repository.existingSession('older-B'),
      isNull,
    );
    final noop =
        await selection.workspace.selectThread('A').result
            as AcknowledgedCommandResult<WorkspaceSelectionResult>;
    expect(noop.value.disposition, SelectionDisposition.unchanged);
    expect(fixture.demand.calls.skip(before), [selectionDelivery(settled)]);
  });

  test('duplicate, reentrant and late generation notifications cannot forward twice or replace B', () async {
    final fixture = _fixture();
    const selectedA = WorkspaceState(
      selection: WorkspaceSelection(
        projectId: 'project',
        threadId: 'A',
        needsOpen: false,
      ),
      selectionGeneration: 1,
      sealed: false,
    );
    const selectedB = WorkspaceState(
      selection: WorkspaceSelection(
        projectId: 'project',
        threadId: 'B',
        needsOpen: false,
      ),
      selectionGeneration: 2,
      sealed: false,
    );
    final source = ResourceSource(
      selectedA,
      fixture.selection.budget,
      'test-workspace-notifications',
    );
    final workspace = _WorkspaceNotifications(source.readonly);
    final binding = WorkspaceConversationBinding(
      workspace: workspace,
      demand: fixture.demand,
    );
    addTearDown(() async {
      await binding.close();
      source.close();
    });
    var reentered = false;
    final active = fixture.selection.conversations.repository.active.watch((
      session,
    ) {
      if (session?.threadId == 'B' && !reentered) {
        reentered = true;
        source.publish(selectedB);
      }
    });
    addTearDown(active.cancel);

    binding.start();
    source.publish(selectedA);
    source.publish(selectedB);
    source.publish(selectedB);
    source.publish(selectedA);
    source.publish(selectedB);
    binding.start();

    expect(reentered, isTrue);
    expect(fixture.demand.calls, [
      selectionDelivery(selectedA),
      selectionDelivery(selectedB),
    ]);
    expect(
      fixture.selection.conversations.repository.active.value?.threadId,
      'B',
    );
  });
}

/// Supplies notifications only; all selection/admission behavior under test is
/// the real binding and ConversationRepository, not a second selection reducer.
final class _WorkspaceNotifications implements WorkspaceRepository {
  _WorkspaceNotifications(this.state);
  @override
  final ReadonlyLatestValue<WorkspaceState> state;
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
