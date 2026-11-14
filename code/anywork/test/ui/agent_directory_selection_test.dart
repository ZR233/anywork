import '../support/chat_fixtures.dart';

import '../support/test_statistics_feed.dart';

import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/shell/shell_view.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'visible ACP membership never admits Native content or state feeds',
    () async {
      final fixture = await _fixture(acpRoot: true);
      final graph = fixture.graph;
      final row = fixture.root;
      final metadata = graph.client.threadDirectory.observeThread(row.threadId);
      addTearDown(metadata.release);
      await metadata.state.waitFor((state) => state.frame?.row != null);
      graph.setConversationPageVisible(true);
      graph.client.selection.selectThread(
        workspaceId: row.workspaceId,
        threadId: row.threadId,
      );
      expect(graph.client.conversations.visibleThreadId.value, isNull);
      expect(graph.client.conversations.existingSession(row.threadId), isNull);
      expect(fixture.transport.stateReads, isEmpty);
      expect(fixture.transport.timelineReaders, isEmpty);
      expect(graph.client.drafts.existingComposer(row.threadId), isNotNull);
    },
  );

  test('explicit cold selection reads only its metadata and opens only its history', () async {
    final fixture = await _fixture();
    final client = fixture.graph.client;
    // A member of another root is not a target of the current root's menu.
    await client.directoryCommands.selectAgentThread(fixture.other.threadId);
    expect(fixture.transport.metadataReads, isEmpty);
    expect(client.conversations.sessionStates, isEmpty);

    await client.directoryCommands.selectAgentThread(fixture.child.threadId);
    await _expectSelectedHistory(fixture);
  });

  test(
    'shell resolves child root metadata through the root agent thread ID',
    () async {
      final fixture = await _fixture(distinctRootIdentity: true);
      final graph = fixture.graph;
      final root = fixture.root;
      final child = fixture.child;
      expect((root.sessionId, root.agentId, root.threadId), ('S', 'A', 'T'));
      expect(child.parentAgentId, 'A');
      expect(child.sessionId, 'S');
      expect(child.threadId, 'C');
      expect(
        fixture.agents.singleWhere((agent) => agent.agentId == 'A').threadId,
        'T',
      );

      final childObservation = graph.client.threadDirectory.observeThread(
        child.threadId,
      );
      await childObservation.state
          .waitFor((state) => state.frame?.row != null)
          .timeout(const Duration(seconds: 5));
      addTearDown(childObservation.release);

      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      addTearDown(container.dispose);
      final header = container.listen(headerViewProvider, (_, _) {});
      final workspace = container.listen(
        conversationWorkspaceProvider(root.threadId),
        (_, _) {},
      );
      addTearDown(header.close);
      addTearDown(workspace.close);

      expect(header.read().selectedRootRow?.threadId, 'T');
      expect(
        container
            .read(conversationWorkspaceProvider(root.threadId))
            ?.rootRow
            .threadId,
        'T',
      );

      graph.client.selection.restoreStartup(
        workspaceId: root.workspaceId,
        threadId: 'C',
        needsOpen: true,
      );
      await container.pump();
      expect(header.read().selectedRootRow?.threadId, 'T');
      expect(container.read(sidebarSelectedRootThreadIdProvider), 'T');
      expect(container.read(sidebarThreadViewProvider('T')).selected, isTrue);
      expect(container.read(sidebarThreadViewProvider('C')).selected, isFalse);
      expect(
        container.read(conversationWorkspaceProvider('C'))?.rootRow.threadId,
        'T',
      );
      expect(fixture.transport.metadataReads, isNot(contains('S')));
      expect(fixture.transport.metadataReads, contains('C'));
    },
  );

  test(
    'restored cold selection stays unopened until its explicit open command',
    () async {
      final fixture = await _fixture();
      final client = fixture.graph.client;
      client.selection.restoreStartup(
        workspaceId: fixture.root.workspaceId,
        threadId: fixture.child.threadId,
        needsOpen: true,
      );
      expect(fixture.transport.metadataReads, isEmpty);
      expect(client.conversations.sessionStates, isEmpty);

      await client.directoryCommands.openSelectedThread();
      await _expectSelectedHistory(fixture);
    },
  );

  test('cold metadata failures and wrong identity cannot change selection or directory', () async {
    final fixture = await _fixture();
    final client = fixture.graph.client;
    final wrongProject = fixture.child.copyWith(
      workspaceId: 'foreign-project',
      workspacePath: '/foreign',
    );
    final wrongRoot = fixture.child.copyWith(
      parentAgentId: fixture.other.threadId,
      sessionId: fixture.other.threadId,
    );
    for (final response in [
      (row: fixture.other, frameThreadId: fixture.other.threadId),
      (row: wrongRoot, frameThreadId: fixture.child.threadId),
      (row: wrongProject, frameThreadId: fixture.child.threadId),
    ]) {
      fixture.transport.frameThreadIdOverride = response.frameThreadId;
      fixture.transport.respond = (_) async => response.row;
      await expectLater(
        client.directoryCommands.selectAgentThread(fixture.child.threadId),
        throwsA(
          isA<StudioFailure>().having(
            (error) => error.code,
            'code',
            StudioFailureCode.protocol,
          ),
        ),
      );
      expect(client.selection.state.selectedThreadId, fixture.root.threadId);
      expect(client.threadDirectory.observedWindows, isEmpty);
      expect(client.conversations.sessionStates, isEmpty);
    }
    fixture.transport.respond = (_) async =>
        throw StateError('saved metadata unavailable');
    await expectLater(
      client.directoryCommands.selectAgentThread(fixture.child.threadId),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.internal,
        ),
      ),
    );
    expect(client.selection.state.selectedThreadId, fixture.root.threadId);
    expect(client.threadDirectory.observedWindows, isEmpty);
    expect(fixture.transport.stateReads, isEmpty);
    expect(fixture.transport.timelineReaders, isEmpty);
  });

  test(
    'late cold metadata cannot override navigation or removed membership',
    () async {
      for (final invalidation in [
        'same-root-selection',
        'root',
        'project',
        'membership',
      ]) {
        final fixture = await _fixture();
        final client = fixture.graph.client;
        final entered = Completer<void>();
        final reply = Completer<SessionDirectoryRow>();
        fixture.transport.respond = (_) {
          entered.complete();
          return reply.future;
        };
        final pending = client.directoryCommands.selectAgentThread(
          fixture.child.threadId,
        );
        await entered.future;
        switch (invalidation) {
          case 'same-root-selection':
            client.selection.restoreStartup(
              workspaceId: fixture.root.workspaceId,
              threadId: 'cold-sibling',
              needsOpen: true,
            );
          case 'root':
            client.selection.restoreStartup(
              workspaceId: fixture.other.workspaceId,
              threadId: fixture.other.threadId,
              needsOpen: true,
            );
          case 'project':
            client.selection.selectProject('foreign-project');
          case 'membership':
            client.project.applyAgentDirectory(
              AgentDirectoryState(
                revision: 2,
                values: fixture.agents
                    .where((agent) => agent.threadId != fixture.child.threadId)
                    .toList(),
              ),
            );
        }
        final newerSelection = client.selection.state;
        reply.complete(fixture.child);
        await pending;
        expect(client.selection.state, newerSelection, reason: invalidation);
        expect(
          client.threadDirectory.observedWindows,
          isEmpty,
          reason: invalidation,
        );
        expect(
          client.conversations.sessionStates,
          isEmpty,
          reason: invalidation,
        );
        expect(fixture.transport.metadataReads, [fixture.child.threadId]);
        expect(fixture.transport.stateReads, isEmpty, reason: invalidation);
        expect(
          fixture.transport.timelineReaders,
          isEmpty,
          reason: invalidation,
        );
      }
    },
  );

  test('a newer public cold selection invalidates the older queued read before publication', () async {
    await _expectLatestQueuedColdSelection();
  });

  test('superseded cold read errors are ignored but the latest read failure remains visible', () async {
    await _expectLatestQueuedColdSelection(oldFails: true);
    await _expectLatestQueuedColdSelection(newFails: true);
  });

  test('all queued directory navigation entries retire an older cold read at receipt', () async {
    for (final action in [
      'root',
      'project',
      'project-failure',
      'new-session',
      'startup-open',
      'restore-failure',
      'open-project',
      'open-remote',
    ]) {
      final fixture = await _fixture();
      final client = fixture.graph.client;
      final entered = Completer<void>();
      final reply = Completer<SessionDirectoryRow>();
      fixture.transport.respond = (threadId) {
        if (threadId == fixture.child.threadId) {
          entered.complete();
          return reply.future;
        }
        return fixture.transport.savedThreads().then(
          (rows) => rows.singleWhere((row) => row.threadId == threadId),
        );
      };
      final oldNavigation = _outcome(
        client.directoryCommands.selectAgentThread(fixture.child.threadId),
      );
      addTearDown(() async {
        if (!reply.isCompleted) reply.complete(fixture.child);
        await oldNavigation;
      });
      await entered.future;
      final commands = client.directoryCommands;
      final next = _outcome(switch (action) {
        'root' => commands.selectThread(fixture.other.threadId),
        'project' => commands.selectProject(fixture.root.workspaceId),
        'project-failure' => commands.selectProject('foreign-project'),
        'new-session' => commands.beginNewThread(),
        'startup-open' => commands.openSelectedThread(),
        'restore-failure' => commands.restoreThread(fixture.root.threadId),
        'open-project' => commands.openProject('/saved/another-project'),
        'open-remote' =>
          commands
              .openRemoteProject('arm-dev', '/saved/remote')
              .then<void>((_) {}),
        _ => throw StateError('Unknown test action $action'),
      });
      reply.complete(fixture.child);
      expect(await oldNavigation, isNull, reason: action);
      final error = await next;
      expect(
        error,
        action.endsWith('-failure') ? isStateError : isNull,
        reason: action,
      );
      expect(client.findThread(fixture.child.threadId), isNull, reason: action);
      expect(
        client.conversations.existingSession(fixture.child.threadId),
        isNull,
        reason: action,
      );
      expect(
        client.selection.state.selectedThreadId,
        isNot(fixture.child.threadId),
        reason: action,
      );
      expect(
        fixture.transport.stateReads,
        isNot(contains(fixture.child.threadId)),
        reason: action,
      );
      expect(
        fixture.transport.timelineReaders.map((timeline) => timeline.threadId),
        isNot(contains(fixture.child.threadId)),
        reason: action,
      );
      expect(
        fixture.transport.metadataReads,
        action == 'root'
            ? [fixture.child.threadId, fixture.other.threadId]
            : [fixture.child.threadId],
        reason: action,
      );
      expect(fixture.transport.submitCalls, 0, reason: action);
    }
  });

  test(
    'project-scoped new session cannot revive a superseded project activation',
    () async {
      final fixture = await _fixture();
      final client = fixture.graph.client;
      final entered = Completer<void>();
      final activation = Completer<void>();
      fixture.transport.onActivate = (_) {
        entered.complete();
        return activation.future;
      };
      final draftNavigation = _outcome(
        client.directoryCommands.beginNewThread(workspaceId: 'foreign-project'),
      );
      addTearDown(() async {
        if (!activation.isCompleted) activation.complete();
        await draftNavigation;
      });
      await entered.future;
      final newer = client.directoryCommands.selectThread(
        fixture.other.threadId,
      );
      activation.complete();
      expect(await draftNavigation, isNull);
      await newer;
      fixture.graph.timeline.updateReadDemand(chatDemand);
      fixture.graph.setConversationPageVisible(true);
      await timelineReady(fixture.graph.timeline, fixture.other.threadId);
      expect(
        client.selection.state.selectedProjectId,
        fixture.other.workspaceId,
      );
      expect(client.selection.state.selectedThreadId, fixture.other.threadId);
      expect(
        client.conversations.sessionStates.map((state) => state.threadId),
        [fixture.other.threadId],
      );
      expect(fixture.transport.stateReads, [fixture.other.threadId]);
    },
  );

  test('new Thread creation and directory reads share the latest navigation boundary', () async {
    final fixture = await _fixture();
    final sibling = _secondColdChild(fixture);
    final client = fixture.graph.client;
    final oldEntered = Completer<void>();
    final oldReply = Completer<SessionDirectoryRow>();
    final newEntered = Completer<void>();
    final newReply = Completer<SessionDirectoryRow>();
    fixture.transport.respond = (id) {
      if (id == fixture.child.threadId) {
        if (!oldEntered.isCompleted) oldEntered.complete();
        return oldReply.future;
      }
      if (!newEntered.isCompleted) newEntered.complete();
      return newReply.future;
    };
    final creation = StreamController<NewThreadStartEvent>();
    fixture.transport.newThreadEvents = creation.stream;
    final oldNavigation = _outcome(
      client.directoryCommands.selectAgentThread(fixture.child.threadId),
    );
    await oldEntered.future;
    final created = client.threadCommands.submitNewThread(
      workspaceId: fixture.root.workspaceId,
      input: const StudioPromptInput(
        inputId: 'create-input',
        text: 'A new root',
        attachmentDraftIds: [],
      ),
      mode: ThreadModeId.simple,
      route: const ModeModelRouteView(
        modeId: ThreadModeId.simple,
        accountId: 'saved-account',
        modelId: 'saved-model',
        effort: 'high',
      ),
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      onProgress: (_) {},
    );
    addTearDown(() async {
      if (!oldReply.isCompleted) oldReply.complete(fixture.child);
      if (!newReply.isCompleted) newReply.complete(sibling);
      await creation.close();
      await oldNavigation;
    });
    await fixture.transport.newThreadEntered.future;
    oldReply.complete(fixture.child);
    expect(await oldNavigation, isNull);
    expect(client.threadDirectory.observedWindows, isEmpty);
    expect(client.conversations.sessionStates, isEmpty);

    final newer = client.directoryCommands.selectAgentThread(sibling.threadId);
    await newEntered.future;
    // Creation is a real accepted operation, but its automatic navigation is
    // obsolete even though the newer metadata read has not changed selection.
    final result = StartNewThreadResult(
      thread: _nativeThreadOf(fixture.root),
      receipt: SubmitPromptReceipt(
        threadId: fixture.root.threadId,
        inputId: 'create-input',
        cursor: 1,
      ),
    );
    creation.add(NewThreadStartSucceeded(result));
    expect(await created, same(result));
    expect(client.selection.state.needsOpen, isTrue);
    expect(client.conversations.sessionStates, isEmpty);
    newReply.complete(sibling);
    await newer;
    fixture.graph.timeline.updateReadDemand(chatDemand);
    fixture.graph.setConversationPageVisible(true);
    await client.conversations.visibleThreadId.waitFor(
      (value) => value == sibling.threadId,
    );
    await timelineReady(fixture.graph.timeline, sibling.threadId);
    expect(client.selection.state.selectedThreadId, sibling.threadId);
    expect(client.conversations.sessionStates.map((state) => state.threadId), [
      sibling.threadId,
    ]);
    expect(fixture.transport.stateReads, [sibling.threadId]);
    expect(client.findThread(fixture.child.threadId), isNull);
  });

  test('the agent directory publishes each row execution and stop qualification, and a stale page cannot replace it', () async {
    final fixture = await _fixture();
    final client = fixture.graph.client;
    final row = fixture.agents.firstWhere(
      (agent) => agent.threadId == fixture.child.threadId,
    );
    final execution = AgentExecutionView(
      id: 'child-execution',
      phase: AgentExecutionPhase.running,
      turnId: 'child-turn',
    );
    expect(
      client.project.applyAgentDirectory(
        AgentDirectoryState(
          revision: 3,
          values: [
            for (final agent in fixture.agents)
              if (agent.threadId == fixture.child.threadId)
                StudioAgentView(
                  agentId: agent.agentId,
                  sessionId: agent.sessionId,
                  parentAgentId: agent.parentAgentId,
                  threadId: agent.threadId,
                  role: agent.role,
                  task: agent.task,
                  summary: agent.summary,
                  delegationMode: agent.delegationMode,
                  delegationPreference: agent.delegationPreference,
                  frozenModel: agent.frozenModel,
                  state: agent.state,
                  updatedAt: agent.updatedAt,
                  execution: execution,
                  canStop: true,
                  awaitingScheduling: true,
                )
              else
                agent,
          ],
        ),
      ),
      isTrue,
    );
    final published = client.project.state.agents!.values.firstWhere(
      (agent) => agent.threadId == fixture.child.threadId,
    );
    expect(published.execution, execution);
    expect(published.canStop, isTrue);
    expect(
      published.awaitingScheduling,
      isTrue,
      reason: 'A member with an unclaimed continuation waits for its parent',
    );
    expect(
      published.state,
      row.state,
      reason: 'The canonical member state is not derived from the execution',
    );
    expect(
      published == row,
      isFalse,
      reason: 'Execution, stop qualification and scheduling fact take part in equality',
    );
    // A page older than the published revision cannot roll the row back.
    expect(
      client.project.applyAgentDirectory(
        AgentDirectoryState(
          revision: 2,
          values: [
            for (final agent in fixture.agents)
              if (agent.threadId == fixture.child.threadId)
                StudioAgentView(
                  agentId: agent.agentId,
                  sessionId: agent.sessionId,
                  parentAgentId: agent.parentAgentId,
                  threadId: agent.threadId,
                  role: agent.role,
                  task: agent.task,
                  delegationMode: agent.delegationMode,
                  delegationPreference: agent.delegationPreference,
                  state: agent.state,
                  updatedAt: agent.updatedAt,
                  canStop: false,
                  awaitingScheduling: false,
                )
              else
                agent,
          ],
        ),
      ),
      isFalse,
    );
    expect(
      client.project.state.agents!.values
          .firstWhere((agent) => agent.threadId == fixture.child.threadId)
          .execution,
      execution,
    );
    expect(
      client.project.state.agents!.values
          .firstWhere((agent) => agent.threadId == fixture.child.threadId)
          .canStop,
      isTrue,
    );
    expect(
      client.project.state.agents!.values
          .firstWhere((agent) => agent.threadId == fixture.child.threadId)
          .awaitingScheduling,
      isTrue,
      reason: 'A stale page never clears the newer scheduling fact',
    );
    // A newer page reports the member was scheduled: the value change is
    // published, and it is independent from the stop qualification.
    expect(
      client.project.applyAgentDirectory(
        AgentDirectoryState(
          revision: 4,
          values: [
            for (final agent in fixture.agents)
              if (agent.threadId == fixture.child.threadId)
                StudioAgentView(
                  agentId: agent.agentId,
                  sessionId: agent.sessionId,
                  parentAgentId: agent.parentAgentId,
                  threadId: agent.threadId,
                  role: agent.role,
                  task: agent.task,
                  delegationMode: agent.delegationMode,
                  delegationPreference: agent.delegationPreference,
                  state: agent.state,
                  updatedAt: agent.updatedAt,
                  execution: execution,
                  canStop: true,
                  awaitingScheduling: false,
                )
              else
                agent,
          ],
        ),
      ),
      isTrue,
    );
    final scheduled = client.project.state.agents!.values.firstWhere(
      (agent) => agent.threadId == fixture.child.threadId,
    );
    expect(scheduled.awaitingScheduling, isFalse);
    expect(
      scheduled.canStop,
      isTrue,
      reason: 'Scheduling state never derives the stop qualification',
    );
    expect(scheduled == published, isFalse);
    // The stop request itself is a phase transition of the same execution.
    final stopping = AgentExecutionView(
      id: 'child-execution',
      phase: AgentExecutionPhase.stopping,
      turnId: 'child-turn',
    );
    expect(stopping.isStopping, isTrue);
    expect(stopping == execution, isFalse);
    // Listing never opens a member: the row facts come from the directory.
    expect(client.conversations.sessionStates, isEmpty);
    expect(client.selection.state.selectedThreadId, fixture.root.threadId);
  });
}

