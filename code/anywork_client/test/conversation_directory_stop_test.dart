import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:test/test.dart';

import 'support/conversation_stop_native.dart';
import 'support/profile_native_pin.dart';
import 'support/workspace_agent_fixture.dart';

const _origin = ProductReadOrigin(
  ownerEpoch: 'directory-runtime',
  incarnation: 1,
);
const _member = ProductEntityRef(entry: 3, revision: 1);
const _ordinaryFailure = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The native Stop failed after a possible cancellation.',
  retryable: false,
  correlationId: 'directory-stop-after-dispatch',
);
AgentDirectoryEntry _agent({AgentExecution? execution, bool closed = false}) =>
    AgentDirectoryEntry(
      id: 'member',
      threadId: 'child',
      rootThreadId: 'root',
      path: 'root/member',
      parentPath: 'root',
      role: 'executor',
      delegationMode: DelegationMode.automatic,
      delegationPreference: DelegationPreference.balanced,
      frozenModel: null,
      task: 'Bounded child task',
      summary: null,
      depth: 1,
      state: closed
          ? const AgentState.closed()
          : const AgentState.idle(budgetPause: null),
      updatedAt: 1,
      execution: execution,
      canStop: execution != null && !closed,
      awaitingScheduling: false,
    );
AgentDirectoryState _state(
  AgentDirectoryEntry row, {
  int revision = 1,
  ProductReadOrigin origin = _origin,
}) {
  final ref = ProductEntityRef(entry: 3, revision: revision);
  return AgentDirectoryState(
    projection: ProductProjection(
      stamp: profileStamp(origin, revision),
      header: AgentDirectoryHeader(
        source: profileSource(revision),
        reference: AgentDirectoryReadRef(entry: 1, revision: revision),
      ),
      sync: const ResourceSyncState(
        phase: ResourceSyncPhase.ready,
        error: null,
        retryExhausted: false,
      ),
    ),
    sourceStatus: null,
    agents: CollectionMirror.current(
      window: CollectionWindow(
        origin: origin,
        reference: ProductCollectionRef(entry: 2, revision: revision, total: 1),
        entries: [ref],
        rows: {
          3: ReadValue.ready(
            current: Materialized(origin: origin, reference: ref, value: row),
          ),
        },
        continuation: const CollectionContinuation.end(),
        complete: true,
        loading: false,
        error: null,
      ),
    ),
  );
}

void _closeFixture(
  WorkspaceAgentFixture fixture,
  StopCommands commands, {
  List<({OperationTicket<Unit> ticket, OperationFailurePhase phase})>
      retainedOperations =
      const [],
}) {
  addTearDown(() async {
    // Release only genuinely entered native calls after an assertion failure.
    // Normal scenarios still supply their own original reply explicitly.
    for (final call in commands.interrupts.values) {
      if (!call.reply.isCompleted) {
        call.reply.completeError(
          const CommandDispatchFailure.rejected(failure: stopCleanupCancelled),
        );
      }
    }
    expect((await fixture.close()).complete, isTrue);
    // Closing joins dispatch/observation, not the missing receipt or evidence.
    // Unknown/unobserved Registry permits remain owned by their real tickets.
    for (final retained in retainedOperations) {
      expect(retained.ticket.state.value.failurePhase, retained.phase);
      expect(retained.ticket.state.value.isPending, isTrue);
    }
    expect(
      fixture.budget.usage,
      unorderedEquals([
        for (final retained in retainedOperations)
          ResourceUsage(
            kind: ResourceKind.pendingOperation,
            owner: retained.ticket.id.value,
            phase: ResourcePhase.unresolved,
          ),
      ]),
    );
  });
}

