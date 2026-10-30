import 'support/mapped_conversation_feed.dart';

import 'support/test_statistics_feed.dart';

import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit cold selection reads only its metadata and opens only its history', () async {
    final fixture = await _fixture();
    final client = fixture.graph.client;
    // A member of another root is not a target of the current root's menu.
    await client.directoryCommands.selectAgentThread(fixture.other.id);
    expect(fixture.transport.metadataReads, isEmpty);
    expect(client.conversations.sessionStates, isEmpty);

    await client.directoryCommands.selectAgentThread(fixture.child.id);
    await _expectSelectedHistory(fixture);
  });

  test(
    'restored cold selection stays unopened until its explicit open command',
    () async {
      final fixture = await _fixture();
      final client = fixture.graph.client;
      client.selection.restoreStartup(
        workspaceId: fixture.root.workspaceId,
        threadId: fixture.child.id,
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
    final wrongProject = StudioThread(
      id: fixture.child.id,
      workspaceId: 'foreign-project',
      title: fixture.child.title,
      mode: fixture.child.mode,
      delegationMode: fixture.child.delegationMode,
      delegationPreference: fixture.child.delegationPreference,
      parentThreadId: fixture.root.id,
      rootThreadId: fixture.root.id,
      workspacePath: '/foreign',
      updatedAt: fixture.child.updatedAt,
    );
    for (final response in [
      fixture.other,
      fixture.child.copyWith(rootThreadId: fixture.other.id),
      wrongProject,
    ]) {
      fixture.transport.respond = (_) async => response;
      await expectLater(
        client.directoryCommands.selectAgentThread(fixture.child.id),
        throwsA(
          isA<StudioFailure>().having(
            (error) => error.code,
            'code',
            StudioFailureCode.protocol,
          ),
        ),
      );
      expect(client.selection.state.selectedThreadId, fixture.root.id);
      expect(client.threadDirectory.state.overlayThreads, isEmpty);
      expect(client.conversations.sessionStates, isEmpty);
    }
    fixture.transport.respond = (_) async =>
        throw StateError('saved metadata unavailable');
    await expectLater(
      client.directoryCommands.selectAgentThread(fixture.child.id),
      throwsStateError,
    );
    expect(client.selection.state.selectedThreadId, fixture.root.id);
    expect(client.threadDirectory.state.overlayThreads, isEmpty);
    expect(client.threadDirectory.state.revision, 7);
    expect(fixture.transport.stateReads, isEmpty);
    expect(fixture.transport.feeds, isEmpty);
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
        final reply = Completer<StudioThread>();
        fixture.transport.respond = (_) {
          entered.complete();
          return reply.future;
        };
        final pending = client.directoryCommands.selectAgentThread(
          fixture.child.id,
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
              threadId: fixture.other.id,
              needsOpen: true,
            );
          case 'project':
            client.selection.selectProject('foreign-project');
          case 'membership':
            client.project.applyAgentDirectory(
              AgentDirectoryState(
                revision: 2,
                values: fixture.agents
                    .where((agent) => agent.threadId != fixture.child.id)
                    .toList(),
              ),
            );
        }
        final newerSelection = client.selection.state;
        reply.complete(fixture.child);
        await pending;
        expect(client.selection.state, newerSelection, reason: invalidation);
        expect(
          client.threadDirectory.state.overlayThreads,
          isEmpty,
          reason: invalidation,
        );
        expect(
          client.conversations.sessionStates,
          isEmpty,
          reason: invalidation,
        );
        expect(fixture.transport.metadataReads, [fixture.child.id]);
        expect(fixture.transport.stateReads, isEmpty, reason: invalidation);
        expect(fixture.transport.feeds, isEmpty, reason: invalidation);
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
      final reply = Completer<StudioThread>();
      fixture.transport.respond = (_) {
        entered.complete();
        return reply.future;
      };
      final oldNavigation = _outcome(
        client.directoryCommands.selectAgentThread(fixture.child.id),
      );
      addTearDown(() async {
        if (!reply.isCompleted) reply.complete(fixture.child);
        await oldNavigation;
      });
      await entered.future;
      final commands = client.directoryCommands;
      final next = _outcome(switch (action) {
        'root' => commands.selectThread(fixture.other.id),
        'project' => commands.selectProject(fixture.root.workspaceId),
        'project-failure' => commands.selectProject('foreign-project'),
        'new-session' => commands.beginNewThread(),
        'startup-open' => commands.openSelectedThread(),
        'restore-failure' => commands.restoreThread(fixture.root.id),
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
      expect(client.findThread(fixture.child.id), isNull, reason: action);
      expect(
        client.conversations.existingSession(fixture.child.id),
        isNull,
        reason: action,
      );
      expect(
        client.selection.state.selectedThreadId,
        isNot(fixture.child.id),
        reason: action,
      );
      expect(
        fixture.transport.stateReads,
        isNot(contains(fixture.child.id)),
        reason: action,
      );
      expect(
        fixture.transport.feeds.map((timeline) => timeline.threadId),
        isNot(contains(fixture.child.id)),
        reason: action,
      );
      expect(fixture.transport.metadataReads, [
        fixture.child.id,
      ], reason: action);
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
      final newer = client.directoryCommands.selectThread(fixture.other.id);
      activation.complete();
      expect(await draftNavigation, isNull);
      await newer;
      fixture.graph.setConversationPageVisible(true);
      await client.conversations.session(fixture.other.id).content.ready;
      expect(client.selection.state.selectedProjectId, fixture.other.workspaceId);
      expect(client.selection.state.selectedThreadId, fixture.other.id);
      expect(
        client.conversations.sessionStates.map((state) => state.threadId),
        [fixture.other.id],
      );
      expect(fixture.transport.stateReads, [fixture.other.id]);
    },
  );

  test('new Thread creation and directory reads share the latest navigation boundary', () async {
    final fixture = await _fixture();
    final sibling = _secondColdChild(fixture);
    final client = fixture.graph.client;
    final oldEntered = Completer<void>();
    final oldReply = Completer<StudioThread>();
    final newEntered = Completer<void>();
    final newReply = Completer<StudioThread>();
    fixture.transport.respond = (id) {
      if (id == fixture.child.id) {
        oldEntered.complete();
        return oldReply.future;
      }
      newEntered.complete();
      return newReply.future;
    };
    final creation = StreamController<NewThreadStartEvent>();
    fixture.transport.newThreadEvents = creation.stream;
    final oldNavigation = _outcome(
      client.directoryCommands.selectAgentThread(fixture.child.id),
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
    expect(client.threadDirectory.state.overlayThreads, isEmpty);
    expect(client.conversations.sessionStates, isEmpty);

    final newer = client.directoryCommands.selectAgentThread(sibling.id);
    await newEntered.future;
    // Creation is a real accepted operation, but its automatic navigation is
    // obsolete even though the newer metadata read has not changed selection.
    final result = StartNewThreadResult(
      thread: fixture.root,
      receipt: SubmitPromptReceipt(
        threadId: fixture.root.id,
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
    fixture.graph.setConversationPageVisible(true);
    await client.conversations.session(sibling.id).content.ready;
    expect(client.selection.state.selectedThreadId, sibling.id);
    expect(client.conversations.sessionStates.map((state) => state.threadId), [
      sibling.id,
    ]);
    expect(fixture.transport.stateReads, [sibling.id]);
    expect(client.findThread(fixture.child.id), isNull);
  });

  test('the agent directory publishes each row execution and stop qualification, and a stale page cannot replace it', () async {
    final fixture = await _fixture();
    final client = fixture.graph.client;
    final row = fixture.agents.firstWhere(
      (agent) => agent.threadId == fixture.child.id,
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
              if (agent.threadId == fixture.child.id)
                StudioAgentView(
                  id: agent.id,
                  threadId: agent.threadId,
                  path: agent.path,
                  parentPath: agent.parentPath,
                  rootThreadId: agent.rootThreadId,
                  depth: agent.depth,
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
      (agent) => agent.threadId == fixture.child.id,
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
              if (agent.threadId == fixture.child.id)
                StudioAgentView(
                  id: agent.id,
                  threadId: agent.threadId,
                  path: agent.path,
                  parentPath: agent.parentPath,
                  rootThreadId: agent.rootThreadId,
                  depth: agent.depth,
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
          .firstWhere((agent) => agent.threadId == fixture.child.id)
          .execution,
      execution,
    );
    expect(
      client.project.state.agents!.values
          .firstWhere((agent) => agent.threadId == fixture.child.id)
          .canStop,
      isTrue,
    );
    expect(
      client.project.state.agents!.values
          .firstWhere((agent) => agent.threadId == fixture.child.id)
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
              if (agent.threadId == fixture.child.id)
                StudioAgentView(
                  id: agent.id,
                  threadId: agent.threadId,
                  path: agent.path,
                  parentPath: agent.parentPath,
                  rootThreadId: agent.rootThreadId,
                  depth: agent.depth,
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
      (agent) => agent.threadId == fixture.child.id,
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
    expect(client.selection.state.selectedThreadId, fixture.root.id);
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
  final oldReply = Completer<StudioThread>();
  final newReply = Completer<StudioThread>();
  final oldError = StateError('superseded metadata read failed');
  final newError = StateError('latest metadata read failed');
  fixture.transport.respond = (id) {
    if (id == fixture.child.id) {
      oldEntered.complete();
      return oldReply.future;
    }
    if (id == sibling.id) {
      newEntered.complete();
      return newReply.future;
    }
    throw StateError('Unexpected metadata read: $id');
  };
  final oldNavigation = _outcome(
    client.directoryCommands.selectAgentThread(fixture.child.id),
  );
  await oldEntered.future;
  // This is the same public command used by the real menu, not a store write.
  final newNavigation = _outcome(
    client.directoryCommands.selectAgentThread(sibling.id),
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
  expect(client.selection.state.selectedThreadId, fixture.root.id);
  expect(
    client.threadDirectory.state.overlayThreads,
    isEmpty,
    reason: 'An old read must not publish while the new command is still queued/reading',
  );
  expect(client.conversations.sessionStates, isEmpty);
  expect(fixture.transport.stateReads, isEmpty);
  expect(fixture.transport.feeds, isEmpty);
  if (newFails) {
    newReply.completeError(newError);
    expect(await newNavigation, same(newError));
    expect(client.selection.state.selectedThreadId, fixture.root.id);
    expect(client.threadDirectory.state.overlayThreads, isEmpty);
    expect(client.conversations.sessionStates, isEmpty);
    expect(fixture.transport.stateReads, isEmpty);
    expect(fixture.transport.feeds, isEmpty);
  } else {
    newReply.complete(sibling);
    expect(await newNavigation, isNull);
    fixture.graph.setConversationPageVisible(true);
    final session = client.conversations.existingSession(sibling.id)!;
    await session.source.waitFor((state) => state.workspace != null);
    await session.content.state.waitFor(
      (state) => state.snapshot is ConversationBaselineFrame,
    );
    expect(client.selection.state.selectedThreadId, sibling.id);
    expect(
      client.threadDirectory.state.overlayThreads.map((thread) => thread.id),
      [sibling.id],
    );
    expect(client.conversations.sessionStates.map((state) => state.threadId), [
      sibling.id,
    ]);
    expect(fixture.transport.stateReads, [sibling.id]);
    expect(fixture.transport.feeds.map((timeline) => timeline.threadId), [
      sibling.id,
    ]);
  }
  expect(client.findThread(fixture.child.id), isNull);
  expect(client.conversations.existingSession(fixture.child.id), isNull);
  expect(fixture.transport.metadataReads, [fixture.child.id, sibling.id]);
  expect(fixture.transport.submitCalls, 0);
  expect(fixture.transport.restoreCalls, 0);
}

// Reuse a second real Demo history as the external saved sibling fixture.
// Client remains responsible for canonical membership, reads and navigation.
StudioThread _secondColdChild(_ColdFixture fixture) {
  final sibling = fixture.other.copyWith(
    parentThreadId: fixture.root.id,
    rootThreadId: fixture.root.id,
    agentPath: 'opaque-sibling-path',
    role: 'executor',
  );
  fixture.transport.savedThreadOverrides[sibling.id] = sibling;
  fixture.graph.client.threadDirectory.applyDelta(
    revision: 8,
    upserted: const [],
    removed: [sibling.id],
  );
  fixture.graph.client.project.applyAgentDirectory(
    AgentDirectoryState(
      revision: 2,
      values: [
        ...fixture.agents.where((agent) => agent.threadId != sibling.id),
        StudioAgentView(
          id: sibling.id,
          threadId: sibling.id,
          path: sibling.agentPath,
          parentPath: fixture.root.agentPath,
          rootThreadId: fixture.root.id,
          depth: 1,
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
  expect(fixture.transport.feeds, isEmpty, reason: '选择身份本身不产生 GUI 内容需求');
  fixture.graph.setConversationPageVisible(true);
  final session = client.conversations.existingSession(fixture.child.id)!;
  await session.source.waitFor((state) => state.workspace != null);
  await session.content.state.waitFor(
    (state) => state.snapshot is ConversationBaselineFrame,
  );
  expect(client.selection.state.selectedThreadId, fixture.child.id);
  expect(client.selection.state.needsOpen, isFalse);
  expect(client.findThread(fixture.child.id)?.status, ThreadStatusView.closed);
  expect(
    client.threadDirectory.state.window.threads.map((thread) => thread.id),
    [fixture.root.id, fixture.other.id],
  );
  expect(
    client.threadDirectory.state.overlayThreads.map((thread) => thread.id),
    [fixture.child.id],
  );
  expect(
    client.threadDirectory.state.revision,
    7,
    reason: 'A one-member metadata read does not advance the paged directory watermark',
  );
  expect(client.conversations.sessionStates.map((state) => state.threadId), [
    fixture.child.id,
  ]);
  expect(fixture.transport.metadataReads, [fixture.child.id]);
  expect(fixture.transport.stateReads, [fixture.child.id]);
  expect(fixture.transport.feeds.map((timeline) => timeline.threadId), [
    fixture.child.id,
  ]);
  expect(fixture.transport.submitCalls, 0);
  expect(fixture.transport.restoreCalls, 0);
}

Future<_ColdFixture> _fixture() async {
  final transport = _ColdSelectionTransport();
  final saved = await transport.savedThreads();
  final root = saved[0];
  final child = saved[1].copyWith(status: ThreadStatusView.closed);
  final other = saved[2];
  transport.child = child;
  final graph = AppGraph(
    statisticsFeed: const TestStatisticsFeedPort(),
    transport: transport,
    clientId: 'cold-agent-selection',
  );
  addTearDown(
    () => graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
  );
  StudioAgentView agent(StudioThread thread, {String? parent, int depth = 0}) =>
      StudioAgentView(
        id: thread.id,
        threadId: thread.id,
        path: thread.agentPath,
        parentPath: parent,
        rootThreadId: thread.effectiveRootThreadId,
        depth: depth,
        role: thread.role,
        task: thread.title,
        delegationMode: thread.delegationMode,
        delegationPreference: thread.delegationPreference,
        frozenModel: thread.frozenModel,
        state: thread.status == ThreadStatusView.closed
            ? const ClosedStudioAgent()
            : const IdleStudioAgent(),
        updatedAt: thread.updatedAt,
      );
  final agents = [
    agent(root),
    agent(child, parent: root.agentPath, depth: 1),
    agent(other),
    StudioAgentView(
      id: 'cold-sibling',
      threadId: 'cold-sibling',
      path: 'opaque-sibling',
      parentPath: root.agentPath,
      rootThreadId: root.id,
      depth: 1,
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
  graph.client.threadDirectory.applyWindow(
    ThreadDirectoryWindow(threads: [root, other], revision: 7),
  );
  graph.client.selection.restoreStartup(
    workspaceId: root.workspaceId,
    threadId: root.id,
    needsOpen: true,
  );
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
  final StudioThread root;
  final StudioThread child;
  final StudioThread other;
  final List<StudioAgentView> agents;
}

// Only the external metadata response and a saved closed-state frame are
// scripted; membership, selection, overlays and content ownership use Client.
final class _ColdSelectionTransport extends RecordingDemoTransport {
  late StudioThread child;
  final metadataReads = <String>[];
  final stateReads = <String>[];
  final savedThreadOverrides = <String, StudioThread>{};
  Future<StudioThread> Function(String)? respond;
  Future<void> Function(String)? onActivate;
  Stream<NewThreadStartEvent>? newThreadEvents;
  final newThreadEntered = Completer<void>();
  var submitCalls = 0;
  var restoreCalls = 0;

  Future<List<StudioThread>> savedThreads() async => [
    await super.readThread('thread-main'),
    await super.readThread('thread-reviewer'),
    await super.readThread('thread-alt'),
  ];

  @override
  Future<StudioThread> readThread(String threadId) {
    metadataReads.add(threadId);
    return respond?.call(threadId) ?? Future.value(child);
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
  Future<ConversationFeed> openConversationFeed(String threadId) async {
    stateReads.add(threadId);
    final saved =
        savedThreadOverrides[threadId] ?? (threadId == child.id ? child : null);
    return MappedConversationFeed(
      await super.openConversationFeed(threadId),
      (frame) => switch (frame) {
        ThreadSnapshotFrame(:final workspace) when saved != null =>
          ThreadSnapshotFrame(workspace: workspace.copyWith(thread: saved)),
        _ => frame,
      },
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
  Future<StudioThread> restoreThread(String threadId) async {
    restoreCalls++;
    throw StateError('Selecting saved history must not restore execution');
  }
}