Future<Object?> _outcome(Future<void> operation) => operation.then<Object?>(
  (_) => null,
  onError: (Object error, StackTrace _) => error,
);

Future<void> _expectLatestQueuedColdSelection({
  bool oldFails = false,
  bool newFails = false,
}) async {
  final fixture = await _fixture();
  final sibling = _secondColdChild(fixture);
  final client = fixture.graph.client;
  final oldEntered = Completer<void>();
  final newEntered = Completer<void>();
  final oldReply = Completer<SessionDirectoryRow>();
  final newReply = Completer<SessionDirectoryRow>();
  final oldError = StateError('superseded metadata read failed');
  final newError = StateError('latest metadata read failed');
  fixture.transport.respond = (id) {
    if (id == fixture.child.threadId) {
      if (!oldEntered.isCompleted) oldEntered.complete();
      return oldReply.future;
    }
    if (id == sibling.threadId) {
      if (!newEntered.isCompleted) newEntered.complete();
      return newReply.future;
    }
    throw StateError('Unexpected metadata read: $id');
  };
  final oldNavigation = _outcome(
    client.directoryCommands.selectAgentThread(fixture.child.threadId),
  );
  await oldEntered.future;
  // This is the same public command used by the real menu, not a store write.
  final newNavigation = _outcome(
    client.directoryCommands.selectAgentThread(sibling.threadId),
  );
  addTearDown(() async {
    if (!oldReply.isCompleted) oldReply.complete(fixture.child);
    if (!newReply.isCompleted) newReply.complete(sibling);
    await Future.wait([oldNavigation, newNavigation]);
  });
  if (oldFails) {
    oldReply.completeError(oldError);
  } else {
    oldReply.complete(fixture.child);
  }
  expect(
    await oldNavigation,
    isNull,
    reason: 'Superseded errors must not reach the menu error handler',
  );
  await newEntered.future;
  expect(client.selection.state.selectedThreadId, fixture.root.threadId);
  expect(
    client.threadDirectory.observedWindows,
    isEmpty,
    reason: 'An old read must not publish while the new command is still queued/reading',
  );
  expect(client.conversations.sessionStates, isEmpty);
  expect(fixture.transport.stateReads, isEmpty);
  expect(fixture.transport.timelineReaders, isEmpty);
  if (newFails) {
    newReply.completeError(newError);
    expect(
      await newNavigation,
      isA<StudioFailure>().having(
        (error) => error.code,
        'code',
        StudioFailureCode.internal,
      ),
    );
    expect(client.selection.state.selectedThreadId, fixture.root.threadId);
    expect(client.threadDirectory.observedWindows, isEmpty);
    expect(client.conversations.sessionStates, isEmpty);
    expect(fixture.transport.stateReads, isEmpty);
    expect(fixture.transport.timelineReaders, isEmpty);
  } else {
    newReply.complete(sibling);
    expect(await newNavigation, isNull);
    fixture.graph.timeline.updateReadDemand(chatDemand);
    fixture.graph.setConversationPageVisible(true);
    await client.conversations.visibleThreadId.waitFor(
      (value) => value == sibling.threadId,
    );
    final session = client.conversations.existingSession(sibling.threadId)!;
    await session.source.waitFor((state) => state.workspace != null);
    await timelineReady(fixture.graph.timeline, session.threadId);
    expect(client.selection.state.selectedThreadId, sibling.threadId);
    expect(client.threadDirectory.observedWindows, isEmpty);
    expect(client.conversations.sessionStates.map((state) => state.threadId), [
      sibling.threadId,
    ]);
    expect(fixture.transport.stateReads, [sibling.threadId]);
    expect(
      fixture.transport.timelineReaders.map((timeline) => timeline.threadId),
      [sibling.threadId],
    );
  }
  expect(client.findThread(fixture.child.threadId), isNull);
  expect(client.conversations.existingSession(fixture.child.threadId), isNull);
  expect(fixture.transport.metadataReads.toSet(), {
    fixture.child.threadId,
    sibling.threadId,
  }, reason: 'Only explicitly addressed Thread IDs use metadata observations');
  expect(fixture.transport.submitCalls, 0);
  expect(fixture.transport.restoreCalls, 0);
}