void main() {
  test('old busy directory reference becomes a pure no-op only after the actual complete Ready read; partial, loading, future and failed sources reject', () async {
    final commands = StopCommands();
    final fixture = WorkspaceAgentFixture(commands: commands);
    _closeFixture(fixture, commands);
    await fixture.establish(pageLimit: 1);
    final repository = fixture.selection.conversations.repository;
    final source = fixture.workspace.agents;
    final original = source.value.projection.stamp!;
    final records =
        fixture.selection.conversations.operations.observations.records.value;
    expect(
      () => repository.stopDirectoryExecution(
        origin: original,
        member: _member,
        executionId: agentPreparingExecution.id,
      ),
      throwsA(isA<StudioFailure>()),
    );
    expect(commands.interrupts.values, isEmpty);
    await fixture.workspace.loadAgents();

    final gate = Completer<void>();
    final empty = AgentReadMaterial(
      revision: 2,
      entityGate: gate,
      entries: [
        (
          reference: const ProductEntityRef(entry: 3, revision: 2),
          value: preparingAgentEntries.first.value.copyWith(
            execution: null,
            canStop: false,
            updatedAt: 2,
          ),
        ),
        preparingAgentEntries.last,
      ],
    );
    await fixture.publish(empty);
    expect(
      () => repository.stopDirectoryExecution(
        origin: original,
        member: _member,
        executionId: agentPreparingExecution.id,
      ),
      throwsA(isA<StudioFailure>()),
    );
    final loading = fixture.workspace.loadAgents();
    await empty.entityEntered.future;
    expect(
      (source.value.agents as CurrentCollectionMirror<AgentDirectoryEntry>)
          .window
          .loading,
      isTrue,
    );
    final loadingBudget = List.of(fixture.budget.usage);
    expect(
      () => repository.stopDirectoryExecution(
        origin: original,
        member: _member,
        executionId: agentPreparingExecution.id,
      ),
      throwsA(isA<StudioFailure>()),
    );
    expect(fixture.budget.usage, loadingBudget);
    expect(
      fixture.selection.conversations.operations.observations.records.value,
      records,
    );
    expect(commands.interrupts.values, isEmpty);
    gate.complete();
    await loading;

    final budget = List.of(fixture.budget.usage);
    final result = repository.stopDirectoryExecution(
      origin: original,
      member: _member,
      executionId: agentPreparingExecution.id,
    );
    expect(result, isA<StopNoExecution>());
    expect((result as StopNoExecution).threadId, 'root');
    expect(
      repository.stopDirectoryExecution(
        origin: original,
        member: _member,
        executionId: ' \n',
      ),
      isA<StopNoExecution>(),
      reason: 'Only an empty identity is invalid; nonempty opaque identities are not trimmed.',
    );
    expect(
      () => repository.stopDirectoryExecution(
        origin: original,
        member: _member,
        executionId: '',
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'empty execution',
          StudioFailureCode.superseded,
        ),
      ),
    );
    expect(
      () => repository.stopDirectoryExecution(
        origin: original.copyWith(revision: 3),
        member: _member,
        executionId: agentPreparingExecution.id,
      ),
      throwsA(isA<StudioFailure>()),
    );
    expect(
      () => repository.stopDirectoryExecution(
        origin: original,
        member: const ProductEntityRef(entry: 3, revision: 3),
        executionId: agentPreparingExecution.id,
      ),
      throwsA(isA<StudioFailure>()),
    );
    expect(
      fixture.selection.conversations.operations.observations.records.value,
      records,
    );
    expect(fixture.budget.usage, budget);
    expect(commands.interrupts.values, isEmpty);
    final currentStamp = source.value.projection.stamp!;
    final currentMember = empty.entries.first.reference;
    fixture.feed.emit(
      AgentDirectoryFrame.failure(
        identity: profileIdentity(
          fixture.feed.feedId,
          empty.origin,
          ProductResource.agentDirectory,
        ),
        error: const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'The original agent source is offline.',
          retryable: true,
          correlationId: 'directory-stop-source-offline',
        ),
      ),
    );
    await source.waitFor(
      (state) => state.projection.sync.phase == ResourceSyncPhase.failed,
    );
    expect(
      () => repository.stopDirectoryExecution(
        origin: currentStamp,
        member: currentMember,
        executionId: agentPreparingExecution.id,
      ),
      throwsA(isA<StudioFailure>()),
    );
    expect(
      fixture.selection.conversations.operations.observations.records.value,
      records,
    );
    expect(commands.interrupts.values, isEmpty);
    expect(repository.existingSession('root'), isNull);
  });
  for (final nullBeforeReply in [true, false]) {
    test(
      'directory Stop has no selected Session, activation, Timeline, draft or sibling stop (nullBeforeReply=$nullBeforeReply)',
      () async {
        final commands = StopCommands();
        final fixture = WorkspaceAgentFixture(commands: commands);
        _closeFixture(fixture, commands);
        const execution = AgentExecution(
          id: 'child-preparing-before-turn',
          phase: AgentExecutionPhase.preparing,
          turnId: null,
        );
        final child = preparingAgentEntries.last.value.copyWith(
          execution: execution,
          canStop: true,
          awaitingScheduling: false,
        );
        final member = preparingAgentEntries.last.reference;
        await fixture.establish(
          initial: AgentReadMaterial(
            revision: 1,
            entries: [
              preparingAgentEntries.first,
              (reference: member, value: child),
            ],
          ),
        );
        final conversations = fixture.selection.conversations;
        final repository = conversations.repository;
        final source = fixture.workspace.agents;
        final original = source.value.projection.stamp!;
        final selection = fixture.workspace.state.value;
        final live = AgentReadMaterial(
          revision: 2,
          entries: [
            preparingAgentEntries.first,
            (
              reference: const ProductEntityRef(entry: 4, revision: 2),
              value: child.copyWith(updatedAt: 2),
            ),
          ],
        );
        await fixture.publish(live);
        await fixture.workspace.loadAgents();
        expect(fixture.workspace.agents, same(source));
        // Admission accepts the older UI capability, but new work must freeze the
        // actually verified revision 2. An exact revision-1 start would self-reject.
        final ticket = (repository.stopDirectoryExecution(
          origin: original,
          member: member,
          executionId: execution.id,
        ) as StopExecutionOperation).ticket;
        final call = await Future.any([
          commands.interrupts.at(0),
          ticket.result.then<StopInterrupt>(
            (result) => fail(
              'Directory Stop settled before the expected native request: $result',
            ),
          ),
        ]);
        expect(
          (call.threadId, call.executionId, call.operationId),
          ('child', execution.id, ticket.id),
        );
        final receipt = stopReceipt(ticket.id);
        final reply = StopExecutionReply(
          threadId: call.threadId,
          executionId: call.executionId,
          stopped: true,
          receipt: receipt,
        );
        if (!nullBeforeReply) {
          call.reply.complete(reply);
          await ticket.state.waitFor((state) => state.receipt != null);
        }
        final stopping = AgentReadMaterial(
          revision: 3,
          entries: [
            preparingAgentEntries.first,
            (
              reference: const ProductEntityRef(entry: 4, revision: 3),
              value: child.copyWith(
                execution: execution.copyWith(
                  phase: AgentExecutionPhase.stopping,
                ),
                updatedAt: 3,
              ),
            ),
          ],
        );
        await fixture.publish(stopping);
        await fixture.workspace.loadAgents();
        expect(
          (ticket.state.value.observed, ticket.state.value.effective),
          (false, false),
        );
        expect(ticket.state.value.failurePhase, isNull);
        final stoppingRecords =
            conversations.operations.observations.records.value;
        final stoppingBudget = List.of(fixture.budget.usage);
        expect(
          (repository.stopDirectoryExecution(
            origin: original,
            member: member,
            executionId: execution.id,
          ) as StopExecutionOperation).ticket,
          same(ticket),
        );
        expect(
          conversations.operations.observations.records.value,
          stoppingRecords,
        );
        expect(fixture.budget.usage, stoppingBudget);

        final gate = Completer<void>();
        final empty = AgentReadMaterial(
          revision: 4,
          entityGate: gate,
          entries: [
            preparingAgentEntries.first,
            (
              reference: const ProductEntityRef(entry: 4, revision: 4),
              value: child.copyWith(
                execution: null,
                canStop: false,
                state: const AgentStateRead.closed(),
                updatedAt: 4,
              ),
            ),
          ],
        );
        await fixture.publish(empty);
        final loading = fixture.workspace.loadAgents();
        await empty.entityEntered.future;
        expect(
          (source.value.agents as CurrentCollectionMirror<AgentDirectoryEntry>)
              .window
              .loading,
          isTrue,
        );
        expect(
          (ticket.state.value.observed, ticket.state.value.effective),
          (false, false),
        );
        gate.complete();
        await loading;
        expect(fixture.workspace.agents, same(source));
        if (nullBeforeReply) {
          final records = conversations.operations.observations.records.value;
          final budget = List.of(fixture.budget.usage);
          expect(call.reply.isCompleted, isFalse);
          expect(
            (repository.stopDirectoryExecution(
              origin: original,
              member: member,
              executionId: execution.id,
            ) as StopExecutionOperation).ticket,
            same(ticket),
          );
          expect(conversations.operations.observations.records.value, records);
          expect(fixture.budget.usage, budget);
          expect(commands.interrupts.values, hasLength(1));
          expect(
            (
              ticket.state.value.receipt,
              ticket.state.value.observed,
              ticket.state.value.effective,
              ticket.state.value.durable,
            ),
            (null, false, false, false),
          );
          call.reply.complete(reply);
        }
        await ticket.state.waitFor(
          (state) => state.effective || state.failurePhase != null,
        );
        expect(
          (
            ticket.state.value.receipt,
            ticket.state.value.observed,
            ticket.state.value.effective,
            ticket.state.value.durable,
          ),
          (receipt, true, true, false),
        );
        expect(await ticket.result, isA<CommittedCommandResult<Unit>>());
        expect(commands.interrupts.values, hasLength(1));
        expect(repository.active.value, isNull);
        expect(repository.existingSession('root'), isNull);
        expect(repository.existingSession('child'), isNull);
        expect(fixture.workspace.state.value, selection);
        expect(fixture.selection.directory.activations, isEmpty);
        expect(conversations.context.metadataRequests, isEmpty);
        expect(conversations.facets.execution, isEmpty);
        expect(conversations.timeline.requests, isEmpty);
        final root =
            (source.value.agents
                        as CurrentCollectionMirror<AgentDirectoryEntry>)
                    .window
                    .rows[3]
                as ReadyReadValue<AgentDirectoryEntry, ProductEntityRef>;
        expect(
          root.current.value.execution,
          agentPreparingExecution,
          reason: 'Stopping the child must not target its still-busy parent.',
        );
        // No Drafts owner is installed: a directory Stop must not need one.
        expect((await fixture.close()).complete, isTrue);
        expect(fixture.pins.every((pin) => pin.closed), isTrue);
        expect(fixture.budget.usage, isEmpty);
      },
    );
  }

  test('old directory capabilities reject a successor execution, rebuilt member and same-ID new owner; new-work eligibility remains enforced', () async {
    final commands = StopCommands();
    final fixture = WorkspaceAgentFixture(commands: commands);
    _closeFixture(fixture, commands);
    await fixture.establish();
    final repository = fixture.selection.conversations.repository;
    final original = fixture.workspace.agents.value.projection.stamp!;
    final records =
        fixture.selection.conversations.operations.observations.records.value;
    await fixture.publish(
      AgentReadMaterial(
        revision: 2,
        entries: [
          (
            reference: const ProductEntityRef(entry: 3, revision: 2),
            value: preparingAgentEntries.first.value.copyWith(
              execution: stopExecutionValue(8),
              updatedAt: 2,
            ),
          ),
          preparingAgentEntries.last,
        ],
      ),
    );
    await fixture.workspace.loadAgents();
    expect(
      () => repository.stopDirectoryExecution(
        origin: original,
        member: _member,
        executionId: agentPreparingExecution.id,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'successor execution',
          StudioFailureCode.superseded,
        ),
      ),
    );
    await fixture.publish(
      AgentReadMaterial(
        revision: 3,
        entries: [
          (
            reference: const ProductEntityRef(entry: 5, revision: 1),
            value: preparingAgentEntries.first.value.copyWith(updatedAt: 3),
          ),
          preparingAgentEntries.last,
        ],
      ),
    );
    await fixture.workspace.loadAgents();
    expect(
      () => repository.stopDirectoryExecution(
        origin: original,
        member: _member,
        executionId: agentPreparingExecution.id,
      ),
      throwsA(isA<StudioFailure>()),
    );
    final newOwner = AgentReadMaterial(
      origin: const ProductReadOrigin(
        ownerEpoch: 'agent-read-runtime',
        incarnation: 2,
      ),
      revision: 1,
      entries: [
        (
          reference: _member,
          value: preparingAgentEntries.first.value.copyWith(
            canStop: false,
            state: const AgentStateRead.closed(),
          ),
        ),
        preparingAgentEntries.last,
      ],
    );
    await fixture.replaceOwner(newOwner);
    expect(
      () => repository.stopDirectoryExecution(
        origin: original,
        member: _member,
        executionId: agentPreparingExecution.id,
      ),
      throwsA(isA<StudioFailure>()),
    );
    expect(
      () => repository.stopDirectoryExecution(
        origin: newOwner.stamp,
        member: _member,
        executionId: agentPreparingExecution.id,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'new-work eligibility',
          StudioFailureCode.conflict,
        ),
      ),
    );
    expect(
      fixture.selection.conversations.operations.observations.records.value,
      records,
    );
    expect(commands.interrupts.values, isEmpty);
    expect(repository.existingSession('root'), isNull);
    expect(repository.existingSession('child'), isNull);
  });

  for (final lateRejected in [false, true]) {
    test(
      'a replacement owner stops the same member/execution independently while the original native call joins (lateRejected=$lateRejected)',
      () async {
        final commands = StopCommands();
        final fixture = WorkspaceAgentFixture(commands: commands);
        final retained =
            <({OperationTicket<Unit> ticket, OperationFailurePhase phase})>[];
        _closeFixture(fixture, commands, retainedOperations: retained);
        await fixture.establish();
        final conversations = fixture.selection.conversations;
        final repository = conversations.repository;
        final source = fixture.workspace.agents;
        final original = source.value.projection.stamp!;
        final originalTicket = (repository.stopDirectoryExecution(
          origin: original,
          member: _member,
          executionId: agentPreparingExecution.id,
        ) as StopExecutionOperation).ticket;
        final originalCall = await Future.any([
          commands.interrupts.at(0),
          originalTicket.result.then<StopInterrupt>(
            (result) => fail(
              'The original Stop did not enter native dispatch: $result',
            ),
          ),
        ]);
        expect(originalCall.reply.isCompleted, isFalse);
        final replacement = AgentReadMaterial(
          origin: const ProductReadOrigin(
            ownerEpoch: 'agent-read-runtime',
            incarnation: 2,
          ),
          revision: 1,
          entries: preparingAgentEntries,
        );
        await fixture.replaceOwner(replacement);
        expect(fixture.workspace.agents, same(source));
        final current = source.value.projection.stamp!;
        final currentMember =
            (source.value.agents
                    as CurrentCollectionMirror<AgentDirectoryEntry>)
                .window
                .entries
                .singleWhere((reference) => reference.entry == _member.entry);
        final beforeNew = conversations.operations.observations.records.value;
        final beforeStale = List.of(fixture.budget.usage);
        expect(
          () => repository.stopDirectoryExecution(
            origin: original,
            member: _member,
            executionId: agentPreparingExecution.id,
          ),
          throwsA(
            isA<StudioFailure>().having(
              (error) => error.code,
              'old UI source',
              StudioFailureCode.superseded,
            ),
          ),
        );
        expect(conversations.operations.observations.records.value, beforeNew);
        expect(fixture.budget.usage, beforeStale);
        final ticket = (repository.stopDirectoryExecution(
          origin: current,
          member: currentMember,
          executionId: agentPreparingExecution.id,
        ) as StopExecutionOperation).ticket;
        expect(ticket, isNot(same(originalTicket)));
        expect(ticket.id, isNot(originalTicket.id));
        final call = await Future.any([
          commands.interrupts.at(1),
          ticket.result.then<StopInterrupt>(
            (result) => fail(
              'The replacement Stop did not enter native dispatch: $result',
            ),
          ),
        ]);
        expect(
          (
            originalCall.threadId,
            originalCall.executionId,
            originalCall.operationId,
          ),
          ('root', agentPreparingExecution.id, originalTicket.id),
        );
        expect(
          (call.threadId, call.executionId, call.operationId),
          ('root', agentPreparingExecution.id, ticket.id),
        );
        final records = conversations.operations.observations.records.value;
        final budget = List.of(fixture.budget.usage);
        expect(records, hasLength(beforeNew.length + 1));
        expect(
          (repository.stopDirectoryExecution(
            origin: current.copyWith(),
            member: currentMember,
            executionId: agentPreparingExecution.id,
          ) as StopExecutionOperation).ticket,
          same(ticket),
        );
        expect(conversations.operations.observations.records.value, records);
        expect(fixture.budget.usage, budget);
        expect(commands.interrupts.values, hasLength(2));
        final pending = ticket.state.value;
        final originalReceipt = stopReceipt(originalTicket.id);
        if (lateRejected) {
          originalCall.reply.completeError(
            const CommandDispatchFailure.rejected(failure: _ordinaryFailure),
          );
        } else {
          originalCall.reply.complete(
            StopExecutionReply(
              threadId: originalCall.threadId,
              executionId: originalCall.executionId,
              stopped: true,
              receipt: originalReceipt,
            ),
          );
        }
        final originalResult = await originalTicket.result;
        if (lateRejected) {
          expect(
            originalResult,
            isA<RejectedCommandResult<Unit>>().having(
              (result) => result.error,
              'original rejection',
              _ordinaryFailure,
            ),
          );
          expect(originalTicket.state.value.receipt, isNull);
          expect(
            originalTicket.state.value.failurePhase,
            OperationFailurePhase.rejected,
          );
        } else {
          expect(
            originalResult,
            isA<SyncFailedCommandResult<Unit>>().having(
              (result) => result.receipt,
              'original receipt',
              originalReceipt,
            ),
          );
          expect(
            originalTicket.state.value.failurePhase,
            OperationFailurePhase.syncFailed,
          );
          retained.add((
            ticket: originalTicket,
            phase: OperationFailurePhase.syncFailed,
          ));
        }
        expect(
          (
            originalTicket.state.value.observed,
            originalTicket.state.value.effective,
            originalTicket.state.value.durable,
          ),
          (false, false, false),
        );
        expect(
          ticket.state.value,
          same(pending),
          reason: 'A late result belongs only to the old owner/operation.',
        );
        expect(call.reply.isCompleted, isFalse);
        expect(
          conversations.operations.observations.latest('stop:root')!.id,
          ticket.id,
        );
        expect(
          source.observerCount,
          1,
          reason: 'Only the replacement Stop still owns a directory watch.',
        );
        expect(
          fixture.budget.usage.where(
            (usage) => usage.kind == ResourceKind.pendingOperation,
          ),
          unorderedEquals([
            ResourceUsage(
              kind: ResourceKind.pendingOperation,
              owner: ticket.id.value,
              phase: ResourcePhase.active,
            ),
            ResourceUsage(
              kind: ResourceKind.pendingOperation,
              owner: 'directory-stop:root:${agentPreparingExecution.id}',
              phase: ResourcePhase.active,
            ),
            if (!lateRejected)
              ResourceUsage(
                kind: ResourceKind.pendingOperation,
                owner: originalTicket.id.value,
                phase: ResourcePhase.unresolved,
              ),
          ]),
        );
        final afterLate = conversations.operations.observations.records.value;
        final afterLateBudget = List.of(fixture.budget.usage);
        // The rejected old work is now released. Pruning it must not evict the
        // replacement work which has the same source object, entry and execution.
        expect(
          (repository.stopDirectoryExecution(
            origin: current,
            member: currentMember,
            executionId: agentPreparingExecution.id,
          ) as StopExecutionOperation).ticket,
          same(ticket),
        );
        expect(conversations.operations.observations.records.value, afterLate);
        expect(fixture.budget.usage, afterLateBudget);
        expect(commands.interrupts.values, hasLength(2));
        final receipt = stopReceipt(ticket.id);
        call.reply.complete(
          StopExecutionReply(
            threadId: call.threadId,
            executionId: call.executionId,
            stopped: true,
            receipt: receipt,
          ),
        );
        await ticket.state.waitFor(
          (state) => state.receipt != null || state.failurePhase != null,
        );
        expect(
          (
            ticket.state.value.receipt,
            ticket.state.value.observed,
            ticket.state.value.effective,
          ),
          (receipt, false, false),
        );
        await fixture.publish(
          AgentReadMaterial(
            origin: replacement.origin,
            revision: 2,
            entries: [
              (
                reference: const ProductEntityRef(entry: 3, revision: 2),
                value: preparingAgentEntries.first.value.copyWith(
                  execution: null,
                  canStop: false,
                  updatedAt: 2,
                ),
              ),
              preparingAgentEntries.last,
            ],
          ),
        );
        await fixture.workspace.loadAgents();
        await ticket.state.waitFor(
          (state) => state.effective || state.failurePhase != null,
        );
        expect(
          await ticket.result,
          isA<CommittedCommandResult<Unit>>().having(
            (result) => result.receipt,
            'replacement receipt',
            receipt,
          ),
        );
        expect(
          (
            ticket.state.value.observed,
            ticket.state.value.effective,
            ticket.state.value.durable,
          ),
          (true, true, false),
        );
        expect(await originalTicket.result, same(originalResult));
        expect(
          (
            originalTicket.state.value.observed,
            originalTicket.state.value.effective,
          ),
          (false, false),
        );
        expect(commands.interrupts.values, hasLength(2));
        expect((await fixture.close()).complete, isTrue);
        expect(fixture.pins.every((pin) => pin.closed), isTrue);
        expect(repository.active.value, isNull);
        expect(repository.existingSession('root'), isNull);
        expect(conversations.context.metadataRequests, isEmpty);
        expect(conversations.facets.execution, isEmpty);
        expect(conversations.timeline.requests, isEmpty);
      },
    );
  }

  test('a dispatched directory Stop remains Unknown and reuses its ticket after the same owner materializes no execution', () async {
    final commands = StopCommands();
    final fixture = WorkspaceAgentFixture(commands: commands);
    final retained =
        <({OperationTicket<Unit> ticket, OperationFailurePhase phase})>[];
    _closeFixture(fixture, commands, retainedOperations: retained);
    await fixture.establish();
    final conversations = fixture.selection.conversations;
    final repository = conversations.repository;
    final source = fixture.workspace.agents;
    final original = source.value.projection.stamp!;
    final ticket = (repository.stopDirectoryExecution(
      origin: original,
      member: _member,
      executionId: agentPreparingExecution.id,
    ) as StopExecutionOperation).ticket;
    final call = await Future.any([
      commands.interrupts.at(0),
      ticket.result.then<StopInterrupt>(
        (result) => fail('The Stop did not enter native dispatch: $result'),
      ),
    ]);
    expect(
      (call.threadId, call.executionId, call.operationId),
      ('root', agentPreparingExecution.id, ticket.id),
    );
    // An ordinary post-dispatch failure is not native evidence of rejection.
    call.reply.completeError(_ordinaryFailure);
    final result = await ticket.result;
    expect(
      result,
      isA<UnknownOutcomeCommandResult<Unit>>().having(
        (result) => result.error,
        'original failure',
        _ordinaryFailure,
      ),
    );
    retained.add((ticket: ticket, phase: OperationFailurePhase.unknownOutcome));
    final unknown = ticket.state.value;
    expect(unknown.failurePhase, OperationFailurePhase.unknownOutcome);
    expect(
      (
        unknown.receipt,
        unknown.acknowledged,
        unknown.observed,
        unknown.effective,
        unknown.durable,
      ),
      (null, false, false, false, false),
    );
    expect(unknown.isPending, isTrue);
    await fixture.publish(
      AgentReadMaterial(
        revision: 2,
        entries: [
          (
            reference: const ProductEntityRef(entry: 3, revision: 2),
            value: preparingAgentEntries.first.value.copyWith(
              execution: null,
              canStop: false,
              updatedAt: 2,
            ),
          ),
          preparingAgentEntries.last,
        ],
      ),
    );
    await fixture.workspace.loadAgents();
    final records = conversations.operations.observations.records.value;
    final budget = List.of(fixture.budget.usage);
    expect(
      (repository.stopDirectoryExecution(
        origin: original,
        member: _member,
        executionId: agentPreparingExecution.id,
      ) as StopExecutionOperation).ticket,
      same(ticket),
    );
    expect(conversations.operations.observations.records.value, records);
    expect(fixture.budget.usage, budget);
    expect(ticket.state.value, same(unknown));
    expect(await ticket.result, same(result));
    expect(commands.interrupts.values, hasLength(1));
    expect(
      fixture.budget.usage.where(
        (usage) => usage.kind == ResourceKind.pendingOperation,
      ),
      [
        ResourceUsage(
          kind: ResourceKind.pendingOperation,
          owner: ticket.id.value,
          phase: ResourcePhase.unresolved,
        ),
      ],
    );
    expect((await fixture.close()).complete, isTrue);
    expect(ticket.state.value, same(unknown));
    expect(await ticket.result, same(result));
    expect(fixture.pins.every((pin) => pin.closed), isTrue);
    expect(repository.active.value, isNull);
    expect(repository.existingSession('root'), isNull);
    expect(conversations.context.metadataRequests, isEmpty);
    expect(conversations.facets.execution, isEmpty);
    expect(conversations.timeline.requests, isEmpty);
  });

  test('closed members remain navigable in canonical membership but are excluded from active count', () {
    final row = _agent(closed: true);
    final rows = AgentDirectoryQueries.forRoot(
      rootThreadId: 'root',
      directory: _state(row),
    );
    expect(rows, [row]);
    expect(AgentDirectoryQueries.activeCount(rows), 0);
    expect(AgentDirectoryQueries.menuOrder(rows), [row]);
  });
}