/// 创建回执仍携带 Native Thread 投影；测试用目录行事实重建等价的执行行。
StudioThread _nativeThreadOf(SessionDirectoryRow row) {
  final backend = row.backend;
  if (backend is! NativeAgentBackendView) {
    throw StateError('Native fixture requires a Native backend');
  }
  return StudioThread(
    id: row.threadId,
    workspaceId: row.workspaceId,
    title: row.title,
    mode: row.mode,
    delegationMode: row.delegationMode,
    delegationPreference: row.delegationPreference,
    frozenModel: row.frozenModel,
    workspaceMode: row.workspaceMode,
    workspacePath: row.workspacePath,
    status: backend.status,
    updatedAt: row.updatedAt,
  );
}

// Reuse a second real Demo history as the external saved sibling fixture.
// Client remains responsible for canonical membership, reads and navigation.
SessionDirectoryRow _secondColdChild(_ColdFixture fixture) {
  final sibling = fixture.other.copyWith(
    parentAgentId: fixture.root.agentId,
    sessionId: fixture.root.sessionId,
    role: 'executor',
  );
  fixture.transport.savedThreadOverrides[sibling.threadId] = sibling;
  fixture.graph.client.project.applyAgentDirectory(
    AgentDirectoryState(
      revision: 2,
      values: [
        ...fixture.agents.where((agent) => agent.threadId != sibling.threadId),
        StudioAgentView(
          agentId: sibling.agentId,
          sessionId: sibling.sessionId,
          parentAgentId: fixture.root.agentId,
          threadId: sibling.threadId,
          role: sibling.role,
          task: sibling.title,
          state: const IdleStudioAgent(),
          delegationMode: sibling.delegationMode,
          delegationPreference: sibling.delegationPreference,
          frozenModel: sibling.frozenModel,
          updatedAt: sibling.updatedAt,
        ),
      ],
    ),
  );
  return sibling;
}

Future<void> _expectSelectedHistory(_ColdFixture fixture) async {
  final client = fixture.graph.client;
  expect(
    fixture.transport.timelineReaders,
    isEmpty,
    reason: '选择身份本身不产生 GUI 内容需求',
  );
  fixture.graph.timeline.updateReadDemand(chatDemand);
  fixture.graph.setConversationPageVisible(true);
  await client.conversations.visibleThreadId.waitFor(
    (value) => value == fixture.child.threadId,
  );
  final session = client.conversations.existingSession(fixture.child.threadId)!;
  await session.source.waitFor((state) => state.workspace != null);
  await timelineReady(fixture.graph.timeline, session.threadId);
  expect(client.selection.state.selectedThreadId, fixture.child.threadId);
  expect(client.selection.state.needsOpen, isFalse);
  expect(
    (session.state.directoryRow!.backend as NativeAgentBackendView).status,
    ThreadStatusView.closed,
    reason: '目录行的 typed 状态是关闭事实的来源',
  );
  expect(
    client.threadDirectory.observedWindows,
    isEmpty,
    reason: 'Cold ID navigation does not create a broad list demand',
  );
  expect(client.conversations.sessionStates.map((state) => state.threadId), [
    fixture.child.threadId,
  ]);
  expect(fixture.transport.metadataReads.toSet(), {
    fixture.child.threadId,
  }, reason: 'The selected history observes only its own Thread ID');
  expect(fixture.transport.stateReads, [fixture.child.threadId]);
  expect(
    fixture.transport.timelineReaders.map((timeline) => timeline.threadId),
    [fixture.child.threadId],
  );
  expect(fixture.transport.submitCalls, 0);
  expect(fixture.transport.restoreCalls, 0);
}

Future<_ColdFixture> _fixture({
  bool distinctRootIdentity = false,
  bool acpRoot = false,
}) async {
  final transport = _ColdSelectionTransport();
  final saved = await transport.savedThreads();
  var root = distinctRootIdentity
      ? saved[0].copyWith(sessionId: 'S', agentId: 'A', threadId: 'T')
      : saved[0];
  if (acpRoot) {
    root = root.copyWith(
      mode: null,
      backend: const AcpAgentBackendView(
        reference: AcpSessionReferenceView(
          accountId: 'custom-acp',
          acpSessionId: 'external-session',
          cwd: '/project',
        ),
      ),
    );
  }
  final child = distinctRootIdentity
      ? saved[1].copyWith(
          backend: (saved[1].backend as NativeAgentBackendView).copyWith(
            status: ThreadStatusView.closed,
          ),
          threadId: 'C',
          sessionId: root.sessionId,
          parentAgentId: root.agentId,
        )
      : saved[1].copyWith(
          backend: (saved[1].backend as NativeAgentBackendView).copyWith(
            status: ThreadStatusView.closed,
          ),
        );
  final other = saved[2];
  transport.rowOverrides.addAll({
    saved[0].threadId: root,
    saved[1].threadId: child,
  });
  transport.child = child;
  final graph = AppGraph(
    statisticsFeed: const TestStatisticsFeedPort(),
    transport: transport,
    clientId: 'cold-agent-selection',
  );
  addTearDown(
    () => graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
  );
  StudioAgentView agent(SessionDirectoryRow row, {String? parentAgentId}) =>
      StudioAgentView(
        agentId: row.agentId,
        sessionId: row.sessionId,
        parentAgentId: parentAgentId,
        threadId: row.threadId,
        role: row.role,
        task: row.title,
        delegationMode: row.delegationMode,
        delegationPreference: row.delegationPreference,
        frozenModel: row.frozenModel,
        state:
            row.backend is NativeAgentBackendView &&
                (row.backend as NativeAgentBackendView).status ==
                    ThreadStatusView.closed
            ? const ClosedStudioAgent()
            : const IdleStudioAgent(),
        updatedAt: row.updatedAt,
      );
  final agents = [
    agent(root),
    agent(child, parentAgentId: root.agentId),
    agent(other),
    StudioAgentView(
      agentId: 'cold-sibling',
      sessionId: root.sessionId,
      parentAgentId: root.agentId,
      threadId: 'cold-sibling',
      role: 'executor',
      task: 'Another cold member',
      state: const IdleStudioAgent(),
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      updatedAt: root.updatedAt,
    ),
  ];
  graph.client.project.applyProjectDirectory(
    ProjectDirectoryState(
      revision: 1,
      values: [
        StudioProject(
          id: root.workspaceId,
          name: 'Saved project',
          path: root.workspacePath,
        ),
        const StudioProject(
          id: 'foreign-project',
          name: 'Foreign project',
          path: '/foreign',
        ),
      ],
    ),
  );
  graph.client.project.applyAgentDirectory(
    AgentDirectoryState(revision: 1, values: agents),
  );
  graph.client.selection.restoreStartup(
    workspaceId: root.workspaceId,
    threadId: root.threadId,
    needsOpen: true,
  );
  final initialThread = graph.client.threadDirectory.observeThread(
    root.threadId,
  );
  await initialThread.state
      .waitFor((state) => state.frame?.row != null)
      .timeout(const Duration(seconds: 5));
  addTearDown(initialThread.release);
  // Startup's actual root metadata read is established before per-action
  // transport reads are measured by these tests.
  transport.metadataReads.clear();
  return _ColdFixture(
    graph: graph,
    transport: transport,
    root: root,
    child: child,
    other: other,
    agents: agents,
  );
}

class _ColdFixture {
  const _ColdFixture({
    required this.graph,
    required this.transport,
    required this.root,
    required this.child,
    required this.other,
    required this.agents,
  });
  final AppGraph graph;
  final _ColdSelectionTransport transport;
  final SessionDirectoryRow root;
  final SessionDirectoryRow child;
  final SessionDirectoryRow other;
  final List<StudioAgentView> agents;
}

// Only the external metadata response and a saved closed-state frame are
// scripted; membership, selection, overlays and content ownership use Client.
final class _ColdSelectionTransport extends RecordingDemoTransport {
  late SessionDirectoryRow child;
  final metadataReads = <String>[];
  final stateReads = <String>[];
  final savedThreadOverrides = <String, SessionDirectoryRow>{};
  String? frameThreadIdOverride;
  Future<SessionDirectoryRow> Function(String)? respond;
  Future<void> Function(String)? onActivate;
  Stream<NewThreadStartEvent>? newThreadEvents;
  final newThreadEntered = Completer<void>();
  var submitCalls = 0;
  var restoreCalls = 0;

  int _metadataRevision = 0;
  final rowOverrides = <String, SessionDirectoryRow>{};

  Future<List<SessionDirectoryRow>> savedThreads() async {
    final rows = (await super.readBootstrap()).threadDirectory.rows;
    return [
      for (final id in ['thread-main', 'thread-reviewer', 'thread-alt'])
        rowOverrides[id] ?? rows.singleWhere((row) => row.threadId == id),
    ];
  }

  @override
  Future<ThreadObservationHandle> openThreadObservation(String threadId) async {
    metadataReads.add(threadId);
    final override = savedThreadOverrides[threadId];
    final response =
        respond?.call(threadId) ??
        (override != null
            ? Future.value(override)
            : threadId == child.threadId
            ? Future.value(child)
            : savedThreads().then(
                (rows) => rows.singleWhere((row) => row.threadId == threadId),
              ));
    final frameThreadId = frameThreadIdOverride ?? threadId;
    frameThreadIdOverride = null;
    return _ColdThreadObservation(
      threadId: frameThreadId,
      revision: ++_metadataRevision,
      response: response,
    );
  }

  @override
  Future<void> activateProject(String workspaceId) =>
      onActivate?.call(workspaceId) ?? super.activateProject(workspaceId);

  @override
  Stream<NewThreadStartEvent> startNewThread(
    String workspaceId,
    StudioPromptInput input,
    ThreadModeId mode, {
    required ModeModelRouteView route,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    String? workspaceMode,
  }) {
    newThreadEntered.complete();
    return newThreadEvents ?? (throw StateError('Unexpected creation request'));
  }

  @override
  Future<TimelineReader> openTimelineReader(
    String threadId, {
    required int presentationVersion,
    required int readerProtocolVersion,
    required ReadDemand demand,
  }) async {
    stateReads.add(threadId);
    return super.openTimelineReader(
      threadId,
      presentationVersion: presentationVersion,
      readerProtocolVersion: timelineReaderProtocolVersion,
      demand: demand,
    );
  }

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) async {
    submitCalls++;
    throw StateError('Selecting saved history must not submit input');
  }

  @override
  Future<SessionDirectoryRow> restoreThread(String threadId) async {
    restoreCalls++;
    throw StateError('Selecting saved history must not restore execution');
  }
}

final class _ColdThreadObservation implements ThreadObservationHandle {
  _ColdThreadObservation({
    required this.threadId,
    required this.revision,
    required this.response,
  }) {
    response.then(
      (row) => _publish(
        ThreadMetadataFrame(
          threadId: threadId,
          stamp: ResourceStamp(
            resourceKey: 'thread-directory',
            ownerEpoch: 'cold-selection',
            revision: revision,
          ),
          row: row,
        ),
      ),
      onError: (Object error, StackTrace stackTrace) =>
          _publishError(error, stackTrace),
    );
  }

  final String threadId;
  final int revision;
  final Future<SessionDirectoryRow> response;
  Completer<ThreadMetadataFrame?>? _waiting;
  ThreadMetadataFrame? _queuedFrame;
  Object? _queuedError;
  StackTrace? _queuedStackTrace;
  bool _hasQueuedResult = false;
  bool _closed = false;

  @override
  Future<ThreadMetadataFrame?> next() {
    if (_closed) return Future.value(null);
    if (_hasQueuedResult) {
      _hasQueuedResult = false;
      final error = _queuedError;
      if (error != null) {
        final stackTrace = _queuedStackTrace!;
        _queuedError = null;
        _queuedStackTrace = null;
        return Future.error(error, stackTrace);
      }
      final frame = _queuedFrame;
      _queuedFrame = null;
      return Future.value(frame);
    }
    return (_waiting = Completer<ThreadMetadataFrame?>()).future;
  }

  void _publish(ThreadMetadataFrame frame) {
    if (_closed) return;
    final waiting = _waiting;
    if (waiting != null) {
      _waiting = null;
      waiting.complete(frame);
    } else {
      _queuedFrame = frame;
      _hasQueuedResult = true;
    }
  }

  void _publishError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    final waiting = _waiting;
    if (waiting != null) {
      _waiting = null;
      waiting.completeError(error, stackTrace);
    } else {
      _queuedError = error;
      _queuedStackTrace = stackTrace;
      _hasQueuedResult = true;
    }
  }

  @override
  void requestClose() {
    _closed = true;
    _hasQueuedResult = false;
    _queuedFrame = null;
    _queuedError = null;
    _queuedStackTrace = null;
    _waiting?.complete();
    _waiting = null;
  }

  @override
  Future<void> close() async => requestClose();
}
